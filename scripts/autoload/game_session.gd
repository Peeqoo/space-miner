extends Node

const DEFAULT_SYSTEM_PATH := "res://data/galaxy_systems/sol_system.tres"
const START_SYSTEM_ID: String = "sol"
const START_DOCK_BODY_ID: String = "earth"
const SCAN_UNKNOWN := "unknown"
const SCAN_BASIC := "basic"
const SCAN_DEEP := "deep"
const SCAN_SPECIAL := "special"


var current_system_definition: SystemDefinition = null
var selected_system_definition: SystemDefinition = null
var current_system_id: String = ""

var system_states: Dictionary = {}
var object_scan_states: Dictionary = {}
var entering_system_from_travel: bool = false


func _ready() -> void:
	ensure_default_system_loaded()
	
func ensure_boot_state() -> void:
	ensure_default_system_loaded()

	if current_system_id.is_empty():
		current_system_id = START_SYSTEM_ID

	var state: ShipRuntimeState = get_or_create_ship_state(current_system_id)
	if state == null:
		return

	var is_uninitialized: bool = state.docked_body_id.is_empty() and state.free_position == Vector2.ZERO
	if is_uninitialized:
		state.is_docked = true
		state.docked_body_id = START_DOCK_BODY_ID
		state.last_selected_object_id = START_DOCK_BODY_ID
		
func ensure_default_system_loaded() -> void:
	if current_system_definition != null:
		return

	var default_system := load(DEFAULT_SYSTEM_PATH) as SystemDefinition
	if default_system == null:
		push_error("Default-System konnte nicht geladen werden: %s" % DEFAULT_SYSTEM_PATH)
		return

	set_current_system(default_system)


func set_current_system(system_definition: SystemDefinition) -> void:
	if system_definition == null:
		return

	current_system_definition = system_definition
	current_system_id = system_definition.id


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


func get_or_create_ship_state(system_id: String) -> ShipRuntimeState:
	if system_id.is_empty():
		return null

	var existing: Variant = system_states.get(system_id)
	if existing is ShipRuntimeState:
		return existing as ShipRuntimeState

	var state: ShipRuntimeState = ShipRuntimeState.new()
	system_states[system_id] = state
	return state


func get_ship_state(system_id: String) -> ShipRuntimeState:
	var existing: Variant = system_states.get(system_id)
	if existing is ShipRuntimeState:
		return existing as ShipRuntimeState
	return null


func can_leave_current_system() -> bool:
	if current_system_id.is_empty():
		return true

	var state := get_ship_state(current_system_id)
	if state == null:
		return true

	return not state.is_docked


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

	var system_scan_state = object_scan_states.get(system_id, {})
	if system_scan_state is Dictionary:
		return str(system_scan_state.get(object_id, SCAN_UNKNOWN))

	return SCAN_UNKNOWN
