## ObjectInfo multi-MiningShip UI smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_multi_ms_ui_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const MINE_BUTTON_DEFAULT: String = "Mine"
const MINE_BUTTON_ASSIGN: String = "Assign MiningShip"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _base_panel: BaseManagementPanel = null
var _mining_count_label: Label = null
var _mine_button: Button = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_setup_mars_mineable()
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
	_base_panel = _system_ui.base_management_panel if _system_ui != null else null

	if _system_ui == null or _selection == null or _automation == null or _object_info == null:
		_fail("Missing system controllers or ObjectInfoPanel")
		_finish()
		return

	_mining_count_label = _object_info.get_node_or_null(
		"Margin/Root/OrbitStatusSection/MiningShipCountLabel"
	) as Label
	_mine_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/SendMiningShipButton"
	) as Button
	if _mining_count_label == null or _mine_button == null:
		_fail("MiningShipCountLabel or SendMiningShipButton missing")
		_finish()
		return

	_automation.ensure_starting_units(BASE_ID)
	_refresh_mars_selection()
	_test_a_zero_assigned()
	_test_b_one_assigned()
	_test_c_two_assigned()
	_test_d_no_idle_button_disabled()
	_test_e_base_panel_stays_closed_on_refresh()
	_regression_checks()
	_finish()


func _test_a_zero_assigned() -> void:
	_refresh_mars_selection()
	var assigned: int = _read_assigned_count()
	_results["test_a_assigned"] = assigned
	_results["test_a_button"] = _mine_button.text

	if assigned != 0:
		_fail("Test A: expected assigned count 0, got %d" % assigned)
	if _mine_button.text != MINE_BUTTON_DEFAULT:
		_fail("Test A: expected button '%s', got '%s'" % [MINE_BUTTON_DEFAULT, _mine_button.text])
	if not _mining_count_label.visible:
		_fail("Test A: MiningShipCountLabel should be visible for mineable Mars")


func _test_b_one_assigned() -> void:
	if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test B: launch_mining_ship failed")
		return
	_refresh_mars_selection()
	var assigned: int = _read_assigned_count()
	_results["test_b_assigned"] = assigned
	_results["test_b_button"] = _mine_button.text

	if assigned != 1:
		_fail("Test B: expected assigned count 1, got %d" % assigned)
	if _mine_button.text != MINE_BUTTON_ASSIGN:
		_fail("Test B: expected button '%s', got '%s'" % [MINE_BUTTON_ASSIGN, _mine_button.text])


func _test_c_two_assigned() -> void:
	_grant_build_resources()
	if not GameSession.build_base_mining_ship(BASE_ID):
		_fail("Test C: build_base_mining_ship failed")
		return
	_automation.spawn_idle_mining_ship_at_base(BASE_ID)
	if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test C: second launch_mining_ship failed")
		return
	_refresh_mars_selection()
	var assigned: int = _read_assigned_count()
	var blocked: String = str(_object_info._live_action_cache.get("mine_blocked_reason", ""))
	_results["test_c_assigned"] = assigned
	_results["test_c_button"] = _mine_button.text
	_results["test_c_mine_blocked"] = blocked

	if assigned != 2:
		_fail("Test C: expected assigned count 2, got %d" % assigned)
	if _mine_button.text != MINE_BUTTON_ASSIGN:
		_fail("Test C: expected button '%s', got '%s'" % [MINE_BUTTON_ASSIGN, _mine_button.text])
	if blocked.to_lower().contains("already"):
		_fail("Test C: unexpected 'already mining' block: %s" % blocked)


func _test_d_no_idle_button_disabled() -> void:
	if _automation.has_available_mining_ship():
		_grant_build_resources()
		while _automation.has_available_mining_ship() and GameSession.build_base_mining_ship(BASE_ID):
			_automation.spawn_idle_mining_ship_at_base(BASE_ID)
			if _automation.launch_mining_ship(TARGET_OBJECT_ID):
				continue
			break

	_refresh_mars_selection()
	var assigned: int = _read_assigned_count()
	_results["test_d_assigned"] = assigned
	_results["test_d_button_disabled"] = _mine_button.disabled

	if _automation.has_available_mining_ship():
		_notes.append("Test D: idle mining ship still available — partial check only")
	if not _mine_button.disabled:
		_fail("Test D: mine button should be disabled when no idle MiningShip")
	if assigned < 1:
		_fail("Test D: expected assigned count >= 1, got %d" % assigned)


func _test_e_base_panel_stays_closed_on_refresh() -> void:
	if _base_panel != null:
		_base_panel.hide_panel()
	for _i: int in range(5):
		_system_ui.update_object_info()
	_wait_sync()
	if _base_panel != null and _base_panel.visible:
		_fail("Test E: BaseManagementPanel opened on ObjectInfo refresh")
	_results["test_e_base_panel_visible"] = _base_panel.visible if _base_panel != null else false


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")


func _setup_mars_mineable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)


func _grant_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Silicon", 200)
	GameSession.add_base_resource(BASE_ID, "Iron", 800)


func _refresh_mars_selection() -> void:
	var mars: SystemBody = _find_body(TARGET_OBJECT_ID)
	if mars == null:
		_fail("Mars body not found for UI refresh")
		return
	_selection.select_world_node(mars)
	_system_ui.update_object_info()


func _read_assigned_count() -> int:
	var text: String = _mining_count_label.text.strip_edges()
	var parts: PackedStringArray = text.split(":")
	if parts.size() < 2:
		return -1
	return int(parts[parts.size() - 1].strip_edges())


func _find_body(body_id: String) -> SystemBody:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return null
	return spawner.get_spawned_object(body_id) as SystemBody


func _find_automation_controller(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _find_automation_controller(child)
		if found != null:
			return found
	return null


func _wait_frames(count: int, callback: Callable) -> void:
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _wait_sync() -> void:
	pass


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[ObjectInfoMultiMsUiSmoke] FAIL: %s" % message)


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
	print("=== ObjectInfo Multi-MS UI SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("========================================")


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
