## ObjectInfo mining_bonus display contract smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_mining_bonus_display_smoke_runner.tscn
extends Node

const PANEL_SCENE_PATH: String = "res://scenes/ui/system/object_info_panel.tscn"
const OBJECT_ID: String = "mars"
const MINING_BONUS_LABEL_PATH: String = "Margin/Root/OrbitStatusSection/MiningBonusLabel"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _panel: ObjectInfoPanel = null
var _mining_bonus_label: Label = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	if not _load_panel():
		_finish()
		return
	_test_a_display_uses_mining_bonus_not_support_count()
	_test_b_normal_bonus_fractions()
	_regression_checks()
	_finish()


func _load_panel() -> bool:
	var packed: PackedScene = load(PANEL_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load object_info_panel.tscn")
		return false
	_panel = packed.instantiate() as ObjectInfoPanel
	if _panel == null:
		_fail("ObjectInfoPanel instantiate failed")
		return false
	_panel.visible = true
	add_child(_panel)
	_mining_bonus_label = _panel.get_node_or_null(MINING_BONUS_LABEL_PATH) as Label
	if _mining_bonus_label == null:
		_fail("MiningBonusLabel missing")
		return false
	return true


func _test_a_display_uses_mining_bonus_not_support_count() -> void:
	_show_info_with_bonus(0.04, 999, 1)
	var text: String = _mining_bonus_label.text
	_results["test_a_label_text"] = text
	_results["test_a_visible"] = _mining_bonus_label.visible

	if not _mining_bonus_label.visible:
		_fail("Test A: MiningBonusLabel should be visible with orbit activity")
	if not text.contains("+4%"):
		_fail("Test A: expected +4%% from mining_bonus=0.04, got '%s'" % text)
	if text.contains("1998") or text.contains("999"):
		_fail("Test A: label must not derive percent from scan_drone_supporting_count")


func _test_b_normal_bonus_fractions() -> void:
	_show_info_with_bonus(0.02, 1, 0)
	var text_2: String = _mining_bonus_label.text
	_results["test_b_two_percent"] = text_2
	if not text_2.contains("+2%"):
		_fail("Test B: mining_bonus=0.02 should display +2%%, got '%s'" % text_2)

	_show_info_with_bonus(0.06, 2, 0)
	var text_6: String = _mining_bonus_label.text
	_results["test_b_six_percent"] = text_6
	if not text_6.contains("+6%"):
		_fail("Test B: mining_bonus=0.06 should display +6%%, got '%s'" % text_6)

	_show_info_with_bonus(0.0, 0, 1)
	_results["test_b_zero_visible"] = _mining_bonus_label.visible
	_results["test_b_zero_text"] = _mining_bonus_label.text
	if not _mining_bonus_label.visible:
		_fail("Test B: bonus row stays visible when mining activity present (unchanged)")
	if not _mining_bonus_label.text.contains("+0%"):
		_fail("Test B: mining_bonus=0.0 should display +0%% when row visible")


func _show_info_with_bonus(
	bonus_fraction: float,
	supporting_count: int,
	mining_ship_mining_count: int,
) -> void:
	var info: Dictionary = {
		"id": OBJECT_ID,
		"display_name": "Mars",
		"body_type": "planet",
		"scan_state": GameSession.SCAN_BASIC,
		"is_discovery_signal": false,
		"resources_visible": [],
		"scan_drone_supporting_count": supporting_count,
		"active_scan_drone_count": supporting_count,
		"mining_ship_mining_count": mining_ship_mining_count,
		"assigned_mining_ship_count": mining_ship_mining_count,
		"show_mining_ship_status": mining_ship_mining_count > 0,
		"mining_bonus": bonus_fraction,
		"mining_yield_upgrade_base_id": BaseStore.BASE_EARTH,
		"distance_text": "100 u",
		"preview_texture": null,
	}
	_panel.show_body_info(info)


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


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[ObjectInfoMiningBonusDisplaySmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ObjectInfo Mining Bonus Display Smoke ===")
	print("Status: %s" % status)
	print("Results: %s" % str(_results))
	for note: String in _notes:
		print("NOTE: %s" % note)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
