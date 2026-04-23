class_name CelestialPresentationCalculator
extends RefCounted


const EARTH_REFERENCE_PERIOD_DAYS: float = 365.25
const MIN_RATIO: float = 0.0001

const DEFAULT_EARTH_TARGET_BODY_DIAMETER_PX: float = 46.0
const DEFAULT_EARTH_TARGET_ORBIT_OFFSET_PX: float = 185.0
const DEFAULT_EARTH_ORBIT_ANGULAR_SPEED: float = 0.22
const DEFAULT_SIZE_CURVE_EXPONENT: float = 0.38
const DEFAULT_ORBIT_CURVE_EXPONENT: float = 0.42
const DEFAULT_SPEED_CURVE_EXPONENT: float = 0.50
const DEFAULT_MINIMUM_BODY_DIAMETER_PX: float = 10.0
const DEFAULT_SELECTION_RING_PADDING_PX: float = 14.0
const DEFAULT_MIN_ANGULAR_SPEED: float = 0.03
const DEFAULT_MAX_ANGULAR_SPEED: float = 1.50


static func build_presentation(
	body_def: SystemBodyDefinition,
	system_def: SystemDefinition
) -> Dictionary:
	var visual_scale: float = get_final_visual_scale(body_def, system_def)
	var body_diameter_px: float = get_rendered_body_diameter_px(body_def, system_def, visual_scale)
	var orbit_radius_px: float = get_final_orbit_radius(body_def, system_def)
	var orbit_speed: float = get_final_orbit_speed(body_def, system_def)
	var ring_padding: float = _read_float(
		system_def,
		"selection_ring_padding_px",
		DEFAULT_SELECTION_RING_PADDING_PX
	)
	var selection_ring_radius: float = max(body_diameter_px * 0.5 + ring_padding, 16.0)

	var result: Dictionary = {}
	result["visual_scale"] = visual_scale
	result["body_diameter_px"] = body_diameter_px
	result["orbit_radius"] = orbit_radius_px
	result["orbit_speed"] = orbit_speed
	result["selection_ring_radius"] = selection_ring_radius
	return result


static func get_final_visual_scale(
	body_def: SystemBodyDefinition,
	system_def: SystemDefinition
) -> float:
	if not _has_calculated_size_input(body_def):
		return max(body_def.body_scale, 0.01)

	var asset_diameter: float = _get_asset_body_diameter_px(body_def)
	if asset_diameter <= 0.0:
		return max(body_def.body_scale, 0.01)

	var target_diameter: float = _get_target_body_diameter_px(body_def, system_def)
	return max(target_diameter / asset_diameter, 0.01)


static func get_rendered_body_diameter_px(
	body_def: SystemBodyDefinition,
	system_def: SystemDefinition,
	visual_scale: float
) -> float:
	if _has_calculated_size_input(body_def):
		return _get_target_body_diameter_px(body_def, system_def)

	var minimum_body_diameter_px: float = _read_float(
		system_def,
		"minimum_body_diameter_px",
		DEFAULT_MINIMUM_BODY_DIAMETER_PX
	)

	var asset_diameter: float = _get_asset_body_diameter_px(body_def)
	if asset_diameter > 0.0:
		return max(asset_diameter * visual_scale, minimum_body_diameter_px)

	var earth_target_body_diameter_px: float = _read_float(
		system_def,
		"earth_target_body_diameter_px",
		DEFAULT_EARTH_TARGET_BODY_DIAMETER_PX
	)

	return max(
		earth_target_body_diameter_px * visual_scale,
		minimum_body_diameter_px
	)


static func get_final_orbit_radius(
	body_def: SystemBodyDefinition,
	system_def: SystemDefinition
) -> float:
	if body_def.reference_orbit_au > 0.0:
		var earth_target_orbit_offset_px: float = _read_float(
			system_def,
			"earth_target_orbit_offset_px",
			DEFAULT_EARTH_TARGET_ORBIT_OFFSET_PX
		)
		var orbit_curve_exponent: float = _read_float(
			system_def,
			"orbit_curve_exponent",
			DEFAULT_ORBIT_CURVE_EXPONENT
		)

		var orbit_factor: float = pow(
			max(body_def.reference_orbit_au, MIN_RATIO),
			orbit_curve_exponent
		)
		var scaled_radius: float = earth_target_orbit_offset_px * orbit_factor
		scaled_radius *= max(body_def.gameplay_orbit_bias, 0.01)

		if body_def.orbit_center_id == "star":
			return _read_float(system_def, "star_visual_radius", 80.0) + scaled_radius

		return scaled_radius

	var legacy_radius: float = max(body_def.orbit_radius, 0.0)
	if body_def.orbit_center_id == "star":
		return _read_float(system_def, "star_visual_radius", 80.0) + legacy_radius

	return legacy_radius


static func get_final_orbit_speed(
	body_def: SystemBodyDefinition,
	system_def: SystemDefinition
) -> float:
	if body_def.reference_period_days > 0.0:
		var earth_orbit_angular_speed: float = _read_float(
			system_def,
			"earth_orbit_angular_speed",
			DEFAULT_EARTH_ORBIT_ANGULAR_SPEED
		)
		var speed_curve_exponent: float = _read_float(
			system_def,
			"speed_curve_exponent",
			DEFAULT_SPEED_CURVE_EXPONENT
		)
		var min_angular_speed: float = _read_float(
			system_def,
			"min_angular_speed",
			DEFAULT_MIN_ANGULAR_SPEED
		)
		var max_angular_speed: float = _read_float(
			system_def,
			"max_angular_speed",
			DEFAULT_MAX_ANGULAR_SPEED
		)

		var period_ratio: float = max(body_def.reference_period_days / EARTH_REFERENCE_PERIOD_DAYS, 0.01)
		var speed_factor: float = pow(period_ratio, -speed_curve_exponent)
		var speed: float = earth_orbit_angular_speed * speed_factor
		speed *= max(body_def.gameplay_speed_bias, 0.01)

		return clamp(speed, min_angular_speed, max_angular_speed)

	return body_def.orbit_speed


static func _has_calculated_size_input(body_def: SystemBodyDefinition) -> bool:
	return body_def.authored_ratio_to_earth > 0.0 or body_def.reference_radius_earth > 0.0


static func _get_target_body_diameter_px(
	body_def: SystemBodyDefinition,
	system_def: SystemDefinition
) -> float:
	var earth_target_body_diameter_px: float = _read_float(
		system_def,
		"earth_target_body_diameter_px",
		DEFAULT_EARTH_TARGET_BODY_DIAMETER_PX
	)
	var size_curve_exponent: float = _read_float(
		system_def,
		"size_curve_exponent",
		DEFAULT_SIZE_CURVE_EXPONENT
	)
	var minimum_body_diameter_px: float = _read_float(
		system_def,
		"minimum_body_diameter_px",
		DEFAULT_MINIMUM_BODY_DIAMETER_PX
	)

	var ratio: float = _resolve_size_ratio(body_def)
	var compressed_ratio: float = pow(max(ratio, MIN_RATIO), size_curve_exponent)
	var target: float = earth_target_body_diameter_px * compressed_ratio
	target *= max(body_def.gameplay_size_bias, 0.01)

	return max(target, minimum_body_diameter_px)


static func _resolve_size_ratio(body_def: SystemBodyDefinition) -> float:
	match body_def.size_authoring_mode:
		SystemBodyDefinition.SizeAuthoringMode.USE_ASSET_RATIO:
			if body_def.authored_ratio_to_earth > 0.0:
				return body_def.authored_ratio_to_earth

		SystemBodyDefinition.SizeAuthoringMode.USE_REFERENCE_DATA:
			if body_def.reference_radius_earth > 0.0:
				return body_def.reference_radius_earth

		SystemBodyDefinition.SizeAuthoringMode.AUTO:
			if body_def.authored_ratio_to_earth > 0.0:
				return body_def.authored_ratio_to_earth
			if body_def.reference_radius_earth > 0.0:
				return body_def.reference_radius_earth

	if body_def.body_scale > 0.0:
		return body_def.body_scale

	return 1.0


static func _get_asset_body_diameter_px(body_def: SystemBodyDefinition) -> float:
	if body_def.asset_body_diameter_px > 0.0:
		return body_def.asset_body_diameter_px

	if body_def.texture != null:
		var texture_width: int = body_def.texture.get_width()
		var texture_height: int = body_def.texture.get_height()
		return float(min(texture_width, texture_height))

	return 0.0


static func _read_float(obj: Object, property_name: String, default_value: float) -> float:
	if obj == null:
		return default_value

	var value: Variant = obj.get(property_name)
	if value == null:
		return default_value

	if value is float:
		return value
	if value is int:
		return float(value)

	return default_value
