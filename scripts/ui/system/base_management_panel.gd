## BaseManagementPanel — shows base hub info and opens sub-panels.
## Production and upgrade logic is now in ProductionPanel / UpgradePanel.
extends PanelContainer

signal open_production_requested
signal open_upgrades_requested

@onready var base_name_label: Label = $Margin/Root/MainRow/MetaColumn/BaseNameLabel
@onready var status_label: Label = $Margin/Root/MainRow/MetaColumn/StatusLabel
@onready var population_label: Label = $Margin/Root/MainRow/MetaColumn/PopulationLabel
@onready var status_text_label: Label = $Margin/Root/StatusTextLabel

@onready var close_base_panel_button: Button = $Margin/Root/HeaderRow/CloseBasePanelButton
@onready var open_production_button: Button = $Margin/Root/ManagementButtonSection/OpenProductionButton
@onready var open_upgrade_button: Button = $Margin/Root/ManagementButtonSection/OpenUpgradeButton

var current_system_id: String = ""
var current_body_id: String = ""
var current_base_name: String = "Earth"
var is_docked: bool = false

var _hold_open_across_selections: bool = false
var _held_base_body_id: String = ""


func _ready() -> void:
	visible = false

	_connect_button(close_base_panel_button, _on_close_base_panel_pressed)
	_connect_button(open_production_button, _on_open_production_pressed)
	_connect_button(open_upgrade_button, _on_open_upgrade_pressed)

	if not GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.connect(_on_game_session_base_resources_changed)

	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_game_session_base_resources_changed)


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


func is_hold_open_across_selection() -> bool:
	return _hold_open_across_selections


func get_hold_base_body_id() -> String:
	return _held_base_body_id


func refresh_while_hold_open() -> void:
	if not _hold_open_across_selections:
		return
	refresh_from_game_session()


func refresh_from_game_session() -> void:
	var base_id := _get_current_base_id()

	base_name_label.text = current_base_name
	status_label.text = "Homebasis" if base_id == BaseStore.BASE_EARTH else "Basis"

	var population := GameSession.get_base_population(base_id)
	population_label.text = "Population: %d" % population

	call_deferred("_fit_height_to_content")


func set_status_text(text: String) -> void:
	if status_text_label != null:
		status_text_label.text = text


func _on_close_base_panel_pressed() -> void:
	hide_panel()


func _on_open_production_pressed() -> void:
	open_production_requested.emit()


func _on_open_upgrade_pressed() -> void:
	open_upgrades_requested.emit()


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _fit_height_to_content() -> void:
	var fixed_width := custom_minimum_size.x
	if fixed_width <= 0.0:
		fixed_width = size.x
	var saved_pos := position
	var target_size := get_combined_minimum_size()
	size = Vector2(fixed_width, target_size.y)
	position = saved_pos


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
