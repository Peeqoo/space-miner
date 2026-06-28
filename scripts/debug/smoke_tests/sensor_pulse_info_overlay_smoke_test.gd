## SensorPulseInfoOverlay extraction smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/sensor_pulse_info_overlay_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const BASE_ID: String = BaseStore.BASE_EARTH
const HIDDEN_CANDIDATE_ID: String = "jupiter"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _pulse_ctrl: BaseSensorPulseController = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_overlay_key_shape()
	_load_system_scene()


func _test_a_overlay_key_shape() -> void:
	var info: Dictionary = {}
	SensorPulseInfoOverlay.apply(info, null, BASE_ID, false)

	for key: StringName in SensorPulseInfoOverlay.OVERLAY_KEYS:
		if String(key).is_empty():
			_fail("Test A: ObjectInfoDictKeys sensor pulse key is empty")
		if not info.has(key):
			_fail("Test A: missing overlay key %s" % String(key))

	_results["test_a_keys_present"] = true
	_results["test_a_show_pulse"] = info.get(ObjectInfoDictKeys.SHOW_SENSOR_PULSE, true)
	if info.get(ObjectInfoDictKeys.SHOW_SENSOR_PULSE, true) != false:
		_fail("Test A: non-home overlay must leave show_sensor_pulse false")


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
	_pulse_ctrl = _find_pulse_controller(_system_scene)
	if _system_ui == null or _pulse_ctrl == null:
		_fail("Missing SystemUIController or BaseSensorPulseController")
		_regression_checks()
		_finish()
		return

	_test_b_controller_delegation_equality()
	_test_d_non_home_base()
	_test_c_active_pulse()
	_regression_checks()
	_finish()


func _test_b_controller_delegation_equality() -> void:
	_select_home_base()

	var info_overlay: Dictionary = {"is_home_base": true}
	var info_controller: Dictionary = {"is_home_base": true}
	var base_id: String = BaseStore.BASE_EARTH

	SensorPulseInfoOverlay.apply(info_overlay, _pulse_ctrl, base_id, true)
	_system_ui._apply_sensor_pulse_info_to_dict(info_controller)

	_results["test_b_overlay"] = _snapshot_sensor_pulse_fields(info_overlay)
	_results["test_b_controller"] = _snapshot_sensor_pulse_fields(info_controller)

	if not _sensor_pulse_dicts_equal(info_overlay, info_controller):
		_fail("Test B: overlay output must match SystemUIController._apply_sensor_pulse_info_to_dict")


func _test_c_active_pulse() -> void:
	_restore_survey_data_for_pulse()
	GameSession.set_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID, GameSession.DISCOVERY_HIDDEN)
	_select_home_base()

	if not _pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_notes.append("Test C: try_start_sensor_pulse skipped — gate blocked")
		return

	var info: Dictionary = {"is_home_base": true}
	SensorPulseInfoOverlay.apply(info, _pulse_ctrl, BASE_ID, true)

	_results["test_c_in_progress"] = info.get(ObjectInfoDictKeys.SENSOR_PULSE_IN_PROGRESS, false)
	_results["test_c_progress_text"] = str(
		info.get(ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT, "")
	)

	if info.get(ObjectInfoDictKeys.SENSOR_PULSE_IN_PROGRESS, false) != true:
		_fail("Test C: sensor_pulse_in_progress should be true during active pulse")
	if str(info.get(ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT, "")).is_empty():
		_fail("Test C: sensor_pulse_progress_text must not be empty during pulse")
	if not str(info.get(ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT, "")).to_lower().contains(
		"scanning for signals"
	):
		_fail("Test C: progress text should use sensor pulse wording")


func _test_d_non_home_base() -> void:
	var info: Dictionary = {"is_home_base": false}
	SensorPulseInfoOverlay.apply(info, _pulse_ctrl, BASE_ID, false)

	_results["test_d"] = _snapshot_sensor_pulse_fields(info)

	if info.get(ObjectInfoDictKeys.SHOW_SENSOR_PULSE, true) != false:
		_fail("Test D: show_sensor_pulse must be false for non-home")
	if info.get(ObjectInfoDictKeys.CAN_SENSOR_PULSE, true) != false:
		_fail("Test D: can_sensor_pulse must be false for non-home")
	if not str(info.get(ObjectInfoDictKeys.SENSOR_PULSE_BLOCKED_REASON, "")).is_empty():
		_fail("Test D: sensor_pulse_blocked_reason must be empty for non-home")
	if info.get(ObjectInfoDictKeys.SENSOR_PULSE_IN_PROGRESS, true) != false:
		_fail("Test D: sensor_pulse_in_progress must be false for non-home")
	if not str(info.get(ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT, "")).is_empty():
		_fail("Test D: sensor_pulse_progress_text must be empty for non-home")
	if not str(info.get(ObjectInfoDictKeys.SENSOR_PULSE_COST_TEXT, "")).is_empty():
		_fail("Test D: sensor_pulse_cost_text must be empty for non-home")


func _snapshot_sensor_pulse_fields(info: Dictionary) -> Dictionary:
	var snap: Dictionary = {}
	for key: StringName in SensorPulseInfoOverlay.OVERLAY_KEYS:
		snap[key] = info.get(key)
	return snap


func _sensor_pulse_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	for key: StringName in SensorPulseInfoOverlay.OVERLAY_KEYS:
		if a.get(key) != b.get(key):
			_results["test_b_mismatch_key"] = String(key)
			_results["test_b_mismatch_a"] = a.get(key)
			_results["test_b_mismatch_b"] = b.get(key)
			return false
	return true


func _select_home_base() -> void:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null or _selection == null:
		return
	var earth: Node = spawner.get_spawned_object(BASE_ID)
	if earth != null:
		_selection.select_world_node(earth as Node2D)


func _restore_survey_data_for_pulse() -> void:
	GameSession.add_base_resource(BASE_ID, "SurveyData", 50)


func _find_pulse_controller(root: Node) -> BaseSensorPulseController:
	if root is BaseSensorPulseController:
		return root as BaseSensorPulseController
	for child: Node in root.get_children():
		var found: BaseSensorPulseController = _find_pulse_controller(child)
		if found != null:
			return found
	return null


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


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
	push_error("[SensorPulseInfoOverlaySmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== SensorPulse Info Overlay Smoke ===")
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
