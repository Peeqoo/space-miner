## Base management UI.
## Shows base resources through ResourceList row-scenes and builds automated drones / mining ships.
extends PanelContainer

signal build_drone_requested
signal build_mining_ship_requested
signal build_colony_ship_requested

const STORAGE_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/storage_info_row.tscn")

const BUTTON_INFO: Dictionary = {
	"BuildDroneButton": {
		"title": "Drone bauen",
		"desc": "Baut eine einfache Arbeitsdrohne für Basis- und Sammelaufgaben.",
	},
	"BuildMiningShipButton": {
		"title": "Mining Ship bauen",
		"desc": "Baut ein Mining-Schiff für automatisierten Ressourcenabbau.",
	},
	"BuildColonyShipButton": {
		"title": "Colony Ship (Locked)",
		"desc": "Noch nicht spielbar — Fokus liegt auf Mining- und Drohnen-Loop.",
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

var current_system_id: String = ""
var current_body_id: String = ""
var current_base_name: String = "Earth"
var is_docked: bool = false

## When true: panel stays visible while selecting other objects (bases with stored body_id).
var _hold_open_across_selections: bool = false
## Last body_id passed to show_for_base — used for toggle-close on same-base click.
var _held_base_body_id: String = ""

@onready var close_base_panel_button: Button = $Margin/Root/HeaderSection/CloseBasePanelButton


func _ready() -> void:
	visible = false
	hover_info_panel.visible = false

	_connect_button(build_drone_button, _on_build_drone_pressed)
	_connect_button(build_mining_ship_button, _on_build_mining_ship_pressed)

	_register_hover_button(build_drone_button)
	_register_hover_button(build_mining_ship_button)
	_register_hover_button(build_colony_ship_button)

	_apply_colony_ship_button_locked_state()

	if not GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.connect(_on_game_session_base_resources_changed)

	_connect_button(close_base_panel_button, _on_close_base_panel_pressed)

	refresh_from_game_session()


func show_for_base(system_id: String, body_id: String, base_name: String, docked: bool) -> void:
	current_system_id = system_id
	current_body_id = body_id
	current_base_name = base_name
	is_docked = docked

	_hold_open_across_selections = true
	_held_base_body_id = body_id

	visible = true
	refresh_from_game_session()


func hide_panel() -> void:
	_hold_open_across_selections = false
	_held_base_body_id = ""
	visible = false
	hover_info_panel.visible = false


func is_hold_open_across_selection() -> bool:
	return _hold_open_across_selections


func get_hold_base_body_id() -> String:
	return _held_base_body_id


func refresh_while_hold_open() -> void:
	if not _hold_open_across_selections:
		return
	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_game_session_base_resources_changed)


func refresh_from_game_session() -> void:
	var base_id := _get_current_base_id()

	var population := _get_base_population(base_id)
	var drones := _get_base_drone_count(base_id)
	var mining_ships := _get_base_mining_ship_count(base_id)

	base_name_label.text = current_base_name
	status_label.text = "Status: Heimatbasis" if base_id == BaseStore.BASE_EARTH else "Status: Basis"
	population_label.text = "Population: %d" % population

	_rebuild_resource_list(base_id)

	drone_count_label.text = "Drones: %d" % drones
	mining_ship_count_label.text = "Mining Ships: %d" % mining_ships

	build_drone_button.disabled = not GameSession.can_build_base_drone(base_id)
	build_mining_ship_button.disabled = not GameSession.can_build_base_mining_ship(base_id)
	_apply_colony_ship_button_locked_state()


func set_status_text(text: String) -> void:
	status_label.text = text


func _on_close_base_panel_pressed() -> void:
	hide_panel()


func _on_build_drone_pressed() -> void:
	var base_id := _get_current_base_id()

	if GameSession.build_base_drone(base_id):
		set_status_text("Drone gebaut.")
		build_drone_requested.emit()
	else:
		set_status_text("Nicht genug Ressourcen für Drone.")

	refresh_from_game_session()


func _on_build_mining_ship_pressed() -> void:
	var base_id := _get_current_base_id()

	if GameSession.build_base_mining_ship(base_id):
		set_status_text("Mining Ship gebaut.")
		build_mining_ship_requested.emit()
	else:
		set_status_text("Nicht genug Ressourcen für Mining Ship.")

	refresh_from_game_session()


func _rebuild_resource_list(base_id: String) -> void:
	_clear_resource_list()

	var resources := GameSession.get_base_resources(base_id)

	for resource_id in resources:
		var amount := int(resources.get(resource_id, 0))
		_add_storage_row(_format_title(str(resource_id)), amount)


func _add_storage_row(resource_name: String, amount: int) -> void:
	var row := STORAGE_ROW_SCENE.instantiate()
	resource_list.add_child(row)

	var name_label := row.get_node_or_null("ResourceNameLabel") as Label
	var value_label := row.get_node_or_null("ResourceValueLabel") as Label

	if name_label != null:
		name_label.text = resource_name
	if value_label != null:
		value_label.text = str(amount)


func _clear_resource_list() -> void:
	for child in resource_list.get_children():
		child.queue_free()


func _connect_button(button: Button, callback: Callable) -> void:
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _apply_colony_ship_button_locked_state() -> void:
	const COLONY_BUTTON_TEXT: String = "Colony Ship"
	const COLONY_HINT: String = "Unlocks after stable Phase 4 loop."

	build_colony_ship_button.disabled = true
	build_colony_ship_button.text = COLONY_BUTTON_TEXT
	build_colony_ship_button.tooltip_text = COLONY_HINT


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
	var base_id_hover: String = _get_current_base_id()
	var resources_snapshot: Dictionary = GameSession.get_base_resources(base_id_hover)

	match button.name:
		"BuildDroneButton":
			return _format_hover_cost_lines(BaseStore.DRONE_COST, resources_snapshot)
		"BuildMiningShipButton":
			return _format_hover_cost_lines(BaseStore.MINING_SHIP_COST, resources_snapshot)
		"BuildColonyShipButton":
			return "Unlocks after stable Phase 4 loop."
		_:
			return ""


func _format_hover_cost_lines(cost: Dictionary, available_by_id: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()

	for resource_id: Variant in cost.keys():
		var need: int = int(cost.get(resource_id, 0))
		var have: int = int(available_by_id.get(resource_id, 0))
		var res_name: String = _format_title(str(resource_id))
		lines.append("%s: %d / %d" % [res_name, have, need])

	return "\n".join(lines)


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


func _get_current_base_id() -> String:
	if current_body_id.is_empty():
		return BaseStore.BASE_EARTH

	return current_body_id


func _on_game_session_base_resources_changed(changed_base_id: String) -> void:
	if not visible:
		return

	var base_id_panel: String = _get_current_base_id()

	if base_id_panel.is_empty():
		return

	if changed_base_id != base_id_panel:
		return

	refresh_from_game_session()


func _get_base_population(base_id: String) -> int:
	return GameSession.get_base_population(base_id)


func _get_base_drone_count(base_id: String) -> int:
	return GameSession.get_base_drone_count(base_id)


func _get_base_mining_ship_count(base_id: String) -> int:
	return GameSession.get_base_mining_ship_count(base_id)
