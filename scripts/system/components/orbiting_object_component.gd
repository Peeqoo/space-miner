class_name OrbitingObjectComponent
extends RefCounted

var orbit_center: Node2D = null
var orbit_radius: float = 300.0
var orbit_speed: float = 0.2
var orbit_angle: float = 0.0


func setup(
	p_orbit_radius: float,
	p_orbit_speed: float,
	p_start_angle_degrees: float
) -> void:
	orbit_radius = p_orbit_radius
	orbit_speed = p_orbit_speed
	orbit_angle = deg_to_rad(p_start_angle_degrees)


func set_orbit_center(node: Node2D) -> void:
	orbit_center = node


func process_orbit(owner: Node2D, delta: float) -> void:
	if orbit_center == null:
		return

	orbit_angle += orbit_speed * delta
	owner.global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius


func refresh_position(owner: Node2D) -> void:
	if orbit_center == null:
		return

	owner.global_position = orbit_center.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius


func get_tangent_direction(owner: Node2D) -> Vector2:
	if orbit_center == null:
		return Vector2.RIGHT

	var radial_direction: Vector2 = owner.global_position - orbit_center.global_position

	if radial_direction == Vector2.ZERO:
		return Vector2.RIGHT

	radial_direction = radial_direction.normalized()

	var tangent_direction := Vector2(-radial_direction.y, radial_direction.x)

	if orbit_speed < 0.0:
		tangent_direction = -tangent_direction

	return tangent_direction.normalized()


func get_velocity_vector(owner: Node2D) -> Vector2:
	if orbit_center == null:
		return Vector2.ZERO

	return get_tangent_direction(owner) * absf(orbit_speed) * orbit_radius
