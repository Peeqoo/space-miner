class_name SystemShipUIController
extends Node

var start_button: Button
var dock_button: Button


func setup(
	p_start_button: Button,
	p_dock_button: Button
) -> void:
	start_button = p_start_button
	dock_button = p_dock_button


func update_ship_ui() -> void:
	var ship_state := get_parent().get_node_or_null("SystemShipStateController") as SystemShipStateController

	if ship_state == null:
		return

	start_button.visible = ship_state.is_docked
	dock_button.visible = not ship_state.is_docked
