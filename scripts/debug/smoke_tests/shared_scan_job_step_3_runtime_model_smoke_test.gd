## SharedScanJob Step 3 — runtime model smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_job_step_3_runtime_model_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH

const STEP2_TELEMETRY_KEYS: Array[String] = [
	"assigned_drones_per_target",
	"active_scan_missions_per_target",
	"support_drones_per_target",
	"targets_with_assigned_scan_drones",
	"targets_with_active_scan_missions",
	"targets_with_support_drones",
	"already_in_progress_blocks",
	"potential_support_blocks",
	"scan_target_telemetry_available",
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _scene_slot: Node = null
var _system_scene: Node = null
var _automation: AutomationController = null
var _telemetry: BalanceTelemetryLogger = null

var _sd_before_scan: int = 0
var _scan_state_before: String = ""


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
	_setup_mars_scannable()
	SceneFlow.goto_system()
	_telemetry = BalanceTelemetryLogger.new()
	add_child(_telemetry)
	_wait_frames(120, _run_tests)


func _run_tests() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("AutomationController missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_test_a_baseline()
	_sd_before_scan = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_before = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_test_b_single_scan_creates_job()
	_test_c_no_multi_sd()
	_test_e_galaxy_roundtrip_during_scan()


func _test_a_baseline() -> void:
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test A: expected 0 active SharedScanJobs at baseline")
	var snap: Dictionary = _telemetry.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	for key: String in STEP2_TELEMETRY_KEYS:
		if not snap.has(key):
			_fail("Test A: Step 2 telemetry key missing '%s'" % key)
	var shared_jobs: Dictionary = snap.get("shared_scan_jobs", {}) as Dictionary
	if not bool(shared_jobs.get("enabled", false)):
		_fail("Test A: shared_scan_jobs.enabled expected true")
	_results["test_a_active_jobs"] = _automation.get_active_shared_scan_job_count()


func _test_b_single_scan_creates_job() -> void:
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if _automation.get_active_shared_scan_job_count() != 1:
		_fail("Test B: expected 1 active SharedScanJob after launch")
	if _automation.get_shared_scan_job_count_for_target(TARGET_OBJECT_ID) != 1:
		_fail("Test B: expected 1 SharedScanJob for mars")
	var job_snap: Dictionary = _automation.get_shared_scan_job_debug_snapshot()
	var jobs: Dictionary = job_snap.get("jobs", {}) as Dictionary
	if jobs.is_empty():
		_fail("Test B: shared job debug snapshot has no jobs")
		return
	var first_job: Dictionary = jobs.values()[0] as Dictionary
	_results["test_b_target_id"] = str(first_job.get("target_id", ""))
	_results["test_b_assigned_count"] = int(first_job.get("assigned_unit_count", -1))
	_results["test_b_mission_count"] = int(first_job.get("active_mission_count", -1))
	if str(first_job.get("target_id", "")) != TARGET_OBJECT_ID:
		_fail("Test B: job target_id mismatch")
	if int(first_job.get("assigned_unit_count", 0)) != 1:
		_fail("Test B: assigned_unit_count expected 1")
	if int(first_job.get("active_mission_count", 0)) != 1:
		_fail("Test B: active_mission_count expected 1")
	var telemetry: Dictionary = _telemetry.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	var tel_jobs: Dictionary = (telemetry.get("shared_scan_jobs", {}) as Dictionary).get("jobs", {}) as Dictionary
	if tel_jobs.is_empty():
		_fail("Test B: telemetry shared_scan_jobs.jobs empty")


func _test_c_no_multi_sd() -> void:
	var jobs_before: int = _automation.get_active_shared_scan_job_count()
	var assigned_before: int = _automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	var jobs_after: int = _automation.get_active_shared_scan_job_count()
	var assigned_after: int = _automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID)
	var gate: Dictionary = GameSession.can_scan_object(
		SYSTEM_ID,
		TARGET_OBJECT_ID,
		BASE_ID,
		true,
		assigned_after > 0,
	)
	_results["test_c_block_key"] = str(gate.get("blocked_reason_key", ""))
	if jobs_after != jobs_before:
		_fail("Test C: second launch created another SharedScanJob")
	if assigned_after != assigned_before:
		_fail("Test C: second launch changed assigned drone count")
	if str(gate.get("blocked_reason_key", "")) != str(GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS):
		_fail("Test C: KEY_SCAN_ALREADY_IN_PROGRESS not active")


func _test_e_galaxy_roundtrip_during_scan() -> void:
	var sd_before_rt: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_before_rt: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	var jobs_before: int = _automation.get_active_shared_scan_job_count()
	if jobs_before < 1:
		_fail("Test E: no active SharedScanJob before galaxy leave")
		return
	_simulate_galaxy_roundtrip(_after_galaxy_roundtrip.bind(sd_before_rt, scan_before_rt, jobs_before))


func _after_galaxy_roundtrip(sd_before_rt: int, scan_before_rt: String, jobs_before: int) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test E: AutomationController missing after restore")
		_poll_completion()
		return
	var jobs_after: int = _automation.get_active_shared_scan_job_count()
	var assigned: int = _automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_e_jobs_after"] = jobs_after
	_results["test_e_assigned"] = assigned
	if jobs_after < 1:
		_fail("Test E: SharedScanJob not restored after galaxy roundtrip")
	if assigned < 1:
		_fail("Test E: scan assignment lost after galaxy roundtrip")
	var job_snap: Dictionary = _automation.get_shared_scan_job_debug_snapshot()
	var jobs: Dictionary = job_snap.get("jobs", {}) as Dictionary
	if not jobs.is_empty():
		var first_job: Dictionary = jobs.values()[0] as Dictionary
		if int(first_job.get("assigned_unit_count", 0)) != 1:
			_fail("Test E: restored job assigned_unit_count != 1")
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != sd_before_rt:
		_fail("Test E: SurveyData changed on restore (no reward expected)")
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != scan_before_rt:
		_fail("Test E: scan state changed on restore")
	_poll_completion()


func _poll_completion(frames_left: int = 3600) -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Completion poll: AutomationController missing")
		_test_f_reset()
		return
	var active_jobs: int = _automation.get_active_shared_scan_job_count()
	var active_missions: int = int(
		(_automation.get_active_scan_mission_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	if active_jobs == 0 and active_missions == 0 and support_n >= 1:
		_test_d_completion_once()
		return
	if frames_left <= 0:
		_notes.append("Completion poll timed out — partial Test D")
		_test_d_completion_once()
		return
	_wait_frames(30, _poll_completion.bind(frames_left - 30))


func _test_d_completion_once() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test D: AutomationController missing")
		_test_f_reset()
		return
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_results["test_d_sd_before"] = _sd_before_scan
	_results["test_d_sd_after"] = sd_after
	_results["test_d_scan_before"] = _scan_state_before
	_results["test_d_scan_after"] = scan_after
	_results["test_d_active_jobs"] = _automation.get_active_shared_scan_job_count()
	if _scan_state_before == GameSession.SCAN_UNKNOWN and scan_after != GameSession.SCAN_BASIC:
		_fail("Test D: expected basic scan state after completion")
	if sd_after <= _sd_before_scan and _scan_state_before == GameSession.SCAN_UNKNOWN:
		_fail("Test D: expected SurveyData reward exactly once on first basic scan")
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test D: active SharedScanJob should be cleared after completion")
	var snap: Dictionary = _automation.get_scan_drone_target_debug_snapshot()
	var support_n: int = int((snap.get("support_drones_per_target", {}) as Dictionary).get(TARGET_OBJECT_ID, 0))
	_results["test_d_support"] = support_n
	if support_n < 1:
		_notes.append("Test D: support drone telemetry 0 after completion")
	_test_f_reset()


func _test_f_reset() -> void:
	GameSession.reset_for_new_game()
	SceneFlow.goto_system()
	_wait_frames(120, _after_reset)


func _after_reset() -> void:
	_automation = _find_automation_controller()
	if _automation == null:
		_fail("Test F: AutomationController missing after reset")
		_regression_checks()
		_finish()
		return
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test F: stale SharedScanJobs after reset")
	if not _automation.shared_scan_jobs_by_job_id.is_empty():
		_fail("Test F: shared_scan_jobs_by_job_id not empty after reset")
	if not _automation.shared_scan_job_id_by_unit_id.is_empty():
		_fail("Test F: shared_scan_job_id_by_unit_id not empty after reset")
	_results["test_f_cleared"] = true
	_regression_checks()
	_finish()


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")
	var tooltip_count: int = _count_tooltip_text_nodes()
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _count_tooltip_text_nodes() -> int:
	var root: Node = get_tree().root
	return _count_tooltip_recursive(root)


func _count_tooltip_recursive(node: Node) -> int:
	var count: int = 0
	if node is Control:
		var ctl: Control = node as Control
		if not str(ctl.tooltip_text).is_empty():
			count += 1
	for child: Node in node.get_children():
		count += _count_tooltip_recursive(child)
	return count


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


func _wait_frames(count: int, callback: Callable) -> void:
	if not callback.is_valid():
		return
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[SharedScanJobStep3Smoke] FAIL: %s" % message)


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
	print("=== SharedScanJob Step 3 Runtime Model SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("====================================================")


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
