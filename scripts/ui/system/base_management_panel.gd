## Base management UI.
## Shows base resources through ResourceList row-scenes and builds automated drones / mining ships.
extends PanelContainer

signal build_drone_requested
signal build_mining_ship_requested
signal build_colony_ship_requested

const STORAGE_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/storage_info_row.tscn")

const DRONE_ORE_COST: int = 10
const MINING_SHIP_ORE_COST: int = 25
const COLONY_SHIP_ORE_COST: int = 200
const COLONY_SHIP_FUEL_COST: int = 100
const COLONY_SHIP_POPULATION_COST: int = 10

const BASE_RESOURCE_ORDER: PackedStringArray = [
	"ore",
	"fuel",
	"food",
]

const BUTTON_INFO: Dictionary = {
	"BuildDroneButton": {
		"title": "Drone bauen",
		"desc": "Baut eine einfache Arbeitsdrohne für Basis- und Sammelaufgaben.",
		"cost": "Kosten: 10 Ore",
	},
	"BuildMiningShipButton": {
		"title": "Mining Ship bauen",
		"desc": "Baut ein Mining-Schiff für automatisierten Ressourcenabbau.",
		"cost": "Kosten: 25 Ore",
	},
	"BuildColonyShipButton": {
		"title": "Colony Ship bauen",
		"desc": "Bereitet ein Kolonieschiff für spätere Expansion vor.",
		"cost": "Kosten: 200 Ore, 100 Fuel, 10 Population",
	},
}

@onready var base_name_label: Label = $Margin/Root/HeaderSection/BaseNameLabel
@onready var status_label: Label = $Margin/Root/HeaderSection/StatusLabel
@onready var population_label: Label = $Margin/Root/HeaderSection/PopulationLabel

@onready var resource_list: VBoxContainer = $Margin/Root/StorageSection/ResourcePanel/ResourceMargin/ResourceScroll/ResourceList

@onready var build_drone_button: Button = $Margin/Root/ProductionSection/ProductionGrid/BuildDroneButton
@onready var build_mining_ship_button: Button = $Margin/Root/ProductionSection/ProductionGrid/BuildMiningShipButton
@onready var build_colony_ship_button: Button = $Margin/Root/ProductionSection/ProductionGrid/BuildColonyShipButton

@onready var drone_count_label: Label = $Margin/Root/FleetSection/FleetGrid/DroneCountLabel
@onready var mining_ship_count_label: Label = $Margin/Root/FleetSection/FleetGrid/MiningShipCountLabel

@onready var hover_info_panel: PanelContainer = $Margin/Root/HoverInfoPanel
@onready var hover_title_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverTitleLabel
@onready var hover_desc_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverDescLabel
@onready var hover_cost_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverCostLabel

@onready var status_text_label: Label = get_node_or_null("Margin/Root/StatusTextLabel") as Label

var current_system_id: String = ""
var current_body_id: String = ""
var current_base_name: String = "Earth"
var is_docked: bool = false


func _ready() -> void:
	visible = false
	hover_info_panel.visible = false

	_connect_button(build_drone_button, _on_build_drone_pressed)
	_connect_button(build_mining_ship_button, _on_build_mining_ship_pressed)
	_connect_button(build_colony_ship_button, _on_build_colony_ship_pressed)

	_register_hover_button(build_drone_button)
	_register_hover_button(build_mining_ship_button)
	_register_hover_button(build_colony_ship_button)

	refresh_from_game_session()


func show_for_base(system_id: String, body_id: String, base_name: String, docked: bool) -> void:
	current_system_id = system_id
	current_body_id = body_id
	current_base_name = base_name
	is_docked = docked

	visible = true
	refresh_from_game_session()


func hide_panel() -> void:
	visible = false
	hover_info_panel.visible = false


func refresh_from_game_session() -> void:
	var base_id := _get_current_base_id()

	var ore := _get_base_resource_amount(base_id, "ore")
	var fuel := _get_base_resource_amount(base_id, "fuel")
	var population := _get_base_population(base_id)
	var drones := _get_base_drone_count(base_id)
	var mining_ships := _get_base_mining_ship_count(base_id)

	base_name_label.text = current_base_name
	status_label.text = "Status: Heimatbasis" if base_id == BaseStore.BASE_EARTH else "Status: Basis"
	population_label.text = "Population: %d" % population

	_rebuild_resource_list(base_id)

	drone_count_label.text = "Drones: %d" % drones
	mining_ship_count_label.text = "Mining Ships: %d" % mining_ships

	build_drone_button.disabled = ore < DRONE_ORE_COST
	build_mining_ship_button.disabled = ore < MINING_SHIP_ORE_COST
	build_colony_ship_button.disabled = (
		ore < COLONY_SHIP_ORE_COST
		or fuel < COLONY_SHIP_FUEL_COST
		or population < COLONY_SHIP_POPULATION_COST
	)


func set_status_text(text: String) -> void:
	if status_text_label != null:
		status_text_label.text = text
	else:
		status_label.text = text


func _on_build_drone_pressed() -> void:
	var base_id := _get_current_base_id()

	if _build_base_drone(base_id):
		set_status_text("Drone gebaut.")
		build_drone_requested.emit()
	else:
		set_status_text("Nicht genug Ore für Drone.")

	refresh_from_game_session()


func _on_build_mining_ship_pressed() -> void:
	var base_id := _get_current_base_id()

	if _build_base_mining_ship(base_id):
		set_status_text("Mining Ship gebaut.")
		build_mining_ship_requested.emit()
	else:
		set_status_text("Nicht genug Ore für Mining Ship.")

	refresh_from_game_session()


func _on_build_colony_ship_pressed() -> void:
	var base_id := _get_current_base_id()

	var ore := _get_base_resource_amount(base_id, "ore")
	var fuel := _get_base_resource_amount(base_id, "fuel")
	var population := _get_base_population(base_id)

	if ore < COLONY_SHIP_ORE_COST:
		set_status_text("Nicht genug Ore für Colony Ship.")
		refresh_from_game_session()
		return

	if fuel < COLONY_SHIP_FUEL_COST:
		set_status_text("Nicht genug Fuel für Colony Ship.")
		refresh_from_game_session()
		return

	if population < COLONY_SHIP_POPULATION_COST:
		set_status_text("Nicht genug Population für Colony Ship.")
		refresh_from_game_session()
		return

	if not _spend_base_resource(base_id, "ore", COLONY_SHIP_ORE_COST):
		set_status_text("Colony Ship konnte nicht gebaut werden.")
		refresh_from_game_session()
		return

	if not _spend_base_resource(base_id, "fuel", COLONY_SHIP_FUEL_COST):
		_add_base_resource(base_id, "ore", COLONY_SHIP_ORE_COST)
		set_status_text("Colony Ship konnte nicht gebaut werden.")
		refresh_from_game_session()
		return

	# Population wird hier bewusst noch nicht abgezogen, solange GameSession dafür keinen sicheren Spend-Call hat.
	set_status_text("Colony Ship vorbereitet.")
	build_colony_ship_requested.emit()
	refresh_from_game_session()


func _rebuild_resource_list(base_id: String) -> void:
	_clear_resource_list()

	for resource_id in BASE_RESOURCE_ORDER:
		var amount := _get_base_resource_amount(base_id, resource_id)
		_add_storage_row(_format_title(resource_id), amount)


func _add_storage_row(resource_name: String, amount: int) -> void:
	var row := STORAGE_ROW_SCENE.instantiate()
	resource_list.add_child(row)

	if row.has_method("set_row_data"):
		row.call("set_row_data", resource_name, amount)


func _clear_resource_list() -> void:
	for child in resource_list.get_children():
		child.queue_free()


func _connect_button(button: Button, callback: Callable) -> void:
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _register_hover_button(button: Button) -> void:
	if not button.mouse_entered.is_connected(_on_action_button_mouse_entered.bind(button)):
		button.mouse_entered.connect(_on_action_button_mouse_entered.bind(button))

	if not button.mouse_exited.is_connected(_on_action_button_mouse_exited.bind(button)):
		button.mouse_exited.connect(_on_action_button_mouse_exited.bind(button))


func _on_action_button_mouse_entered(button: Button) -> void:
	var info: Dictionary = BUTTON_INFO.get(button.name, {})
	if info.is_empty():
		return

	hover_title_label.text = str(info.get("title", "Aktion"))
	hover_desc_label.text = str(info.get("desc", ""))
	hover_cost_label.text = _build_hover_cost_text(button)
	hover_info_panel.visible = true


func _on_action_button_mouse_exited(_button: Button) -> void:
	hover_info_panel.visible = false


func _build_hover_cost_text(button: Button) -> String:
	var base_id := _get_current_base_id()
	var ore := _get_base_resource_amount(base_id, "ore")
	var fuel := _get_base_resource_amount(base_id, "fuel")
	var population := _get_base_population(base_id)

	match button.name:
		"BuildDroneButton":
			return "Ore: %d / %d" % [ore, DRONE_ORE_COST]
		"BuildMiningShipButton":
			return "Ore: %d / %d" % [ore, MINING_SHIP_ORE_COST]
		"BuildColonyShipButton":
			return "Ore: %d / %d | Fuel: %d / %d | Pop: %d / %d" % [
				ore,
				COLONY_SHIP_ORE_COST,
				fuel,
				COLONY_SHIP_FUEL_COST,
				population,
				COLONY_SHIP_POPULATION_COST,
			]
		_:
			var info: Dictionary = BUTTON_INFO.get(button.name, {})
			return str(info.get("cost", ""))


func _get_current_base_id() -> String:
	if current_body_id.is_empty():
		return BaseStore.BASE_EARTH

	return current_body_id


func _get_base_resource_amount(base_id: String, resource_id: String) -> int:
	return GameSession.get_base_resource_amount(base_id, resource_id)


func _add_base_resource(base_id: String, resource_id: String, amount: int) -> void:
	GameSession.add_base_resource(base_id, resource_id, amount)


func _spend_base_resource(base_id: String, resource_id: String, amount: int) -> bool:
	return GameSession.spend_base_resource(base_id, resource_id, amount)


func _get_base_population(base_id: String) -> int:
	return GameSession.get_base_population(base_id)


func _get_base_drone_count(base_id: String) -> int:
	return GameSession.get_base_drone_count(base_id)


func _get_base_mining_ship_count(base_id: String) -> int:
	return GameSession.get_base_mining_ship_count(base_id)


func _build_base_drone(base_id: String) -> bool:
	return GameSession.build_base_drone(base_id)


func _build_base_mining_ship(base_id: String) -> bool:
	return GameSession.build_base_mining_ship(base_id)


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
