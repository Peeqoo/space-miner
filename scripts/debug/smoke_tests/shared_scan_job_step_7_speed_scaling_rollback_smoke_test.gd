## SharedScanJob Step 7 rollback — remove wrong speed scaling smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_job_step_7_speed_scaling_rollback_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const TEST_SAVE_SLOT: int = 3

const FORBIDDEN_SYMBOLS: Array[String] = [
	"SHARED_SCAN_EXTRA_DRONE_BONUS",
	"SHARED_SCAN_MAX_SPEED_MULTIPLIER",
	"_get_shared_scan_speed_multiplier",
	"get_shared_scan_speed_multiplier_for_arrived_count",
	"shared_scan_extra_drone_sqrt_bonus",
	"shared_scan_max_speed_multiplier",
	"_process_shared_scan_jobs",
	"capture_shared_scan_jobs_runtime_snapshot",
	"restore_shared_scan_jobs_from_runtime_snapshot",
	"get_shared_scan_job_status_for_target",
	"effective_speed_multiplier",
	"arrived_unit_ids",
	"estimated_remaining_seconds",
]

const SCAN_PATHS: Array[String] = [
	"res://scripts/system/controller/automation_controller.gd",
	"res://resources/definitions/game_balance_definition.gd",
	"res://scripts/system/controller/system_ui_controller.gd",
	"res://scripts/ui/system/object_info_panel.gd",
	"res://scenes/ui/system/object_info_panel.tscn",
	"res://scripts/debug/balance_telemetry_logger.gd",
	"res://scripts/autoload/game_session.gd",
	"res://scripts/system/system_scene.gd",
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _scan_button: Button = null

var _sd_at_start: int = 0
var _scan_state_at_start: String = ""
var _work_required_one_drone: float = -1.0


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	_test_a_no_speed_scaling_symbols()
	GameSession.reset_for_new_game()
	_setup_mars_scannable()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_and_run)


func _test_a_no_speed_scaling_symbols() -> void:
	var hits: Array[String] = []
	for rel_path: String in SCAN_PATHS:
		var full_path: String = ProjectSettings.globalize_path(rel_path)
		if not FileAccess.file_exists(full_path):
			continue
		var text: String = FileAccess.get_file_as_string(full_path)
		for symbol: String in FORBIDDEN_SYMBOLS:
			if text.contains(symbol):
				hits.append("%s contains %s" % [rel_path, symbol])
	if _object_info_panel_has_scan_speed_nodes():
		hits.append("object_info_panel.tscn still has ScanSpeedLabel or ScanProgressLabel")
	_results["test_a_symbol_hits"] = hits.size()
	if not hits.is_empty():
		for hit: String in hits:
			_fail("Test A: %s" % hit)


func _object_info_panel_has_scan_speed_nodes() -> bool:
	var tscn_path: String = ProjectSettings.globalize_path(
		"res://scenes/ui/system/object_info_panel.tscn"
	)
	if not FileAccess.file_exists(tscn_path):
		return false
	var text: String = FileAccess.get_file_as_string(tscn_path)
	return text.contains("ScanSpeedLabel") or text.contains("ScanProgressLabel")


func _setup_and_run() -> void:
	var system_ui: SystemUIController = (
		_system_scene.get_node_or_null("SystemUIController") as SystemUIController
	)
	_automation = _find_automation_controller(_system_scene)
	_object_info = system_ui.object_info_panel if system_ui != null else null
	_scan_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/ScanWithDroneButton"
	) as Button if _object_info != null else null
	if _automation == null or _object_info == null or _scan_button == null:
		_fail("Missing controllers or ObjectInfoPanel")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_sd_at_start = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_at_start = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_test_b_multi_assign()
	_test_c_no_timing_change()
	_poll_completion()


func _test_b_multi_assign() -> void:
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if not _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test B: SharedScanJob missing after launch")
	var assigned_one: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_b_assigned_one"] = assigned_one
	if assigned_one != 1:
		_fail("Test B: expected assigned_unit_count 1 after launch, got %d" % assigned_one)
	_grant_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
		_fail("Test B: assign_scan_drone_to_shared_job failed")
		return
	var assigned_two: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_b_assigned_two"] = assigned_two
	if assigned_two != 2:
		_fail("Test B: expected assigned_unit_count 2, got %d" % assigned_two)
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != _sd_at_start:
		_fail("Test B: SurveyData changed on assign")
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != _scan_state_at_start:
		_fail("Test B: scan state changed on assign")


func _test_c_no_timing_change() -> void:
	var snap: Dictionary = _automation.get_shared_scan_job_debug_snapshot()
	var jobs: Dictionary = snap.get("jobs", {}) as Dictionary
	if jobs.is_empty():
		_fail("Test C: no SharedScanJob in debug snapshot")
		return
	var first_job: Dictionary = jobs.values()[0] as Dictionary
	_work_required_one_drone = float(first_job.get("work_required", -1.0))
	_results["test_c_work_required"] = _work_required_one_drone
	if _work_required_one_drone > 1.01:
		_fail(
			"Test C: work_required should not use scan duration for speed (got %s)"
			% _work_required_one_drone
		)
	if first_job.has("effective_speed_multiplier"):
		_fail("Test C: debug snapshot must not expose effective_speed_multiplier")
	if float(first_job.get("progress", -1.0)) != 0.0:
		_fail("Test C: in-flight progress expected 0 before primary arrival")


func _poll_completion(frames_left: int = 4000) -> void:
	_automation = _find_automation_controller(_system_scene)
	if _automation == null:
		_fail("Completion poll: AutomationController missing")
		_test_d_regression()
		_finish()
		return
	var active_jobs: int = _automation.get_active_shared_scan_job_count()
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(
			TARGET_OBJECT_ID, 0
		)
	)
	if active_jobs == 0 and support_n >= 1:
		_assert_completion_once()
		_test_d_regression()
		_finish()
		return
	if frames_left <= 0:
		_notes.append("Completion poll timed out")
		_assert_completion_once()
		_test_d_regression()
		_finish()
		return
	_wait_frames(30, _poll_completion.bind(frames_left - 30))


func _assert_completion_once() -> void:
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_results["test_c_sd_delta"] = sd_after - _sd_at_start
	_results["test_c_scan_after"] = scan_after
	if sd_after <= _sd_at_start:
		_fail("Test C: expected SurveyData reward exactly once")
	if scan_after == _scan_state_at_start:
		_fail("Test C: scan state unchanged after completion")
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test C: stale active SharedScanJob after completion")


func _test_d_regression() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("Regression: SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("Regression: KEY_SCAN_ALREADY_IN_PROGRESS missing")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("Regression: tooltip_text count expected 0, got %d" % tooltip_count)
	if not _automation.has_method("assign_scan_drone_to_shared_job"):
		_fail("Regression: Step 6 assign_scan_drone_to_shared_job missing")
	if not _automation.has_method("get_assigned_scan_drone_count_for_target"):
		_fail("Regression: assigned scan drone count API missing")
	var tel: BalanceTelemetryLogger = BalanceTelemetryLogger.new()
	add_child(tel)
	var snap: Dictionary = tel.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	for key: String in [
		"assigned_drones_per_target",
		"shared_scan_jobs",
	]:
		if not snap.has(key):
			_fail("Regression: telemetry key missing '%s'" % key)
	var shared_jobs: Dictionary = snap.get("shared_scan_jobs", {}) as Dictionary
	if shared_jobs.has("max_shared_scan_speed_multiplier"):
		_fail("Regression: telemetry must not expose max_shared_scan_speed_multiplier")
	if str(shared_jobs.get("completion_owner", "")) != "shared_scan_job":
		_notes.append("Regression: completion_owner not shared_scan_job at end state")
	tel.queue_free()


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _grant_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 500)
	GameSession.add_base_resource(BASE_ID, "Copper", 500)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Carbon", 500)


func _find_automation_controller(root: Node) -> AutomationController:
	if root == null:
		return null
	for child: Node in root.get_children():
		if child is AutomationController:
			return child as AutomationController
		var nested: AutomationController = _find_automation_controller(child)
		if nested != null:
			return nested
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
	push_error("[SharedScanJobStep7RollbackSmoke] FAIL: %s" % message)


func _finish() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== SharedScanJob Step 7 Speed Scaling Rollback Smoke ===")
	print("Status: %s" % status)
	print("Results: %s" % str(_results))
	if not _notes.is_empty():
		print("Notes: %s" % ", ".join(_notes))
	if not _failures.is_empty():
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
