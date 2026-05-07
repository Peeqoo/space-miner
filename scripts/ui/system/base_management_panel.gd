## Base management UI.
## Shows base resources and builds automated drones / mining ships.
extends PanelContainer

signal build_drone_requested
signal build_mining_ship_requested
signal build_colony_ship_requested

const DRONE_ORE_COST: int = 10
const MINING_SHIP_ORE_COST: int = 25
const COLONY_SHIP_ORE_COST: int = 200
const COLONY_SHIP_FUEL_COST: int = 100
const COLONY_SHIP_POPULATION_COST: int = 10

@onready var base_name_label: Label = $Margin/Root/BaseNameLabel
@onready var status_label: Label = $Margin/Root/StatusLabel

@onready var ore_label: Label = $Margin/Root/OreLabel
@onready var fuel_label: Label = $Margin/Root/FuelLabel
@onready var food_label: Label = $Margin/Root/FoodLabel
@onready var population_label: Label = $Margin/Root/PopulationLabel

@onready var build_drone_button: Button = $Margin/Root/BuildDroneButton
@onready var build_mining_ship_button: Button = $Margin/Root/BuildMiningShipButton
@onready var build_colony_ship_button: Button = $Margin/Root/BuildColonyShipButton

@onready var drone_count_label: Label = $Margin/Root/DroneCountLabel
@onready var mining_ship_count_label: Label = $Margin/Root/MiningShipCountLabel
@onready var status_text_label: Label = $Margin/Root/StatusTextLabel

var current_system_id: String = ""
var current_body_id: String = ""
var current_base_name: String = "Earth"
var is_docked: bool = false


# --------------------------------------------------
# Lifecycle
# --------------------------------------------------

func _ready() -> void:
	visible = false

	if not build_drone_button.pressed.is_connected(_on_build_drone_pressed):
		build_drone_button.pressed.connect(_on_build_drone_pressed)

	if not build_mining_ship_button.pressed.is_connected(_on_build_mining_ship_pressed):
		build_mining_ship_button.pressed.connect(_on_build_mining_ship_pressed)

	if not build_colony_ship_button.pressed.is_connected(_on_build_colony_ship_pressed):
		build_colony_ship_button.pressed.connect(_on_build_colony_ship_pressed)

	refresh_from_game_session()


# --------------------------------------------------
# Public API
# --------------------------------------------------

func show_for_base(system_id: String, body_id: String, base_name: String, docked: bool) -> void:
	current_system_id = system_id
	current_body_id = body_id
	current_base_name = base_name
	is_docked = docked

	visible = true
	refresh_from_game_session()


func hide_panel() -> void:
	visible = false


func refresh_from_game_session() -> void:
	var base_id := _get_current_base_id()

	var ore := _get_base_resource_amount(base_id, "ore")
	var fuel := _get_base_resource_amount(base_id, "fuel")
	var food := _get_base_resource_amount(base_id, "food")
	var population := _get_base_population(base_id)
	var drones := _get_base_drone_count(base_id)
	var mining_ships := _get_base_mining_ship_count(base_id)

	base_name_label.text = current_base_name
	status_label.text = "Status: Heimatbasis" if base_id == "earth" else "Status: Basis"

	ore_label.text = "Ore: %d" % ore
	fuel_label.text = "Fuel: %d" % fuel
	food_label.text = "Food: %d" % food
	population_label.text = "Population: %d" % population

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
	status_text_label.text = text


# --------------------------------------------------
# Button Callbacks
# --------------------------------------------------

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

	set_status_text("Colony Ship vorbereitet.")
	build_colony_ship_requested.emit()
	refresh_from_game_session()


# --------------------------------------------------
# GameSession Access
# --------------------------------------------------

func _get_current_base_id() -> String:
	if current_body_id.is_empty():
		return "earth"

	return current_body_id


func _get_base_resource_amount(base_id: String, resource_id: String) -> int:
	if GameSession.has_method("get_base_resource_amount"):
		return int(GameSession.call("get_base_resource_amount", base_id, resource_id))

	if GameSession.has_method("get_earth_resource_amount"):
		return int(GameSession.call("get_earth_resource_amount", resource_id))

	return 0


func _add_base_resource(base_id: String, resource_id: String, amount: int) -> void:
	if GameSession.has_method("add_base_resource"):
		GameSession.call("add_base_resource", base_id, resource_id, amount)
		return

	if GameSession.has_method("add_earth_resource"):
		GameSession.call("add_earth_resource", resource_id, amount)


func _spend_base_resource(base_id: String, resource_id: String, amount: int) -> bool:
	if GameSession.has_method("spend_base_resource"):
		return bool(GameSession.call("spend_base_resource", base_id, resource_id, amount))

	if GameSession.has_method("spend_earth_resource"):
		return bool(GameSession.call("spend_earth_resource", resource_id, amount))

	return false


func _get_base_population(base_id: String) -> int:
	if GameSession.has_method("get_base_population"):
		return int(GameSession.call("get_base_population", base_id))

	if GameSession.has_method("get_earth_population"):
		return int(GameSession.call("get_earth_population"))

	return 0


func _get_base_drone_count(base_id: String) -> int:
	if GameSession.has_method("get_base_drone_count"):
		return int(GameSession.call("get_base_drone_count", base_id))

	if GameSession.has_method("get_drone_count"):
		return int(GameSession.call("get_drone_count"))

	return 0


func _get_base_mining_ship_count(base_id: String) -> int:
	if GameSession.has_method("get_base_mining_ship_count"):
		return int(GameSession.call("get_base_mining_ship_count", base_id))

	if GameSession.has_method("get_mining_ship_count"):
		return int(GameSession.call("get_mining_ship_count"))

	return 0


func _build_base_drone(base_id: String) -> bool:
	if GameSession.has_method("build_base_drone"):
		return bool(GameSession.call("build_base_drone", base_id))

	if GameSession.has_method("build_drone"):
		return bool(GameSession.call("build_drone"))

	return false


func _build_base_mining_ship(base_id: String) -> bool:
	if GameSession.has_method("build_base_mining_ship"):
		return bool(GameSession.call("build_base_mining_ship", base_id))

	if GameSession.has_method("build_mining_ship"):
		return bool(GameSession.call("build_mining_ship"))

	return false
