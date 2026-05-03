class_name ShipStateStore
extends RefCounted

var system_states: Dictionary = {}


func get_or_create_ship_state(system_id: String) -> ShipRuntimeState:
	if system_id.is_empty():
		return null

	var existing: Variant = system_states.get(system_id)

	if existing is ShipRuntimeState:
		return existing as ShipRuntimeState

	var state := ShipRuntimeState.new()
	system_states[system_id] = state
	return state


func get_ship_state(system_id: String) -> ShipRuntimeState:
	var existing: Variant = system_states.get(system_id)

	if existing is ShipRuntimeState:
		return existing as ShipRuntimeState

	return null


func can_leave_system(system_id: String) -> bool:
	if system_id.is_empty():
		return true

	var state := get_ship_state(system_id)

	if state == null:
		return true

	return not state.is_docked
