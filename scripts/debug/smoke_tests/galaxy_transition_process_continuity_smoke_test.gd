## Galaxy transition process continuity smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/galaxy_transition_process_continuity_smoke_runner.tscn
extends Node

const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const PROXIMA_ID: String = GameSession.PROXIMA_SYSTEM_ID

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _scene_slot: Node = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	_setup_scene_flow()
	call_deferred("_begin")


func _setup_scene_flow() -> void:
	var scene_root := Node.new()
	scene_root.name = "SceneRoot"
	add_child(scene_root)
	_scene_slot = Node.new()
	_scene_slot.name = "CurrentSceneSlot"
	scene_root.add_child(_scene_slot)
	SceneFlow.register_main_root(self)


func _begin() -> void:
	GameSession.reset_for_new_game()
	SceneFlow.goto_system()
	_wait_frames(120, _run_all_tests)


func _run_all_tests() -> void:
	_test_a_survey_probe_survives()


func _continue_after_test_a() -> void:
	_test_b_scan_drone_survives()


func _continue_after_test_b() -> void:
	_test_c_mining_ship_survives()


func _continue_after_test_c() -> void:
	_test_e_sensor_pulse_survives()


func _continue_after_test_e() -> void:
	_test_f_colonization_survives()


func _continue_after_test_f() -> void:
	_regression_checks()
	_finish()


func _test_a_survey_probe_survives() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_SIGNAL)
	var spc: SurveyProbeMissionController = _find_survey_probe_controller()
	if spc == null:
		_fail("Test A: SurveyProbeMissionController missing")
		return

	var probes_before: int = GameSession.bases.get_survey_probe_count(BASE_ID)
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")

	if not spc.try_start_investigate_signal(TARGET_OBJECT_ID, BASE_ID):
		_fail("Test A: try_start_investigate_signal failed")
		return

	var probes_after_start: int = GameSession.bases.get_survey_probe_count(BASE_ID)
	_results["test_a_probes_before"] = probes_before
	_results["test_a_probes_after_start"] = probes_after_start

	if probes_after_start != probes_before - 1:
		_fail("Test A: expected probe count -1 (before=%d after=%d)" % [probes_before, probes_after_start])

	if not spc.is_investigate_active(TARGET_OBJECT_ID):
		_fail("Test A: investigate not active before galaxy leave")

	_simulate_galaxy_roundtrip(_after_test_a_galaxy.bind(probes_after_start, sd_before))


func _after_test_a_galaxy(probes_after_start: int, sd_before: int) -> void:
	var spc: SurveyProbeMissionController = _find_survey_probe_controller()
	if spc == null:
		_fail("Test A: SurveyProbeMissionController missing after restore")
		return

	var probes_after_return: int = GameSession.bases.get_survey_probe_count(BASE_ID)
	_results["test_a_probes_after_return"] = probes_after_return

	if probes_after_return != probes_after_start:
		_fail(
			"Test A: probe double-spend or refund (after_start=%d after_return=%d)"
			% [probes_after_start, probes_after_return]
		)

	var active: bool = spc.is_investigate_active(TARGET_OBJECT_ID)
	var known: bool = (
		GameSession.get_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID)
		== GameSession.DISCOVERY_KNOWN
	)
	_results["test_a_active_after_return"] = active
	_results["test_a_known_after_return"] = known

	if not active and not known:
		_fail("Test A: investigate neither active nor completed after galaxy roundtrip")

	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if known and sd_after < sd_before:
		_fail("Test A: SurveyData decreased on completion path unexpectedly")

	_continue_after_test_a()


func _test_b_scan_drone_survives() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)

	var automation: AutomationController = _find_automation_controller()
	if automation == null:
		_fail("Test B: AutomationController missing")
		return

	var jobs_before: int = automation.scan_drone_target_by_unit_id.size()
	automation.launch_scan_drone(TARGET_OBJECT_ID)
	var jobs_after_launch: int = automation.scan_drone_target_by_unit_id.size()
	_results["test_b_scan_jobs_before"] = jobs_after_launch

	if jobs_after_launch <= jobs_before:
		_fail("Test B: launch_scan_drone did not start a job (before=%d after=%d)" % [
			jobs_before, jobs_after_launch,
		])
		return

	_simulate_galaxy_roundtrip(_after_test_b_galaxy.bind(jobs_after_launch))


func _after_test_b_galaxy(jobs_before: int) -> void:
	var automation: AutomationController = _find_automation_controller()
	if automation == null:
		_fail("Test B: AutomationController missing after restore")
		return

	var jobs_after: int = automation.scan_drone_target_by_unit_id.size()
	_results["test_b_scan_jobs_after"] = jobs_after
	if jobs_after < 1:
		_fail("Test B: scan mission lost after galaxy (before=%d after=%d)" % [jobs_before, jobs_after])

	_continue_after_test_b()


func _test_c_mining_ship_survives() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)

	var automation: AutomationController = _find_automation_controller()
	if automation == null:
		_fail("Test C: AutomationController missing")
		return

	if not automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test C: launch_mining_ship failed")
		return

	_wait_frames(180, _after_mining_ticks_before_galaxy)


func _after_mining_ticks_before_galaxy() -> void:
	var automation: AutomationController = _find_automation_controller()
	if automation == null:
		_fail("Test C: AutomationController missing")
		return

	var iron_before: int = GameSession.get_remaining_resource_amount(SYSTEM_ID, TARGET_OBJECT_ID, "Iron")
	var cargo_snapshot: int = _sum_mars_cargo(automation)
	var jobs_before: int = automation.mining_ship_runtime_by_unit_id.size()
	_results["test_c_jobs_before"] = jobs_before
	_results["test_c_cargo_before"] = cargo_snapshot
	_results["test_c_iron_before"] = iron_before

	if jobs_before < 1:
		_fail("Test C: no mining job before galaxy leave")
		return

	_simulate_galaxy_roundtrip(_after_test_c_galaxy.bind(iron_before, cargo_snapshot, jobs_before))


func _after_test_c_galaxy(iron_before: int, cargo_before: int, jobs_before: int) -> void:
	var automation: AutomationController = _find_automation_controller()
	if automation == null:
		_fail("Test C: AutomationController missing after restore")
		return

	var jobs_after: int = automation.mining_ship_runtime_by_unit_id.size()
	var cargo_after: int = _sum_mars_cargo(automation)
	var iron_after: int = GameSession.get_remaining_resource_amount(SYSTEM_ID, TARGET_OBJECT_ID, "Iron")

	_results["test_c_jobs_after"] = jobs_after
	_results["test_c_cargo_after"] = cargo_after
	_results["test_c_iron_after"] = iron_after

	if jobs_after < 1:
		_fail("Test C: mining mission lost after galaxy (before=%d after=%d)" % [jobs_before, jobs_after])
	if iron_after > iron_before:
		_fail("Test C: Iron increased after galaxy (duplication?) before=%d after=%d" % [iron_before, iron_after])
	if cargo_before > 0 and cargo_after <= 0:
		_fail("Test C: cargo lost after galaxy (before=%d after=%d)" % [cargo_before, cargo_after])

	_continue_after_test_c()


func _test_e_sensor_pulse_survives() -> void:
	var pulse_ctrl: BaseSensorPulseController = _find_sensor_pulse_controller()
	if pulse_ctrl == null:
		_fail("Test E: BaseSensorPulseController missing")
		return

	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if not pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_notes.append("Test E: sensor pulse could not start (no hidden candidates?) — skipped")
		_results["test_e"] = "SKIPPED"
		_continue_after_test_e()
		return

	var sd_after_start: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_results["test_e_sd_before"] = sd_before
	_results["test_e_sd_after_start"] = sd_after_start

	if sd_after_start >= sd_before:
		_fail("Test E: SurveyData not spent on pulse start")

	_simulate_galaxy_roundtrip(_after_test_e_galaxy.bind(sd_after_start))


func _after_test_e_galaxy(sd_after_start: int) -> void:
	var pulse_ctrl: BaseSensorPulseController = _find_sensor_pulse_controller()
	if pulse_ctrl == null:
		_fail("Test E: BaseSensorPulseController missing after restore")
		return

	var sd_after_return: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_results["test_e_sd_after_return"] = sd_after_return
	_results["test_e_pulse_active"] = pulse_ctrl.is_pulse_active()

	if sd_after_return > sd_after_start:
		_fail("Test E: SurveyData refunded incorrectly after galaxy (start=%d return=%d)" % [
			sd_after_start, sd_after_return,
		])

	_continue_after_test_e()


func _test_f_colonization_survives() -> void:
	GameSession.bases.add_colony_ship(BASE_ID, 1)
	var op_id: String = GameSession.start_colonization_operation(BASE_ID, PROXIMA_ID)
	if op_id.is_empty():
		_notes.append("Test F: colonization start not available — skipped")
		_results["test_f"] = "SKIPPED"
		_continue_after_test_f()
		return

	var ships_before: int = GameSession.get_base_colony_ship_count(BASE_ID)
	var pending_before: int = GameSession.get_pending_colonization_operations().size()
	_results["test_f_op_id"] = op_id
	_results["test_f_pending_before"] = pending_before

	_simulate_galaxy_roundtrip(_after_test_f_galaxy.bind(op_id, ships_before))


func _after_test_f_galaxy(op_id: String, ships_before: int) -> void:
	var still_pending: bool = false
	for rec_variant: Variant in GameSession.get_pending_colonization_operations():
		if rec_variant is Dictionary:
			if str((rec_variant as Dictionary).get("operation_id", "")) == op_id:
				still_pending = true
				break

	_results["test_f_still_pending"] = still_pending
	if not still_pending:
		_fail("Test F: colonization operation lost after galaxy roundtrip")

	var ships_after: int = GameSession.get_base_colony_ship_count(BASE_ID)
	if ships_after < ships_before:
		_fail("Test F: colony ship count dropped after galaxy (before=%d after=%d)" % [
			ships_before, ships_after,
		])

	_continue_after_test_f()


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")


func _simulate_galaxy_roundtrip(done_callback: Callable) -> void:
	GameSession.capture_system_scene_processes_before_leave()
	SceneFlow.goto_galaxy()
	_wait_frames(30, func() -> void:
		SceneFlow.goto_system()
		_wait_frames(150, done_callback)
	)


func _sum_mars_cargo(automation: AutomationController) -> int:
	var total: int = 0
	for uid_v: Variant in automation.mining_ship_runtime_by_unit_id.keys():
		var rt: Dictionary = automation.mining_ship_runtime_by_unit_id[uid_v] as Dictionary
		if str(rt.get("target_id", "")) != TARGET_OBJECT_ID:
			continue
		var cargo: Dictionary = rt.get("cargo_resources", {}) as Dictionary
		for amt_v: Variant in cargo.values():
			total += int(amt_v)
	return total


func _find_survey_probe_controller() -> SurveyProbeMissionController:
	var scene: Node = SceneFlow.get_current_scene()
	if scene == null:
		return null
	return _search_survey_probe(scene)


func _find_automation_controller() -> AutomationController:
	var scene: Node = SceneFlow.get_current_scene()
	if scene == null:
		return null
	return _search_automation(scene)


func _find_sensor_pulse_controller() -> BaseSensorPulseController:
	var scene: Node = SceneFlow.get_current_scene()
	if scene == null:
		return null
	return _search_sensor_pulse(scene)


func _search_survey_probe(node: Node) -> SurveyProbeMissionController:
	if node is SurveyProbeMissionController:
		return node as SurveyProbeMissionController
	for child: Node in node.get_children():
		var found: SurveyProbeMissionController = _search_survey_probe(child)
		if found != null:
			return found
	return null


func _search_automation(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _search_automation(child)
		if found != null:
			return found
	return null


func _search_sensor_pulse(node: Node) -> BaseSensorPulseController:
	if node is BaseSensorPulseController:
		return node as BaseSensorPulseController
	for child: Node in node.get_children():
		var found: BaseSensorPulseController = _search_sensor_pulse(child)
		if found != null:
			return found
	return null


func _wait_frames(count: int, callback: Callable) -> void:
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[GalaxyTransitionSmoke] FAIL: %s" % message)


func _finish() -> void:
	_print_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _print_report() -> void:
	var overall: String = "PASS"
	if not _failures.is_empty():
		overall = "FAIL"
	elif not _notes.is_empty():
		overall = "PASS WITH NOTES"
	print("")
	print("=== Galaxy Transition Process Continuity SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("======================================================")


class _FrameWaiter extends Node:
	signal done

	var frames: int = 1

	func _ready() -> void:
		_run()

	func _run() -> void:
		for _i: int in range(maxi(1, frames)):
			await get_tree().process_frame
		done.emit()
		queue_free()
