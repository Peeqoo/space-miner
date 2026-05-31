## Handles selecting system bodies and points of interest.
## Emits selection_changed so UI updates immediately.
class_name SystemSelectionController
extends Node

signal selection_changed(selected_node: Node)

## Emitted when the player double-clicks the already selected object to resume camera follow.
signal focus_selected_requested(target: Node2D)

var system_definition: SystemDefinition
var spawner: SystemSpawner

var selected_node: Node = null


func setup(
	p_system_definition: SystemDefinition,
	p_spawner: SystemSpawner
) -> void:
	system_definition = p_system_definition
	spawner = p_spawner


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


func register_signal_marker(marker: SignalMarker) -> void:
	if marker == null:
		return

	if not marker.selected.is_connected(_on_signal_marker_selected):
		marker.selected.connect(_on_signal_marker_selected)

	if not marker.refocus_camera_requested.is_connected(_on_signal_marker_refocus_requested):
		marker.refocus_camera_requested.connect(_on_signal_marker_refocus_requested)


func get_selected_node() -> Node:
	return selected_node


func notify_focus_selected_requested(target: Node2D) -> void:
	if target == null:
		return

	if get_selected_node() != target:
		return

	focus_selected_requested.emit(target)


func select_world_node(node: Node) -> void:
	if node == null:
		return
	if node is SystemBody:
		_on_body_selected(node as SystemBody)
	elif node is PointOfInterest:
		_on_poi_selected(node as PointOfInterest)
	elif node is SignalMarker:
		_on_signal_marker_selected(node as SignalMarker)


func clear_selection(should_emit: bool = true) -> void:
	if selected_node != null:
		if selected_node is SignalMarker:
			(selected_node as SignalMarker).set_selected(false)
		elif selected_node.has_method("set_selected"):
			selected_node.set_selected(false)

	selected_node = null

	if should_emit:
		selection_changed.emit(null)


func handle_empty_space_click(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clear_selection(true)


func _on_body_selected(body: SystemBody) -> void:
	if body != null and selected_node == body:
		return

	clear_selection(false)

	selected_node = body
	body.set_selected(true)

	_play_object_selected_sfx()
	selection_changed.emit(body)


func _on_poi_selected(poi: PointOfInterest) -> void:
	if poi != null and selected_node == poi:
		return

	clear_selection(false)

	selected_node = poi
	poi.set_selected(true)

	_play_object_selected_sfx()
	selection_changed.emit(poi)


func _on_signal_marker_selected(marker: SignalMarker) -> void:
	if marker != null and selected_node == marker:
		return

	clear_selection(false)

	selected_node = marker
	marker.set_selected(true)

	_play_object_selected_sfx()
	selection_changed.emit(marker)


func _on_signal_marker_refocus_requested(node: Node2D) -> void:
	notify_focus_selected_requested(node)


func _play_object_selected_sfx() -> void:
	AudioManager.play_sfx_optional(&"object_selected")
