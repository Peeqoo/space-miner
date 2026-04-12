extends RefCounted
class_name ShipMovementComponent

var current_velocity: Vector2 = Vector2.ZERO

func set_from_body(body_velocity: Vector2) -> void:
	current_velocity = body_velocity

func handle_rotation(
	body: CharacterBody2D,
	stats: ShipStats,
	input_state: Dictionary,
	can_stabilize: bool,
	delta: float
) -> bool:
	var turn_input: float = input_state["turn"]
	var rotation_speed_rad: float = deg_to_rad(stats.rotation_speed_deg)
	var used_stabilizer := false

	if input_state["stabilize"] and can_stabilize:
		rotation_speed_rad *= stats.stabilizer_rotation_multiplier
		used_stabilizer = true

	body.rotation += turn_input * rotation_speed_rad * delta
	return used_stabilizer

func handle_movement(
	body: CharacterBody2D,
	stats: ShipStats,
	input_state: Dictionary,
	can_stabilize: bool,
	has_fuel: bool,
	delta: float
) -> Dictionary:
	var forward := Vector2.RIGHT.rotated(body.rotation)
	var used_stabilizer := false
	var used_thrust := false
	var used_brake := false

	if input_state["thrust"] and has_fuel:
		current_velocity += forward * stats.acceleration * delta
		used_thrust = true

	if input_state["brake"]:
		current_velocity = current_velocity.move_toward(Vector2.ZERO, stats.brake_acceleration * delta)
		used_brake = true

	var drag_strength := stats.passive_drag
	if input_state["stabilize"] and can_stabilize:
		drag_strength = stats.stabilizer_drag
		used_stabilizer = true

	current_velocity = current_velocity.move_toward(Vector2.ZERO, drag_strength * delta)
	current_velocity = current_velocity.limit_length(stats.max_speed)

	body.velocity = current_velocity

	return {
		"used_stabilizer": used_stabilizer,
		"used_thrust": used_thrust,
		"used_brake": used_brake
	}

func apply_burst(body: CharacterBody2D, stats: ShipStats) -> void:
	var forward := Vector2.RIGHT.rotated(body.rotation)
	current_velocity += forward * stats.burst_impulse
	current_velocity = current_velocity.limit_length(stats.max_speed)
	body.velocity = current_velocity
