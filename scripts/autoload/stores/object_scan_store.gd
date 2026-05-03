## Stores scan states per object and system.
## Keeps object discovery progress out of GameSession.
class_name ObjectScanStore
extends RefCounted


# --------------------------------------------------
# Constants
# --------------------------------------------------

const SCAN_UNKNOWN := "unknown"
const SCAN_BASIC := "basic"
const SCAN_DEEP := "deep"
const SCAN_SPECIAL := "special"


# --------------------------------------------------
# State
# --------------------------------------------------

var object_scan_states: Dictionary = {}


# --------------------------------------------------
# Public API
# --------------------------------------------------

func set_object_scan_state(system_id: String, object_id: String, scan_state: String) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not object_scan_states.has(system_id):
		object_scan_states[system_id] = {}

	var system_scan_state: Dictionary = object_scan_states[system_id]
	system_scan_state[object_id] = scan_state
	object_scan_states[system_id] = system_scan_state


func get_object_scan_state(system_id: String, object_id: String) -> String:
	if system_id.is_empty() or object_id.is_empty():
		return SCAN_UNKNOWN

	var system_scan_state: Variant = object_scan_states.get(system_id, {})

	if system_scan_state is Dictionary:
		return str(system_scan_state.get(object_id, SCAN_UNKNOWN))

	return SCAN_UNKNOWN
