## Applies scan-drone / shared-scan-job fields to an ObjectInfo dictionary.
class_name ScanDroneInfoOverlay
extends RefCounted

const OVERLAY_KEYS: Array[StringName] = [
	ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE,
	ObjectInfoDictKeys.CAN_SCAN_WITH_DRONE,
	ObjectInfoDictKeys.SCAN_BLOCKED_REASON,
	ObjectInfoDictKeys.SCAN_BUTTON_TEXT,
	ObjectInfoDictKeys.ASSIGNED_SCAN_DRONE_COUNT,
	ObjectInfoDictKeys.SHOW_SCAN_DRONE_STATUS,
	ObjectInfoDictKeys.HAS_ACTIVE_SHARED_SCAN_JOB,
]


static func apply(
	info: Dictionary,
	selected_node: Node,
	object_id: String,
	system_id: String,
	base_id: String,
	automation_controller: AutomationController,
	has_available_drone: bool,
	scan_button_text: String,
	is_established_home_body: bool,
) -> void:
	info[ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE] = false
	info[ObjectInfoDictKeys.CAN_SCAN_WITH_DRONE] = false
	info[ObjectInfoDictKeys.SCAN_BLOCKED_REASON] = ""
	info[ObjectInfoDictKeys.SCAN_BUTTON_TEXT] = ""
	info[ObjectInfoDictKeys.ASSIGNED_SCAN_DRONE_COUNT] = 0
	info[ObjectInfoDictKeys.SHOW_SCAN_DRONE_STATUS] = false
	info[ObjectInfoDictKeys.HAS_ACTIVE_SHARED_SCAN_JOB] = false

	if selected_node == null:
		return

	if selected_node is SignalMarker:
		return

	if not selected_node is SystemBody and not selected_node is PointOfInterest:
		return

	if selected_node is SystemBody and is_established_home_body:
		return

	var sys_id: String = system_id.strip_edges()
	var target_id: String = object_id.strip_edges()
	if sys_id.is_empty() or target_id.is_empty():
		return

	var economy_base_id: String = base_id.strip_edges()
	var has_active_job: bool = _has_active_shared_scan_job_for_target(
		automation_controller,
		target_id,
	)
	var assigned_count: int = _get_assigned_scan_drone_count(automation_controller, target_id)
	info[ObjectInfoDictKeys.ASSIGNED_SCAN_DRONE_COUNT] = assigned_count
	info[ObjectInfoDictKeys.HAS_ACTIVE_SHARED_SCAN_JOB] = has_active_job

	var scan_gate: Dictionary = GameSession.can_scan_object(
		sys_id,
		target_id,
		economy_base_id,
		has_available_drone,
		has_active_job,
	)
	var target_state: String = str(scan_gate.get("target_scan_state", "")).strip_edges()
	var show_scan_button: bool = not target_state.is_empty()

	if has_active_job:
		var assign_gate: Dictionary = _get_assign_scan_drone_gate(automation_controller, target_id)
		info[ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE] = true
		info[ObjectInfoDictKeys.CAN_SCAN_WITH_DRONE] = bool(assign_gate.get("ok", false))
		info[ObjectInfoDictKeys.SCAN_BLOCKED_REASON] = str(
			assign_gate.get("blocked_reason", "")
		).strip_edges()
	elif show_scan_button:
		info[ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE] = true
		info[ObjectInfoDictKeys.CAN_SCAN_WITH_DRONE] = bool(scan_gate.get("ok", false))
		info[ObjectInfoDictKeys.SCAN_BLOCKED_REASON] = str(
			scan_gate.get("blocked_reason", "")
		).strip_edges()

	if bool(info.get(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE, false)):
		info[ObjectInfoDictKeys.SCAN_BUTTON_TEXT] = scan_button_text.strip_edges()

	info[ObjectInfoDictKeys.SHOW_SCAN_DRONE_STATUS] = (
		bool(info.get(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE, false)) or assigned_count > 0
	)


static func _get_assigned_scan_drone_count(
	automation_controller: AutomationController,
	object_id: String,
) -> int:
	if object_id.is_empty() or automation_controller == null:
		return 0
	return automation_controller.get_assigned_scan_drone_count_for_target(object_id)


static func _has_active_shared_scan_job_for_target(
	automation_controller: AutomationController,
	object_id: String,
) -> bool:
	if object_id.is_empty() or automation_controller == null:
		return false
	return automation_controller.has_active_shared_scan_job_for_target(object_id)


static func _get_assign_scan_drone_gate(
	automation_controller: AutomationController,
	object_id: String,
) -> Dictionary:
	if object_id.is_empty() or automation_controller == null:
		return {"ok": false, "blocked_reason": "", "blocked_reason_key": &""}
	return automation_controller.can_assign_scan_drone_to_shared_job(object_id)
