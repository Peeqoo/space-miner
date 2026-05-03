## Applies low-level movement, braking and rotation to the player ship.
## Contains no targeting or autopilot state.
class_name ShipMovementMotor
extends RefCounted


# --------------------------------------------------
# Settings
# --------------------------------------------------

var max_speed: float = 260.0
var acceleration: float = 420.0
var braking_force: float = 520.0
var turn_speed: float = 4.5


# --------------------------------------------------
# Movement API
# --------------------------------------------------

func apply_idle_brake(ship: CharacterBody2D, delta: float) -> void:
	ship.velocity = ship.velocity.move_toward(Vector2.ZERO, braking_force * delta)


func rotate_ship_towards(ship: CharacterBody2D, direction: Vector2, delta: float) -> void:
	if direction == Vector2.ZERO:
		return

	var target_angle := direction.angle()
	ship.rotation = rotate_toward(ship.rotation, target_angle, turn_speed * delta)


func apply_desired_velocity(ship: CharacterBody2D, desired_velocity: Vector2, delta: float) -> void:
	if ship.velocity.length() < desired_velocity.length():
		ship.velocity = ship.velocity.move_toward(desired_velocity, acceleration * delta)
	else:
		ship.velocity = ship.velocity.move_toward(desired_velocity, braking_force * delta)


func move_ship(ship: CharacterBody2D) -> void:
	ship.move_and_slide()
