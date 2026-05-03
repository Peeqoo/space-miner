extends Node

const DEFAULT_SYSTEM_PATH := "res://data/galaxy_systems/sol_system.tres"
const START_SYSTEM_ID: String = "sol"
const START_DOCK_BODY_ID: String = "earth"

const SCAN_UNKNOWN := ObjectScanStore.SCAN_UNKNOWN
const SCAN_BASIC := ObjectScanStore.SCAN_BASIC
const SCAN_DEEP := ObjectScanStore.SCAN_DEEP
const SCAN_SPECIAL := ObjectScanStore.SCAN_SPECIAL

var current_system_definition: SystemDefinition = null
var current_system_id: String = ""

var ship_states := ShipStateStore.new()
var object_scans := ObjectScanStore.new()
var system_entry := SystemEntryStore.new()


func _ready() -> void:
	ensure_default_system_loaded()


func ensure_boot_state() -> void:
	ensure_default_system_loaded()

	if current_system_id.is_empty():
		current_system_id = START_SYSTEM_ID

	var state := get_or_create_ship_state(current_system_id)

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
	system_entry.stage_system_entry(system_definition, from_travel)


func consume_selected_system_definition() -> SystemDefinition:
	return system_entry.consume_selected_system_definition()


func consume_travel_entry_flag() -> bool:
	return system_entry.consume_travel_entry_flag()


func get_or_create_ship_state(system_id: String) -> ShipRuntimeState:
	return ship_states.get_or_create_ship_state(system_id)


func get_ship_state(system_id: String) -> ShipRuntimeState:
	return ship_states.get_ship_state(system_id)


func can_leave_current_system() -> bool:
	return ship_states.can_leave_system(current_system_id)


func set_object_scan_state(system_id: String, object_id: String, scan_state: String) -> void:
	object_scans.set_object_scan_state(system_id, object_id, scan_state)


func get_object_scan_state(system_id: String, object_id: String) -> String:
	return object_scans.get_object_scan_state(system_id, object_id)
