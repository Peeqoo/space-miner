extends Camera2D

@export var follow_smoothing: float = 6.0
@export var velocity_lookahead_distance: float = 80.0
@export var lookahead_smoothing: float = 5.0

var _target: Node2D
var _current_lookahead: Vector2 = Vector2.ZERO

func set_target(target: Node2D) -> void:
	_target = target

func _process(delta: float) -> void:
	if _target == null:
		return

	var ship := _target as CharacterBody2D
	var desired_lookahead := Vector2.ZERO

	if ship != null:
		var vel := ship.velocity
		if vel.length() > 1.0:
			desired_lookahead = vel.normalized() * velocity_lookahead_distance

	_current_lookahead = _current_lookahead.lerp(
		desired_lookahead,
		clamp(lookahead_smoothing * delta, 0.0, 1.0)
	)

	global_position = global_position.lerp(
		_target.global_position + _current_lookahead,
		clamp(follow_smoothing * delta, 0.0, 1.0)
	)
