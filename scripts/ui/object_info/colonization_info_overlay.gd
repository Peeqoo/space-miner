## Applies colonization action fields to an ObjectInfo dictionary.
class_name ColonizationInfoOverlay
extends RefCounted

const OVERLAY_KEYS: Array[StringName] = [
	ObjectInfoDictKeys.COLONIZATION_BUTTON_VISIBLE,
	ObjectInfoDictKeys.COLONIZATION_PENDING,
	ObjectInfoDictKeys.COLONIZATION_CAN_START,
]


static func apply(
	info: Dictionary,
	system_id: String,
	object_id: String,
) -> void:
	info[ObjectInfoDictKeys.SYSTEM_ID] = system_id.strip_edges()
	info[ObjectInfoDictKeys.OBJECT_ID] = object_id.strip_edges()

	## v0.1: colonization starts from Galaxy map (system pick), not per-body in system view.
	info[ObjectInfoDictKeys.COLONIZATION_BUTTON_VISIBLE] = false
	info[ObjectInfoDictKeys.COLONIZATION_PENDING] = false
	info[ObjectInfoDictKeys.COLONIZATION_CAN_START] = false
