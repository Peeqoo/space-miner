## Builds ObjectInfo dictionaries for discovery SIGNAL markers (investigate overlay).
class_name SignalObjectInfoBuilder
extends RefCounted


static func build(
	signal_marker: SignalMarker,
	survey_probe_controller: SurveyProbeMissionController,
	base_id: String,
) -> Dictionary:
	var info: Dictionary = signal_marker.build_signal_info()
	var object_id: String = signal_marker.object_id.strip_edges()
	var economy_base_id: String = base_id.strip_edges()

	var can_investigate: bool = false
	var blocked_reason: String = ""
	var in_progress: bool = false

	if survey_probe_controller != null:
		in_progress = survey_probe_controller.is_investigate_active(object_id)
		var gate: Dictionary = survey_probe_controller.can_investigate_signal(
			object_id,
			economy_base_id,
		)
		can_investigate = gate.get("ok", false) == true
		blocked_reason = str(gate.get("blocked_reason", "")).strip_edges()
	else:
		blocked_reason = DiscoverySignalUiTextDefinition.get_template(
			SurveyProbeMissionController.REASON_BASE_MISSING
		)

	if in_progress and not can_investigate and blocked_reason.is_empty():
		blocked_reason = DiscoverySignalUiTextDefinition.get_template(
			SurveyProbeMissionController.REASON_IN_PROGRESS
		)

	info[ObjectInfoDictKeys.CAN_INVESTIGATE_SIGNAL] = can_investigate
	info[ObjectInfoDictKeys.INVESTIGATE_BLOCKED_REASON] = blocked_reason
	info[ObjectInfoDictKeys.INVESTIGATE_IN_PROGRESS] = in_progress

	if in_progress:
		info[ObjectInfoDictKeys.LORE_TEXT] = DiscoverySignalUiTextDefinition.get_template(
			DiscoverySignalUiTextDefinition.KEY_INVESTIGATE_LORE_ACTIVE
		)
		info[ObjectInfoDictKeys.SCAN_STATE] = GameSession.SCAN_UNKNOWN

	info[ObjectInfoDictKeys.IS_INVESTIGATE_ACTIVE] = in_progress
	var progress: float = 0.0
	if in_progress and survey_probe_controller != null:
		progress = survey_probe_controller.get_investigation_progress(object_id)
	info[ObjectInfoDictKeys.INVESTIGATE_PROGRESS] = progress
	info[ObjectInfoDictKeys.INVESTIGATE_PROGRESS_TEXT] = (
		DiscoverySignalUiTextDefinition.format_investigate_progress(
			int(round(progress * 100.0))
		)
	)

	return info
