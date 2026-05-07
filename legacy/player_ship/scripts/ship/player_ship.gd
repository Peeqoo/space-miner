## Runtime node for the player ship.
## Emits selected when the ship itself is clicked.
extends CharacterBody2D

signal selected(ship: CharacterBody2D)

@export var visual_rotation_offset_degrees: float = 0.0
@export var interaction_click_radius: float = 26.0

@onready var visual_root: Node2D = $VisualRoot
@onready var camera_anchor: Marker2D = $CameraAnchor
@onready var navigation: ShipNavigationComponent = $ShipNavigationComponent
@onready var interaction_area: Area2D = $InteractionArea
@onready var interaction_collision: CollisionShape2D = $InteractionArea/CollisionShape2D


func _ready() -> void:
	visual_root.rotation_degrees = visual_rotation_offset_degrees
	_setup_interaction_area()


func _setup_interaction_area() -> void:
	if interaction_area == null or interaction_collision == null:
		return

	interaction_area.input_pickable = true

	if interaction_collision.shape == null:
		var shape := CircleShape2D.new()
		shape.radius = interaction_click_radius
		interaction_collision.shape = shape

	if not interaction_area.input_event.is_connected(_on_interaction_area_input_event):
		interaction_area.input_event.connect(_on_interaction_area_input_event)


func _on_interaction_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		selected.emit(self)
