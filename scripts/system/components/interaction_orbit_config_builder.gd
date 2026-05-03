class_name InteractionOrbitConfigBuilder
extends RefCounted


static func build_config(
	action_name: String,
	desired_range: float,
	selection_ring_radius: float,
	orbit_speed: float,
	is_body: bool
) -> Dictionary:
	return {
		"radius": get_interaction_radius(action_name, desired_range, selection_ring_radius, is_body),
		"direction": 1.0 if orbit_speed >= 0.0 else -1.0,
		"angular_speed": get_local_orbit_angular_speed(action_name, is_body),
	}


static func get_interaction_radius(
	action_name: String,
	desired_range: float,
	selection_ring_radius: float,
	is_body: bool
) -> float:
	if is_body:
		var body_base_radius: float = maxf(selection_ring_radius + 16.0, desired_range * 0.18)

		match action_name:
			"dock", "land":
				return selection_ring_radius + 12.0
			"scan":
				return selection_ring_radius + 16.0
			"mining":
				return selection_ring_radius + 20.0
			"approach":
				return selection_ring_radius + 18.0
			_:
				return body_base_radius

	var poi_base_radius: float = maxf(selection_ring_radius + 12.0, desired_range * 0.16)

	match action_name:
		"scan":
			return selection_ring_radius + 12.0
		"mining":
			return selection_ring_radius + 16.0
		"approach":
			return selection_ring_radius + 14.0
		_:
			return poi_base_radius


static func get_local_orbit_angular_speed(action_name: String, is_body: bool) -> float:
	if is_body:
		match action_name:
			"dock", "land":
				return 0.42
			"scan":
				return 0.58
			"mining":
				return 0.72
			"approach":
				return 0.60
			_:
				return 0.60

	match action_name:
		"scan":
			return 0.66
		"mining":
			return 0.82
		"approach":
			return 0.70
		_:
			return 0.70
