## DEFAULT_SCAN_DURATION_FALLBACK audit smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/default_scan_duration_fallback_audit_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SCAN_DRONE_UNIT_PATH: String = "res://data/units/scan_drone.tres"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH

const FALLBACK_CONST: float = 2.0

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _automation: AutomationController = null
var _sd_before_scan: int = 0
var _scan_state_before: String = ""


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_setup_mars_scannable()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(80, _run_tests)


func _run_tests() -> void:
	_automation = _find_automation_controller(_system_scene)
	if _automation == null:
		_fail("AutomationController missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_test_a_regular_path_uses_data_not_fallback()
	_test_b_shared_scan_job_single_reward()
	_test_c_fallback_emergency_only()
	_regression_checks()
	_finish()


func _test_a_regular_path_uses_data_not_fallback() -> void:
	var unit_def: UnitDefinition = load(SCAN_DRONE_UNIT_PATH) as UnitDefinition
	if unit_def == null:
		_fail("Test A: scan_drone.tres failed to load")
		return

	_results["test_a_unit_scan_duration_seconds"] = unit_def.scan_duration_seconds
	_results["test_a_unit_basic_layer_seconds"] = unit_def.basic_scan_duration_seconds

	if unit_def.scan_duration_seconds <= 0.0:
		_fail("Test A: scan_drone.tres scan_duration_seconds must be > 0 for normal catalog path")

	var balance := GameSession.get_game_balance()
	var expected_basic: float = 35.0
	if balance != null:
		expected_basic = balance.basic_scan_duration

	var expected_mission_duration: float = GameSession.get_scan_duration_seconds_for_target_state(
		GameSession.SCAN_BASIC,
		BASE_ID,
	)
	_results["test_a_expected_mission_duration"] = expected_mission_duration
	_results["test_a_balance_basic_scan_duration"] = expected_basic

	if absf(expected_mission_duration - expected_basic) > 0.01:
		_notes.append(
			"Test A: mission duration differs from balance basic (upgrade multiplier may apply)"
		)

	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	var unit: AutomationUnit = _first_active_scan_drone()
	if unit == null:
		_fail("Test A: no active scan drone after launch")
		return

	_results["test_a_launch_work_duration"] = unit.work_duration
	if absf(unit.work_duration - expected_mission_duration) > 0.01:
		_fail(
			"Test A: launch work_duration %.3f != get_scan_duration_seconds_for_target_state %.3f"
			% [unit.work_duration, expected_mission_duration]
		)

	if absf(unit.work_duration - FALLBACK_CONST) < 0.001 and absf(expected_mission_duration - FALLBACK_CONST) > 0.01:
		_fail("Test A: active scan appears to use DEFAULT_SCAN_DURATION_FALLBACK instead of balance path")

	var catalog := UnitCatalog.new()
	catalog.load_all()
	var from_catalog: UnitDefinition = catalog.get_definition("scan_drone")
	_results["test_a_catalog_loaded"] = from_catalog != null
	if from_catalog == null:
		_fail("Test A: UnitCatalog missing scan_drone definition — would hit emergency fallback")
	elif from_catalog.scan_duration_seconds <= 0.0:
		_fail("Test A: catalog scan_duration_seconds <= 0 — would hit emergency fallback")


func _test_b_shared_scan_job_single_reward() -> void:
	if _automation.get_active_shared_scan_job_count() == 0:
		_fail("Test B: expected active SharedScanJob from Test A launch")
		return

	_sd_before_scan = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_before = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_results["test_b_sd_before"] = _sd_before_scan
	_results["test_b_scan_state_before"] = _scan_state_before
	_poll_scan_completion(400)


func _poll_scan_completion(frames_left: int) -> void:
	if _automation.get_active_shared_scan_job_count() == 0:
		_verify_single_reward()
		return
	if frames_left <= 0:
		_notes.append("Test B: scan completion poll timed out")
		_verify_single_reward()
		return
	_wait_frames(30, _poll_scan_completion.bind(frames_left - 1))


func _verify_single_reward() -> void:
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	var balance := GameSession.get_game_balance()
	var expected_reward: int = 10
	if balance != null:
		expected_reward = balance.scan_basic_survey_data_reward

	_results["test_b_sd_after"] = sd_after
	_results["test_b_scan_state_after"] = scan_after
	_results["test_b_expected_reward"] = expected_reward
	_results["test_b_sd_delta"] = sd_after - _sd_before_scan

	if scan_after == _scan_state_before:
		_fail("Test B: scan state did not advance after completion")
	if sd_after - _sd_before_scan != expected_reward:
		_fail(
			"Test B: SurveyData delta expected %d, got %d"
			% [expected_reward, sd_after - _sd_before_scan]
		)


func _test_c_fallback_emergency_only() -> void:
	var unit_def: UnitDefinition = load(SCAN_DRONE_UNIT_PATH) as UnitDefinition
	_results["test_c_fallback_const"] = FALLBACK_CONST
	_results["test_c_unit_def_present"] = unit_def != null

	if unit_def == null:
		_notes.append(
			"Test C: scan_drone.tres missing — DEFAULT_SCAN_DURATION_FALLBACK would be used for idle/restore paths"
		)
		return

	_results["test_c_unit_scan_duration_seconds"] = unit_def.scan_duration_seconds
	if unit_def.scan_duration_seconds <= 0.0:
		_notes.append("Test C: scan_duration_seconds <= 0 — emergency fallback path reachable")
	else:
		_results["test_c_emergency_fallback_reachable_in_normal_play"] = false

	_results["test_c_mission_duration_source"] = "GameSession.get_scan_duration_seconds_for_target_state"
	_results["test_c_idle_duration_source"] = "data/units/scan_drone.tres scan_duration_seconds"


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _first_active_scan_drone() -> AutomationUnit:
	for unit_variant: Variant in _automation.active_units_by_mission_id.values():
		var unit := unit_variant as AutomationUnit
		if unit != null and unit.unit_type == AutomationUnit.UnitType.DRONE:
			return unit
	return null


func _find_automation_controller(root: Node) -> AutomationController:
	if root is AutomationController:
		return root as AutomationController
	for child: Node in root.get_children():
		var found := _find_automation_controller(child)
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
	push_error("[DefaultScanDurationFallbackAuditSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== DEFAULT_SCAN_DURATION_FALLBACK Audit Smoke ===")
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
