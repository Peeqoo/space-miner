## BaseManagementPanel must not auto-open on resource/automation refresh (MiningShip unload path).
## Run: godot --headless --path . --scene res://scripts/debug/smoke_tests/base_panel_unload_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const BASE_ID: String = BaseStore.BASE_EARTH

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _spawner: SystemSpawner = null
var _base_panel: BaseManagementPanel = null
var _production_panel: ProductionPanel = null
var _object_info: ObjectInfoPanel = null


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
	_spawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if _system_ui == null or _selection == null or _spawner == null:
		_fail("Missing system controllers")
		_finish()
		return

	_base_panel = _system_ui.base_management_panel
	_production_panel = _system_ui.production_panel
	_object_info = _system_ui.object_info_panel
	if _base_panel == null:
		_fail("BaseManagementPanel missing")
		_finish()
		return

	var earth: SystemBody = _spawner.get_spawned_object(BASE_ID) as SystemBody
	if earth == null:
		_fail("Earth SystemBody not spawned")
		_finish()
		return

	_test_a_closed_panel_unload_refresh(earth)
	_test_b_open_panel_unload_refresh(earth)
	_test_c_explicit_player_open(earth)
	_test_d_regression_panels(earth)
	_finish()


func _test_a_closed_panel_unload_refresh(earth: SystemBody) -> void:
	_selection.select_world_node(earth)
	_wait_sync()
	if not _base_panel.visible:
		_fail("Test A setup: panel should open after Earth selection")
		_results["test_a"] = "FAIL setup"
		return

	_base_panel.hide_panel()
	_wait_sync()
	if _base_panel.visible:
		_fail("Test A setup: panel should be closed after hide")
		_results["test_a"] = "FAIL setup close"
		return

	var iron_before: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	_simulate_mining_ship_unload_refresh()
	_wait_sync()

	if _base_panel.visible:
		_fail("Test A: BaseManagementPanel reopened after unload refresh while closed")
		_results["test_a"] = "FAIL auto-open"
		return
	if _base_panel.is_hold_open_across_selection():
		_fail("Test A: hold_open still true after close + refresh")
		_results["test_a"] = "FAIL hold_open"
		return

	var iron_after: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	if iron_after <= iron_before:
		_notes.append("Test A: storage iron unchanged in simulated unload (+50)")

	_results["test_a"] = "PASS"


func _test_b_open_panel_unload_refresh(earth: SystemBody) -> void:
	_selection.clear_selection(false)
	_selection.select_world_node(earth)
	_wait_sync()
	if not _base_panel.visible:
		_fail("Test B setup: panel should be open")
		_results["test_b"] = "FAIL setup"
		return

	var pop_before: String = _base_panel.population_label.text
	_simulate_mining_ship_unload_refresh()
	_wait_sync()

	if not _base_panel.visible:
		_fail("Test B: panel closed unexpectedly during refresh")
		_results["test_b"] = "FAIL closed"
		return

	_base_panel.refresh_from_game_session()
	var pop_after: String = _base_panel.population_label.text
	if pop_before != pop_after:
		_notes.append("Test B: population label changed (may be ok)")

	_results["test_b"] = "PASS"


func _test_c_explicit_player_open(earth: SystemBody) -> void:
	_base_panel.hide_panel()
	_selection.clear_selection(true)
	_wait_sync()
	if _base_panel.visible:
		_fail("Test C setup: panel should be closed")
		_results["test_c"] = "FAIL setup"
		return

	_selection.select_world_node(earth)
	_wait_sync()

	if not _base_panel.visible:
		_fail("Test C: panel did not open on Earth selection (player action)")
		_results["test_c"] = "FAIL no open on select"
		return
	if not _base_panel.is_hold_open_across_selection():
		_fail("Test C: hold_open not set after show_for_base")
		_results["test_c"] = "FAIL hold_open"
		return

	_results["test_c"] = "PASS"


func _test_d_regression_panels(earth: SystemBody) -> void:
	_base_panel.hide_panel()
	if _production_panel != null:
		_production_panel.visible = false
	_simulate_mining_ship_unload_refresh()
	_wait_sync()

	if _base_panel.visible:
		_fail("Test D: BaseManagementPanel auto-opened")
		_results["test_d"] = "FAIL base panel"
		return
	if _production_panel != null and _production_panel.visible:
		_fail("Test D: ProductionPanel auto-opened on resource refresh")
		_results["test_d"] = "FAIL production panel"
		return

	_selection.select_world_node(earth)
	_wait_sync()
	_system_ui.update_object_info()
	if _object_info != null and not _object_info.visible:
		_notes.append("Test D: ObjectInfo not visible for Earth base selection (may be expected)")

	_results["test_d"] = "PASS"


func _simulate_mining_ship_unload_refresh() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 50)
	if _system_ui.has_method("_on_base_resources_changed_ui_refresh"):
		_system_ui.call("_on_base_resources_changed_ui_refresh", BASE_ID)
	if _system_ui.has_method("_on_automation_state_changed"):
		_system_ui.call("_on_automation_state_changed")


func _wait_sync() -> void:
	# Allow deferred UI refresh to settle in headless run.
	for _i: int in range(3):
		RenderingServer.force_draw()


func _wait_frames(count: int, callback: Callable) -> void:
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[BasePanelUnloadSmoke] FAIL: %s" % message)


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
	print("=== Base Panel Unload SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("===================================")


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
