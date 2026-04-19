extends Node2D

@export var system_definition: SystemDefinition
@export var start_docked_body_id: String = "earth"

@onready var orbit_guides_layer: Node2D = $BackgroundRoot/OrbitGuidesLayer
@onready var star_root: Node2D = $WorldRoot/StarRoot
@onready var system_bodies_root: Node2D = $WorldRoot/SystemBodiesRoot
@onready var poi_root: Node2D = $WorldRoot/PointOfInterestRoot
@onready var player_ship: CharacterBody2D = $WorldRoot/PlayerShip
@onready var camera: SystemCameraController = $CameraRoot/SystemCamera2D
@onready var context_info_panel: PanelContainer = $UI/MarginContainer/ContextInfoPanel
@onready var back_button: Button = $UI/MarginContainer/ContextInfoPanel/VBoxContainer/BackButton
@onready var start_button: Button = $UI/MarginContainer/ShipControlPanel/VBoxContainer/StartButton
@onready var dock_button: Button = $UI/MarginContainer/ShipControlPanel/VBoxContainer/DockButton

const SYSTEM_BODY_SCENE: PackedScene = preload("res://scenes/system/objects/system_body.tscn")
const POINT_OF_INTEREST_SCENE: PackedScene = preload("res://scenes/system/objects/point_of_interest.tscn")

var selected_node: Node = null
var spawned_lookup: Dictionary = {}
var star_visual: Sprite2D = null
var docked_body: SystemBody = null
var is_docked: bool = true
var entered_from_travel: bool = false


func _ready() -> void:
	_resolve_active_system_definition()
	entered_from_travel = GameSession.consume_travel_entry_flag()

	if system_definition != null:
		GameSession.set_current_system(system_definition)

	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	dock_button.pressed.connect(_on_dock_pressed)

	_spawn_from_definition()
	_setup_orbit_guides()
	context_info_panel.show_empty()

	call_deferred("_finish_initial_setup")


func _finish_initial_setup() -> void:
	await _restore_ship_state()
	await _restore_camera_state()
	_update_ship_ui()


func _process(_delta: float) -> void:
	if system_definition == null:
		return

	if is_docked and docked_body != null:
		player_ship.global_position = docked_body.global_position
	else:
		var state := GameSession.get_or_create_ship_state(system_definition.id)
		if state != null:
			state.free_position = player_ship.global_position

	_setup_orbit_guides()


func _resolve_active_system_definition() -> void:
	var staged_system := GameSession.consume_selected_system_definition()
	if staged_system != null:
		system_definition = staged_system
		return

	if GameSession.current_system_definition != null:
		system_definition = GameSession.current_system_definition
		return

	GameSession.ensure_default_system_loaded()
	system_definition = GameSession.current_system_definition


func _get_ship_navigation() -> ShipNavigationComponent:
	return player_ship.get_node_or_null("ShipNavigationComponent") as ShipNavigationComponent


func _save_current_ship_state() -> void:
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


func _spawn_from_definition() -> void:
	if system_definition == null:
		push_error("SystemDefinition fehlt.")
		return

	spawned_lookup.clear()
	spawned_lookup["star"] = star_root

	_setup_star()
	_spawn_bodies()
	_spawn_pois()
	_resolve_orbits()


func _setup_star() -> void:
	star_visual = Sprite2D.new()
	star_visual.texture = system_definition.star_texture
	star_visual.scale = system_definition.star_scale
	star_visual.modulate = system_definition.star_modulate
	star_root.add_child(star_visual)


func _setup_orbit_guides() -> void:
	var orbit_entries: Array = []

	for child in system_bodies_root.get_children():
		var body := child as SystemBody
		if body == null or body.orbit_center == null:
			continue
		orbit_entries.append({"center": body.orbit_center.global_position, "radius": body.orbit_radius})

	for child in poi_root.get_children():
		var poi := child as PointOfInterest
		if poi == null or poi.orbit_center == null:
			continue
		orbit_entries.append({"center": poi.orbit_center.global_position, "radius": poi.orbit_radius})

	if orbit_guides_layer.has_method("set_orbits"):
		orbit_guides_layer.set_orbits(orbit_entries)


func _spawn_bodies() -> void:
	for body_def in system_definition.bodies:
		var body := SYSTEM_BODY_SCENE.instantiate() as SystemBody
		body.set_definition(body_def)

		if body_def.orbit_center_id == "star":
			body.orbit_radius = system_definition.star_visual_radius + body_def.orbit_radius

		system_bodies_root.add_child(body)
		body.selected.connect(_on_body_selected)
		spawned_lookup[body_def.id] = body


func _spawn_pois() -> void:
	for poi_def in system_definition.pois:
		var poi := POINT_OF_INTEREST_SCENE.instantiate() as PointOfInterest
		poi.set_definition(poi_def)

		if poi_def.orbit_center_id == "star":
			poi.orbit_radius = system_definition.star_visual_radius + poi_def.orbit_radius

		poi_root.add_child(poi)
		poi.selected.connect(_on_poi_selected)
		spawned_lookup[poi_def.id] = poi


func _resolve_orbits() -> void:
	for body_def in system_definition.bodies:
		var body := spawned_lookup.get(body_def.id) as SystemBody
		var center := spawned_lookup.get(body_def.orbit_center_id) as Node2D
		if body != null and center != null:
			body.set_orbit_center(center)
			body.refresh_orbit_position()

	for poi_def in system_definition.pois:
		var poi := spawned_lookup.get(poi_def.id) as PointOfInterest
		var center := spawned_lookup.get(poi_def.orbit_center_id) as Node2D
		if poi != null and center != null:
			poi.set_orbit_center(center)
			poi.refresh_orbit_position()


func _restore_ship_state() -> void:
	await get_tree().process_frame

	if system_definition == null:
		return

	if entered_from_travel:
		_spawn_at_entry()
		return

	var state := GameSession.get_or_create_ship_state(system_definition.id)
	if state == null:
		_dock_to_start_body()
		return

	if state.is_docked and not state.docked_body_id.is_empty():
		var body := spawned_lookup.get(state.docked_body_id) as SystemBody
		if body != null:
			_dock_to_body(body)
			_restore_last_selection(state)
			return

	if not state.is_docked:
		_restore_undocked(state.free_position)
		_restore_last_selection(state)
		return

	_dock_to_start_body()


func _restore_last_selection(state: ShipRuntimeState) -> void:
	if state == null or state.last_selected_object_id.is_empty():
		return

	var candidate: Node = spawned_lookup.get(state.last_selected_object_id) as Node
	if candidate == null:
		return

	if candidate is SystemBody:
		_on_body_selected(candidate)
	elif candidate is PointOfInterest:
		_on_poi_selected(candidate)


func _restore_camera_state() -> void:
	await get_tree().process_frame

	if is_docked and docked_body != null:
		camera.set_follow_target(docked_body, true)
		return

	camera.clear_follow()
	camera.set_start_position(player_ship)


func _spawn_at_entry() -> void:
	var angle: float = deg_to_rad(system_definition.entry_spawn_angle_degrees)
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	var spawn_position: Vector2 = star_root.global_position + direction * system_definition.entry_spawn_radius

	var state := GameSession.get_or_create_ship_state(system_definition.id)
	if state != null:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = spawn_position

	_restore_undocked(spawn_position)


func _restore_undocked(spawn_position: Vector2) -> void:
	is_docked = false
	docked_body = null
	player_ship.global_position = spawn_position

	var nav := _get_ship_navigation()
	if nav != null:
		nav.set_process(true)
		nav.clear_target()

	_update_ship_ui()


func _dock_to_start_body() -> void:
	var body := spawned_lookup.get(start_docked_body_id) as SystemBody
	if body != null:
		_dock_to_body(body)


func _dock_to_body(body: SystemBody) -> void:
	if body == null:
		return

	docked_body = body
	is_docked = true
	player_ship.global_position = body.global_position
	camera.set_follow_target(body, true)

	var nav := _get_ship_navigation()
	if nav != null:
		nav.set_process(false)
		nav.clear_target()

	var state := GameSession.get_or_create_ship_state(system_definition.id)
	if state != null:
		state.is_docked = true
		state.docked_body_id = body.body_id
		state.free_position = body.global_position

	_update_ship_ui()


func _launch_ship() -> void:
	if docked_body == null:
		return

	var launch_position := docked_body.global_position + Vector2.RIGHT * 80.0
	is_docked = false
	docked_body = null
	player_ship.global_position = launch_position
	camera.clear_follow()
	camera.set_start_position(player_ship)

	var nav := _get_ship_navigation()
	if nav != null:
		nav.set_process(true)
		nav.clear_target()

	var state := GameSession.get_or_create_ship_state(system_definition.id)
	if state != null:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = launch_position

	_update_ship_ui()


func _update_ship_ui() -> void:
	start_button.visible = is_docked
	dock_button.visible = not is_docked


func _clear_selection() -> void:
	if selected_node != null and selected_node.has_method("set_selected"):
		selected_node.set_selected(false)
	selected_node = null


func _on_body_selected(body: SystemBody) -> void:
	_clear_selection()
	selected_node = body
	body.set_selected(true)

	var info := body.get_info()
	info["scan_state"] = GameSession.get_object_scan_state(system_definition.id, body.body_id)
	context_info_panel.show_body_info(info)

	if not is_docked:
		_send_ship_to_target(body.global_position)


func _on_poi_selected(poi: PointOfInterest) -> void:
	_clear_selection()
	selected_node = poi
	poi.set_selected(true)

	var info := poi.get_info()
	info["scan_state"] = GameSession.get_object_scan_state(system_definition.id, poi.poi_id)
	context_info_panel.show_poi_info(info)

	if not is_docked:
		_send_ship_to_target(poi.global_position)


func _send_ship_to_target(target: Vector2) -> void:
	var nav := _get_ship_navigation()
	if nav != null:
		nav.set_target(target)


func _on_start_pressed() -> void:
	_launch_ship()


func _on_dock_pressed() -> void:
	if not (selected_node is SystemBody):
		return

	var body := selected_node as SystemBody
	if player_ship.global_position.distance_to(body.global_position) <= 100.0:
		_dock_to_body(body)


func _on_back_pressed() -> void:
	_save_current_ship_state()
	SceneFlow.goto_galaxy()
