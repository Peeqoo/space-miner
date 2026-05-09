class_name AutomationStore
extends RefCounted

enum MissionType {
	SCAN,
	MINE,
}

var next_mission_id: int = 1
var missions: Dictionary = {}


func create_scan_mission(base_id: String, target_id: String) -> int:
	return _create_mission(MissionType.SCAN, base_id, target_id)


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
