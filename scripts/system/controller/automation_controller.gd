## Spawns and controls visible automated drones and mining ships.
## Uses AutomationStore through GameSession, but keeps visual scene logic local.
class_name AutomationController
extends Node

signal automation_state_changed

const DRONE_SCENE: PackedScene = preload("res://scenes/automation/drone.tscn")
const MINING_SHIP_SCENE: PackedScene = preload("res://scenes/automation/mining_ship.tscn")

const BASE_ID_EARTH: String = "earth"
const DEFAULT_SCAN_DURATION: float = 2.0
const DEFAULT_MINING_DURATION: float = 999999.0
const DEFAULT_MINING_CARGO_CAPACITY: int = 20
const DEFAULT_MINING_RATE_PER_SECOND: float = 2.0
const DEFAULT_MINING_UNLOAD_DURATION: float = 2.0
const DEFAULT_MINING_RESOURCE_ID: String = ""
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
		automation_state_changed.emit()


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

	automation_state_changed.emit()


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

	automation_state_changed.emit()


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

	automation_state_changed.emit()


func launch_mining_ship(target_id: String) -> void:
	if target_id.is_empty():
		return

	var target_node := _get_target_node(target_id)

	if target_node == null:
		return

	var unit := _get_idle_mining_ship()

	if unit == null:
		return

	_disconnect_unit_signals(unit)
	unit.work_duration = DEFAULT_MINING_DURATION

	if not unit.arrived_at_target.is_connected(_on_mining_ship_arrived_at_target):
		unit.arrived_at_target.connect(_on_mining_ship_arrived_at_target)

	if not unit.returned_to_base.is_connected(_on_mining_ship_returned_to_base):
		unit.returned_to_base.connect(_on_mining_ship_returned_to_base)

	var resolved_resource_id := _resolve_mining_resource_id(target_node)
	if resolved_resource_id.is_empty():
		_disconnect_unit_signals(unit)
		unit.return_to_base_orbit()
		return

	mining_ship_runtime_by_unit_id[unit.get_instance_id()] = {
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
	}

	unit.start_mission_to_node(target_node)

	automation_state_changed.emit()


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
		automation_state_changed.emit()
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
		selected_ship.recall_to_base(home_base_node)

	mining_ship_runtime_by_unit_id[unit_id] = selected_runtime
	automation_state_changed.emit()
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
		automation_state_changed.emit()
		return

	_complete_scan_mission(target_id)
	active_units_by_mission_id.erase(mission_id)

	var target_node := _get_target_node(target_id)

	if target_node == null:
		unit.return_to_base_orbit()
		automation_state_changed.emit()
		return

	_disconnect_unit_signals(unit)
	unit.transfer_orbit_to_base(target_node)

	automation_state_changed.emit()


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

		automation_state_changed.emit()
		return

	unit.transfer_orbit_to_base(target_node)

	runtime["status"] = MiningShipStatus.MINING
	mining_ship_runtime_by_unit_id[unit_id] = runtime
	automation_state_changed.emit()


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
				var target_id := str(runtime.get("target_id", ""))
				var current_cargo := float(runtime.get("current_cargo", 0.0))
				var cargo_capacity := float(runtime.get("cargo_capacity", float(DEFAULT_MINING_CARGO_CAPACITY)))
				var mining_rate := float(runtime.get("mining_rate_per_second", DEFAULT_MINING_RATE_PER_SECOND))
				var bonus := get_mining_bonus_for_target(target_id)
				var effective_rate := mining_rate * (1.0 + bonus)

				current_cargo = minf(current_cargo + (effective_rate * delta), cargo_capacity)
				runtime["current_cargo"] = current_cargo

				if current_cargo >= cargo_capacity:
					var home_base_node := _get_target_node(str(runtime.get("base_id", BASE_ID_EARTH)))

					if home_base_node != null:
						runtime["status"] = MiningShipStatus.TO_BASE
						unit.recall_to_base(home_base_node)

				mining_ship_runtime_by_unit_id[unit_id] = runtime

			MiningShipStatus.UNLOADING:
				var unload_timer := float(runtime.get("unload_timer", 0.0)) - delta
				runtime["unload_timer"] = unload_timer

				if unload_timer <= 0.0:
					var loop_active := bool(runtime.get("loop_active", true))
					var target_id := str(runtime.get("target_id", ""))

					if loop_active and not target_id.is_empty():
						var target_node := _get_target_node(target_id)

						if target_node != null:
							runtime["status"] = MiningShipStatus.TO_TARGET
							mining_ship_runtime_by_unit_id[unit_id] = runtime
							unit.start_mission_to_node(target_node)
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
	var current_cargo := int(floor(float(runtime.get("current_cargo", 0.0))))

	if current_cargo > 0 and not resource_id.is_empty():
		GameSession.add_base_resource(base_id, resource_id, current_cargo)

	runtime["current_cargo"] = 0.0
	runtime["status"] = MiningShipStatus.UNLOADING
	runtime["unload_timer"] = float(runtime.get("unload_duration", DEFAULT_MINING_UNLOAD_DURATION))
	mining_ship_runtime_by_unit_id[unit_id] = runtime

	if unit.base_node != null and is_instance_valid(unit.base_node):
		unit.transfer_orbit_to_base(unit.base_node)

	automation_state_changed.emit()


func _release_mining_ship_runtime(unit_id: int) -> void:
	var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})
	mining_ship_runtime_by_unit_id.erase(unit_id)

	var unit := instance_from_id(unit_id) as AutomationUnit

	if unit == null or not is_instance_valid(unit):
		automation_state_changed.emit()
		return

	_disconnect_unit_signals(unit)

	var base_id := str(runtime.get("base_id", BASE_ID_EARTH))
	var home_base_node := _get_target_node(base_id)

	if home_base_node != null:
		unit.transfer_orbit_to_base(home_base_node)

	automation_state_changed.emit()


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


func _resolve_mining_resource_id(target_node: Node2D) -> String:
	if target_node == null:
		push_error("AutomationController: Kein Ziel-Node für Mining-Resource-Auflösung. Mining abgebrochen.")
		return ""

	# SystemBody: scan_basic/deep/special_resources sind Array[ScannedResourceEntry]
	if target_node is SystemBody:
		var body := target_node as SystemBody
		if body.definition != null:
			for prop: String in ["scan_basic_resources", "scan_deep_resources", "scan_special_resources"]:
				var entries: Variant = body.definition.get(prop)
				if entries == null:
					continue
				for entry: Variant in entries:
					if entry is Resource:
						var rid: Variant = entry.get("resource_id")
						if rid != null and not String(rid).is_empty():
							return String(rid)

	# PointOfInterest: scan_basic/deep/special_resources sind PackedStringArray (Legacy)
	if target_node is PointOfInterest:
		var poi := target_node as PointOfInterest
		if poi.definition != null:
			for prop: String in ["scan_basic_resources", "scan_deep_resources", "scan_special_resources"]:
				var entries: Variant = poi.definition.get(prop)
				if entries == null:
					continue
				for entry: Variant in entries:
					var entry_str := String(entry)
					if not entry_str.is_empty():
						return entry_str

	push_error(
		"AutomationController: Keine Mining-Resource für Ziel gefunden. Mining abgebrochen. Ziel: %s"
		% str(target_node.name)
	)
	return ""
