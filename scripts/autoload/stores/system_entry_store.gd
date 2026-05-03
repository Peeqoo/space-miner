## Stores temporary system-entry data while scenes are changing.
## Keeps staged travel flags out of GameSession.
class_name SystemEntryStore
extends RefCounted


# --------------------------------------------------
# State
# --------------------------------------------------

var selected_system_definition: SystemDefinition = null
var entering_system_from_travel: bool = false


# --------------------------------------------------
# Public API
# --------------------------------------------------

func stage_system_entry(system_definition: SystemDefinition, from_travel: bool) -> void:
	selected_system_definition = system_definition
	entering_system_from_travel = from_travel


func consume_selected_system_definition() -> SystemDefinition:
	var result := selected_system_definition
	selected_system_definition = null
	return result


func consume_travel_entry_flag() -> bool:
	var result := entering_system_from_travel
	entering_system_from_travel = false
	return result
