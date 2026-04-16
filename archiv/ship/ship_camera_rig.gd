extends Node2D
class_name ShipCameraRig

@export var trauma_decay: float = 10.0
@export var max_shake_offset: Vector2 = Vector2(18.0, 18.0)

var _trauma: float = 0.0

func add_trauma(amount: float) -> void:
	_trauma = clamp(_trauma + amount, 0.0, 1.0)
	print("ADD TRAUMA: ", _trauma)

func _physics_process(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = max(0.0, _trauma - trauma_decay * delta)

	var shake_strength: float = _trauma

	if shake_strength <= 0.0:
		position = Vector2.ZERO
		return

	position = Vector2(
		randf_range(-max_shake_offset.x, max_shake_offset.x),
		randf_range(-max_shake_offset.y, max_shake_offset.y)
	) * shake_strength
