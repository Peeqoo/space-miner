## Shows selected planet / object information.
## Emits action signals when the player wants to scan or mine the selected object.
class_name ObjectInfoPanel
extends PanelContainer

signal scan_requested(object_id: String)
signal mining_requested(object_id: String)
signal recall_drone_requested(object_id: String)
signal recall_mining_ship_requested(object_id: String)
signal colonization_requested(object_id: String)
signal investigate_requested(object_id: String)
signal sensor_pulse_requested()
signal close_requested()

const RESOURCE_INFO_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/resource_info_row.tscn")

@onready var root_vbox: VBoxContainer = $Margin/Root
@onready var header_label: Label = $Margin/Root/HBoxContainer/HeaderLabel
@onready var preview_texture: TextureRect = $Margin/Root/MainRow/PreviewPanel/PreviewCenter/PreviewTexture
@onready var name_label: Label = $Margin/Root/MainRow/MetaColumn/NameLabel
@onready var type_label: Label = $Margin/Root/MainRow/MetaColumn/TypeLabel
@onready var scan_status_label: Label = $Margin/Root/MainRow/MetaColumn/ScanStatusLabel
@onready var distance_label: Label = $Margin/Root/MainRow/MetaColumn/DistanceLabel
@onready var divider_b: HSeparator = $Margin/Root/DividerB
@onready var resource_title_label: Label = $Margin/Root/ResourceTitleLabel
@onready var resource_panel: PanelContainer = $Margin/Root/ResourcePanel
@onready var resource_list: VBoxContainer = $Margin/Root/ResourcePanel/ResourceMargin/ResourceScroll/ResourceList
@onready var lore_title_label: Label = $Margin/Root/LoreTitleLabel
@onready var lore_panel: PanelContainer = $Margin/Root/LorePanel
@onready var lore_scroll: ScrollContainer = $Margin/Root/LorePanel/LoreMargin/LoreScroll
@onready var lore_text_label: Label = $Margin/Root/LorePanel/LoreMargin/LoreScroll/LoreTextLabel
@onready var divider_d: HSeparator = $Margin/Root/DividerD
@onready var orbit_status_section: VBoxContainer = $Margin/Root/OrbitStatusSection

@onready var drone_orbit_label: Label = $Margin/Root/OrbitStatusSection/DroneOrbitLabel
@onready var scan_drone_count_label: Label = $Margin/Root/OrbitStatusSection/ScanDroneCountLabel
@onready var mining_ship_count_label: Label = $Margin/Root/OrbitStatusSection/MiningShipCountLabel
@onready var mine_orbit_label: Label = $Margin/Root/OrbitStatusSection/MineOrbitLabel
@onready var mining_bonus_label: Label = $Margin/Root/OrbitStatusSection/MiningBonusLabel

@onready var close_base_panel_button: Button = $Margin/Root/HBoxContainer/CloseBasePanelButton
@onready var scan_with_drone_button: Button = $Margin/Root/GridContainer/ScanWithDroneButton
@onready var send_mining_ship_button: Button = $Margin/Root/GridContainer/SendMiningShipButton
@onready var recall_drone_button: Button = $Margin/Root/GridContainer/RecallDroneButton
@onready var recall_mining_ship_button: Button = $Margin/Root/GridContainer/RecallMiningShipButton
@onready var colonization_button: Button = $Margin/Root/GridContainer/ColonizationButton
@onready var investigate_button: Button = $Margin/Root/GridContainer/InvestigateButton
@onready var sensor_pulse_button: Button = $Margin/Root/GridContainer/SensorPulseButton
@onready var economy_block_label: Label = $Margin/Root/EconomyBlockLabel
@onready var investigate_progress_label: Label = $Margin/Root/InvestigateProgressLabel
@onready var sensor_pulse_progress_label: Label = $Margin/Root/SensorPulseProgressLabel
@onready var investigate_progress_format_template: Label = (
	$Margin/Root/InvestigateProgressFormatTemplate
)

@onready var empty_value_template: Label = $Margin/Root/EmptyValueTemplate
@onready var scan_state_unknown_template: Label = $Margin/Root/ScanStateUnknownTemplate
@onready var scan_state_basic_template: Label = $Margin/Root/ScanStateBasicTemplate
@onready var scan_state_deep_template: Label = $Margin/Root/ScanStateDeepTemplate
@onready var scan_state_special_template: Label = $Margin/Root/ScanStateSpecialTemplate
@onready var empty_selection_lore_template: Label = $Margin/Root/EmptySelectionLoreTemplate
@onready var no_description_lore_template: Label = $Margin/Root/NoDescriptionLoreTemplate
@onready var mining_button_depleted_template: Label = $Margin/Root/MiningButtonDepletedTemplate
@onready var colonization_running_template: Label = $Margin/Root/ColonizationRunningTemplate
@onready var colonization_no_ship_block_template: Label = $Margin/Root/ColonizationNoShipBlockTemplate
@onready var automation_drone_supporting_template: Label = $Margin/Root/AutomationDroneSupportingTemplate
@onready var automation_drone_on_mission_template: Label = $Margin/Root/AutomationDroneOnMissionTemplate

var current_object_id: String = ""

## Shallow copy of `resources_visible` for live amount updates without a full info rebuild.
var _cached_visible_resources: Array = []

## Last known action flags from `_build_selected_object_info` (orbit buttons + mine eligibility).
var _live_action_cache: Dictionary = {
	"can_scan": false,
	"can_mine": false,
	"can_recall_drone": false,
	"can_recall_mining_ship": false,
	"is_home_base": false,
	"mining_exhausted": false,
	"colonization_button_visible": false,
	"colonization_pending": false,
	"colonization_can_start": false,
	"is_discovery_signal": false,
	"can_investigate_signal": false,
	"investigate_blocked_reason": "",
	"investigate_in_progress": false,
	"is_investigate_active": false,
	"investigate_progress": 0.0,
	"investigate_progress_text": "",
	"discovery_complete_message": "",
	"show_sensor_pulse": false,
	"can_sensor_pulse": false,
	"sensor_pulse_blocked_reason": "",
	"sensor_pulse_in_progress": false,
	"sensor_pulse_progress_text": "",
	"sensor_pulse_cost_text": "",
}

## Editor-owned prefixes captured from visible meta/orbit labels in _ready().
var _name_label_prefix: String = ""
var _type_label_prefix: String = ""
var _scan_status_label_prefix: String = ""
var _distance_label_prefix: String = ""
var _drone_orbit_label_prefix: String = ""
var _scan_drone_count_label_prefix: String = ""
var _mining_ship_count_label_prefix: String = ""
var _mine_orbit_label_prefix: String = ""
var _mining_bonus_label_prefix: String = ""

var _empty_value_text: String = "-"
var _scan_state_labels: Dictionary = {}
var _empty_selection_lore: String = ""
var _no_description_lore: String = ""
var _mining_button_text_default: String = ""
var _scan_button_text_default: String = ""
var _mining_button_text_depleted: String = ""
var _colonization_button_text_default: String = ""
var _colonization_button_text_running: String = ""
var _colonization_no_ship_block_text: String = ""
var _automation_drone_supporting_format: String = ""
var _automation_drone_on_mission_format: String = ""
var _unknown_display_name_fallback: String = ""
var _investigate_progress_format: String = ""

var _known_panel_custom_minimum_size: Vector2 = Vector2.ZERO
var _known_offset_bottom: float = 0.0
var _lore_panel_known_minimum_size: Vector2 = Vector2.ZERO
var _resource_panel_known_minimum_size: Vector2 = Vector2.ZERO
var _lore_text_label_known_minimum_size: Vector2 = Vector2.ZERO
var _lore_scroll_known_minimum_size: Vector2 = Vector2.ZERO
var _lore_scroll_known_vertical_scroll_mode: ScrollContainer.ScrollMode = (
	ScrollContainer.SCROLL_MODE_AUTO
)


func _ready() -> void:
	_capture_editor_text_templates()
	_capture_known_layout_sizes()

	if not close_base_panel_button.pressed.is_connected(_on_close_base_panel_pressed):
		close_base_panel_button.pressed.connect(_on_close_base_panel_pressed)

	if not scan_with_drone_button.pressed.is_connected(_on_scan_with_drone_pressed):
		scan_with_drone_button.pressed.connect(_on_scan_with_drone_pressed)

	if not send_mining_ship_button.pressed.is_connected(_on_send_mining_ship_pressed):
		send_mining_ship_button.pressed.connect(_on_send_mining_ship_pressed)

	if not recall_drone_button.pressed.is_connected(_on_recall_drone_pressed):
		recall_drone_button.pressed.connect(_on_recall_drone_pressed)

	if not recall_mining_ship_button.pressed.is_connected(_on_recall_mining_ship_pressed):
		recall_mining_ship_button.pressed.connect(_on_recall_mining_ship_pressed)

	if colonization_button != null:
		if not colonization_button.pressed.is_connected(_on_colonization_pressed):
			colonization_button.pressed.connect(_on_colonization_pressed)
		_colonization_button_text_default = colonization_button.text

	if investigate_button != null:
		if not investigate_button.pressed.is_connected(_on_investigate_pressed):
			investigate_button.pressed.connect(_on_investigate_pressed)
	if sensor_pulse_button != null:
		if not sensor_pulse_button.pressed.is_connected(_on_sensor_pulse_pressed):
			sensor_pulse_button.pressed.connect(_on_sensor_pulse_pressed)

	_mining_button_text_default = send_mining_ship_button.text
	_scan_button_text_default = scan_with_drone_button.text

	for ui_button: Button in [
		close_base_panel_button,
		scan_with_drone_button,
		send_mining_ship_button,
		recall_drone_button,
		recall_mining_ship_button,
		colonization_button,
		investigate_button,
		sensor_pulse_button,
	]:
		AudioManager.bind_ui_button_optional(ui_button)

	if not GameSession.object_remaining_resources_changed.is_connected(
		_on_game_session_object_resources_changed
	):
		GameSession.object_remaining_resources_changed.connect(
			_on_game_session_object_resources_changed
		)

	show_empty()


func _capture_editor_text_templates() -> void:
	_name_label_prefix = _label_prefix(name_label)
	_type_label_prefix = _label_prefix(type_label)
	_scan_status_label_prefix = _label_prefix(scan_status_label)
	_distance_label_prefix = _label_prefix(distance_label)
	_drone_orbit_label_prefix = _label_prefix(drone_orbit_label)
	_scan_drone_count_label_prefix = _label_prefix(scan_drone_count_label)
	_mining_ship_count_label_prefix = _label_prefix(mining_ship_count_label)
	_mine_orbit_label_prefix = _label_prefix(mine_orbit_label)
	_mining_bonus_label_prefix = _label_prefix(mining_bonus_label)

	_empty_value_text = empty_value_template.text.strip_edges()
	_scan_state_labels = {
		GameSession.SCAN_UNKNOWN: scan_state_unknown_template.text.strip_edges(),
		GameSession.SCAN_BASIC: scan_state_basic_template.text.strip_edges(),
		GameSession.SCAN_DEEP: scan_state_deep_template.text.strip_edges(),
		GameSession.SCAN_SPECIAL: scan_state_special_template.text.strip_edges(),
	}
	_empty_selection_lore = empty_selection_lore_template.text.strip_edges()
	_no_description_lore = no_description_lore_template.text.strip_edges()
	_mining_button_text_depleted = mining_button_depleted_template.text.strip_edges()
	_colonization_button_text_running = colonization_running_template.text.strip_edges()
	var colonization_no_ship_template := colonization_no_ship_block_template.text.strip_edges()
	_colonization_no_ship_block_text = GameSession.get_gate_text(
		GateUiTextDefinition.KEY_COLONY_NO_SHIP,
		colonization_no_ship_template,
	)
	_automation_drone_supporting_format = automation_drone_supporting_template.text.strip_edges()
	_automation_drone_on_mission_format = automation_drone_on_mission_template.text.strip_edges()
	_unknown_display_name_fallback = _scan_state_labels.get(
		GameSession.SCAN_UNKNOWN,
		_empty_value_text
	)
	if investigate_progress_format_template != null:
		_investigate_progress_format = investigate_progress_format_template.text.strip_edges()


func _capture_known_layout_sizes() -> void:
	_known_panel_custom_minimum_size = custom_minimum_size
	_known_offset_bottom = offset_bottom
	if lore_panel != null:
		_lore_panel_known_minimum_size = lore_panel.custom_minimum_size
	if resource_panel != null:
		_resource_panel_known_minimum_size = resource_panel.custom_minimum_size
	if lore_text_label != null:
		_lore_text_label_known_minimum_size = lore_text_label.custom_minimum_size
	if lore_scroll != null:
		_lore_scroll_known_minimum_size = lore_scroll.custom_minimum_size
		_lore_scroll_known_vertical_scroll_mode = lore_scroll.vertical_scroll_mode


func _get_lore_text_wrap_width() -> float:
	var wrap_width := 0.0
	if lore_scroll != null and lore_scroll.size.x > 1.0:
		wrap_width = lore_scroll.size.x
	elif size.x > 1.0:
		wrap_width = size.x
	elif custom_minimum_size.x > 1.0:
		wrap_width = custom_minimum_size.x
	else:
		wrap_width = 200.0
	# MarginContainer (4*2) + LoreMargin (4*2)
	return maxf(wrap_width - 16.0, 80.0)


func _fit_signal_lore_text_height() -> void:
	if lore_text_label == null:
		return

	var wrap_width := _get_lore_text_wrap_width()
	lore_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore_text_label.custom_minimum_size = Vector2(wrap_width, 0)
	lore_text_label.update_minimum_size()
	var content_height: float = lore_text_label.get_combined_minimum_size().y
	if content_height < 1.0:
		content_height = lore_text_label.get_minimum_size().y

	lore_text_label.custom_minimum_size = Vector2(wrap_width, content_height)
	lore_text_label.update_minimum_size()

	if lore_scroll != null:
		lore_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		lore_scroll.custom_minimum_size = Vector2(0, float(content_height))
		lore_scroll.update_minimum_size()

	if lore_panel != null:
		var lore_margin_height := 8.0
		if lore_scroll != null:
			var lore_margin := lore_scroll.get_parent() as MarginContainer
			if lore_margin != null:
				lore_margin_height = float(
					lore_margin.get_theme_constant("margin_top")
					+ lore_margin.get_theme_constant("margin_bottom")
				)
		lore_panel.custom_minimum_size = Vector2(0, float(content_height) + lore_margin_height)
		lore_panel.update_minimum_size()


func _restore_known_lore_layout() -> void:
	if lore_scroll != null:
		lore_scroll.vertical_scroll_mode = _lore_scroll_known_vertical_scroll_mode
		lore_scroll.custom_minimum_size = _lore_scroll_known_minimum_size
		lore_scroll.update_minimum_size()
	if lore_panel != null:
		lore_panel.custom_minimum_size = _lore_panel_known_minimum_size
		lore_panel.update_minimum_size()
	if lore_text_label != null:
		lore_text_label.custom_minimum_size = _lore_text_label_known_minimum_size
		lore_text_label.update_minimum_size()


func _apply_signal_panel_layout(is_signal: bool) -> void:
	if is_signal:
		custom_minimum_size = Vector2(_known_panel_custom_minimum_size.x, 0)
		if lore_text_label != null:
			lore_text_label.custom_minimum_size = Vector2(_lore_text_label_known_minimum_size.x, 0)
		if resource_panel != null:
			resource_panel.custom_minimum_size = Vector2.ZERO
		if divider_d != null:
			divider_d.visible = false
		if orbit_status_section != null:
			orbit_status_section.visible = false
		_fit_signal_lore_text_height()
	else:
		custom_minimum_size = _known_panel_custom_minimum_size
		_restore_known_lore_layout()
		if resource_panel != null:
			resource_panel.custom_minimum_size = _resource_panel_known_minimum_size
		if divider_d != null:
			divider_d.visible = true
		if orbit_status_section != null:
			orbit_status_section.visible = true
		offset_bottom = _known_offset_bottom

	_queue_panel_layout_refresh(is_signal)


func _queue_panel_layout_refresh(is_signal: bool) -> void:
	if root_vbox != null:
		root_vbox.queue_sort()
	reset_size()
	if is_signal:
		var content_height: float = maxf(
			float(get_minimum_size().y),
			float(get_combined_minimum_size().y)
		)
		if content_height > 0.0:
			offset_bottom = offset_top + content_height
	update_minimum_size()


func _label_prefix(label: Label) -> String:
	if label == null:
		return ""

	var text := label.text.strip_edges()
	var separator_index := text.find(": ")
	if separator_index >= 0:
		return text.substr(0, separator_index + 2)

	return ""


func _meta_label(prefix: String, value: String) -> String:
	return "%s%s" % [prefix, value]


func show_empty() -> void:
	current_object_id = ""

	preview_texture.texture = null
	name_label.text = _meta_label(_name_label_prefix, _empty_value_text)
	type_label.text = _meta_label(_type_label_prefix, _empty_value_text)
	scan_status_label.text = _meta_label(_scan_status_label_prefix, _empty_value_text)
	distance_label.text = _meta_label(_distance_label_prefix, _empty_value_text)

	_clear_resource_rows()

	drone_orbit_label.visible = false
	mining_ship_count_label.visible = false
	mine_orbit_label.visible = false
	mining_bonus_label.visible = false

	lore_text_label.text = _empty_selection_lore

	send_mining_ship_button.text = _mining_button_text_default
	_set_action_buttons(false, false, false, false, _scan_button_text_default, "", false, "")
	_set_recall_buttons(false, false)
	_apply_colonization_controls()

	_cached_visible_resources.clear()
	_live_action_cache = {
	"can_scan": false,
	"show_scan": false,
	"show_mine": false,
	"mine_blocked_reason": "",
		"scan_blocked_reason": "",
		"scan_button_text": _scan_button_text_default,
		"can_mine": false,
		"can_recall_drone": false,
		"can_recall_mining_ship": false,
		"is_home_base": false,
		"mining_exhausted": false,
		"scan_state": GameSession.SCAN_UNKNOWN,
		"visible_resource_count": 0,
		"system_economy_blocked_reason": "",
		"colonization_button_visible": false,
		"colonization_pending": false,
		"colonization_can_start": false,
		"is_discovery_signal": false,
		"can_investigate_signal": false,
		"investigate_blocked_reason": "",
		"investigate_in_progress": false,
		"is_investigate_active": false,
		"investigate_progress": 0.0,
		"investigate_progress_text": "",
		"discovery_complete_message": "",
	}

	_apply_signal_discovery_controls()
	_hide_investigate_progress_ui()
	_hide_sensor_pulse_progress_ui()
	if is_instance_valid(economy_block_label):
		economy_block_label.visible = false


func _exit_tree() -> void:
	if GameSession.object_remaining_resources_changed.is_connected(
		_on_game_session_object_resources_changed
	):
		GameSession.object_remaining_resources_changed.disconnect(
			_on_game_session_object_resources_changed
		)


func show_body_info(info: Dictionary) -> void:
	_apply_info(info)


func show_poi_info(info: Dictionary) -> void:
	_apply_info(info)


func _apply_info(info: Dictionary) -> void:
	current_object_id = str(info.get("id", ""))

	preview_texture.texture = info.get("preview_texture", null) as Texture2D
	name_label.text = _meta_label(
		_name_label_prefix,
		str(info.get("display_name", _unknown_display_name_fallback))
	)

	var type_text: String = "-"

	if info.has("body_type"):
		type_text = str(info.get("body_type", "-"))
	elif info.has("poi_type"):
		type_text = str(info.get("poi_type", "-"))

	type_label.text = _meta_label(_type_label_prefix, _format_title(type_text))
	scan_status_label.text = _meta_label(
		_scan_status_label_prefix,
		_format_scan_state(str(info.get("scan_state", GameSession.SCAN_UNKNOWN)))
	)
	distance_label.text = _meta_label(
		_distance_label_prefix,
		str(info.get("distance_text", _empty_value_text))
	)

	_apply_automation_status(info)
	_apply_resources(info)
	_apply_lore(info)

	_live_action_cache = {
		"can_scan": bool(info.get("can_scan_with_drone", false)),
		"show_scan": bool(info.get("show_scan_with_drone", false)),
		"show_mine": bool(info.get("show_mine_with_ship", false)),
		"mine_blocked_reason": str(info.get("mine_blocked_reason", "")).strip_edges(),
		"scan_blocked_reason": str(info.get("scan_blocked_reason", "")).strip_edges(),
		"scan_button_text": str(info.get("scan_button_text", _scan_button_text_default)).strip_edges(),
		"mining_button_text": str(info.get("mining_button_text", "")).strip_edges(),
		"assigned_scan_drone_count": int(info.get("assigned_scan_drone_count", 0)),
		"show_scan_drone_status": bool(info.get("show_scan_drone_status", false)),
		"has_active_shared_scan_job": bool(info.get("has_active_shared_scan_job", false)),
		"assigned_mining_ship_count": int(info.get("assigned_mining_ship_count", 0)),
		"show_mining_ship_status": bool(info.get("show_mining_ship_status", false)),
		"can_mine": bool(info.get("can_mine_with_ship", false)),
		"can_recall_drone": bool(info.get("can_recall_drone", false)),
		"can_recall_mining_ship": bool(info.get("can_recall_mining_ship", false)),
		"is_home_base": bool(info.get("is_home_base", false)),
		"mining_exhausted": bool(info.get("mining_exhausted", false)),
		"scan_state": str(info.get("scan_state", GameSession.SCAN_UNKNOWN)),
		"visible_resource_count": _get_visible_resource_count(info),
		"system_economy_blocked_reason": str(info.get("system_economy_blocked_reason", "")),
		"colonization_button_visible": bool(info.get("colonization_button_visible", false)),
		"colonization_pending": bool(info.get("colonization_pending", false)),
		"colonization_can_start": bool(info.get("colonization_can_start", false)),
		"is_discovery_signal": info.get("is_discovery_signal", false) == true,
		"can_investigate_signal": info.get("can_investigate_signal", false) == true,
		"investigate_blocked_reason": str(info.get("investigate_blocked_reason", "")).strip_edges(),
		"investigate_in_progress": info.get("investigate_in_progress", false) == true,
		"is_investigate_active": info.get("is_investigate_active", false) == true,
		"investigate_progress": float(info.get("investigate_progress", 0.0)),
		"investigate_progress_text": str(info.get("investigate_progress_text", "")).strip_edges(),
		"discovery_complete_message": str(info.get("discovery_complete_message", "")).strip_edges(),
		"show_sensor_pulse": bool(info.get("show_sensor_pulse", false)),
		"can_sensor_pulse": bool(info.get("can_sensor_pulse", false)),
		"sensor_pulse_blocked_reason": str(info.get("sensor_pulse_blocked_reason", "")).strip_edges(),
		"sensor_pulse_in_progress": bool(info.get("sensor_pulse_in_progress", false)),
		"sensor_pulse_progress_text": str(info.get("sensor_pulse_progress_text", "")).strip_edges(),
		"sensor_pulse_cost_text": str(info.get("sensor_pulse_cost_text", "")).strip_edges(),
	}

	_apply_signal_discovery_controls()
	_apply_live_action_controls()


func apply_investigate_progress(progress: float) -> void:
	if _live_action_cache.get("investigate_in_progress", false) != true:
		return

	var clamped: float = clampf(progress, 0.0, 1.0)
	var percent: int = int(round(clamped * 100.0))
	var progress_text := _format_investigate_progress(percent)

	_live_action_cache["investigate_progress"] = clamped
	_live_action_cache["investigate_progress_text"] = progress_text
	_live_action_cache["is_investigate_active"] = true

	_show_investigate_progress_ui(progress_text, percent)


func _show_investigate_progress_ui(progress_text: String, _percent: int) -> void:
	if investigate_progress_label != null:
		investigate_progress_label.text = progress_text
		investigate_progress_label.visible = true


func _hide_investigate_progress_ui() -> void:
	if investigate_progress_label != null:
		investigate_progress_label.visible = false


func _show_sensor_pulse_progress_ui(progress_text: String) -> void:
	if sensor_pulse_progress_label == null:
		return
	sensor_pulse_progress_label.text = progress_text
	sensor_pulse_progress_label.visible = true
	_queue_panel_layout_refresh(false)


func _hide_sensor_pulse_progress_ui() -> void:
	if sensor_pulse_progress_label == null:
		return
	if not sensor_pulse_progress_label.visible:
		return
	sensor_pulse_progress_label.visible = false
	_queue_panel_layout_refresh(false)


func _set_resource_section_visible(visible: bool) -> void:
	if divider_b != null:
		divider_b.visible = visible
	if resource_title_label != null:
		resource_title_label.visible = visible
	if resource_panel != null:
		resource_panel.visible = visible


func _apply_signal_discovery_controls() -> void:
	var is_signal: bool = _live_action_cache.get("is_discovery_signal", false) == true

	_set_resource_section_visible(not is_signal)
	_apply_signal_panel_layout(is_signal)

	if is_signal:
		drone_orbit_label.visible = false
		mining_ship_count_label.visible = false
		mine_orbit_label.visible = false
		mining_bonus_label.visible = false

	if not is_signal:
		if investigate_button != null:
			investigate_button.visible = false
		return

	if investigate_button == null:
		return

	var can_investigate: bool = _live_action_cache.get("can_investigate_signal", false) == true
	var in_progress: bool = _live_action_cache.get("investigate_in_progress", false) == true
	var blocked: String = str(_live_action_cache.get("investigate_blocked_reason", "")).strip_edges()
	var complete_msg: String = str(_live_action_cache.get("discovery_complete_message", "")).strip_edges()

	if in_progress:
		investigate_button.visible = false
	else:
		investigate_button.visible = true
		investigate_button.disabled = not can_investigate

	if in_progress:
		var progress_text: String = str(
			_live_action_cache.get("investigate_progress_text", "")
		).strip_edges()
		if progress_text.is_empty():
			progress_text = _format_investigate_progress(0)
		var percent: int = int(
			round(float(_live_action_cache.get("investigate_progress", 0.0)) * 100.0)
		)
		_show_investigate_progress_ui(progress_text, percent)
	elif _live_action_cache.get("is_investigate_active", false) != true:
		_hide_investigate_progress_ui()

	if is_instance_valid(economy_block_label):
		if not complete_msg.is_empty():
			economy_block_label.text = complete_msg
			economy_block_label.visible = true
		elif in_progress:
			economy_block_label.visible = false
		elif not can_investigate and not blocked.is_empty():
			economy_block_label.text = blocked
			economy_block_label.visible = true
		elif str(_live_action_cache.get("system_economy_blocked_reason", "")).strip_edges().is_empty():
			economy_block_label.visible = false


func _apply_live_action_controls() -> void:
	var is_signal: bool = bool(_live_action_cache.get("is_discovery_signal", false))
	if is_signal:
		_set_action_buttons(false, false, false, false, _scan_button_text_default, "", false, "")
		_set_recall_buttons(false, false)
		_apply_colonization_controls()
		_apply_signal_discovery_controls()
		return

	var block_rs: String = str(_live_action_cache.get("system_economy_blocked_reason", "")).strip_edges()

	var can_scan: bool = bool(_live_action_cache.get("can_scan", false))
	var show_scan: bool = bool(_live_action_cache.get("show_scan", false))
	var scan_blocked: String = str(_live_action_cache.get("scan_blocked_reason", "")).strip_edges()
	var scan_button_text: String = str(_live_action_cache.get("scan_button_text", _scan_button_text_default)).strip_edges()
	var mining_button_text: String = str(_live_action_cache.get("mining_button_text", "")).strip_edges()
	var can_mine: bool = bool(_live_action_cache.get("can_mine", false))
	var show_mine: bool = bool(_live_action_cache.get("show_mine", false))
	var mine_blocked: String = str(_live_action_cache.get("mine_blocked_reason", "")).strip_edges()
	var can_recall_drone: bool = bool(_live_action_cache.get("can_recall_drone", false))
	var can_recall_mining_ship: bool = bool(_live_action_cache.get("can_recall_mining_ship", false))
	var is_home_base: bool = bool(_live_action_cache.get("is_home_base", false))

	if not block_rs.is_empty():
		can_scan = false
		show_scan = false
		can_mine = false
		show_mine = false
		can_recall_drone = false
		can_recall_mining_ship = false
		if is_instance_valid(economy_block_label):
			economy_block_label.text = block_rs
			economy_block_label.visible = true
	else:
		if is_instance_valid(economy_block_label):
			economy_block_label.visible = false

	var mining_exhausted: bool = bool(_live_action_cache.get("mining_exhausted", false)) or _is_current_object_mining_exhausted()
	_live_action_cache["mining_exhausted"] = mining_exhausted

	var mining_block_depleted: bool = (
		mining_exhausted
		or mine_blocked == GateUiTextDefinition.get_text(GateUiTextDefinition.KEY_MINE_DEPLETED)
	)
	var can_mine_effective: bool = can_mine and not mining_block_depleted
	var mine_visible: bool = show_mine or can_mine
	var scan_visible: bool = show_scan or can_scan

	if block_rs.is_empty() and is_instance_valid(economy_block_label):
		var action_block := ""
		if scan_visible and not can_scan and not scan_blocked.is_empty():
			action_block = scan_blocked
		elif mine_visible and not can_mine_effective and not mine_blocked.is_empty():
			action_block = mine_blocked
		if not action_block.is_empty():
			economy_block_label.text = action_block
			economy_block_label.visible = true

	if is_home_base:
		send_mining_ship_button.text = _mining_button_text_default
		_set_action_buttons(false, false, false, false, _scan_button_text_default, "")
		_set_recall_buttons(false, false)
		_apply_sensor_pulse_controls()
	else:
		if sensor_pulse_button != null:
			sensor_pulse_button.visible = false
		_hide_sensor_pulse_progress_ui()
		_set_action_buttons(
			can_scan,
			scan_visible,
			can_mine_effective,
			mine_visible,
			scan_button_text,
			scan_blocked,
			mining_block_depleted,
			mine_blocked,
			mining_button_text,
		)
		_set_recall_buttons(can_recall_drone, can_recall_mining_ship)

	_apply_colonization_controls()
	if not is_home_base and sensor_pulse_button != null:
		sensor_pulse_button.visible = false


func _apply_sensor_pulse_controls() -> void:
	if sensor_pulse_button == null:
		return

	var show_pulse: bool = bool(_live_action_cache.get("show_sensor_pulse", false))
	if not show_pulse:
		sensor_pulse_button.visible = false
		_hide_sensor_pulse_progress_ui()
		return

	var in_progress: bool = bool(_live_action_cache.get("sensor_pulse_in_progress", false))
	var can_pulse: bool = bool(_live_action_cache.get("can_sensor_pulse", false))
	var blocked: String = str(_live_action_cache.get("sensor_pulse_blocked_reason", "")).strip_edges()

	if in_progress:
		sensor_pulse_button.visible = false
		var progress_text: String = str(
			_live_action_cache.get("sensor_pulse_progress_text", "")
		).strip_edges()
		if progress_text.is_empty():
			progress_text = DiscoverySignalUiTextDefinition.format_sensor_pulse_progress(0)
		_show_sensor_pulse_progress_ui(progress_text)
		if is_instance_valid(economy_block_label):
			economy_block_label.visible = false
		return

	_hide_sensor_pulse_progress_ui()

	sensor_pulse_button.visible = true
	sensor_pulse_button.disabled = not can_pulse

	if is_instance_valid(economy_block_label):
		if not can_pulse and not blocked.is_empty():
			economy_block_label.text = blocked
			economy_block_label.visible = true
		elif str(_live_action_cache.get("system_economy_blocked_reason", "")).strip_edges().is_empty():
			economy_block_label.visible = false


func _apply_colonization_controls() -> void:
	if colonization_button == null:
		return

	var show_colonization := bool(_live_action_cache.get("colonization_button_visible", false))
	colonization_button.visible = show_colonization
	if not show_colonization:
		colonization_button.disabled = true
		colonization_button.text = _colonization_button_text_default
		return

	if bool(_live_action_cache.get("colonization_pending", false)):
		colonization_button.disabled = true
		colonization_button.text = _colonization_button_text_running
		return

	var can_start: bool = bool(_live_action_cache.get("colonization_can_start", false))
	colonization_button.disabled = not can_start
	colonization_button.text = _colonization_button_text_default
	if not can_start and is_instance_valid(economy_block_label) and not _colonization_no_ship_block_text.is_empty():
		economy_block_label.text = _colonization_no_ship_block_text
		economy_block_label.visible = true


func _is_current_object_mining_exhausted() -> bool:
	var system_id_r: String = GameSession.current_system_id

	if system_id_r.is_empty() or current_object_id.is_empty():
		return false

	if _cached_visible_resources.is_empty():
		return false

	if not GameSession.has_object_resources(system_id_r, current_object_id):
		return false

	var has_mineable_entry := false

	for entry: Variant in _cached_visible_resources:
		if not (entry is Dictionary):
			continue

		var resource_id_r: String = _get_resource_store_id(entry as Dictionary)
		if resource_id_r.is_empty():
			continue

		has_mineable_entry = true

		var remaining: int = GameSession.get_remaining_resource_amount(
			system_id_r,
			current_object_id,
			resource_id_r
		)

		if remaining > 0:
			return false

	return has_mineable_entry


func _get_visible_resource_count(info: Dictionary) -> int:
	var visible_resources_variant: Variant = info.get("resources_visible", [])
	if visible_resources_variant is Array:
		return (visible_resources_variant as Array).size()

	return 0


func _apply_automation_status(info: Dictionary) -> void:
	var drone_supporting: int = int(info.get("scan_drone_supporting_count", 0))
	var drone_total_assigned: int = int(info.get("active_scan_drone_count", 0))
	var drone_on_mission: int = maxi(0, drone_total_assigned - drone_supporting)

	var mining_mining_count: int = int(info.get("mining_ship_mining_count", 0))
	var assigned_mining_count: int = int(info.get("assigned_mining_ship_count", 0))
	var show_mining_ship_status: bool = bool(info.get("show_mining_ship_status", false))
	var assigned_scan_count: int = int(info.get("assigned_scan_drone_count", 0))
	var show_scan_drone_status: bool = bool(info.get("show_scan_drone_status", false))
	var upgrade_base_id: String = str(info.get("mining_yield_upgrade_base_id", "")).strip_edges()
	if upgrade_base_id.is_empty():
		upgrade_base_id = BaseStore.BASE_EARTH
	var per_drone_pct: int = GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(
		upgrade_base_id
	)
	var bonus_pct: int = drone_supporting * per_drone_pct

	var drone_line_visible: bool = drone_supporting > 0 or drone_on_mission > 0
	var mine_line_visible: bool = mining_mining_count > 0
	var activity_any: bool = drone_line_visible or mine_line_visible

	drone_orbit_label.visible = drone_line_visible
	scan_drone_count_label.visible = show_scan_drone_status
	mining_ship_count_label.visible = show_mining_ship_status
	mine_orbit_label.visible = mine_line_visible
	mining_bonus_label.visible = activity_any

	if show_scan_drone_status:
		scan_drone_count_label.text = _meta_label(
			_scan_drone_count_label_prefix,
			NumberFormat.format_compact(assigned_scan_count),
		)

	if show_mining_ship_status:
		mining_ship_count_label.text = _meta_label(
			_mining_ship_count_label_prefix,
			NumberFormat.format_compact(assigned_mining_count),
		)

	var drone_parts: PackedStringArray = []

	if drone_supporting > 0 and not _automation_drone_supporting_format.is_empty():
		drone_parts.append(
			_format_count_template(_automation_drone_supporting_format, drone_supporting)
		)

	if drone_on_mission > 0 and not _automation_drone_on_mission_format.is_empty():
		drone_parts.append(_format_count_template(_automation_drone_on_mission_format, drone_on_mission))

	drone_orbit_label.text = _meta_label(_drone_orbit_label_prefix, ", ".join(drone_parts))
	mine_orbit_label.text = _meta_label(
		_mine_orbit_label_prefix,
		NumberFormat.format_compact(mining_mining_count),
	)
	mining_bonus_label.text = _meta_label(_mining_bonus_label_prefix, "+%d%%" % bonus_pct)


func _apply_resources(info: Dictionary) -> void:
	_cached_visible_resources.clear()

	var visible_resources_variant: Variant = info.get("resources_visible", [])
	if visible_resources_variant is Array:
		_cached_visible_resources = (visible_resources_variant as Array).duplicate()

	_refresh_resource_rows_from_cache()


func _refresh_resource_rows_from_cache() -> void:
	_clear_resource_rows()

	for entry: Variant in _cached_visible_resources:
		var row: ResourceInfoRow = RESOURCE_INFO_ROW_SCENE.instantiate() as ResourceInfoRow
		resource_list.add_child(row)

		if entry is Dictionary:
			_apply_resource_dict_to_row(row, entry as Dictionary)
		else:
			var entry_id := str(entry).strip_edges()
			row.set_row_data(_resolve_resource_label_for_id(entry_id), "--")


func _apply_resource_dict_to_row(row: ResourceInfoRow, resource_entry: Dictionary) -> void:
	var detail_text: String = _build_resource_detail_text(resource_entry)
	row.set_row_data(_resolve_resource_label_for_entry(resource_entry), detail_text)


func _resolve_resource_label_for_id(resource_id: String) -> String:
	var cleaned := resource_id.strip_edges()
	var title_fallback := _format_title(cleaned)
	return GameSession.get_resource_display_name(StringName(cleaned), title_fallback)


func _resolve_resource_label_for_entry(resource_entry: Dictionary) -> String:
	var resource_id_r: String = _get_resource_store_id(resource_entry)
	if resource_id_r.is_empty():
		resource_id_r = _get_resource_display_name(resource_entry)
	return _resolve_resource_label_for_id(resource_id_r)


func _get_resource_display_name(resource_entry: Dictionary) -> String:
	# New scan_info_builder format.
	if resource_entry.has("id"):
		return String(resource_entry.get("id", &""))

	# Compatibility with older/local formats.
	if resource_entry.has("resource_id"):
		return String(resource_entry.get("resource_id", &""))

	if resource_entry.has("name"):
		return str(resource_entry.get("name", ""))

	return _unknown_display_name_fallback


func _get_resource_store_id(resource_entry: Dictionary) -> String:
	if resource_entry.has("id"):
		return String(resource_entry.get("id", &""))

	if resource_entry.has("resource_id"):
		return String(resource_entry.get("resource_id", &""))

	if resource_entry.has("name"):
		return str(resource_entry.get("name", ""))

	return ""


func _build_resource_detail_text(resource_entry: Dictionary) -> String:
	var system_id_r: String = GameSession.current_system_id

	if system_id_r.is_empty() or current_object_id.is_empty():
		return _build_amount_text_without_store(resource_entry)

	if not GameSession.has_object_resources(system_id_r, current_object_id):
		return _build_amount_text_without_store(resource_entry)

	var resource_id_r: String = _get_resource_store_id(resource_entry)

	if resource_id_r.is_empty():
		return _build_amount_text_without_store(resource_entry)

	var remaining: int = GameSession.get_remaining_resource_amount(
		system_id_r,
		current_object_id,
		resource_id_r
	)

	var total_from_entry: int = _read_total_amount_from_resource_entry(resource_entry)
	var total: int = remaining

	if total_from_entry >= 0:
		total = maxi(total_from_entry, remaining)

	if remaining <= 0:
		return "0 / %s" % NumberFormat.format_compact(total)

	return "%s / %s" % [
		NumberFormat.format_compact(remaining),
		NumberFormat.format_compact(total),
	]


## Reads an optional cap/total from the scan `resources_visible` dict only (no store/API).
## Returns -1 if no usable field exists — caller then uses `remaining` as display total (fallback).
func _read_total_amount_from_resource_entry(resource_entry: Dictionary) -> int:
	const KEYS: Array[StringName] = [
		&"total",
		&"total_amount",
		&"max_amount",
		&"initial_amount",
		&"original_amount",
		&"base_amount",
		&"deposit_amount",
		&"amount",
	]

	for key: StringName in KEYS:
		if not resource_entry.has(key):
			continue

		var raw: Variant = resource_entry.get(key, null)
		if raw == null:
			continue

		var parsed: int = int(raw)

		if parsed < 0:
			continue

		return parsed

	return -1


func _apply_lore(info: Dictionary) -> void:
	var lore_text: String = str(info.get("lore_text", "")).strip_edges()

	if lore_text.is_empty():
		lore_text = _no_description_lore

	lore_text_label.text = lore_text


func _set_action_buttons(
	can_scan: bool,
	show_scan: bool,
	mine_enabled: bool,
	mine_visible: bool,
	scan_button_text: String = "",
	scan_blocked_reason: String = "",
	mining_depleted: bool = false,
	mine_blocked_reason: String = "",
	mining_button_text: String = "",
) -> void:
	scan_with_drone_button.visible = show_scan
	scan_with_drone_button.disabled = not can_scan

	var scan_label := scan_button_text.strip_edges()
	if scan_label.is_empty():
		scan_label = _scan_button_text_default
	scan_with_drone_button.text = scan_label

	send_mining_ship_button.visible = mine_visible
	send_mining_ship_button.disabled = not mine_enabled

	if mining_depleted:
		send_mining_ship_button.text = _mining_button_text_depleted
	else:
		var mine_label := mining_button_text.strip_edges()
		if mine_label.is_empty():
			mine_label = _mining_button_text_default
		send_mining_ship_button.text = mine_label


func _set_recall_buttons(can_recall_drone: bool, can_recall_mining_ship: bool) -> void:
	recall_drone_button.visible = can_recall_drone
	recall_drone_button.disabled = not can_recall_drone

	recall_mining_ship_button.visible = can_recall_mining_ship
	recall_mining_ship_button.disabled = not can_recall_mining_ship


func set_distance_text(value_text: String) -> void:
	distance_label.text = _meta_label(_distance_label_prefix, value_text)


func _clear_resource_rows() -> void:
	for child in resource_list.get_children():
		child.queue_free()


func _build_amount_text_without_store(resource_entry: Dictionary) -> String:
	var total_from_entry: int = _read_total_amount_from_resource_entry(resource_entry)
	if total_from_entry >= 0:
		var compact_total := NumberFormat.format_compact(total_from_entry)
		return "%s / %s" % [compact_total, compact_total]

	return "--"


func _format_investigate_progress(percent: int) -> String:
	var format_str := _investigate_progress_format.strip_edges()
	if format_str.is_empty():
		return DiscoverySignalUiTextDefinition.format_investigate_progress(percent)
	return format_str % maxi(0, percent)


func _format_count_template(format_str: String, count: int) -> String:
	var compact := NumberFormat.format_compact(count)
	if format_str.contains("%d"):
		return format_str.replace("%d", compact)
	return format_str % compact


func _format_scan_state(scan_state: String) -> String:
	if _scan_state_labels.has(scan_state):
		return str(_scan_state_labels.get(scan_state, _empty_value_text))

	return _format_title(scan_state)


func _format_title(value: String) -> String:
	var cleaned: String = value.strip_edges().replace("_", " ")

	if cleaned.is_empty():
		return _empty_value_text

	var words: PackedStringArray = cleaned.split(" ", false)
	var result_words: PackedStringArray = []

	for word in words:
		if word.is_empty():
			continue

		result_words.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())

	return " ".join(result_words)


func _on_game_session_object_resources_changed(changed_system_id: String, changed_object_id: String) -> void:
	if current_object_id.is_empty():
		return

	if visible == false:
		return

	var view_system_id: String = GameSession.current_system_id

	if view_system_id.is_empty() or changed_system_id != view_system_id:
		return

	if changed_object_id != current_object_id:
		return

	_refresh_resource_rows_from_cache()
	_apply_live_action_controls()


func _on_close_base_panel_pressed() -> void:
	show_empty()
	hide()
	close_requested.emit()


func _on_scan_with_drone_pressed() -> void:
	if current_object_id.is_empty():
		return

	scan_requested.emit(current_object_id)


func _on_send_mining_ship_pressed() -> void:
	if current_object_id.is_empty():
		return

	mining_requested.emit(current_object_id)


func _on_recall_drone_pressed() -> void:
	if current_object_id.is_empty():
		return

	recall_drone_requested.emit(current_object_id)


func _on_recall_mining_ship_pressed() -> void:
	if current_object_id.is_empty():
		return

	recall_mining_ship_requested.emit(current_object_id)


func _on_colonization_pressed() -> void:
	if current_object_id.is_empty():
		return
	if colonization_button == null or colonization_button.disabled:
		return

	colonization_requested.emit(current_object_id)


func _forward_investigate_if_unconnected(object_id: String) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group(&"system_ui_controller"):
		if node is SystemUIController:
			(node as SystemUIController).handle_investigate_requested(oid)
			return
	push_warning(
		"ObjectInfoPanel: investigate_requested has no listeners (object_id=%s)." % oid
	)


func _on_investigate_pressed() -> void:
	if current_object_id.is_empty():
		return
	if investigate_button == null or investigate_button.disabled:
		return

	var listener_count: int = investigate_requested.get_connections().size()
	investigate_requested.emit(current_object_id)
	if listener_count == 0:
		_forward_investigate_if_unconnected(current_object_id)


func _on_sensor_pulse_pressed() -> void:
	if sensor_pulse_button == null or sensor_pulse_button.disabled:
		return

	var listener_count: int = sensor_pulse_requested.get_connections().size()
	sensor_pulse_requested.emit()
	if listener_count == 0:
		_forward_sensor_pulse_if_unconnected()


func _forward_sensor_pulse_if_unconnected() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"system_ui_controller"):
		if node is SystemUIController:
			(node as SystemUIController).handle_sensor_pulse_requested()
			return
	push_warning("ObjectInfoPanel: sensor_pulse_requested has no listeners.")
