extends Node2D

@export var system_definition: SystemDefinition
@export var auto_sync_collision_to_sprite: bool = true
@export var collision_padding: float = 1.15
@export var min_collision_radius: float = 8.0
@export var debug_collision_sync: bool = false

@onready var area: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var selection_ring: CanvasItem = get_node_or_null("SelectionRing") as CanvasItem
@onready var body_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	add_to_group("galaxy_system_node")

	area.input_pickable = true
	if not area.input_event.is_connected(_on_click):
		area.input_event.connect(_on_click)

	_apply_star_presentation()
	call_deferred("_sync_collision_to_sprite")
	set_selected(false)
	apply_progression_state()


func _apply_star_presentation() -> void:
	if system_definition == null:
		return
	if body_sprite != null:
		if system_definition.star_texture != null:
			body_sprite.texture = system_definition.star_texture
		body_sprite.scale = system_definition.star_scale
	_sync_collision_to_sprite()


func _sync_collision_to_sprite() -> void:
	if not auto_sync_collision_to_sprite:
		return
	if not is_instance_valid(body_sprite):
		return
	if not is_instance_valid(area):
		return
	if not is_instance_valid(collision_shape):
		return
	if body_sprite.texture == null:
		return

	var texture_size := body_sprite.texture.get_size()

	if body_sprite.hframes > 1:
		texture_size.x /= float(body_sprite.hframes)
	if body_sprite.vframes > 1:
		texture_size.y /= float(body_sprite.vframes)

	var visual_size := Vector2(
		abs(texture_size.x * body_sprite.scale.x),
		abs(texture_size.y * body_sprite.scale.y),
	)

	var radius := maxf(visual_size.x, visual_size.y) * 0.5 * collision_padding
	radius = maxf(radius, min_collision_radius)

	# Fall A: Sprite2D and Area2D are siblings — move Area2D to sprite, shape at Area2D origin.
	area.position = body_sprite.position
	collision_shape.position = Vector2.ZERO

	var area_scale := area.scale
	var area_scale_max := maxf(abs(area_scale.x), abs(area_scale.y))
	if area_scale_max > 0.0001:
		radius /= area_scale_max

	# Per-instance shape — scene subresource must not be shared across instances.
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision_shape.shape = circle

	if debug_collision_sync:
		print(
			"GalaxySystemNode collision sync '%s': radius=%s sprite_scale=%s tex=%s area_pos=%s"
			% [
				str(system_definition.id if system_definition != null else "?"),
				radius,
				body_sprite.scale,
				texture_size,
				area.position,
			]
		)


## Used by GalaxyMap empty-space hit test; matches Area2D/CollisionShape2D in local space.
func contains_world_point(world_pt: Vector2) -> bool:
	if not is_instance_valid(area) or not is_instance_valid(collision_shape):
		return false
	var shape := collision_shape.shape
	if shape == null or not shape is CircleShape2D:
		return false
	var circle := shape as CircleShape2D
	var local_pt := area.to_local(world_pt)
	return local_pt.distance_to(collision_shape.position) <= circle.radius + 2.0


func refresh_presentation() -> void:
	_apply_star_presentation()
	_sync_collision_to_sprite()


func apply_progression_state() -> void:
	if system_definition == null:
		return

	if body_sprite != null:
		body_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		body_sprite.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_click(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var galaxy_map: Node = get_tree().get_first_node_in_group("galaxy_map_root")
			if galaxy_map != null and galaxy_map.has_method("is_pause_menu_open"):
				if galaxy_map.call("is_pause_menu_open"):
					return
			get_viewport().set_input_as_handled()
			_select_system()


func _select_system() -> void:
	if system_definition == null:
		push_warning("SystemNode ohne system_definition.")
		return

	var galaxy_map: Node = get_tree().get_first_node_in_group("galaxy_map_root")
	if galaxy_map == null:
		push_error("Kein galaxy_map_root gefunden.")
		return

	if galaxy_map.has_method("select_system"):
		galaxy_map.call("select_system", system_definition)


func set_selected(value: bool) -> void:
	if selection_ring != null:
		selection_ring.visible = value
