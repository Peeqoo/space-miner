## SensorPulseProgressLabel cleanup smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/sensor_pulse_progress_label_cleanup_smoke_runner.tscn
extends Node

const PANEL_SCENE_PATH: String = "res://scenes/ui/system/object_info_panel.tscn"
const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const SIGNAL_OBJECT_ID: String = "venus"
const BASE_ID: String = BaseStore.BASE_EARTH
const HIDDEN_CANDIDATE_ID: String = "jupiter"
const SIGNAL_INVESTIGATE_LABEL_PATH: String = (
	"Margin/Root/SignalInfoSubPanel/InvestigateProgressLabel"
)

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _object_info: ObjectInfoPanel = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _spc: SurveyProbeMissionController = null
var _pulse_ctrl: BaseSensorPulseController = null

var _investigate_label: Label = null
var _sensor_pulse_label: Label = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_scene_nodes()
	_load_system_scene()


func _test_a_scene_nodes() -> void:
	var packed: PackedScene = load(PANEL_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Test A: could not load object_info_panel.tscn")
		return
	var panel := packed.instantiate() as ObjectInfoPanel
	if panel == null:
		_fail("Test A: panel instantiate failed")
		return
	add_child(panel)

	var investigate: Label = panel.get_node_or_null(SIGNAL_INVESTIGATE_LABEL_PATH) as Label
	var sensor_pulse: Label = panel.get_node_or_null(
		"Margin/Root/SensorPulseProgressLabel"
	) as Label
	_results["test_a_investigate_node"] = investigate != null
	_results["test_a_sensor_pulse_node"] = sensor_pulse != null
	if investigate == null:
		_fail("Test A: InvestigateProgressLabel missing")
	if sensor_pulse == null:
		_fail("Test A: SensorPulseProgressLabel missing")
	if investigate == sensor_pulse:
		_fail("Test A: investigate and sensor pulse labels must be distinct nodes")

	panel.queue_free()


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
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	_selection = _system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	_object_info = _system_ui.object_info_panel if _system_ui != null else null
	_spc = _find_survey_probe_controller(_system_scene)
	_pulse_ctrl = _find_pulse_controller(_system_scene)
	if _object_info == null or _system_ui == null or _spc == null or _pulse_ctrl == null:
		_fail("Missing ObjectInfoPanel, SystemUIController, or controllers")
		_finish()
		return

	_investigate_label = _object_info.get_node_or_null(SIGNAL_INVESTIGATE_LABEL_PATH) as Label
	_sensor_pulse_label = _object_info.get_node_or_null(
		"Margin/Root/SensorPulseProgressLabel"
	) as Label
	if _investigate_label == null or _sensor_pulse_label == null:
		_fail("Runtime: progress label nodes missing on ObjectInfoPanel")
		_finish()
		return

	var automation: AutomationController = _find_automation_controller(_system_scene)
	if automation != null:
		automation.ensure_starting_units(BASE_ID)

	_test_b_investigate_label()
	_test_c_sensor_pulse_label()
	_test_d_reset_labels()
	_test_e_no_gameplay_change()
	_regression_checks()
	_finish()


func _test_b_investigate_label() -> void:
	if not _spc.try_start_investigate_signal(SIGNAL_OBJECT_ID, BASE_ID):
		_fail("Test B: try_start_investigate_signal failed")
		return
	if not _spc.is_investigate_active(SIGNAL_OBJECT_ID):
		_fail("Test B: investigate not active after start")
		return

	var marker: SignalMarker = _find_signal_marker(SIGNAL_OBJECT_ID)
	if marker == null:
		_fail("Test B: SignalMarker for %s not found" % SIGNAL_OBJECT_ID)
		return

	_selection.select_world_node(marker)
	_system_ui.update_object_info()

	var in_progress_cache: bool = bool(_object_info._live_action_cache.get("investigate_in_progress", false))
	_results["test_b_in_progress_cache"] = in_progress_cache
	_results["test_b_investigate_visible"] = _investigate_label.visible
	_results["test_b_investigate_text"] = _investigate_label.text
	_results["test_b_sensor_pulse_visible"] = _sensor_pulse_label.visible

	if not in_progress_cache:
		_fail("Test B: investigate_in_progress not set in ObjectInfo cache")
	if not _investigate_label.visible:
		_fail("Test B: InvestigateProgressLabel should be visible during investigate")
	if _investigate_label.text.is_empty():
		_fail("Test B: InvestigateProgressLabel text empty")
	if _sensor_pulse_label.visible:
		_fail("Test B: SensorPulseProgressLabel must stay hidden during investigate")
	if _investigate_label.text.to_lower().contains("scanning for signals"):
		_fail("Test B: investigate label must not show sensor pulse wording")


func _test_c_sensor_pulse_label() -> void:
	_restore_survey_data_for_pulse()
	GameSession.set_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID, GameSession.DISCOVERY_HIDDEN)
	_select_home_base()
	_system_ui.update_object_info()

	if not _pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_fail("Test C: try_start_sensor_pulse failed")
		return

	_system_ui.update_object_info()

	_results["test_c_sensor_pulse_visible"] = _sensor_pulse_label.visible
	_results["test_c_sensor_pulse_text"] = _sensor_pulse_label.text
	_results["test_c_investigate_visible"] = _investigate_label.visible
	_results["test_c_investigate_text"] = _investigate_label.text

	if not _sensor_pulse_label.visible:
		_fail("Test C: SensorPulseProgressLabel should be visible during pulse")
	if _sensor_pulse_label.text.is_empty():
		_fail("Test C: SensorPulseProgressLabel text empty")
	if not _sensor_pulse_label.text.to_lower().contains("scanning for signals"):
		_fail("Test C: sensor pulse label should use pulse progress wording")
	if _investigate_label.visible and _investigate_label.text.to_lower().contains("scanning for signals"):
		_fail("Test C: InvestigateProgressLabel must not display sensor pulse progress")


func _test_d_reset_labels() -> void:
	_object_info.show_empty()
	_results["test_d_investigate_visible"] = _investigate_label.visible
	_results["test_d_sensor_pulse_visible"] = _sensor_pulse_label.visible
	if _investigate_label.visible:
		_fail("Test D: InvestigateProgressLabel should be hidden after show_empty()")
	if _sensor_pulse_label.visible:
		_fail("Test D: SensorPulseProgressLabel should be hidden after show_empty()")


func _test_e_no_gameplay_change() -> void:
	var balance := GameSession.get_game_balance()
	var expected_cost: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		expected_cost = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))

	_restore_survey_data_for_pulse()
	GameSession.set_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID, GameSession.DISCOVERY_HIDDEN)
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var hidden_before: bool = (
		GameSession.get_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID)
		== GameSession.DISCOVERY_HIDDEN
	)

	if not _pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_notes.append("Test E: second pulse start skipped (active pulse or gate)")
	else:
		var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
		_results["test_e_sd_before"] = sd_before
		_results["test_e_sd_after"] = sd_after
		_results["test_e_expected_cost"] = expected_cost
		if sd_after >= sd_before:
			_fail("Test E: SurveyData should decrease when pulse starts")
		if sd_before - sd_after != expected_cost:
			_fail("Test E: pulse cost mismatch (expected %d, delta %d)" % [
				expected_cost, sd_before - sd_after,
			])

	if hidden_before:
		_results["test_e_hidden_still_hidden"] = (
			GameSession.get_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID)
			== GameSession.DISCOVERY_HIDDEN
		)


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _find_signal_marker(object_id: String) -> SignalMarker:
	return _search_signal_marker(_system_scene, object_id.strip_edges())


func _search_signal_marker(node: Node, object_id: String) -> SignalMarker:
	if node is SignalMarker and (node as SignalMarker).object_id.strip_edges() == object_id:
		return node as SignalMarker
	for child: Node in node.get_children():
		var found: SignalMarker = _search_signal_marker(child, object_id)
		if found != null:
			return found
	return null


func _select_home_base() -> void:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return
	var earth: Node = spawner.get_spawned_object(BASE_ID)
	if earth != null:
		_selection.select_world_node(earth as Node2D)


func _restore_survey_data_for_pulse() -> void:
	var balance := GameSession.get_game_balance()
	var needed: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		needed = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))
	var current: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if current < needed * 2:
		GameSession.add_base_resource(BASE_ID, "SurveyData", needed * 2 - current)


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


func _find_pulse_controller(root: Node) -> BaseSensorPulseController:
	if root is BaseSensorPulseController:
		return root as BaseSensorPulseController
	for child: Node in root.get_children():
		var found: BaseSensorPulseController = _find_pulse_controller(child)
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
	push_error("[SensorPulseProgressLabelCleanupSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== SensorPulse Progress Label Cleanup Smoke ===")
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
