class_name AutomationStore
extends RefCounted

enum MissionType {
	SCAN,
	MINE,
}

var next_mission_id: int = 1
var missions: Dictionary = {}


func create_scan_mission(
	base_id: String,
	target_id: String,
	target_scan_state: String = "",
	scan_is_progression: bool = true,
) -> int:
	var mission_id := _create_mission(MissionType.SCAN, base_id, target_id)
	var mission: Dictionary = missions.get(mission_id, {})
	if not mission.is_empty():
		mission["target_scan_state"] = target_scan_state.strip_edges()
		mission["scan_is_progression"] = scan_is_progression
		missions[mission_id] = mission
	return mission_id


func create_mining_mission(base_id: String, target_id: String) -> int:
	return _create_mission(MissionType.MINE, base_id, target_id)


func get_mission(mission_id: int) -> Dictionary:
	return missions.get(mission_id, {})


func complete_mission(mission_id: int) -> Dictionary:
	if not missions.has(mission_id):
		return {}

	var mission: Dictionary = missions[mission_id]
	missions.erase(mission_id)
	return mission


func _create_mission(mission_type: MissionType, base_id: String, target_id: String) -> int:
	var mission_id := next_mission_id
	next_mission_id += 1

	missions[mission_id] = {
		"id": mission_id,
		"type": mission_type,
		"base_id": base_id,
		"target_id": target_id,
	}

	return mission_id


func to_save_data() -> Dictionary:
	var missions_out: Dictionary = {}

	for mission_id_variant: Variant in missions.keys():
		var mission_id := int(mission_id_variant)
		var mission_variant: Variant = missions[mission_id_variant]

		if not mission_variant is Dictionary:
			continue

		var mission: Dictionary = (mission_variant as Dictionary).duplicate(true)
		mission["id"] = mission_id
		mission["type"] = int(mission.get("type", MissionType.SCAN))
		missions_out[str(mission_id)] = mission

	return {
		"next_mission_id": next_mission_id,
		"missions": missions_out,
	}


func apply_save_data(data: Dictionary) -> void:
	missions.clear()
	next_mission_id = maxi(1, int(data.get("next_mission_id", 1)))

	var missions_variant: Variant = data.get("missions", {})

	if not missions_variant is Dictionary:
		return

	for mission_key_variant: Variant in (missions_variant as Dictionary).keys():
		var mission_id := int(str(mission_key_variant))
		var mission_variant: Variant = (missions_variant as Dictionary)[mission_key_variant]

		if mission_id < 1 or not mission_variant is Dictionary:
			continue

		var mission: Dictionary = (mission_variant as Dictionary).duplicate(true)
		mission["id"] = mission_id
		mission["type"] = int(mission.get("type", MissionType.SCAN))
		missions[mission_id] = mission
		next_mission_id = maxi(next_mission_id, mission_id + 1)


func restore_mission_record(mission_id: int, mission_data: Dictionary) -> void:
	if mission_id < 1 or mission_data.is_empty():
		return

	var mission: Dictionary = mission_data.duplicate(true)
	mission["id"] = mission_id
	mission["type"] = int(mission.get("type", MissionType.SCAN))
	missions[mission_id] = mission
	next_mission_id = maxi(next_mission_id, mission_id + 1)
