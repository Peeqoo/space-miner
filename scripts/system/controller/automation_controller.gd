## Spawns and controls visible automated drones and mining ships.
## Uses AutomationStore through GameSession, but keeps visual scene logic local.
class_name AutomationController
extends Node

signal automation_state_changed

const DRONE_SCENE: PackedScene = preload("res://scenes/automation/drone.tscn")
const MINING_SHIP_SCENE: PackedScene = preload("res://scenes/automation/mining_ship.tscn")

const BASE_ID_EARTH: String = "earth"
const DEFAULT_SCAN_DURATION: float = 2.0
# Work duration is intentionally huge: mining completes when internal cargo fills,
# not when AutomationUnit.work_timer runs out.
const DEFAULT_MINING_DURATION: float = 999999.0
const DEFAULT_MINING_CARGO_CAPACITY: int = 20
const DEFAULT_MINING_RATE_PER_SECOND: float = 2.0
const DEFAULT_MINING_UNLOAD_DURATION: float = 2.0
const DRONE_MINING_BONUS_PER_UNIT: float = 0.02

var automation_root: Node2D
var spawner: SystemSpawner

var active_units_by_mission_id: Dictionary = {}
var idle_drones: Array[AutomationUnit] = []
var idle_mining_ships: Array[AutomationUnit] = []

var starting_units_initialized: bool = false

enum MiningShipStatus {
	TO_TARGET,
	MINING,
	TO_BASE,
	UNLOADING,
}

var mining_ship_runtime_by_unit_id: Dictionary = {}

## Coalesces automation_state_changed emits to at most once per idle frame (fewer UI rebuilds).
var _automation_state_emit_scheduled: bool = false


func setup(
	p_automation_root: Node2D,
	p_spawner: SystemSpawner
) -> void:
	automation_root = p_automation_root
	spawner = p_spawner
	set_process(true)


func ensure_starting_units() -> void:
	if starting_units_initialized:
		return

	starting_units_initialized = true

	var base_node := _get_target_node(BASE_ID_EARTH)

	if base_node == null:
		return

	# BaseStore is the source of truth for fleet counts.
	# Spawn idle visual units to match — handles both first load and scene reloads.
	var ships_to_spawn := GameSession.get_base_mining_ship_count(BASE_ID_EARTH) - idle_mining_ships.size()

	for i in ships_to_spawn:
		var unit := _spawn_unit(MINING_SHIP_SCENE)

		if unit == null:
			continue

		unit.work_duration = DEFAULT_MINING_DURATION
		unit.start_orbiting_base(base_node)
		idle_mining_ships.append(unit)

	var drones_to_spawn := GameSession.get_base_drone_count(BASE_ID_EARTH) - idle_drones.size()

	for i in drones_to_spawn:
		var unit := _spawn_unit(DRONE_SCENE)

		if unit == null:
			continue

		unit.work_duration = DEFAULT_SCAN_DURATION
		unit.start_orbiting_base(base_node)
		idle_drones.append(unit)

	if ships_to_spawn > 0 or drones_to_spawn > 0:
		_request_automation_state_changed()


func spawn_idle_drone_at_base(base_id: String = BASE_ID_EARTH) -> void:
	var base_node := _get_target_node(base_id)

	if base_node == null:
		return

	var unit := _spawn_unit(DRONE_SCENE)

	if unit == null:
		return

	unit.work_duration = DEFAULT_SCAN_DURATION
	unit.start_orbiting_base(base_node)
	idle_drones.append(unit)

	_request_automation_state_changed()


func spawn_idle_mining_ship_at_base(base_id: String = BASE_ID_EARTH) -> void:
	var base_node := _get_target_node(base_id)

	if base_node == null:
		return

	var unit := _spawn_unit(MINING_SHIP_SCENE)

	if unit == null:
		return

	unit.work_duration = DEFAULT_MINING_DURATION
	unit.start_orbiting_base(base_node)
	idle_mining_ships.append(unit)

	_request_automation_state_changed()


func launch_scan_drone(target_id: String) -> void:
	if target_id.is_empty():
		return

	var target_node := _get_target_node(target_id)

	if target_node == null:
		return

	var unit := _get_idle_drone()

	if unit == null:
		return

	var mission_id := GameSession.create_scan_mission(BASE_ID_EARTH, target_id)

	_disconnect_unit_signals(unit)

	if not unit.arrived_at_target.is_connected(_on_scan_drone_arrived_at_target):
		unit.arrived_at_target.connect(_on_scan_drone_arrived_at_target.bind(mission_id, target_id))

	active_units_by_mission_id[mission_id] = unit
	unit.start_mission_to_node(target_node)

	_request_automation_state_changed()


func launch_mining_ship(target_id: String) -> bool:
	if target_id.is_empty():
		return false

	var target_node := _get_target_node(target_id)

	if target_node == null:
		return false

	var unit := _get_idle_mining_ship()

	if unit == null:
		return false

	var system_id: String = GameSession.current_system_id
	if system_id.is_empty():
		push_error("AutomationController: Mining abgebrochen — current_system_id ist leer.")
		return false

	if GameSession.has_object_resources(system_id, target_id):
		if GameSession.is_object_depleted(system_id, target_id):
			push_warning("Cannot start mining: source depleted.")
			return false

	var resolved_resource_id: String = _pick_mining_resource_id_from_store(system_id, target_id)

	if resolved_resource_id.is_empty():
		return false

	_disconnect_unit_signals(unit)
	unit.work_duration = DEFAULT_MINING_DURATION

	if not unit.arrived_at_target.is_connected(_on_mining_ship_arrived_at_target):
		unit.arrived_at_target.connect(_on_mining_ship_arrived_at_target)

	if not unit.returned_to_base.is_connected(_on_mining_ship_returned_to_base):
		unit.returned_to_base.connect(_on_mining_ship_returned_to_base)

	mining_ship_runtime_by_unit_id[unit.get_instance_id()] = {
		"system_id": system_id,
		"base_id": BASE_ID_EARTH,
		"target_id": target_id,
		"cargo_resource_id": resolved_resource_id,
		"current_cargo": 0.0,
		"cargo_capacity": DEFAULT_MINING_CARGO_CAPACITY,
		"mining_rate_per_second": DEFAULT_MINING_RATE_PER_SECOND,
		"unload_duration": DEFAULT_MINING_UNLOAD_DURATION,
		"unload_timer": 0.0,
		"loop_active": true,
		"status": MiningShipStatus.TO_TARGET,
		"extract_remainder": 0.0,
	}

	unit.start_mission_to_node(target_node)

	_request_automation_state_changed()
	return true


func has_idle_drone() -> bool:
	return _get_idle_drone() != null


func has_idle_mining_ship() -> bool:
	return _get_idle_mining_ship() != null


func get_orbiting_drone_count(target_id: String) -> int:
	if target_id.is_empty():
		return 0

	var count := 0

	for drone in idle_drones:
		if drone == null or not is_instance_valid(drone):
			continue

		if not drone.is_available():
			continue

		if drone.base_node == null or not is_instance_valid(drone.base_node):
			continue

		if _get_object_id_from_node(drone.base_node) == target_id:
			count += 1

	return count


func get_orbiting_mining_ship_count(target_id: String) -> int:
	if target_id.is_empty():
		return 0

	var count := 0

	for ship in idle_mining_ships:
		if ship == null or not is_instance_valid(ship):
			continue

		if not ship.is_available():
			continue

		if ship.base_node == null or not is_instance_valid(ship.base_node):
			continue

		if _get_object_id_from_node(ship.base_node) == target_id:
			count += 1

	return count


func recall_one_drone_from_target(target_id: String) -> bool:
	if target_id.is_empty():
		return false

	var home_base_node := _get_target_node(BASE_ID_EARTH)

	if home_base_node == null:
		return false

	for drone in idle_drones:
		if drone == null or not is_instance_valid(drone):
			continue

		if not drone.is_available():
			continue

		if drone.base_node == null or not is_instance_valid(drone.base_node):
			continue

		if _get_object_id_from_node(drone.base_node) != target_id:
			continue

		_disconnect_unit_signals(drone)
		drone.recall_to_base(home_base_node)
		_request_automation_state_changed()
		return true

	return false


func recall_one_mining_ship_from_target(target_id: String) -> bool:
	if target_id.is_empty():
		return false

	var home_base_node := _get_target_node(BASE_ID_EARTH)

	if home_base_node == null:
		return false

	var selected_ship: AutomationUnit = null
	var selected_status: int = -1

	for ship in idle_mining_ships:
		if ship == null or not is_instance_valid(ship):
			continue

		var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(ship.get_instance_id(), {})

		if runtime.is_empty():
			continue

		if str(runtime.get("target_id", "")) != target_id:
			continue

		var status := int(runtime.get("status", MiningShipStatus.TO_TARGET))

		if selected_ship == null:
			selected_ship = ship
			selected_status = status
			continue

		if status == MiningShipStatus.MINING and selected_status != MiningShipStatus.MINING:
			selected_ship = ship
			selected_status = status

	if selected_ship == null:
		return false

	var unit_id := selected_ship.get_instance_id()
	var selected_runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})

	if selected_runtime.is_empty():
		return false

	selected_runtime["loop_active"] = false

	if selected_status == MiningShipStatus.MINING or selected_status == MiningShipStatus.TO_TARGET:
		selected_runtime["status"] = MiningShipStatus.TO_BASE
		selected_runtime["extract_remainder"] = 0.0
		selected_ship.recall_to_base(home_base_node)

	mining_ship_runtime_by_unit_id[unit_id] = selected_runtime
	_request_automation_state_changed()
	return true


func get_mining_bonus_for_target(target_id: String) -> float:
	return float(get_orbiting_drone_count(target_id)) * DRONE_MINING_BONUS_PER_UNIT


func get_assigned_mining_ship_count(target_id: String) -> int:
	if target_id.is_empty():
		return 0

	var count := 0

	for runtime_variant in mining_ship_runtime_by_unit_id.values():
		var runtime := runtime_variant as Dictionary

		if str(runtime.get("target_id", "")) == target_id:
			count += 1

	return count


func _spawn_unit(scene: PackedScene) -> AutomationUnit:
	if automation_root == null:
		return null

	var unit := scene.instantiate() as AutomationUnit

	if unit == null:
		return null

	automation_root.add_child(unit)
	return unit


func _on_scan_drone_arrived_at_target(
	unit: AutomationUnit,
	mission_id: int,
	target_id: String
) -> void:
	var mission := GameSession.complete_automation_mission(mission_id)

	if mission.is_empty():
		active_units_by_mission_id.erase(mission_id)
		_request_automation_state_changed()
		return

	_complete_scan_mission(target_id)
	active_units_by_mission_id.erase(mission_id)

	var target_node := _get_target_node(target_id)

	if target_node == null:
		unit.return_to_base_orbit()
		_request_automation_state_changed()
		return

	_disconnect_unit_signals(unit)
	unit.transfer_orbit_to_base(target_node)

	_request_automation_state_changed()


func _on_mining_ship_arrived_at_target(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var unit_id := unit.get_instance_id()
	var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})

	if runtime.is_empty():
		return

	var target_id := str(runtime.get("target_id", ""))

	var target_node := _get_target_node(target_id)

	if target_node == null:
		var earth_node := _get_target_node(BASE_ID_EARTH)

		if earth_node != null:
			unit.recall_to_base(earth_node)

		_request_automation_state_changed()
		return

	unit.transfer_orbit_to_base(target_node)

	runtime["status"] = MiningShipStatus.MINING
	mining_ship_runtime_by_unit_id[unit_id] = runtime
	_request_automation_state_changed()


func _complete_scan_mission(target_id: String) -> void:
	if target_id.is_empty():
		return

	if GameSession.current_system_id.is_empty():
		return

	GameSession.set_object_scan_state(
		GameSession.current_system_id,
		target_id,
		GameSession.SCAN_BASIC
	)

	var target_node: Node2D = _get_target_node(target_id)

	if target_node == null:
		return

	var definition: Resource = _get_definition_from_target_node(target_node)

	if definition == null:
		return

	var visible_resources: Array = _get_visible_resource_entries_for_scanner(
		definition,
		GameSession.get_active_scanner_tier()
	)

	GameSession.ensure_object_resources_initialized(
		GameSession.current_system_id,
		target_id,
		visible_resources
	)
	

func _cleanup_unit(mission_id: int, unit: AutomationUnit) -> void:
	active_units_by_mission_id.erase(mission_id)

	if unit != null and is_instance_valid(unit):
		mining_ship_runtime_by_unit_id.erase(unit.get_instance_id())
		unit.queue_free()


func _process(delta: float) -> void:
	if mining_ship_runtime_by_unit_id.is_empty():
		return

	var ids_to_release: Array[int] = []

	for unit_id_variant in mining_ship_runtime_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})

		if runtime.is_empty():
			ids_to_release.append(unit_id)
			continue

		var status := int(runtime.get("status", MiningShipStatus.TO_TARGET))
		var unit := instance_from_id(unit_id) as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			ids_to_release.append(unit_id)
			continue

		match status:
			MiningShipStatus.MINING:
				var sid: String = str(runtime.get("system_id", ""))
				if sid.is_empty():
					sid = GameSession.current_system_id

				var target_id_mining: String = str(runtime.get("target_id", ""))
				var cargo_resource_id: String = str(runtime.get("cargo_resource_id", ""))

				var current_cargo_float: float = float(runtime.get("current_cargo", 0.0))
				var cargo_capacity_float: float = float(
					runtime.get("cargo_capacity", float(DEFAULT_MINING_CARGO_CAPACITY))
				)

				var mining_rate_pf: float = float(
					runtime.get("mining_rate_per_second", DEFAULT_MINING_RATE_PER_SECOND)
				)
				var bonus_pf: float = get_mining_bonus_for_target(target_id_mining)
				var effective_rate_pf: float = mining_rate_pf * (1.0 + bonus_pf)

				var cargo_slots_left: int = maxi(0, ceili(cargo_capacity_float - current_cargo_float))

				if cargo_slots_left <= 0:
					runtime["extract_remainder"] = 0.0
					var home_full: Node2D = _get_target_node(str(runtime.get("base_id", BASE_ID_EARTH)))
					if home_full != null:
						runtime["status"] = MiningShipStatus.TO_BASE
						unit.recall_to_base(home_full)
					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				var extract_remainder: float = float(runtime.get("extract_remainder", 0.0))
				extract_remainder = extract_remainder + (effective_rate_pf * delta)

				var requested_amount: int = int(floor(extract_remainder))
				if requested_amount <= 0:
					runtime["extract_remainder"] = extract_remainder
					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				requested_amount = mini(requested_amount, cargo_slots_left)

				var extracted_amount: int = 0

				if not sid.is_empty() and not target_id_mining.is_empty() and not cargo_resource_id.is_empty():
					extracted_amount = GameSession.extract_resource_amount(
						sid,
						target_id_mining,
						cargo_resource_id,
						requested_amount
					)

				extract_remainder = extract_remainder - float(extracted_amount)

				if extract_remainder < 0.0:
					extract_remainder = 0.0

				runtime["extract_remainder"] = extract_remainder

				current_cargo_float = current_cargo_float + float(extracted_amount)
				runtime["current_cargo"] = current_cargo_float

				if current_cargo_float >= cargo_capacity_float:
					runtime["extract_remainder"] = 0.0
					var home_base_node_pf: Node2D = _get_target_node(str(runtime.get("base_id", BASE_ID_EARTH)))
					if home_base_node_pf != null:
						runtime["status"] = MiningShipStatus.TO_BASE
						unit.recall_to_base(home_base_node_pf)
				elif requested_amount > 0 and extracted_amount == 0:
					var rid_depleted: bool = GameSession.is_resource_depleted(
						sid,
						target_id_mining,
						cargo_resource_id
					)
					var bad_ids: bool = (
						sid.is_empty()
						or target_id_mining.is_empty()
						or cargo_resource_id.is_empty()
					)

					if bad_ids or rid_depleted:
						runtime["extract_remainder"] = 0.0
						if current_cargo_float > 1e-5:
							var home_depleted: Node2D = _get_target_node(str(runtime.get("base_id", BASE_ID_EARTH)))
							if home_depleted != null:
								runtime["status"] = MiningShipStatus.TO_BASE
								unit.recall_to_base(home_depleted)
						else:
							runtime["loop_active"] = false
							mining_ship_runtime_by_unit_id[unit_id] = runtime
							_release_mining_ship_runtime(unit_id)
							continue
					else:
						runtime["extract_remainder"] = 0.0
						runtime["loop_active"] = false
						mining_ship_runtime_by_unit_id[unit_id] = runtime
						_release_mining_ship_runtime(unit_id)
						continue

				mining_ship_runtime_by_unit_id[unit_id] = runtime

			MiningShipStatus.UNLOADING:
				var base_id_ul: String = str(runtime.get("base_id", BASE_ID_EARTH))
				var resource_id_ul: String = str(runtime.get("cargo_resource_id", ""))
				var unload_timer_ul: float = float(runtime.get("unload_timer", 0.0))

				var cargo_f_ul: float = float(runtime.get("current_cargo", 0.0))
				var snapshot_f_ul: float = float(runtime.get("unload_cargo_snapshot", cargo_f_ul))
				var unload_dur_ul: float = float(
					runtime.get("unload_duration", DEFAULT_MINING_UNLOAD_DURATION)
				)
				var xfer_buf_ul: float = float(runtime.get("unload_xfer_buffer", 0.0))

				if snapshot_f_ul <= 1e-6 or resource_id_ul.is_empty():
					unload_timer_ul = 0.0
				else:
					var xfer_rate_ul: float = (
						snapshot_f_ul / unload_dur_ul if unload_dur_ul > 1e-5 else snapshot_f_ul
					)

					xfer_buf_ul += xfer_rate_ul * delta
					var chunk_i_ul: int = int(floor(xfer_buf_ul))

					if chunk_i_ul > 0 and cargo_f_ul > 1e-6:
						var take_i_ul: int = mini(chunk_i_ul, int(floor(cargo_f_ul)))

						if take_i_ul > 0:
							xfer_buf_ul -= float(take_i_ul)
							cargo_f_ul -= float(take_i_ul)
							GameSession.add_base_resource(base_id_ul, resource_id_ul, take_i_ul)

					unload_timer_ul -= delta

				runtime["unload_xfer_buffer"] = xfer_buf_ul
				runtime["current_cargo"] = cargo_f_ul
				runtime["unload_timer"] = unload_timer_ul

				var unload_finished: bool = unload_timer_ul <= 0.0 or cargo_f_ul <= 1e-6

				if unload_finished:
					var tail_i_ul: int = int(floor(cargo_f_ul + 1e-5))

					if tail_i_ul > 0 and not resource_id_ul.is_empty():
						GameSession.add_base_resource(base_id_ul, resource_id_ul, tail_i_ul)
						cargo_f_ul = 0.0

					runtime["current_cargo"] = cargo_f_ul
					runtime["unload_xfer_buffer"] = 0.0
					runtime["extract_remainder"] = 0.0

					var loop_active_ul: bool = bool(runtime.get("loop_active", true))
					var target_id_ul: String = str(runtime.get("target_id", ""))

					if loop_active_ul and not target_id_ul.is_empty():
						var sys_ul: String = str(runtime.get("system_id", ""))

						if sys_ul.is_empty():
							sys_ul = GameSession.current_system_id

						if GameSession.is_object_depleted(sys_ul, target_id_ul):
							ids_to_release.append(unit_id)
						else:
							var next_resource_id_ul: String = _pick_mining_resource_id_from_store(
								sys_ul,
								target_id_ul
							)

							if next_resource_id_ul.is_empty():
								ids_to_release.append(unit_id)
							else:
								runtime["cargo_resource_id"] = next_resource_id_ul
								runtime["extract_remainder"] = 0.0
								var target_node_ul: Node2D = _get_target_node(target_id_ul)

								if target_node_ul != null:
									runtime["status"] = MiningShipStatus.TO_TARGET
									mining_ship_runtime_by_unit_id[unit_id] = runtime
									unit.start_mission_to_node(target_node_ul)
								else:
									ids_to_release.append(unit_id)
					else:
						ids_to_release.append(unit_id)
				else:
					mining_ship_runtime_by_unit_id[unit_id] = runtime

	for unit_id in ids_to_release:
		_release_mining_ship_runtime(unit_id)


func _on_mining_ship_returned_to_base(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var unit_id := unit.get_instance_id()
	var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})

	if runtime.is_empty():
		return

	var status := int(runtime.get("status", MiningShipStatus.TO_TARGET))

	if status != MiningShipStatus.TO_BASE:
		return

	var base_id := str(runtime.get("base_id", BASE_ID_EARTH))
	var resource_id := str(runtime.get("cargo_resource_id", ""))
	var cargo_at_arrival := float(runtime.get("current_cargo", 0.0))

	runtime["unload_cargo_snapshot"] = cargo_at_arrival
	runtime["unload_xfer_buffer"] = 0.0

	if cargo_at_arrival <= 1e-6 or resource_id.is_empty():
		runtime["unload_timer"] = 0.0
	else:
		runtime["current_cargo"] = cargo_at_arrival
		runtime["unload_timer"] = float(runtime.get("unload_duration", DEFAULT_MINING_UNLOAD_DURATION))

	runtime["extract_remainder"] = 0.0
	runtime["status"] = MiningShipStatus.UNLOADING
	mining_ship_runtime_by_unit_id[unit_id] = runtime

	if unit.base_node != null and is_instance_valid(unit.base_node):
		unit.transfer_orbit_to_base(unit.base_node)

	_request_automation_state_changed()


func _release_mining_ship_runtime(unit_id: int) -> void:
	var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})
	mining_ship_runtime_by_unit_id.erase(unit_id)

	var unit := instance_from_id(unit_id) as AutomationUnit

	if unit == null or not is_instance_valid(unit):
		_request_automation_state_changed()
		return

	_disconnect_unit_signals(unit)

	var base_id := str(runtime.get("base_id", BASE_ID_EARTH))
	var home_base_node := _get_target_node(base_id)

	if home_base_node != null:
		unit.transfer_orbit_to_base(home_base_node)

	_request_automation_state_changed()


func _get_idle_drone() -> AutomationUnit:
	for drone in idle_drones:
		if drone == null or not is_instance_valid(drone):
			continue

		if not drone.is_available():
			continue

		if drone.base_node == null or not is_instance_valid(drone.base_node):
			continue

		if _get_object_id_from_node(drone.base_node) != BASE_ID_EARTH:
			continue

		return drone

	return null


func _get_idle_mining_ship() -> AutomationUnit:
	for ship in idle_mining_ships:
		if ship == null or not is_instance_valid(ship):
			continue

		if not ship.is_available():
			continue

		if ship.base_node == null or not is_instance_valid(ship.base_node):
			continue

		if _get_object_id_from_node(ship.base_node) != BASE_ID_EARTH:
			continue

		return ship

	return null


func _disconnect_unit_signals(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	for connection in unit.arrived_at_target.get_connections():
		var callable: Callable = connection.get("callable")

		if unit.arrived_at_target.is_connected(callable):
			unit.arrived_at_target.disconnect(callable)

	for connection in unit.returned_to_base.get_connections():
		var callable: Callable = connection.get("callable")

		if unit.returned_to_base.is_connected(callable):
			unit.returned_to_base.disconnect(callable)

func _get_definition_from_target_node(target_node: Node2D) -> Resource:
	if target_node == null:
		return null

	if target_node is SystemBody:
		return (target_node as SystemBody).definition

	if target_node is PointOfInterest:
		return (target_node as PointOfInterest).definition

	return null


func _get_visible_resource_entries_for_scanner(definition: Resource, scanner_tier: String) -> Array:
	var result: Array = []

	if definition == null:
		return result

	result.append_array(_get_resource_entries_for_tier(
		definition,
		&"get_basic_scan_resources",
		GameSession.SCANNER_BASIC,
		scanner_tier
	))

	result.append_array(_get_resource_entries_for_tier(
		definition,
		&"get_deep_scan_resources",
		GameSession.SCANNER_DEEP,
		scanner_tier
	))

	result.append_array(_get_resource_entries_for_tier(
		definition,
		&"get_special_scan_resources",
		GameSession.SCANNER_SPECIAL,
		scanner_tier
	))

	return result


func _get_resource_entries_for_tier(
	definition: Resource,
	method_name: StringName,
	resource_tier: String,
	scanner_tier: String
) -> Array:
	var result: Array = []

	if definition == null:
		return result

	if not definition.has_method(method_name):
		return result

	if not _can_scanner_see_resource_tier(scanner_tier, resource_tier):
		return result

	var entries: Array = definition.call(method_name)

	for entry: Variant in entries:
		result.append(entry)

	return result


func _can_scanner_see_resource_tier(scanner_tier: String, resource_tier: String) -> bool:
	match scanner_tier:
		GameSession.SCANNER_BASIC:
			return resource_tier == GameSession.SCANNER_BASIC

		GameSession.SCANNER_DEEP:
			return resource_tier == GameSession.SCANNER_BASIC or resource_tier == GameSession.SCANNER_DEEP

		GameSession.SCANNER_SPECIAL:
			return true

		_:
			return false


func _get_object_id_from_node(node: Node) -> String:
	if node is SystemBody:
		return (node as SystemBody).body_id

	if node is PointOfInterest:
		return (node as PointOfInterest).poi_id

	return ""


func _get_target_node(target_id: String) -> Node2D:
	if spawner == null:
		return null

	return spawner.get_spawned_object(target_id) as Node2D


func _pick_mining_resource_id_from_store(system_id: String, object_id: String) -> String:
	if system_id.is_empty() or object_id.is_empty():
		return ""

	var remaining_m: Dictionary = GameSession.get_object_remaining_resources(system_id, object_id)

	if remaining_m.is_empty():
		return ""

	var keys_sorted := PackedStringArray()
	for dict_key in remaining_m.keys():
		var key_str: String = String(dict_key)
		if key_str.is_empty():
			continue
		keys_sorted.append(key_str)

	keys_sorted.sort()

	for sorted_key: String in keys_sorted:
		var amt_var: Variant = remaining_m.get(sorted_key, 0)
		if int(amt_var) > 0:
			return sorted_key

	return ""


func _request_automation_state_changed() -> void:
	if _automation_state_emit_scheduled:
		return
	_automation_state_emit_scheduled = true
	call_deferred("_emit_automation_state_changed_deferred")


func _emit_automation_state_changed_deferred() -> void:
	_automation_state_emit_scheduled = false
	if not is_inside_tree():
		return
	automation_state_changed.emit()
