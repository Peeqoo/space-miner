## Visual unit for automated drones and mining ships.
## Handles idle orbit, smooth travel, orbit approach and mission work.
class_name AutomationUnit
extends Node2D

signal arrived_at_target(unit: AutomationUnit)
signal returned_to_base(unit: AutomationUnit)

enum UnitType {
	DRONE,
	MINING_SHIP,
}

enum State {
	IDLE,
	ORBITING_BASE,
	TRAVEL_TO_TARGET,
	APPROACH_ORBIT,
	WORKING,
	RETURNING,
}

@export var unit_type: UnitType = UnitType.DRONE

@export var travel_speed: float = 220.0
@export var travel_curve_strength: float = 80.0
@export var travel_accel_curve_power: float = 1.8
@export var return_speed: float = 200.0
@export var work_duration: float = 2.0

@export var orbit_padding_min: float = 10.0
@export var orbit_padding_max: float = 32.0
@export var orbit_perspective_y_scale_min: float = 0.25
@export var orbit_perspective_y_scale_max: float = 0.45
@export var orbit_tilt_degrees_min: float = -25.0
@export var orbit_tilt_degrees_max: float = 25.0

@export var min_orbit_speed: float = 0.7
@export var max_orbit_speed: float = 1.6

@export var approach_distance: float = 12.0
@export var approach_speed: float = 90.0
@export var visual_rotation_offset_degrees: float = 0.0

@onready var visual_root: Node2D = $VisualRoot

var base_node: Node2D = null
var target_node: Node2D = null

var base_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var orbit_entry_position: Vector2 = Vector2.ZERO

var state: State = State.IDLE
var work_timer: float = 0.0

var orbit_radius_x: float = 40.0
var orbit_radius_y: float = 20.0
var orbit_speed: float = 1.0
var orbit_angle: float = 0.0
var orbit_direction: float = 1.0
var orbit_rotation: float = 0.0
var free_flight_parent: Node = null
var travel_start_position: Vector2 = Vector2.ZERO
var travel_control_position: Vector2 = Vector2.ZERO
var travel_end_position: Vector2 = Vector2.ZERO
var travel_progress: float = 0.0
var travel_duration: float = 0.1
# Stored at curve setup so the arc side stays consistent when the endpoint moves.
var travel_curve_side_sign: float = 1.0


func _ready() -> void:
	z_as_relative = false
	free_flight_parent = get_parent()
	_generate_random_orbit()


func _process(delta: float) -> void:
	match state:
		State.ORBITING_BASE:
			_process_base_orbit(delta)
		State.TRAVEL_TO_TARGET:
			_process_travel_to_target(delta)
		State.APPROACH_ORBIT:
			_process_approach_orbit(delta)
		State.WORKING:
			_process_working(delta)
		State.RETURNING:
			_process_returning(delta)


func start_orbiting_base(p_base_node: Node2D) -> void:
	if p_base_node == null:
		return

	base_node = p_base_node
	target_node = null
	base_position = base_node.global_position
	state = State.ORBITING_BASE
	work_timer = 0.0
	visible = true

	_generate_random_orbit()
	_process_base_orbit(0.0)


func start_mission_to_node(p_target_node: Node2D) -> void:
	if p_target_node == null:
		return

	target_node = p_target_node
	target_position = target_node.global_position

	if base_node != null and is_instance_valid(base_node):
		base_position = base_node.global_position

	# Generate orbit parameters sized for the TARGET planet, not Earth.
	_generate_orbit_for_node(target_node)
	_prepare_orbit_entry()
	_move_to_free_flight_parent()
	_setup_travel_curve(global_position, orbit_entry_position)
	state = State.TRAVEL_TO_TARGET
	work_timer = 0.0
	visible = true


func return_to_base_orbit() -> void:
	if base_node == null or not is_instance_valid(base_node):
		state = State.IDLE
		return

	_prepare_orbit_entry_for_node(base_node)
	_move_to_free_flight_parent()
	state = State.RETURNING


func recall_to_base(p_home_base_node: Node2D) -> void:
	if p_home_base_node == null:
		return

	target_node = null
	base_node = p_home_base_node
	base_position = p_home_base_node.global_position
	_move_to_free_flight_parent()
	state = State.RETURNING


func transfer_orbit_to_base(p_new_base_node: Node2D) -> void:
	if p_new_base_node == null:
		return

	base_node = p_new_base_node
	target_node = null

	_adopt_current_position_as_orbit()
	state = State.ORBITING_BASE
	work_timer = 0.0


func is_available() -> bool:
	return state == State.ORBITING_BASE


func is_busy() -> bool:
	return (
		state == State.TRAVEL_TO_TARGET
		or state == State.APPROACH_ORBIT
		or state == State.WORKING
		or state == State.RETURNING
	)


func _process_base_orbit(delta: float) -> void:
	if base_node == null or not is_instance_valid(base_node):
		state = State.IDLE
		return

	base_position = base_node.global_position
	orbit_angle += orbit_speed * orbit_direction * delta

	var raw_orbit_offset := _build_raw_orbit_offset()
	var local_offset := raw_orbit_offset.rotated(orbit_rotation)

	global_position = base_position + local_offset
	_set_visual_rotation(local_offset.angle())
	_update_orbit_render_layer(raw_orbit_offset)


func _process_travel_to_target(delta: float) -> void:
	# Abort cleanly if the target node was destroyed.
	if target_node == null or not is_instance_valid(target_node):
		_move_to_free_flight_parent()
		state = State.RETURNING
		return

	# Re-derive the orbit entry point from the planet's CURRENT position every
	# frame so the Bezier endpoint tracks the moving planet.
	target_position = target_node.global_position
	_prepare_orbit_entry()
	travel_end_position = orbit_entry_position
	_recalculate_travel_control_point()

	travel_progress = minf(travel_progress + (delta / maxf(travel_duration, 0.001)), 1.0)

	var eased_progress := _ease_in_out_power(travel_progress, travel_accel_curve_power)
	var new_position := _quadratic_bezier(travel_start_position, travel_control_position, travel_end_position, eased_progress)
	var direction := new_position - global_position

	global_position = new_position

	if direction.length_squared() > 0.0001:
		_set_visual_rotation(direction.angle())

	if travel_progress >= 1.0:
		state = State.APPROACH_ORBIT


func _process_approach_orbit(delta: float) -> void:
	if target_node == null or not is_instance_valid(target_node):
		_move_to_free_flight_parent()
		state = State.RETURNING
		return

	target_position = target_node.global_position
	_prepare_orbit_entry()

	_move_towards(orbit_entry_position, approach_speed, delta)

	if global_position.distance_to(orbit_entry_position) <= 3.0:
		state = State.WORKING
		work_timer = 0.0
		arrived_at_target.emit(self)


func _process_working(delta: float) -> void:
	if target_node != null and is_instance_valid(target_node):
		target_position = target_node.global_position
		orbit_angle += orbit_speed * orbit_direction * delta

		var raw_orbit_offset := _build_raw_orbit_offset()
		var local_offset := raw_orbit_offset.rotated(orbit_rotation)

		global_position = target_position + local_offset
		_set_visual_rotation(local_offset.angle())
		_update_orbit_render_layer(raw_orbit_offset)

	work_timer += delta

	if work_timer >= work_duration:
		state = State.RETURNING


func _process_returning(delta: float) -> void:
	if base_node != null and is_instance_valid(base_node):
		base_position = base_node.global_position

	_move_towards(base_position, return_speed, delta)

	if global_position.distance_to(base_position) <= 4.0:
		if base_node != null and is_instance_valid(base_node):
			transfer_orbit_to_base(base_node)
		else:
			state = State.IDLE
		returned_to_base.emit(self)


func _prepare_orbit_entry() -> void:
	if target_node == null or not is_instance_valid(target_node):
		orbit_entry_position = target_position
		return

	var target_center := target_node.global_position
	var entry_raw_offset := _build_raw_orbit_offset()
	var entry_offset := entry_raw_offset.rotated(orbit_rotation)

	orbit_entry_position = target_center + entry_offset


func _prepare_orbit_entry_for_node(node: Node2D) -> void:
	if node == null:
		return

	var target_center := node.global_position
	var entry_raw_offset := _build_raw_orbit_offset()
	var entry_offset := entry_raw_offset.rotated(orbit_rotation)

	orbit_entry_position = target_center + entry_offset


func _adopt_current_position_as_orbit() -> void:
	if base_node == null or not is_instance_valid(base_node):
		return

	base_position = base_node.global_position

	var local_offset := global_position - base_position
	var planet_radius := _get_base_visual_radius()
	var wanted_radius := maxf(local_offset.length(), planet_radius + orbit_padding_min)
	var max_radius := planet_radius + orbit_padding_max
	var y_scale := randf_range(orbit_perspective_y_scale_min, orbit_perspective_y_scale_max)

	orbit_radius_x = clampf(wanted_radius, planet_radius + orbit_padding_min, max_radius)
	orbit_radius_y = orbit_radius_x * y_scale
	orbit_angle = 0.0
	orbit_direction = -1.0 if randf() < 0.5 else 1.0
	orbit_rotation = _build_orbit_rotation()


func _generate_random_orbit() -> void:
	_generate_orbit_for_node(base_node)


# Generates orbit parameters sized to the visual radius of the given node.
# Call with target_node before a mission, with base_node for base orbit.
func _generate_orbit_for_node(node: Node2D) -> void:
	var planet_radius := _get_node_visual_radius(node)
	var padding := randf_range(orbit_padding_min, orbit_padding_max)

	orbit_radius_x = planet_radius + padding
	orbit_radius_y = orbit_radius_x * randf_range(orbit_perspective_y_scale_min, orbit_perspective_y_scale_max)
	orbit_speed = randf_range(min_orbit_speed, max_orbit_speed)
	orbit_angle = randf_range(0.0, TAU)
	orbit_direction = -1.0 if randf() < 0.5 else 1.0
	orbit_rotation = _build_orbit_rotation()


func _build_orbit_rotation() -> float:
	return deg_to_rad(90.0 + randf_range(orbit_tilt_degrees_min, orbit_tilt_degrees_max))


func _build_raw_orbit_offset() -> Vector2:
	return Vector2(
		cos(orbit_angle) * orbit_radius_x,
		sin(orbit_angle) * orbit_radius_y
	)


func _setup_travel_curve(start_pos: Vector2, end_pos: Vector2) -> void:
	travel_start_position = start_pos
	travel_end_position = end_pos
	travel_progress = 0.0
	travel_curve_side_sign = -1.0 if randf() < 0.5 else 1.0

	var travel_distance := (end_pos - start_pos).length()
	travel_duration = maxf(travel_distance / maxf(travel_speed, 1.0), 0.12)

	_recalculate_travel_control_point()


# Rebuilds the Bezier control point from the current start/end positions,
# keeping the stored side sign so the arc shape stays visually stable even
# when the endpoint moves every frame.
func _recalculate_travel_control_point() -> void:
	var travel_vector := travel_end_position - travel_start_position
	var travel_distance := travel_vector.length()
	var travel_direction := Vector2.RIGHT

	if travel_distance > 0.001:
		travel_direction = travel_vector / travel_distance

	var perpendicular := Vector2(-travel_direction.y, travel_direction.x)
	var curve_strength := minf(travel_curve_strength, travel_distance * 0.35)
	var midpoint := (travel_start_position + travel_end_position) * 0.5

	travel_control_position = midpoint + perpendicular * curve_strength * travel_curve_side_sign


func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var one_minus_t := 1.0 - t
	return (
		(one_minus_t * one_minus_t) * p0
		+ (2.0 * one_minus_t * t) * p1
		+ (t * t) * p2
	)


func _ease_in_out_power(t: float, power: float) -> float:
	var safe_power := maxf(power, 1.0)

	if t < 0.5:
		return 0.5 * pow(2.0 * t, safe_power)

	return 1.0 - 0.5 * pow(2.0 * (1.0 - t), safe_power)


func _move_towards(target: Vector2, speed: float, delta: float) -> void:
	var direction := target - global_position

	if direction.length() <= 0.01:
		return

	global_position = global_position.move_toward(target, speed * delta)
	_set_visual_rotation(direction.angle())


func _set_visual_rotation(angle: float) -> void:
	rotation = 0.0

	if visual_root != null:
		visual_root.rotation = angle + deg_to_rad(visual_rotation_offset_degrees)


func _update_orbit_render_layer(raw_orbit_offset: Vector2) -> void:
	var orbit_body := _get_active_orbit_node()
	var target_parent := _get_orbit_layer_parent(orbit_body, raw_orbit_offset)

	if target_parent == null:
		return

	if get_parent() == target_parent:
		return

	var old_global_transform: Transform2D = global_transform
	reparent(target_parent)
	global_transform = old_global_transform


func _get_active_orbit_node() -> Node2D:
	match state:
		State.ORBITING_BASE:
			return base_node
		State.WORKING:
			return target_node
		_:
			return null


func _get_base_visual() -> Sprite2D:
	return _get_node_visual(base_node)


func _get_node_visual(node: Node2D) -> Sprite2D:
	if node == null or not is_instance_valid(node):
		return null

	return node.get_node_or_null("OrbitPivot/BodyVisual") as Sprite2D


func _get_orbit_layer_parent(orbit_body: Node2D, raw_orbit_offset: Vector2) -> Node:
	if orbit_body == null or not is_instance_valid(orbit_body):
		return free_flight_parent

	if orbit_body is SystemBody:
		var body := orbit_body as SystemBody

		if raw_orbit_offset.y < 0.0:
			return body.get_back_orbit_units()

		return body.get_front_orbit_units()

	return free_flight_parent


func _move_to_free_flight_parent() -> void:
	if free_flight_parent == null or not is_instance_valid(free_flight_parent):
		return

	if get_parent() == free_flight_parent:
		return

	var old_global_transform: Transform2D = global_transform
	reparent(free_flight_parent)
	global_transform = old_global_transform


func _get_base_visual_radius() -> float:
	return _get_node_visual_radius(base_node)


func _get_node_visual_radius(node: Node2D) -> float:
	var planet_visual := _get_node_visual(node)

	if planet_visual == null:
		return 24.0

	if planet_visual.texture == null:
		return 24.0

	var texture_size: Vector2 = planet_visual.texture.get_size()
	var texture_radius: float = minf(texture_size.x, texture_size.y) * 0.5
	var scale_factor: float = maxf(absf(planet_visual.global_scale.x), absf(planet_visual.global_scale.y))

	return texture_radius * scale_factor
