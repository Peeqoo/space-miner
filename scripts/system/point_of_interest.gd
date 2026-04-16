class_name PointOfInterest
extends Node2D

signal selected(poi: PointOfInterest)

@export var poi_id: String = ""
@export var display_name: String = "Unknown POI"
@export var poi_type: String = "asteroid_field"

@export_group("Orbit")
@export var orbit_radius: float = 500.0
@export var orbit_speed: float = 0.12
@export var orbit_start_angle_degrees: float = 0.0

@export_group("Visual")
@export var poi_color: Color = Color(0.8, 0.8, 0.8)
@export var selection_ring_radius: float = 28.0

@onready var poi_visual: Sprite2D = $OrbitPivot/POIVisual
@onready var selection_ring: Node2D = $OrbitPivot/SelectionRing
@onready var click_area: Area2D = $OrbitPivot/ClickArea
@onready var click_collision: CollisionShape2D = $OrbitPivot/ClickArea/CollisionShape2D

var orbit_center: Node2D = null
var orbit_angle: float = 0.0
var is_selected: bool = false

func _ready() -> void:
	apply_orbit_values()
	apply_definition_values()
	set_selected(false)

	_update_click_shape()

	if not click_area.input_event.is_connected(_on_click_area_input_event):
		click_area.input_event.connect(_on_click_area_input_event)

func apply_orbit_values() -> void:
	orbit_angle = deg_to_rad(orbit_start_angle_degrees)

func apply_definition_values() -> void:
	poi_visual.modulate = poi_color
	
func _process(delta: float) -> void:
	if orbit_center == null:
		return

	orbit_angle += orbit_speed * delta
	global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius

func set_orbit_center(node: Node2D) -> void:
	orbit_center = node

func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value

func get_info() -> Dictionary:
	return {
		"id": poi_id,
		"display_name": display_name,
		"poi_type": poi_type,
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
