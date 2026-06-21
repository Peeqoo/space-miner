## ObjectInfo simple action button labels smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_simple_action_button_labels_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH

const MINE_BUTTON_TEXT: String = "Mine"
const SCAN_BUTTON_TEXT: String = "Scan"

const FORBIDDEN_LABELS: PackedStringArray = [
	"Assign MiningShip",
	"Assign ScanDrone",
	"Basic Scan",
	"Deep Scan",
	"Special Scan",
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _mining_count_label: Label = null
var _scan_count_label: Label = null
var _mine_button: Button = null
var _scan_button: Button = null

var _sd_at_start: int = 0


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
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

	_mining_count_label = _object_info.get_node_or_null(
		"Margin/Root/OrbitStatusSection/MiningShipCountLabel"
	) as Label
	_scan_count_label = _object_info.get_node_or_null(
		"Margin/Root/OrbitStatusSection/ScanDroneCountLabel"
	) as Label
	_mine_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/SendMiningShipButton"
	) as Button
	_scan_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/ScanWithDroneButton"
	) as Button
	if _mine_button == null or _scan_button == null:
		_fail("Mine or Scan button missing")
		_finish()
		return

	_automation.ensure_starting_units(BASE_ID)
	_sd_at_start = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")

	_setup_mars_mineable()
	_test_a_mining_no_active_ship()
	_test_b_mining_active_ship()
	_test_c_mining_disabled()
	_prepare_for_scan_tests()
	_test_d_scan_no_active_job()
	_test_e_scan_active_job()
	_test_f_scan_disabled()
	_poll_completion_for_test_g()


func _test_a_mining_no_active_ship() -> void:
	_refresh_mars_selection()
	_results["test_a_assigned"] = _read_mining_assigned_count()
	_results["test_a_button"] = _mine_button.text
	_assert_mine_label("Test A")
	if _read_mining_assigned_count() != 0:
		_fail("Test A: expected assigned count 0")
	if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test A: launch_mining_ship failed")
	_refresh_mars_selection()
	if _read_mining_assigned_count() < 1:
		_fail("Test A: click path should start mining (assigned >= 1)")


func _test_b_mining_active_ship() -> void:
	_refresh_mars_selection()
	var assigned: int = _read_mining_assigned_count()
	_results["test_b_assigned"] = assigned
	_results["test_b_button"] = _mine_button.text
	_assert_mine_label("Test B")
	if assigned < 1:
		_fail("Test B: expected assigned count >= 1, got %d" % assigned)
	_grant_mining_build_resources()
	if GameSession.build_base_mining_ship(BASE_ID):
		_automation.spawn_idle_mining_ship_at_base(BASE_ID)
	if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test B: second launch_mining_ship failed")
		return
	_refresh_mars_selection()
	assigned = _read_mining_assigned_count()
	_results["test_b_assigned_after"] = assigned
	if assigned != 2:
		_fail("Test B: expected assigned count 2, got %d" % assigned)
	_assert_mine_label("Test B after assign")


func _test_c_mining_disabled() -> void:
	if _automation.has_available_mining_ship():
		_grant_mining_build_resources()
		var guard: int = 0
		while _automation.has_available_mining_ship() and guard < 8:
			guard += 1
			if not GameSession.build_base_mining_ship(BASE_ID):
				break
			_automation.spawn_idle_mining_ship_at_base(BASE_ID)
			if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
				break
	_refresh_mars_selection()
	var assigned: int = _read_mining_assigned_count()
	_results["test_c_assigned"] = assigned
	_results["test_c_disabled"] = _mine_button.disabled
	_results["test_c_button"] = _mine_button.text
	_assert_mine_label("Test C")
	if _automation.has_available_mining_ship():
		_notes.append("Test C: idle mining ship still available — partial check")
	if not _mine_button.disabled:
		_fail("Test C: mine button should be disabled when no idle MiningShip")
	if assigned < 1:
		_fail("Test C: assigned count should remain visible (>= 1)")


func _prepare_for_scan_tests() -> void:
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _test_d_scan_no_active_job() -> void:
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_d_assigned"] = assigned
	_results["test_d_button"] = _scan_button.text
	_assert_scan_label("Test D")
	if assigned != 0:
		_fail("Test D: expected assigned count 0, got %d" % assigned)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	_refresh_mars_selection()
	if not _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test D: SharedScanJob missing after launch")


func _test_e_scan_active_job() -> void:
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_e_assigned"] = assigned
	_results["test_e_button"] = _scan_button.text
	_assert_scan_label("Test E")
	if assigned < 1:
		_fail("Test E: expected assigned count >= 1, got %d" % assigned)
	_grant_scan_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
		_fail("Test E: assign_scan_drone_to_shared_job failed")
		return
	_refresh_mars_selection()
	assigned = _read_scan_assigned_count()
	_results["test_e_assigned_after"] = assigned
	if assigned != 2:
		_fail("Test E: expected assigned count 2, got %d" % assigned)
	_assert_scan_label("Test E after assign")


func _test_f_scan_disabled() -> void:
	while _has_idle_scan_drone():
		if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
			break
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_f_assigned"] = assigned
	_results["test_f_disabled"] = _scan_button.disabled
	_results["test_f_button"] = _scan_button.text
	_assert_scan_label("Test F")
	if _has_idle_scan_drone():
		_notes.append("Test F: idle scan drone still available — partial check")
	if not _scan_button.disabled:
		_fail("Test F: scan button should be disabled when no idle ScanDrone")
	if assigned < 1:
		_fail("Test F: assigned count should remain visible (>= 1)")


func _poll_completion_for_test_g(frames_left: int = 400) -> void:
	if _automation.get_active_shared_scan_job_count() == 0:
		_test_g_support_only_after_completion()
		_regression_checks()
		_finish()
		return
	if frames_left <= 0:
		_notes.append("Test G: completion poll timed out")
		_test_g_support_only_after_completion()
		_regression_checks()
		_finish()
		return
	_wait_frames(30, _poll_completion_for_test_g.bind(frames_left - 1))


func _test_g_support_only_after_completion() -> void:
	_refresh_mars_selection()
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	_results["test_g_support"] = support_n
	_results["test_g_button"] = _scan_button.text
	_results["test_g_has_active_job"] = _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID)
	if _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test G: support-only must not show active SharedScanJob")
	_assert_scan_label("Test G")
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if sd_after <= _sd_at_start:
		_fail("Test G: expected SurveyData reward once during completion poll")


func _assert_mine_label(test_id: String) -> void:
	if _mine_button.text != MINE_BUTTON_TEXT:
		_fail("%s: expected '%s', got '%s'" % [test_id, MINE_BUTTON_TEXT, _mine_button.text])
	for forbidden: String in FORBIDDEN_LABELS:
		if _mine_button.text == forbidden or _mine_button.text.contains(forbidden):
			_fail("%s: forbidden label '%s'" % [test_id, forbidden])


func _assert_scan_label(test_id: String) -> void:
	if _scan_button.text != SCAN_BUTTON_TEXT:
		_fail("%s: expected '%s', got '%s'" % [test_id, SCAN_BUTTON_TEXT, _scan_button.text])
	for forbidden: String in FORBIDDEN_LABELS:
		if _scan_button.text == forbidden or _scan_button.text.contains(forbidden):
			_fail("%s: forbidden label '%s'" % [test_id, forbidden])
	if _scan_button.text.to_lower().contains("scan speed"):
		_fail("%s: must not show scan speed text" % test_id)


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _setup_mars_mineable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)


func _grant_mining_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Silicon", 200)
	GameSession.add_base_resource(BASE_ID, "Iron", 800)


func _grant_scan_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 500)
	GameSession.add_base_resource(BASE_ID, "Copper", 500)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Carbon", 500)


func _read_mining_assigned_count() -> int:
	if _mining_count_label != null and _mining_count_label.visible:
		var text: String = _mining_count_label.text
		var parts: PackedStringArray = text.split(":")
		if parts.size() >= 2:
			return int(parts[1].strip_edges())
	return int(_object_info._live_action_cache.get("assigned_mining_ship_count", 0))


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
	push_error("[ObjectInfoSimpleActionButtonLabelsSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ObjectInfo Simple Action Button Labels Smoke ===")
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
