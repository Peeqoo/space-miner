class_name ShipNavigationComponent
extends Node

signal autopilot_state_changed(state_name: String, status_text: String)
signal interaction_orbit_ready(action_name: String, target: Node2D)

enum AutopilotState {
	NONE,
	POSITION_NAV,
	PLAN,
	APPROACH,
	CAPTURE,
	LOCAL_ORBIT
}

@export var max_speed: float = 190.0
@export var acceleration: float = 250.0
@export var braking_force: float = 320.0
@export var turn_speed: float = 3.6
@export var arrival_radius: float = 10.0
@export var slow_down_radius: float = 110.0
@export var min_speed_factor_near_target: float = 0.18
@export var auto_clear_target_on_arrival: bool = true

@export var plan_delay_seconds: float = 0.35
@export var interaction_intercept_lead_time: float = 0.55
@export var capture_distance: float = 56.0
@export var orbit_insert_distance_tolerance: float = 12.0
@export var orbit_insert_velocity_tolerance: float = 34.0
@export var orbit_follow_gain: float = 3.2
@export var orbit_ready_delay: float = 0.45

var target_position: Vector2 = Vector2.ZERO
var has_target: bool = false
var navigation_enabled: bool = true

var autopilot_state: AutopilotState = AutopilotState.NONE
var interaction_target: Node2D = null
var interaction_action_name: String = ""
var interaction_desired_range: float = 0.0

var plan_timer_remaining: float = 0.0
var hold_ready_emitted: bool = false
var local_orbit_radius: float = 0.0
var local_orbit_direction: float = 1.0
var local_orbit_angle: float = 0.0
var local_orbit_angular_speed: float = 0.0
var local_orbit_ready_timer: float = 0.0

@onready var ship: CharacterBody2D = get_parent() as CharacterBody2D


func _physics_process(delta: float) -> void:
	if ship == null:
		return

	if not navigation_enabled:
		apply_idle_brake(delta)
		move_ship()
		return

	if interaction_target != null:
		_process_interaction_autopilot(delta)
		return

	if not has_target:
		autopilot_state = AutopilotState.NONE
		apply_idle_brake(delta)
		move_ship()
		return

	autopilot_state = AutopilotState.POSITION_NAV
	_process_position_navigation(delta)


func _process_position_navigation(delta: float) -> void:
	var to_target: Vector2 = target_position - ship.global_position
	var distance: float = to_target.length()

	if distance <= arrival_radius:
		if auto_clear_target_on_arrival:
			clear_target()

		apply_idle_brake(delta)
		move_ship()
		return

	var desired_direction: Vector2 = to_target.normalized()
	rotate_ship_towards(desired_direction, delta)

	var desired_speed: float = max_speed
	if distance < slow_down_radius:
		var slowdown_factor: float = clampf(
			distance / slow_down_radius,
			min_speed_factor_near_target,
			1.0
		)
		desired_speed *= slowdown_factor

	var desired_velocity: Vector2 = desired_direction * desired_speed
	_apply_desired_velocity(desired_velocity, delta)
	move_ship()


func begin_interaction_approach(target: Node2D, action_name: String, desired_range: float) -> void:
	if ship == null or target == null:
		return

	has_target = false
	target_position = ship.global_position

	interaction_target = target
	interaction_action_name = action_name
	interaction_desired_range = desired_range

	hold_ready_emitted = false
	local_orbit_ready_timer = 0.0

	if is_orbiting_target(target):
		emit_signal("autopilot_state_changed", "local_orbit", "Stabile Orbitposition erreicht")
		emit_signal("interaction_orbit_ready", action_name, target)
		return

	_rebuild_orbit_plan()
	autopilot_state = AutopilotState.PLAN
	plan_timer_remaining = plan_delay_seconds

	emit_signal("autopilot_state_changed", "plan", "Abfangkurs wird berechnet")


func cancel_interaction_autopilot(stop_ship: bool = false) -> void:
	interaction_target = null
	interaction_action_name = ""
	interaction_desired_range = 0.0

	plan_timer_remaining = 0.0
	hold_ready_emitted = false
	local_orbit_radius = 0.0
	local_orbit_direction = 1.0
	local_orbit_angle = 0.0
	local_orbit_angular_speed = 0.0
	local_orbit_ready_timer = 0.0

	if not has_target:
		autopilot_state = AutopilotState.NONE

	if stop_ship and ship != null:
		ship.velocity = Vector2.ZERO

	emit_signal("autopilot_state_changed", "idle", "")


func set_target(position: Vector2) -> void:
	cancel_interaction_autopilot(false)
	target_position = position
	has_target = true
	autopilot_state = AutopilotState.POSITION_NAV


func clear_target() -> void:
	has_target = false
	if interaction_target == null:
		autopilot_state = AutopilotState.NONE


func stop_immediately() -> void:
	has_target = false
	cancel_interaction_autopilot(false)

	if ship != null:
		ship.velocity = Vector2.ZERO


func set_navigation_enabled(enabled: bool) -> void:
	navigation_enabled = enabled
	if not enabled:
		clear_target()
		cancel_interaction_autopilot(false)


func is_orbiting_target(target: Node2D) -> bool:
	if target == null:
		return false

	return autopilot_state == AutopilotState.LOCAL_ORBIT and interaction_target == target


func get_interaction_target() -> Node2D:
	return interaction_target


func has_active_interaction_target() -> bool:
	return interaction_target != null


func apply_idle_brake(delta: float) -> void:
	if ship == null:
		return

	ship.velocity = ship.velocity.move_toward(Vector2.ZERO, braking_force * delta)


func rotate_ship_towards(direction: Vector2, delta: float) -> void:
	if ship == null or direction == Vector2.ZERO:
		return

	var target_angle: float = direction.angle()
	ship.rotation = rotate_toward(ship.rotation, target_angle, turn_speed * delta)


func move_ship() -> void:
	if ship == null:
		return

	ship.move_and_slide()


func get_debug_data() -> Dictionary:
	return {
		"navigation_enabled": navigation_enabled,
		"has_target": has_target,
		"target_position": target_position,
		"speed": ship.velocity.length(),
		"autopilot_state": int(autopilot_state),
		"interaction_action_name": interaction_action_name,
		"has_interaction_target": interaction_target != null,
		"local_orbit_radius": local_orbit_radius,
		"local_orbit_angular_speed": local_orbit_angular_speed,
	}


func _process_interaction_autopilot(delta: float) -> void:
	if ship == null:
		return

	if not is_instance_valid(interaction_target):
		cancel_interaction_autopilot(false)
		apply_idle_brake(delta)
		move_ship()
		return

	match autopilot_state:
		AutopilotState.PLAN:
			_process_plan_state(delta)

		AutopilotState.APPROACH:
			_process_approach_state(delta)

		AutopilotState.CAPTURE:
			_process_capture_state(delta)

		AutopilotState.LOCAL_ORBIT:
			_process_local_orbit_state(delta)

		_:
			autopilot_state = AutopilotState.PLAN
			plan_timer_remaining = plan_delay_seconds
			emit_signal("autopilot_state_changed", "plan", "Abfangkurs wird berechnet")


func _process_plan_state(delta: float) -> void:
	ship.velocity = Vector2.ZERO
	move_ship()

	plan_timer_remaining = maxf(plan_timer_remaining - delta, 0.0)
	if plan_timer_remaining > 0.0:
		return

	_rebuild_orbit_plan()
	autopilot_state = AutopilotState.APPROACH
	emit_signal("autopilot_state_changed", "approach", "Abfangkurs aktiv")


func _process_approach_state(delta: float) -> void:
	var intercept_point: Vector2 = _get_predicted_orbit_insert_point()
	var to_intercept: Vector2 = intercept_point - ship.global_position
	var distance_to_intercept: float = to_intercept.length()

	if to_intercept != Vector2.ZERO:
		rotate_ship_towards(to_intercept.normalized(), delta)

	_process_seek_to_position(intercept_point, delta)

	if distance_to_intercept <= capture_distance:
		autopilot_state = AutopilotState.CAPTURE
		emit_signal("autopilot_state_changed", "capture", "Relativgeschwindigkeit wird angepasst")


func _process_capture_state(delta: float) -> void:
	_rebuild_orbit_plan()

	var insert_point: Vector2 = _get_current_orbit_insert_point()
	var target_velocity: Vector2 = _get_target_velocity(interaction_target)
	var desired_orbit_velocity: Vector2 = _build_desired_orbit_velocity(insert_point, target_velocity)

	var to_insert: Vector2 = insert_point - ship.global_position
	var correction_velocity: Vector2 = to_insert * orbit_follow_gain
	var desired_velocity: Vector2 = (desired_orbit_velocity + correction_velocity).limit_length(max_speed)

	if desired_velocity != Vector2.ZERO:
		rotate_ship_towards(desired_velocity.normalized(), delta)

	_apply_desired_velocity(desired_velocity, delta)
	move_ship()

	var velocity_error: float = (ship.velocity - desired_orbit_velocity).length()
	if to_insert.length() <= orbit_insert_distance_tolerance and velocity_error <= orbit_insert_velocity_tolerance:
		local_orbit_angle = _get_angle_from_target(ship.global_position)
		local_orbit_ready_timer = 0.0
		hold_ready_emitted = false
		autopilot_state = AutopilotState.LOCAL_ORBIT
		emit_signal("autopilot_state_changed", "local_orbit", "Stabile Orbitposition wird gehalten")


func _process_local_orbit_state(delta: float) -> void:
	_rebuild_orbit_plan()

	local_orbit_angle += local_orbit_angular_speed * local_orbit_direction * delta

	var orbit_point: Vector2 = _get_current_orbit_point()
	var target_velocity: Vector2 = _get_target_velocity(interaction_target)
	var desired_orbit_velocity: Vector2 = _build_desired_orbit_velocity(orbit_point, target_velocity)

	var to_orbit_point: Vector2 = orbit_point - ship.global_position
	var correction_velocity: Vector2 = to_orbit_point * orbit_follow_gain
	var desired_velocity: Vector2 = (desired_orbit_velocity + correction_velocity).limit_length(max_speed)

	if desired_velocity != Vector2.ZERO:
		rotate_ship_towards(desired_velocity.normalized(), delta)

	_apply_desired_velocity(desired_velocity, delta)
	move_ship()

	if to_orbit_point.length() <= orbit_insert_distance_tolerance:
		local_orbit_ready_timer += delta
	else:
		local_orbit_ready_timer = 0.0

	if not hold_ready_emitted and local_orbit_ready_timer >= orbit_ready_delay:
		hold_ready_emitted = true
		emit_signal("interaction_orbit_ready", interaction_action_name, interaction_target)


func _process_seek_to_position(position: Vector2, delta: float) -> void:
	var to_target: Vector2 = position - ship.global_position
	var distance: float = to_target.length()

	if distance <= arrival_radius:
		apply_idle_brake(delta)
		move_ship()
		return

	var desired_direction: Vector2 = to_target.normalized()
	var desired_speed: float = max_speed

	if distance < slow_down_radius:
		var slowdown_factor: float = clampf(
			distance / slow_down_radius,
			min_speed_factor_near_target,
			1.0
		)
		desired_speed *= slowdown_factor

	var desired_velocity: Vector2 = desired_direction * desired_speed
	_apply_desired_velocity(desired_velocity, delta)
	move_ship()


func _apply_desired_velocity(desired_velocity: Vector2, delta: float) -> void:
	if ship == null:
		return

	if ship.velocity.length() < desired_velocity.length():
		ship.velocity = ship.velocity.move_toward(desired_velocity, acceleration * delta)
	else:
		ship.velocity = ship.velocity.move_toward(desired_velocity, braking_force * delta)


func _rebuild_orbit_plan() -> void:
	if interaction_target == null:
		return

	var orbit_config: Dictionary = _get_target_orbit_config(interaction_target)

	local_orbit_radius = float(orbit_config.get("radius", maxf(interaction_desired_range, 30.0)))
	local_orbit_direction = float(orbit_config.get("direction", 1.0))
	local_orbit_angular_speed = float(orbit_config.get("angular_speed", 0.7))

	if local_orbit_radius <= 0.0:
		local_orbit_radius = maxf(interaction_desired_range, 30.0)

	if local_orbit_angular_speed <= 0.0:
		local_orbit_angular_speed = 0.7

	if autopilot_state == AutopilotState.PLAN or autopilot_state == AutopilotState.APPROACH:
		var predicted_insert_point: Vector2 = _get_predicted_orbit_insert_point()
		local_orbit_angle = _get_angle_from_target(predicted_insert_point)


func _get_target_orbit_config(target: Node2D) -> Dictionary:
	if target == null:
		return {
			"radius": maxf(interaction_desired_range, 30.0),
			"direction": 1.0,
			"angular_speed": 0.7,
		}

	if target.has_method("get_interaction_orbit_config"):
		var config_result: Variant = target.call(
			"get_interaction_orbit_config",
			interaction_action_name,
			interaction_desired_range,
			ship.global_position
		)
		if config_result is Dictionary:
			return config_result as Dictionary

	return {
		"radius": maxf(interaction_desired_range, 30.0),
		"direction": 1.0,
		"angular_speed": 0.7,
	}


func _get_predicted_orbit_insert_point() -> Vector2:
	if interaction_target == null:
		return ship.global_position

	var target_velocity: Vector2 = _get_target_velocity(interaction_target)
	var predicted_target_position: Vector2 = interaction_target.global_position + target_velocity * interaction_intercept_lead_time
	var offset: Vector2 = Vector2.RIGHT.rotated(local_orbit_angle) * local_orbit_radius
	return predicted_target_position + offset


func _get_current_orbit_insert_point() -> Vector2:
	if interaction_target == null:
		return ship.global_position

	var offset: Vector2 = Vector2.RIGHT.rotated(local_orbit_angle) * local_orbit_radius
	return interaction_target.global_position + offset


func _get_current_orbit_point() -> Vector2:
	if interaction_target == null:
		return ship.global_position

	var offset: Vector2 = Vector2.RIGHT.rotated(local_orbit_angle) * local_orbit_radius
	return interaction_target.global_position + offset


func _build_desired_orbit_velocity(orbit_point: Vector2, target_velocity: Vector2) -> Vector2:
	if interaction_target == null:
		return Vector2.ZERO

	var radial: Vector2 = orbit_point - interaction_target.global_position
	if radial == Vector2.ZERO:
		radial = Vector2.RIGHT

	var radial_direction: Vector2 = radial.normalized()
	var tangent_direction: Vector2 = Vector2(-radial_direction.y, radial_direction.x) * local_orbit_direction
	var orbit_linear_speed: float = local_orbit_radius * local_orbit_angular_speed

	return target_velocity + tangent_direction * orbit_linear_speed


func _get_angle_from_target(world_position: Vector2) -> float:
	if interaction_target == null:
		return 0.0

	var offset: Vector2 = world_position - interaction_target.global_position
	if offset == Vector2.ZERO:
		return 0.0

	return offset.angle()


func _get_target_velocity(target: Node2D) -> Vector2:
	if target == null:
		return Vector2.ZERO

	if target.has_method("get_orbit_velocity_vector"):
		var velocity_result: Variant = target.call("get_orbit_velocity_vector")
		if velocity_result is Vector2:
			return velocity_result as Vector2

	return Vector2.ZERO
