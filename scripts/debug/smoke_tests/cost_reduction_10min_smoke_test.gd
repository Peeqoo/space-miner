## Cost Reduction v0.2 — 10-minute informed early-game strategy smoke (debug-only, headless).
## Run: godot --headless --path . --scene res://scripts/debug/smoke_tests/cost_reduction_10min_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const BASE_ID: String = BaseStore.BASE_EARTH
const RUN_DURATION_SEC: float = 600.0
const ECONOMY_TICK_SEC: float = 2.0
const TELEMETRY_LABEL: String = "cost_reduction_10min_strategy_v0_3"

const MS2_IRON_NEED: int = 135
const MS2_SILICON_NEED: int = 23
const MIN_IRON_AFTER_SP_REBUILD: int = 80
const STORAGE_I_IRON_COST: int = 20
const IRON_BODY_ORDER: Array[String] = ["mars", "moon", "mercury"]
const VENUS_FALLBACK_ID: String = "venus"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _elapsed: float = 0.0
var _tick_accum: float = 0.0
var _last_minute_logged: int = -1
var _finished: bool = false

var _system_scene: Node = null
var _automation: AutomationController = null
var _telemetry: BalanceTelemetryLogger = null

var _milestones: Dictionary = {}
var _minute_snapshots: Array[Dictionary] = []

var _prev_sd: int = -1
var _prev_ms: int = -1
var _prev_sp: int = -1
var _prev_storage_lvl: int = -1
var _sp_rebuild_count: int = 0


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — skipped")
		call_deferred("_finish")
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_telemetry = GameSession.get_node_or_null("BalanceTelemetryLogger") as BalanceTelemetryLogger
	if _telemetry == null:
		_fail("BalanceTelemetryLogger not found on GameSession")
		_finish()
		return

	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return

	_system_scene = packed.instantiate()
	add_child(_system_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	_automation = _find_automation_controller(_system_scene)
	if _automation == null:
		_fail("AutomationController not found")
		_finish()
		return

	_automation.ensure_starting_units(BASE_ID)
	_telemetry.start_run(TELEMETRY_LABEL)
	_record_milestone("run_start", _elapsed)
	_verify_telemetry_baseline()
	set_process(true)


func _process(delta: float) -> void:
	if _finished:
		return

	_elapsed += delta
	_tick_accum += delta

	if _tick_accum >= ECONOMY_TICK_SEC:
		_tick_accum = 0.0
		_economy_tick()

	var minute: int = int(_elapsed / 60.0)
	if minute > _last_minute_logged and minute <= 10:
		_last_minute_logged = minute
		_log_minute(minute)

	if _elapsed >= RUN_DURATION_SEC:
		_finished = true
		set_process(false)
		_finish_run()


func _economy_tick() -> void:
	_track_unit_milestones()
	_try_sensor_pulse()
	_try_investigate_iron_priority()
	_try_launch_scan_iron_priority()
	_try_launch_mining_iron_priority()
	_try_build_mining_ship()
	if _should_buy_storage_sensible():
		_try_buy_storage_upgrade()
	if _should_build_scan_drone():
		_try_build_scan_drone()
	_try_launch_scan_secondary()
	if _should_build_survey_probe():
		_try_build_survey_probe()


func _ms2_built() -> bool:
	return GameSession.get_base_mining_ship_count(BASE_ID) >= 2


func _ms2_imminent() -> bool:
	if _ms2_built():
		return false
	var si: int = GameSession.get_base_resource_amount(BASE_ID, "Silicon")
	var fe: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	return si >= MS2_SILICON_NEED and fe >= MS2_IRON_NEED - 40


func _can_spend_iron_for_non_ms2(amount: int, min_remainder: int) -> bool:
	if amount <= 0:
		return true
	var fe: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	if fe < amount:
		return false
	var after: int = fe - amount
	if _ms2_built():
		return after >= min_remainder
	var si: int = GameSession.get_base_resource_amount(BASE_ID, "Silicon")
	if si >= MS2_SILICON_NEED and after < MS2_IRON_NEED:
		return false
	return after >= maxi(min_remainder, 0)


func _should_build_survey_probe() -> bool:
	if GameSession.bases.get_survey_probe_count(BASE_ID) > 0:
		return false
	if _ms2_imminent():
		return false
	var gate: Dictionary = GameSession.get_build_base_survey_probe_gate(BASE_ID)
	if not bool(gate.get("ok", false)):
		return false
	var cost: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SURVEY_PROBE, BASE_ID
	)
	var sp_iron: int = int(cost.get("Iron", 0))
	return _can_spend_iron_for_non_ms2(sp_iron, MIN_IRON_AFTER_SP_REBUILD)


func _should_build_scan_drone() -> bool:
	if GameSession.get_base_drone_count(BASE_ID) >= 2:
		return false
	var gate: Dictionary = GameSession.get_build_base_scan_drone_gate(BASE_ID)
	if not bool(gate.get("ok", false)):
		return false
	var cost: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SCAN_DRONE, BASE_ID
	)
	var sd_iron: int = int(cost.get("Iron", 0))
	if not _can_spend_iron_for_non_ms2(sd_iron, 0):
		return false
	if _ms2_built():
		return true
	if _milestones.has("first_delivery"):
		return true
	var si: int = GameSession.get_base_resource_amount(BASE_ID, "Silicon")
	if si < MS2_SILICON_NEED:
		return true
	var fe: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	return fe - sd_iron >= MS2_IRON_NEED


func _should_buy_storage_sensible() -> bool:
	if GameSession.get_base_upgrade_level(BASE_ID, &"storage") > 0:
		return false
	var cap: int = GameSession.get_base_storage_capacity(BASE_ID)
	if cap <= 0:
		return false
	var used: int = GameSession.get_base_storage_used(BASE_ID)
	if float(used) / float(cap) < 0.70:
		return false
	var iron: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	var copper: int = GameSession.get_base_resource_amount(BASE_ID, "Copper")
	if iron < STORAGE_I_IRON_COST or copper < 5:
		return false
	if not _ms2_built() and _ms2_imminent():
		return false
	return _can_spend_iron_for_non_ms2(STORAGE_I_IRON_COST, 0)


func _try_build_scan_drone() -> void:
	var gate: Dictionary = GameSession.get_build_base_scan_drone_gate(BASE_ID)
	if not bool(gate.get("ok", false)):
		return
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)


func _try_build_mining_ship() -> void:
	var gate: Dictionary = GameSession.get_build_base_mining_ship_gate(BASE_ID)
	if not bool(gate.get("ok", false)):
		return
	if GameSession.build_base_mining_ship(BASE_ID):
		_automation.spawn_idle_mining_ship_at_base(BASE_ID)


func _try_build_survey_probe() -> void:
	var life_before: int = GameSession.get_production_lifetime_count(
		BASE_ID, BaseStore.PRODUCTION_SURVEY_PROBE
	)
	var gate: Dictionary = GameSession.get_build_base_survey_probe_gate(BASE_ID)
	if not bool(gate.get("ok", false)):
		return
	if GameSession.build_base_survey_probe(BASE_ID):
		if life_before >= 2:
			_sp_rebuild_count += 1
			_record_milestone("survey_probe_rebuild_%d" % _sp_rebuild_count, _elapsed)


func _try_buy_storage_upgrade() -> void:
	var gate: Dictionary = GameSession.get_buy_next_base_upgrade_gate(BASE_ID, &"storage")
	if not bool(gate.get("ok", false)):
		return
	if GameSession.buy_next_base_upgrade(BASE_ID, &"storage"):
		_record_milestone("storage_upgrade_bought", _elapsed)


func _try_sensor_pulse() -> void:
	var ctrl: BaseSensorPulseController = _find_sensor_pulse_controller()
	if ctrl == null:
		return
	if bool(ctrl.can_start_sensor_pulse(BASE_ID).get("ok", false)):
		ctrl.try_start_sensor_pulse(BASE_ID)


func _try_investigate_iron_priority() -> void:
	if GameSession.bases.get_survey_probe_count(BASE_ID) < 1:
		return
	if _ms2_imminent() and GameSession.bases.get_survey_probe_count(BASE_ID) <= 1:
		if _any_iron_body_mineable():
			return
	var ctrl: SurveyProbeMissionController = _find_survey_probe_controller()
	if ctrl == null:
		return
	var oid: String = _first_iron_signal_candidate()
	if oid.is_empty():
		return
	ctrl.try_start_investigate_signal(oid, BASE_ID)


func _try_launch_scan_iron_priority() -> void:
	if _automation == null or not _automation.has_idle_drone():
		return
	for oid: String in IRON_BODY_ORDER:
		if not GameSession.is_object_known(SYSTEM_ID, oid):
			continue
		if not _body_has_basic_iron(oid):
			continue
		var gate: Dictionary = GameSession.can_scan_object(
			SYSTEM_ID, oid, BASE_ID, true, _scan_active_for(oid)
		)
		if bool(gate.get("ok", false)):
			_automation.launch_scan_drone(oid)
			return


func _try_launch_scan_secondary() -> void:
	if _automation == null or not _automation.has_idle_drone():
		return
	for oid: String in IRON_BODY_ORDER:
		var gate: Dictionary = GameSession.can_scan_object(
			SYSTEM_ID, oid, BASE_ID, true, _scan_active_for(oid)
		)
		if bool(gate.get("ok", false)):
			_automation.launch_scan_drone(oid)
			return


func _try_launch_mining_iron_priority() -> void:
	if _automation == null or not _automation.has_idle_mining_ship():
		return
	var target: String = _best_iron_mine_target()
	if target.is_empty():
		return
	if _automation.launch_mining_ship(target):
		if not _milestones.has("first_mining_target"):
			_record_milestone("first_mining_target_%s" % target, _elapsed)
		if target != VENUS_FALLBACK_ID and _body_has_basic_iron(target):
			_record_milestone("first_iron_mining_%s" % target, _elapsed)


func _best_iron_mine_target() -> String:
	for oid: String in IRON_BODY_ORDER:
		if not _body_has_basic_iron(oid):
			continue
		var gate: Dictionary = GameSession.can_mine_object(SYSTEM_ID, oid, BASE_ID, true)
		if bool(gate.get("ok", false)):
			return oid
	var venus_gate: Dictionary = GameSession.can_mine_object(
		SYSTEM_ID, VENUS_FALLBACK_ID, BASE_ID, true
	)
	if bool(venus_gate.get("ok", false)):
		return VENUS_FALLBACK_ID
	return ""


func _any_iron_body_mineable() -> bool:
	var target: String = _best_iron_mine_target()
	return not target.is_empty() and target != VENUS_FALLBACK_ID


func _body_has_basic_iron(object_id: String) -> bool:
	var body_def: SystemBodyDefinition = _get_body_definition(object_id)
	if body_def == null:
		return false
	for entry_variant: Variant in body_def.scan_resources:
		var entry: ScannedResourceEntry = entry_variant as ScannedResourceEntry
		if entry == null:
			continue
		if String(entry.resource_id) != "Iron":
			continue
		if int(entry.layer) == int(ScannedResourceEntry.Layer.BASIC):
			return true
	return false


func _get_body_definition(object_id: String) -> SystemBodyDefinition:
	var sys_def: SystemDefinition = GameSession.current_system_definition
	if sys_def == null:
		return null
	for body_def: SystemBodyDefinition in sys_def.bodies:
		if body_def == null:
			continue
		if str(body_def.id).strip_edges() == object_id:
			return body_def
	return null


func _first_iron_signal_candidate() -> String:
	for oid: String in IRON_BODY_ORDER:
		if GameSession.get_object_discovery_state(SYSTEM_ID, oid) == GameSession.DISCOVERY_SIGNAL:
			return oid
	return _first_any_signal_candidate()


func _first_any_signal_candidate() -> String:
	var sys_def: SystemDefinition = GameSession.current_system_definition
	if sys_def == null:
		return ""
	for body_def: SystemBodyDefinition in sys_def.bodies:
		if body_def == null:
			continue
		var oid: String = str(body_def.id).strip_edges()
		if oid.is_empty() or oid == BASE_ID:
			continue
		if GameSession.get_object_discovery_state(SYSTEM_ID, oid) == GameSession.DISCOVERY_SIGNAL:
			return oid
	for poi_def: PointOfInterestDefinition in sys_def.pois:
		if poi_def == null:
			continue
		var oid: String = str(poi_def.id).strip_edges()
		if oid.is_empty():
			continue
		if GameSession.get_object_discovery_state(SYSTEM_ID, oid) == GameSession.DISCOVERY_SIGNAL:
			return oid
	return ""


func _scan_active_for(object_id: String) -> bool:
	if _automation == null:
		return false
	return _automation.get_active_scan_drone_count_for_target(object_id) > 0


func _track_unit_milestones() -> void:
	var sd: int = GameSession.get_base_drone_count(BASE_ID)
	var ms: int = GameSession.get_base_mining_ship_count(BASE_ID)
	var sp: int = GameSession.bases.get_survey_probe_count(BASE_ID)
	var st: int = GameSession.get_base_upgrade_level(BASE_ID, &"storage")

	if _prev_sd >= 0 and sd > _prev_sd:
		_record_milestone("scan_drone_count_%d" % sd, _elapsed)
	if _prev_ms >= 0 and ms > _prev_ms:
		_record_milestone("mining_ship_count_%d" % ms, _elapsed)
	if _prev_sp >= 0 and sp > _prev_sp:
		_record_milestone("survey_probe_count_%d" % sp, _elapsed)
	if _prev_storage_lvl >= 0 and st > _prev_storage_lvl:
		_record_milestone("storage_level_%d" % st, _elapsed)

	_prev_sd = sd
	_prev_ms = ms
	_prev_sp = sp
	_prev_storage_lvl = st


func _verify_telemetry_baseline() -> void:
	_check_scaled_cost(BaseStore.PRODUCTION_SCAN_DRONE, "Iron", 56)
	_check_scaled_cost(BaseStore.PRODUCTION_MINING_SHIP, "Iron", 135)
	_check_scaled_cost(BaseStore.PRODUCTION_MINING_SHIP, "Silicon", 23)
	_check_scaled_cost(BaseStore.PRODUCTION_SURVEY_PROBE, "Iron", 37)

	var cs_info: Dictionary = GameSession.get_scaled_production_cost_preview_info(
		BaseStore.PRODUCTION_COLONY_SHIP, BASE_ID
	)
	if not bool(cs_info.get("scaling_excluded", false)):
		_fail("colony_ship scaling_excluded expected true")

	var cs_cost: Dictionary = GameSession.get_colony_ship_build_cost()
	_expect_amount(int(cs_cost.get("Iron", 0)), 900, "ColonyShip Iron")
	_expect_amount(int(cs_cost.get("Silicon", 0)), 180, "ColonyShip Silicon")
	_expect_amount(int(cs_cost.get("Water", 0)), 250, "ColonyShip Water")
	_expect_amount(int(cs_cost.get("SurveyData", 0)), 100, "ColonyShip SurveyData")

	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")


func _check_scaled_cost(production_id: String, res: String, expected: int) -> void:
	var cost: Dictionary = GameSession.get_scaled_production_cost(production_id, BASE_ID)
	var actual: int = int(cost.get(res, -1))
	if actual != expected:
		_fail("%s %s scaled cost expected %d got %d" % [production_id, res, expected, actual])


func _expect_amount(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _log_minute(minute: int) -> void:
	if _telemetry != null:
		_telemetry.record_snapshot("minute_%d" % minute)
	var snap: Dictionary = _build_minute_snapshot(minute)
	_minute_snapshots.append(snap)
	print(
		"[10minSmoke] m=%d Fe=%d Si=%d SD=%d MS=%d SP=%d stor=%d/%d"
		% [
			minute,
			GameSession.get_base_resource_amount(BASE_ID, "Iron"),
			GameSession.get_base_resource_amount(BASE_ID, "Silicon"),
			GameSession.get_base_drone_count(BASE_ID),
			GameSession.get_base_mining_ship_count(BASE_ID),
			GameSession.bases.get_survey_probe_count(BASE_ID),
			GameSession.get_base_storage_used(BASE_ID),
			GameSession.get_base_storage_capacity(BASE_ID),
		]
	)


func _build_minute_snapshot(minute: int) -> Dictionary:
	var cs_gate: Dictionary = GameSession.get_build_base_colony_ship_gate(BASE_ID)
	return {
		"minute": minute,
		"elapsed": _elapsed,
		"iron": GameSession.get_base_resource_amount(BASE_ID, "Iron"),
		"silicon": GameSession.get_base_resource_amount(BASE_ID, "Silicon"),
		"copper": GameSession.get_base_resource_amount(BASE_ID, "Copper"),
		"water": GameSession.get_base_resource_amount(BASE_ID, "Water"),
		"survey_data": GameSession.get_base_resource_amount(BASE_ID, "SurveyData"),
		"scan_drones": GameSession.get_base_drone_count(BASE_ID),
		"mining_ships": GameSession.get_base_mining_ship_count(BASE_ID),
		"survey_probes": GameSession.bases.get_survey_probe_count(BASE_ID),
		"storage_level": GameSession.get_base_upgrade_level(BASE_ID, &"storage"),
		"scan_drone_level": GameSession.get_base_upgrade_level(BASE_ID, &"scan_drone"),
		"mining_ship_level": GameSession.get_base_upgrade_level(BASE_ID, &"mining_ship"),
		"colony_gate_ok": bool(cs_gate.get("ok", false)),
		"colony_prereqs": cs_gate.get("prerequisites", []),
		"sd_next_cost": GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_SCAN_DRONE, BASE_ID
		),
		"ms_next_cost": GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_MINING_SHIP, BASE_ID
		),
		"sp_next_cost": GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_SURVEY_PROBE, BASE_ID
		),
	}


func _finish_run() -> void:
	_record_milestone("run_end", _elapsed)
	if not _milestones.has("mining_ship_count_2"):
		var fe: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
		var si: int = GameSession.get_base_resource_amount(BASE_ID, "Silicon")
		_notes.append(
			"MS #2 not built in 10 min (Fe=%d need %d, Si=%d need %d, SP rebuilds=%d)"
			% [fe, MS2_IRON_NEED, si, MS2_SILICON_NEED, _sp_rebuild_count]
		)
	if _milestones.has("first_mining_target_venus") and not _milestones.has("first_iron_mining_mars"):
		if not _milestones.has("first_iron_mining_moon") and not _milestones.has("first_iron_mining_mercury"):
			_notes.append("First mining was Venus fallback — no iron body mineable in time")
	if _telemetry != null:
		_telemetry.stop_run()
		var path: String = _telemetry.save_run()
		print("[10minSmoke] telemetry saved: %s" % path)
	_finish()


func _record_milestone(key: String, at_sec: float) -> void:
	if _milestones.has(key):
		return
	_milestones[key] = snappedf(at_sec, 0.1)


func _find_automation_controller(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _find_automation_controller(child)
		if found != null:
			return found
	return null


func _find_sensor_pulse_controller() -> BaseSensorPulseController:
	if _system_scene == null:
		return null
	return _find_typed_node(_system_scene, BaseSensorPulseController) as BaseSensorPulseController


func _find_survey_probe_controller() -> SurveyProbeMissionController:
	if _system_scene == null:
		return null
	return _find_typed_node(_system_scene, SurveyProbeMissionController) as SurveyProbeMissionController


func _find_typed_node(root: Node, type_match: Variant) -> Node:
	if root == null:
		return null
	if type_match == BaseSensorPulseController and root is BaseSensorPulseController:
		return root
	if type_match == SurveyProbeMissionController and root is SurveyProbeMissionController:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_typed_node(child, type_match)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[10minSmoke] FAIL: %s" % message)


func _finish() -> void:
	_print_summary()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _print_summary() -> void:
	var overall: String = "PASS"
	if not _failures.is_empty():
		overall = "FAIL"
	elif not _notes.is_empty():
		overall = "PASS WITH NOTES"

	print("")
	print("=== Cost Reduction 10min Strategy Smoke v0.3 ===")
	print("Overall: %s" % overall)
	print("Elapsed: %.1fs" % _elapsed)
	print("SP rebuilds: %d" % _sp_rebuild_count)
	print("Milestones:")
	for key: String in _milestones.keys():
		print("  %s @ %.1fs" % [key, float(_milestones[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("================================================")
