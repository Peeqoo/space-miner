extends Node2D

func _draw() -> void:
	draw_circle(Vector2.ZERO, 3.0, Color.RED)

func _ready() -> void:
	queue_redraw()
