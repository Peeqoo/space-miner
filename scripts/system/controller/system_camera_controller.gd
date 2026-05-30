class_name SystemCameraController
extends Camera2D

enum FrameMode {
	NONE,
	SYSTEM_FULL,
	MANUAL_OVERVIEW
}

# --------------------------------------------------
# Exports — Pan
# --------------------------------------------------

@export var keyboard_pan_speed: float = 600.0
@export var mouse_drag_pan_speed: float = 1.0
@export var acceleration: float = 8.0
@export var deceleration: float = 12.0
@export var max_pan_speed: float = 900.0
@export var allow_keyboard_pan: bool = true

# --------------------------------------------------
# Exports — Zoom
# --------------------------------------------------

@export var zoom_min: float = 0.2
@export var zoom_max: float = 2.0
@export var zoom_step: float = 0.1
@export var zoom_smooth_speed: float = 8.0

# --------------------------------------------------
# Exports — Framing
# --------------------------------------------------

@export var start_frame_mode: FrameMode = FrameMode.NONE
@export var auto_frame_on_ready: bool = true
@export var auto_frame_margin_pixels: float = 120.0
@export var overview_world_size: Vector2 = Vector2(1600.0, 900.0)

# --------------------------------------------------
# Internal State
# --------------------------------------------------

var zoom_target: Vector2 = Vector2.ONE
var _velocity: Vector2 = Vector2.ZERO
var _drag_relative: Vector2 = Vector2.ZERO
var _is_right_dragging: bool = false

## When enabled, camera lerps toward `focus_target` (selection / refocus). Manual pan turns this off.
var focus_target: Node2D = null
var follow_enabled: bool = false

@export var follow_smooth_speed: float = 5.0


func _ready() -> void:
	make_current()
	zoom_target = zoom

	if auto_frame_on_ready and not _should_skip_start_frame_for_pending_save():
		call_deferred("_apply_start_frame")


func _should_skip_start_frame_for_pending_save() -> bool:
	return GameSession.has_camera_state_pending_for_system(GameSession.current_system_id)


func _process(delta: float) -> void:
	if follow_enabled and (focus_target == null or not is_instance_valid(focus_target)):
		clear_focus_target()

	if follow_enabled and is_instance_valid(focus_target):
		var kb: Vector2 = _read_keyboard_input()
		var drag_pan_this_frame: bool = (
			_is_right_dragging and delta > 0.0 and _drag_relative.length_squared() > 0.0
		)

		if kb.length_squared() > 0.01 or drag_pan_this_frame:
			disable_follow_from_manual_input()
		else:
			global_position = global_position.lerp(
				focus_target.global_position,
				1.0 - exp(-follow_smooth_speed * delta)
			)
			_velocity = Vector2.ZERO
			_drag_relative = Vector2.ZERO
			zoom = zoom.lerp(zoom_target, clampf(zoom_smooth_speed * delta, 0.0, 1.0))
			return

	_handle_camera_movement(delta)
	zoom = zoom.lerp(zoom_target, clampf(zoom_smooth_speed * delta, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_right_dragging = mb.pressed
			# Consume right-press so it doesn't reach selection / UI.
			get_viewport().set_input_as_handled()
			return

		if not mb.pressed:
			return

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if get_viewport().gui_get_hovered_control() != null:
				return

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target(zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target(-zoom_step)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _is_right_dragging:
		_drag_relative += (event as InputEventMouseMotion).relative
		get_viewport().set_input_as_handled()


# --------------------------------------------------
# Movement
# --------------------------------------------------

func _handle_camera_movement(delta: float) -> void:
	var current_zoom: float = maxf(zoom.x, 0.01)
	var has_drag: bool = _drag_relative.length_squared() > 0.0 and delta > 0.0

	# --- Mouse drag: convert screen-pixel displacement to world velocity.
	# Dividing by delta turns "pixels this frame" into "pixels per second",
	# which is then scaled to world space by the current zoom level.
	# Result: the camera tracks the mouse 1:1 while dragging; the stored
	# _velocity gives natural momentum when the button is released.
	if has_drag:
		var drag_vel: Vector2 = -_drag_relative / delta / current_zoom * mouse_drag_pan_speed
		_velocity = drag_vel.limit_length(max_pan_speed)
		_drag_relative = Vector2.ZERO

		# Allow WASD to add on top of drag.
		if allow_keyboard_pan:
			var kb: Vector2 = _read_keyboard_input() * keyboard_pan_speed / current_zoom
			if kb.length_squared() > 0.01:
				_velocity = (_velocity + kb).limit_length(max_pan_speed)

		global_position += _velocity * delta
		return

	_drag_relative = Vector2.ZERO

	# --- Keyboard: smooth acceleration / deceleration via exponential lerp.
	if allow_keyboard_pan:
		var kb: Vector2 = _read_keyboard_input()

		if kb.length_squared() > 0.01:
			var desired: Vector2 = kb * keyboard_pan_speed / current_zoom
			desired = desired.limit_length(max_pan_speed)
			_velocity = _velocity.lerp(desired, 1.0 - exp(-acceleration * delta))
		else:
			_velocity = _velocity.lerp(Vector2.ZERO, 1.0 - exp(-deceleration * delta))
	else:
		_velocity = _velocity.lerp(Vector2.ZERO, 1.0 - exp(-deceleration * delta))

	if _velocity.length_squared() > 0.01:
		global_position += _velocity * delta


func _read_keyboard_input() -> Vector2:
	var v: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		v.y -= 1.0
	if Input.is_action_pressed("move_down"):
		v.y += 1.0
	if Input.is_action_pressed("move_left"):
		v.x -= 1.0
	if Input.is_action_pressed("move_right"):
		v.x += 1.0

	return v.normalized()


# --------------------------------------------------
# Public API (kept identical for callers in system_scene.gd)
# --------------------------------------------------

func set_start_position(world_position: Vector2) -> void:
	disable_follow_from_manual_input()
	global_position = world_position
	_velocity = Vector2.ZERO


func focus_world_position(world_position: Vector2) -> void:
	disable_follow_from_manual_input()
	global_position = world_position
	_velocity = Vector2.ZERO


func snap_to_position(world_position: Vector2) -> void:
	disable_follow_from_manual_input()
	global_position = world_position
	_velocity = Vector2.ZERO


func clear_follow() -> void:
	clear_focus_target()


func set_focus_target(target: Node2D, enable_follow: bool = true) -> void:
	focus_target = target
	follow_enabled = enable_follow and target != null and is_instance_valid(target)


func focus_current_target() -> void:
	follow_enabled = focus_target != null and is_instance_valid(focus_target)


func disable_follow_from_manual_input() -> void:
	follow_enabled = false


func clear_focus_target() -> void:
	focus_target = null
	follow_enabled = false


func to_save_state() -> Dictionary:
	return {
		"system_id": GameSession.current_system_id,
		"global_position": {"x": global_position.x, "y": global_position.y},
		"zoom": {"x": zoom.x, "y": zoom.y},
	}


func restore_saved_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false

	var pos_variant: Variant = state.get("global_position", null)

	if pos_variant is Dictionary:
		var pos_dict: Dictionary = pos_variant as Dictionary
		snap_to_position(
			Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
		)
	elif pos_variant is Vector2:
		snap_to_position(pos_variant as Vector2)

	var zoom_variant: Variant = state.get("zoom", null)

	if zoom_variant is Dictionary:
		var zoom_dict: Dictionary = zoom_variant as Dictionary
		var restored_zoom := Vector2(float(zoom_dict.get("x", 1.0)), float(zoom_dict.get("y", 1.0)))
		zoom = restored_zoom
		zoom_target = restored_zoom
	elif zoom_variant is Vector2:
		zoom = zoom_variant as Vector2
		zoom_target = zoom_variant as Vector2

	clear_focus_target()
	return true


# --------------------------------------------------
# Framing helpers
# --------------------------------------------------

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
	_velocity = Vector2.ZERO

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


# --------------------------------------------------
# Zoom
# --------------------------------------------------

func _zoom_target(amount: float) -> void:
	var new_zoom: Vector2 = zoom_target + Vector2(amount, amount)
	new_zoom.x = clampf(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clampf(new_zoom.y, zoom_min, zoom_max)
	zoom_target = new_zoom


# --------------------------------------------------
# Start framing
# --------------------------------------------------

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
