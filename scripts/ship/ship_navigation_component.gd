class_name ShipNavigationComponent
extends Node

@export var max_speed: float = 260.0
@export var acceleration: float = 420.0
@export var braking_force: float = 520.0
@export var turn_speed: float = 4.5
@export var arrival_radius: float = 10.0
@export var slow_down_radius: float = 90.0
@export var min_speed_factor_near_target: float = 0.15
@export var auto_clear_target_on_arrival: bool = true

var target_position: Vector2 = Vector2.ZERO
var has_target: bool = false
var navigation_enabled: bool = true

@onready var ship: CharacterBody2D = get_parent() as CharacterBody2D


func _physics_process(delta: float) -> void:
	if ship == null:
		return

	if not navigation_enabled:
		apply_idle_brake(delta)
		move_ship()
		return

	if not has_target:
		apply_idle_brake(delta)
		move_ship()
		return

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

	if ship.velocity.length() < desired_velocity.length():
		ship.velocity = ship.velocity.move_toward(desired_velocity, acceleration * delta)
	else:
		ship.velocity = ship.velocity.move_toward(desired_velocity, braking_force * delta)

	move_ship()


func set_target(position: Vector2) -> void:
	target_position = position
	has_target = true


func clear_target() -> void:
	has_target = false


func stop_immediately() -> void:
	has_target = false
	if ship != null:
		ship.velocity = Vector2.ZERO


func set_navigation_enabled(enabled: bool) -> void:
	navigation_enabled = enabled
	if not enabled:
		clear_target()


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
	}
