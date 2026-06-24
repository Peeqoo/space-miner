## ObjectInfo recall button language pass smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_recall_button_language_pass_smoke_runner.tscn
extends Node

const PANEL_SCENE_PATH: String = "res://scenes/ui/system/object_info_panel.tscn"
const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH

const RECALL_DRONE_TEXT: String = "Recall Drone"
const RECALL_SHIP_TEXT: String = "Recall Ship"

const FORBIDDEN_GERMAN: PackedStringArray = [
	"zurück",
	"Zurück",
	"Drone zurück",
	"Schiff zurück",
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _recall_drone_button: Button = null
var _recall_ship_button: Button = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_run_test_a_then_system()


func _run_test_a_then_system() -> void:
	var packed: PackedScene = load(PANEL_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Test A: could not load object_info_panel.tscn")
		_load_system_scene()
		return

	var panel := packed.instantiate() as ObjectInfoPanel
	if panel == null:
		_fail("Test A: ObjectInfoPanel instantiate failed")
		_load_system_scene()
		return

	add_child(panel)
	_wait_frames(2, func() -> void:
		_check_recall_button_text(panel.recall_drone_button, RECALL_DRONE_TEXT, "RecallDroneButton")
		_check_recall_button_text(panel.recall_mining_ship_button, RECALL_SHIP_TEXT, "RecallMiningShipButton")
		_results["test_a_drone_text"] = panel.recall_drone_button.text
		_results["test_a_ship_text"] = panel.recall_mining_ship_button.text
		panel.queue_free()
		_load_system_scene()
	)


func _load_system_scene() -> void:
	_setup_mars_scannable()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_runtime_tests)


func _setup_runtime_tests() -> void:
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	_selection = _system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	_automation = _find_automation_controller(_system_scene)
	_object_info = _system_ui.object_info_panel if _system_ui != null else null
	if _system_ui == null or _selection == null or _automation == null or _object_info == null:
		_fail("Missing controllers or ObjectInfoPanel")
		_finish()
		return

	_recall_drone_button = _object_info.recall_drone_button
	_recall_ship_button = _object_info.recall_mining_ship_button
	_automation.ensure_starting_units(BASE_ID)
	_test_b_scan_drone_recall()


func _test_b_scan_drone_recall() -> void:
	_refresh_mars_selection()
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	_refresh_mars_selection()

	_check_recall_button_text(_recall_drone_button, RECALL_DRONE_TEXT, "runtime RecallDroneButton")
	if not _recall_drone_button.visible:
		_fail("Test B: RecallDroneButton should be visible with active scan drone")

	var before: int = _scan_drones_at_target()
	_results["test_b_drones_before_recall"] = before
	_results["test_b_object_id"] = _object_info.current_object_id
	if _object_info.current_object_id != TARGET_OBJECT_ID:
		_fail("Test B: current_object_id expected '%s', got '%s'" % [
			TARGET_OBJECT_ID, _object_info.current_object_id,
		])
	if before < 1:
		_fail("Test B: expected >= 1 scan drone at target before recall, got %d" % before)
		_test_c_mining_ship_recall()
		return

	_object_info._on_recall_drone_pressed()
	_poll_scan_recall(before, 80)


func _poll_scan_recall(before: int, frames_left: int) -> void:
	_refresh_mars_selection()
	var after: int = _scan_drones_at_target()
	if after < before:
		_results["test_b_drones_after_recall"] = after
		_test_c_mining_ship_recall()
		return
	if frames_left <= 0:
		_results["test_b_drones_after_recall"] = after
		_fail("Test B: scan drone recall did not reduce target count (%d -> %d)" % [before, after])
		_test_c_mining_ship_recall()
		return
	_wait_frames(5, _poll_scan_recall.bind(before, frames_left - 5))


func _test_c_mining_ship_recall() -> void:
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)
	if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
		_fail("Test C: launch_mining_ship failed")
		_regression_checks()
		_finish()
		return
	_refresh_mars_selection()

	_check_recall_button_text(_recall_ship_button, RECALL_SHIP_TEXT, "runtime RecallMiningShipButton")
	if not _recall_ship_button.visible:
		_fail("Test C: RecallMiningShipButton should be visible with active mining ship")

	var before: int = _automation.get_active_mining_ship_count_for_target(TARGET_OBJECT_ID)
	_results["test_c_ships_before_recall"] = before
	_results["test_c_object_id"] = _object_info.current_object_id
	if _object_info.current_object_id != TARGET_OBJECT_ID:
		_fail("Test C: current_object_id expected '%s', got '%s'" % [
			TARGET_OBJECT_ID, _object_info.current_object_id,
		])
	if before < 1:
		_fail("Test C: expected >= 1 mining ship at target before recall, got %d" % before)
		_regression_checks()
		_finish()
		return

	_object_info._on_recall_mining_ship_pressed()
	_poll_mining_recall(before, 120)


func _poll_mining_recall(before: int, frames_left: int) -> void:
	_refresh_mars_selection()
	var after: int = _automation.get_active_mining_ship_count_for_target(TARGET_OBJECT_ID)
	if after < before:
		_results["test_c_ships_after_recall"] = after
		_regression_checks()
		_finish()
		return
	if frames_left <= 0:
		_results["test_c_ships_after_recall"] = after
		_fail("Test C: mining ship recall did not reduce target count (%d -> %d)" % [before, after])
		_regression_checks()
		_finish()
		return
	_wait_frames(5, _poll_mining_recall.bind(before, frames_left - 5))


func _check_recall_button_text(button: Button, expected: String, label: String) -> void:
	if button == null:
		_fail("Test A: %s missing" % label)
		return
	var text: String = button.text.strip_edges()
	_results["label_%s" % label] = text
	if text != expected:
		_fail("%s expected '%s', got '%s'" % [label, expected, text])
	for forbidden: String in FORBIDDEN_GERMAN:
		if text.contains(forbidden):
			_fail("%s contains forbidden German '%s'" % [label, forbidden])


func _scan_drones_at_target() -> int:
	return (
		_automation.get_active_scan_drone_count_for_target(TARGET_OBJECT_ID)
		+ _automation.get_active_scan_drone_support_count_for_target(TARGET_OBJECT_ID)
		+ _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	)


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


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


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
	push_error("[ObjectInfoRecallButtonLanguagePassSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ObjectInfo Recall Button Language Pass Smoke ===")
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
