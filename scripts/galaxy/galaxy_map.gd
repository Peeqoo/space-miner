extends Node2D

@export var camera_speed: float = 800.0
@export var zoom_min: float = 0.3
@export var zoom_max: float = 2.5
@export var zoom_step: float = 0.1
@export var zoom_smooth_speed: float = 8.0

@onready var camera: Camera2D = $Camera2D
@onready var system_name_label: Label = $UI/Control/VBoxContainer/SystemName
@onready var enter_button: Button = $UI/Control/VBoxContainer/EnterButton

var selected_system: SystemDefinition = null
var zoom_target: Vector2 = Vector2.ONE

func _ready() -> void:
	camera.make_current()
	zoom_target = camera.zoom

	enter_button.pressed.connect(_on_enter_pressed)
	enter_button.disabled = true

	system_name_label.text = "Kein System ausgewählt"

	if GameSession.current_system_definition == null:
		var default_system: SystemDefinition = preload("res://data/galaxy_systems/sol_system.tres")
		GameSession.current_system_definition = default_system
		GameSession.current_system_id = default_system.id
func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	camera.zoom = camera.zoom.lerp(zoom_target, zoom_smooth_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target(zoom_step)

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

func _zoom_target(amount: float) -> void:
	var new_zoom := zoom_target + Vector2(amount, amount)

	new_zoom.x = clamp(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clamp(new_zoom.y, zoom_min, zoom_max)

	zoom_target = new_zoom

func select_system(system_def: SystemDefinition) -> void:
	if system_def == null:
		return

	selected_system = system_def
	system_name_label.text = system_def.display_name
	enter_button.disabled = false

func _on_enter_pressed() -> void:
	if selected_system == null:
		if GameSession.current_system_definition != null:
			get_tree().change_scene_to_file("res://scenes/system/system_scene.tscn")
		return

	if selected_system.id == GameSession.current_system_id:
		GameSession.selected_system_definition = selected_system
		GameSession.arriving_from_travel = false
		get_tree().change_scene_to_file("res://scenes/system/system_scene.tscn")
		return

	var current_state: ShipState = GameSession.system_states.get(GameSession.current_system_id) as ShipState
	if current_state != null and current_state.is_docked:
		print("Abdocken notwendig zum Reisen")
		return

	GameSession.selected_system_definition = selected_system
	GameSession.arriving_from_travel = true
	get_tree().change_scene_to_file("res://scenes/system/system_scene.tscn")
