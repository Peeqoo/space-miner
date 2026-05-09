## Runtime node for planets and other system bodies.
## Delegates orbit, selection and scan info behavior to components.
class_name SystemBody
extends Node2D

signal selected(body: SystemBody)

@onready var body_visual: Sprite2D = $OrbitPivot/BodyVisual
@onready var back_orbit_units: Node2D = $OrbitPivot/BackOrbitUnits
@onready var front_orbit_units: Node2D = $OrbitPivot/FrontOrbitUnits
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


# --------------------------------------------------
# Lifecycle
# --------------------------------------------------

func _ready() -> void:
	if definition != null:
		_apply_definition()

	_apply_presentation()
	set_selected(false)

	selectable.setup_click_area(
		click_area,
		click_collision,
		_on_click_area_input_event
	)


func _process(delta: float) -> void:
	orbiting.process_orbit(self, delta)


# --------------------------------------------------
# Public API
# --------------------------------------------------

func set_definition(def: SystemBodyDefinition) -> void:
	definition = def

	if is_inside_tree():
		_apply_definition()
		_apply_presentation()


func set_presentation(new_presentation: Dictionary) -> void:
	presentation = new_presentation.duplicate(true)

	if is_inside_tree():
		_apply_presentation()


func set_orbit_center(node: Node2D) -> void:
	orbiting.set_orbit_center(node)


func refresh_orbit_position() -> void:
	orbiting.refresh_position(self)


func set_selected(value: bool) -> void:
	selectable.set_selected(selection_ring, value)


func get_info() -> Dictionary:
	return {
		"id": body_id,
		"display_name": display_name,
		"body_type": body_type,
		"orbit_radius": orbit_radius,
		"orbit_speed": orbit_speed,
		"visual_scale": visual_scale,
		"selected": is_selected,
	}


func build_scan_info(scan_state: String, scanner_tier: String) -> Dictionary:
	return ScanInfoBuilder.build_scan_info(
		definition,
		body_id,
		display_name,
		"body_type",
		body_type,
		scan_state,
		scanner_tier
	)


func get_back_orbit_units() -> Node2D:
	return back_orbit_units


func get_front_orbit_units() -> Node2D:
	return front_orbit_units


# --------------------------------------------------
# Definition / Presentation
# --------------------------------------------------

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

	orbiting.setup(
		orbit_radius,
		orbit_speed,
		orbit_start_angle_degrees
	)

	body_visual.texture = definition.texture
	body_visual.modulate = body_color
	body_visual.scale = Vector2.ONE * visual_scale


func _apply_presentation() -> void:
	if presentation.is_empty():
		_update_selection_defaults()
		return

	orbit_radius = float(presentation.get("orbit_radius", orbit_radius))
	orbit_speed = float(presentation.get("orbit_speed", orbit_speed))
	visual_scale = maxf(float(presentation.get("visual_scale", visual_scale)), 0.01)
	selection_ring_radius = float(presentation.get("selection_ring_radius", selection_ring_radius))

	orbiting.orbit_radius = orbit_radius
	orbiting.orbit_speed = orbit_speed

	body_visual.scale = Vector2.ONE * visual_scale

	selectable.set_selection_ring_radius(selection_ring, selection_ring_radius)
	selectable.update_click_shape(click_collision)


func _update_selection_defaults() -> void:
	var texture_diameter := 0.0

	if body_visual.texture != null:
		var texture_width := body_visual.texture.get_width()
		var texture_height := body_visual.texture.get_height()
		texture_diameter = float(min(texture_width, texture_height))

	if texture_diameter > 0.0:
		selection_ring_radius = maxf(texture_diameter * visual_scale * 0.5 + 14.0, 18.0)
	else:
		selection_ring_radius = maxf(28.0 * visual_scale, 18.0)

	selectable.set_selection_ring_radius(selection_ring, selection_ring_radius)
	selectable.update_click_shape(click_collision)


# --------------------------------------------------
# Input
# --------------------------------------------------

func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		selected.emit(self)
