## Spawns and controls visible automated drones and mining ships.
## Uses AutomationStore through GameSession, but keeps visual scene logic local.
class_name AutomationController
extends Node

signal automation_state_changed

const DRONE_SCENE: PackedScene = preload("res://scenes/automation/drone.tscn")
const MINING_SHIP_SCENE: PackedScene = preload("res://scenes/automation/mining_ship.tscn")
const SURVEY_PROBE_SCENE: PackedScene = preload("res://scenes/automation/survey_probe_unit.tscn")

const UNIT_ID_SCAN_DRONE := "scan_drone"
const UNIT_ID_MINING_SHIP := "mining_ship"

## Safety fallbacks only when `UnitDefinition` fails to load — not the primary data source.
const DEFAULT_SCAN_DURATION_FALLBACK: float = 2.0
const DEFAULT_MINING_CARGO_CAPACITY_FALLBACK: int = 20
const DEFAULT_MINING_RATE_PER_SECOND_FALLBACK: float = 2.0
const DEFAULT_MINING_UNLOAD_DURATION_FALLBACK: float = 2.0

# Work duration is intentionally huge: mining completes when internal cargo fills,
# not when AutomationUnit.work_timer runs out.
const DEFAULT_MINING_DURATION: float = 999999.0

## SharedScanJob minimum progress floor; real duration comes from scan layer + upgrades.
const SHARED_SCAN_JOB_WORK_REQUIRED: float = 1.0
const SHARED_SCAN_JOB_COMPLETION_OWNER: String = "shared_scan_job"

var automation_root: Node2D
var spawner: SystemSpawner

var active_units_by_mission_id: Dictionary = {}
var idle_drones: Array[AutomationUnit] = []
var idle_mining_ships: Array[AutomationUnit] = []
var idle_survey_probes: Array[SurveyProbeUnit] = []

## instance_id -> true — probe on investigate mission (not idle; may be consumed in BaseStore).
var survey_probe_busy_unit_ids: Dictionary = {}

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

## SharedScanJob runtime (Step 3): one job per system+target+scan_state; multi-SD not enabled yet.
var shared_scan_jobs_by_job_id: Dictionary = {}
var shared_scan_job_id_by_unit_id: Dictionary = {}

## Coalesces automation_state_changed emits to at most once per idle frame (fewer UI rebuilds).
var _automation_state_emit_scheduled: bool = false

var _unit_catalog: UnitCatalog = null

var _audio_service: AutomationAudioService = AutomationAudioService.new()
var _save_service: AutomationSaveService = AutomationSaveService.new()


func _ensure_unit_catalog() -> UnitCatalog:
	if _unit_catalog == null:
		_unit_catalog = UnitCatalog.new()
		_unit_catalog.load_all()
	return _unit_catalog


func _get_scan_duration_seconds_base() -> float:
	var def := _ensure_unit_catalog().get_definition(UNIT_ID_SCAN_DRONE)
	if def != null and def.scan_duration_seconds > 0.0:
		return def.scan_duration_seconds
	push_warning("AutomationController: using fallback scan duration (definition missing or invalid)")
	return DEFAULT_SCAN_DURATION_FALLBACK


func _get_mining_cargo_capacity_base() -> int:
	var def := _ensure_unit_catalog().get_definition(UNIT_ID_MINING_SHIP)
	if def != null and def.mining_cargo_capacity > 0:
		return def.mining_cargo_capacity
	push_warning("AutomationController: using fallback mining cargo capacity (definition missing or invalid)")
	return DEFAULT_MINING_CARGO_CAPACITY_FALLBACK


func _get_mining_rate_per_second_base() -> float:
	var def := _ensure_unit_catalog().get_definition(UNIT_ID_MINING_SHIP)
	if def != null and def.mining_rate_per_second > 0.0:
		return def.mining_rate_per_second
	push_warning("AutomationController: using fallback mining rate (definition missing or invalid)")
	return DEFAULT_MINING_RATE_PER_SECOND_FALLBACK


func _get_mining_unload_duration_seconds_base() -> float:
	var def := _ensure_unit_catalog().get_definition(UNIT_ID_MINING_SHIP)
	if def != null and def.mining_unload_duration_seconds > 0.0:
		return def.mining_unload_duration_seconds
	push_warning("AutomationController: using fallback mining unload duration (definition missing or invalid)")
	return DEFAULT_MINING_UNLOAD_DURATION_FALLBACK


func _get_scan_work_duration_for_base(base_id: String) -> float:
	var bid: String = base_id.strip_edges()

	if bid.is_empty():
		bid = _get_session_base_id()

	return maxf(
		_get_scan_duration_seconds_base() * GameSession.get_scan_drone_scan_duration_multiplier(bid),
		0.001,
	)


func _get_mining_rate_for_base(base_id: String) -> float:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		bid = GameSession.get_primary_base_id()
	return (
		_get_mining_rate_per_second_base()
		* GameSession.get_mining_ship_mining_rate_multiplier(bid)
	)


func _get_mining_cargo_capacity_for_base(base_id: String) -> int:
	var bid: String = base_id.strip_edges()

	if bid.is_empty():
		bid = _get_session_base_id()

	return maxi(
		1,
		int(
			round(
				float(_get_mining_cargo_capacity_base())
				* GameSession.get_mining_ship_cargo_capacity_multiplier(bid)
			)
		),
	)


func _apply_scan_drone_upgrade_stats_to_unit(unit: AutomationUnit, base_id: String = "") -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit.unit_type != AutomationUnit.UnitType.DRONE:
		return

	unit.work_duration = _get_scan_work_duration_for_base(base_id)


func _apply_mining_runtime_upgrade_stats(runtime: Dictionary, base_id: String = "") -> void:
	if runtime.is_empty():
		return

	var bid: String = base_id.strip_edges()

	if bid.is_empty():
		bid = _runtime_base_id_with_session_fallback(runtime)

	runtime["cargo_capacity"] = _get_mining_cargo_capacity_for_base(bid)
	runtime["mining_rate_per_second"] = _get_mining_rate_for_base(bid)
	runtime["unload_duration"] = _get_mining_unload_duration_seconds_base()

	var cargo_res: Dictionary = _merge_legacy_cargo_into_dictionary(runtime)
	var cargo_total: int = _cargo_resources_total(cargo_res)
	runtime["cargo_resources"] = cargo_res
	runtime["current_cargo"] = float(cargo_total)


## Re-apply ScanDrone / MiningShip upgrade-derived stats to all live units (after save/load restore).
func reapply_session_base_unit_upgrade_effects() -> void:
	var base_id: String = _get_session_base_id()

	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var unit := instance_from_id(int(unit_id_variant)) as AutomationUnit
		_apply_scan_drone_upgrade_stats_to_unit(unit, base_id)

	for unit_variant: Variant in active_units_by_mission_id.values():
		_apply_scan_drone_upgrade_stats_to_unit(unit_variant as AutomationUnit, base_id)

	for idle_drone: AutomationUnit in idle_drones:
		_apply_scan_drone_upgrade_stats_to_unit(idle_drone, base_id)

	for unit_id_variant: Variant in mining_ship_runtime_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var runtime_variant: Variant = mining_ship_runtime_by_unit_id[unit_id_variant]

		if not runtime_variant is Dictionary:
			continue

		var runtime: Dictionary = runtime_variant as Dictionary
		_apply_mining_runtime_upgrade_stats(runtime, base_id)
		mining_ship_runtime_by_unit_id[unit_id] = runtime


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
	if not GameSession.base_resources_changed.is_connected(_on_base_resources_changed_survey_probes):
		GameSession.base_resources_changed.connect(_on_base_resources_changed_survey_probes)
	set_process(true)


func ensure_starting_units(primary_base_id: String = "") -> void:
	if starting_units_initialized:
		return

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
	var idle_ships_at_home := 0

	for idle_ship: AutomationUnit in idle_mining_ships:
		if idle_ship == null or not is_instance_valid(idle_ship):
			continue

		if not idle_ship.is_available():
			continue

		if mining_ship_runtime_by_unit_id.has(idle_ship.get_instance_id()):
			continue

		idle_ships_at_home += 1

	var busy_ships := mining_ship_runtime_by_unit_id.size()
	var ships_to_spawn := maxi(
		0,
		GameSession.get_base_mining_ship_count(base_id) - idle_ships_at_home - busy_ships
	)

	for i in ships_to_spawn:
		var unit := _spawn_unit(MINING_SHIP_SCENE)

		if unit == null:
			continue

		unit.work_duration = DEFAULT_MINING_DURATION
		unit.start_orbiting_base(base_node)
		idle_mining_ships.append(unit)

	var idle_drones_at_home := 0

	for idle_drone: AutomationUnit in idle_drones:
		if idle_drone == null or not is_instance_valid(idle_drone):
			continue

		if not idle_drone.is_available():
			continue

		idle_drones_at_home += 1

	var busy_drones := scan_drone_target_by_unit_id.size()
	var drones_to_spawn := maxi(
		0,
		GameSession.get_base_drone_count(base_id) - idle_drones_at_home - busy_drones
	)

	for i in drones_to_spawn:
		var unit := _spawn_unit(DRONE_SCENE)

		if unit == null:
			continue

		unit.work_duration = _get_scan_work_duration_for_base(base_id)
		unit.start_orbiting_base(base_node)
		idle_drones.append(unit)

	var idle_probes_at_home := _count_idle_survey_probes_at_home(base_id)
	var busy_probes := survey_probe_busy_unit_ids.size()
	var probes_to_spawn := maxi(
		0,
		GameSession.get_available_survey_probe_count(base_id) - idle_probes_at_home - busy_probes
	)

	for _probe_i in probes_to_spawn:
		var probe_unit := _spawn_survey_probe_unit()
		if probe_unit == null:
			continue
		probe_unit.one_way_investigate = false
		probe_unit.start_orbiting_base(base_node)
		idle_survey_probes.append(probe_unit)

	if ships_to_spawn > 0 or drones_to_spawn > 0 or probes_to_spawn > 0:
		_request_automation_state_changed()

	reapply_session_base_unit_upgrade_effects()
	starting_units_initialized = true


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

	unit.work_duration = _get_scan_work_duration_for_base(bid)
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


func spawn_idle_survey_probe_at_base(base_id: String = "") -> void:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	if not GameSession.has_established_base(bid):
		push_warning(
			"AutomationController: spawn_idle_survey_probe_at_base aborted — no established base for base_id=%s"
			% bid
		)
		return

	var base_node := _get_target_node(bid)
	if base_node == null:
		return

	var unit := _spawn_survey_probe_unit()
	if unit == null:
		return

	unit.one_way_investigate = false
	unit.start_orbiting_base(base_node)
	idle_survey_probes.append(unit)
	_request_automation_state_changed()


## Sync visible idle survey probes with BaseStore inventory (session primary base only).
func ensure_survey_probe_units_for_base(base_id: String = "") -> void:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	var session_home: String = _session_primary_base_body_id.strip_edges()
	if not session_home.is_empty() and bid != session_home:
		return

	if not GameSession.has_established_base(bid):
		return

	var base_node := _get_target_node(bid)
	if base_node == null:
		return

	_prune_idle_survey_probes()

	var wanted_idle: int = GameSession.get_available_survey_probe_count(bid)
	var have_idle: int = _count_idle_survey_probes_at_home(bid)
	if have_idle > wanted_idle:
		_trim_excess_idle_survey_probes(wanted_idle, bid)
		have_idle = _count_idle_survey_probes_at_home(bid)

	var to_spawn: int = maxi(0, wanted_idle - have_idle)
	for _i in to_spawn:
		var unit := _spawn_survey_probe_unit()
		if unit == null:
			push_warning(
				"AutomationController: failed to spawn idle survey probe (base_id=%s)." % bid
			)
			continue
		unit.one_way_investigate = false
		unit.start_orbiting_base(base_node)
		idle_survey_probes.append(unit)

	_trim_excess_idle_survey_probes(wanted_idle, bid)

	if to_spawn > 0:
		_request_automation_state_changed()


func get_idle_survey_probe_count() -> int:
	_prune_idle_survey_probes()
	return idle_survey_probes.size()


func get_idle_survey_probe_count_at_home(base_id: String = "") -> int:
	_prune_idle_survey_probes()
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()
	return _count_idle_survey_probes_at_home(bid)


func get_busy_survey_probe_count() -> int:
	return survey_probe_busy_unit_ids.size()


func take_idle_survey_probe_for_base(base_id: String = "") -> SurveyProbeUnit:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	ensure_survey_probe_units_for_base(bid)
	_prune_idle_survey_probes()

	var unit := _take_idle_survey_probe_from_list(bid)
	if unit != null:
		survey_probe_busy_unit_ids[unit.get_instance_id()] = true
		return unit

	if GameSession.get_available_survey_probe_count(bid) <= 0:
		return null

	var base_node := _get_target_node(bid)
	if base_node == null:
		return null

	unit = _spawn_survey_probe_unit()
	if unit == null:
		return null

	unit.one_way_investigate = false
	unit.start_orbiting_base(base_node)
	survey_probe_busy_unit_ids[unit.get_instance_id()] = true
	return unit


## Restore-only: spawn a mission visual without BaseStore consume (probe already spent).
func borrow_survey_probe_unit_for_restored_mission(base_id: String = "") -> SurveyProbeUnit:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	if not GameSession.has_established_base(bid):
		return null

	var unit := _spawn_survey_probe_unit()
	if unit == null:
		return null

	unit.one_way_investigate = false
	survey_probe_busy_unit_ids[unit.get_instance_id()] = true
	return unit


func return_survey_probe_to_idle_orbit(unit: SurveyProbeUnit, base_id: String = "") -> void:
	if unit == null or not is_instance_valid(unit):
		return

	survey_probe_busy_unit_ids.erase(unit.get_instance_id())
	unit.one_way_investigate = false

	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	var base_node := _get_target_node(bid)
	if base_node != null and is_instance_valid(base_node):
		unit.start_orbiting_base(base_node)

	_register_idle_survey_probe(unit)


func release_survey_probe_unit(unit: SurveyProbeUnit) -> void:
	if unit == null:
		return

	survey_probe_busy_unit_ids.erase(unit.get_instance_id())
	var idx: int = idle_survey_probes.find(unit)
	if idx >= 0:
		idle_survey_probes.remove_at(idx)


func launch_scan_drone(target_id: String) -> void:
	if target_id.is_empty():
		return

	var session_bid_ls: String = _get_session_base_id()
	if not GameSession.has_established_base(session_bid_ls):
		push_warning(
			"AutomationController: cannot start scan, no established base for base_id=%s" % session_bid_ls
		)
		return

	var system_id: String = GameSession.current_system_id
	if system_id.is_empty():
		return

	var target_node := _get_target_node(target_id)

	if target_node == null:
		return

	var unit := _get_idle_drone()

	if unit == null:
		return

	var scan_active: bool = has_active_shared_scan_job_for_target(target_id)
	var scan_gate: Dictionary = GameSession.can_scan_object(
		system_id,
		target_id,
		session_bid_ls,
		true,
		scan_active,
	)
	if not bool(scan_gate.get("ok", false)):
		var reason: String = str(scan_gate.get("blocked_reason", "")).strip_edges()
		if not reason.is_empty():
			push_warning("AutomationController: cannot start scan — %s" % reason)
		return

	var target_scan_state: String = str(scan_gate.get("target_scan_state", GameSession.SCAN_BASIC)).strip_edges()
	if target_scan_state.is_empty():
		target_scan_state = GameSession.SCAN_BASIC
	var scan_is_progression: bool = bool(scan_gate.get("scan_is_progression", true))

	var shared_job_id: String = _create_shared_scan_job_for_scan_mission(
		system_id,
		target_id,
		session_bid_ls,
		target_scan_state,
		scan_is_progression,
		SHARED_SCAN_JOB_WORK_REQUIRED,
	)

	var mission_id := GameSession.create_scan_mission(
		session_bid_ls,
		target_id,
		target_scan_state,
		scan_is_progression,
	)

	_disconnect_unit_signals(unit)

	if not unit.arrived_at_target.is_connected(_on_scan_drone_arrived_at_target):
		unit.arrived_at_target.connect(_on_scan_drone_arrived_at_target.bind(mission_id, target_id))

	active_units_by_mission_id[mission_id] = unit

	var drone_uid_launch: int = unit.get_instance_id()
	scan_drone_target_by_unit_id[drone_uid_launch] = target_id

	if not shared_job_id.is_empty():
		_assign_scan_drone_to_shared_scan_job(shared_job_id, drone_uid_launch, mission_id)

	_ensure_returned_to_base_connected(unit)

	unit.work_duration = GameSession.get_scan_duration_seconds_for_target_state(
		target_scan_state,
		session_bid_ls,
	)

	_scan_drone_start_outbound(unit, target_node)

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

	if not GameSession.is_object_known(system_id, target_id):
		push_warning("Cannot start mining: object not discovered.")
		return false

	if GameSession.get_object_scan_state(system_id, target_id) == GameSession.SCAN_UNKNOWN:
		push_warning("Cannot start mining: object not scanned.")
		return false

	GameSession.ensure_mining_resources_for_object(system_id, target_id)

	if not has_mining_candidates_for_target(target_id):
		push_warning("Cannot start mining: no mineable resources for current scan state.")
		return false

	_disconnect_unit_signals(unit)
	unit.work_duration = DEFAULT_MINING_DURATION

	if not unit.arrived_at_target.is_connected(_on_mining_ship_arrived_at_target):
		unit.arrived_at_target.connect(_on_mining_ship_arrived_at_target)

	_ensure_returned_to_base_connected(unit)

	var mining_base_id: String = _get_session_base_id()

	var cargo_cap_mission: int = _get_mining_cargo_capacity_for_base(mining_base_id)

	mining_ship_runtime_by_unit_id[unit.get_instance_id()] = {
		"system_id": system_id,
		"base_id": mining_base_id,
		"target_id": target_id,
		"cargo_resources": {} as Dictionary,
		"mining_extract_remainders": {} as Dictionary,
		"cargo_resource_id": "",
		"current_cargo": 0.0,
		"cargo_capacity": cargo_cap_mission,
		"mining_rate_per_second": _get_mining_rate_for_base(mining_base_id),
		"unload_duration": _get_mining_unload_duration_seconds_base(),
		"unload_timer": 0.0,
		"unload_xfer_buffers": {} as Dictionary,
		"loop_active": true,
		"status": MiningShipStatus.TO_TARGET,
		"extract_remainder": 0.0,
	}

	_mining_ship_start_outbound(unit, target_node)

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

	var allowed_entries: Array = _get_allowed_scanned_entries_for_object_scan(
		definition,
		scan_state,
		GameSession.get_unlocked_mining_layer_for_base(_get_session_base_id())
	)
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

	GameSession.ensure_mining_resources_for_object(sid, object_id)

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
	return get_active_scan_drone_support_count_for_target(target_id)


## Post-completion support orbit count (all drones at target, no active scan mission).
func get_active_scan_drone_support_count_for_target(target_id: String) -> int:
	return get_scan_drone_support_effect_count_for_target(target_id)


func get_scan_drone_support_effect_count_for_target(target_id: String) -> int:
	var normalized_target_id: String = target_id.strip_edges()
	if normalized_target_id.is_empty():
		return 0
	return int(get_scan_drone_support_counts_by_target().get(normalized_target_id, 0))


func has_active_scan_drone_support_for_target(target_id: String) -> bool:
	return get_scan_drone_support_effect_count_for_target(target_id) > 0


## Read-only telemetry: all ScanDrones with `scan_drone_target_by_unit_id` assignment.
func get_scan_drone_assigned_counts_by_target() -> Dictionary:
	var counts: Dictionary = {}

	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var target_id: String = str(scan_drone_target_by_unit_id.get(unit_id_variant, "")).strip_edges()
		if target_id.is_empty():
			continue
		counts[target_id] = int(counts.get(target_id, 0)) + 1

	return counts


## Read-only telemetry: ScanDrones with an in-flight AutomationStore scan mission.
func get_active_scan_mission_counts_by_target() -> Dictionary:
	var counts: Dictionary = {}

	for mission_id_variant: Variant in active_units_by_mission_id.keys():
		var mission_id: int = int(mission_id_variant)
		var unit: AutomationUnit = active_units_by_mission_id[mission_id_variant] as AutomationUnit
		var target_id: String = ""

		if unit != null and is_instance_valid(unit):
			var unit_id: int = unit.get_instance_id()
			target_id = str(scan_drone_target_by_unit_id.get(unit_id, "")).strip_edges()

		if target_id.is_empty():
			var mission: Dictionary = GameSession.get_automation_mission(mission_id)
			target_id = str(mission.get("target_id", "")).strip_edges()

		if target_id.is_empty():
			continue

		counts[target_id] = int(counts.get(target_id, 0)) + 1

	return counts


## Read-only telemetry: post-completion support orbit (no active scan mission on unit).
func get_scan_drone_support_counts_by_target() -> Dictionary:
	var counts: Dictionary = {}

	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var target_id: String = str(scan_drone_target_by_unit_id.get(unit_id_variant, "")).strip_edges()
		if target_id.is_empty():
			continue

		var unit := instance_from_id(int(unit_id_variant)) as AutomationUnit
		if not _is_scan_drone_in_support_orbit_at_target(unit, target_id):
			continue

		counts[target_id] = int(counts.get(target_id, 0)) + 1

	for idle_drone: AutomationUnit in idle_drones:
		if idle_drone == null or not is_instance_valid(idle_drone):
			continue

		var idle_uid: int = idle_drone.get_instance_id()
		if scan_drone_target_by_unit_id.has(idle_uid):
			continue

		var orbit_target_id: String = _scan_drone_support_orbit_target_id(idle_drone)
		if orbit_target_id.is_empty():
			continue

		if not _is_scan_drone_in_support_orbit_at_target(idle_drone, orbit_target_id):
			continue

		counts[orbit_target_id] = int(counts.get(orbit_target_id, 0)) + 1

	return counts


## Read-only telemetry snapshot for SharedScanJob Step 2 (no gameplay side effects).
func get_scan_drone_target_debug_snapshot() -> Dictionary:
	var assigned: Dictionary = get_scan_drone_assigned_counts_by_target()
	var active_missions: Dictionary = get_active_scan_mission_counts_by_target()
	var support: Dictionary = get_scan_drone_support_counts_by_target()

	return {
		"assigned_drones_per_target": assigned.duplicate(true),
		"active_scan_missions_per_target": active_missions.duplicate(true),
		"support_drones_per_target": support.duplicate(true),
		"scan_support_effects": get_scan_drone_support_effects_by_target(),
		"targets_with_assigned_scan_drones": _count_nonempty_target_keys(assigned),
		"targets_with_active_scan_missions": _count_nonempty_target_keys(active_missions),
		"targets_with_support_drones": _count_nonempty_target_keys(support),
	}


func get_scan_drone_support_effects_by_target() -> Dictionary:
	var out: Dictionary = {}
	var bonus_base_id: String = _get_session_base_id()
	if not GameSession.has_established_base(bonus_base_id):
		return out

	var bonus_per_drone: float = (
		float(GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(bonus_base_id))
		/ 100.0
	)
	var support_counts: Dictionary = get_scan_drone_support_counts_by_target()
	for target_variant: Variant in support_counts.keys():
		var target_id: String = str(target_variant).strip_edges()
		var support_count: int = int(support_counts.get(target_variant, 0))
		if target_id.is_empty() or support_count <= 0:
			continue
		var total_bonus: float = float(support_count) * bonus_per_drone
		out[target_id] = {
			"support_drone_count": support_count,
			"bonus_per_drone": bonus_per_drone,
			"total_mining_bonus": total_bonus,
			"mining_rate_multiplier": 1.0 + total_bonus,
		}
	return out


func _count_nonempty_target_keys(per_target: Dictionary) -> int:
	var n: int = 0
	for target_variant: Variant in per_target.keys():
		if int(per_target.get(target_variant, 0)) > 0:
			n += 1
	return n


func _make_shared_scan_job_id(
	system_id: String,
	target_id: String,
	target_scan_state: String,
) -> String:
	var sid: String = system_id.strip_edges()
	var tid: String = target_id.strip_edges()
	var tss: String = target_scan_state.strip_edges()
	if sid.is_empty() or tid.is_empty() or tss.is_empty():
		return ""
	return "%s:%s:%s" % [sid, tid, tss]


func _create_shared_scan_job_for_scan_mission(
	system_id: String,
	target_id: String,
	base_id: String,
	target_scan_state: String,
	scan_is_progression: bool,
	work_required: float,
) -> String:
	var job_id: String = _make_shared_scan_job_id(system_id, target_id, target_scan_state)
	if job_id.is_empty():
		return ""

	if shared_scan_jobs_by_job_id.has(job_id):
		return job_id

	var tss: String = target_scan_state.strip_edges()
	shared_scan_jobs_by_job_id[job_id] = {
		"job_id": job_id,
		"system_id": system_id.strip_edges(),
		"target_id": target_id.strip_edges(),
		"base_id": base_id.strip_edges(),
		"target_scan_state": tss,
		"scan_layer": GameSession.scan_state_rank(tss),
		"scan_is_progression": scan_is_progression,
		"assigned_unit_ids": [],
		"active_mission_ids": [],
		"progress": 0.0,
		"work_required": maxf(SHARED_SCAN_JOB_WORK_REQUIRED, work_required),
		"completed": false,
		"completion_applied": false,
		"reward_given": false,
		"created_at_msec": Time.get_ticks_msec(),
		"completed_at_msec": 0,
	}
	return job_id


func _assign_scan_drone_to_shared_scan_job(job_id: String, unit_id: int, mission_id: int) -> void:
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		return

	var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
	var unit_ids: Array = (job.get("assigned_unit_ids", []) as Array).duplicate()
	if not unit_ids.has(unit_id):
		unit_ids.append(unit_id)
	job["assigned_unit_ids"] = unit_ids

	if mission_id > 0:
		var mission_ids: Array = (job.get("active_mission_ids", []) as Array).duplicate()
		if not mission_ids.has(mission_id):
			mission_ids.append(mission_id)
		job["active_mission_ids"] = mission_ids

	shared_scan_jobs_by_job_id[job_id] = job
	shared_scan_job_id_by_unit_id[unit_id] = job_id


func _get_shared_scan_job_for_unit(unit_id: int) -> Dictionary:
	var job_id: String = str(shared_scan_job_id_by_unit_id.get(unit_id, "")).strip_edges()
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		return {}
	return (shared_scan_jobs_by_job_id[job_id] as Dictionary).duplicate(true)


func _mark_shared_scan_job_completed(job_id: String, reward_given: bool) -> void:
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		return

	var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
	job["completed"] = true
	job["completion_applied"] = true
	job["reward_given"] = reward_given
	job["completed_at_msec"] = Time.get_ticks_msec()
	job["active_mission_ids"] = []
	shared_scan_jobs_by_job_id[job_id] = job

	for uid_variant: Variant in job.get("assigned_unit_ids", []):
		shared_scan_job_id_by_unit_id.erase(int(uid_variant))

	shared_scan_jobs_by_job_id.erase(job_id)


func _clear_shared_scan_job_for_unit(unit_id: int) -> void:
	var job_id: String = str(shared_scan_job_id_by_unit_id.get(unit_id, "")).strip_edges()
	shared_scan_job_id_by_unit_id.erase(unit_id)
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		return

	var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
	if bool(job.get("completed", false)):
		return

	var unit_ids: Array = (job.get("assigned_unit_ids", []) as Array).duplicate()
	unit_ids.erase(unit_id)
	if unit_ids.is_empty():
		shared_scan_jobs_by_job_id.erase(job_id)
		return

	job["assigned_unit_ids"] = unit_ids
	shared_scan_jobs_by_job_id[job_id] = job


func _clear_all_shared_scan_jobs() -> void:
	shared_scan_jobs_by_job_id.clear()
	shared_scan_job_id_by_unit_id.clear()


func get_shared_scan_job_debug_snapshot() -> Dictionary:
	var jobs_out: Dictionary = {}
	for job_id_variant: Variant in shared_scan_jobs_by_job_id.keys():
		var job_id: String = str(job_id_variant).strip_edges()
		if job_id.is_empty():
			continue
		var job: Dictionary = shared_scan_jobs_by_job_id[job_id_variant] as Dictionary
		if bool(job.get("completed", false)):
			continue
		var assigned: Array = job.get("assigned_unit_ids", []) as Array
		var missions: Array = job.get("active_mission_ids", []) as Array
		jobs_out[job_id] = {
			"target_id": str(job.get("target_id", "")),
			"target_scan_state": str(job.get("target_scan_state", "")),
			"assigned_unit_count": assigned.size(),
			"active_mission_count": missions.size(),
			"completed": bool(job.get("completed", false)),
			"completion_applied": bool(job.get("completion_applied", false)),
			"reward_given": bool(job.get("reward_given", false)),
			"progress": float(job.get("progress", 0.0)),
			"work_required": float(job.get("work_required", 0.0)),
			"completion_owner": SHARED_SCAN_JOB_COMPLETION_OWNER,
		}

	return {
		"enabled": true,
		"active_count": jobs_out.size(),
		"completion_owner": SHARED_SCAN_JOB_COMPLETION_OWNER,
		"jobs": jobs_out,
	}


func get_active_shared_scan_job_count() -> int:
	var count: int = 0
	for job_variant: Variant in shared_scan_jobs_by_job_id.values():
		if job_variant is Dictionary and not bool((job_variant as Dictionary).get("completed", false)):
			count += 1
	return count


func get_shared_scan_job_count_for_target(target_id: String) -> int:
	var tid: String = target_id.strip_edges()
	if tid.is_empty():
		return 0
	var count: int = 0
	for job_variant: Variant in shared_scan_jobs_by_job_id.values():
		if not job_variant is Dictionary:
			continue
		var job: Dictionary = job_variant as Dictionary
		if bool(job.get("completed", false)):
			continue
		if str(job.get("target_id", "")).strip_edges() == tid:
			count += 1
	return count


func has_active_shared_scan_job_for_target(target_id: String) -> bool:
	return not _get_active_shared_scan_job_id_for_target(target_id).is_empty()


func get_active_shared_scan_job_id_for_target(target_id: String) -> String:
	return _get_active_shared_scan_job_id_for_target(target_id)


func _get_active_shared_scan_job_id_for_target(target_id: String) -> String:
	var tid: String = target_id.strip_edges()
	if tid.is_empty():
		return ""

	for job_id_variant: Variant in shared_scan_jobs_by_job_id.keys():
		var job: Dictionary = shared_scan_jobs_by_job_id[job_id_variant] as Dictionary
		if bool(job.get("completed", false)) or bool(job.get("completion_applied", false)):
			continue
		if str(job.get("target_id", "")).strip_edges() == tid:
			return str(job_id_variant).strip_edges()

	return ""


func get_assigned_scan_drone_count_for_target(target_id: String) -> int:
	var job_id: String = _get_active_shared_scan_job_id_for_target(target_id)
	if not job_id.is_empty() and shared_scan_jobs_by_job_id.has(job_id):
		var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
		var assigned: Array = job.get("assigned_unit_ids", []) as Array
		return assigned.size()

	return get_active_scan_drone_count_for_target(target_id)


func can_assign_scan_drone_to_shared_job(target_id: String) -> Dictionary:
	var tid: String = target_id.strip_edges()
	var session_bid: String = _get_session_base_id()
	var system_id: String = GameSession.current_system_id.strip_edges()

	if tid.is_empty() or system_id.is_empty():
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_NONE, "")

	if not GameSession.has_established_base(session_bid):
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_NONE, "")

	if not GameSession.is_object_known(system_id, tid):
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_SCAN_NOT_DISCOVERED, "")

	var job_id: String = _get_active_shared_scan_job_id_for_target(tid)
	if job_id.is_empty():
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_NONE, "")

	var job: Dictionary = shared_scan_jobs_by_job_id.get(job_id, {}) as Dictionary
	if job.is_empty():
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_NONE, "")

	if bool(job.get("completed", false)) or bool(job.get("completion_applied", false)):
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_NONE, job_id)

	if _get_idle_drone() == null:
		return _assign_scan_gate_fail(GateUiTextDefinition.KEY_SCAN_NO_DRONE, job_id)

	return {
		"ok": true,
		"blocked_reason": "",
		"blocked_reason_key": GateUiTextDefinition.KEY_NONE,
		"job_id": job_id,
	}


func _assign_scan_gate_fail(reason_key: StringName, job_id: String) -> Dictionary:
	var key_str: String = str(reason_key).strip_edges()
	return {
		"ok": false,
		"blocked_reason": (
			GameSession.get_gate_text(reason_key) if not key_str.is_empty() else ""
		),
		"blocked_reason_key": reason_key,
		"job_id": job_id,
	}


func assign_scan_drone_to_shared_job(target_id: String) -> bool:
	var tid: String = target_id.strip_edges()
	if tid.is_empty():
		return false

	var assign_gate: Dictionary = can_assign_scan_drone_to_shared_job(tid)
	if not bool(assign_gate.get("ok", false)):
		var reason: String = str(assign_gate.get("blocked_reason", "")).strip_edges()
		if not reason.is_empty():
			push_warning("AutomationController: cannot assign scan drone — %s" % reason)
		return false

	var job_id: String = str(assign_gate.get("job_id", "")).strip_edges()
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		return false

	var target_node: Node2D = _get_target_node(tid)
	if target_node == null:
		return false

	var unit: AutomationUnit = _get_idle_drone()
	if unit == null:
		return false

	var unit_id: int = unit.get_instance_id()
	scan_drone_target_by_unit_id[unit_id] = tid
	_assign_scan_drone_to_shared_scan_job(job_id, unit_id, 0)

	var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
	var target_scan_state: String = str(job.get("target_scan_state", GameSession.SCAN_BASIC)).strip_edges()
	if target_scan_state.is_empty():
		target_scan_state = GameSession.SCAN_BASIC

	_disconnect_unit_signals(unit)
	_ensure_returned_to_base_connected(unit)

	if not unit.arrived_at_target.is_connected(_on_assign_scan_drone_arrived_at_target):
		unit.arrived_at_target.connect(_on_assign_scan_drone_arrived_at_target.bind(tid))

	unit.work_duration = GameSession.get_scan_duration_seconds_for_target_state(
		target_scan_state,
		_get_session_base_id(),
	)

	_scan_drone_start_outbound(unit, target_node)
	_request_automation_state_changed()
	return true


func _on_assign_scan_drone_arrived_at_target(unit: AutomationUnit, target_id: String) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var tid: String = target_id.strip_edges()
	var target_node: Node2D = _get_target_node(tid)

	if target_node == null:
		_scan_drone_return_to_base_orbit(unit)
		_request_automation_state_changed()
		return

	_disconnect_unit_signals(unit)
	unit.transfer_orbit_to_base(target_node)
	_start_scan_orbit_audio(unit, target_node)
	_request_automation_state_changed()


func _resolve_shared_scan_job_id_for_arrival(
	unit_id: int,
	mission_id: int,
	target_id: String,
	target_scan_state: String,
	scan_is_progression: bool,
) -> String:
	var job_id: String = str(shared_scan_job_id_by_unit_id.get(unit_id, "")).strip_edges()
	if not job_id.is_empty() and shared_scan_jobs_by_job_id.has(job_id):
		return job_id

	push_warning(
		"AutomationController: SharedScanJob missing on arrival — reconstructing (unit=%d target=%s)."
		% [unit_id, target_id]
	)
	var system_id: String = GameSession.current_system_id
	var base_id: String = _get_session_base_id()
	_reconstruct_shared_scan_job_for_restored_mission(
		system_id,
		target_id,
		base_id,
		target_scan_state,
		scan_is_progression,
		SHARED_SCAN_JOB_WORK_REQUIRED,
		unit_id,
		mission_id,
	)
	return str(shared_scan_job_id_by_unit_id.get(unit_id, "")).strip_edges()


func _mark_shared_scan_job_ready_for_completion(job_id: String) -> void:
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		return

	var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
	var work_required: float = maxf(
		float(job.get("work_required", SHARED_SCAN_JOB_WORK_REQUIRED)),
		SHARED_SCAN_JOB_WORK_REQUIRED,
	)
	job["work_required"] = work_required
	job["progress"] = work_required
	job["completed"] = true
	shared_scan_jobs_by_job_id[job_id] = job


func _apply_shared_scan_job_completion(job_id: String) -> bool:
	if job_id.is_empty() or not shared_scan_jobs_by_job_id.has(job_id):
		push_warning(
			"AutomationController: SharedScanJob completion apply failed — job missing (job_id=%s)."
			% job_id
		)
		return false

	var job: Dictionary = shared_scan_jobs_by_job_id[job_id] as Dictionary
	if bool(job.get("completion_applied", false)):
		push_warning(
			"AutomationController: duplicate SharedScanJob completion blocked (job_id=%s)."
			% job_id
		)
		return false

	if not bool(job.get("completed", false)):
		_mark_shared_scan_job_ready_for_completion(job_id)
		job = shared_scan_jobs_by_job_id[job_id] as Dictionary

	var target_id: String = str(job.get("target_id", "")).strip_edges()
	var target_scan_state: String = str(job.get("target_scan_state", "")).strip_edges()
	var scan_is_progression: bool = bool(job.get("scan_is_progression", true))
	var target_node: Node2D = _get_target_node(target_id)

	_complete_scan_mission(target_id, target_node, target_scan_state, scan_is_progression)
	_mark_shared_scan_job_completed(job_id, scan_is_progression)
	return true


func _process_shared_scan_job_arrival(
	unit: AutomationUnit,
	mission_id: int,
	target_id: String,
	target_scan_state: String,
	scan_is_progression: bool,
) -> bool:
	var unit_id: int = unit.get_instance_id()
	var job_id: String = _resolve_shared_scan_job_id_for_arrival(
		unit_id,
		mission_id,
		target_id,
		target_scan_state,
		scan_is_progression,
	)
	if job_id.is_empty():
		push_warning(
			"AutomationController: SharedScanJob arrival processing failed (target=%s)."
			% target_id
		)
		active_units_by_mission_id.erase(mission_id)
		return false

	var job: Dictionary = shared_scan_jobs_by_job_id.get(job_id, {}) as Dictionary
	if bool(job.get("completion_applied", false)):
		push_warning(
			"AutomationController: duplicate scan arrival blocked (job_id=%s target=%s)."
			% [job_id, target_id]
		)
		active_units_by_mission_id.erase(mission_id)
		return false

	_mark_shared_scan_job_ready_for_completion(job_id)
	return _apply_shared_scan_job_completion(job_id)


func _finalize_shared_scan_job_unit(
	unit: AutomationUnit,
	mission_id: int,
	target_id: String,
) -> void:
	active_units_by_mission_id.erase(mission_id)

	var target_node: Node2D = _get_target_node(target_id)
	if target_node == null:
		_scan_drone_return_to_base_orbit(unit)
		_request_automation_state_changed()
		return

	_disconnect_unit_signals(unit)
	unit.transfer_orbit_to_base(target_node)
	_start_scan_orbit_audio(unit, target_node)
	_request_automation_state_changed()


func _reconstruct_shared_scan_job_for_restored_mission(
	system_id: String,
	target_id: String,
	base_id: String,
	target_scan_state: String,
	scan_is_progression: bool,
	work_required: float,
	unit_id: int,
	mission_id: int,
) -> void:
	var job_id: String = _create_shared_scan_job_for_scan_mission(
		system_id,
		target_id,
		base_id,
		target_scan_state,
		scan_is_progression,
		work_required,
	)
	if job_id.is_empty():
		return
	_assign_scan_drone_to_shared_scan_job(job_id, unit_id, mission_id)


func _rebuild_shared_scan_jobs_from_active_scan_missions() -> void:
	var system_id: String = GameSession.current_system_id.strip_edges()
	if system_id.is_empty():
		return

	for mission_id_variant: Variant in active_units_by_mission_id.keys():
		var mission_id: int = int(mission_id_variant)
		var unit: AutomationUnit = active_units_by_mission_id[mission_id_variant] as AutomationUnit
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.unit_type != AutomationUnit.UnitType.DRONE:
			continue

		var unit_id: int = unit.get_instance_id()
		var target_id: String = str(scan_drone_target_by_unit_id.get(unit_id, "")).strip_edges()
		if target_id.is_empty():
			continue

		var mission_rec: Dictionary = GameSession.get_automation_mission(mission_id)
		if mission_rec.is_empty():
			continue
		if int(mission_rec.get("type", AutomationStore.MissionType.SCAN)) != AutomationStore.MissionType.SCAN:
			continue

		var base_id: String = str(mission_rec.get("base_id", _get_session_base_id())).strip_edges()
		var target_scan_state: String = str(mission_rec.get("target_scan_state", "")).strip_edges()
		var scan_is_progression: bool = bool(mission_rec.get("scan_is_progression", true))
		if target_scan_state.is_empty():
			var scan_gate: Dictionary = GameSession.get_scan_target_state_or_rescan_state(
				system_id,
				target_id,
				base_id,
			)
			target_scan_state = str(scan_gate.get("target_scan_state", GameSession.SCAN_BASIC)).strip_edges()
			if target_scan_state.is_empty():
				target_scan_state = GameSession.SCAN_BASIC
			scan_is_progression = bool(scan_gate.get("scan_is_progression", true))

		var job_id: String = _make_shared_scan_job_id(system_id, target_id, target_scan_state)
		if job_id.is_empty():
			continue

		if not shared_scan_jobs_by_job_id.has(job_id):
			_create_shared_scan_job_for_scan_mission(
				system_id,
				target_id,
				base_id,
				target_scan_state,
				scan_is_progression,
				SHARED_SCAN_JOB_WORK_REQUIRED,
			)

		var job: Dictionary = shared_scan_jobs_by_job_id.get(job_id, {}) as Dictionary
		if bool(job.get("completion_applied", false)):
			continue

		_assign_scan_drone_to_shared_scan_job(job_id, unit_id, mission_id)


func _sync_shared_scan_job_assignments_from_target_map() -> void:
	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var unit_id: int = int(unit_id_variant)
		var target_id: String = str(scan_drone_target_by_unit_id.get(unit_id_variant, "")).strip_edges()
		if target_id.is_empty():
			continue

		var job_id: String = _get_active_shared_scan_job_id_for_target(target_id)
		if job_id.is_empty():
			continue

		var job: Dictionary = shared_scan_jobs_by_job_id.get(job_id, {}) as Dictionary
		var assigned: Array = job.get("assigned_unit_ids", []) as Array
		if assigned.has(unit_id):
			continue

		var mission_id: int = 0
		for mission_id_variant: Variant in active_units_by_mission_id.keys():
			var assigned_unit: AutomationUnit = active_units_by_mission_id[mission_id_variant] as AutomationUnit
			if assigned_unit != null and assigned_unit.get_instance_id() == unit_id:
				mission_id = int(mission_id_variant)
				break

		_assign_scan_drone_to_shared_scan_job(job_id, unit_id, mission_id)


func _validate_shared_scan_jobs_after_restore() -> void:
	_rebuild_shared_scan_jobs_from_active_scan_missions()
	_sync_shared_scan_job_assignments_from_target_map()

	var jobs_to_remove: Array[String] = []
	for job_id_variant: Variant in shared_scan_jobs_by_job_id.keys():
		var job_id: String = str(job_id_variant).strip_edges()
		if job_id.is_empty():
			continue

		var job: Dictionary = shared_scan_jobs_by_job_id[job_id_variant] as Dictionary
		if bool(job.get("completion_applied", false)):
			jobs_to_remove.append(job_id)
			continue

		var has_live_scan_mission: bool = false
		for mission_id_variant: Variant in job.get("active_mission_ids", []):
			var mission_id: int = int(mission_id_variant)
			if mission_id <= 0:
				continue
			if not active_units_by_mission_id.has(mission_id):
				continue
			if GameSession.get_automation_mission(mission_id).is_empty():
				continue
			has_live_scan_mission = true
			break

		if not has_live_scan_mission:
			var assigned_units: Array = job.get("assigned_unit_ids", []) as Array
			if assigned_units.is_empty():
				jobs_to_remove.append(job_id)

	for remove_id: String in jobs_to_remove:
		var remove_job: Dictionary = shared_scan_jobs_by_job_id.get(remove_id, {}) as Dictionary
		for uid_variant: Variant in remove_job.get("assigned_unit_ids", []):
			shared_scan_job_id_by_unit_id.erase(int(uid_variant))
		shared_scan_jobs_by_job_id.erase(remove_id)


func _unit_has_active_scan_mission(unit: AutomationUnit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false

	for assigned_unit: Variant in active_units_by_mission_id.values():
		if assigned_unit == unit:
			return true

	return false


func _scan_drone_support_orbit_target_id(unit: AutomationUnit) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""

	if unit.state != AutomationUnit.State.ORBITING_BASE:
		return ""

	if unit.base_node == null or not is_instance_valid(unit.base_node):
		return ""

	var anchor_id: String = _get_object_id_from_node(unit.base_node).strip_edges()
	var session_home_id: String = _get_session_base_id().strip_edges()

	if anchor_id.is_empty() or anchor_id == session_home_id:
		return ""

	return anchor_id


func _is_scan_drone_in_support_orbit_at_target(
	unit: AutomationUnit,
	normalized_target_id: String,
) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false

	if unit.unit_type != AutomationUnit.UnitType.DRONE:
		return false

	if normalized_target_id.is_empty():
		return false

	if _unit_has_active_scan_mission(unit):
		return false

	return _scan_drone_support_orbit_target_id(unit) == normalized_target_id


func _is_scan_drone_providing_mining_support_at_target(
	unit: AutomationUnit,
	normalized_target_id: String,
) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false

	if unit.unit_type != AutomationUnit.UnitType.DRONE:
		return false

	if normalized_target_id.is_empty():
		return false

	var session_home_id: String = _get_session_base_id().strip_edges()
	var state: AutomationUnit.State = unit.state

	if (
		state == AutomationUnit.State.IDLE
		or state == AutomationUnit.State.RETURNING
		or state == AutomationUnit.State.TRAVEL_TO_TARGET
		or state == AutomationUnit.State.APPROACH_ORBIT
	):
		return false

	if state == AutomationUnit.State.WORKING:
		if unit.target_node == null or not is_instance_valid(unit.target_node):
			return false
		return _get_object_id_from_node(unit.target_node).strip_edges() == normalized_target_id

	if state == AutomationUnit.State.ORBITING_BASE:
		if unit.base_node == null or not is_instance_valid(unit.base_node):
			return false
		var anchor_id: String = _get_object_id_from_node(unit.base_node).strip_edges()
		if anchor_id.is_empty() or anchor_id == session_home_id:
			return false
		return anchor_id == normalized_target_id

	return false


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
	var normalized_target_id: String = target_id.strip_edges()

	if normalized_target_id.is_empty():
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

	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var assigned_target: String = str(scan_drone_target_by_unit_id.get(unit_id, "")).strip_edges()

		if assigned_target != normalized_target_id:
			continue

		var mission_drone := instance_from_id(unit_id) as AutomationUnit

		if mission_drone == null or not is_instance_valid(mission_drone):
			continue

		_abort_scan_mission_for_unit(mission_drone)
		_disconnect_unit_signals(mission_drone)
		_ensure_returned_to_base_connected(mission_drone)
		_scan_drone_recall_to_base(mission_drone, home_base_node)
		_request_automation_state_changed()
		return true

	for drone in idle_drones:
		if drone == null or not is_instance_valid(drone):
			continue

		if not drone.is_available():
			continue

		if drone.base_node == null or not is_instance_valid(drone.base_node):
			continue

		if _get_object_id_from_node(drone.base_node).strip_edges() != normalized_target_id:
			continue

		var support_uid: int = drone.get_instance_id()

		if scan_drone_target_by_unit_id.has(support_uid):
			_abort_scan_mission_for_unit(drone)

		_disconnect_unit_signals(drone)
		_ensure_returned_to_base_connected(drone)
		_scan_drone_recall_to_base(drone, home_base_node)
		_request_automation_state_changed()
		return true

	return false


func _abort_scan_mission_for_unit(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	for mission_id_variant: Variant in active_units_by_mission_id.keys():
		if active_units_by_mission_id[mission_id_variant] != unit:
			continue

		var mission_id := int(mission_id_variant)
		active_units_by_mission_id.erase(mission_id_variant)

		if GameSession.automation.missions.has(mission_id):
			GameSession.automation.missions.erase(mission_id)

		break

	_clear_shared_scan_job_for_unit(unit.get_instance_id())


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

	for unit_id_variant: Variant in mining_ship_runtime_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})

		if runtime.is_empty():
			continue

		if str(runtime.get("target_id", "")) != target_id:
			continue

		var ship := instance_from_id(unit_id) as AutomationUnit

		if ship == null or not is_instance_valid(ship):
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
			_mining_ship_recall_to_base(selected_ship, home_base_node)
		MiningShipStatus.TO_BASE:
			_mining_ship_recall_to_base(selected_ship, home_base_node)
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

	var support_count: int = get_scan_drone_support_effect_count_for_target(target_id)
	if support_count <= 0:
		return 0.0

	var per_pct: float = float(
		GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(bonus_base_id)
	)
	return (float(support_count) * per_pct) / 100.0


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

		_clear_shared_scan_job_for_unit(drone_uid_miss)

		_stop_scan_orbit_audio(unit)
		_request_automation_state_changed()
		return

	var target_scan_state: String = str(mission.get("target_scan_state", "")).strip_edges()
	var scan_is_progression: bool = bool(mission.get("scan_is_progression", true))
	var completion_applied: bool = _process_shared_scan_job_arrival(
		unit,
		mission_id,
		target_id,
		target_scan_state,
		scan_is_progression,
	)
	if completion_applied:
		_finalize_shared_scan_job_unit(unit, mission_id, target_id)
	else:
		active_units_by_mission_id.erase(mission_id)
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
			_mining_ship_recall_to_base(unit, home_fallback)

		_request_automation_state_changed()
		return

	unit.transfer_orbit_to_base(target_node)

	runtime["status"] = MiningShipStatus.MINING
	mining_ship_runtime_by_unit_id[unit_id] = runtime
	_play_mining_ship_arrive_audio(unit, target_node)
	_request_automation_state_changed()


func _complete_scan_mission(
	target_id: String,
	target_node: Node2D,
	target_scan_state: String = "",
	scan_is_progression: bool = true,
) -> void:
	if target_id.is_empty():
		return

	if GameSession.current_system_id.is_empty():
		return

	if target_node == null:
		target_node = _get_target_node(target_id)

	if not scan_is_progression:
		if target_node != null:
			_play_automation_sfx(&"scan_complete", target_node)
		return

	var session_base_id: String = _get_session_base_id()
	var unlocked_scan_layer: int = GameSession.get_unlocked_scan_layer_for_base(session_base_id)
	var completion_state: String = target_scan_state.strip_edges()
	if completion_state.is_empty():
		completion_state = GameSession.scan_completion_state_for_unlocked_scan_layer(
			unlocked_scan_layer
		)

	GameSession.set_object_scan_state(
		GameSession.current_system_id,
		target_id,
		completion_state
	)

	GameSession.grant_scan_survey_data_reward(session_base_id, completion_state)

	if target_node == null:
		return

	var definition: Resource = _get_definition_from_target_node(target_node)

	if definition == null:
		return

	var visible_resources: Array = _get_visible_resource_entries_for_scan_state(
		definition,
		unlocked_scan_layer,
		completion_state
	)

	GameSession.ensure_object_resources_initialized(
		GameSession.current_system_id,
		target_id,
		visible_resources
	)
	GameSession.ensure_mining_resources_for_object(GameSession.current_system_id, target_id)

	_play_automation_sfx(&"scan_complete", target_node)
	if not visible_resources.is_empty():
		_play_automation_sfx(&"resource_revealed", target_node)


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
				var cargo_cap_min: int = int(runtime.get("cargo_capacity", _get_mining_cargo_capacity_base()))

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
						_mining_ship_recall_to_base(unit, home_full_c)

					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				var base_id_min: String = _runtime_base_id_with_session_fallback(runtime)
				if cargo_total_min > 0 and GameSession.get_base_storage_free(base_id_min) <= 0:
					runtime["blocked_reason"] = GameSession.get_base_storage_blocked_reason_full()
					var home_storage_full: Node2D = _get_target_node(base_id_min)
					if home_storage_full != null:
						runtime["status"] = MiningShipStatus.TO_BASE
						_mining_ship_recall_to_base(unit, home_storage_full)
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
							_mining_ship_recall_to_base(unit, home_empty_src)
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
							_mining_ship_recall_to_base(unit, home_ws)
					else:
						runtime["loop_active"] = false
						mining_ship_runtime_by_unit_id[unit_id] = runtime
						_release_mining_ship_runtime(unit_id)
						continue

					mining_ship_runtime_by_unit_id[unit_id] = runtime
					continue

				var mining_rate_min: float = float(
					runtime.get(
						"mining_rate_per_second",
						_get_mining_rate_for_base(_runtime_base_id_with_session_fallback(runtime)),
					)
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

					var remaining_amt: int = 0
					if not sid_min.is_empty() and not target_id_min.is_empty():
						remaining_amt = GameSession.get_remaining_resource_amount(
							sid_min,
							target_id_min,
							rid,
						)

					requested = mini(mini(requested, space_left_min), remaining_amt)

					if requested <= 0:
						rem_dict_min[rid] = acc
						continue

					var extracted: int = 0

					if not sid_min.is_empty() and not target_id_min.is_empty():
						extracted = GameSession.extract_resource_amount(
							sid_min,
							target_id_min,
							rid,
							requested,
						)

					acc -= float(extracted)
					if acc < 0.0:
						acc = 0.0

					rem_dict_min[rid] = acc

					if extracted > 0:
						var cur_c: int = int(cargo_res_min.get(rid, 0))
						cargo_res_min[rid] = cur_c + extracted
						cargo_total_min += extracted
						space_left_min = maxi(0, cargo_cap_min - cargo_total_min)
						_play_mining_resource_tick_sfx(unit)

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
						var mining_done_node: Node2D = target_node_min if target_node_min != null else unit
						_play_automation_sfx(&"mining_complete", mining_done_node)
						runtime["status"] = MiningShipStatus.TO_BASE
						_mining_ship_recall_to_base(unit, home_cap)

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
							var mining_done_node_pc: Node2D = target_node_min if target_node_min != null else unit
							_play_automation_sfx(&"mining_complete", mining_done_node_pc)
							runtime["status"] = MiningShipStatus.TO_BASE
							_mining_ship_recall_to_base(unit, home_pc)
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
					runtime.get("unload_duration", _get_mining_unload_duration_seconds_base())
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
							if not bool(runtime.get("cargo_unload_sfx_played", false)):
								runtime["cargo_unload_sfx_played"] = true
								_play_automation_sfx(&"cargo_unload", _audio_node_for_base(base_id_ul, unit))

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
						runtime["blocked_reason"] = ""

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
									_mining_ship_start_outbound(unit, target_node_ul)
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
						runtime["blocked_reason"] = GameSession.get_base_storage_blocked_reason_full()
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
					runtime["blocked_reason"] = ""

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
								_mining_ship_start_outbound(unit_ws, target_node_ws)
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

	var base_id_rb: String = _runtime_base_id_with_session_fallback(runtime)

	if total_rb <= 0:
		runtime["unload_timer"] = 0.0
	elif GameSession.get_base_storage_free(base_id_rb) <= 0:
		runtime["blocked_reason"] = GameSession.get_base_storage_blocked_reason_full()
		_mining_ship_enter_waiting_for_storage(unit, runtime)
		mining_ship_runtime_by_unit_id[unit_id] = runtime
		_request_automation_state_changed()
		return
	else:
		runtime["unload_timer"] = float(runtime.get("unload_duration", _get_mining_unload_duration_seconds_base()))

	runtime["status"] = MiningShipStatus.UNLOADING
	runtime["blocked_reason"] = ""
	runtime["cargo_unload_sfx_played"] = false
	mining_ship_runtime_by_unit_id[unit_id] = runtime

	if unit.base_node != null and is_instance_valid(unit.base_node):
		unit.transfer_orbit_to_base(unit.base_node)

	_play_mining_ship_arrive_audio(
		unit,
		_audio_node_for_base(_runtime_base_id_with_session_fallback(runtime), unit),
	)

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
	runtime["blocked_reason"] = GameSession.get_base_storage_blocked_reason_full()

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

	_register_idle_mining_ship(unit)
	_request_automation_state_changed()


func _register_idle_drone(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit.unit_type != AutomationUnit.UnitType.DRONE:
		return

	for existing: AutomationUnit in idle_drones:
		if existing == unit:
			return

	idle_drones.append(unit)


func _register_idle_mining_ship(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit.unit_type != AutomationUnit.UnitType.MINING_SHIP:
		return

	for existing: AutomationUnit in idle_mining_ships:
		if existing == unit:
			return

	idle_mining_ships.append(unit)


func _on_base_resources_changed_survey_probes(base_id: String) -> void:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		return
	var session_home: String = _session_primary_base_body_id.strip_edges()
	if session_home.is_empty() or bid != session_home:
		return
	ensure_survey_probe_units_for_base(bid)


func _spawn_survey_probe_unit() -> SurveyProbeUnit:
	if automation_root == null or SURVEY_PROBE_SCENE == null:
		return null
	var unit := SURVEY_PROBE_SCENE.instantiate() as SurveyProbeUnit
	if unit == null:
		return null
	automation_root.add_child(unit)
	return unit


func _prune_idle_survey_probes() -> void:
	var kept: Array[SurveyProbeUnit] = []
	for unit: SurveyProbeUnit in idle_survey_probes:
		if unit == null or not is_instance_valid(unit):
			continue
		if survey_probe_busy_unit_ids.has(unit.get_instance_id()):
			continue
		if unit.is_available():
			kept.append(unit)
	idle_survey_probes = kept


func _count_idle_survey_probes_at_home(base_id: String) -> int:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	var count := 0
	for unit: SurveyProbeUnit in idle_survey_probes:
		if unit == null or not is_instance_valid(unit):
			continue
		if survey_probe_busy_unit_ids.has(unit.get_instance_id()):
			continue
		if not unit.is_available():
			continue
		if unit.base_node == null or not is_instance_valid(unit.base_node):
			continue
		if _get_object_id_from_node(unit.base_node) != bid:
			continue
		count += 1
	return count


func _trim_excess_idle_survey_probes(wanted_idle: int, base_id: String) -> void:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	while _count_idle_survey_probes_at_home(bid) > wanted_idle:
		var removed := false
		for i in range(idle_survey_probes.size() - 1, -1, -1):
			var unit: SurveyProbeUnit = idle_survey_probes[i]
			if unit == null or not is_instance_valid(unit):
				idle_survey_probes.remove_at(i)
				removed = true
				break
			if survey_probe_busy_unit_ids.has(unit.get_instance_id()):
				continue
			if not unit.is_available():
				continue
			if unit.base_node == null or _get_object_id_from_node(unit.base_node) != bid:
				continue
			idle_survey_probes.remove_at(i)
			unit.queue_free()
			removed = true
			break
		if not removed:
			break


func _take_idle_survey_probe_from_list(base_id: String) -> SurveyProbeUnit:
	var bid: String = base_id.strip_edges()
	if bid.is_empty():
		bid = _get_session_base_id()

	for i in idle_survey_probes.size():
		var unit: SurveyProbeUnit = idle_survey_probes[i]
		if unit == null or not is_instance_valid(unit):
			continue
		if survey_probe_busy_unit_ids.has(unit.get_instance_id()):
			continue
		if not unit.is_available():
			continue
		if unit.base_node == null or not is_instance_valid(unit.base_node):
			continue
		if _get_object_id_from_node(unit.base_node) != bid:
			continue
		idle_survey_probes.remove_at(i)
		return unit
	return null


func _register_idle_survey_probe(unit: SurveyProbeUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if survey_probe_busy_unit_ids.has(unit.get_instance_id()):
		return
	for existing: SurveyProbeUnit in idle_survey_probes:
		if existing == unit:
			return
	idle_survey_probes.append(unit)


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

	_stop_scan_orbit_audio(unit)
	_play_scan_drone_arrive_audio(unit, _audio_node_for_base(_get_session_base_id(), unit))

	if not scan_drone_target_by_unit_id.has(drone_uid_rb):
		return

	scan_drone_target_by_unit_id.erase(drone_uid_rb)

	for mission_id_variant: Variant in active_units_by_mission_id.keys():
		var assigned_unit: Variant = active_units_by_mission_id[mission_id_variant]

		if assigned_unit == unit:
			active_units_by_mission_id.erase(mission_id_variant)
			break

	_register_idle_drone(unit)
	_request_automation_state_changed()


func _disconnect_unit_signals(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit.unit_type == AutomationUnit.UnitType.DRONE:
		_stop_scan_orbit_audio(unit)

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


func _get_visible_resource_entries_for_scan_state(
	definition: Resource,
	unlocked_scan_layer: int,
	scan_state: String
) -> Array:
	var result: Array = []

	if definition == null:
		return result

	var rank: int = GameSession.scan_state_rank(scan_state)

	if rank >= GameSession.scan_state_rank(GameSession.SCAN_BASIC):
		result.append_array(
			_get_resource_entries_for_tier(
				definition,
				&"get_basic_scan_resources",
				GameSession.SCANNER_BASIC,
				unlocked_scan_layer
			)
		)

	if rank >= GameSession.scan_state_rank(GameSession.SCAN_DEEP):
		result.append_array(
			_get_resource_entries_for_tier(
				definition,
				&"get_deep_scan_resources",
				GameSession.SCANNER_DEEP,
				unlocked_scan_layer
			)
		)

	if rank >= GameSession.scan_state_rank(GameSession.SCAN_SPECIAL):
		result.append_array(
			_get_resource_entries_for_tier(
				definition,
				&"get_special_scan_resources",
				GameSession.SCANNER_SPECIAL,
				unlocked_scan_layer
			)
		)

	return result


func _get_resource_entries_for_tier(
	definition: Resource,
	method_name: StringName,
	resource_tier: String,
	unlocked_scan_layer: int
) -> Array:
	var result: Array = []

	if definition == null:
		return result

	if not definition.has_method(method_name):
		return result

	if not _can_unlocked_scan_layer_see_resource_tier(unlocked_scan_layer, resource_tier):
		return result

	var entries: Array = definition.call(method_name)

	for entry: Variant in entries:
		result.append(entry)

	return result


func _can_unlocked_scan_layer_see_resource_tier(
	unlocked_scan_layer: int,
	resource_tier: String
) -> bool:
	return unlocked_scan_layer >= GameSession.resource_tier_string_to_layer_int(resource_tier)


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


func _get_allowed_scanned_entries_for_object_scan(
	definition: Resource,
	scan_state: String,
	unlocked_mining_layer: int = ScannedResourceEntry.Layer.BASIC
) -> Array:
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

	return _filter_scanned_entries_for_mining_layer(out, unlocked_mining_layer)


func _filter_scanned_entries_for_mining_layer(entries: Array, unlocked_mining_layer: int) -> Array:
	var filtered: Array = []
	for entry_variant: Variant in entries:
		var entry: ScannedResourceEntry = entry_variant as ScannedResourceEntry
		if entry == null:
			continue
		if int(entry.layer) > unlocked_mining_layer:
			continue
		filtered.append(entry)
	return filtered


func _list_mining_weighted_candidates(
	system_id: String,
	object_id: String,
	definition: Resource,
	scan_state: String
) -> Array:
	var result: Array = []

	if system_id.is_empty() or object_id.is_empty():
		return result

	var entries: Array = _get_allowed_scanned_entries_for_object_scan(
		definition,
		scan_state,
		GameSession.get_unlocked_mining_layer_for_base(_get_session_base_id())
	)
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


func to_save_data() -> Dictionary:
	var data: Dictionary = _save_service.build_runtime_save_data(
		GameSession.current_system_id,
		_session_primary_base_body_id,
		_get_session_base_id(),
		scan_drone_target_by_unit_id,
		active_units_by_mission_id,
		mining_ship_runtime_by_unit_id,
		Callable(self, "_resolve_automation_unit_from_instance_id"),
		Callable(self, "_get_object_id_from_node"),
		Callable(self, "_runtime_base_id_with_session_fallback"),
	)
	return data


func _resolve_automation_unit_from_instance_id(unit_id: int) -> AutomationUnit:
	var instance := instance_from_id(unit_id)
	return instance as AutomationUnit


func apply_automation_save_if_pending() -> void:
	if not GameSession.has_automation_runtime_pending():
		return

	# Always consume pending data so it is not reapplied in another system scene.
	var runtime: Dictionary = GameSession.take_automation_runtime_pending()
	await _restore_automation_runtime_when_ready(runtime)


func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	var saved_system_id: String = str(data.get("system_id", "")).strip_edges()
	var current_sid: String = GameSession.current_system_id.strip_edges()

	if not saved_system_id.is_empty() and not current_sid.is_empty() and saved_system_id != current_sid:
		push_warning(
			"AutomationController: automation restore skipped (system_id mismatch saved=%s current=%s)."
			% [saved_system_id, current_sid]
		)
		return

	var saved_base_id: String = str(data.get("primary_base_id", "")).strip_edges()
	if _session_primary_base_body_id.is_empty() and not saved_base_id.is_empty():
		_session_primary_base_body_id = saved_base_id

	var session_base_id: String = _session_primary_base_body_id.strip_edges()

	if not saved_base_id.is_empty() and not session_base_id.is_empty() and saved_base_id != session_base_id:
		push_warning(
			"AutomationController: automation restore skipped (base_id mismatch saved=%s session=%s)."
			% [saved_base_id, session_base_id]
		)
		return

	for scan_job_variant: Variant in data.get("scan_missions", []):
		if scan_job_variant is Dictionary:
			_restore_scan_mission(scan_job_variant as Dictionary)

	for mining_job_variant: Variant in data.get("mining_missions", []):
		if mining_job_variant is Dictionary:
			_restore_mining_mission(mining_job_variant as Dictionary)

	_restart_automation_audio_after_restore()
	reapply_session_base_unit_upgrade_effects()
	_validate_shared_scan_jobs_after_restore()

	_request_automation_state_changed()


func _restore_automation_runtime_when_ready(runtime: Dictionary) -> void:
	if runtime.is_empty():
		return

	_clear_automation_visuals_and_mission_state()
	apply_save_data(runtime)

	var expected_jobs: int = _expected_automation_job_count_in_runtime(runtime)

	if expected_jobs > 0 and _count_restored_automation_jobs() == 0:
		await get_tree().process_frame
		_clear_automation_visuals_and_mission_state()
		apply_save_data(runtime)

	if expected_jobs > 0 and _count_restored_automation_jobs() == 0:
		push_warning(
			"AutomationController: mission restore failed after load; no active automation jobs restored."
		)

	_validate_shared_scan_jobs_after_restore()
	reapply_session_base_unit_upgrade_effects()


func _expected_automation_job_count_in_runtime(runtime: Dictionary) -> int:
	var scan_jobs: Variant = runtime.get("scan_missions", [])
	var mining_jobs: Variant = runtime.get("mining_missions", [])
	var scan_count := 0
	var mining_count := 0

	if scan_jobs is Array:
		scan_count = (scan_jobs as Array).size()

	if mining_jobs is Array:
		mining_count = (mining_jobs as Array).size()

	return scan_count + mining_count


func _count_restored_automation_jobs() -> int:
	return scan_drone_target_by_unit_id.size() + mining_ship_runtime_by_unit_id.size()


func _clear_automation_visuals_and_mission_state() -> void:
	if automation_root != null:
		for child: Node in automation_root.get_children():
			if child is AutomationUnit:
				_stop_scan_orbit_audio(child as AutomationUnit)

	active_units_by_mission_id.clear()
	scan_drone_target_by_unit_id.clear()
	_clear_all_shared_scan_jobs()
	mining_ship_runtime_by_unit_id.clear()
	idle_drones.clear()
	idle_mining_ships.clear()

	if automation_root == null:
		return

	for child: Node in automation_root.get_children():
		if child is AutomationUnit:
			child.queue_free()


func _global_position_from_save_dict(job: Dictionary) -> Vector2:
	var pos_variant: Variant = job.get("global_position", null)

	if pos_variant is Vector2:
		return pos_variant as Vector2

	if pos_variant is Dictionary:
		var pos_dict: Dictionary = pos_variant as Dictionary
		return Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))

	return Vector2.INF


func _restore_scan_mission(job: Dictionary) -> void:
	var target_id: String = str(job.get("target_id", "")).strip_edges()

	if target_id.is_empty():
		return

	var home_base_id: String = str(job.get("base_id", _get_session_base_id())).strip_edges()
	var home_node: Node2D = _get_target_node(home_base_id)
	var target_node: Node2D = _get_target_node(target_id)

	if home_node == null or target_node == null:
		push_warning(
			"AutomationController: scan mission restore skipped (nodes missing base=%s target=%s)."
			% [home_base_id, target_id]
		)
		_fallback_scan_job_to_idle(home_base_id, home_node)
		return

	var orbit_anchor_id: String = str(job.get("orbit_anchor_id", home_base_id)).strip_edges()
	var orbit_node: Node2D = _get_target_node(orbit_anchor_id)

	if orbit_node == null:
		orbit_node = home_node

	var unit := _spawn_unit(DRONE_SCENE)

	if unit == null:
		push_warning("AutomationController: scan mission restore failed (could not spawn drone).")
		_fallback_scan_job_to_idle(home_base_id, home_node)
		return

	unit.work_duration = maxf(float(job.get("work_duration", _get_scan_duration_seconds_base())), 0.001)

	var mission_id: int = int(job.get("mission_id", 0))
	var scan_reveal_done: bool = bool(job.get("scan_reveal_done", mission_id <= 0))
	var saved_position: Vector2 = _global_position_from_save_dict(job)

	_disconnect_unit_signals(unit)
	_ensure_returned_to_base_connected(unit)

	var unit_id: int = unit.get_instance_id()
	scan_drone_target_by_unit_id[unit_id] = target_id

	var target_scan_state: String = GameSession.SCAN_BASIC
	var scan_is_progression: bool = true
	if mission_id > 0:
		var mission_rec_pre: Dictionary = GameSession.get_automation_mission(mission_id)
		target_scan_state = str(mission_rec_pre.get("target_scan_state", "")).strip_edges()
		scan_is_progression = bool(mission_rec_pre.get("scan_is_progression", true))
	if target_scan_state.is_empty():
		var scan_gate: Dictionary = GameSession.get_scan_target_state_or_rescan_state(
			GameSession.current_system_id,
			target_id,
			home_base_id,
		)
		target_scan_state = str(scan_gate.get("target_scan_state", GameSession.SCAN_BASIC)).strip_edges()
		if target_scan_state.is_empty():
			target_scan_state = GameSession.SCAN_BASIC
		scan_is_progression = bool(scan_gate.get("scan_is_progression", true))

	if not scan_reveal_done and mission_id > 0:
		var mission_rec: Dictionary = GameSession.get_automation_mission(mission_id)

		if mission_rec.is_empty():
			GameSession.automation.restore_mission_record(
				mission_id,
				{
					"type": AutomationStore.MissionType.SCAN,
					"base_id": home_base_id,
					"target_id": target_id,
					"target_scan_state": target_scan_state,
					"scan_is_progression": scan_is_progression,
				}
			)

		active_units_by_mission_id[mission_id] = unit

		if not unit.arrived_at_target.is_connected(_on_scan_drone_arrived_at_target):
			unit.arrived_at_target.connect(_on_scan_drone_arrived_at_target.bind(mission_id, target_id))

		_reconstruct_shared_scan_job_for_restored_mission(
			GameSession.current_system_id,
			target_id,
			home_base_id,
			target_scan_state,
			scan_is_progression,
			SHARED_SCAN_JOB_WORK_REQUIRED,
			unit_id,
			mission_id,
		)

	var active_job_id: String = _get_active_shared_scan_job_id_for_target(target_id)
	if not active_job_id.is_empty():
		var sync_mission_id: int = 0
		if not scan_reveal_done and mission_id > 0:
			sync_mission_id = mission_id
		else:
			sync_mission_id = 0
		_assign_scan_drone_to_shared_scan_job(active_job_id, unit_id, sync_mission_id)
		if sync_mission_id <= 0:
			var restored_state: AutomationUnit.State = (
				int(job.get("unit_state", AutomationUnit.State.TRAVEL_TO_TARGET))
				as AutomationUnit.State
			)
			if restored_state != AutomationUnit.State.ORBITING_BASE:
				if not unit.arrived_at_target.is_connected(_on_assign_scan_drone_arrived_at_target):
					unit.arrived_at_target.connect(
						_on_assign_scan_drone_arrived_at_target.bind(target_id)
					)

	unit.restore_mission_visual_state(
		int(job.get("unit_state", AutomationUnit.State.TRAVEL_TO_TARGET)) as AutomationUnit.State,
		home_node,
		orbit_node,
		target_node,
		float(job.get("work_timer", 0.0)),
		float(job.get("work_duration", unit.work_duration)),
		float(job.get("travel_progress", 0.0)),
		saved_position,
	)
	unit.apply_saved_scan_motion_from_job(job)
	_apply_scan_drone_upgrade_stats_to_unit(unit, home_base_id)


func _restore_mining_mission(job: Dictionary) -> void:
	var target_id: String = str(job.get("target_id", "")).strip_edges()

	if target_id.is_empty():
		return

	var home_base_id: String = str(job.get("base_id", _get_session_base_id())).strip_edges()
	var home_node: Node2D = _get_target_node(home_base_id)
	var target_node: Node2D = _get_target_node(target_id)

	if home_node == null or target_node == null:
		push_warning(
			"AutomationController: mining mission restore skipped (nodes missing base=%s target=%s)."
			% [home_base_id, target_id]
		)
		_fallback_mining_job_to_idle(home_base_id, home_node)
		return

	var orbit_anchor_id: String = str(job.get("orbit_anchor_id", home_base_id)).strip_edges()
	var orbit_node: Node2D = _get_target_node(orbit_anchor_id)

	if orbit_node == null:
		orbit_node = home_node

	var unit := _spawn_unit(MINING_SHIP_SCENE)

	if unit == null:
		push_warning("AutomationController: mining mission restore failed (could not spawn mining ship).")
		_fallback_mining_job_to_idle(home_base_id, home_node)
		return

	unit.work_duration = maxf(float(job.get("work_duration", DEFAULT_MINING_DURATION)), 0.001)
	_disconnect_unit_signals(unit)

	if not unit.arrived_at_target.is_connected(_on_mining_ship_arrived_at_target):
		unit.arrived_at_target.connect(_on_mining_ship_arrived_at_target)

	_ensure_returned_to_base_connected(unit)

	var runtime: Dictionary = _save_service.sanitize_dictionary_for_save(job)
	runtime.erase("unit_state")
	runtime.erase("work_timer")
	runtime.erase("work_duration")
	runtime.erase("travel_progress")
	runtime.erase("orbit_anchor_id")
	runtime.erase("global_position")
	runtime.erase("scan_reveal_done")

	if not runtime.has("system_id") or str(runtime.get("system_id", "")).is_empty():
		runtime["system_id"] = GameSession.current_system_id

	if not runtime.has("status"):
		runtime["status"] = MiningShipStatus.TO_TARGET

	var unit_id: int = unit.get_instance_id()
	_apply_mining_runtime_upgrade_stats(runtime, home_base_id)
	mining_ship_runtime_by_unit_id[unit_id] = runtime

	var saved_position: Vector2 = _global_position_from_save_dict(job)

	unit.restore_mission_visual_state(
		int(job.get("unit_state", AutomationUnit.State.TRAVEL_TO_TARGET)) as AutomationUnit.State,
		home_node,
		orbit_node,
		target_node,
		float(job.get("work_timer", 0.0)),
		float(job.get("work_duration", unit.work_duration)),
		float(job.get("travel_progress", 0.0)),
		saved_position,
	)

	var status_after: int = int(runtime.get("status", MiningShipStatus.TO_TARGET))

	if status_after == MiningShipStatus.TO_BASE:
		if unit.state != AutomationUnit.State.RETURNING:
			unit.recall_to_base(home_node)
	elif status_after == MiningShipStatus.MINING:
		if unit.state != AutomationUnit.State.WORKING:
			unit.transfer_orbit_to_base(target_node)
	elif status_after == MiningShipStatus.UNLOADING or status_after == MiningShipStatus.WAITING_FOR_STORAGE:
		if unit.state != AutomationUnit.State.WORKING:
			unit.transfer_orbit_to_base(home_node)


func _fallback_scan_job_to_idle(home_base_id: String, home_node: Node2D) -> void:
	if home_node == null:
		home_node = _get_target_node(home_base_id.strip_edges())

	if home_node == null:
		return

	var unit := _spawn_unit(DRONE_SCENE)

	if unit == null:
		return

	unit.work_duration = _get_scan_work_duration_for_base(home_base_id)
	_disconnect_unit_signals(unit)
	_ensure_returned_to_base_connected(unit)
	unit.start_orbiting_base(home_node)
	idle_drones.append(unit)


func _fallback_mining_job_to_idle(home_base_id: String, home_node: Node2D) -> void:
	if home_node == null:
		home_node = _get_target_node(home_base_id.strip_edges())

	if home_node == null:
		return

	var unit := _spawn_unit(MINING_SHIP_SCENE)

	if unit == null:
		return

	unit.work_duration = DEFAULT_MINING_DURATION
	_disconnect_unit_signals(unit)
	_ensure_returned_to_base_connected(unit)
	unit.start_orbiting_base(home_node)
	idle_mining_ships.append(unit)


func _restart_automation_audio_after_restore() -> void:
	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var unit := instance_from_id(unit_id) as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		var assigned_target_id: String = str(scan_drone_target_by_unit_id.get(unit_id, "")).strip_edges()
		var target_node: Node2D = _get_target_node(assigned_target_id)

		if target_node == null:
			continue

		var is_scanning_at_target := false

		if unit.state == AutomationUnit.State.WORKING:
			is_scanning_at_target = true
		elif unit.state == AutomationUnit.State.ORBITING_BASE:
			if unit.base_node != null and is_instance_valid(unit.base_node):
				is_scanning_at_target = (
					_get_object_id_from_node(unit.base_node).strip_edges() == assigned_target_id
				)

		if not is_scanning_at_target:
			continue

		_start_scan_orbit_audio(unit, target_node)

	for unit_id_variant: Variant in mining_ship_runtime_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var runtime: Dictionary = mining_ship_runtime_by_unit_id.get(unit_id, {})

		if runtime.is_empty():
			continue

		if int(runtime.get("status", MiningShipStatus.TO_TARGET)) != MiningShipStatus.MINING:
			continue

		var unit := instance_from_id(unit_id) as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		_play_mining_resource_tick_sfx(unit)


func _request_automation_state_changed() -> void:
	if _automation_state_emit_scheduled:
		return
	_automation_state_emit_scheduled = true
	call_deferred("_emit_automation_state_changed_deferred")


func _emit_automation_state_changed_deferred() -> void:
	_automation_state_emit_scheduled = false
	if not is_inside_tree():
		return
	if GameSession.has_method("refresh_automation_snapshot_from_scene"):
		GameSession.refresh_automation_snapshot_from_scene()
	automation_state_changed.emit()


func _play_automation_sfx(event_id: StringName, source: Node2D) -> void:
	_audio_service.play_automation_sfx(event_id, source)


func _play_unit_travel_sfx(event_id: StringName, unit: AutomationUnit, fallback: Node2D = null) -> void:
	_audio_service.play_unit_travel_sfx(event_id, unit, fallback)


func _play_scan_drone_launch_audio(unit: AutomationUnit) -> void:
	_audio_service.play_scan_drone_launch(unit)


func _play_scan_drone_arrive_audio(unit: AutomationUnit, fallback: Node2D = null) -> void:
	_audio_service.play_scan_drone_arrive(unit, fallback)


func _play_mining_ship_launch_audio(unit: AutomationUnit) -> void:
	_audio_service.play_mining_ship_launch(unit)


func _play_mining_ship_arrive_audio(unit: AutomationUnit, fallback: Node2D = null) -> void:
	_audio_service.play_mining_ship_arrive(unit, fallback)


func _begin_scan_drone_return_travel(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	_stop_scan_orbit_audio(unit)
	_play_scan_drone_launch_audio(unit)


func _begin_mining_ship_return_travel(unit: AutomationUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	_play_mining_ship_launch_audio(unit)


func _scan_drone_start_outbound(unit: AutomationUnit, target_node: Node2D) -> void:
	if unit == null or target_node == null:
		return

	_stop_scan_orbit_audio(unit)
	_play_scan_drone_launch_audio(unit)
	unit.start_mission_to_node(target_node)


func _mining_ship_start_outbound(unit: AutomationUnit, target_node: Node2D) -> void:
	if unit == null or target_node == null:
		return

	_play_mining_ship_launch_audio(unit)
	unit.start_mission_to_node(target_node)


func _scan_drone_recall_to_base(unit: AutomationUnit, home_base_node: Node2D) -> void:
	if unit == null or home_base_node == null:
		return

	_begin_scan_drone_return_travel(unit)
	unit.recall_to_base(home_base_node)


func _scan_drone_return_to_base_orbit(unit: AutomationUnit) -> void:
	if unit == null:
		return

	_begin_scan_drone_return_travel(unit)
	unit.return_to_base_orbit()


func _mining_ship_recall_to_base(unit: AutomationUnit, home_base_node: Node2D) -> void:
	if unit == null or home_base_node == null:
		return

	_begin_mining_ship_return_travel(unit)
	unit.recall_to_base(home_base_node)


func _play_mining_resource_tick_sfx(unit: AutomationUnit) -> void:
	_audio_service.play_mining_resource_tick(unit)


func _scan_orbit_loop_id(unit: AutomationUnit) -> StringName:
	return _audio_service.scan_orbit_loop_id(unit)


func _start_scan_orbit_audio(unit: AutomationUnit, target_node: Node2D) -> void:
	_audio_service.start_scan_orbit_audio(unit, target_node)


func _stop_scan_orbit_audio(unit: AutomationUnit) -> void:
	_audio_service.stop_scan_orbit_audio(unit)


func _audio_source_node(unit: Node2D, fallback: Node2D) -> Node2D:
	return _audio_service.audio_source_node(unit, fallback) as Node2D


func _audio_node_for_base(base_id: String, unit: AutomationUnit) -> Node2D:
	return _audio_service.audio_node_for_base(spawner, base_id, unit) as Node2D
