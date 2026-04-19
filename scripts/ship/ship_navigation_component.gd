class_name ShipNavigationComponent
extends Node

@export var max_speed: float = 260.0
@export var acceleration: float = 420.0
@export var braking_force: float = 520.0
@export var turn_speed: float = 4.5
@export var arrival_radius: float = 10.0
@export var slow_down_radius: float = 90.0
@export var manual_cancel_action: StringName = &"clear_navigation_target"

var target_position: Vector2 = Vector2.ZERO
var has_target: bool = false

@onready var ship: CharacterBody2D = get_parent() as CharacterBody2D


func _unhandled_input(event: InputEvent) -> void:
	if not is_processing():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		set_target(ship.get_global_mouse_position())

	if event.is_action_pressed(manual_cancel_action):
		clear_target()


func _physics_process(delta: float) -> void:
	if ship == null:
		return

	if not has_target:
		apply_idle_brake(delta)
		move_ship()
		return

	var to_target := target_position - ship.global_position
	var distance := to_target.length()
	if distance <= arrival_radius:
		clear_target()
		ship.velocity = ship.velocity.move_toward(Vector2.ZERO, braking_force * delta)
		move_ship()
		return

	var desired_direction := to_target.normalized()
	rotate_ship_towards(desired_direction, delta)

	var desired_speed := max_speed
	if distance < slow_down_radius:
		var slowdown_factor: float = clampf(distance / slow_down_radius, 0.15, 1.0)
		desired_speed *= slowdown_factor

	var desired_velocity := desired_direction * desired_speed
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


func apply_idle_brake(delta: float) -> void:
	ship.velocity = ship.velocity.move_toward(Vector2.ZERO, braking_force * delta)


func rotate_ship_towards(direction: Vector2, delta: float) -> void:
	var target_angle := direction.angle()
	ship.rotation = rotate_toward(ship.rotation, target_angle, turn_speed * delta)


func move_ship() -> void:
	ship.move_and_slide()


func get_debug_data() -> Dictionary:
	return {
		"has_target": has_target,
		"target_position": target_position,
		"speed": ship.velocity.length(),
	}
