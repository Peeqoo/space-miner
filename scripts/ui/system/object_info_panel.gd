## Shows selected planet / object information.
## Emits action signals when the player wants to scan or mine the selected object.
extends PanelContainer

signal scan_requested(object_id: String)
signal mining_requested(object_id: String)
signal recall_drone_requested(object_id: String)
signal recall_mining_ship_requested(object_id: String)
signal colonization_requested(object_id: String)
signal close_requested()

const RESOURCE_INFO_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/resource_info_row.tscn")

@onready var header_label: Label = $Margin/Root/HBoxContainer/HeaderLabel
@onready var preview_texture: TextureRect = $Margin/Root/MainRow/PreviewPanel/PreviewCenter/PreviewTexture
@onready var name_label: Label = $Margin/Root/MainRow/MetaColumn/NameLabel
@onready var type_label: Label = $Margin/Root/MainRow/MetaColumn/TypeLabel
@onready var scan_status_label: Label = $Margin/Root/MainRow/MetaColumn/ScanStatusLabel
@onready var distance_label: Label = $Margin/Root/MainRow/MetaColumn/DistanceLabel
@onready var resource_title_label: Label = $Margin/Root/ResourceTitleLabel
@onready var resource_list: VBoxContainer = $Margin/Root/ResourcePanel/ResourceMargin/ResourceScroll/ResourceList
@onready var lore_title_label: Label = $Margin/Root/LoreTitleLabel
@onready var lore_text_label: Label = $Margin/Root/LorePanel/LoreMargin/LoreScroll/LoreTextLabel

@onready var drone_orbit_label: Label = $Margin/Root/OrbitStatusSection/DroneOrbitLabel
@onready var mine_orbit_label: Label = $Margin/Root/OrbitStatusSection/MineOrbitLabel
@onready var mining_bonus_label: Label = $Margin/Root/OrbitStatusSection/MiningBonusLabel

@onready var close_base_panel_button: Button = $Margin/Root/HBoxContainer/CloseBasePanelButton
@onready var scan_with_drone_button: Button = $Margin/Root/GridContainer/ScanWithDroneButton
@onready var send_mining_ship_button: Button = $Margin/Root/GridContainer/SendMiningShipButton
@onready var recall_drone_button: Button = $Margin/Root/GridContainer/RecallDroneButton
@onready var recall_mining_ship_button: Button = $Margin/Root/GridContainer/RecallMiningShipButton
@onready var colonization_button: Button = $Margin/Root/GridContainer/ColonizationButton
@onready var economy_block_label: Label = $Margin/Root/EconomyBlockLabel

@onready var empty_value_template: Label = $Margin/Root/EmptyValueTemplate
@onready var scan_state_unknown_template: Label = $Margin/Root/ScanStateUnknownTemplate
@onready var scan_state_basic_template: Label = $Margin/Root/ScanStateBasicTemplate
@onready var scan_state_deep_template: Label = $Margin/Root/ScanStateDeepTemplate
@onready var scan_state_special_template: Label = $Margin/Root/ScanStateSpecialTemplate
@onready var empty_selection_lore_template: Label = $Margin/Root/EmptySelectionLoreTemplate
@onready var no_description_lore_template: Label = $Margin/Root/NoDescriptionLoreTemplate
@onready var mining_button_depleted_template: Label = $Margin/Root/MiningButtonDepletedTemplate
@onready var colonization_running_template: Label = $Margin/Root/ColonizationRunningTemplate
@onready var colonization_no_ship_tooltip_template: Label = $Margin/Root/ColonizationNoShipTooltipTemplate
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
}

## Editor-owned prefixes captured from visible meta/orbit labels in _ready().
var _name_label_prefix: String = ""
var _type_label_prefix: String = ""
var _scan_status_label_prefix: String = ""
var _distance_label_prefix: String = ""
var _drone_orbit_label_prefix: String = ""
var _mine_orbit_label_prefix: String = ""
var _mining_bonus_label_prefix: String = ""

var _empty_value_text: String = "-"
var _scan_state_labels: Dictionary = {}
var _empty_selection_lore: String = ""
var _no_description_lore: String = ""
var _mining_button_text_default: String = ""
var _mining_button_text_depleted: String = ""
var _colonization_button_text_default: String = ""
var _colonization_button_text_running: String = ""
var _colonization_no_ship_tooltip: String = ""
var _automation_drone_supporting_format: String = ""
var _automation_drone_on_mission_format: String = ""
var _unknown_display_name_fallback: String = ""


func _ready() -> void:
	_capture_editor_text_templates()

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

	_mining_button_text_default = send_mining_ship_button.text

	for ui_button: Button in [
		close_base_panel_button,
		scan_with_drone_button,
		send_mining_ship_button,
		recall_drone_button,
		recall_mining_ship_button,
		colonization_button,
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
	_colonization_no_ship_tooltip = colonization_no_ship_tooltip_template.text.strip_edges()
	_automation_drone_supporting_format = automation_drone_supporting_template.text.strip_edges()
	_automation_drone_on_mission_format = automation_drone_on_mission_template.text.strip_edges()
	_unknown_display_name_fallback = _scan_state_labels.get(
		GameSession.SCAN_UNKNOWN,
		_empty_value_text
	)


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
	mine_orbit_label.visible = false
	mining_bonus_label.visible = false

	lore_text_label.text = _empty_selection_lore

	send_mining_ship_button.text = _mining_button_text_default
	_set_action_buttons(false, false, false)
	_set_recall_buttons(false, false)
	_apply_colonization_controls()

	_cached_visible_resources.clear()
	_live_action_cache = {
		"can_scan": false,
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
	}

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
	}

	_apply_live_action_controls()


func _apply_live_action_controls() -> void:
	var block_rs: String = str(_live_action_cache.get("system_economy_blocked_reason", "")).strip_edges()

	var can_scan: bool = bool(_live_action_cache.get("can_scan", false))
	var can_mine: bool = bool(_live_action_cache.get("can_mine", false))
	var can_recall_drone: bool = bool(_live_action_cache.get("can_recall_drone", false))
	var can_recall_mining_ship: bool = bool(_live_action_cache.get("can_recall_mining_ship", false))
	var is_home_base: bool = bool(_live_action_cache.get("is_home_base", false))

	if not block_rs.is_empty():
		can_scan = false
		can_mine = false
		can_recall_drone = false
		can_recall_mining_ship = false
		if is_instance_valid(economy_block_label):
			economy_block_label.text = block_rs
			economy_block_label.visible = true
		scan_with_drone_button.tooltip_text = block_rs
		send_mining_ship_button.tooltip_text = block_rs
		recall_drone_button.tooltip_text = block_rs
		recall_mining_ship_button.tooltip_text = block_rs
	else:
		if is_instance_valid(economy_block_label):
			economy_block_label.visible = false
		scan_with_drone_button.tooltip_text = ""
		send_mining_ship_button.tooltip_text = ""
		recall_drone_button.tooltip_text = ""
		recall_mining_ship_button.tooltip_text = ""

	var mining_exhausted: bool = bool(_live_action_cache.get("mining_exhausted", false)) or _is_current_object_mining_exhausted()
	_live_action_cache["mining_exhausted"] = mining_exhausted

	var mining_block_depleted: bool = mining_exhausted
	var can_mine_effective: bool = can_mine and not mining_block_depleted

	if is_home_base:
		send_mining_ship_button.text = _mining_button_text_default
		_set_action_buttons(false, false, false)
		_set_recall_buttons(false, false)
	else:
		_set_action_buttons(can_scan, can_mine, can_mine_effective)
		_set_recall_buttons(can_recall_drone, can_recall_mining_ship)

		if can_mine and mining_block_depleted:
			send_mining_ship_button.text = _mining_button_text_depleted
		else:
			send_mining_ship_button.text = _mining_button_text_default

	_apply_colonization_controls()


func _apply_colonization_controls() -> void:
	if colonization_button == null:
		return

	var show_colonization := bool(_live_action_cache.get("colonization_button_visible", false))
	colonization_button.visible = show_colonization
	if not show_colonization:
		colonization_button.disabled = true
		colonization_button.text = _colonization_button_text_default
		colonization_button.tooltip_text = ""
		return

	if bool(_live_action_cache.get("colonization_pending", false)):
		colonization_button.disabled = true
		colonization_button.text = _colonization_button_text_running
		colonization_button.tooltip_text = ""
		return

	var can_start: bool = bool(_live_action_cache.get("colonization_can_start", false))
	colonization_button.disabled = not can_start
	colonization_button.text = _colonization_button_text_default
	if can_start:
		colonization_button.tooltip_text = ""
	else:
		colonization_button.tooltip_text = _colonization_no_ship_tooltip


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
	mine_orbit_label.visible = mine_line_visible
	mining_bonus_label.visible = activity_any

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
			row.set_row_data(_format_title(str(entry)), "--")


func _apply_resource_dict_to_row(row: ResourceInfoRow, resource_entry: Dictionary) -> void:
	var resource_name: String = _get_resource_display_name(resource_entry)
	var detail_text: String = _build_resource_detail_text(resource_entry)
	row.set_row_data(_format_title(resource_name), detail_text)


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


func _set_action_buttons(can_scan: bool, mine_visible: bool, mine_enabled: bool) -> void:
	scan_with_drone_button.visible = can_scan
	scan_with_drone_button.disabled = not can_scan

	send_mining_ship_button.visible = mine_visible
	send_mining_ship_button.disabled = not mine_enabled


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
