## Spawns and controls visible automated drones and mining ships.
## Uses AutomationStore through GameSession, but keeps visual scene logic local.
class_name AutomationController
extends Node

signal automation_state_changed

const DRONE_SCENE: PackedScene = preload("res://scenes/automation/drone.tscn")
const MINING_SHIP_SCENE: PackedScene = preload("res://scenes/automation/mining_ship.tscn")

const DEFAULT_SCAN_DURATION: float = 2.0
# Work duration is intentionally huge: mining completes when internal cargo fills,
# not when AutomationUnit.work_timer runs out.
const DEFAULT_MINING_DURATION: float = 999999.0
const DEFAULT_MINING_CARGO_CAPACITY: int = 20
const DEFAULT_MINING_RATE_PER_SECOND: float = 2.0
const DEFAULT_MINING_UNLOAD_DURATION: float = 2.0
## Deprecated: yield per supporting scan drone now comes from `GameSession` / upgrade data.
const DRONE_MINING_BONUS_PER_UNIT: float = 0.02

var automation_root: Node2D
var spawner: SystemSpawner

var active_units_by_mission_id: Dictionary = {}
var idle_drones: Array[AutomationUnit] = []
var idle_mining_ships: Array[AutomationUnit] = []

var starting_units_initialized: bool = false

## Primary-base body id for this SystemScene instance (`BaseStore` key). Set in `ensure_starting_units`.
var _session_primary_base_body_id: String = ""

enum MiningShipStatus {
	TO_TARGET,
	MINING,
	TO_BASE,
	UNLOADING,
	WAITING_FOR_STORAGE,
}

var mining_ship_runtime_by_unit_id: Dictionary = {}

## Scan drones keep a logical assignment from launch until idle at session primary base (`returned_to_base`).
## Mirrors mining runtime: used for UI mission counts independent of orbit position / AutomationStore lifecycle.
var scan_drone_target_by_unit_id: Dictionary = {}

## Coalesces automation_state_changed emits to at most once per idle frame (fewer UI rebuilds).
var _automation_state_emit_scheduled: bool = false


func _get_session_base_id() -> String:
	var sid: String = _session_primary_base_body_id.strip_edges()
	if not sid.is_empty():
		return sid
	push_warning("AutomationController: missing session primary base id, falling back to BaseStore.BASE_EARTH")
	return BaseStore.BASE_EARTH


## Prefer explicit `runtime["base_id"]`, then session basis; `_get_session_base_id()` warns if needed.
func _runtime_base_id_with_session_fallback(runtime: Dictionary) -> String:
	var from_rt: String = str(runtime.get("base_id", "")).strip_edges()
	if not from_rt.is_empty():
		return from_rt
	return _get_session_base_id()


func setup(
	p_automation_root: Node2D,
	p_spawner: SystemSpawner,
	p_session_primary_base_body_id: String = "",
) -> void:
	automation_root = p_automation_root
	spawner = p_spawner
	_session_primary_base_body_id = p_session_primary_base_body_id.strip_edges()
	set_process(true)


func ensure_starting_units(primary_base_id: String = "") -> void:
	if starting_units_initialized:
		return

	starting_units_initialized = true

	var base_id: String = primary_base_id.strip_edges()
	_session_primary_base_body_id = base_id
	if base_id.is_empty():
		push_warning("AutomationController: ensure_starting_units — kein gültiger primary_base_id, Start-Einheiten übersprungen.")
		return

	if not GameSession.has_established_base(base_id):
		push_warning(
			"AutomationController: ensure_starting_units — keine etablierte Basis für base_id=%s, keine Start-Einheiten."
			% base_id
		)
		return

	var base_node := _get_target_node(base_id)

	if base_node == null:
		push_warning("AutomationController: Start-Basis-Knoten '%s' nicht gefunden, Start-Einheiten übersprungen." % base_id)
		return

	# BaseStore is the source of truth for fleet counts.
	# Spawn idle visual units to match — handles both first load and scene reloads.
	var ships_to_spawn := GameSession.get_base_mining_ship_count(base_id) - idle_mining_ships.size()

	for i in ships_to_spawn:
		var unit := _spawn_unit(MINING_SHIP_SCENE)

		if unit == null:
			continue

		unit.work_duration = DEFAULT_MINING_DURATION
		unit.start_orbiting_base(base_node)
		idle_mining_ships.append(unit)

	var drones_to_spawn := GameSession.get_base_drone_count(base_id) - idle_drones.size()

	for i in drones_to_spawn:
		var unit := _spawn_unit(DRONE_SCENE)

		if unit == null:
			continue

		unit.work_duration = DEFAULT_SCAN_DURATION
		unit.start_orbiting_base(base_node)
		idle_drones.append(unit)

	if ships_to_spawn > 0 or drones_to_spawn > 0:
		_request_automation_state_changed()


## Active ScanDrone + MiningShip automation missions tracked by this controller for TopHUD (`base_id` = primary body id).
## Only matches the session base from `ensure_starting_units`; other ids return 0 (no accidental cross-system totals).
func get_active_job_count_for_base(base_id: String) -> int:
	if base_id.strip_edges() != _session_primary_base_body_id.strip_edges():
		return 0
	if base_id.strip_edges().is_empty():
		return 0
	return scan_drone_target_by_unit_id.size() + mining_ship_runtime_by_unit_id.size()


func get_active_scan_job_count_for_session_base(base_id: String) -> int:
	if base_id.strip_edges() != _session_primary_base_body_id.strip_edges() or base_id.strip_edges().is_empty():
		return 0
	return scan_drone_target_by_unit_id.size()


func get_active_mining_job_count_for_session_base(base_id: String) -> int:
	if base_id.strip_edges() != _session_primary_base_body_id.strip_edges() or base_id.strip_edges().is_empty():
		return 0
	return mining_ship_runtime_by_unit_id.size()


func spawn_idle_drone_at_base(base_id: String = "") -> void:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	if not GameSession.has_established_base(bid):
		push_warning(
			"AutomationController: spawn_idle_drone_at_base aborted — no established base for base_id=%s" % bid
		)
		return

	var base_node := _get_target_node(bid)

	if base_node == null:
		return

	var unit := _spawn_unit(DRONE_SCENE)

	if unit == null:
		return

	unit.work_duration = DEFAULT_SCAN_DURATION
	unit.start_orbiting_base(base_node)
	idle_drones.append(unit)

	_request_automation_state_changed()


func spawn_idle_mining_ship_at_base(base_id: String = "") -> void:
	var bid_s: String = base_id.strip_edges()
	if bid_s.is_empty():
		bid_s = _get_session_base_id()

	if not GameSession.has_established_base(bid_s):
		push_warning(
			"AutomationController: spawn_idle_mining_ship_at_base aborted — no established base for base_id=%s" % bid_s
		)
		return

	var base_node := _get_target_node(bid_s)

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

	var session_bid_ls: String = _get_session_base_id()
	if not GameSession.has_established_base(session_bid_ls):
		push_warning(
			"AutomationController: cannot start scan, no established base for base_id=%s" % session_bid_ls
		)
		return

	var target_node := _get_target_node(target_id)

	if target_node == null:
		return

	var unit := _get_idle_drone()

	if unit == null:
		return

	var mission_id := GameSession.create_scan_mission(session_bid_ls, target_id)

	_disconnect_unit_signals(unit)

	if not unit.arrived_at_target.is_connected(_on_scan_drone_arrived_at_target):
		unit.arrived_at_target.connect(_on_scan_drone_arrived_at_target.bind(mission_id, target_id))

	active_units_by_mission_id[mission_id] = unit

	var drone_uid_launch: int = unit.get_instance_id()
	scan_drone_target_by_unit_id[drone_uid_launch] = target_id

	_ensure_returned_to_base_connected(unit)

	unit.work_duration = (
		DEFAULT_SCAN_DURATION
		* GameSession.get_scan_drone_scan_duration_multiplier(session_bid_ls)
	)

	unit.start_mission_to_node(target_node)

	_request_automation_state_changed()


func launch_mining_ship(target_id: String) -> bool:
	if target_id.is_empty():
		return false

	var session_bid_lm: String = _get_session_base_id()
	if not GameSession.has_established_base(session_bid_lm):
		push_warning(
			"AutomationController: cannot start mining, no established base for base_id=%s" % session_bid_lm
		)
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

	if GameSession.get_object_scan_state(system_id, target_id) == GameSession.SCAN_UNKNOWN:
		push_warning("Cannot start mining: object not scanned.")
		return false

	if not has_mining_candidates_for_target(target_id):
		push_warning("Cannot start mining: no mineable resources for current scan state.")
		return false

	_disconnect_unit_signals(unit)
	unit.work_duration = DEFAULT_MINING_DURATION

	if not unit.arrived_at_target.is_connected(_on_mining_ship_arrived_at_target):
		unit.arrived_at_target.connect(_on_mining_ship_arrived_at_target)

	_ensure_returned_to_base_connected(unit)

	var mining_base_id: String = _get_session_base_id()

	var cargo_cap_mission: int = maxi(
		1,
		int(
			round(
				float(DEFAULT_MINING_CARGO_CAPACITY)
				* GameSession.get_mining_ship_cargo_capacity_multiplier(mining_base_id)
			)
		)
	)

	mining_ship_runtime_by_unit_id[unit.get_instance_id()] = {
		"system_id": system_id,
		"base_id": mining_base_id,
		"target_id": target_id,
		"cargo_resources": {} as Dictionary,
		"mining_extract_remainders": {} as Dictionary,
		"cargo_resource_id": "",
		"current_cargo": 0.0,
		"cargo_capacity": cargo_cap_mission,
		"mining_rate_per_second": DEFAULT_MINING_RATE_PER_SECOND,
		"unload_duration": DEFAULT_MINING_UNLOAD_DURATION,
		"unload_timer": 0.0,
		"unload_xfer_buffers": {} as Dictionary,
		"loop_active": true,
		"status": MiningShipStatus.TO_TARGET,
		"extract_remainder": 0.0,
	}

	unit.start_mission_to_node(target_node)

	_request_automation_state_changed()
	return true


func has_mining_candidates_for_target(object_id: String) -> bool:
	var sid: String = GameSession.current_system_id

	if sid.is_empty() or object_id.is_empty():
		return false

	var scan_state: String = GameSession.get_object_scan_state(sid, object_id)

	if scan_state == GameSession.SCAN_UNKNOWN:
		return false

	var target_node: Node2D = _get_target_node(object_id)
	var definition: Resource = _get_definition_from_target_node(target_node)

	if definition == null:
		return false

	var allowed_entries: Array = _get_allowed_scanned_entries_for_object_scan(definition, scan_state)
	var probe_ids: Array = []

	for entry_variant: Variant in allowed_entries:
		var scanned: ScannedResourceEntry = entry_variant as ScannedResourceEntry

		if scanned == null:
			continue

		var rid_probe: String = String(scanned.resource_id)

		if rid_probe.is_empty():
			continue

		if not probe_ids.has(rid_probe):
			probe_ids.append(rid_probe)

	if probe_ids.is_empty():
		return false

	return GameSession.has_remaining_resources_among(sid, object_id, probe_ids)


func has_idle_drone() -> bool:
	return _get_idle_drone() != null


func has_idle_mining_ship() -> bool:
	return _get_idle_mining_ship() != null


func has_available_mining_ship() -> bool:
	return _get_idle_mining_ship() != null


func get_active_scan_drone_count_for_target(target_id: String) -> int:
	if target_id.is_empty():
		return 0

	var n: int = 0

	for uid_var: Variant in scan_drone_target_by_unit_id.keys():
		var assigned: Variant = scan_drone_target_by_unit_id.get(uid_var, "")
		var assigned_str: String = str(assigned)

		if assigned_str.is_empty():
			continue

		if assigned_str != target_id:
			continue

		n += 1

	return n


func get_active_mining_ship_count_for_target(target_id: String) -> int:
	return get_assigned_mining_ship_count(target_id)


func get_orbiting_drone_count(target_id: String) -> int:
	if target_id.is_empty():
		return 0

	var orbit_drone_count: int = 0

	for orbiting_drone: AutomationUnit in idle_drones:
		if orbiting_drone == null or not is_instance_valid(orbiting_drone):
			continue

		if orbiting_drone.unit_type != AutomationUnit.UnitType.DRONE:
			continue

		if not orbiting_drone.is_available():
			continue

		if orbiting_drone.base_node == null or not is_instance_valid(orbiting_drone.base_node):
			continue

		if _get_object_id_from_node(orbiting_drone.base_node) != target_id:
			continue

		orbit_drone_count += 1

	return orbit_drone_count


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

	var session_bid_rd: String = _get_session_base_id()
	if not GameSession.has_established_base(session_bid_rd):
		push_warning(
			"AutomationController: recall drone aborted — no established base for base_id=%s" % session_bid_rd
		)
		return false

	var home_base_node := _get_target_node(session_bid_rd)

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
		_ensure_returned_to_base_connected(drone)
		drone.recall_to_base(home_base_node)
		_request_automation_state_changed()
		return true

	return false


func recall_one_mining_ship_from_target(target_id: String) -> bool:
	if target_id.is_empty():
		return false

	var session_bid_rm: String = _get_session_base_id()
	if not GameSession.has_established_base(session_bid_rm):
		push_warning(
			"AutomationController: recall mining ship aborted — no established base for base_id=%s"
			% session_bid_rm
		)
		return false

	var home_base_node := _get_target_node(session_bid_rm)

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

	match selected_status:
		MiningShipStatus.MINING, MiningShipStatus.TO_TARGET:
			selected_runtime["status"] = MiningShipStatus.TO_BASE
			selected_runtime["extract_remainder"] = 0.0
			selected_runtime["mining_extract_remainders"] = {} as Dictionary
			selected_ship.recall_to_base(home_base_node)
		MiningShipStatus.TO_BASE:
			selected_ship.recall_to_base(home_base_node)
		MiningShipStatus.UNLOADING:
			_mining_ship_enter_waiting_for_storage(selected_ship, selected_runtime)
		_:
			pass

	mining_ship_runtime_by_unit_id[unit_id] = selected_runtime
	_request_automation_state_changed()
	return true


func get_mining_bonus_for_target(target_id: String) -> float:
	var bonus_base_id: String = _get_session_base_id()
	if not GameSession.has_established_base(bonus_base_id):
		return 0.0
	var per_pct := float(
		GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(bonus_base_id)
	)
	return float(get_orbiting_drone_count(target_id)) * per_pct / 100.0


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
		var drone_uid_miss: int = unit.get_instance_id()

		if scan_drone_target_by_unit_id.has(drone_uid_miss):
			scan_drone_target_by_unit_id.erase(drone_uid_miss)

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
		var home_fallback: Node2D = _get_target_node(_get_session_base_id())

		if home_fallback != null:
			unit.recall_to_base(home_fallback)

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
				var sid_min: String = str(runtime.get("system_id", ""))

				if sid_min.is_empty():
					sid_min = GameSession.current_system_id

				var target_id_min: String = str(runtime.get("target_id", ""))
				var cargo_cap_min: int = int(runtime.get("cargo_capacity", DEFAULT_MINING_CARGO_CAPACITY))

				var cargo_res_min: Dictionary = _merge_legacy_cargo_into_dictionary(runtime)
				var cargo_total_min: int = _cargo_resources_total(cargo_res_min)

				runtime["cargo_resources"] = cargo_res_min
				runtime["current_cargo"] = float(cargo_total_min)

				if cargo_total_min >= cargo_cap_min:
					runtime["mining_extract_remainders"] = {} as Dictionary
					runtime["extract_remainder"] = 0.0
					var home_full_c: Node2D = _get_target_node(
						_runtime_base_id_with_session_fallback(runtime)
					)

					if home_full_c != null:
						runtime["status"] = MiningShipStatus.TO_BASE
						unit.recall_to_base(home_full_c)

					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				var target_node_min: Node2D = _get_target_node(target_id_min)
				var definition_min: Resource = _get_definition_from_target_node(target_node_min)
				var scan_state_min: String = GameSession.get_object_scan_state(sid_min, target_id_min)

				var candidates_min: Array = _list_mining_weighted_candidates(
					sid_min,
					target_id_min,
					definition_min,
					scan_state_min
				)

				if candidates_min.is_empty():
					runtime["mining_extract_remainders"] = {} as Dictionary
					runtime["extract_remainder"] = 0.0

					if cargo_total_min > 0:
						var home_empty_src: Node2D = _get_target_node(
							_runtime_base_id_with_session_fallback(runtime)
						)

						if home_empty_src != null:
							runtime["status"] = MiningShipStatus.TO_BASE
							unit.recall_to_base(home_empty_src)
					else:
						runtime["loop_active"] = false
						mining_ship_runtime_by_unit_id[unit_id] = runtime
						_release_mining_ship_runtime(unit_id)
						continue

					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				var weight_sum: float = 0.0

				for cand_m: Variant in candidates_min:
					var cm: Dictionary = cand_m as Dictionary
					weight_sum += float(cm.get("weight", 1.0))

				if weight_sum <= 0.0001:
					runtime["mining_extract_remainders"] = {} as Dictionary
					runtime["extract_remainder"] = 0.0

					if cargo_total_min > 0:
						var home_ws: Node2D = _get_target_node(_runtime_base_id_with_session_fallback(runtime))

						if home_ws != null:
							runtime["status"] = MiningShipStatus.TO_BASE
							unit.recall_to_base(home_ws)
					else:
						runtime["loop_active"] = false
						mining_ship_runtime_by_unit_id[unit_id] = runtime
						_release_mining_ship_runtime(unit_id)
						continue

					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				var mining_rate_min: float = float(
					runtime.get("mining_rate_per_second", DEFAULT_MINING_RATE_PER_SECOND)
				)
				var bonus_min: float = get_mining_bonus_for_target(target_id_min)
				var effective_rate_min: float = mining_rate_min * (1.0 + bonus_min)
				var total_extract_float: float = effective_rate_min * delta

				var rem_dict_min: Dictionary = runtime.get("mining_extract_remainders", {}) as Dictionary
				rem_dict_min = rem_dict_min.duplicate(true)

				var space_left_min: int = maxi(0, cargo_cap_min - cargo_total_min)

				for cand_v: Variant in candidates_min:
					var cand: Dictionary = cand_v as Dictionary
					var rid: String = str(cand.get("id", ""))

					if rid.is_empty():
						continue

					var w: float = float(cand.get("weight", 1.0))
					var per_res_float: float = total_extract_float * (w / weight_sum)
					var acc: float = float(rem_dict_min.get(rid, 0.0))
					acc += per_res_float
					var requested: int = int(floor(acc))

					if requested <= 0:
						rem_dict_min[rid] = acc
						continue

					requested = mini(requested, space_left_min)

					if requested <= 0:
						rem_dict_min[rid] = acc
						continue

					var extracted: int = 0

					if not sid_min.is_empty() and not target_id_min.is_empty():
						extracted = GameSession.extract_resource_amount(
							sid_min,
							target_id_min,
							rid,
							requested
						)

					if extracted > 0:
						acc = acc - float(extracted)
					elif requested > 0:
						acc = acc - float(requested)

					if acc < 0.0:
						acc = 0.0

					rem_dict_min[rid] = acc

					if extracted > 0:
						var cur_c: int = int(cargo_res_min.get(rid, 0))
						cargo_res_min[rid] = cur_c + extracted
						cargo_total_min += extracted
						space_left_min = maxi(0, cargo_cap_min - cargo_total_min)

					if space_left_min <= 0:
						break

				runtime["cargo_resources"] = cargo_res_min
				runtime["mining_extract_remainders"] = rem_dict_min
				runtime["extract_remainder"] = 0.0
				cargo_total_min = _cargo_resources_total(cargo_res_min)
				runtime["current_cargo"] = float(cargo_total_min)

				if cargo_total_min >= cargo_cap_min:
					runtime["mining_extract_remainders"] = {} as Dictionary
					runtime["extract_remainder"] = 0.0
					var home_cap: Node2D = _get_target_node(_runtime_base_id_with_session_fallback(runtime))

					if home_cap != null:
						runtime["status"] = MiningShipStatus.TO_BASE
						unit.recall_to_base(home_cap)

				var post_candidates: Array = _list_mining_weighted_candidates(
					sid_min,
					target_id_min,
					definition_min,
					scan_state_min
				)

				if post_candidates.is_empty():
					runtime["mining_extract_remainders"] = {} as Dictionary
					runtime["extract_remainder"] = 0.0

					if cargo_total_min > 0:
						var home_pc: Node2D = _get_target_node(_runtime_base_id_with_session_fallback(runtime))

						if home_pc != null:
							runtime["status"] = MiningShipStatus.TO_BASE
							unit.recall_to_base(home_pc)
					else:
						runtime["loop_active"] = false
						mining_ship_runtime_by_unit_id[unit_id] = runtime
						_release_mining_ship_runtime(unit_id)
						continue

				mining_ship_runtime_by_unit_id[unit_id] = runtime

			MiningShipStatus.UNLOADING:
				var base_id_ul: String = _runtime_base_id_with_session_fallback(runtime)
				var unload_timer_ul: float = float(runtime.get("unload_timer", 0.0))
				var unload_dur_ul: float = float(
					runtime.get("unload_duration", DEFAULT_MINING_UNLOAD_DURATION)
				)

				var cargo_res_ul: Dictionary = runtime.get("cargo_resources", {}) as Dictionary
				cargo_res_ul = cargo_res_ul.duplicate(true)
				var snap_ul: Dictionary = runtime.get("unload_cargo_snapshot", {}) as Dictionary
				snap_ul = snap_ul.duplicate(true)

				var bufs_ul: Dictionary = runtime.get("unload_xfer_buffers", {}) as Dictionary
				bufs_ul = bufs_ul.duplicate(true)

				var snap_total_ul: int = _cargo_resources_total(snap_ul)
				var cargo_total_ul: int = _cargo_resources_total(cargo_res_ul)

				if cargo_total_ul > 0 and GameSession.get_base_storage_free(base_id_ul) <= 0:
					runtime["cargo_resources"] = cargo_res_ul
					_mining_ship_enter_waiting_for_storage(unit, runtime)
					mining_ship_runtime_by_unit_id[unit_id] = runtime
					_request_automation_state_changed()
					continue

				if snap_total_ul > 0 and unload_dur_ul > 1e-5:
					var xfer_rate_total: float = float(snap_total_ul) / unload_dur_ul

					for snap_key_variant: Variant in snap_ul.keys():
						var rid_ul: String = str(snap_key_variant)
						var snap_amt: int = maxi(0, int(snap_ul.get(rid_ul, 0)))

						if snap_amt <= 0 or rid_ul.is_empty():
							continue

						var portion: float = float(snap_amt) / float(snap_total_ul)
						var rate_rid: float = xfer_rate_total * portion
						var buf_val: float = float(bufs_ul.get(rid_ul, 0.0))
						buf_val += rate_rid * delta
						var chunk_i: int = int(floor(buf_val))
						var cargo_here: int = maxi(0, int(cargo_res_ul.get(rid_ul, 0)))

						var take_i: int = mini(chunk_i, cargo_here)
						var storage_free_xfer: int = GameSession.get_base_storage_free(base_id_ul)
						take_i = mini(take_i, storage_free_xfer)

						if take_i > 0:
							buf_val -= float(take_i)
							var after_r: int = cargo_here - take_i
							if after_r <= 0:
								cargo_res_ul.erase(rid_ul)
							else:
								cargo_res_ul[rid_ul] = after_r
							GameSession.add_base_resource(base_id_ul, rid_ul, take_i)

						bufs_ul[rid_ul] = buf_val

					unload_timer_ul -= delta
				else:
					unload_timer_ul = 0.0

				runtime["cargo_resources"] = cargo_res_ul
				runtime["unload_xfer_buffers"] = bufs_ul
				runtime["unload_timer"] = unload_timer_ul

				cargo_total_ul = _cargo_resources_total(cargo_res_ul)
				runtime["current_cargo"] = float(cargo_total_ul)

				var unload_finished: bool = unload_timer_ul <= 0.0 or cargo_total_ul <= 0

				if unload_finished:
					if cargo_total_ul > 0:
						cargo_res_ul = _unload_greedy_into_base_until_full(base_id_ul, cargo_res_ul)
						cargo_total_ul = _cargo_resources_total(cargo_res_ul)

					if cargo_total_ul <= 0:
						var empty_bufs: Dictionary = {} as Dictionary
						cargo_res_ul.clear()

						runtime["cargo_resources"] = cargo_res_ul
						runtime["unload_xfer_buffers"] = empty_bufs
						runtime["unload_cargo_snapshot"] = {} as Dictionary
						runtime["unload_timer"] = 0.0
						runtime["extract_remainder"] = 0.0
						runtime["mining_extract_remainders"] = {} as Dictionary
						runtime["current_cargo"] = 0.0
						runtime["cargo_resource_id"] = ""

						var loop_active_ul: bool = bool(runtime.get("loop_active", true))
						var target_id_ul: String = str(runtime.get("target_id", ""))

						if loop_active_ul and not target_id_ul.is_empty():
							var sys_ul: String = str(runtime.get("system_id", ""))

							if sys_ul.is_empty():
								sys_ul = GameSession.current_system_id

							if not has_mining_candidates_for_target(target_id_ul):
								ids_to_release.append(unit_id)
							else:
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
						var empty_bufs_wait: Dictionary = {} as Dictionary
						runtime["cargo_resources"] = cargo_res_ul
						runtime["unload_xfer_buffers"] = empty_bufs_wait
						runtime["unload_cargo_snapshot"] = {} as Dictionary
						runtime["unload_timer"] = 0.0
						runtime["current_cargo"] = float(cargo_total_ul)
						runtime["status"] = MiningShipStatus.WAITING_FOR_STORAGE
						mining_ship_runtime_by_unit_id[unit_id] = runtime
				else:
					mining_ship_runtime_by_unit_id[unit_id] = runtime

			MiningShipStatus.WAITING_FOR_STORAGE:
				var base_ws: String = _runtime_base_id_with_session_fallback(runtime)
				var cargo_ws: Dictionary = _merge_legacy_cargo_into_dictionary(runtime)

				var unit_ws: AutomationUnit = instance_from_id(unit_id) as AutomationUnit

				if unit_ws == null or not is_instance_valid(unit_ws):
					ids_to_release.append(unit_id)
					continue

				cargo_ws = _unload_greedy_into_base_until_full(base_ws, cargo_ws.duplicate(true))
				var cargo_total_ws: int = _cargo_resources_total(cargo_ws)
				runtime["cargo_resources"] = cargo_ws
				runtime["current_cargo"] = float(cargo_total_ws)

				if cargo_total_ws <= 0:
					var empty_bufs_ws: Dictionary = {} as Dictionary
					cargo_ws.clear()

					runtime["cargo_resources"] = cargo_ws
					runtime["unload_xfer_buffers"] = empty_bufs_ws
					runtime["unload_cargo_snapshot"] = {} as Dictionary
					runtime["unload_timer"] = 0.0
					runtime["extract_remainder"] = 0.0
					runtime["mining_extract_remainders"] = {} as Dictionary
					runtime["current_cargo"] = 0.0
					runtime["cargo_resource_id"] = ""

					var loop_active_ws: bool = bool(runtime.get("loop_active", true))
					var target_id_ws: String = str(runtime.get("target_id", ""))

					if loop_active_ws and not target_id_ws.is_empty():
						var sys_ws: String = str(runtime.get("system_id", ""))

						if sys_ws.is_empty():
							sys_ws = GameSession.current_system_id

						if not has_mining_candidates_for_target(target_id_ws):
							ids_to_release.append(unit_id)
						else:
							var target_node_ws: Node2D = _get_target_node(target_id_ws)

							if target_node_ws != null:
								runtime["status"] = MiningShipStatus.TO_TARGET
								mining_ship_runtime_by_unit_id[unit_id] = runtime
								unit_ws.start_mission_to_node(target_node_ws)
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

	var cargo_res_rb: Dictionary = _merge_legacy_cargo_into_dictionary(runtime)
	runtime["cargo_resources"] = cargo_res_rb

	var snap_rb: Dictionary = {} as Dictionary

	for snap_key_variant: Variant in cargo_res_rb.keys():
		var rid_snap: String = str(snap_key_variant)
		var amt_snap: int = maxi(0, int(cargo_res_rb.get(rid_snap, 0)))

		if rid_snap.is_empty() or amt_snap <= 0:
			continue

		snap_rb[rid_snap] = amt_snap

	var total_rb: int = _cargo_resources_total(snap_rb)
	runtime["unload_cargo_snapshot"] = snap_rb

	var buf_init: Dictionary = {} as Dictionary

	for buf_key_variant: Variant in snap_rb.keys():
		buf_init[str(buf_key_variant)] = 0.0

	runtime["unload_xfer_buffers"] = buf_init
	runtime["mining_extract_remainders"] = {} as Dictionary
	runtime["extract_remainder"] = 0.0
	runtime["current_cargo"] = float(total_rb)
	runtime["cargo_resource_id"] = ""

	if total_rb <= 0:
		runtime["unload_timer"] = 0.0
	else:
		runtime["unload_timer"] = float(runtime.get("unload_duration", DEFAULT_MINING_UNLOAD_DURATION))

	runtime["status"] = MiningShipStatus.UNLOADING
	mining_ship_runtime_by_unit_id[unit_id] = runtime

	if unit.base_node != null and is_instance_valid(unit.base_node):
		unit.transfer_orbit_to_base(unit.base_node)

	_request_automation_state_changed()


## Cargo stays on the ship; clears staged unload so we are not stuck in UNLOADING while storage is full.
func _mining_ship_enter_waiting_for_storage(unit: AutomationUnit, runtime: Dictionary) -> void:
	var base_id_wait: String = _runtime_base_id_with_session_fallback(runtime)
	var home_wait: Node2D = _get_target_node(base_id_wait)
	var cargo_merged: Dictionary = _merge_legacy_cargo_into_dictionary(runtime)

	runtime["cargo_resources"] = cargo_merged
	runtime["current_cargo"] = float(_cargo_resources_total(cargo_merged))
	runtime["unload_xfer_buffers"] = {} as Dictionary
	runtime["unload_cargo_snapshot"] = {} as Dictionary
	runtime["unload_timer"] = 0.0
	runtime["mining_extract_remainders"] = {} as Dictionary
	runtime["extract_remainder"] = 0.0
	runtime["status"] = MiningShipStatus.WAITING_FOR_STORAGE

	if unit != null and is_instance_valid(unit) and home_wait != null:
		unit.transfer_orbit_to_base(home_wait)


func _release_mining_ship_runtime(unit_id: int) -> void:
	var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})
	mining_ship_runtime_by_unit_id.erase(unit_id)

	var unit := instance_from_id(unit_id) as AutomationUnit

	if unit == null or not is_instance_valid(unit):
		_request_automation_state_changed()
		return

	_disconnect_unit_signals(unit)

	var base_id: String = _runtime_base_id_with_session_fallback(runtime)
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

		var session_home: String = _get_session_base_id()
		if _get_object_id_from_node(drone.base_node) != session_home:
			continue

		return drone

	return null


func _get_idle_mining_ship() -> AutomationUnit:
	for ship in idle_mining_ships:
		if ship == null or not is_instance_valid(ship):
			continue

		if not ship.is_available():
			continue

		var ship_uid_idle: int = ship.get_instance_id()

		if mining_ship_runtime_by_unit_id.has(ship_uid_idle):
			continue

		if ship.base_node == null or not is_instance_valid(ship.base_node):
			continue

		var session_ship_home: String = _get_session_base_id()
		if _get_object_id_from_node(ship.base_node) != session_ship_home:
			continue

		return ship

	return null


func _ensure_returned_to_base_connected(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if not unit.returned_to_base.is_connected(_on_automation_unit_returned_to_base):
		unit.returned_to_base.connect(_on_automation_unit_returned_to_base)


func _on_automation_unit_returned_to_base(unit: AutomationUnit) -> void:
	match unit.unit_type:
		AutomationUnit.UnitType.MINING_SHIP:
			_on_mining_ship_returned_to_base(unit)
		AutomationUnit.UnitType.DRONE:
			_on_scan_drone_return_dock_clear_assignment(unit)


func _on_scan_drone_return_dock_clear_assignment(unit: AutomationUnit) -> void:
	var drone_uid_rb: int = unit.get_instance_id()

	if not scan_drone_target_by_unit_id.has(drone_uid_rb):
		return

	scan_drone_target_by_unit_id.erase(drone_uid_rb)
	_request_automation_state_changed()


func _disconnect_unit_signals(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	for arrival_connection: Dictionary in unit.arrived_at_target.get_connections():
		var arrival_callable_variant: Variant = arrival_connection.get("callable", Callable())

		if not arrival_callable_variant is Callable:
			continue

		var arrival_cb: Callable = arrival_callable_variant as Callable

		if unit.arrived_at_target.is_connected(arrival_cb):
			unit.arrived_at_target.disconnect(arrival_cb)

	for return_connection: Dictionary in unit.returned_to_base.get_connections():
		var return_callable_variant: Variant = return_connection.get("callable", Callable())

		if not return_callable_variant is Callable:
			continue

		var return_cb: Callable = return_callable_variant as Callable

		if unit.returned_to_base.is_connected(return_cb):
			unit.returned_to_base.disconnect(return_cb)


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


func _cargo_resources_total(cargo_resources: Variant) -> int:
	if not cargo_resources is Dictionary:
		return 0

	var d: Dictionary = cargo_resources as Dictionary
	var total_acc: int = 0

	for value_variant: Variant in d.values():
		total_acc += maxi(0, int(value_variant))

	return total_acc


func _unload_greedy_into_base_until_full(base_id_load: String, cargo_in: Dictionary) -> Dictionary:
	var leftover_load: Dictionary = cargo_in.duplicate(true)
	var key_list_load: Array = []

	for k_var_unload: Variant in leftover_load.keys():
		key_list_load.append(str(k_var_unload))

	key_list_load.sort()

	for rid_g: Variant in key_list_load:
		var rid_str: String = str(rid_g)

		if rid_str.is_empty():
			continue

		var have_ul_q: int = maxi(0, int(leftover_load.get(rid_str, 0)))

		if have_ul_q <= 0:
			leftover_load.erase(rid_str)
			continue

		var free_ul_q: int = GameSession.get_base_storage_free(base_id_load)

		if free_ul_q <= 0:
			continue

		var req_take: int = mini(have_ul_q, free_ul_q)
		var accepted_ul_q: int = GameSession.add_base_resource(base_id_load, rid_str, req_take)
		var remain_ul_q: int = have_ul_q - accepted_ul_q

		if remain_ul_q <= 0:
			leftover_load.erase(rid_str)
		else:
			leftover_load[rid_str] = remain_ul_q

	return leftover_load


func _merge_legacy_cargo_into_dictionary(runtime: Dictionary) -> Dictionary:
	var out: Dictionary = {} as Dictionary
	var cargo_variant: Variant = runtime.get("cargo_resources", {})

	if cargo_variant is Dictionary:
		for key_variant: Variant in (cargo_variant as Dictionary).keys():
			var ks: String = str(key_variant)

			if ks.is_empty():
				continue

			out[ks] = maxi(0, int((cargo_variant as Dictionary).get(key_variant, 0)))

	var has_positive: bool = false

	for amt_v: Variant in out.values():
		if int(amt_v) > 0:
			has_positive = true
			break

	if not has_positive:
		var legacy_rid: String = str(runtime.get("cargo_resource_id", ""))
		var legacy_amt: int = maxi(0, int(floor(float(runtime.get("current_cargo", 0.0)))))

		if not legacy_rid.is_empty() and legacy_amt > 0:
			out[legacy_rid] = legacy_amt

	return out


func _resource_weight_from_scanned_entry(entry: ScannedResourceEntry) -> float:
	if entry == null:
		return 1.0

	var rp: int = int(entry.richness_percent)

	if rp <= 0:
		return 1.0

	return float(rp)


func _append_scanned_entries_from_method(dst: Array, definition: Resource, method: StringName) -> void:
	if definition == null or not definition.has_method(method):
		return

	var got: Variant = definition.call(method)

	if not got is Array:
		return

	for item: Variant in got as Array:
		var sre: ScannedResourceEntry = item as ScannedResourceEntry

		if sre != null:
			dst.append(sre)


func _get_allowed_scanned_entries_for_object_scan(definition: Resource, scan_state: String) -> Array:
	var out: Array = []

	if definition == null:
		return out

	match scan_state:
		GameSession.SCAN_BASIC:
			_append_scanned_entries_from_method(out, definition, &"get_basic_scan_resources")
		GameSession.SCAN_DEEP:
			_append_scanned_entries_from_method(out, definition, &"get_basic_scan_resources")
			_append_scanned_entries_from_method(out, definition, &"get_deep_scan_resources")
		GameSession.SCAN_SPECIAL:
			_append_scanned_entries_from_method(out, definition, &"get_basic_scan_resources")
			_append_scanned_entries_from_method(out, definition, &"get_deep_scan_resources")
			_append_scanned_entries_from_method(out, definition, &"get_special_scan_resources")
		_:
			pass

	return out


func _list_mining_weighted_candidates(
	system_id: String,
	object_id: String,
	definition: Resource,
	scan_state: String
) -> Array:
	var result: Array = []

	if system_id.is_empty() or object_id.is_empty():
		return result

	var entries: Array = _get_allowed_scanned_entries_for_object_scan(definition, scan_state)
	var by_id: Dictionary = {} as Dictionary

	for entry_variant: Variant in entries:
		var entry: ScannedResourceEntry = entry_variant as ScannedResourceEntry

		if entry == null:
			continue

		var rid: String = String(entry.resource_id)

		if rid.is_empty():
			continue

		if GameSession.get_remaining_resource_amount(system_id, object_id, rid) <= 0:
			continue

		var wt: float = _resource_weight_from_scanned_entry(entry)

		if by_id.has(rid):
			by_id[rid] = float(by_id[rid]) + wt
		else:
			by_id[rid] = wt

	var keys_sorted: PackedStringArray = PackedStringArray()

	for dict_key: Variant in by_id.keys():
		keys_sorted.append(str(dict_key))

	keys_sorted.sort()

	for sk: String in keys_sorted:
		result.append({"id": sk, "weight": float(by_id[sk])} as Dictionary)

	return result


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
