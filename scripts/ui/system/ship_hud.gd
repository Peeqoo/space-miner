extends PanelContainer

signal galaxy_map_requested

const CARGO_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/cargo_row.tscn")

@export var auto_refresh_interval: float = 0.25

@onready var header_label: Label = $Margin/Root/HeaderLabel
@onready var ship_sprite: TextureRect = $Margin/Root/ShipRow/ShipPreviewPanel/ShipPreviewCenter/ShipSprite
@onready var current_system_label: Label = $Margin/Root/ShipRow/ShipMetaColumn/CurrentSystemLabel
@onready var cargo_capacity_label: Label = $Margin/Root/ShipRow/ShipMetaColumn/CargoCapacityLabel
@onready var scanner_tier_label: Label = $Margin/Root/ShipRow/ShipMetaColumn/ScannerTierLabel
@onready var status_label: Label = $Margin/Root/ShipRow/ShipMetaColumn/StatusLabel
@onready var cargo_title_label: Label = $Margin/Root/CargoTitleLabel
@onready var cargo_list: VBoxContainer = $Margin/Root/CargoPanel/CargoMargin/ScrollContainer/CargoList
@onready var empty_cargo_label: Label = $Margin/Root/EmptyCargoLabel
@onready var galaxy_map_button: Button = $Margin/Root/GalaxyMapButton

var _refresh_timer: float = 0.0


func _ready() -> void:
	header_label.text = "SCHIFF"
	cargo_title_label.text = "CARGOINHALT"

	if not galaxy_map_button.pressed.is_connected(_on_galaxy_map_button_pressed):
		galaxy_map_button.pressed.connect(_on_galaxy_map_button_pressed)

	refresh_from_game_session()


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return

	_refresh_timer = auto_refresh_interval
	refresh_from_game_session()


func refresh_from_game_session() -> void:
	_update_system_text()
	_update_cargo_summary()
	_update_scanner_tier()
	_update_status_text()
	_rebuild_cargo_list()


func _update_system_text() -> void:
	var system_name: String = "System: -"

	if GameSession.current_system_definition != null:
		system_name = "System: %s" % GameSession.current_system_definition.display_name
	elif not GameSession.current_system_id.is_empty():
		system_name = "System: %s" % GameSession.current_system_id.capitalize()

	current_system_label.text = system_name


func _update_cargo_summary() -> void:
	var used: int = GameSession.get_cargo_used()
	var capacity: int = GameSession.get_cargo_capacity()
	cargo_capacity_label.text = "Cargo: %d / %d" % [used, capacity]


func _update_scanner_tier() -> void:
	var scanner_tier: String = GameSession.get_active_scanner_tier()
	scanner_tier_label.text = "Scanner: %s" % _format_scanner_tier(scanner_tier)


func _update_status_text() -> void:
	if GameSession.current_system_id.is_empty():
		status_label.text = "Status: Kein System"
		return

	var ship_state: ShipRuntimeState = GameSession.get_ship_state(GameSession.current_system_id)
	if ship_state == null:
		status_label.text = "Status: Aktiv"
		return

	if ship_state.is_docked:
		status_label.text = "Status: Angedockt"
	else:
		status_label.text = "Status: Im Flug"


func _rebuild_cargo_list() -> void:
	for child in cargo_list.get_children():
		child.queue_free()

	var cargo_items: Dictionary = GameSession.get_cargo_items()
	if cargo_items.is_empty():
		empty_cargo_label.visible = true
		return

	empty_cargo_label.visible = false

	var resource_ids: Array[String] = []
	for key in cargo_items.keys():
		resource_ids.append(str(key))

	resource_ids.sort()

	for resource_id in resource_ids:
		var amount: int = int(cargo_items.get(resource_id, 0))
		if amount <= 0:
			continue

		var row: HBoxContainer = CARGO_ROW_SCENE.instantiate() as HBoxContainer
		cargo_list.add_child(row)

		if row.has_method("set_row_data"):
			row.call("set_row_data", _format_resource_name(resource_id), amount)


func _format_resource_name(resource_id: String) -> String:
	var cleaned: String = resource_id.strip_edges().replace("_", " ")
	if cleaned.is_empty():
		return "Unbekannt"

	var words: PackedStringArray = cleaned.split(" ", false)
	var formatted_words: PackedStringArray = []

	for word in words:
		if word.is_empty():
			continue
		formatted_words.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())

	return " ".join(formatted_words)


func _format_scanner_tier(scanner_tier: String) -> String:
	match scanner_tier:
		GameSession.SCANNER_BASIC:
			return "Basic"
		GameSession.SCANNER_DEEP:
			return "Deep"
		GameSession.SCANNER_SPECIAL:
			return "Special"
		_:
			return scanner_tier.capitalize()


func _on_galaxy_map_button_pressed() -> void:
	emit_signal("galaxy_map_requested")
