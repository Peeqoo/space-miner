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
	add_to_group("galaxy_map_root")
	camera.make_current()
	zoom_target = camera.zoom

	enter_button.pressed.connect(_on_enter_pressed)
	GameSession.ensure_default_system_loaded()

	if GameSession.current_system_definition != null:
		select_system(GameSession.current_system_definition)
	else:
		system_name_label.text = "Kein System ausgewählt"
		enter_button.disabled = true


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
	print("GalaxyMap selected_system -> ", system_def.id)

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
