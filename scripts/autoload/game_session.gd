extends Node

const DEFAULT_SYSTEM_PATH := "res://data/galaxy_systems/sol_system.tres"
const START_SYSTEM_ID: String = "sol"
const START_DOCK_BODY_ID: String = "earth"

const SCAN_UNKNOWN := "unknown"
const SCAN_BASIC := "basic"
const SCAN_DEEP := "deep"
const SCAN_SPECIAL := "special"

const SCANNER_BASIC := "basic"
const SCANNER_DEEP := "deep"
const SCANNER_SPECIAL := "special"

var current_system_definition: SystemDefinition = null
var selected_system_definition: SystemDefinition = null
var current_system_id: String = ""

var system_states: Dictionary = {}
var object_scan_states: Dictionary = {}
var object_resource_states: Dictionary = {}
var object_mining_cooldowns: Dictionary = {}

var entering_system_from_travel: bool = false
var active_scanner_tier: String = SCANNER_BASIC

# MVP Cargo / Inventar
var ship_cargo_capacity: int = 100
var ship_cargo: Dictionary = {}

var ship_max_fuel: float = 100.0
var ship_fuel: float = 100.0


func _ready() -> void:
	ensure_default_system_loaded()
	_ensure_default_bases()


func ensure_boot_state() -> void:
	if current_system_id.is_empty():
		current_system_id = START_SYSTEM_ID

	if current_system_definition == null:
		current_system_definition = load(DEFAULT_SYSTEM_PATH) as SystemDefinition

	var state: ShipRuntimeState = get_or_create_ship_state(current_system_id)
	if state == null:
		return

	var is_uninitialized: bool = state.docked_body_id.is_empty() and state.free_position == Vector2.ZERO
	if is_uninitialized:
		state.is_docked = true
		state.docked_body_id = START_DOCK_BODY_ID
		state.last_selected_object_id = START_DOCK_BODY_ID

	_ensure_default_bases()


func ensure_default_system_loaded() -> void:
	if current_system_definition != null:
		return

	var default_system := load(DEFAULT_SYSTEM_PATH) as SystemDefinition
	if default_system == null:
		push_error("Default-System konnte nicht geladen werden: %s" % DEFAULT_SYSTEM_PATH)
		return

	set_current_system(default_system)


func set_current_system(system_definition: SystemDefinition) -> void:
	if system_definition == null:
		return

	current_system_definition = system_definition
	current_system_id = system_definition.id


func stage_system_entry(system_definition: SystemDefinition, from_travel: bool) -> void:
	selected_system_definition = system_definition
	entering_system_from_travel = from_travel


func consume_selected_system_definition() -> SystemDefinition:
	var result := selected_system_definition
	selected_system_definition = null
	return result


func consume_travel_entry_flag() -> bool:
	var result := entering_system_from_travel
	entering_system_from_travel = false
	return result


func get_or_create_ship_state(system_id: String) -> ShipRuntimeState:
	if system_id.is_empty():
		return null

	var existing: Variant = system_states.get(system_id)
	if existing is ShipRuntimeState:
		return existing as ShipRuntimeState

	var state: ShipRuntimeState = ShipRuntimeState.new()
	system_states[system_id] = state
	return state


func get_ship_state(system_id: String) -> ShipRuntimeState:
	var existing: Variant = system_states.get(system_id)
	if existing is ShipRuntimeState:
		return existing as ShipRuntimeState
	return null


func can_leave_current_system() -> bool:
	if current_system_id.is_empty():
		return true

	var state := get_ship_state(current_system_id)
	if state == null:
		return true

	return not state.is_docked


func set_object_scan_state(system_id: String, object_id: String, scan_state: String) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not object_scan_states.has(system_id):
		object_scan_states[system_id] = {}

	var system_scan_state: Dictionary = object_scan_states[system_id]
	system_scan_state[object_id] = scan_state
	object_scan_states[system_id] = system_scan_state


func get_object_scan_state(system_id: String, object_id: String) -> String:
	if system_id.is_empty() or object_id.is_empty():
		return SCAN_UNKNOWN

	var system_scan_state = object_scan_states.get(system_id, {})
	if system_scan_state is Dictionary:
		return str(system_scan_state.get(object_id, SCAN_UNKNOWN))

	return SCAN_UNKNOWN


func get_active_scanner_tier() -> String:
	return active_scanner_tier


func set_active_scanner_tier(scanner_tier: String) -> void:
	match scanner_tier:
		SCANNER_BASIC, SCANNER_DEEP, SCANNER_SPECIAL:
			active_scanner_tier = scanner_tier
		_:
			push_warning("Unbekannte Scanner-Stufe: %s" % scanner_tier)


func scanner_supports_resource_tier(resource_tier: String) -> bool:
	return _scanner_tier_rank(active_scanner_tier) >= _scanner_tier_rank(resource_tier)


func can_scan_to_next_state(current_scan_state: String) -> bool:
	var next_state: String = get_next_scan_state(current_scan_state)
	if next_state == current_scan_state:
		return false

	return scanner_supports_scan_state(next_state)


func scanner_supports_scan_state(scan_state: String) -> bool:
	match scan_state:
		SCAN_BASIC:
			return _scanner_tier_rank(active_scanner_tier) >= _scanner_tier_rank(SCANNER_BASIC)
		SCAN_DEEP:
			return _scanner_tier_rank(active_scanner_tier) >= _scanner_tier_rank(SCANNER_DEEP)
		SCAN_SPECIAL:
			return _scanner_tier_rank(active_scanner_tier) >= _scanner_tier_rank(SCANNER_SPECIAL)
		_:
			return false


func get_next_scan_state(current_scan_state: String) -> String:
	match current_scan_state:
		SCAN_UNKNOWN:
			return SCAN_BASIC
		SCAN_BASIC:
			return SCAN_DEEP
		SCAN_DEEP:
			return SCAN_SPECIAL
		SCAN_SPECIAL:
			return SCAN_SPECIAL
		_:
			return SCAN_BASIC


func advance_object_scan_state(system_id: String, object_id: String) -> bool:
	var current_state: String = get_object_scan_state(system_id, object_id)
	var next_state: String = get_next_scan_state(current_state)

	if next_state == current_state:
		return false

	if not scanner_supports_scan_state(next_state):
		return false

	set_object_scan_state(system_id, object_id, next_state)
	return true


# --------------------------------------------------
# Cargo / Inventar
# --------------------------------------------------

func get_cargo_capacity() -> int:
	return ship_cargo_capacity


func set_cargo_capacity(new_capacity: int) -> void:
	ship_cargo_capacity = max(new_capacity, 0)


func get_cargo_items() -> Dictionary:
	return ship_cargo.duplicate(true)


func clear_cargo() -> void:
	ship_cargo.clear()


func get_cargo_used() -> int:
	var used: int = 0

	for value in ship_cargo.values():
		used += int(value)

	return used


func get_cargo_free_space() -> int:
	return max(ship_cargo_capacity - get_cargo_used(), 0)


func has_cargo_space() -> bool:
	return get_cargo_free_space() > 0


func add_cargo_item(resource_id: String, amount: int) -> int:
	if resource_id.is_empty():
		return 0

	if amount <= 0:
		return 0

	var free_space: int = get_cargo_free_space()
	if free_space <= 0:
		return 0

	var accepted_amount: int = min(amount, free_space)
	var current_amount: int = int(ship_cargo.get(resource_id, 0))
	ship_cargo[resource_id] = current_amount + accepted_amount
	return accepted_amount


func get_cargo_summary_text() -> String:
	return "Cargo: %d / %d" % [get_cargo_used(), ship_cargo_capacity]


func get_max_fuel() -> float:
	return ship_max_fuel


func get_fuel() -> float:
	return ship_fuel


func set_max_fuel(value: float, refill: bool = false) -> void:
	ship_max_fuel = maxf(value, 0.0)
	if refill:
		ship_fuel = ship_max_fuel
	else:
		ship_fuel = clampf(ship_fuel, 0.0, ship_max_fuel)


func set_fuel(value: float) -> void:
	ship_fuel = clampf(value, 0.0, ship_max_fuel)


func has_fuel(minimum_amount: float = 0.01) -> bool:
	return ship_fuel >= minimum_amount


func add_fuel(amount: float) -> float:
	if amount <= 0.0:
		return 0.0

	var before: float = ship_fuel
	ship_fuel = clampf(ship_fuel + amount, 0.0, ship_max_fuel)
	return ship_fuel - before


func consume_fuel(amount: float) -> bool:
	if amount <= 0.0:
		return true

	if ship_fuel < amount:
		return false

	ship_fuel = maxf(ship_fuel - amount, 0.0)
	return true


# --------------------------------------------------
# Mining Runtime / Object Resources
# --------------------------------------------------

func ensure_object_resource_runtime(system_id: String, object_id: String, resource_ids: Array[String]) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not object_resource_states.has(system_id):
		object_resource_states[system_id] = {}

	var system_resources: Dictionary = object_resource_states.get(system_id, {})
	var object_resources: Dictionary = system_resources.get(object_id, {})

	for resource_id in resource_ids:
		if resource_id.is_empty():
			continue
		if object_resources.has(resource_id):
			continue
		object_resources[resource_id] = _get_default_resource_amount(resource_id)

	system_resources[object_id] = object_resources
	object_resource_states[system_id] = system_resources


func get_object_resource_amount(system_id: String, object_id: String, resource_id: String) -> int:
	var object_resources: Dictionary = _get_object_resource_dictionary(system_id, object_id)
	return int(object_resources.get(resource_id, 0))


func consume_object_resource(system_id: String, object_id: String, resource_id: String, requested_amount: int) -> int:
	if system_id.is_empty() or object_id.is_empty() or resource_id.is_empty():
		return 0
	if requested_amount <= 0:
		return 0

	var system_resources: Dictionary = object_resource_states.get(system_id, {})
	var object_resources: Dictionary = system_resources.get(object_id, {})
	var available_amount: int = int(object_resources.get(resource_id, 0))
	if available_amount <= 0:
		return 0

	var consumed_amount: int = mini(requested_amount, available_amount)
	object_resources[resource_id] = available_amount - consumed_amount
	system_resources[object_id] = object_resources
	object_resource_states[system_id] = system_resources
	return consumed_amount


func is_object_depleted(system_id: String, object_id: String, resource_ids: Array[String]) -> bool:
	if system_id.is_empty() or object_id.is_empty():
		return true
	if resource_ids.is_empty():
		return true

	var object_resources: Dictionary = _get_object_resource_dictionary(system_id, object_id)
	for resource_id in resource_ids:
		if int(object_resources.get(resource_id, 0)) > 0:
			return false
	return true


func get_object_mining_cooldown_remaining(system_id: String, object_id: String) -> float:
	if system_id.is_empty() or object_id.is_empty():
		return 0.0
	var system_cooldowns: Dictionary = object_mining_cooldowns.get(system_id, {})
	return maxf(float(system_cooldowns.get(object_id, 0.0)), 0.0)


func set_object_mining_cooldown_remaining(system_id: String, object_id: String, remaining_seconds: float) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return
	if not object_mining_cooldowns.has(system_id):
		object_mining_cooldowns[system_id] = {}

	var system_cooldowns: Dictionary = object_mining_cooldowns.get(system_id, {})
	if remaining_seconds <= 0.0:
		system_cooldowns.erase(object_id)
	else:
		system_cooldowns[object_id] = remaining_seconds

	object_mining_cooldowns[system_id] = system_cooldowns


func tick_mining_cooldowns(delta: float) -> void:
	if delta <= 0.0:
		return

	var systems_to_clear: Array[String] = []
	for system_key in object_mining_cooldowns.keys():
		var system_id: String = str(system_key)
		var system_cooldowns: Dictionary = object_mining_cooldowns.get(system_id, {})
		var object_ids: Array = system_cooldowns.keys()
		for object_key in object_ids:
			var object_id: String = str(object_key)
			var remaining: float = maxf(float(system_cooldowns.get(object_id, 0.0)) - delta, 0.0)
			if remaining <= 0.0:
				system_cooldowns.erase(object_id)
			else:
				system_cooldowns[object_id] = remaining

		if system_cooldowns.is_empty():
			systems_to_clear.append(system_id)
		else:
			object_mining_cooldowns[system_id] = system_cooldowns

	for system_id in systems_to_clear:
		object_mining_cooldowns.erase(system_id)


func _get_object_resource_dictionary(system_id: String, object_id: String) -> Dictionary:
	var system_resources: Dictionary = object_resource_states.get(system_id, {})
	var object_resources: Variant = system_resources.get(object_id, {})
	if object_resources is Dictionary:
		return (object_resources as Dictionary).duplicate(true)
	return {}


func _get_default_resource_amount(resource_id: String) -> int:
	match resource_id.to_lower():
		"stone":
			return 80
		"ice", "water":
			return 50
		"iron", "metal":
			return 35
		"titanium":
			return 18
		_:
			return 25


func _scan_state_rank(scan_state: String) -> int:
	match scan_state:
		SCAN_BASIC:
			return 1
		SCAN_DEEP:
			return 2
		SCAN_SPECIAL:
			return 3
		_:
			return 0


func _scanner_tier_rank(scanner_tier: String) -> int:
	match scanner_tier:
		SCANNER_BASIC:
			return 1
		SCANNER_DEEP:
			return 2
		SCANNER_SPECIAL:
			return 3
		_:
			return 0


# --------------------------------------------------
# Bases / Base Storage
# --------------------------------------------------
var base_states: Dictionary = {}


func _ensure_default_bases() -> void:
	_ensure_base_exists(START_SYSTEM_ID, START_DOCK_BODY_ID, "Earth Base")


func _ensure_base_exists(system_id: String, body_id: String, base_name: String) -> Dictionary:
	if system_id.is_empty() or body_id.is_empty():
		return {}

	if not base_states.has(system_id):
		base_states[system_id] = {}

	var system_bases: Dictionary = base_states.get(system_id, {})
	var base_state: Dictionary = system_bases.get(body_id, {})
	if base_state.is_empty():
		base_state = {
			"name": base_name,
			"storage": {},
		}
	elif str(base_state.get("name", "")).is_empty():
		base_state["name"] = base_name
	if not base_state.has("storage") or not (base_state.get("storage") is Dictionary):
		base_state["storage"] = {}

	system_bases[body_id] = base_state
	base_states[system_id] = system_bases
	return base_state


func has_base_on_body(system_id: String, body_id: String) -> bool:
	if system_id.is_empty() or body_id.is_empty():
		return false
	var system_bases: Dictionary = base_states.get(system_id, {})
	return system_bases.has(body_id)


func build_base_on_body(system_id: String, body_id: String, display_name: String) -> bool:
	if system_id.is_empty() or body_id.is_empty():
		return false
	if has_base_on_body(system_id, body_id):
		return false
	var base_name: String = "%s Base" % display_name if not display_name.is_empty() else "%s Base" % body_id.capitalize()
	_ensure_base_exists(system_id, body_id, base_name)
	return true


func get_base_name(system_id: String, body_id: String) -> String:
	if not has_base_on_body(system_id, body_id):
		return ""
	var system_bases: Dictionary = base_states.get(system_id, {})
	var base_state: Dictionary = system_bases.get(body_id, {})
	return str(base_state.get("name", ""))


func get_base_storage(system_id: String, body_id: String) -> Dictionary:
	if not has_base_on_body(system_id, body_id):
		return {}
	var system_bases: Dictionary = base_states.get(system_id, {})
	var base_state: Dictionary = system_bases.get(body_id, {})
	var storage: Variant = base_state.get("storage", {})
	if storage is Dictionary:
		return (storage as Dictionary).duplicate(true)
	return {}


func get_base_storage_items(system_id: String = START_SYSTEM_ID, body_id: String = START_DOCK_BODY_ID) -> Array:
	# Kompatibilität: alte UI-Skripte haben teilweise nur body_id übergeben.
	if not has_base_on_body(system_id, body_id) and not current_system_id.is_empty() and has_base_on_body(current_system_id, system_id):
		body_id = system_id
		system_id = current_system_id

	var result: Array = []
	var storage: Dictionary = get_base_storage(system_id, body_id)
	for resource_id in storage.keys():
		var amount: int = int(storage.get(resource_id, 0))
		if amount <= 0:
			continue
		result.append({
			"resource_id": str(resource_id),
			"resource_name": str(resource_id),
			"amount": amount,
		})
	return result


func get_earth_storage_items() -> Array:
	return get_base_storage_items(START_SYSTEM_ID, START_DOCK_BODY_ID)


func can_unload_ship_cargo_to_base(system_id: String, body_id: String) -> bool:
	if not has_base_on_body(system_id, body_id):
		return false
	return not ship_cargo.is_empty()


func unload_ship_cargo_to_base(system_id: String, body_id: String) -> Dictionary:
	if not can_unload_ship_cargo_to_base(system_id, body_id):
		return {}

	var base_state: Dictionary = _ensure_base_exists(system_id, body_id, get_base_name(system_id, body_id))
	var storage: Dictionary = base_state.get("storage", {})
	var unloaded: Dictionary = {}

	for resource_id in ship_cargo.keys():
		var amount: int = int(ship_cargo.get(resource_id, 0))
		if amount <= 0:
			continue
		storage[resource_id] = int(storage.get(resource_id, 0)) + amount
		unloaded[resource_id] = amount

	base_state["storage"] = storage
	var system_bases: Dictionary = base_states.get(system_id, {})
	system_bases[body_id] = base_state
	base_states[system_id] = system_bases
	clear_cargo()
	return unloaded
