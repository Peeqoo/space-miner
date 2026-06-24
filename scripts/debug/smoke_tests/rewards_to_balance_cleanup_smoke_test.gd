## Rewards-to-balance cleanup smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/rewards_to_balance_cleanup_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const BALANCE_PATH: String = "res://data/balance/v0_1_balance.tres"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const SIGNAL_OBJECT_ID: String = "venus"
const BASE_ID: String = BaseStore.BASE_EARTH

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _automation: AutomationController = null
var _spc: SurveyProbeMissionController = null
var _balance: GameBalanceDefinition = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_balance = GameSession.get_game_balance()
	_test_a_balance_fields()
	_test_c_reward_lookup_by_state()
	_load_system_scene()


func _load_system_scene() -> void:
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_runtime_tests)


func _setup_runtime_tests() -> void:
	_automation = _find_automation_controller(_system_scene)
	_spc = _find_survey_probe_controller(_system_scene)
	if _automation == null:
		_fail("AutomationController missing")
		_finish()
		return
	if _spc == null:
		_fail("SurveyProbeMissionController missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_test_e_investigate_reward()


func _after_investigate_tests() -> void:
	_setup_mars_scannable()
	_test_b_basic_scan_reward()


func _test_a_balance_fields() -> void:
	var tres_balance: GameBalanceDefinition = load(BALANCE_PATH) as GameBalanceDefinition
	if tres_balance == null:
		_fail("Test A: could not load v0_1_balance.tres")
		return
	var session_balance: GameBalanceDefinition = GameSession.get_game_balance()
	if session_balance == null:
		_fail("Test A: GameSession.get_game_balance() returned null")
		return

	_results["test_a_basic"] = tres_balance.scan_basic_survey_data_reward
	_results["test_a_deep"] = tres_balance.scan_deep_survey_data_reward
	_results["test_a_special"] = tres_balance.scan_special_survey_data_reward
	_results["test_a_investigate"] = tres_balance.survey_probe_investigate_survey_data_reward

	if tres_balance.scan_basic_survey_data_reward != 10:
		_fail("Test A: basic_scan reward expected 10, got %d" % tres_balance.scan_basic_survey_data_reward)
	if tres_balance.scan_deep_survey_data_reward != 25:
		_fail("Test A: deep_scan reward expected 25, got %d" % tres_balance.scan_deep_survey_data_reward)
	if tres_balance.scan_special_survey_data_reward != 50:
		_fail("Test A: special_scan reward expected 50, got %d" % tres_balance.scan_special_survey_data_reward)
	if tres_balance.survey_probe_investigate_survey_data_reward != 5:
		_fail("Test A: investigate reward expected 5, got %d" % tres_balance.survey_probe_investigate_survey_data_reward)

	if session_balance.scan_basic_survey_data_reward != tres_balance.scan_basic_survey_data_reward:
		_fail("Test A: session balance basic reward mismatch vs .tres")


func _test_c_reward_lookup_by_state() -> void:
	var balance: GameBalanceDefinition = GameBalanceDefinition.new()
	_results["test_c_basic_lookup"] = balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_BASIC)
	_results["test_c_deep_lookup"] = balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_DEEP)
	_results["test_c_special_lookup"] = balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_SPECIAL)
	_results["test_c_unknown_lookup"] = balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_UNKNOWN)

	if balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_BASIC) != 10:
		_fail("Test C: BASIC lookup expected 10")
	if balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_DEEP) != 25:
		_fail("Test C: DEEP lookup expected 25")
	if balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_SPECIAL) != 50:
		_fail("Test C: SPECIAL lookup expected 50")
	if balance.get_scan_survey_data_reward_for_state(GameSession.SCAN_UNKNOWN) != 0:
		_fail("Test C: UNKNOWN lookup expected 0")
	if balance.get_survey_probe_investigate_survey_data_reward() != 5:
		_fail("Test C: investigate lookup expected 5")

	_notes.append(
		"Test C: Deep/Special runtime scan not fully simulated — direct balance lookup used."
	)


func _test_b_basic_scan_reward() -> void:
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var expected: int = _balance.scan_basic_survey_data_reward
	_results["test_b_sd_before"] = sd_before
	_results["test_b_expected"] = expected

	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	_poll_basic_scan_complete(sd_before, expected, 0)


func _poll_basic_scan_complete(sd_before: int, expected: int, pass_index: int) -> void:
	if pass_index >= 400:
		_fail("Test B: basic scan completion poll timed out")
		_after_basic_scan_tests()
		return
	if (
		_automation.get_active_shared_scan_job_count() == 0
		and GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) == GameSession.SCAN_BASIC
	):
		var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
		var delta: int = sd_after - sd_before
		_results["test_b_sd_after"] = sd_after
		_results["test_b_delta"] = delta
		if delta != expected:
			_fail("Test B: SurveyData delta expected %d, got %d" % [expected, delta])
		_after_basic_scan_tests()
		return
	_wait_frames(30, _poll_basic_scan_complete.bind(sd_before, expected, pass_index + 1))


func _after_basic_scan_tests() -> void:
	_test_d_rescan_no_farming()


func _test_d_rescan_no_farming() -> void:
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != GameSession.SCAN_BASIC:
		_notes.append("Test D: Mars not basic — rescan check skipped")
		_regression_checks()
		_finish()
		return

	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_results["test_d_sd_before"] = sd_before

	if _automation.idle_drones.is_empty():
		_grant_scan_build_resources()
		if GameSession.build_base_drone(BASE_ID):
			_automation.spawn_idle_drone_at_base(BASE_ID)

	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	_poll_rescan_no_reward(sd_before, 0)


func _poll_rescan_no_reward(sd_before: int, pass_index: int) -> void:
	if pass_index >= 400:
		_fail("Test D: rescan completion poll timed out")
		_regression_checks()
		_finish()
		return
	if _automation.get_active_shared_scan_job_count() == 0:
		var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
		_results["test_d_sd_after"] = sd_after
		if sd_after != sd_before:
			_fail("Test D: rescan farmed SurveyData (%d -> %d)" % [sd_before, sd_after])
		_regression_checks()
		_finish()
		return
	_wait_frames(30, _poll_rescan_no_reward.bind(sd_before, pass_index + 1))


func _test_e_investigate_reward() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, SIGNAL_OBJECT_ID, GameSession.DISCOVERY_SIGNAL)
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var expected: int = _balance.survey_probe_investigate_survey_data_reward
	_results["test_e_sd_before"] = sd_before
	_results["test_e_expected"] = expected

	if not _spc.try_start_investigate_signal(SIGNAL_OBJECT_ID, BASE_ID):
		_fail("Test E: try_start_investigate_signal failed")
		return
	_poll_investigate_complete(sd_before, expected, 0)


func _poll_investigate_complete(sd_before: int, expected: int, pass_index: int) -> void:
	if pass_index >= 1200:
		_fail("Test E: investigate completion poll timed out")
		_after_investigate_tests()
		return
	var known: bool = (
		GameSession.get_object_discovery_state(SYSTEM_ID, SIGNAL_OBJECT_ID) == GameSession.DISCOVERY_KNOWN
	)
	if not _spc.is_investigate_active(SIGNAL_OBJECT_ID) and known:
		var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
		var delta: int = sd_after - sd_before
		_results["test_e_sd_after"] = sd_after
		_results["test_e_delta"] = delta
		if delta != expected:
			_fail("Test E: investigate SurveyData delta expected %d, got %d" % [expected, delta])
		_after_investigate_tests()
		return
	_wait_frames(30, _poll_investigate_complete.bind(sd_before, expected, pass_index + 1))


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


func _grant_scan_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 500)
	GameSession.add_base_resource(BASE_ID, "Copper", 500)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Carbon", 500)


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
	push_error("[RewardsToBalanceCleanupSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== Rewards To Balance Cleanup Smoke ===")
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
