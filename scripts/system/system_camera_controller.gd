class_name SystemCameraController
extends Camera2D

enum FrameMode {
	NONE,
	SYSTEM_FULL,
	MANUAL_OVERVIEW
}

@export var camera_speed: float = 600.0
@export var zoom_min: float = 0.2
@export var zoom_max: float = 2.0
@export var zoom_step: float = 0.1
@export var zoom_smooth_speed: float = 8.0
@export var allow_keyboard_pan: bool = true

@export var start_frame_mode: FrameMode = FrameMode.NONE
@export var auto_frame_on_ready: bool = true
@export var auto_frame_margin_pixels: float = 120.0
@export var overview_world_size: Vector2 = Vector2(1600.0, 900.0)

var zoom_target: Vector2 = Vector2.ONE


func _ready() -> void:
	make_current()
	zoom_target = zoom

	if auto_frame_on_ready:
		call_deferred("_apply_start_frame")


func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	zoom = zoom.lerp(zoom_target, clampf(zoom_smooth_speed * delta, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target(zoom_step)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target(-zoom_step)


func _handle_camera_movement(delta: float) -> void:
	if not allow_keyboard_pan:
		return

	var input_vector: Vector2 = Vector2.ZERO

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
		global_position += input_vector * camera_speed * delta


func set_start_position(world_position: Vector2) -> void:
	global_position = world_position


func focus_world_position(world_position: Vector2) -> void:
	global_position = world_position


func snap_to_position(world_position: Vector2) -> void:
	global_position = world_position


func clear_follow() -> void:
	pass


func set_follow_target(target: Node2D, _enable_follow: bool = true) -> void:
	if target == null:
		return

	global_position = target.global_position


func frame_nodes(nodes: Array[Node2D], margin_pixels: float = auto_frame_margin_pixels) -> void:
	if nodes.is_empty():
		return

	var rect_initialized: bool = false
	var min_pos: Vector2 = Vector2.ZERO
	var max_pos: Vector2 = Vector2.ZERO

	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue

		var p: Vector2 = node.global_position
		if not rect_initialized:
			min_pos = p
			max_pos = p
			rect_initialized = true
		else:
			min_pos.x = minf(min_pos.x, p.x)
			min_pos.y = minf(min_pos.y, p.y)
			max_pos.x = maxf(max_pos.x, p.x)
			max_pos.y = maxf(max_pos.y, p.y)

	if not rect_initialized:
		return

	var size: Vector2 = (max_pos - min_pos) + Vector2.ONE * margin_pixels
	var center: Vector2 = (min_pos + max_pos) * 0.5

	frame_rect(center, size)


func frame_rect(center: Vector2, world_size: Vector2) -> void:
	global_position = center

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var size_x: float = maxf(world_size.x, 1.0)
	var size_y: float = maxf(world_size.y, 1.0)

	var zoom_x: float = viewport_size.x / size_x
	var zoom_y: float = viewport_size.y / size_y
	var target_zoom_scalar: float = minf(zoom_x, zoom_y)

	target_zoom_scalar = clampf(target_zoom_scalar, zoom_min, zoom_max)

	zoom = Vector2.ONE * target_zoom_scalar
	zoom_target = zoom


func _apply_start_frame() -> void:
	match start_frame_mode:
		FrameMode.SYSTEM_FULL:
			var scene_root: Node = get_tree().current_scene
			if scene_root == null:
				return

			var candidates: Array[Node2D] = _collect_frame_nodes(scene_root)
			frame_nodes(candidates)

		FrameMode.MANUAL_OVERVIEW:
			frame_rect(global_position, overview_world_size)

		FrameMode.NONE:
			pass


func _collect_frame_nodes(root: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []

	for child in root.get_children():
		if child is Node2D:
			var node2d: Node2D = child as Node2D

			if node2d == self:
				continue

			if node2d.name == "CameraRoot":
				continue

			if node2d.name == "UI":
				continue

			result.append(node2d)

		result.append_array(_collect_frame_nodes(child))

	return result


func _zoom_target(amount: float) -> void:
	var new_zoom: Vector2 = zoom_target + Vector2(amount, amount)
	new_zoom.x = clampf(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clampf(new_zoom.y, zoom_min, zoom_max)
	zoom_target = new_zoom
