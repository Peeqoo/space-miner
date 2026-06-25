## ObjectInfo SIGNAL vs KNOWN layout smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_signal_layout_smoke_runner.tscn
extends Node

const PANEL_SCENE_PATH: String = "res://scenes/ui/system/object_info_panel.tscn"
const SIGNAL_OBJECT_ID: String = "venus"
const KNOWN_OBJECT_ID: String = "mars"

const MIN_KNOWN_TALLER_THAN_SIGNAL_PX: float = 12.0
const HEIGHT_COMPARE_TOLERANCE_PX: float = 4.0
const SIGNAL_SUB_PANEL_PATH: String = "Margin/Root/SignalInfoSubPanel"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _panel: ObjectInfoPanel = null
var _divider_b: HSeparator = null
var _resource_title: Label = null
var _resource_panel: PanelContainer = null
var _divider_d: HSeparator = null
var _orbit_section: VBoxContainer = null
var _lore_panel: PanelContainer = null
var _lore_scroll: ScrollContainer = null
var _scan_button: Button = null
var _mine_button: Button = null
var _investigate_button: Button = null
var _investigate_label: Label = null
var _sensor_pulse_label: Label = null

var _known_layout_height: float = -1.0
var _signal_layout_height: float = -1.0


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
	_wait_frames(3, _run_tests)


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
	_panel.custom_minimum_size = Vector2(200, 0)
	add_child(_panel)
	if not _bind_panel_nodes():
		return false
	return true


func _bind_panel_nodes() -> bool:
	_divider_b = _panel.get_node_or_null("Margin/Root/DividerB") as HSeparator
	_resource_title = _panel.get_node_or_null("Margin/Root/ResourceTitleLabel") as Label
	_resource_panel = _panel.get_node_or_null("Margin/Root/ResourcePanel") as PanelContainer
	_divider_d = _panel.get_node_or_null("Margin/Root/DividerD") as HSeparator
	_orbit_section = _panel.get_node_or_null("Margin/Root/OrbitStatusSection") as VBoxContainer
	_lore_panel = _panel.get_node_or_null("Margin/Root/LorePanel") as PanelContainer
	_lore_scroll = _panel.get_node_or_null(
		"Margin/Root/LorePanel/LoreMargin/LoreScroll"
	) as ScrollContainer
	_scan_button = _panel.get_node_or_null(
		"Margin/Root/GridContainer/ScanWithDroneButton"
	) as Button
	_mine_button = _panel.get_node_or_null(
		"Margin/Root/GridContainer/SendMiningShipButton"
	) as Button
	_investigate_button = _panel.get_node_or_null(
		"%s/InvestigateButton" % SIGNAL_SUB_PANEL_PATH
	) as Button
	_investigate_label = _panel.get_node_or_null(
		"%s/InvestigateProgressLabel" % SIGNAL_SUB_PANEL_PATH
	) as Label
	_sensor_pulse_label = _panel.get_node_or_null(
		"Margin/Root/SensorPulseProgressLabel"
	) as Label

	var missing: PackedStringArray = []
	if _divider_b == null:
		missing.append("DividerB")
	if _resource_title == null:
		missing.append("ResourceTitleLabel")
	if _resource_panel == null:
		missing.append("ResourcePanel")
	if _orbit_section == null:
		missing.append("OrbitStatusSection")
	if _scan_button == null or _mine_button == null:
		missing.append("Scan/Mine buttons")
	if _investigate_button == null or _investigate_label == null:
		missing.append("Investigate controls")
	if _sensor_pulse_label == null:
		missing.append("SensorPulseProgressLabel")

	_results["nodes_bound"] = missing.is_empty()
	if not missing.is_empty():
		_fail("Missing panel nodes: %s" % str(missing))
		return false
	if _investigate_label == _sensor_pulse_label:
		_fail("InvestigateProgressLabel and SensorPulseProgressLabel must be distinct")
		return false
	return true


func _run_tests() -> void:
	_test_a_signal_compact_controls()


func _test_a_signal_compact_controls() -> void:
	_show_signal_info(false)
	_wait_frames(2, _assert_test_a)


func _assert_test_a() -> void:
	_results["test_a_is_discovery_signal"] = bool(
		_panel._live_action_cache.get("is_discovery_signal", false)
	)

	if not bool(_panel._live_action_cache.get("is_discovery_signal", false)):
		_fail("Test A: is_discovery_signal expected true")

	if _divider_b.visible:
		_fail("Test A: DividerB should be hidden for SIGNAL")
	if _resource_title.visible:
		_fail("Test A: ResourceTitleLabel should be hidden for SIGNAL")
	if _resource_panel.visible:
		_fail("Test A: ResourcePanel should be hidden for SIGNAL")
	if _divider_d.visible:
		_fail("Test A: DividerD should be hidden for SIGNAL")
	if _orbit_section.visible:
		_fail("Test A: OrbitStatusSection should be hidden for SIGNAL")
	if _scan_button.visible:
		_fail("Test A: ScanWithDroneButton should be hidden for SIGNAL")
	if _mine_button.visible:
		_fail("Test A: SendMiningShipButton should be hidden for SIGNAL")
	if not _investigate_button.visible:
		_fail("Test A: InvestigateButton should be visible when gate allows")
	if _sensor_pulse_label.visible:
		_fail("Test A: SensorPulseProgressLabel should be hidden for SIGNAL")

	_signal_layout_height = _measure_panel_content_height()
	_results["test_a_signal_height"] = _signal_layout_height

	_test_b_signal_investigate_progress()


func _test_b_signal_investigate_progress() -> void:
	_show_signal_info(true)
	_wait_frames(2, _assert_test_b)


func _assert_test_b() -> void:
	_results["test_b_investigate_visible"] = _investigate_label.visible
	_results["test_b_investigate_text"] = _investigate_label.text
	_results["test_b_sensor_pulse_visible"] = _sensor_pulse_label.visible
	_results["test_b_investigate_button_visible"] = _investigate_button.visible

	if not _investigate_label.visible:
		_fail("Test B: InvestigateProgressLabel should be visible during investigate")
	if _investigate_label.text.is_empty():
		_fail("Test B: InvestigateProgressLabel text empty")
	if _sensor_pulse_label.visible:
		_fail("Test B: SensorPulseProgressLabel must stay hidden during investigate")
	if _investigate_button.visible:
		_fail("Test B: InvestigateButton should be hidden during in-progress investigate")
	if _investigate_label.text.to_lower().contains("scanning for signals"):
		_fail("Test B: investigate label must not use sensor pulse wording")

	_test_c_known_restore_after_signal()


func _test_c_known_restore_after_signal() -> void:
	_show_known_info()
	_wait_frames(3, _assert_test_c)


func _assert_test_c() -> void:
	var is_signal: bool = bool(_panel._live_action_cache.get("is_discovery_signal", false))
	_results["test_c_is_discovery_signal"] = is_signal
	if is_signal:
		_fail("Test C: is_discovery_signal should be false after KNOWN info")

	if not _divider_b.visible:
		_fail("Test C: DividerB should be visible for KNOWN")
	if not _resource_title.visible:
		_fail("Test C: ResourceTitleLabel should be visible for KNOWN")
	if not _resource_panel.visible:
		_fail("Test C: ResourcePanel should be visible for KNOWN")
	if not _divider_d.visible:
		_fail("Test C: DividerD should be visible for KNOWN")
	if not _orbit_section.visible:
		_fail("Test C: OrbitStatusSection should be visible for KNOWN")
	if not _scan_button.visible:
		_fail("Test C: ScanWithDroneButton should be visible for KNOWN (gate allows)")
	if not _mine_button.visible:
		_fail("Test C: SendMiningShipButton should be visible for KNOWN (gate allows)")

	if _investigate_button.visible:
		_fail("Test C: InvestigateButton should be hidden for KNOWN")
	if _investigate_label.visible:
		_fail("Test C: InvestigateProgressLabel should be hidden for KNOWN")

	if _lore_scroll != null:
		var scroll_disabled: bool = (
			_lore_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		)
		_results["test_c_lore_scroll_disabled"] = scroll_disabled
		if scroll_disabled:
			_fail("Test C: LoreScroll should not remain disabled after KNOWN restore")

	if _lore_panel != null:
		var lore_h: float = _lore_panel.custom_minimum_size.y
		_results["test_c_lore_panel_min_h"] = lore_h
		if lore_h > 0.0 and lore_h < 40.0:
			_notes.append(
				"Test C: LorePanel min height %.1f — may be short lore text, not stuck signal shrink"
				% lore_h
			)

	_known_layout_height = _measure_panel_content_height()
	_results["test_c_known_height"] = _known_layout_height

	_test_d_panel_height_sanity()


func _test_d_panel_height_sanity() -> void:
	_results["test_d_signal_height"] = _signal_layout_height
	_results["test_d_known_height"] = _known_layout_height

	if _signal_layout_height < 0.0 or _known_layout_height < 0.0:
		_notes.append("Test D: height compare skipped — missing signal or known measurement")
		_finish_regression_and_exit()
		return

	var delta: float = _known_layout_height - _signal_layout_height
	_results["test_d_height_delta"] = delta

	if delta + HEIGHT_COMPARE_TOLERANCE_PX < MIN_KNOWN_TALLER_THAN_SIGNAL_PX:
		_fail(
			"Test D: KNOWN height should exceed SIGNAL by >= %.1f px (delta=%.1f)"
			% [MIN_KNOWN_TALLER_THAN_SIGNAL_PX, delta]
		)

	_finish_regression_and_exit()


func _finish_regression_and_exit() -> void:
	_test_e_regression()
	_finish()


func _test_e_regression() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _show_signal_info(in_progress: bool) -> void:
	var info: Dictionary = {
		"id": SIGNAL_OBJECT_ID,
		"object_id": SIGNAL_OBJECT_ID,
		"display_name": "Unknown",
		"body_type": "Signal",
		"scan_state": GameSession.SCAN_UNKNOWN,
		"is_discovery_signal": true,
		"is_signal_marker": true,
		"can_investigate_signal": not in_progress,
		"investigate_in_progress": in_progress,
		"is_investigate_active": in_progress,
		"investigate_progress": 0.35 if in_progress else 0.0,
		"investigate_progress_text": DiscoverySignalUiTextDefinition.format_investigate_progress(
			35 if in_progress else 0
		),
		"investigate_blocked_reason": "",
		"discovery_complete_message": "",
		"lore_text": DiscoverySignalUiTextDefinition.get_unknown_signal_lore(),
		"resources_visible": [],
		"resources_hidden_count": 0,
		"can_scan_with_drone": false,
		"show_scan_with_drone": false,
		"can_mine_with_ship": false,
		"show_mine_with_ship": false,
		"can_recall_drone": false,
		"can_recall_mining_ship": false,
		"is_home_base": false,
		"mining_exhausted": false,
		"distance_text": "120 u",
		"preview_texture": null,
	}
	_panel.show_body_info(info)
	if in_progress:
		_panel.apply_investigate_progress(0.35)


func _show_known_info() -> void:
	var info: Dictionary = {
		"id": KNOWN_OBJECT_ID,
		"display_name": "Mars",
		"body_type": "planet",
		"scan_state": GameSession.SCAN_BASIC,
		"is_discovery_signal": false,
		"lore_text": "Known body lore for layout restore smoke.",
		"resources_visible": [
			{
				"resource_id": "Iron",
				"label": "Iron",
				"total_amount": 100,
				"remaining_amount": 80,
			},
		],
		"can_scan_with_drone": true,
		"show_scan_with_drone": true,
		"scan_button_text": "Scan",
		"can_mine_with_ship": true,
		"show_mine_with_ship": true,
		"mining_button_text": "Mine",
		"can_recall_drone": false,
		"can_recall_mining_ship": false,
		"is_home_base": false,
		"mining_exhausted": false,
		"assigned_scan_drone_count": 1,
		"show_scan_drone_status": true,
		"assigned_mining_ship_count": 0,
		"show_mining_ship_status": false,
		"active_scan_drone_count": 0,
		"scan_drone_supporting_count": 0,
		"mining_ship_mining_count": 0,
		"mining_bonus": 0.0,
		"distance_text": "184 u",
		"preview_texture": null,
	}
	_panel.show_body_info(info)


func _measure_panel_content_height() -> float:
	_panel.update_minimum_size()
	return maxf(
		float(_panel.get_combined_minimum_size().y),
		float(_panel.custom_minimum_size.y),
	)


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
	push_error("[ObjectInfoSignalLayoutSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ObjectInfo Signal Layout Smoke ===")
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
