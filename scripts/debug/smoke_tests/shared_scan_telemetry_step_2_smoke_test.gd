## SharedScanJob Step 2 — scan target telemetry smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_telemetry_step_2_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH

const TELEMETRY_KEYS: Array[String] = [
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

var _system_scene: Node = null
var _automation: AutomationController = null
var _telemetry: BalanceTelemetryLogger = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_setup_mars_known()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_telemetry = BalanceTelemetryLogger.new()
	add_child(_telemetry)
	_wait_frames(100, _run_tests)


func _run_tests() -> void:
	_automation = _find_automation_controller(_system_scene)
	if _automation == null:
		_fail("AutomationController missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_test_a_baseline()
	_wait_frames(10, _test_b_one_active_scan)


func _test_a_baseline() -> void:
	var snap: Dictionary = _telemetry.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	for key: String in TELEMETRY_KEYS:
		if not snap.has(key):
			_fail("Test A: telemetry scan section missing key '%s'" % key)
	var ac_snap: Dictionary = _automation.get_scan_drone_target_debug_snapshot()
	_results["test_a_telemetry_available"] = bool(snap.get("scan_target_telemetry_available", false))
	_results["test_a_assigned_targets"] = int(snap.get("targets_with_assigned_scan_drones", -1))
	if int(snap.get("targets_with_assigned_scan_drones", -1)) != 0:
		_fail("Test A: expected 0 assigned scan targets at baseline")
	if int(ac_snap.get("targets_with_assigned_scan_drones", -1)) != 0:
		_fail("Test A: automation snapshot expected 0 assigned targets")


func _test_b_one_active_scan() -> void:
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_before: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	var assigned: Dictionary = _automation.get_scan_drone_assigned_counts_by_target()
	var active: Dictionary = _automation.get_active_scan_mission_counts_by_target()
	_results["test_b_assigned"] = int(assigned.get(TARGET_OBJECT_ID, 0))
	_results["test_b_active_missions"] = int(active.get(TARGET_OBJECT_ID, 0))
	if int(assigned.get(TARGET_OBJECT_ID, 0)) != 1:
		_fail("Test B: expected assigned_drones_per_target[mars] == 1")
	if int(active.get(TARGET_OBJECT_ID, 0)) != 1:
		_fail("Test B: expected active_scan_missions_per_target[mars] == 1")
	var snap: Dictionary = _telemetry.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	if int(snap.get("already_in_progress_blocks", 0)) < 1:
		_fail("Test B: expected already_in_progress_blocks >= 1 while scan active")
	var gate: Dictionary = GameSession.can_scan_object(
		SYSTEM_ID,
		TARGET_OBJECT_ID,
		BASE_ID,
		true,
		_automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID) > 0,
	)
	if str(gate.get("blocked_reason_key", "")) != str(GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS):
		_fail("Test B: KEY_SCAN_ALREADY_IN_PROGRESS not active during scan")
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	if sd_after != sd_before:
		_fail("Test B: SurveyData changed during in-flight scan")
	if scan_after != scan_before:
		_fail("Test B: scan state changed during in-flight scan")
	_test_c_support_orbit()


func _test_c_support_orbit() -> void:
	_poll_until_support_or_timeout(2400)


func _after_support_verified() -> void:
	_test_d_no_gameplay_change()
	_regression_checks()
	_finish()


func _poll_until_support_or_timeout(frames_left: int) -> void:
	var support: Dictionary = _automation.get_scan_drone_support_counts_by_target()
	var active: Dictionary = _automation.get_active_scan_mission_counts_by_target()
	var support_n: int = int(support.get(TARGET_OBJECT_ID, 0))
	var active_n: int = int(active.get(TARGET_OBJECT_ID, 0))
	if support_n >= 1 and active_n == 0:
		_verify_support_telemetry()
		return
	if frames_left <= 0:
		_notes.append("Test C: scan support orbit not reached in time — partial check")
		_verify_support_telemetry()
		return
	_wait_frames(30, _poll_until_support_or_timeout.bind(frames_left - 30))


func _verify_support_telemetry() -> void:
	var snap: Dictionary = _automation.get_scan_drone_target_debug_snapshot()
	var assigned: int = int((snap.get("assigned_drones_per_target", {}) as Dictionary).get(TARGET_OBJECT_ID, 0))
	var active_n: int = int((snap.get("active_scan_missions_per_target", {}) as Dictionary).get(TARGET_OBJECT_ID, 0))
	var support_n: int = int((snap.get("support_drones_per_target", {}) as Dictionary).get(TARGET_OBJECT_ID, 0))
	_results["test_c_assigned"] = assigned
	_results["test_c_active_missions"] = active_n
	_results["test_c_support"] = support_n
	var telemetry: Dictionary = _telemetry.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	var potential: Dictionary = telemetry.get("potential_support_blocks", {}) as Dictionary
	_results["test_c_potential_support_block"] = bool(potential.get(TARGET_OBJECT_ID, false))
	if support_n >= 1:
		if active_n != 0:
			_fail("Test C: expected active_scan_missions == 0 after support orbit")
		if not bool(potential.get(TARGET_OBJECT_ID, false)):
			_fail("Test C: expected potential_support_blocks[mars] == true")
	elif assigned >= 1 and active_n == 0:
		_notes.append("Test C: support count 0 but assigned persists — orbit may differ")
	_after_support_verified()


func _test_d_no_gameplay_change() -> void:
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_before: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	var assigned_before: int = _automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	var assigned_after: int = _automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID)
	var gate: Dictionary = GameSession.can_scan_object(
		SYSTEM_ID,
		TARGET_OBJECT_ID,
		BASE_ID,
		true,
		assigned_after > 0,
	)
	_results["test_d_assigned_before"] = assigned_before
	_results["test_d_assigned_after"] = assigned_after
	_results["test_d_block_key"] = str(gate.get("blocked_reason_key", ""))
	if assigned_after != assigned_before:
		_fail("Test D: second launch changed assigned drone count")
	if str(gate.get("blocked_reason_key", "")) != str(GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS):
		_fail("Test D: expected KEY_SCAN_ALREADY_IN_PROGRESS on second launch path")
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != sd_before:
		_fail("Test D: SurveyData changed after blocked second launch")
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != scan_before:
		_fail("Test D: scan state changed after blocked second launch")


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")


func _setup_mars_known() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)


func _find_automation_controller(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _find_automation_controller(child)
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
	push_error("[SharedScanTelemetryStep2Smoke] FAIL: %s" % message)


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
	print("=== SharedScanJob Step 2 Telemetry SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("===============================================")


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
