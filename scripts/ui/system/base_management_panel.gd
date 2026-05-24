## BaseManagementPanel — shows base hub info and opens sub-panels.
## Production and upgrade logic is now in ProductionPanel / UpgradePanel.
extends PanelContainer

signal open_production_requested
signal open_upgrades_requested
signal open_storage_requested
signal close_requested

@onready var base_name_label: Label = $Margin/Root/MainRow/MetaColumn/BaseNameLabel
@onready var status_label: Label = $Margin/Root/MainRow/MetaColumn/StatusLabel
@onready var population_label: Label = $Margin/Root/MainRow/MetaColumn/PopulationLabel

@onready var close_base_panel_button: Button = $Margin/Root/HeaderRow/CloseBasePanelButton
@onready var open_production_button: Button = $Margin/Root/ManagementButtonSection/OpenProductionButton
@onready var open_upgrade_button: Button = $Margin/Root/ManagementButtonSection/OpenUpgradeButton
@onready var open_storage_button: Button = $Margin/Root/ManagementButtonSection/OpenStorageButton

var current_system_id: String = ""
var current_body_id: String = ""
var current_base_name: String = "Earth"
var is_docked: bool = false

var _hold_open_across_selections: bool = false
var _held_base_body_id: String = ""

var _economy_actions_enabled: bool = true


func _ready() -> void:
	visible = false

	_connect_button(close_base_panel_button, _on_close_base_panel_pressed)
	_connect_button(open_production_button, _on_open_production_pressed)
	_connect_button(open_upgrade_button, _on_open_upgrade_pressed)
	_connect_button(open_storage_button, _on_open_storage_pressed)

	if not GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.connect(_on_game_session_base_resources_changed)

	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_game_session_base_resources_changed)


func show_for_base(system_id: String, body_id: String, base_name: String, docked: bool) -> void:
	var bid := body_id.strip_edges()
	if bid.is_empty() or not GameSession.has_established_base(bid):
		hide_panel()
		return

	current_system_id = system_id
	current_body_id = bid
	current_base_name = base_name
	is_docked = docked

	_hold_open_across_selections = true
	_held_base_body_id = bid

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


func get_managed_base_id() -> String:
	return _get_current_base_id()


func set_economy_actions_enabled(enabled: bool) -> void:
	_economy_actions_enabled = enabled
	if open_production_button != null:
		open_production_button.disabled = not enabled
	if open_upgrade_button != null:
		open_upgrade_button.disabled = not enabled
	if open_storage_button != null:
		open_storage_button.disabled = not enabled


func refresh_while_hold_open() -> void:
	if not _hold_open_across_selections:
		return
	refresh_from_game_session()


func refresh_from_game_session() -> void:
	var base_id := _get_current_base_id()
	if base_id.is_empty() or not GameSession.has_established_base(base_id):
		hide_panel()
		return

	base_name_label.text = current_base_name
	status_label.text = "Homebasis" if base_id == BaseStore.BASE_EARTH else "Basis"

	var population := GameSession.get_base_population(base_id)
	population_label.text = "Population: %s" % NumberFormat.format_compact(population)


func _on_close_base_panel_pressed() -> void:
	hide_panel()
	close_requested.emit()


func _on_open_production_pressed() -> void:
	if not _economy_actions_enabled:
		return
	open_production_requested.emit()


func _on_open_upgrade_pressed() -> void:
	if not _economy_actions_enabled:
		return
	open_upgrades_requested.emit()


func _on_open_storage_pressed() -> void:
	if not _economy_actions_enabled:
		return
	open_storage_requested.emit()


func _connect_button(button: Button, callback: Callable) -> void:
	if button == null:
		return
	AudioManager.bind_ui_button_optional(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


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
