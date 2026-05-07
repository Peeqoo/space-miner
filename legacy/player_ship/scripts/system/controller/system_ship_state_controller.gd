## Handles ship docking, launching, restoring and saving runtime state.
## Keeps ship runtime state logic out of SystemScene.
class_name SystemShipStateController
extends Node


# --------------------------------------------------
# Dependencies
# --------------------------------------------------

var system_definition: SystemDefinition
var start_docked_body_id: String
var player_ship: CharacterBody2D
var camera: SystemCameraController
var spawner: SystemSpawner
var ship_ui: SystemUIController


# --------------------------------------------------
# State
# --------------------------------------------------

var docked_body: SystemBody = null
var is_docked: bool = true


# --------------------------------------------------
# Setup
# --------------------------------------------------

func setup(
	p_system_definition: SystemDefinition,
	p_start_docked_body_id: String,
	p_player_ship: CharacterBody2D,
	p_camera: SystemCameraController,
	p_spawner: SystemSpawner,
	p_ship_ui: SystemUIController
) -> void:
	system_definition = p_system_definition
	start_docked_body_id = p_start_docked_body_id
	player_ship = p_player_ship
	camera = p_camera
	spawner = p_spawner
	ship_ui = p_ship_ui


# --------------------------------------------------
# Process Sync
# --------------------------------------------------

func sync_ship_position() -> void:
	if system_definition == null:
		return

	if is_docked and docked_body != null:
		player_ship.global_position = docked_body.global_position
		return

	var state := GameSession.get_or_create_ship_state(system_definition.id)

	if state != null:
		state.free_position = player_ship.global_position


# --------------------------------------------------
# Save / Restore
# --------------------------------------------------

func save_current_ship_state(selected_node: Node) -> void:
	if system_definition == null:
		return

	var state := GameSession.get_or_create_ship_state(system_definition.id)

	if state == null:
		return

	if is_docked and docked_body != null:
		state.is_docked = true
		state.docked_body_id = docked_body.body_id
		state.free_position = docked_body.global_position
	else:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = player_ship.global_position

	if selected_node is SystemBody:
		state.last_selected_object_id = (selected_node as SystemBody).body_id
	elif selected_node is PointOfInterest:
		state.last_selected_object_id = (selected_node as PointOfInterest).poi_id
	else:
		state.last_selected_object_id = ""


func restore_ship_state(entered_from_travel: bool) -> void:
	await get_tree().process_frame

	if system_definition == null:
		return

	if entered_from_travel:
		_spawn_at_entry()
		return

	var state := GameSession.get_or_create_ship_state(system_definition.id)

	if state == null:
		dock_to_start_body()
		return

	if state.is_docked and not state.docked_body_id.is_empty():
		var body := spawner.get_spawned_object(state.docked_body_id) as SystemBody

		if body != null:
			dock_to_body(body)
			return

	if not state.is_docked:
		restore_undocked(state.free_position)
		return

	dock_to_start_body()


func restore_camera_state() -> void:
	await get_tree().process_frame

	if is_docked and docked_body != null:
		camera.set_follow_target(docked_body, true)
		return

	camera.clear_follow()
	camera.set_start_position(player_ship.global_position)


# --------------------------------------------------
# Docking
# --------------------------------------------------

func dock_to_start_body() -> void:
	var body := spawner.get_spawned_object(start_docked_body_id) as SystemBody

	if body != null:
		dock_to_body(body)


func dock_to_body(body: SystemBody) -> void:
	if body == null:
		return

	docked_body = body
	is_docked = true

	player_ship.global_position = body.global_position
	camera.set_follow_target(body, true)

	var nav := get_ship_navigation()

	if nav != null:
		nav.set_process(false)
		nav.clear_target()

	var state := GameSession.get_or_create_ship_state(system_definition.id)

	if state != null:
		state.is_docked = true
		state.docked_body_id = body.body_id
		state.free_position = body.global_position

	ship_ui.update_ship_ui()


func launch_ship() -> void:
	if docked_body == null:
		return

	var launch_position := docked_body.global_position + Vector2.RIGHT * 80.0

	is_docked = false
	docked_body = null

	player_ship.global_position = launch_position

	camera.clear_follow()
	camera.set_start_position(player_ship.global_position)

	var nav := get_ship_navigation()

	if nav != null:
		nav.set_process(true)
		nav.clear_target()

	var state := GameSession.get_or_create_ship_state(system_definition.id)

	if state != null:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = launch_position

	ship_ui.update_ship_ui()


func restore_undocked(spawn_position: Vector2) -> void:
	is_docked = false
	docked_body = null

	player_ship.global_position = spawn_position

	var nav := get_ship_navigation()

	if nav != null:
		nav.set_process(true)
		nav.clear_target()

	ship_ui.update_ship_ui()


# --------------------------------------------------
# Helpers
# --------------------------------------------------

func get_ship_navigation() -> ShipNavigationComponent:
	return player_ship.get_node_or_null("ShipNavigationComponent") as ShipNavigationComponent


func _spawn_at_entry() -> void:
	var angle: float = deg_to_rad(system_definition.entry_spawn_angle_degrees)
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	var spawn_position: Vector2 = spawner.star_root.global_position + direction * system_definition.entry_spawn_radius

	var state := GameSession.get_or_create_ship_state(system_definition.id)

	if state != null:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = spawn_position

	restore_undocked(spawn_position)
