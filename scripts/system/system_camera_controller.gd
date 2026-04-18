class_name SystemCameraController
extends Camera2D

@export var camera_speed: float = 600.0
@export var zoom_min: float = 0.3
@export var zoom_max: float = 2.0
@export var zoom_step: float = 0.1
@export var zoom_smooth_speed: float = 8.0

var zoom_target: Vector2 = Vector2.ONE
var follow_target: Node2D = null
var follow_enabled: bool = false

func _ready() -> void:
	make_current()
	zoom_target = zoom

func _process(delta: float) -> void:
	_handle_camera_movement(delta)

	if follow_enabled and follow_target != null:
		global_position = follow_target.global_position

	zoom = zoom.lerp(zoom_target, zoom_smooth_speed * delta)

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

	if input_vector != Vector2.ZERO:
		follow_enabled = false
		global_position += input_vector * camera_speed * delta

func set_follow_target(target: Node2D, enable_follow: bool = true) -> void:
	follow_target = target
	follow_enabled = enable_follow

	if follow_target != null and follow_enabled:
		global_position = follow_target.global_position

func clear_follow() -> void:
	follow_enabled = false
	follow_target = null

func set_start_position(target: Node2D) -> void:
	if target == null:
		return

	global_position = target.global_position

func _zoom_target(amount: float) -> void:
	var new_zoom := zoom_target + Vector2(amount, amount)
	new_zoom.x = clamp(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clamp(new_zoom.y, zoom_min, zoom_max)
	zoom_target = new_zoom
