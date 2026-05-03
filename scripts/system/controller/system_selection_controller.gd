## Handles selecting system bodies and points of interest.
## Keeps object selection and navigation targeting out of SystemScene.
class_name SystemSelectionController
extends Node


# --------------------------------------------------
# Dependencies
# --------------------------------------------------

var system_definition: SystemDefinition
var player_ship: CharacterBody2D
var spawner: SystemSpawner
var ship_state: SystemShipStateController


# --------------------------------------------------
# State
# --------------------------------------------------

var selected_node: Node = null


# --------------------------------------------------
# Setup
# --------------------------------------------------

func setup(
	p_system_definition: SystemDefinition,
	p_player_ship: CharacterBody2D,
	p_spawner: SystemSpawner,
	p_ship_state: SystemShipStateController
) -> void:
	system_definition = p_system_definition
	player_ship = p_player_ship
	spawner = p_spawner
	ship_state = p_ship_state


# --------------------------------------------------
# Registration
# --------------------------------------------------

func register_body(body: SystemBody) -> void:
	if body == null:
		return

	if not body.selected.is_connected(_on_body_selected):
		body.selected.connect(_on_body_selected)


func register_poi(poi: PointOfInterest) -> void:
	if poi == null:
		return

	if not poi.selected.is_connected(_on_poi_selected):
		poi.selected.connect(_on_poi_selected)


# --------------------------------------------------
# Public API
# --------------------------------------------------

func get_selected_node() -> Node:
	return selected_node


func restore_last_selection(state: ShipRuntimeState) -> void:
	if state == null or state.last_selected_object_id.is_empty():
		return

	var candidate: Node = spawner.get_spawned_object(state.last_selected_object_id)

	if candidate == null:
		return

	if candidate is SystemBody:
		_on_body_selected(candidate)
	elif candidate is PointOfInterest:
		_on_poi_selected(candidate)


func clear_selection() -> void:
	if selected_node != null and selected_node.has_method("set_selected"):
		selected_node.set_selected(false)

	selected_node = null


# --------------------------------------------------
# Selection Callbacks
# --------------------------------------------------

func _on_body_selected(body: SystemBody) -> void:
	clear_selection()

	selected_node = body
	body.set_selected(true)

	if not ship_state.is_docked:
		_send_ship_to_target(body.global_position)


func _on_poi_selected(poi: PointOfInterest) -> void:
	clear_selection()

	selected_node = poi
	poi.set_selected(true)

	if not ship_state.is_docked:
		_send_ship_to_target(poi.global_position)


# --------------------------------------------------
# Navigation
# --------------------------------------------------

func _send_ship_to_target(target: Vector2) -> void:
	var nav := player_ship.get_node_or_null("ShipNavigationComponent") as ShipNavigationComponent

	if nav != null:
		nav.set_target(target)
