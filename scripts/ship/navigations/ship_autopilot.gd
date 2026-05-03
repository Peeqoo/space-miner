class_name ShipAutopilot
extends RefCounted

enum Mode {
	NONE,
	GOTO_POSITION,
	INTERACTION_APPROACH,
	ORBIT_APPROACH,
}

var mode: Mode = Mode.NONE
var target_node: Node2D = null
var desired_range: float = 0.0
var action_name: StringName = &""


func is_active() -> bool:
	return mode != Mode.NONE


func clear() -> void:
	mode = Mode.NONE
	target_node = null
	desired_range = 0.0
	action_name = &""


func begin_interaction_approach(
	p_target_node: Node2D,
	p_action_name: StringName,
	p_desired_range: float
) -> void:
	target_node = p_target_node
	action_name = p_action_name
	desired_range = p_desired_range
	mode = Mode.INTERACTION_APPROACH


func get_target_position() -> Vector2:
	if target_node == null or not is_instance_valid(target_node):
		clear()
		return Vector2.ZERO

	return target_node.global_position


func has_reached_range(ship: CharacterBody2D) -> bool:
	if target_node == null or not is_instance_valid(target_node):
		clear()
		return false

	return ship.global_position.distance_to(target_node.global_position) <= desired_range
