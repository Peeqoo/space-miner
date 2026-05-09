## Reusable orbit behavior for system bodies and points of interest.
## Stores orbit settings and applies orbit movement to an owner node.
class_name OrbitingObjectComponent
extends RefCounted


# --------------------------------------------------
# State
# --------------------------------------------------

var orbit_center: Node2D = null
var orbit_radius: float = 300.0
var orbit_speed: float = 0.2
var orbit_angle: float = 0.0


# --------------------------------------------------
# Setup
# --------------------------------------------------

func setup(p_orbit_radius: float, p_orbit_speed: float, p_start_angle_degrees: float) -> void:
	orbit_radius = p_orbit_radius
	orbit_speed = p_orbit_speed
	orbit_angle = deg_to_rad(p_start_angle_degrees)


func set_orbit_center(node: Node2D) -> void:
	orbit_center = node


# --------------------------------------------------
# Orbit Movement
# --------------------------------------------------

func process_orbit(owner: Node2D, delta: float) -> void:
	if orbit_center == null:
		return

	orbit_angle += orbit_speed * delta
	owner.global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius


func refresh_position(owner: Node2D) -> void:
	if orbit_center == null:
		return

	owner.global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius

