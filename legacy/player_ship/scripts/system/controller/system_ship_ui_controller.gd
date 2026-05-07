## Updates ship control buttons based on docking state.
## Keeps button visibility logic out of the system scene.
class_name SystemShipUIController
extends Node


# --------------------------------------------------
# Node References
# --------------------------------------------------

var start_button: Button
var dock_button: Button


# --------------------------------------------------
# Setup
# --------------------------------------------------

func setup(p_start_button: Button, p_dock_button: Button) -> void:
	start_button = p_start_button
	dock_button = p_dock_button


# --------------------------------------------------
# Public API
# --------------------------------------------------

func update_ship_ui() -> void:
	var ship_state := get_parent().get_node_or_null("SystemShipStateController") as SystemShipStateController

	if ship_state == null:
		return
