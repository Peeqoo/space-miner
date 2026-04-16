extends RefCounted
class_name ShipMovementComponent

var current_velocity: Vector2 = Vector2.ZERO
var burst_time_left: float = 0.0

func set_from_body(body_velocity: Vector2) -> void:
	current_velocity = body_velocity

func tick(delta: float) -> void:
	if burst_time_left > 0.0:
		burst_time_left = max(0.0, burst_time_left - delta)

func handle_rotation(
	body: CharacterBody2D,
	stats: ShipStats,
	input_state: Dictionary,
	can_stabilize: bool,
	delta: float
) -> bool:
	var turn_input: float = input_state["turn"]
	var rotation_speed_rad: float = deg_to_rad(stats.rotation_speed_deg)
	var used_stabilizer: bool = false

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
	var forward: Vector2 = Vector2.UP.rotated(body.rotation)

	var used_stabilizer: bool = false
	var used_thrust: bool = false
	var used_brake: bool = false

	var speed: float = current_velocity.length()
	var burst_active: bool = burst_time_left > 0.0
	var stabilizer_active: bool = input_state["stabilize"] and can_stabilize

	# Normaler Schub nur bis max_speed
	if input_state["thrust"] and has_fuel and speed < stats.max_speed:
		current_velocity += forward * stats.acceleration * delta
		used_thrust = true

	# Burst-Schub nur bis burst_max_speed
	if burst_active and speed < stats.burst_max_speed:
		current_velocity += forward * stats.burst_acceleration * delta

	# Steering / Flugrichtung zur Nase ziehen
	if current_velocity.length() > 0.1:
		var steering_speed: float = 0.0

		if input_state["thrust"] or burst_active:
			steering_speed = stats.steering_lerp_speed

		if abs(input_state["turn"]) > 0.01:
			steering_speed = max(steering_speed, stats.turn_steering_lerp_speed)

		if stabilizer_active:
			steering_speed *= stats.stabilizer_steering_multiplier
			used_stabilizer = true

		if steering_speed > 0.0:
			var target_velocity: Vector2 = forward * current_velocity.length()
			current_velocity = current_velocity.lerp(
				target_velocity,
				clamp(steering_speed * delta, 0.0, 1.0)
			)

	# Brake = echtes Stoppen
	if input_state["brake"]:
		current_velocity = current_velocity.move_toward(
			Vector2.ZERO,
			stats.brake_acceleration * delta
		)
		used_brake = true

	# Passiver Drag
	current_velocity = current_velocity.move_toward(
		Vector2.ZERO,
		stats.passive_drag * delta
	)

	# Stabilizer = nur auf reduzierte Geschwindigkeit ziehen, nicht auf 0
	if stabilizer_active:
		used_stabilizer = true

		var reduced_speed: float = max(0.0, stats.max_speed - stats.stabilizer_speed_reduction)

		if current_velocity.length() > reduced_speed:
			var target_velocity: Vector2 = current_velocity.normalized() * reduced_speed
			current_velocity = current_velocity.move_toward(
				target_velocity,
				stats.stabilizer_drag * delta
			)

	# Speed-Logik
	if burst_active:
		current_velocity = current_velocity.limit_length(stats.burst_max_speed)
	else:
		# Nach Burst langsam zurück auf max_speed
		if current_velocity.length() > stats.max_speed:
			var target_velocity: Vector2 = current_velocity.normalized() * stats.max_speed
			current_velocity = current_velocity.move_toward(
				target_velocity,
				stats.burst_decay * delta
			)

		# Normales Fluglimit
		current_velocity = current_velocity.limit_length(stats.max_speed)

	body.velocity = current_velocity

	return {
		"used_stabilizer": used_stabilizer,
		"used_thrust": used_thrust,
		"used_brake": used_brake
	}

func apply_burst(_body: CharacterBody2D, stats: ShipStats) -> void:
	burst_time_left = stats.burst_duration

func is_burst_active() -> bool:
	return burst_time_left > 0.0

func is_above_normal_speed(stats: ShipStats) -> bool:
	return current_velocity.length() > stats.max_speed + 1.0
