## TopHUD storage hover resource display smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/top_hud_hover_storage_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const BASE_ID: String = BaseStore.BASE_EARTH

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_load_system_scene()


func _load_system_scene() -> void:
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_tests)


func _setup_tests() -> void:
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	if _system_ui == null:
		_fail("Missing SystemUIController")
		_finish()
		return

	_test_a_survey_data_display_name()
	_test_b_catalog_names_and_compact_amounts()
	_test_c_empty_storage_text()
	_test_d_title_and_hint()
	_regression_checks()
	_finish()


func _test_a_survey_data_display_name() -> void:
	_clear_base_resources(BASE_ID)
	GameSession.add_base_resource(BASE_ID, "SurveyData", 42)

	var content: Dictionary = _build_storage_hover()
	var details: Array = content.get("details", [])
	_results["test_a_details"] = details

	var survey_line: String = _find_detail_line(details, "Survey Data")
	_results["test_a_survey_line"] = survey_line

	if survey_line.is_empty():
		_fail("Test A: expected detail line containing 'Survey Data'")
	if _details_contain_substring(details, "Surveydata"):
		_fail("Test A: detail must not contain 'Surveydata'")
	if not survey_line.ends_with(NumberFormat.format_compact(42)):
		_fail("Test A: Survey Data line should end with compact amount 42")


func _test_b_catalog_names_and_compact_amounts() -> void:
	_clear_base_resources(BASE_ID)
	GameSession.add_base_resource(BASE_ID, "Iron", 100)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Ice", 50)

	var content: Dictionary = _build_storage_hover()
	var details: Array = content.get("details", [])
	_results["test_b_details"] = details

	var iron_line := _find_detail_line(details, "Iron:")
	if iron_line.is_empty():
		_fail("Test B: expected Iron catalog line")
	elif not iron_line.ends_with(NumberFormat.format_compact(100)):
		_fail("Test B: Iron amount should use NumberFormat compact")

	var silicon_line := _find_detail_line(details, "Silicon:")
	if silicon_line.is_empty():
		_fail("Test B: expected Silicon catalog line")
	elif not silicon_line.ends_with(NumberFormat.format_compact(500)):
		_fail("Test B: Silicon amount should use NumberFormat compact")

	var ice_line := _find_detail_line(details, "Ice:")
	if ice_line.is_empty():
		_fail("Test B: expected Ice catalog line")
	elif not ice_line.ends_with(NumberFormat.format_compact(50)):
		_fail("Test B: Ice amount should use NumberFormat compact")

	var iron_index: int = _detail_line_index(details, "Iron:")
	var silicon_index: int = _detail_line_index(details, "Silicon:")
	var ice_index: int = _detail_line_index(details, "Ice:")
	_results["test_b_sort_indices"] = {
		"iron": iron_index,
		"silicon": silicon_index,
		"ice": ice_index,
	}
	if iron_index < 0 or silicon_index < 0 or ice_index < 0:
		_fail("Test B: missing sorted resource lines")
	elif not (iron_index < silicon_index and silicon_index < ice_index):
		_fail("Test B: resource lines should follow catalog sort order (Iron before Silicon before Ice)")

	_clear_base_resources(BASE_ID)
	GameSession.add_base_resource(BASE_ID, "Silicon", 1000)
	var compact_content: Dictionary = _build_storage_hover()
	var compact_details: Array = compact_content.get("details", [])
	var compact_silicon_line := _find_detail_line(compact_details, "Silicon:")
	_results["test_b_compact_k_line"] = compact_silicon_line
	if compact_silicon_line != "Silicon: %s" % NumberFormat.format_compact(1000):
		_fail("Test B: compact K-format line mismatch for Silicon 1000")


func _test_c_empty_storage_text() -> void:
	_clear_base_resources(BASE_ID)

	var content: Dictionary = _build_storage_hover()
	var details: Array = content.get("details", [])
	_results["test_c_details"] = details

	if not details.has("No resources stored."):
		_fail('Test C: empty storage should show "No resources stored."')


func _test_d_title_and_hint() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 1)

	var content: Dictionary = _build_storage_hover()
	_results["test_d_title"] = str(content.get("title", ""))
	_results["test_d_hint"] = str(content.get("hint", ""))

	if str(content.get("title", "")) != "Storage":
		_fail('Test D: hover title should remain "Storage"')
	if str(content.get("hint", "")) != "Storage capacity.":
		_fail('Test D: hover hint should remain "Storage capacity."')


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _build_storage_hover() -> Dictionary:
	return _system_ui._build_hover_details("storage")


func _clear_base_resources(base_id: String) -> void:
	var resources: Dictionary = GameSession.get_base_resources(base_id)
	for res_key: Variant in resources.keys():
		var rid := str(res_key).strip_edges()
		var amt := int(resources.get(res_key, 0))
		if amt > 0 and not rid.is_empty():
			GameSession.remove_base_resource(base_id, rid, amt)


func _find_detail_line(details: Array, prefix: String) -> String:
	for line_variant: Variant in details:
		var line := str(line_variant)
		if line.begins_with(prefix):
			return line
	return ""


func _detail_line_index(details: Array, prefix: String) -> int:
	for i: int in range(details.size()):
		if str(details[i]).begins_with(prefix):
			return i
	return -1


func _details_contain_substring(details: Array, needle: String) -> bool:
	for line_variant: Variant in details:
		if str(line_variant).contains(needle):
			return true
	return false


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
	push_error("[TopHudHoverStorageSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== TopHUD Hover Storage Smoke ===")
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
