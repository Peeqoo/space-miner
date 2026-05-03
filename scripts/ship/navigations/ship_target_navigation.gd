class_name ShipTargetNavigation
extends RefCounted

var arrival_radius: float = 10.0
var slow_down_radius: float = 90.0

var target_position: Vector2 = Vector2.ZERO
var has_target: bool = false


func set_target(position: Vector2) -> void:
	target_position = position
	has_target = true


func clear_target() -> void:
	has_target = false


func physics_process(
	ship: CharacterBody2D,
	motor: ShipMovementMotor,
	delta: float
) -> void:
	if not has_target:
		motor.apply_idle_brake(ship, delta)
		motor.move_ship(ship)
		return

	var to_target := target_position - ship.global_position
	var distance := to_target.length()

	if distance <= arrival_radius:
		clear_target()
		motor.apply_idle_brake(ship, delta)
		motor.move_ship(ship)
		return

	var desired_direction := to_target.normalized()
	motor.rotate_ship_towards(ship, desired_direction, delta)

	var desired_speed := motor.max_speed

	if distance < slow_down_radius:
		var slowdown_factor: float = clampf(distance / slow_down_radius, 0.15, 1.0)
		desired_speed *= slowdown_factor

	var desired_velocity := desired_direction * desired_speed

	motor.apply_desired_velocity(ship, desired_velocity, delta)
	motor.move_ship(ship)


func get_debug_data(ship: CharacterBody2D) -> Dictionary:
	return {
		"has_target": has_target,
		"target_position": target_position,
		"speed": ship.velocity.length(),
	}
