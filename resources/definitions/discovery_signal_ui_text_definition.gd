## Data-driven UI strings for discovery signals and survey-probe investigate UI.
## Loaded from `data/ui_text/discovery_signal_ui_texts.tres` in GameSession.
class_name DiscoverySignalUiTextDefinition
extends Resource

const KEY_INVESTIGATE_PROGRESS := &"investigate_progress"
const KEY_INVESTIGATE_LORE_ACTIVE := &"investigate_lore_active"
const KEY_SIGNAL_LORE_FALLBACK := &"signal_lore_fallback"
const KEY_MARKER_LABEL_FALLBACK := &"marker_label_fallback"
const KEY_SIGNAL_OBJECT_TYPE_LABEL := &"signal_object_type_label"
const KEY_UNKNOWN_SIGNAL_NAME := &"unknown_signal_name"
const KEY_UNKNOWN_SIGNAL_TYPE := &"unknown_signal_type"
const KEY_UNKNOWN_SIGNAL_LORE := &"unknown_signal_lore"

const KEY_BLOCKED_NO_PROBE := &"blocked_no_probe"
const KEY_BLOCKED_NOT_SIGNAL := &"blocked_not_signal"
const KEY_BLOCKED_IN_PROGRESS := &"blocked_in_progress"
const KEY_BLOCKED_TARGET_MISSING := &"blocked_target_missing"
const KEY_BLOCKED_BASE_MISSING := &"blocked_base_missing"
const KEY_BLOCKED_ALREADY_KNOWN := &"blocked_already_known"
const KEY_BLOCKED_ACTIVE_PROBE_LIMIT := &"blocked_active_probe_limit"

const KEY_SENSOR_PULSE_BUTTON_LABEL := &"sensor_pulse_button_label"
const KEY_SENSOR_PULSE_PROGRESS := &"sensor_pulse_progress_format"
const KEY_SENSOR_PULSE_BLOCK_ACTIVE := &"sensor_pulse_block_active"
const KEY_SENSOR_PULSE_BLOCK_COOLDOWN := &"sensor_pulse_block_cooldown"
const KEY_SENSOR_PULSE_BLOCK_NO_HIDDEN := &"sensor_pulse_block_no_hidden"
const KEY_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA := &"sensor_pulse_block_not_enough_survey_data"
const KEY_SENSOR_PULSE_BLOCK_BASE_MISSING := &"sensor_pulse_block_base_missing"
const KEY_SENSOR_PULSE_COST_FORMAT := &"sensor_pulse_cost_format"

const FALLBACK_INVESTIGATE_PROGRESS := "Investigating: %d%%"
const FALLBACK_INVESTIGATE_LORE_ACTIVE := "Survey probe investigating this signal..."
const FALLBACK_SIGNAL_LORE := (
	"Unidentified signal. Survey required before this object can be analyzed."
)
const FALLBACK_MARKER_LABEL := "Signal"
const FALLBACK_SIGNAL_OBJECT_TYPE_LABEL := "Signal"
const FALLBACK_UNKNOWN_SIGNAL_NAME := "Unknown"
const FALLBACK_UNKNOWN_SIGNAL_TYPE := "Unknown"
const FALLBACK_UNKNOWN_SIGNAL_LORE := "Unknown signal detected by the base sensors."

const FALLBACK_BLOCKED_NO_PROBE := "No survey probe available"
const FALLBACK_BLOCKED_NOT_SIGNAL := "Target is not a signal"
const FALLBACK_BLOCKED_IN_PROGRESS := "Investigation already in progress"
const FALLBACK_BLOCKED_TARGET_MISSING := "Signal target missing"
const FALLBACK_BLOCKED_BASE_MISSING := "Base missing"
const FALLBACK_BLOCKED_ALREADY_KNOWN := "Object already discovered"
const FALLBACK_BLOCKED_ACTIVE_PROBE_LIMIT := "Active probe limit reached"

const FALLBACK_SENSOR_PULSE_BUTTON_LABEL := "Sensor Pulse"
const FALLBACK_SENSOR_PULSE_PROGRESS := "Scanning for signals: %d%%"
const FALLBACK_SENSOR_PULSE_BLOCK_ACTIVE := "Sensor pulse already active"
const FALLBACK_SENSOR_PULSE_BLOCK_COOLDOWN := "Sensor pulse cooling down"
const FALLBACK_SENSOR_PULSE_BLOCK_NO_HIDDEN := "No hidden signals detected"
const FALLBACK_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA := "Not enough Survey Data"
const FALLBACK_SENSOR_PULSE_BLOCK_BASE_MISSING := "No established base"
const FALLBACK_SENSOR_PULSE_COST_FORMAT := "Cost: %s"

@export var templates: Dictionary = {}

static var _global: DiscoverySignalUiTextDefinition


static func set_global(definition: DiscoverySignalUiTextDefinition) -> void:
	_global = definition


static func get_template(key: StringName) -> String:
	if _global != null:
		var from_data := str(_global.templates.get(key, "")).strip_edges()
		if not from_data.is_empty():
			return from_data
	return _fallback_for_key(key)


static func get_signal_object_type_label() -> String:
	return get_template(KEY_SIGNAL_OBJECT_TYPE_LABEL)


static func get_unknown_signal_name() -> String:
	return get_template(KEY_UNKNOWN_SIGNAL_NAME)


static func get_unknown_signal_lore() -> String:
	return get_template(KEY_UNKNOWN_SIGNAL_LORE)


static func format_investigate_progress(percent: int) -> String:
	var format_str := get_template(KEY_INVESTIGATE_PROGRESS)
	if format_str.is_empty():
		format_str = FALLBACK_INVESTIGATE_PROGRESS
	return format_str % maxi(0, percent)


static func format_sensor_pulse_progress(percent: int) -> String:
	var format_str := get_template(KEY_SENSOR_PULSE_PROGRESS)
	if format_str.is_empty():
		format_str = FALLBACK_SENSOR_PULSE_PROGRESS
	return format_str % maxi(0, percent)


static func format_sensor_pulse_cost(cost_summary: String) -> String:
	var summary := cost_summary.strip_edges()
	if summary.is_empty():
		return ""
	var format_str := get_template(KEY_SENSOR_PULSE_COST_FORMAT)
	if format_str.is_empty():
		format_str = FALLBACK_SENSOR_PULSE_COST_FORMAT
	return format_str % summary


static func _fallback_for_key(key: StringName) -> String:
	match key:
		KEY_INVESTIGATE_PROGRESS:
			return FALLBACK_INVESTIGATE_PROGRESS
		KEY_INVESTIGATE_LORE_ACTIVE:
			return FALLBACK_INVESTIGATE_LORE_ACTIVE
		KEY_SIGNAL_LORE_FALLBACK:
			return FALLBACK_SIGNAL_LORE
		KEY_MARKER_LABEL_FALLBACK:
			return FALLBACK_MARKER_LABEL
		KEY_SIGNAL_OBJECT_TYPE_LABEL:
			return FALLBACK_SIGNAL_OBJECT_TYPE_LABEL
		KEY_UNKNOWN_SIGNAL_NAME:
			return FALLBACK_UNKNOWN_SIGNAL_NAME
		KEY_UNKNOWN_SIGNAL_TYPE:
			return FALLBACK_UNKNOWN_SIGNAL_TYPE
		KEY_UNKNOWN_SIGNAL_LORE:
			return FALLBACK_UNKNOWN_SIGNAL_LORE
		KEY_BLOCKED_NO_PROBE:
			return FALLBACK_BLOCKED_NO_PROBE
		KEY_BLOCKED_NOT_SIGNAL:
			return FALLBACK_BLOCKED_NOT_SIGNAL
		KEY_BLOCKED_IN_PROGRESS:
			return FALLBACK_BLOCKED_IN_PROGRESS
		KEY_BLOCKED_TARGET_MISSING:
			return FALLBACK_BLOCKED_TARGET_MISSING
		KEY_BLOCKED_BASE_MISSING:
			return FALLBACK_BLOCKED_BASE_MISSING
		KEY_BLOCKED_ALREADY_KNOWN:
			return FALLBACK_BLOCKED_ALREADY_KNOWN
		KEY_BLOCKED_ACTIVE_PROBE_LIMIT:
			return FALLBACK_BLOCKED_ACTIVE_PROBE_LIMIT
		KEY_SENSOR_PULSE_BUTTON_LABEL:
			return FALLBACK_SENSOR_PULSE_BUTTON_LABEL
		KEY_SENSOR_PULSE_PROGRESS:
			return FALLBACK_SENSOR_PULSE_PROGRESS
		KEY_SENSOR_PULSE_BLOCK_ACTIVE:
			return FALLBACK_SENSOR_PULSE_BLOCK_ACTIVE
		KEY_SENSOR_PULSE_BLOCK_COOLDOWN:
			return FALLBACK_SENSOR_PULSE_BLOCK_COOLDOWN
		KEY_SENSOR_PULSE_BLOCK_NO_HIDDEN:
			return FALLBACK_SENSOR_PULSE_BLOCK_NO_HIDDEN
		KEY_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA:
			return FALLBACK_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA
		KEY_SENSOR_PULSE_BLOCK_BASE_MISSING:
			return FALLBACK_SENSOR_PULSE_BLOCK_BASE_MISSING
		KEY_SENSOR_PULSE_COST_FORMAT:
			return FALLBACK_SENSOR_PULSE_COST_FORMAT
		_:
			return ""
