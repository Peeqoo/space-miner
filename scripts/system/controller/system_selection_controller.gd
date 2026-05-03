## Handles selecting system bodies, points of interest and the player ship.
## Emits selection_changed so UI updates immediately.
class_name SystemSelectionController
extends Node

signal selection_changed(selected_node: Node)

var system_definition: SystemDefinition
var player_ship: CharacterBody2D
var spawner: SystemSpawner
var ship_state: SystemShipStateController

var selected_node: Node = null


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

	_register_ship()


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


func clear_selection(emit_signal: bool = true) -> void:
	if selected_node != null and selected_node.has_method("set_selected"):
		selected_node.set_selected(false)

	selected_node = null

	if emit_signal:
		selection_changed.emit(null)


func handle_empty_space_click(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clear_selection(true)


func _register_ship() -> void:
	if player_ship == null:
		return

	if not player_ship.has_signal("selected"):
		return

	if not player_ship.selected.is_connected(_on_ship_selected):
		player_ship.selected.connect(_on_ship_selected)


func _on_ship_selected(ship: CharacterBody2D) -> void:
	if selected_node == ship:
		clear_selection(true)
		return

	clear_selection(false)

	selected_node = ship
	selection_changed.emit(ship)


func _on_body_selected(body: SystemBody) -> void:
	clear_selection(false)

	selected_node = body
	body.set_selected(true)

	if not ship_state.is_docked:
		_send_ship_to_target(body.global_position)

	selection_changed.emit(body)


func _on_poi_selected(poi: PointOfInterest) -> void:
	clear_selection(false)

	selected_node = poi
	poi.set_selected(true)

	if not ship_state.is_docked:
		_send_ship_to_target(poi.global_position)

	selection_changed.emit(poi)


func _send_ship_to_target(target: Vector2) -> void:
	var nav := player_ship.get_node_or_null("ShipNavigationComponent") as ShipNavigationComponent

	if nav != null:
		nav.set_target(target)
