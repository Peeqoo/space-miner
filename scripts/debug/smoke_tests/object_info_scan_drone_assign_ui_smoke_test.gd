## ObjectInfo ScanDrone assign UI smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_scan_drone_assign_ui_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH

const SCAN_BUTTON_BASIC: String = "Basic Scan"
const SCAN_BUTTON_ASSIGN: String = "Assign ScanDrone"
const MINE_BUTTON_ASSIGN: String = "Assign MiningShip"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _scan_count_label: Label = null
var _scan_button: Button = null
var _mine_button: Button = null

var _sd_at_start: int = 0
var _scan_state_at_start: String = ""


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
	_wait_frames(100, _setup_and_run)


func _setup_and_run() -> void:
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	_selection = _system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	_automation = _find_automation_controller(_system_scene)
	_object_info = _system_ui.object_info_panel if _system_ui != null else null
	if _system_ui == null or _selection == null or _automation == null or _object_info == null:
		_fail("Missing controllers or ObjectInfoPanel")
		_finish()
		return
	_scan_count_label = _object_info.get_node_or_null(
		"Margin/Root/OrbitStatusSection/ScanDroneCountLabel"
	) as Label
	_scan_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/ScanWithDroneButton"
	) as Button
	_mine_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/SendMiningShipButton"
	) as Button
	if _scan_count_label == null or _scan_button == null:
		_fail("ScanDroneCountLabel or ScanWithDroneButton missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_sd_at_start = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_at_start = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_test_a_normal_scan_button()
	_test_b_active_job_assign()
	_test_c_second_assign()
	_test_d_no_idle_disabled()
	_poll_completion_for_test_e()


func _test_a_normal_scan_button() -> void:
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_a_assigned"] = assigned
	_results["test_a_button"] = _scan_button.text
	_results["test_a_count_visible"] = _scan_count_label.visible
	if assigned != 0:
		_fail("Test A: expected assigned count 0, got %d" % assigned)
	if _scan_button.text != SCAN_BUTTON_BASIC:
		_fail("Test A: expected '%s', got '%s'" % [SCAN_BUTTON_BASIC, _scan_button.text])
	if _scan_button.text == "Assigned ScanDrone":
		_fail("Test A: typo 'Assigned ScanDrone' must not appear")
	if not _scan_count_label.visible:
		_fail("Test A: ScanDroneCountLabel should be visible for scannable Mars (mining parity)")


func _test_b_active_job_assign() -> void:
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if not _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test B: SharedScanJob missing after launch")
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_b_assigned"] = assigned
	_results["test_b_button"] = _scan_button.text
	_results["test_b_count_visible"] = _scan_count_label.visible
	if assigned < 1:
		_fail("Test B: expected assigned count >= 1, got %d" % assigned)
	if _scan_button.text != SCAN_BUTTON_ASSIGN:
		_fail("Test B: expected '%s', got '%s'" % [SCAN_BUTTON_ASSIGN, _scan_button.text])
	if not _scan_count_label.visible:
		_fail("Test B: ScanDroneCountLabel must stay visible with active job")


func _test_c_second_assign() -> void:
	_grant_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
		_fail("Test C: assign_scan_drone_to_shared_job failed")
		return
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_c_assigned"] = assigned
	_results["test_c_button"] = _scan_button.text
	if assigned != 2:
		_fail("Test C: expected assigned count 2, got %d" % assigned)
	if _has_idle_scan_drone() and _scan_button.text != SCAN_BUTTON_ASSIGN:
		_fail("Test C: expected '%s' when idle drone remains" % SCAN_BUTTON_ASSIGN)


func _test_d_no_idle_disabled() -> void:
	while _has_idle_scan_drone():
		if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
			break
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_d_assigned"] = assigned
	_results["test_d_button"] = _scan_button.text
	_results["test_d_disabled"] = _scan_button.disabled
	_results["test_d_count_visible"] = _scan_count_label.visible
	if _has_idle_scan_drone():
		_notes.append("Test D: idle scan drone still available — partial check")
	if not _scan_button.disabled:
		_fail("Test D: button should be disabled when no idle ScanDrone")
	if assigned < 1:
		_fail("Test D: assigned count should remain visible (>= 1), got %d" % assigned)
	if not _scan_count_label.visible:
		_fail("Test D: ScanDroneCountLabel must stay visible when button disabled")
	if _scan_button.text != SCAN_BUTTON_ASSIGN:
		_fail("Test D: disabled assign state must keep '%s', got '%s'" % [
			SCAN_BUTTON_ASSIGN, _scan_button.text,
		])


func _poll_completion_for_test_e(frames_left: int = 400) -> void:
	if _automation.get_active_shared_scan_job_count() == 0:
		_test_e_support_only_after_completion()
		_test_f_mining_regression()
		_regression_checks()
		_finish()
		return
	if frames_left <= 0:
		_notes.append("Test E: completion poll timed out")
		_test_e_support_only_after_completion()
		_test_f_mining_regression()
		_regression_checks()
		_finish()
		return
	_wait_frames(30, _poll_completion_for_test_e.bind(frames_left - 1))


func _test_e_support_only_after_completion() -> void:
	_refresh_mars_selection()
	var assigned: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	_results["test_e_assigned"] = assigned
	_results["test_e_support"] = support_n
	_results["test_e_button"] = _scan_button.text
	_results["test_e_has_active_job"] = _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID)
	if _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test E: support-only must not show active SharedScanJob")
	if _scan_button.text == SCAN_BUTTON_ASSIGN:
		_fail("Test E: support-only must not show Assign ScanDrone")
	if _scan_button.text != SCAN_BUTTON_BASIC:
		_notes.append("Test E: post-basic-scan button text is '%s'" % _scan_button.text)
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if sd_after <= _sd_at_start:
		_fail("Test E: expected SurveyData reward once during completion poll")


func _test_f_mining_regression() -> void:
	if _mine_button == null:
		_notes.append("Test F: mine button missing — skipped")
		return
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)
	if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test F: launch_mining_ship failed")
		return
	_refresh_mars_selection()
	_results["test_f_mine_button"] = _mine_button.text
	if _mine_button.text != MINE_BUTTON_ASSIGN:
		_fail("Test F: mining assign regression — expected '%s', got '%s'" % [
			MINE_BUTTON_ASSIGN, _mine_button.text,
		])


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)
	if _scan_button != null and _scan_button.text.to_lower().contains("scan speed"):
		_fail("Regression: scan button must not show scan speed text")


func _read_scan_assigned_count() -> int:
	if _scan_count_label != null and _scan_count_label.visible:
		var text: String = _scan_count_label.text
		var parts: PackedStringArray = text.split(":")
		if parts.size() >= 2:
			return int(parts[1].strip_edges())
	return int(_object_info._live_action_cache.get("assigned_scan_drone_count", 0))


func _has_idle_scan_drone() -> bool:
	return _automation != null and not _automation.idle_drones.is_empty()


func _refresh_mars_selection() -> void:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return
	var body: Node = spawner.get_spawned_object(TARGET_OBJECT_ID)
	if body != null and _selection != null:
		_selection.select_world_node(body as Node2D)
	if _system_ui != null:
		_system_ui.update_object_info()


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _grant_build_resources() -> void:
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
	push_error("[ObjectInfoScanDroneAssignUiSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ObjectInfo ScanDrone Assign UI Smoke ===")
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
