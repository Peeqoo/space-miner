## One-way survey probe: base orbit → target orbit (investigate) → destroyed (no return).
class_name SurveyProbeUnit
extends AutomationUnit

signal investigation_finished(unit: SurveyProbeUnit)
signal investigate_progress_changed(progress: float)

## Set true only when investigate work phase completes at the target.
var mission_succeeded: bool = false

var one_way_investigate: bool = false

var investigate_elapsed_seconds: float = 0.0
var investigate_duration_seconds: float = 1.0

var _last_emitted_progress_percent: int = -1


func _ready() -> void:
	unit_type = UnitType.SURVEY_PROBE
	super._ready()


func begin_investigate(duration_seconds: float) -> void:
	investigate_duration_seconds = maxf(0.1, duration_seconds)
	investigate_elapsed_seconds = 0.0
	work_duration = investigate_duration_seconds
	work_timer = 0.0
	_last_emitted_progress_percent = -1


func get_investigate_progress() -> float:
	if investigate_duration_seconds <= 0.0:
		return 0.0
	if state != State.WORKING:
		return 0.0
	return clampf(investigate_elapsed_seconds / investigate_duration_seconds, 0.0, 1.0)


func _process_travel_to_target(delta: float) -> void:
	if one_way_investigate and (target_node == null or not is_instance_valid(target_node)):
		push_warning("SurveyProbeUnit: target lost during travel to investigate target.")
		_fail_investigation()
		return
	super._process_travel_to_target(delta)


func _process_approach_orbit(delta: float) -> void:
	if one_way_investigate and (target_node == null or not is_instance_valid(target_node)):
		push_warning("SurveyProbeUnit: target lost during approach to investigate orbit.")
		_fail_investigation()
		return
	super._process_approach_orbit(delta)


func _process_working(delta: float) -> void:
	if not one_way_investigate:
		super._process_working(delta)
		return

	if target_node == null or not is_instance_valid(target_node):
		push_warning("SurveyProbeUnit: target lost during investigate work phase.")
		_fail_investigation()
		return

	visible = true
	_update_target_orbit_motion(delta)

	investigate_elapsed_seconds += delta
	work_timer = investigate_elapsed_seconds
	_emit_investigate_progress_if_changed()

	if investigate_elapsed_seconds >= investigate_duration_seconds:
		mission_succeeded = true
		investigate_progress_changed.emit(1.0)
		investigation_finished.emit(self)


func _process_returning(delta: float) -> void:
	if one_way_investigate:
		_fail_investigation()
		return
	super._process_returning(delta)


func _update_target_orbit_motion(delta: float) -> void:
	target_position = target_node.global_position
	orbit_angle += orbit_speed * orbit_direction * delta

	var raw_orbit_offset := _build_raw_orbit_offset()
	var local_offset := raw_orbit_offset.rotated(orbit_rotation)

	global_position = target_position + local_offset
	_set_visual_rotation(local_offset.angle())
	_keep_probe_on_free_flight_layer()


## Survey probes must not reparent into hidden SystemBody orbit layers during investigate.
func _update_orbit_render_layer(raw_orbit_offset: Vector2) -> void:
	if one_way_investigate:
		_keep_probe_on_free_flight_layer()
		return
	super._update_orbit_render_layer(raw_orbit_offset)


func _keep_probe_on_free_flight_layer() -> void:
	_move_to_free_flight_parent()
	visible = true
	if visual_root != null:
		visual_root.visible = true
		var sprite := visual_root.get_node_or_null("ProbeSprite") as CanvasItem
		if sprite != null:
			sprite.visible = true


func _emit_investigate_progress_if_changed() -> void:
	var progress := get_investigate_progress()
	var percent: int = int(floor(progress * 100.0))
	if percent == _last_emitted_progress_percent:
		return
	_last_emitted_progress_percent = percent
	investigate_progress_changed.emit(progress)


func _fail_investigation() -> void:
	mission_succeeded = false
	investigation_finished.emit(self)
