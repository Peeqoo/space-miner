extends Node2D

@export var system_definition: SystemDefinition

@export var camera_speed: float = 600.0
@export var zoom_speed: float = 0.1
@export var zoom_min: float = 0.3
@export var zoom_max: float = 2.0
@export var zoom_step: float = 0.1
@export var zoom_smooth_speed: float = 8.0

@onready var orbit_guides_layer: Node2D = $BackgroundRoot/OrbitGuidesLayer
@onready var star_root: Node2D = $WorldRoot/StarRoot
@onready var system_bodies_root: Node2D = $WorldRoot/SystemBodiesRoot
@onready var poi_root: Node2D = $WorldRoot/PointOfInterestRoot
@onready var player_ship: CharacterBody2D = $WorldRoot/PlayerShip
@onready var camera: Camera2D = $CameraRoot/SystemCamera2D
@onready var context_info_panel = $UI/ContextInfoPanel

var selected_node: Node = null
var spawned_lookup: Dictionary = {}
var star_visual: Sprite2D = null
var zoom_target: Vector2 = Vector2.ONE

const SYSTEM_BODY_SCENE: PackedScene = preload("res://scenes/system/objects/system_body.tscn")
const POINT_OF_INTEREST_SCENE: PackedScene = preload("res://scenes/system/objects/point_of_interest.tscn")

func _ready() -> void:
	camera.make_current()
	zoom_target = camera.zoom

	_spawn_from_definition()
	_setup_orbit_guides()

	player_ship.global_position = Vector2(0, 330)
	context_info_panel.show_empty()

func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	_setup_orbit_guides()

	camera.zoom = camera.zoom.lerp(zoom_target, zoom_smooth_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target(zoom_step)
			
func _zoom_target(amount: float) -> void:
	var new_zoom = zoom_target + Vector2(amount, amount)

	new_zoom.x = clamp(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clamp(new_zoom.y, zoom_min, zoom_max)

	zoom_target = new_zoom

func _handle_camera_movement(delta: float) -> void:
	var input_vector := Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1.0
	if Input.is_action_pressed("move_down"):
		input_vector.y += 1.0
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0

	input_vector = input_vector.normalized()
	camera.global_position += input_vector * camera_speed * delta

func _zoom_camera(amount: float) -> void:
	var new_zoom := camera.zoom + Vector2(amount, amount)
	new_zoom.x = clamp(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clamp(new_zoom.y, zoom_min, zoom_max)
	camera.zoom = new_zoom

func _spawn_from_definition() -> void:
	if system_definition == null:
		push_error("SystemDefinition fehlt auf SystemScene.")
		return

	_cleanup_spawned_content()

	spawned_lookup.clear()
	spawned_lookup["sun"] = star_root

	_setup_star_from_definition()
	_spawn_bodies_from_definition()
	_spawn_pois_from_definition()
	_resolve_orbit_centers_from_definition()

func _cleanup_spawned_content() -> void:
	for child in system_bodies_root.get_children():
		child.queue_free()

	for child in poi_root.get_children():
		child.queue_free()

	if star_visual != null and is_instance_valid(star_visual):
		star_visual.queue_free()
		star_visual = null

	selected_node = null

func _setup_star_from_definition() -> void:
	star_visual = Sprite2D.new()
	star_visual.name = "StarVisual"
	star_visual.centered = true
	star_visual.texture = system_definition.star_texture
	star_visual.scale = system_definition.star_scale
	star_visual.modulate = system_definition.star_modulate
	star_root.add_child(star_visual)

func _spawn_bodies_from_definition() -> void:
	for body_def in system_definition.bodies:
		if body_def == null:
			push_warning("Null-Eintrag in system_definition.bodies gefunden.")
			continue

		var body: SystemBody = SYSTEM_BODY_SCENE.instantiate()
		system_bodies_root.add_child(body)

		body.body_id = body_def.id
		body.display_name = body_def.display_name
		body.body_type = body_def.body_type

		if body_def.orbit_center_id == "sun":
			body.orbit_radius = system_definition.star_visual_radius + body_def.orbit_radius
		else:
			body.orbit_radius = body_def.orbit_radius

		body.orbit_speed = body_def.orbit_speed
		body.orbit_start_angle_degrees = body_def.orbit_start_angle_degrees

		body.body_scale = body_def.body_scale
		body.body_color = body_def.body_color

		var visual := body.get_node_or_null("OrbitPivot/BodyVisual") as Sprite2D
		if visual != null:
			visual.texture = body_def.texture
		else:
			push_warning("BodyVisual nicht gefunden für Body: %s" % body_def.id)

		body.apply_orbit_values()
		body.apply_definition_values()
		body.selected.connect(_on_body_selected)

		spawned_lookup[body_def.id] = body

func _spawn_pois_from_definition() -> void:
	for poi_def in system_definition.pois:
		if poi_def == null:
			push_warning("Null-Eintrag in system_definition.pois gefunden.")
			continue

		var poi: PointOfInterest = POINT_OF_INTEREST_SCENE.instantiate()
		poi_root.add_child(poi)

		poi.poi_id = poi_def.id
		poi.display_name = poi_def.display_name
		poi.poi_type = poi_def.poi_type

		if poi_def.orbit_center_id == "sun":
			poi.orbit_radius = system_definition.star_visual_radius + poi_def.orbit_radius
		else:
			poi.orbit_radius = poi_def.orbit_radius

		poi.orbit_speed = poi_def.orbit_speed
		poi.orbit_start_angle_degrees = poi_def.orbit_start_angle_degrees

		poi.poi_color = poi_def.poi_color

		var visual := poi.get_node_or_null("OrbitPivot/POIVisual") as Sprite2D
		if visual != null:
			visual.texture = poi_def.texture
		else:
			push_warning("POIVisual nicht gefunden für POI: %s" % poi_def.id)

		poi.apply_orbit_values()
		poi.apply_definition_values()
		poi.selected.connect(_on_poi_selected)

		spawned_lookup[poi_def.id] = poi

func _resolve_orbit_centers_from_definition() -> void:
	for body_def in system_definition.bodies:
		if body_def == null:
			continue

		var body := spawned_lookup.get(body_def.id) as SystemBody
		var center := spawned_lookup.get(body_def.orbit_center_id) as Node2D

		if body == null:
			push_warning("Spawned Body fehlt für ID: %s" % body_def.id)
			continue

		if center == null:
			push_warning("Orbit center fehlt für Body '%s' -> '%s'" % [body_def.id, body_def.orbit_center_id])
			continue

		body.set_orbit_center(center)

	for poi_def in system_definition.pois:
		if poi_def == null:
			continue

		var poi := spawned_lookup.get(poi_def.id) as PointOfInterest
		var center := spawned_lookup.get(poi_def.orbit_center_id) as Node2D

		if poi == null:
			push_warning("Spawned POI fehlt für ID: %s" % poi_def.id)
			continue

		if center == null:
			push_warning("Orbit center fehlt für POI '%s' -> '%s'" % [poi_def.id, poi_def.orbit_center_id])
			continue

		poi.set_orbit_center(center)

func _setup_orbit_guides() -> void:
	var orbit_entries: Array = []

	for child in system_bodies_root.get_children():
		var body := child as SystemBody
		if body == null or body.orbit_center == null:
			continue

		orbit_entries.append({
			"center": body.orbit_center.global_position,
			"radius": body.orbit_radius
		})

	for child in poi_root.get_children():
		var poi := child as PointOfInterest
		if poi == null or poi.orbit_center == null:
			continue

		orbit_entries.append({
			"center": poi.orbit_center.global_position,
			"radius": poi.orbit_radius
		})

	if orbit_guides_layer.has_method("set_orbits"):
		orbit_guides_layer.set_orbits(orbit_entries)

func _clear_selection() -> void:
	if selected_node == null:
		return

	if selected_node.has_method("set_selected"):
		selected_node.set_selected(false)

	selected_node = null

func _on_body_selected(body: SystemBody) -> void:
	_clear_selection()
	selected_node = body
	body.set_selected(true)
	context_info_panel.show_body_info(body.get_info())
	_send_ship_to_target(body.global_position)

func _on_poi_selected(poi: PointOfInterest) -> void:
	_clear_selection()
	selected_node = poi
	poi.set_selected(true)
	context_info_panel.show_poi_info(poi.get_info())
	_send_ship_to_target(poi.global_position)

func _send_ship_to_target(target: Vector2) -> void:
	var nav := player_ship.get_node_or_null("ShipNavigationComponent")
	if nav != null and nav.has_method("set_target"):
		nav.set_target(target)
