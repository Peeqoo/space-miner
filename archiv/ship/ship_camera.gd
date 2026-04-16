extends Camera2D
class_name ShipCamera

@export var offset_smoothing: float = 8.0
@export var velocity_lookahead_distance: float = 24.0

@export var lookahead_activation_distance: float = 56.0
@export var lookahead_fade_distance: float = 32.0
@export var lookahead_blend_smoothing: float = 6.0

@export var movement_reset_speed: float = 5.0

var _target: CharacterBody2D
var _current_offset: Vector2 = Vector2.ZERO

var _movement_start_position: Vector2 = Vector2.ZERO
var _movement_started: bool = false
var _lookahead_blend: float = 0.0

func set_target(target: Node2D) -> void:
	_target = target as CharacterBody2D

	if _target != null:
		_movement_start_position = _target.global_position
		_movement_started = false
		_lookahead_blend = 0.0

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var speed: float = _target.velocity.length()

	if speed > movement_reset_speed:
		if not _movement_started:
			_movement_started = true
			_movement_start_position = _target.global_position
	else:
		_movement_started = false
		_movement_start_position = _target.global_position

	var moved_distance: float = _target.global_position.distance_to(_movement_start_position)

	var target_blend: float = 0.0

	if _movement_started and speed > movement_reset_speed:
		var fade_start: float = lookahead_activation_distance
		var fade_end: float = lookahead_activation_distance + lookahead_fade_distance

		target_blend = inverse_lerp(fade_start, fade_end, moved_distance)
		target_blend = clamp(target_blend, 0.0, 1.0)

	_lookahead_blend = lerp(
		_lookahead_blend,
		target_blend,
		clamp(lookahead_blend_smoothing * delta, 0.0, 1.0)
	)

	var desired_offset: Vector2 = Vector2.ZERO

	if speed > 1.0:
		var lookahead_direction: Vector2 = _target.velocity.normalized()
		desired_offset = lookahead_direction * velocity_lookahead_distance * _lookahead_blend

	_current_offset = _current_offset.lerp(
		desired_offset,
		clamp(offset_smoothing * delta, 0.0, 1.0)
	)

	offset = _current_offset
