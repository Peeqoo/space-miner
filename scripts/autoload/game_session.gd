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

var entering_system_from_travel: bool = false
var active_scanner_tier: String = SCANNER_BASIC

# MVP Cargo / Inventar
var ship_cargo_capacity: int = 100
var ship_cargo: Dictionary = {}

var object_resource_remaining: Dictionary = {}
var object_mining_cooldowns: Dictionary = {}


func _ready() -> void:
	ensure_default_system_loaded()


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


func ensure_object_resource_runtime(system_id: String, object_id: String, visible_resources: Array[String]) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not object_resource_remaining.has(system_id):
		object_resource_remaining[system_id] = {}

	var system_resources: Dictionary = object_resource_remaining[system_id]
	var object_resources: Dictionary = system_resources.get(object_id, {})

	for resource_id in visible_resources:
		if not object_resources.has(resource_id):
			object_resources[resource_id] = _get_default_resource_total(resource_id)

	system_resources[object_id] = object_resources
	object_resource_remaining[system_id] = system_resources


func get_object_resource_remaining(system_id: String, object_id: String, resource_id: String) -> int:
	if system_id.is_empty() or object_id.is_empty() or resource_id.is_empty():
		return 0

	var system_resources: Variant = object_resource_remaining.get(system_id, {})
	if not (system_resources is Dictionary):
		return 0

	var object_resources: Variant = (system_resources as Dictionary).get(object_id, {})
	if not (object_resources is Dictionary):
		return 0

	return int((object_resources as Dictionary).get(resource_id, 0))


func consume_object_resource(system_id: String, object_id: String, resource_id: String, amount: int) -> int:
	if amount <= 0:
		return 0

	var available: int = get_object_resource_remaining(system_id, object_id, resource_id)
	if available <= 0:
		return 0

	var consumed: int = min(available, amount)

	var system_resources: Dictionary = object_resource_remaining.get(system_id, {})
	var object_resources: Dictionary = system_resources.get(object_id, {})
	object_resources[resource_id] = max(available - consumed, 0)
	system_resources[object_id] = object_resources
	object_resource_remaining[system_id] = system_resources

	return consumed


func get_total_object_resources_remaining(system_id: String, object_id: String, visible_resources: Array[String]) -> int:
	ensure_object_resource_runtime(system_id, object_id, visible_resources)

	var total: int = 0
	for resource_id in visible_resources:
		total += get_object_resource_remaining(system_id, object_id, resource_id)

	return total


func is_object_depleted(system_id: String, object_id: String, visible_resources: Array[String]) -> bool:
	if visible_resources.is_empty():
		return true

	return get_total_object_resources_remaining(system_id, object_id, visible_resources) <= 0


func get_object_mining_cooldown_remaining(system_id: String, object_id: String) -> float:
	if system_id.is_empty() or object_id.is_empty():
		return 0.0

	var system_cooldowns: Variant = object_mining_cooldowns.get(system_id, {})
	if not (system_cooldowns is Dictionary):
		return 0.0

	return float((system_cooldowns as Dictionary).get(object_id, 0.0))


func set_object_mining_cooldown_remaining(system_id: String, object_id: String, seconds: float) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not object_mining_cooldowns.has(system_id):
		object_mining_cooldowns[system_id] = {}

	var system_cooldowns: Dictionary = object_mining_cooldowns[system_id]
	system_cooldowns[object_id] = maxf(seconds, 0.0)
	object_mining_cooldowns[system_id] = system_cooldowns


func tick_mining_cooldowns(delta: float) -> void:
	if delta <= 0.0:
		return

	for system_id in object_mining_cooldowns.keys():
		var system_cooldowns: Variant = object_mining_cooldowns.get(system_id, {})
		if not (system_cooldowns is Dictionary):
			continue

		var cooldowns: Dictionary = system_cooldowns.duplicate(true)
		for object_id in cooldowns.keys():
			var remaining: float = maxf(float(cooldowns.get(object_id, 0.0)) - delta, 0.0)
			if remaining <= 0.0:
				cooldowns.erase(object_id)
			else:
				cooldowns[object_id] = remaining

		object_mining_cooldowns[system_id] = cooldowns


func _get_default_resource_total(resource_id: String) -> int:
	match resource_id.to_lower():
		"stone":
			return 120
		"iron":
			return 35
		"water":
			return 24
		"ice":
			return 40
		"metal":
			return 48
		"titanium":
			return 18
		_:
			return 20


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
