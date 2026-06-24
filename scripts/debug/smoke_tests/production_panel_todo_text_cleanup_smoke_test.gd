## ProductionPanel TODO text cleanup smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/production_panel_todo_text_cleanup_smoke_runner.tscn
extends Node

const PANEL_SCENE_PATH: String = "res://scenes/ui/system/production_panel.tscn"
const BASE_ID: String = BaseStore.BASE_EARTH

const FORBIDDEN_SUBSTRINGS: PackedStringArray = [
	"TODO",
	"timer TODO",
	"instant build",
]

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
	_load_panel_for_tests()


func _load_panel_for_tests() -> void:
	var packed: PackedScene = load(PANEL_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load production_panel.tscn")
		_finish()
		return

	var panel := packed.instantiate() as ProductionPanel
	if panel == null:
		_fail("ProductionPanel instantiate failed")
		_finish()
		return

	add_child(panel)
	_wait_frames(2, func() -> void:
		_run_panel_tests(panel)
	)


func _run_panel_tests(panel: ProductionPanel) -> void:
	_test_a_no_todo_in_panel(panel)
	panel.queue_free()
	_test_b_build_still_instant()
	_regression_checks()
	_finish()


func _test_a_no_todo_in_panel(panel: ProductionPanel) -> void:
	panel.visible = true
	panel.set_economy_body_id(BASE_ID)
	panel.refresh_from_game_session()

	var texts: PackedStringArray = _collect_visible_text(panel)
	_results["test_a_text_count"] = texts.size()
	_results["test_a_texts"] = texts

	for text: String in texts:
		var lower := text.to_lower()
		for forbidden: String in FORBIDDEN_SUBSTRINGS:
			if lower.contains(forbidden.to_lower()):
				_fail("Test A: forbidden substring '%s' in '%s'" % [forbidden, text])

	_simulate_hover_all_buttons(panel)
	panel.hover_info_section.visible = true
	var hover_texts: PackedStringArray = _collect_visible_text(panel.hover_info_section)
	_results["test_a_hover_text_count"] = hover_texts.size()

	for text: String in hover_texts:
		var lower := text.to_lower()
		for forbidden: String in FORBIDDEN_SUBSTRINGS:
			if lower.contains(forbidden.to_lower()):
				_fail("Test A: forbidden '%s' in hover '%s'" % [forbidden, text])

	_check_hover_cost_on_scan_drone(panel)


func _check_hover_cost_on_scan_drone(panel: ProductionPanel) -> void:
	panel._on_button_hover_entered(panel.build_scan_drone_button)
	var cost_text: String = panel.hover_cost_label.text
	_results["test_a_scan_drone_cost_hover"] = cost_text
	if not cost_text.contains("Iron"):
		_fail("Test A: scan drone hover cost should mention Iron, got '%s'" % cost_text)
	panel._on_button_hover_exited(panel.build_scan_drone_button)


func _test_b_build_still_instant() -> void:
	var iron_before: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	var drones_before: int = GameSession.get_base_drone_count(BASE_ID)
	var gate: Dictionary = GameSession.get_build_base_scan_drone_gate(BASE_ID)

	_results["test_b_gate_ok"] = bool(gate.get("ok", false))
	_results["test_b_iron_before"] = iron_before
	_results["test_b_drones_before"] = drones_before

	if not bool(gate.get("ok", false)):
		_notes.append("Test B: scan drone gate blocked — build instant check skipped")
		return

	if not GameSession.build_base_drone(BASE_ID):
		_fail("Test B: build_base_drone failed")
		return

	var iron_after: int = GameSession.get_base_resource_amount(BASE_ID, "Iron")
	var drones_after: int = GameSession.get_base_drone_count(BASE_ID)

	_results["test_b_iron_after"] = iron_after
	_results["test_b_drones_after"] = drones_after
	_results["test_b_iron_spent"] = iron_before - iron_after

	if drones_after != drones_before + 1:
		_fail("Test B: drone count did not increase immediately (instant build)")
	if iron_after >= iron_before:
		_fail("Test B: iron was not consumed on build")


func _simulate_hover_all_buttons(panel: ProductionPanel) -> void:
	var list: VBoxContainer = panel.get_node_or_null("Margin/Root/ProductionList") as VBoxContainer
	if list == null:
		return
	for child: Node in list.get_children():
		if child is Button:
			panel._on_button_hover_entered(child as Button)
	panel._on_button_hover_exited(null)


func _collect_visible_text(root: Control) -> PackedStringArray:
	var out: PackedStringArray = []
	if root == null:
		return out
	_gather_text_recursive(root, out)
	return out


func _gather_text_recursive(node: Node, out: PackedStringArray) -> void:
	if node is Control:
		var ctl: Control = node as Control
		if not ctl.visible:
			return
		if node is Button:
			var btn: Button = node as Button
			var t: String = btn.text.strip_edges()
			if not t.is_empty():
				out.append(t)
		elif node is Label:
			var lbl: Label = node as Label
			var t: String = lbl.text.strip_edges()
			if not t.is_empty():
				out.append(t)
	for child: Node in node.get_children():
		_gather_text_recursive(child, out)


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
	push_error("[ProductionPanelTodoTextCleanupSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ProductionPanel TODO Text Cleanup Smoke ===")
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
