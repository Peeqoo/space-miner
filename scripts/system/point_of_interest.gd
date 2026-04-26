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

var orbit_center: Node2D = null
var orbit_angle: float = 0.0
var is_selected: bool = false


func _ready() -> void:
	if definition != null:
		_apply_definition()

	set_selected(false)
	_update_click_shape()

	if selection_ring != null and selection_ring.has_method("set"):
		selection_ring.set("radius", selection_ring_radius)

	click_area.input_pickable = true
	if not click_area.input_event.is_connected(_on_click_area_input_event):
		click_area.input_event.connect(_on_click_area_input_event)


func _process(delta: float) -> void:
	if orbit_center == null:
		return

	orbit_angle += orbit_speed * delta
	global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius


func set_definition(def: PointOfInterestDefinition) -> void:
	definition = def
	if is_inside_tree():
		_apply_definition()


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
	orbit_angle = deg_to_rad(orbit_start_angle_degrees)

	poi_visual.modulate = poi_color
	poi_visual.texture = definition.texture if definition.texture != null else _build_fallback_texture()
	poi_visual.scale = Vector2.ONE * 0.35


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
		"id": poi_id,
		"display_name": display_name,
		"poi_type": poi_type,
		"orbit_radius": orbit_radius,
		"orbit_speed": orbit_speed,
		"selected": is_selected,
	}


func build_scan_info(scan_state: String, scanner_tier: String) -> Dictionary:
	var visible_name: String = "Unknown"
	var visible_type: String = "unknown"
	var visible_resources: Array[String] = []

	if scan_state != GameSession.SCAN_UNKNOWN:
		if definition.scan_basic_reveal_name:
			visible_name = display_name
		if definition.scan_basic_reveal_type:
			visible_type = poi_type

		visible_resources.append_array(_filter_resources_for_scanner(scanner_tier, definition.scan_basic_resources))
		visible_resources.append_array(_filter_resources_for_scanner(scanner_tier, definition.scan_deep_resources))
		visible_resources.append_array(_filter_resources_for_scanner(scanner_tier, definition.scan_special_resources))

	var hidden_slots: int = _count_hidden_resource_slots(scanner_tier)

	return {
		"id": poi_id,
		"display_name": visible_name,
		"poi_type": visible_type,
		"scan_state": scan_state,
		"resources_visible": visible_resources,
		"resources_hidden_count": hidden_slots,
		"is_scanned": scan_state != GameSession.SCAN_UNKNOWN,
	}


func get_orbit_tangent_direction() -> Vector2:
	if orbit_center == null:
		return Vector2.RIGHT

	var radial_direction: Vector2 = global_position - orbit_center.global_position
	if radial_direction == Vector2.ZERO:
		return Vector2.RIGHT

	radial_direction = radial_direction.normalized()
	var tangent_direction: Vector2 = Vector2(-radial_direction.y, radial_direction.x)
	if orbit_speed < 0.0:
		tangent_direction = -tangent_direction
	return tangent_direction.normalized()


func get_orbit_velocity_vector() -> Vector2:
	if orbit_center == null:
		return Vector2.ZERO
	return get_orbit_tangent_direction() * absf(orbit_speed) * orbit_radius


func get_interaction_orbit_config(action_name: String, desired_range: float, _reference_position: Vector2 = Vector2.ZERO) -> Dictionary:
	var orbit_radius_local: float = _get_interaction_radius(action_name, desired_range)
	var orbit_direction: float = 1.0 if orbit_speed >= 0.0 else -1.0
	var angular_speed: float = _get_local_orbit_angular_speed(action_name)
	return {
		"radius": orbit_radius_local,
		"direction": orbit_direction,
		"angular_speed": angular_speed,
	}


func _get_interaction_radius(action_name: String, desired_range: float) -> float:
	var base_radius: float = maxf(selection_ring_radius + 12.0, desired_range * 0.16)
	match action_name:
		"scan":
			return selection_ring_radius + 12.0
		"mining":
			return selection_ring_radius + 16.0
		"approach":
			return selection_ring_radius + 14.0
		_:
			return base_radius


func _get_local_orbit_angular_speed(action_name: String) -> float:
	match action_name:
		"scan":
			return 0.66
		"mining":
			return 0.82
		"approach":
			return 0.70
		_:
			return 0.70


func _filter_resources_for_scanner(scanner_tier: String, resources: PackedStringArray) -> Array[String]:
	var result: Array[String] = []

	for resource_name in resources:
		match scanner_tier:
			GameSession.SCANNER_BASIC:
				if resources == definition.scan_basic_resources:
					result.append(resource_name)
			GameSession.SCANNER_DEEP:
				if resources == definition.scan_basic_resources or resources == definition.scan_deep_resources:
					result.append(resource_name)
			GameSession.SCANNER_SPECIAL:
				result.append(resource_name)

	return result


func _count_hidden_resource_slots(scanner_tier: String) -> int:
	var hidden_count: int = 0

	match scanner_tier:
		GameSession.SCANNER_BASIC:
			hidden_count += definition.scan_deep_resources.size()
			hidden_count += definition.scan_special_resources.size()
			hidden_count += definition.scan_hidden_slots_after_special
		GameSession.SCANNER_DEEP:
			hidden_count += definition.scan_special_resources.size()
			hidden_count += definition.scan_hidden_slots_after_special
		GameSession.SCANNER_SPECIAL:
			hidden_count += definition.scan_hidden_slots_after_special

	return hidden_count


func _update_click_shape() -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = max(selection_ring_radius, 12.0)
	click_collision.shape = shape


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		selected.emit(self)


func _build_fallback_texture() -> Texture2D:
	var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(32):
		for x in range(32):
			var dist: float = Vector2(x - 15.5, y - 15.5).length()
			if dist <= 11.5:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
			elif dist <= 14.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.35))

	return ImageTexture.create_from_image(image)
