extends Node2D
class_name DamageNumber

@export var float_distance: float = 24.0
@export var lifetime: float = 0.5
@export var hold_time: float = 0.4

@export var start_scale: Vector2 = Vector2(2.2, 2.2)
@export var normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var end_scale: Vector2 = Vector2(0.7, 0.7)

@onready var label: Label = $Label

func setup(amount: float) -> void:
	label.text = "-" + str(int(round(amount)))

	# Farbe
	if amount < 10.0:
		label.modulate = Color.WHITE
	elif amount < 25.0:
		label.modulate = Color.YELLOW
	else:
		label.modulate = Color.RED

	label.scale = start_scale

	_start_animation()

func _start_animation() -> void:
	var start_pos: Vector2 = global_position
	var end_pos: Vector2 = start_pos + Vector2(randf_range(-10.0, 10.0), -float_distance)

	var tween := create_tween()

	# Phase 1: POP (groß → normal)
	tween.tween_property(label, "scale", normal_scale, 0.12)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	# Phase 2: HOLD (stehen bleiben)
	tween.tween_interval(hold_time)

	# Phase 3: FLOAT + FADE + SHRINK
	tween.tween_property(self, "global_position", end_pos, lifetime)
	tween.parallel().tween_property(label, "modulate:a", 0.0, lifetime)
	tween.parallel().tween_property(label, "scale", end_scale, lifetime)

	tween.finished.connect(func() -> void:
		queue_free()
	)
