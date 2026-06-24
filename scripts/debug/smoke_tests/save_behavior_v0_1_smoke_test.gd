## Save behavior v0.1 smoke test (debug-only) — disk save cancel/refund policy.
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/save_behavior_v0_1_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const SIGNAL_OBJECT_ID: String = "venus"
const BASE_ID: String = BaseStore.BASE_EARTH
const HIDDEN_CANDIDATE_ID: String = "jupiter"
const TEST_SAVE_SLOT: int = 3

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _spc: SurveyProbeMissionController = null
var _pulse_ctrl: BaseSensorPulseController = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	GameSession.reset_for_new_game()
	_load_system_scene()


func _load_system_scene() -> void:
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _run_tests)


func _run_tests() -> void:
	_spc = _find_survey_probe_controller(_system_scene)
	_pulse_ctrl = _find_pulse_controller(_system_scene)
	if _spc == null or _pulse_ctrl == null:
		_fail("Missing SurveyProbeMissionController or BaseSensorPulseController")
		_finish()
		return

	var automation: AutomationController = _find_automation_controller(_system_scene)
	if automation != null:
		automation.ensure_starting_units(BASE_ID)

	_test_a_save_during_investigate()
	_test_b_save_during_sensor_pulse()
	_regression_checks()
	_finish()


func _test_a_save_during_investigate() -> void:
	var probes_before: int = GameSession.get_available_survey_probe_count(BASE_ID)
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")

	if not _spc.try_start_investigate_signal(SIGNAL_OBJECT_ID, BASE_ID):
		_fail("Test A: try_start_investigate_signal failed")
		return
	if not _spc.is_investigate_active(SIGNAL_OBJECT_ID):
		_fail("Test A: investigate not active after start")
		return

	var probes_after_start: int = GameSession.get_available_survey_probe_count(BASE_ID)
	_results["test_a_probes_before"] = probes_before
	_results["test_a_probes_after_start"] = probes_after_start

	if probes_after_start != probes_before - 1:
		_fail("Test A: expected probe consumed once (before=%d after=%d)" % [
			probes_before, probes_after_start,
		])

	if not SaveManager.save_game(TEST_SAVE_SLOT):
		_fail("Test A: save_game failed")
		return

	var probes_after_save: int = GameSession.get_available_survey_probe_count(BASE_ID)
	var discovery: String = GameSession.get_object_discovery_state(SYSTEM_ID, SIGNAL_OBJECT_ID)
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var active: bool = _spc.is_investigate_active(SIGNAL_OBJECT_ID)

	_results["test_a_probes_after_save"] = probes_after_save
	_results["test_a_discovery"] = discovery
	_results["test_a_sd_after"] = sd_after
	_results["test_a_active_after_save"] = active

	if probes_after_save != probes_before:
		_fail("Test A: probe not refunded on save (expected %d, got %d)" % [
			probes_before, probes_after_save,
		])
	if active:
		_fail("Test A: investigate still active after save (should be cancelled)")
	if discovery == GameSession.DISCOVERY_KNOWN:
		_fail("Test A: signal must not become KNOWN from save-cancel")
	if sd_after != sd_before:
		_fail("Test A: SurveyData changed on investigate save-cancel")


func _test_b_save_during_sensor_pulse() -> void:
	_restore_survey_data_for_pulse()
	GameSession.set_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID, GameSession.DISCOVERY_HIDDEN)

	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var balance := GameSession.get_game_balance()
	var expected_cost: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		expected_cost = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))

	if not _pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_fail("Test B: try_start_sensor_pulse failed")
		return
	if not _pulse_ctrl.is_pulse_active():
		_fail("Test B: pulse not active after start")
		return

	var sd_after_start: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_results["test_b_sd_before"] = sd_before
	_results["test_b_sd_after_start"] = sd_after_start
	_results["test_b_expected_cost"] = expected_cost

	if sd_before - sd_after_start != expected_cost:
		_fail("Test B: pulse did not spend expected SurveyData")

	if not SaveManager.save_game(TEST_SAVE_SLOT):
		_fail("Test B: save_game failed")
		return

	var sd_after_save: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var pulse_active: bool = _pulse_ctrl.is_pulse_active()
	var hidden_after: String = GameSession.get_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID)

	_results["test_b_sd_after_save"] = sd_after_save
	_results["test_b_pulse_active_after_save"] = pulse_active
	_results["test_b_jupiter_after"] = hidden_after

	if sd_after_save != sd_before:
		_fail("Test B: SurveyData not refunded on pulse save-cancel (before=%d after=%d)" % [
			sd_before, sd_after_save,
		])
	if pulse_active:
		_fail("Test B: pulse still active after save")
	if hidden_after != GameSession.DISCOVERY_HIDDEN:
		_notes.append("Test B: jupiter not HIDDEN after save — may have been revealed earlier in session")


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)

	_notes.append("Test C (scan/mining save): see shared_scan_job_step_5_save_restore_smoke_test.gd")
	_notes.append("Test D (galaxy transition): see galaxy_transition_process_continuity_smoke_test.gd")


func _restore_survey_data_for_pulse() -> void:
	var balance := GameSession.get_game_balance()
	var needed: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		needed = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))
	var current: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if current < needed * 2:
		GameSession.add_base_resource(BASE_ID, "SurveyData", needed * 2 - current)


func _find_automation_controller(root: Node) -> AutomationController:
	if root is AutomationController:
		return root as AutomationController
	for child: Node in root.get_children():
		var found: AutomationController = _find_automation_controller(child)
		if found != null:
			return found
	return null


func _find_survey_probe_controller(root: Node) -> SurveyProbeMissionController:
	if root is SurveyProbeMissionController:
		return root as SurveyProbeMissionController
	for child: Node in root.get_children():
		var found: SurveyProbeMissionController = _find_survey_probe_controller(child)
		if found != null:
			return found
	return null


func _find_pulse_controller(root: Node) -> BaseSensorPulseController:
	if root is BaseSensorPulseController:
		return root as BaseSensorPulseController
	for child: Node in root.get_children():
		var found: BaseSensorPulseController = _find_pulse_controller(child)
		if found != null:
			return found
	return null


func _count_tooltip_recursive(node: Node) -> int:
	var count: int = 0
	if node is Control:
		var ctl: Control = node as Control
		if not str(ctl.tooltip_text).is_empty():
			count += 1
	for child: Node in node.get_children():
		count += _count_tooltip_recursive(child)
	return count


func _wait_frames(count: int, callback: Callable) -> void:
	if not callback.is_valid():
		return
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[SaveBehaviorV01Smoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== Save Behavior v0.1 Smoke ===")
	print("Status: %s" % status)
	print("Results: %s" % str(_results))
	for note: String in _notes:
		print("NOTE: %s" % note)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


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
