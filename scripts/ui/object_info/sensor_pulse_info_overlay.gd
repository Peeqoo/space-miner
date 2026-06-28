## Applies home-base sensor pulse fields to an ObjectInfo dictionary.
class_name SensorPulseInfoOverlay
extends RefCounted

const OVERLAY_KEYS: Array[StringName] = [
	ObjectInfoDictKeys.SHOW_SENSOR_PULSE,
	ObjectInfoDictKeys.CAN_SENSOR_PULSE,
	ObjectInfoDictKeys.SENSOR_PULSE_BLOCKED_REASON,
	ObjectInfoDictKeys.SENSOR_PULSE_IN_PROGRESS,
	ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT,
	ObjectInfoDictKeys.SENSOR_PULSE_COST_TEXT,
]


static func apply(
	info: Dictionary,
	base_sensor_pulse_controller: BaseSensorPulseController,
	base_id: String,
	is_home_base: bool,
) -> void:
	info[ObjectInfoDictKeys.SHOW_SENSOR_PULSE] = false
	info[ObjectInfoDictKeys.CAN_SENSOR_PULSE] = false
	info[ObjectInfoDictKeys.SENSOR_PULSE_BLOCKED_REASON] = ""
	info[ObjectInfoDictKeys.SENSOR_PULSE_IN_PROGRESS] = false
	info[ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT] = ""
	info[ObjectInfoDictKeys.SENSOR_PULSE_COST_TEXT] = ""

	if not is_home_base:
		return

	if base_sensor_pulse_controller == null:
		return

	var economy_base_id: String = base_id.strip_edges()
	var in_progress: bool = base_sensor_pulse_controller.is_pulse_active()
	info[ObjectInfoDictKeys.SENSOR_PULSE_IN_PROGRESS] = in_progress
	info[ObjectInfoDictKeys.SHOW_SENSOR_PULSE] = true

	if in_progress:
		var percent: int = base_sensor_pulse_controller.get_pulse_progress_percent()
		info[ObjectInfoDictKeys.SENSOR_PULSE_PROGRESS_TEXT] = (
			DiscoverySignalUiTextDefinition.format_sensor_pulse_progress(percent)
		)
		return

	info[ObjectInfoDictKeys.SENSOR_PULSE_COST_TEXT] = (
		base_sensor_pulse_controller.get_pulse_cost_display_text()
	)
	var gate: Dictionary = base_sensor_pulse_controller.can_start_sensor_pulse(economy_base_id)
	info[ObjectInfoDictKeys.CAN_SENSOR_PULSE] = bool(gate.get("ok", false))
	info[ObjectInfoDictKeys.SENSOR_PULSE_BLOCKED_REASON] = str(
		gate.get("blocked_reason", "")
	).strip_edges()
