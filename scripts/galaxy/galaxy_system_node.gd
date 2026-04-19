extends Node2D

@export var system_definition: SystemDefinition

@onready var area: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D


func _ready() -> void:
	area.input_pickable = true
	area.input_event.connect(_on_click)
	area.mouse_entered.connect(_on_mouse_entered)

	if collision_shape.shape == null:
		var circle := CircleShape2D.new()
		circle.radius = 24.0
		collision_shape.shape = circle

	if system_definition != null:
		print(name, " ready with system_definition = ", system_definition.id)
	else:
		print(name, " ready with NO system_definition")


func _on_click(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_select_system()


func _on_mouse_entered() -> void:
	if system_definition != null:
		print("Hover system: ", system_definition.id)


func _select_system() -> void:
	if system_definition == null:
		push_warning("SystemNode ohne system_definition.")
		return

	var galaxy_map: Node = get_tree().get_first_node_in_group("galaxy_map_root")
	if galaxy_map == null:
		push_error("Kein galaxy_map_root gefunden.")
		return

	if galaxy_map.has_method("select_system"):
		print("Select system: ", system_definition.id)
		galaxy_map.call("select_system", system_definition)
