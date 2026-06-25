## Central StringName keys for ObjectInfoPanel `info` dictionaries (contract v0.1).
class_name ObjectInfoDictKeys
extends RefCounted

# --- 4.1 Identity & presentation ---
const ID: StringName = &"id"
const OBJECT_ID: StringName = &"object_id"
const DISPLAY_NAME: StringName = &"display_name"
const BODY_TYPE: StringName = &"body_type"
const POI_TYPE: StringName = &"poi_type"
const SCAN_STATE: StringName = &"scan_state"
const PREVIEW_TEXTURE: StringName = &"preview_texture"
const DISTANCE_TEXT: StringName = &"distance_text"
const LORE_TEXT: StringName = &"lore_text"

# --- 4.2 Scan / deposit resources (KNOWN) ---
const RESOURCES_VISIBLE: StringName = &"resources_visible"
const RESOURCES_HIDDEN_COUNT: StringName = &"resources_hidden_count"
const IS_SCANNED: StringName = &"is_scanned"

# --- 4.3 Scan drone / shared job ---
const SHOW_SCAN_WITH_DRONE: StringName = &"show_scan_with_drone"
const CAN_SCAN_WITH_DRONE: StringName = &"can_scan_with_drone"
const SCAN_BLOCKED_REASON: StringName = &"scan_blocked_reason"
const SCAN_BUTTON_TEXT: StringName = &"scan_button_text"
const ASSIGNED_SCAN_DRONE_COUNT: StringName = &"assigned_scan_drone_count"
const SHOW_SCAN_DRONE_STATUS: StringName = &"show_scan_drone_status"
const HAS_ACTIVE_SHARED_SCAN_JOB: StringName = &"has_active_shared_scan_job"
const ACTIVE_SCAN_DRONE_COUNT: StringName = &"active_scan_drone_count"
const SCAN_DRONE_SUPPORTING_COUNT: StringName = &"scan_drone_supporting_count"

# --- 4.4 Mining ship ---
const SHOW_MINE_WITH_SHIP: StringName = &"show_mine_with_ship"
const CAN_MINE_WITH_SHIP: StringName = &"can_mine_with_ship"
const MINE_BLOCKED_REASON: StringName = &"mine_blocked_reason"
const MINING_BUTTON_TEXT: StringName = &"mining_button_text"
const MINING_EXHAUSTED: StringName = &"mining_exhausted"
const ASSIGNED_MINING_SHIP_COUNT: StringName = &"assigned_mining_ship_count"
const SHOW_MINING_SHIP_STATUS: StringName = &"show_mining_ship_status"
const MINING_SHIP_MINING_COUNT: StringName = &"mining_ship_mining_count"
const MINING_BONUS: StringName = &"mining_bonus"
const MINING_YIELD_UPGRADE_BASE_ID: StringName = &"mining_yield_upgrade_base_id"
const ACTIVE_MINING_SHIP_COUNT: StringName = &"active_mining_ship_count"

# --- 4.5 Recall ---
const CAN_RECALL_DRONE: StringName = &"can_recall_drone"
const CAN_RECALL_MINING_SHIP: StringName = &"can_recall_mining_ship"

# --- 4.6 Home base / sensor pulse ---
const IS_HOME_BASE: StringName = &"is_home_base"
const SHOW_SENSOR_PULSE: StringName = &"show_sensor_pulse"
const CAN_SENSOR_PULSE: StringName = &"can_sensor_pulse"
const SENSOR_PULSE_BLOCKED_REASON: StringName = &"sensor_pulse_blocked_reason"
const SENSOR_PULSE_IN_PROGRESS: StringName = &"sensor_pulse_in_progress"
const SENSOR_PULSE_PROGRESS_TEXT: StringName = &"sensor_pulse_progress_text"
const SENSOR_PULSE_COST_TEXT: StringName = &"sensor_pulse_cost_text"

# --- 4.7 SIGNAL / discovery ---
const IS_DISCOVERY_SIGNAL: StringName = &"is_discovery_signal"
const IS_SIGNAL_MARKER: StringName = &"is_signal_marker"
const SIGNAL_TYPE: StringName = &"signal_type"
const SIGNAL_TYPE_ID: StringName = &"signal_type_id"
const SIGNAL_TYPE_DISPLAY_NAME: StringName = &"signal_type_display_name"
const SIGNAL_TYPE_SHORT_LABEL: StringName = &"signal_type_short_label"
const SIGNAL_DESCRIPTION: StringName = &"signal_description"
const CAN_INVESTIGATE_SIGNAL: StringName = &"can_investigate_signal"
const INVESTIGATE_BLOCKED_REASON: StringName = &"investigate_blocked_reason"
const INVESTIGATE_IN_PROGRESS: StringName = &"investigate_in_progress"
const IS_INVESTIGATE_ACTIVE: StringName = &"is_investigate_active"
const INVESTIGATE_PROGRESS: StringName = &"investigate_progress"
const INVESTIGATE_PROGRESS_TEXT: StringName = &"investigate_progress_text"
const DISCOVERY_COMPLETE_MESSAGE: StringName = &"discovery_complete_message"

# --- 4.8 Colonization & session gate ---
const COLONIZATION_BUTTON_VISIBLE: StringName = &"colonization_button_visible"
const COLONIZATION_PENDING: StringName = &"colonization_pending"
const COLONIZATION_CAN_START: StringName = &"colonization_can_start"
const SYSTEM_ID: StringName = &"system_id"
const SYSTEM_ECONOMY_BLOCKED_REASON: StringName = &"system_economy_blocked_reason"

## Keys written or read on the SIGNAL object-info path (smoke / contract).
const SIGNAL_KEYS: Array[StringName] = [
	ID,
	OBJECT_ID,
	DISPLAY_NAME,
	BODY_TYPE,
	SCAN_STATE,
	LORE_TEXT,
	IS_DISCOVERY_SIGNAL,
	IS_SIGNAL_MARKER,
	SIGNAL_TYPE,
	SIGNAL_TYPE_ID,
	SIGNAL_TYPE_DISPLAY_NAME,
	SIGNAL_TYPE_SHORT_LABEL,
	SIGNAL_DESCRIPTION,
	CAN_INVESTIGATE_SIGNAL,
	INVESTIGATE_BLOCKED_REASON,
	INVESTIGATE_IN_PROGRESS,
	IS_INVESTIGATE_ACTIVE,
	INVESTIGATE_PROGRESS,
	INVESTIGATE_PROGRESS_TEXT,
	CAN_SCAN_WITH_DRONE,
	CAN_MINE_WITH_SHIP,
	CAN_RECALL_DRONE,
	CAN_RECALL_MINING_SHIP,
]

## Keys the panel expects on every applied info dict (subset for smoke guards).
const SIGNAL_BUILDER_REQUIRED_KEYS: Array[StringName] = [
	ID,
	OBJECT_ID,
	DISPLAY_NAME,
	SCAN_STATE,
	LORE_TEXT,
	IS_DISCOVERY_SIGNAL,
	IS_SIGNAL_MARKER,
	CAN_INVESTIGATE_SIGNAL,
	INVESTIGATE_BLOCKED_REASON,
	INVESTIGATE_IN_PROGRESS,
	IS_INVESTIGATE_ACTIVE,
	INVESTIGATE_PROGRESS,
	INVESTIGATE_PROGRESS_TEXT,
]


static func signal_keys_have_duplicates() -> bool:
	var seen: Dictionary = {}
	for key: StringName in SIGNAL_KEYS:
		if seen.has(key):
			return true
		seen[key] = true
	return false
