class_name ShipNavigationComponent
extends Node

@export var max_speed: float = 260.0
@export var acceleration: float = 420.0
@export var braking_force: float = 520.0
@export var turn_speed: float = 4.5

@export var arrival_radius: float = 10.0
@export var slow_down_radius: float = 90.0

@export var manual_cancel_action: StringName = &"clear_navigation_target"

var motor := ShipMovementMotor.new()
var target_navigation := ShipTargetNavigation.new()
var autopilot := ShipAutopilot.new()

@onready var ship: CharacterBody2D = get_parent() as CharacterBody2D


func _ready() -> void:
	_apply_exported_values()


func _unhandled_input(event: InputEvent) -> void:
	if not is_processing():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		cancel_interaction_autopilot()
		set_target(ship.get_global_mouse_position())

	if event.is_action_pressed(manual_cancel_action):
		clear_target()
		cancel_interaction_autopilot()


func _physics_process(delta: float) -> void:
	if ship == null:
		return

	if autopilot.is_active():
		_process_autopilot(delta)
		return

	target_navigation.physics_process(ship, motor, delta)


func set_target(position: Vector2) -> void:
	target_navigation.set_target(position)


func clear_target() -> void:
	target_navigation.clear_target()


func has_target() -> bool:
	return target_navigation.has_target


func begin_interaction_approach(
	target_node: Node2D,
	action_name: StringName,
	desired_range: float
) -> void:
	if target_node == null:
		return

	autopilot.begin_interaction_approach(target_node, action_name, desired_range)
	target_navigation.set_target(target_node.global_position)


func cancel_interaction_autopilot() -> void:
	autopilot.clear()


func is_autopilot_active() -> bool:
	return autopilot.is_active()


func get_debug_data() -> Dictionary:
	var data := target_navigation.get_debug_data(ship)
	data["autopilot_active"] = autopilot.is_active()
	data["autopilot_mode"] = autopilot.mode
	data["autopilot_action"] = autopilot.action_name
	return data


func _process_autopilot(delta: float) -> void:
	if autopilot.target_node == null or not is_instance_valid(autopilot.target_node):
		cancel_interaction_autopilot()
		clear_target()
		return

	if autopilot.has_reached_range(ship):
		clear_target()
		cancel_interaction_autopilot()
		motor.apply_idle_brake(ship, delta)
		motor.move_ship(ship)
		return

	target_navigation.set_target(autopilot.get_target_position())
	target_navigation.physics_process(ship, motor, delta)


func _apply_exported_values() -> void:
	motor.max_speed = max_speed
	motor.acceleration = acceleration
	motor.braking_force = braking_force
	motor.turn_speed = turn_speed

	target_navigation.arrival_radius = arrival_radius
	target_navigation.slow_down_radius = slow_down_radius
