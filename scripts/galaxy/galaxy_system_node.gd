extends Node2D

@export var system_definition: SystemDefinition

@onready var area: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var selection_ring: CanvasItem = get_node_or_null("SelectionRing") as CanvasItem


func _ready() -> void:
	add_to_group("galaxy_system_node")

	area.input_pickable = true
	if not area.input_event.is_connected(_on_click):
		area.input_event.connect(_on_click)

	if collision_shape.shape == null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 24.0
		collision_shape.shape = circle

	set_selected(false)


func _on_click(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			get_viewport().set_input_as_handled()
			_select_system()


func _select_system() -> void:
	if system_definition == null:
		push_warning("SystemNode ohne system_definition.")
		return

	var galaxy_map: Node = get_tree().get_first_node_in_group("galaxy_map_root")
	if galaxy_map == null:
		push_error("Kein galaxy_map_root gefunden.")
		return

	if galaxy_map.has_method("select_system"):
		galaxy_map.call("select_system", system_definition)


func set_selected(value: bool) -> void:
	if selection_ring != null:
		selection_ring.visible = value
