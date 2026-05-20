extends Node2D

@export var system_definition: SystemDefinition

@onready var area: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var selection_ring: CanvasItem = get_node_or_null("SelectionRing") as CanvasItem
@onready var body_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	add_to_group("galaxy_system_node")

	area.input_pickable = true
	if not area.input_event.is_connected(_on_click):
		area.input_event.connect(_on_click)

	if collision_shape.shape == null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 24.0
		collision_shape.shape = circle

	_apply_star_presentation()
	set_selected(false)
	apply_progression_state()


func _apply_star_presentation() -> void:
	if system_definition == null:
		return
	if body_sprite != null:
		if system_definition.star_texture != null:
			body_sprite.texture = system_definition.star_texture
		body_sprite.scale = system_definition.star_scale
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		var circle: CircleShape2D = collision_shape.shape as CircleShape2D
		var vr: float = system_definition.star_visual_radius
		if vr > 0.0:
			circle.radius = clamp(sqrt(vr) * 4.4, 18.0, 120.0)


func apply_progression_state() -> void:
	if system_definition == null:
		return

	var is_unlocked: bool = GameSession.is_system_unlocked(system_definition.id)
	var canvas: CanvasItem = body_sprite if body_sprite != null else self
	if is_unlocked:
		canvas.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		canvas.modulate = Color(0.55, 0.55, 0.55, 0.55)


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
