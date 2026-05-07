## Shows selected planet / object information.
## Emits action signals when the player wants to scan or mine the selected object.
extends PanelContainer

signal scan_requested(object_id: String)
signal mining_requested(object_id: String)
signal recall_drone_requested(object_id: String)
signal recall_mining_ship_requested(object_id: String)

const RESOURCE_INFO_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/resource_info_row.tscn")

@onready var header_label: Label = $Margin/Root/HeaderLabel
@onready var preview_texture: TextureRect = $Margin/Root/MainRow/PreviewPanel/PreviewCenter/PreviewTexture
@onready var name_label: Label = $Margin/Root/MainRow/MetaColumn/NameLabel
@onready var type_label: Label = $Margin/Root/MainRow/MetaColumn/TypeLabel
@onready var scan_status_label: Label = $Margin/Root/MainRow/MetaColumn/ScanStatusLabel
@onready var distance_label: Label = $Margin/Root/MainRow/MetaColumn/DistanceLabel
@onready var resource_title_label: Label = $Margin/Root/ResourceTitleLabel
@onready var resource_list: VBoxContainer = $Margin/Root/ResourcePanel/ResourceMargin/ResourceScroll/ResourceList
@onready var hidden_resources_label: Label = $Margin/Root/HiddenResourcesLabel
@onready var lore_title_label: Label = $Margin/Root/LoreTitleLabel
@onready var lore_text_label: Label = $Margin/Root/LoreTextLabel

@onready var drone_orbit_label: Label = $Margin/Root/VBoxContainer/DroneOrbitLabel
@onready var mine_orbit_label: Label = $Margin/Root/VBoxContainer/MineOrbitLabel
@onready var mining_bonus_label: Label = $Margin/Root/VBoxContainer/MiningBonusLabel

@onready var scan_with_drone_button: Button = $Margin/Root/HBoxContainer/ScanWithDroneButton
@onready var send_mining_ship_button: Button = $Margin/Root/HBoxContainer/SendMiningShipButton
@onready var recall_drone_button: Button = $Margin/Root/HBoxContainer/RecallDroneButton
@onready var recall_mining_ship_button: Button = $Margin/Root/HBoxContainer/RecallMiningShipButton

var current_object_id: String = ""


func _ready() -> void:
	header_label.text = "OBJEKT-INFO"
	resource_title_label.text = "SICHTBARE RESSOURCEN"
	lore_title_label.text = "HINWEIS"

	if not scan_with_drone_button.pressed.is_connected(_on_scan_with_drone_pressed):
		scan_with_drone_button.pressed.connect(_on_scan_with_drone_pressed)

	if not send_mining_ship_button.pressed.is_connected(_on_send_mining_ship_pressed):
		send_mining_ship_button.pressed.connect(_on_send_mining_ship_pressed)

	if not recall_drone_button.pressed.is_connected(_on_recall_drone_pressed):
		recall_drone_button.pressed.connect(_on_recall_drone_pressed)

	if not recall_mining_ship_button.pressed.is_connected(_on_recall_mining_ship_pressed):
		recall_mining_ship_button.pressed.connect(_on_recall_mining_ship_pressed)

	show_empty()


func show_empty() -> void:
	current_object_id = ""

	header_label.text = "OBJEKT-INFO"
	preview_texture.texture = null
	name_label.text = "Name: -"
	type_label.text = "Typ: -"
	scan_status_label.text = "Scanstatus: -"
	distance_label.text = "Distanz: -"

	_clear_resource_rows()

	hidden_resources_label.visible = false
	drone_orbit_label.visible = false
	mine_orbit_label.visible = false
	mining_bonus_label.visible = false

	lore_text_label.text = "Kein Objekt ausgewählt."

	_set_action_buttons(false, false)
	_set_recall_buttons(false, false)


func show_body_info(info: Dictionary) -> void:
	_apply_info(info, "PLANETEN-INFO")


func show_poi_info(info: Dictionary) -> void:
	_apply_info(info, "OBJEKT-INFO")


func _apply_info(info: Dictionary, panel_title: String) -> void:
	header_label.text = panel_title
	current_object_id = str(info.get("id", ""))

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

	var can_scan: bool = bool(info.get("can_scan_with_drone", false))
	var can_mine: bool = bool(info.get("can_mine_with_ship", false))
	var can_recall_drone: bool = bool(info.get("can_recall_drone", false))
	var can_recall_mining_ship: bool = bool(info.get("can_recall_mining_ship", false))
	var is_home_base: bool = bool(info.get("is_home_base", false))

	if is_home_base:
		_set_action_buttons(false, false)
		_set_recall_buttons(false, false)
	else:
		_set_action_buttons(can_scan, can_mine)
		_set_recall_buttons(can_recall_drone, can_recall_mining_ship)


func _apply_automation_status(info: Dictionary) -> void:
	var drone_count: int = int(info.get("orbiting_drone_count", 0))
	var mining_ship_count: int = int(info.get("orbiting_mining_ship_count", 0))
	var mining_bonus: float = float(info.get("mining_bonus", 0.0))

	drone_orbit_label.visible = drone_count > 0
	mine_orbit_label.visible = mining_ship_count > 0
	mining_bonus_label.visible = drone_count > 0

	drone_orbit_label.text = "Drones im Orbit: %d" % drone_count
	mine_orbit_label.text = "Mining Ships im Orbit: %d" % mining_ship_count
	mining_bonus_label.text = "Mining Bonus: +%d%%" % int(round(mining_bonus * 100.0))


func _apply_resources(info: Dictionary) -> void:
	_clear_resource_rows()

	var visible_resources: Array = []
	var visible_resources_variant: Variant = info.get("resources_visible", [])

	if visible_resources_variant is Array:
		visible_resources = visible_resources_variant

	for entry in visible_resources:
		var row: ResourceInfoRow = RESOURCE_INFO_ROW_SCENE.instantiate() as ResourceInfoRow
		resource_list.add_child(row)

		if entry is Dictionary:
			var entry_dict: Dictionary = entry as Dictionary
			var resource_name: String = str(entry_dict.get("name", "Unknown"))
			var percent_text: String = _build_percent_text(entry_dict)
			row.set_row_data(_format_title(resource_name), percent_text)
		else:
			row.set_row_data(_format_title(str(entry)), "--")

	var hidden_count: int = int(info.get("resources_hidden_count", 0))

	if hidden_count > 0:
		hidden_resources_label.text = "Weitere: ?"
		hidden_resources_label.visible = true
	else:
		hidden_resources_label.visible = false


func _apply_lore(info: Dictionary) -> void:
	var lore_text: String = str(info.get("lore_text", "")).strip_edges()

	if lore_text.is_empty():
		lore_text = "Keine Beschreibung verfügbar."

	lore_text_label.text = lore_text


func _set_action_buttons(can_scan: bool, can_mine: bool) -> void:
	scan_with_drone_button.visible = can_scan
	scan_with_drone_button.disabled = not can_scan

	send_mining_ship_button.visible = can_mine
	send_mining_ship_button.disabled = not can_mine


func _set_recall_buttons(can_recall_drone: bool, can_recall_mining_ship: bool) -> void:
	recall_drone_button.visible = can_recall_drone
	recall_drone_button.disabled = not can_recall_drone

	recall_mining_ship_button.visible = can_recall_mining_ship
	recall_mining_ship_button.disabled = not can_recall_mining_ship


func _clear_resource_rows() -> void:
	for child in resource_list.get_children():
		child.queue_free()


func _build_percent_text(resource_entry: Dictionary) -> String:
	if resource_entry.has("percent"):
		return "%d%%" % int(resource_entry.get("percent", 0))

	if resource_entry.has("abundance_percent"):
		return "%d%%" % int(resource_entry.get("abundance_percent", 0))

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
