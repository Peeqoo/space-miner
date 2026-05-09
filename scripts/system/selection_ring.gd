## Draws a circular selection ring around a selected system object.
extends Node2D

@export var radius: float = 28.0
@export var color: Color = Color(0.35, 0.85, 1.0)
@export var width: float = 2.0
@export var segments: int = 48

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, segments, color, width)
