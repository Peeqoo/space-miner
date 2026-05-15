## Shows selected planet / object information.
## Emits action signals when the player wants to scan or mine the selected object.
extends PanelContainer

signal scan_requested(object_id: String)
signal mining_requested(object_id: String)
signal recall_drone_requested(object_id: String)
signal recall_mining_ship_requested(object_id: String)
signal close_requested()

const RESOURCE_INFO_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/resource_info_row.tscn")

const MINING_BUTTON_TEXT_DEFAULT: String = "Mine"
const MINING_BUTTON_TEXT_DEPLETED: String = "Depleted"

@onready var header_label: Label = $Margin/Root/HBoxContainer/HeaderLabel
@onready var preview_texture: TextureRect = $Margin/Root/MainRow/PreviewPanel/PreviewCenter/PreviewTexture
@onready var name_label: Label = $Margin/Root/MainRow/MetaColumn/NameLabel
@onready var type_label: Label = $Margin/Root/MainRow/MetaColumn/TypeLabel
@onready var scan_status_label: Label = $Margin/Root/MainRow/MetaColumn/ScanStatusLabel
@onready var distance_label: Label = $Margin/Root/MainRow/MetaColumn/DistanceLabel
@onready var resource_title_label: Label = $Margin/Root/ResourceTitleLabel
@onready var resource_list: VBoxContainer = $Margin/Root/ResourcePanel/ResourceMargin/ResourceScroll/ResourceList
@onready var lore_title_label: Label = $Margin/Root/LoreTitleLabel
@onready var lore_text_label: Label = $Margin/Root/LoreTextLabel

@onready var drone_orbit_label: Label = $Margin/Root/OrbitStatusSection/DroneOrbitLabel
@onready var mine_orbit_label: Label = $Margin/Root/OrbitStatusSection/MineOrbitLabel
@onready var mining_bonus_label: Label = $Margin/Root/OrbitStatusSection/MiningBonusLabel

@onready var close_base_panel_button: Button = $Margin/Root/HBoxContainer/CloseBasePanelButton
@onready var scan_with_drone_button: Button = $Margin/Root/GridContainer/ScanWithDroneButton
@onready var send_mining_ship_button: Button = $Margin/Root/GridContainer/SendMiningShipButton
@onready var recall_drone_button: Button = $Margin/Root/GridContainer/RecallDroneButton
@onready var recall_mining_ship_button: Button = $Margin/Root/GridContainer/RecallMiningShipButton

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
}

var _economy_block_label: Label = null


func _ready() -> void:
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

	if not GameSession.object_remaining_resources_changed.is_connected(
		_on_game_session_object_resources_changed
	):
		GameSession.object_remaining_resources_changed.connect(
			_on_game_session_object_resources_changed
		)

	show_empty()


func show_empty() -> void:
	current_object_id = ""

	preview_texture.texture = null
	name_label.text = "Name: -"
	type_label.text = "Typ: -"
	scan_status_label.text = "Scanstatus: -"
	distance_label.text = "Distanz: -"
	resource_title_label.text = "Resources"

	_clear_resource_rows()

	drone_orbit_label.visible = false
	mine_orbit_label.visible = false
	mining_bonus_label.visible = false

	lore_text_label.text = "Kein Objekt ausgewählt."

	send_mining_ship_button.text = MINING_BUTTON_TEXT_DEFAULT
	_set_action_buttons(false, false, false)
	_set_recall_buttons(false, false)

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
	}

	if _economy_block_label != null and is_instance_valid(_economy_block_label):
		_economy_block_label.visible = false

	call_deferred("_fit_height_to_content")


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

	resource_title_label.text = "Resources"
	preview_texture.texture = info.get("preview_texture", null) as Texture2D
	name_label.text = "Name: %s" % str(info.get("display_name", "Unknown"))

	var type_text: String = "-"

	if info.has("body_type"):
		type_text = str(info.get("body_type", "-"))
	elif info.has("poi_type"):
		type_text = str(info.get("poi_type", "-"))

	type_label.text = "Typ: %s" % _format_title(type_text)
	scan_status_label.text = "Scanstatus: %s" % _format_scan_state(str(info.get("scan_state", GameSession.SCAN_UNKNOWN)))
	distance_label.text = "Distanz: %s" % str(info.get("distance_text", "-"))

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
	}

	_apply_live_action_controls()


func _ensure_economy_block_label() -> void:
	if _economy_block_label != null and is_instance_valid(_economy_block_label):
		return
	var root: Node = get_node_or_null("Margin/Root")
	if root == null:
		return
	var grid: Node = root.get_node_or_null("GridContainer")
	if grid == null:
		return
	var lbl := Label.new()
	lbl.name = "EconomyBlockLabel"
	lbl.visible = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 6)
	root.add_child(lbl)
	root.move_child(lbl, grid.get_index())
	_economy_block_label = lbl


func _apply_live_action_controls() -> void:
	var block_rs: String = str(_live_action_cache.get("system_economy_blocked_reason", "")).strip_edges()
	_ensure_economy_block_label()

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
		if _economy_block_label != null:
			_economy_block_label.text = block_rs
			_economy_block_label.visible = true
		scan_with_drone_button.tooltip_text = block_rs
		send_mining_ship_button.tooltip_text = block_rs
		recall_drone_button.tooltip_text = block_rs
		recall_mining_ship_button.tooltip_text = block_rs
	else:
		if _economy_block_label != null:
			_economy_block_label.visible = false
		scan_with_drone_button.tooltip_text = ""
		send_mining_ship_button.tooltip_text = ""
		recall_drone_button.tooltip_text = ""
		recall_mining_ship_button.tooltip_text = ""

	var mining_exhausted: bool = bool(_live_action_cache.get("mining_exhausted", false)) or _is_current_object_mining_exhausted()
	_live_action_cache["mining_exhausted"] = mining_exhausted

	var mining_block_depleted: bool = mining_exhausted
	var can_mine_effective: bool = can_mine and not mining_block_depleted

	if is_home_base:
		send_mining_ship_button.text = MINING_BUTTON_TEXT_DEFAULT
		_set_action_buttons(false, false, false)
		_set_recall_buttons(false, false)
	else:
		_set_action_buttons(can_scan, can_mine, can_mine_effective)
		_set_recall_buttons(can_recall_drone, can_recall_mining_ship)

		if can_mine and mining_block_depleted:
			send_mining_ship_button.text = MINING_BUTTON_TEXT_DEPLETED
		else:
			send_mining_ship_button.text = MINING_BUTTON_TEXT_DEFAULT

	call_deferred("_fit_height_to_content")


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

	if drone_supporting > 0:
		drone_parts.append("%d supporting" % drone_supporting)

	if drone_on_mission > 0:
		drone_parts.append("%d on mission" % drone_on_mission)

	drone_orbit_label.text = "ScanDrones: %s" % ", ".join(drone_parts)
	mine_orbit_label.text = "MiningShips: %d mining" % mining_mining_count

	mining_bonus_label.text = "Local Effects: Mining Yield Bonus: +%d%%" % bonus_pct


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

	return "Unknown"


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

	if (
		system_id_r.is_empty()
		or current_object_id.is_empty()
		or not GameSession.has_object_resources(system_id_r, current_object_id)
	):
		return _build_percent_text(resource_entry)

	var resource_id_r: String = _get_resource_store_id(resource_entry)

	if resource_id_r.is_empty():
		return _build_percent_text(resource_entry)

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
		return "0 / %d" % total

	return "%d / %d" % [remaining, total]


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
		lore_text = "Keine Beschreibung verfügbar."

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


func set_distance_text(text: String) -> void:
	distance_label.text = text


func _clear_resource_rows() -> void:
	for child in resource_list.get_children():
		child.queue_free()


func _build_percent_text(resource_entry: Dictionary) -> String:
	# Preferred new scan_info_builder format from ScannedResourceEntry.
	if resource_entry.has("richness_percent"):
		return "Richness: %d%%" % int(resource_entry.get("richness_percent", 0))

	# Compatibility with older/local formats.
	if resource_entry.has("percent"):
		return "Richness: %d%%" % int(resource_entry.get("percent", 0))

	if resource_entry.has("abundance_percent"):
		return "Richness: %d%%" % int(resource_entry.get("abundance_percent", 0))

	return "--"


func _format_scan_state(scan_state: String) -> String:
	match scan_state:
		GameSession.SCAN_UNKNOWN:
			return "Unknown"
		GameSession.SCAN_BASIC:
			return "Basic"
		GameSession.SCAN_DEEP:
			return "Deep"
		GameSession.SCAN_SPECIAL:
			return "Special"
		_:
			return _format_title(scan_state)


func _format_title(value: String) -> String:
	var cleaned: String = value.strip_edges().replace("_", " ")

	if cleaned.is_empty():
		return "-"

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


func _fit_height_to_content() -> void:
	if not is_inside_tree():
		return

	if not visible:
		return

	size.y = get_combined_minimum_size().y
