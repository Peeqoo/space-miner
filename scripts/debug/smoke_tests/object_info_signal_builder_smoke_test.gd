## ObjectInfoDictKeys + SignalObjectInfoBuilder smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_signal_builder_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SIGNAL_OBJECT_ID: String = "venus"
const BASE_ID: String = BaseStore.BASE_EARTH

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_key_constants()
	_test_b_builder_output_shape()
	_load_system_scene_for_test_c()


func _test_a_key_constants() -> void:
	_results["test_a_signal_key_count"] = ObjectInfoDictKeys.SIGNAL_KEYS.size()
	_results["test_a_has_duplicates"] = ObjectInfoDictKeys.signal_keys_have_duplicates()

	if ObjectInfoDictKeys.SIGNAL_KEYS.is_empty():
		_fail("Test A: SIGNAL_KEYS must not be empty")
	if ObjectInfoDictKeys.signal_keys_have_duplicates():
		_fail("Test A: SIGNAL_KEYS contains duplicate StringNames")

	for key: StringName in [
		ObjectInfoDictKeys.ID,
		ObjectInfoDictKeys.IS_DISCOVERY_SIGNAL,
		ObjectInfoDictKeys.CAN_INVESTIGATE_SIGNAL,
		ObjectInfoDictKeys.INVESTIGATE_PROGRESS_TEXT,
	]:
		if String(key).is_empty():
			_fail("Test A: required ObjectInfoDictKeys entry is empty")


func _test_b_builder_output_shape() -> void:
	var marker := _make_test_signal_marker()
	var info: Dictionary = SignalObjectInfoBuilder.build(marker, null, BASE_ID)
	_results["test_b_key_count"] = info.size()

	for required_key: StringName in ObjectInfoDictKeys.SIGNAL_BUILDER_REQUIRED_KEYS:
		if not info.has(required_key):
			_fail("Test B: missing required key %s" % String(required_key))

	if info.get(ObjectInfoDictKeys.IS_DISCOVERY_SIGNAL, false) != true:
		_fail("Test B: is_discovery_signal must be true")

	if info.get(ObjectInfoDictKeys.CAN_SCAN_WITH_DRONE, true) != false:
		_fail("Test B: can_scan_with_drone must be false for SIGNAL")
	if info.get(ObjectInfoDictKeys.CAN_MINE_WITH_SHIP, true) != false:
		_fail("Test B: can_mine_with_ship must be false for SIGNAL")
	if info.get(ObjectInfoDictKeys.CAN_RECALL_DRONE, true) != false:
		_fail("Test B: can_recall_drone must be false for SIGNAL")
	if info.get(ObjectInfoDictKeys.CAN_RECALL_MINING_SHIP, true) != false:
		_fail("Test B: can_recall_mining_ship must be false for SIGNAL")

	if info.has(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE):
		if info.get(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE, true) != false:
			_fail("Test B: show_scan_with_drone must be false when present")
	if info.has(ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP):
		if info.get(ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP, true) != false:
			_fail("Test B: show_mine_with_ship must be false when present")

	if info.has(ObjectInfoDictKeys.DISCOVERY_COMPLETE_MESSAGE):
		_fail("Test B: discovery_complete_message must not be set by builder")

	marker.queue_free()


func _load_system_scene_for_test_c() -> void:
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Test C: could not load system scene")
		_finish()
		return
	var system_scene: Node = packed.instantiate()
	add_child(system_scene)
	_wait_frames(100, _test_c_controller_delegation.bind(system_scene))


func _test_c_controller_delegation(system_scene: Node) -> void:
	var system_ui: SystemUIController = (
		system_scene.get_node_or_null("SystemUIController") as SystemUIController
	)
	if system_ui == null:
		_fail("Test C: SystemUIController missing")
		_regression_checks()
		_finish()
		return

	var marker := _find_signal_marker(system_scene, SIGNAL_OBJECT_ID)
	if marker == null:
		marker = _make_test_signal_marker()
		_notes.append("Test C: venus SignalMarker not in scene — used synthetic fixture")

	var from_builder: Dictionary = SignalObjectInfoBuilder.build(
		marker,
		system_ui.survey_probe_mission_controller,
		BaseStore.BASE_EARTH,
	)
	var from_controller: Dictionary = system_ui._build_signal_marker_info(marker)
	_results["test_c_builder_keys"] = from_builder.size()
	_results["test_c_controller_keys"] = from_controller.size()

	if not _signal_info_dicts_equal(from_builder, from_controller):
		_fail("Test C: builder output must match SystemUIController._build_signal_marker_info")

	_regression_checks()
	_finish()


func _make_test_signal_marker() -> SignalMarker:
	var marker := SignalMarker.new()
	marker.object_id = SIGNAL_OBJECT_ID
	marker.signal_type_id = "unknown"
	marker.signal_type_display_name = "Unknown Signal"
	marker.signal_type_short_label = "SIG"
	marker.signal_description = "Test fixture"
	return marker


func _find_signal_marker(root: Node, object_id: String) -> SignalMarker:
	for node: Node in root.find_children("*", "SignalMarker", true, false):
		var marker := node as SignalMarker
		if marker != null and marker.object_id.strip_edges() == object_id:
			return marker
	return null


func _signal_info_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		_results["test_c_size_mismatch"] = {"a": a.size(), "b": b.size()}
		return false
	for key: Variant in a.keys():
		if not b.has(key):
			_results["test_c_missing_in_b"] = str(key)
			return false
		if a[key] != b[key]:
			_results["test_c_value_mismatch_key"] = str(key)
			_results["test_c_value_a"] = a[key]
			_results["test_c_value_b"] = b[key]
			return false
	return true


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
	push_error("[ObjectInfoSignalBuilderSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ObjectInfo Signal Builder Smoke ===")
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
