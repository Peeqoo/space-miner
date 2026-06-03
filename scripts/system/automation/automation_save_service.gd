## Save-v1 write path for `game_session.automation.runtime`. No restore, store, or gameplay logic.
class_name AutomationSaveService
extends RefCounted


func build_runtime_save_data(
	system_id: String,
	primary_base_id: String,
	session_base_id: String,
	scan_drone_target_by_unit_id: Dictionary,
	active_units_by_mission_id: Dictionary,
	mining_ship_runtime_by_unit_id: Dictionary,
	resolve_unit_from_id: Callable,
	get_object_id_from_node: Callable,
	runtime_base_id_with_session_fallback: Callable,
) -> Dictionary:
	return {
		"system_id": system_id,
		"primary_base_id": primary_base_id,
		"scan_missions": build_scan_missions_array(
			scan_drone_target_by_unit_id,
			active_units_by_mission_id,
			session_base_id,
			resolve_unit_from_id,
			get_object_id_from_node,
		),
		"mining_missions": build_mining_missions_array(
			mining_ship_runtime_by_unit_id,
			session_base_id,
			resolve_unit_from_id,
			get_object_id_from_node,
			runtime_base_id_with_session_fallback,
		),
	}


func build_scan_missions_array(
	scan_drone_target_by_unit_id: Dictionary,
	active_units_by_mission_id: Dictionary,
	session_base_id: String,
	resolve_unit_from_id: Callable,
	get_object_id_from_node: Callable,
) -> Array:
	var jobs: Array = []
	var mission_id_by_unit: Dictionary = {}
	var saved_unit_ids: Dictionary = {}

	for mission_id_variant: Variant in active_units_by_mission_id.keys():
		var mission_id := int(mission_id_variant)
		var unit_variant: Variant = active_units_by_mission_id[mission_id_variant]
		var unit := unit_variant as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		mission_id_by_unit[unit.get_instance_id()] = mission_id

	for unit_id_variant: Variant in scan_drone_target_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var unit: AutomationUnit = resolve_unit_from_id.call(unit_id) as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		var target_id: String = str(scan_drone_target_by_unit_id.get(unit_id, "")).strip_edges()

		if target_id.is_empty():
			continue

		var mission_id_saved: int = int(mission_id_by_unit.get(unit_id, 0))
		var job: Dictionary = build_scan_job_save_dict(
			unit,
			target_id,
			mission_id_saved,
			session_base_id,
			active_units_by_mission_id,
			get_object_id_from_node,
		)

		if not job.is_empty():
			jobs.append(job)
			saved_unit_ids[unit_id] = true

	for mission_id_variant: Variant in active_units_by_mission_id.keys():
		var unit := active_units_by_mission_id[mission_id_variant] as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		if unit.unit_type != AutomationUnit.UnitType.DRONE:
			continue

		var unit_id := unit.get_instance_id()

		if saved_unit_ids.has(unit_id):
			continue

		var target_id_fallback: String = str(scan_drone_target_by_unit_id.get(unit_id, "")).strip_edges()

		if target_id_fallback.is_empty():
			continue

		var job_fallback: Dictionary = build_scan_job_save_dict(
			unit,
			target_id_fallback,
			int(mission_id_variant),
			session_base_id,
			active_units_by_mission_id,
			get_object_id_from_node,
		)

		if not job_fallback.is_empty():
			jobs.append(job_fallback)

	return jobs


func build_mining_missions_array(
	mining_ship_runtime_by_unit_id: Dictionary,
	session_base_id: String,
	resolve_unit_from_id: Callable,
	get_object_id_from_node: Callable,
	runtime_base_id_with_session_fallback: Callable,
) -> Array:
	var jobs: Array = []

	for unit_id_variant: Variant in mining_ship_runtime_by_unit_id.keys():
		var unit_id := int(unit_id_variant)
		var runtime_variant: Variant = mining_ship_runtime_by_unit_id[unit_id_variant]

		if not runtime_variant is Dictionary:
			continue

		var unit: AutomationUnit = resolve_unit_from_id.call(unit_id) as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		var job: Dictionary = build_mining_job_save_dict(
			unit,
			runtime_variant as Dictionary,
			session_base_id,
			get_object_id_from_node,
			runtime_base_id_with_session_fallback,
		)

		if not job.is_empty():
			jobs.append(job)

	return jobs


func build_scan_job_save_dict(
	unit: AutomationUnit,
	target_id: String,
	mission_id: int,
	session_base_id: String,
	active_units_by_mission_id: Dictionary,
	get_object_id_from_node: Callable,
) -> Dictionary:
	var home_base_id: String = session_base_id
	var orbit_anchor_id: String = home_base_id

	if unit.base_node != null and is_instance_valid(unit.base_node):
		var anchor_id: String = str(get_object_id_from_node.call(unit.base_node)).strip_edges()

		if not anchor_id.is_empty():
			orbit_anchor_id = anchor_id

	var scan_reveal_done := mission_id <= 0

	if not scan_reveal_done:
		scan_reveal_done = not active_units_by_mission_id.has(mission_id)

	var job := {
		"target_id": target_id,
		"base_id": home_base_id,
		"mission_id": mission_id,
		"orbit_anchor_id": orbit_anchor_id,
		"unit_state": int(unit.state),
		"work_timer": float(unit.work_timer),
		"work_duration": float(unit.work_duration),
		"travel_progress": float(unit.travel_progress),
		"scan_reveal_done": scan_reveal_done,
		"global_position": global_position_to_save_dict(unit.global_position),
		"orbit_angle": float(unit.orbit_angle),
		"orbit_direction": float(unit.orbit_direction),
		"orbit_radius_x": float(unit.orbit_radius_x),
		"orbit_radius_y": float(unit.orbit_radius_y),
		"orbit_speed": float(unit.orbit_speed),
		"orbit_rotation": float(unit.orbit_rotation),
		"travel_curve_side_sign": float(unit.travel_curve_side_sign),
	}

	return job


func build_mining_job_save_dict(
	unit: AutomationUnit,
	runtime: Dictionary,
	session_base_id: String,
	get_object_id_from_node: Callable,
	runtime_base_id_with_session_fallback: Callable,
) -> Dictionary:
	var job: Dictionary = sanitize_dictionary_for_save(runtime)
	job["target_id"] = str(runtime.get("target_id", ""))
	job["base_id"] = str(runtime_base_id_with_session_fallback.call(runtime))
	job["orbit_anchor_id"] = session_base_id

	if unit.base_node != null and is_instance_valid(unit.base_node):
		var anchor_id: String = str(get_object_id_from_node.call(unit.base_node)).strip_edges()

		if not anchor_id.is_empty():
			job["orbit_anchor_id"] = anchor_id

	job["unit_state"] = int(unit.state)
	job["work_timer"] = float(unit.work_timer)
	job["work_duration"] = float(unit.work_duration)
	job["travel_progress"] = float(unit.travel_progress)
	job["global_position"] = global_position_to_save_dict(unit.global_position)
	return job


func global_position_to_save_dict(position: Vector2) -> Dictionary:
	return {"x": position.x, "y": position.y}


func sanitize_dictionary_for_save(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}

	for key_variant: Variant in source.keys():
		var key_str: String = str(key_variant)
		var value_variant: Variant = source[key_variant]
		var sanitized: Variant = sanitize_value_for_save(value_variant)

		if sanitized != null:
			out[key_str] = sanitized

	return out


func sanitize_value_for_save(value: Variant) -> Variant:
	if value == null:
		return null

	if value is String or value is int or value is float or value is bool:
		return value

	if value is Dictionary:
		var out_dict: Dictionary = {}

		for nested_key: Variant in (value as Dictionary).keys():
			var nested_value: Variant = sanitize_value_for_save((value as Dictionary)[nested_key])

			if nested_value != null:
				out_dict[str(nested_key)] = nested_value

		return out_dict

	if value is Array:
		var out_arr: Array = []

		for item: Variant in value as Array:
			var sanitized_item: Variant = sanitize_value_for_save(item)

			if sanitized_item != null:
				out_arr.append(sanitized_item)

		return out_arr

	return null
