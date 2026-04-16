extends RefCounted
class_name ShipDamageComponent

var was_colliding_last_frame: bool = false

func should_apply_impact_damage(is_colliding_now: bool) -> bool:
	var is_new_impact: bool = is_colliding_now and not was_colliding_last_frame
	was_colliding_last_frame = is_colliding_now
	return is_new_impact

func compute_impact_damage(
	impact_speed: float,
	collision_normal: Vector2,
	velocity_direction: Vector2,
	speed_multiplier: float,
	minimum_damage: float,
	glancing_min_factor: float
) -> float:
	var impact_alignment: float = abs(velocity_direction.dot(collision_normal))
	var glancing_factor: float = lerp(glancing_min_factor, 1.0, impact_alignment)
	return max(minimum_damage, impact_speed * speed_multiplier * glancing_factor)

func reset_contact_state() -> void:
	was_colliding_last_frame = false
