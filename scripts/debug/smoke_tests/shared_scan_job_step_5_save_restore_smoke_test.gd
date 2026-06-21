## SharedScanJob Step 5 — save/restore smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_job_step_5_save_restore_smoke_runner.tscn
extends Node

const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const TEST_SAVE_SLOT: int = 3

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _scene_slot: Node = null
var _automation: AutomationController = null

var _sd_at_scan_start: int = 0
var _scan_state_at_scan_start: String = ""
var _sd_after_completion: int = 0


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
	SaveManager.delete_save(TEST_SAVE_SLOT)
	GameSession.reset_for_new_game()
	_setup_mars_scannable()
	SceneFlow.goto_system()
	_wait_frames(120, _test_a_active_scan_save_load)


func _test_a_active_scan_save_load() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test A: AutomationController missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_sd_at_scan_start = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_at_scan_start = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if _automation.get_active_shared_scan_job_count() != 1:
		_fail("Test A: expected SharedScanJob before save")
		return
	if not SaveManager.save_game(TEST_SAVE_SLOT):
		_fail("Test A: save_game failed")
		_finish()
		return
	SaveManager.load_game(TEST_SAVE_SLOT)
	_reload_system_scene(_after_test_a_load)


func _after_test_a_load() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test A: AutomationController missing after load")
		_test_e_reset()
		return
	var active_missions: int = int(
		(_automation.get_active_scan_mission_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	_results["test_a_active_missions"] = active_missions
	_results["test_a_shared_jobs"] = _automation.get_active_shared_scan_job_count()
	if active_missions < 1:
		_fail("Test A: active scan mission missing after load")
	if _automation.get_active_shared_scan_job_count() != 1:
		_fail("Test A: SharedScanJob not reconstructed after load")
	var job_snap: Dictionary = _automation.get_shared_scan_job_debug_snapshot()
	var jobs: Dictionary = job_snap.get("jobs", {}) as Dictionary
	if jobs.is_empty():
		_fail("Test A: SharedScanJob debug snapshot empty after load")
	else:
		var first_job: Dictionary = jobs.values()[0] as Dictionary
		if int(first_job.get("assigned_unit_count", 0)) != 1:
			_fail("Test A: assigned_unit_count != 1 after load")
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != _sd_at_scan_start:
		_fail("Test A: SurveyData changed on load (no reward expected)")
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != _scan_state_at_scan_start:
		_fail("Test A: scan state changed on load")
	_poll_completion_after_load()


func _poll_completion_after_load(frames_left: int = 3600) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test B: AutomationController missing during completion poll")
		_test_c_save_after_completion()
		return
	var active_jobs: int = _automation.get_active_shared_scan_job_count()
	var active_missions: int = int(
		(_automation.get_active_scan_mission_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	if active_jobs == 0 and active_missions == 0 and support_n >= 1:
		_test_b_completion_after_load()
		return
	if frames_left <= 0:
		_notes.append("Test B: completion poll timed out")
		_test_b_completion_after_load()
		return
	_wait_frames(30, _poll_completion_after_load.bind(frames_left - 30))


func _test_b_completion_after_load() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test B: AutomationController missing")
		_test_c_save_after_completion()
		return
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_results["test_b_sd_after"] = sd_after
	_results["test_b_scan_after"] = scan_after
	_results["test_b_active_jobs"] = _automation.get_active_shared_scan_job_count()
	if _scan_state_at_scan_start == GameSession.SCAN_UNKNOWN and scan_after != GameSession.SCAN_BASIC:
		_fail("Test B: scan state not basic after completion")
	if sd_after <= _sd_at_scan_start:
		_fail("Test B: SurveyData reward missing after completion")
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test B: stale active SharedScanJob after completion")
	_sd_after_completion = sd_after
	_test_c_save_after_completion()


func _test_c_save_after_completion() -> void:
	if not SaveManager.save_game(TEST_SAVE_SLOT):
		_fail("Test C: save_game after completion failed")
		_test_d_galaxy_save_combo()
		return
	var scan_before_load: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	var sd_before_load: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	SaveManager.load_game(TEST_SAVE_SLOT)
	_reload_system_scene(_after_test_c_load.bind(scan_before_load, sd_before_load))


func _after_test_c_load(scan_before_load: String, sd_before_load: int) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test C: AutomationController missing after load")
		_test_d_galaxy_save_combo()
		return
	_results["test_c_active_jobs"] = _automation.get_active_shared_scan_job_count()
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test C: active SharedScanJob restored for completed scan")
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != scan_before_load:
		_fail("Test C: scan state changed after load of completed save")
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != sd_before_load:
		_fail("Test C: duplicate SurveyData reward after load of completed save")
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	_results["test_c_support"] = support_n
	if support_n < 1:
		_notes.append("Test C: support drone count 0 after completed save/load")
	_test_d_galaxy_save_combo()


func _test_d_galaxy_save_combo() -> void:
	GameSession.reset_for_new_game()
	_setup_mars_scannable()
	SceneFlow.goto_system()
	_wait_frames(120, _after_test_d_fresh_scene)


func _after_test_d_fresh_scene() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test D: AutomationController missing")
		_test_e_reset()
		return
	_automation.ensure_starting_units(BASE_ID)
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if _automation.get_active_shared_scan_job_count() != 1:
		_fail("Test D: SharedScanJob missing before galaxy/save")
		return
	_simulate_galaxy_roundtrip(_after_test_d_galaxy.bind(sd_before))


func _after_test_d_galaxy(sd_before: int) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test D: AutomationController missing after galaxy")
		_test_e_reset()
		return
	if _automation.get_active_shared_scan_job_count() < 1:
		_fail("Test D: SharedScanJob lost after galaxy roundtrip")
	if not SaveManager.save_game(TEST_SAVE_SLOT):
		_fail("Test D: save after galaxy failed")
		_test_e_reset()
		return
	SaveManager.load_game(TEST_SAVE_SLOT)
	_reload_system_scene(_after_test_d_load.bind(sd_before))


func _after_test_d_load(sd_before: int) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test D: AutomationController missing after save/load")
		_test_e_reset()
		return
	if _automation.get_active_shared_scan_job_count() < 1:
		_fail("Test D: SharedScanJob missing after save/load combo")
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != sd_before:
		_fail("Test D: SurveyData changed on load before completion")
	_poll_test_d_completion(sd_before)


func _poll_test_d_completion(sd_before: int, frames_left: int = 3600) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test D: AutomationController missing during completion")
		_test_e_reset()
		return
	var active_jobs: int = _automation.get_active_shared_scan_job_count()
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	if active_jobs == 0 and support_n >= 1:
		var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
		_results["test_d_sd_before"] = sd_before
		_results["test_d_sd_after"] = sd_after
		if sd_after <= sd_before:
			_fail("Test D: completion reward missing after save/load combo")
		_test_e_reset()
		return
	if frames_left <= 0:
		_fail("Test D: completion timed out after save/load combo")
		_test_e_reset()
		return
	_wait_frames(30, _poll_test_d_completion.bind(sd_before, frames_left - 30))


func _test_e_reset() -> void:
	GameSession.reset_for_new_game()
	SceneFlow.goto_system()
	_wait_frames(120, _after_test_e_reset)


func _after_test_e_reset() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test E: AutomationController missing after reset")
		_regression_checks()
		_finish()
		return
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test E: stale SharedScanJobs after reset")
	if not _automation.shared_scan_jobs_by_job_id.is_empty():
		_fail("Test E: shared_scan_jobs_by_job_id not empty")
	if not _automation.shared_scan_job_id_by_unit_id.is_empty():
		_fail("Test E: shared_scan_job_id_by_unit_id not empty")
	_results["test_e_cleared"] = true
	_regression_checks()
	_finish()


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _reload_system_scene(done_callback: Callable) -> void:
	SceneFlow.goto_system()
	_wait_frames(150, done_callback)


func _simulate_galaxy_roundtrip(done_callback: Callable) -> void:
	GameSession.capture_system_scene_processes_before_leave()
	SceneFlow.goto_galaxy()
	_wait_frames(30, func() -> void:
		SceneFlow.goto_system()
		_wait_frames(150, done_callback)
	)


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _find_automation_controller() -> AutomationController:
	var scene: Node = SceneFlow.get_current_scene()
	if scene == null:
		return null
	return _search_automation(scene)


func _search_automation(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _search_automation(child)
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
	push_error("[SharedScanJobStep5Smoke] FAIL: %s" % message)


func _finish() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	_print_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _print_report() -> void:
	var overall: String = "PASS"
	if not _failures.is_empty():
		overall = "FAIL"
	elif not _notes.is_empty():
		overall = "PASS WITH NOTES"
	print("")
	print("=== SharedScanJob Step 5 Save/Restore SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("===================================================")


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
