class_name PointOfInterest
extends Node2D

signal selected(poi: PointOfInterest)

@onready var poi_visual: Sprite2D = $OrbitPivot/POIVisual
@onready var selection_ring: Node2D = $OrbitPivot/SelectionRing
@onready var click_area: Area2D = $OrbitPivot/ClickArea
@onready var click_collision: CollisionShape2D = $OrbitPivot/ClickArea/CollisionShape2D

var definition: PointOfInterestDefinition = null

var poi_id: String = ""
var display_name: String = "Unknown POI"
var poi_type: String = "asteroid_field"

var orbit_radius: float = 500.0
var orbit_speed: float = 0.12
var orbit_start_angle_degrees: float = 0.0
var poi_color: Color = Color(0.8, 0.8, 0.8)
var selection_ring_radius: float = 28.0

var orbiting := OrbitingObjectComponent.new()
var selectable := SelectableObjectComponent.new()


var orbit_center: Node2D:
	get:
		return orbiting.orbit_center

var orbit_angle: float:
	get:
		return orbiting.orbit_angle

var is_selected: bool:
	get:
		return selectable.is_selected


func _ready() -> void:
	if definition != null:
		_apply_definition()

	set_selected(false)

	selectable.set_selection_ring_radius(selection_ring, selection_ring_radius)
	selectable.setup_click_area(
		click_area,
		click_collision,
		_on_click_area_input_event
	)


func _process(delta: float) -> void:
	orbiting.process_orbit(self, delta)


func set_definition(def: PointOfInterestDefinition) -> void:
	definition = def

	if is_inside_tree():
		_apply_definition()


func set_orbit_center(node: Node2D) -> void:
	orbiting.set_orbit_center(node)


func refresh_orbit_position() -> void:
	orbiting.refresh_position(self)


func set_selected(value: bool) -> void:
	selectable.set_selected(selection_ring, value)


func get_info() -> Dictionary:
	return {
		"id": poi_id,
		"display_name": display_name,
		"poi_type": poi_type,
		"orbit_radius": orbit_radius,
		"orbit_speed": orbit_speed,
		"selected": is_selected,
	}


func build_scan_info(scan_state: String, scanner_tier: String) -> Dictionary:
	return ScanInfoBuilder.build_scan_info(
		definition,
		poi_id,
		display_name,
		"poi_type",
		poi_type,
		scan_state,
		scanner_tier
	)


func _apply_definition() -> void:
	if definition == null:
		return

	poi_id = definition.id
	display_name = definition.display_name
	poi_type = definition.poi_type

	orbit_radius = definition.orbit_radius
	orbit_speed = definition.orbit_speed
	orbit_start_angle_degrees = definition.orbit_start_angle_degrees
	poi_color = definition.poi_color

	orbiting.setup(
		orbit_radius,
		orbit_speed,
		orbit_start_angle_degrees
	)

	poi_visual.modulate = poi_color
	poi_visual.texture = definition.texture if definition.texture != null else _build_fallback_texture()
	poi_visual.scale = Vector2.ONE * 0.35


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		selected.emit(self)


func _build_fallback_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(32):
		for x in range(32):
			var dist := Vector2(x - 15.5, y - 15.5).length()

			if dist <= 11.5:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
			elif dist <= 14.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.35))

	return ImageTexture.create_from_image(image)
