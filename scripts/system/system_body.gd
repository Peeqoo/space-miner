class_name SystemBody
extends Node2D


signal selected(body: SystemBody)


@onready var body_visual: Sprite2D = $OrbitPivot/BodyVisual
@onready var selection_ring: Node2D = $OrbitPivot/SelectionRing
@onready var click_area: Area2D = $OrbitPivot/ClickArea
@onready var click_collision: CollisionShape2D = $OrbitPivot/ClickArea/CollisionShape2D

var definition: SystemBodyDefinition = null
var presentation: Dictionary = {}

var body_id: String = ""
var display_name: String = "Unknown"
var body_type: String = "planet"

var orbit_radius: float = 300.0
var orbit_speed: float = 0.2
var orbit_start_angle_degrees: float = 0.0

var body_scale: float = 1.0
var visual_scale: float = 1.0
var body_color: Color = Color.WHITE
var selection_ring_radius: float = 28.0

var orbit_center: Node2D = null
var orbit_angle: float = 0.0
var is_selected: bool = false


func _ready() -> void:
	if definition != null:
		_apply_definition()

	_apply_presentation()
	set_selected(false)
	_update_click_shape()
	_update_selection_ring()

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
		_apply_presentation()


func set_presentation(new_presentation: Dictionary) -> void:
	presentation = new_presentation.duplicate(true)
	if is_inside_tree():
		_apply_presentation()


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
	visual_scale = body_scale
	body_color = definition.body_color
	orbit_angle = deg_to_rad(orbit_start_angle_degrees)

	body_visual.texture = definition.texture
	body_visual.modulate = body_color
	body_visual.scale = Vector2.ONE * visual_scale


func _apply_presentation() -> void:
	if presentation.is_empty():
		_update_selection_defaults()
		return

	orbit_radius = float(presentation.get("orbit_radius", orbit_radius))
	orbit_speed = float(presentation.get("orbit_speed", orbit_speed))
	visual_scale = max(float(presentation.get("visual_scale", visual_scale)), 0.01)
	selection_ring_radius = float(presentation.get("selection_ring_radius", selection_ring_radius))

	body_visual.scale = Vector2.ONE * visual_scale
	_update_click_shape()
	_update_selection_ring()


func _update_selection_defaults() -> void:
	var texture_diameter: float = 0.0

	if body_visual.texture != null:
		var texture_width: int = body_visual.texture.get_width()
		var texture_height: int = body_visual.texture.get_height()
		texture_diameter = float(min(texture_width, texture_height))

	if texture_diameter > 0.0:
		selection_ring_radius = max(texture_diameter * visual_scale * 0.5 + 14.0, 18.0)
	else:
		selection_ring_radius = max(28.0 * visual_scale, 18.0)

	_update_click_shape()
	_update_selection_ring()


func _update_selection_ring() -> void:
	if selection_ring != null:
		selection_ring.set("radius", selection_ring_radius)


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
	var info: Dictionary = {}
	info["id"] = body_id
	info["display_name"] = display_name
	info["body_type"] = body_type
	info["orbit_radius"] = orbit_radius
	info["orbit_speed"] = orbit_speed
	info["visual_scale"] = visual_scale
	info["selected"] = is_selected
	return info


func _update_click_shape() -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = max(selection_ring_radius, 12.0)
	click_collision.shape = shape


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(self)
