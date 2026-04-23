extends Node2D

@export var start_center_system_id: String = "sol_system"
@export var start_zoom_world_size: Vector2 = Vector2(1600.0, 900.0)

@onready var camera: SystemCameraController = $CameraRoot/GalaxyCamera2D
@onready var system_name_label: Label = $UI/Control/VBoxContainer/SystemName
@onready var enter_button: Button = $UI/Control/VBoxContainer/EnterButton

var selected_system: SystemDefinition = null


func _ready() -> void:
	add_to_group("galaxy_map_root")

	camera.make_current()

	if not enter_button.pressed.is_connected(_on_enter_pressed):
		enter_button.pressed.connect(_on_enter_pressed)

	GameSession.ensure_default_system_loaded()

	if GameSession.current_system_definition != null:
		select_system(GameSession.current_system_definition)
	else:
		system_name_label.text = "Kein System ausgewählt"
		enter_button.disabled = true

	call_deferred("_center_camera_on_sol_system")


func select_system(system_def: SystemDefinition) -> void:
	if system_def == null:
		push_warning("select_system(): system_def ist null")
		return

	selected_system = system_def

	var is_current: bool = system_def.id == GameSession.current_system_id
	var can_enter: bool = is_current or GameSession.can_leave_current_system()

	enter_button.disabled = not can_enter

	var label_text: String = system_def.display_name
	if is_current:
		label_text += " (aktuell)"
	elif not can_enter:
		label_text += " (gesperrt: erst abdocken)"

	system_name_label.text = label_text


func _on_enter_pressed() -> void:
	if selected_system == null:
		push_warning("_on_enter_pressed(): kein selected_system")
		return

	var entering_current_system: bool = selected_system.id == GameSession.current_system_id

	if not entering_current_system and not GameSession.can_leave_current_system():
		push_warning("Systemwechsel blockiert: Schiff ist noch angedockt.")
		return

	GameSession.stage_system_entry(selected_system, not entering_current_system)

	if entering_current_system:
		GameSession.set_current_system(selected_system)

	SceneFlow.goto_system()


func _center_camera_on_sol_system() -> void:
	var sol_node: Node2D = _find_system_node_by_definition_id(start_center_system_id)

	if sol_node != null:
		camera.frame_rect(sol_node.global_position, start_zoom_world_size)
		return

	push_warning("Sol-System-Knoten nicht gefunden. Fallback auf aktuelle Auswahl.")
	if selected_system != null:
		var selected_node: Node2D = _find_system_node_by_definition_id(selected_system.id)
		if selected_node != null:
			camera.frame_rect(selected_node.global_position, start_zoom_world_size)


func _find_system_node_by_definition_id(system_id: String) -> Node2D:
	for child in get_children():
		var found: Node2D = _find_system_node_in_branch(child, system_id)
		if found != null:
			return found
	return null


func _find_system_node_in_branch(node: Node, system_id: String) -> Node2D:
	if node == null:
		return null

	if node.has_method("get"):
		var maybe_definition: Variant = node.get("system_definition")
		if maybe_definition is SystemDefinition:
			var system_def: SystemDefinition = maybe_definition as SystemDefinition
			if system_def != null and system_def.id == system_id and node is Node2D:
				return node as Node2D

	for child in node.get_children():
		var found: Node2D = _find_system_node_in_branch(child, system_id)
		if found != null:
			return found

	return null
