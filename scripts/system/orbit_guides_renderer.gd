extends Node2D

@export var orbit_color: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var orbit_width: float = 0.5
@export var segments: int = 96

var orbit_entries: Array = []

func set_orbits(entries: Array) -> void:
	orbit_entries = entries
	queue_redraw()

func _draw() -> void:
	for entry in orbit_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var center: Vector2 = entry.get("center", Vector2.ZERO)
		var radius: float = float(entry.get("radius", 100.0))
		draw_arc(center, radius, 0.0, TAU, segments, orbit_color, orbit_width)
