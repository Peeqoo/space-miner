class_name SystemBody
extends Node2D

signal selected(body: SystemBody)

@onready var orbit_pivot: Node2D = $OrbitPivot
@onready var body_visual: Sprite2D = $OrbitPivot/BodyVisual
@onready var selection_ring: Node2D = $OrbitPivot/SelectionRing
@onready var click_area: Area2D = $OrbitPivot/ClickArea
@onready var click_collision: CollisionShape2D = $OrbitPivot/ClickArea/CollisionShape2D

var definition: SystemBodyDefinition = null

var body_id: String = ""
var display_name: String = "Unknown"
var body_type: String = "planet"

var orbit_radius: float = 300.0
var orbit_speed: float = 0.2
var orbit_start_angle_degrees: float = 0.0

var body_scale: float = 1.0
var body_color: Color = Color.WHITE
var selection_ring_radius: float = 28.0

var orbit_center: Node2D = null
var orbit_angle: float = 0.0
var is_selected: bool = false

func _ready() -> void:
	if definition != null:
		_apply_definition()

	set_selected(false)
	_update_click_shape()

	if not click_area.input_event.is_connected(_on_click_area_input_event):
		click_area.input_event.connect(_on_click_area_input_event)

func _process(delta: float) -> void:
	if orbit_center == null:
		return

	orbit_angle += orbit_speed * delta
	global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius

func set_definition(def: SystemBodyDefinition) -> void:
	definition = def

	if is_inside_tree():
		_apply_definition()

func _apply_definition() -> void:
	if definition == null:
		return

	body_id = definition.id
	display_name = definition.display_name
	body_type = definition.body_type

	orbit_radius = definition.orbit_radius
	orbit_speed = definition.orbit_speed
	orbit_start_angle_degrees = definition.orbit_start_angle_degrees

	body_scale = definition.body_scale
	body_color = definition.body_color

	orbit_angle = deg_to_rad(orbit_start_angle_degrees)

	scale = Vector2.ONE * body_scale
	body_visual.modulate = body_color
	body_visual.texture = definition.texture

func set_orbit_center(node: Node2D) -> void:
	orbit_center = node

func refresh_orbit_position() -> void:
	if orbit_center == null:
		return

	global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius

func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value

func get_info() -> Dictionary:
	return {
		"id": body_id,
		"display_name": display_name,
		"body_type": body_type,
		"orbit_radius": orbit_radius,
		"orbit_speed": orbit_speed,
		"selected": is_selected
	}

func _update_click_shape() -> void:
	var shape := CircleShape2D.new()
	shape.radius = max(selection_ring_radius, 12.0)
	click_collision.shape = shape

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		selected.emit(self)
