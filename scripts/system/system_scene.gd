## Main orchestrator for the system scene.
## Wires controllers together and handles scene-level flow.
extends Node2D

@export var system_definition: SystemDefinition
## Scene fallback only when no `SystemDefinition` is loaded (Inspector override).
@export var music_track_id: StringName = &"music_system_default"

@onready var camera: SystemCameraController = $CameraRoot/SystemCamera2D

@onready var spawner: SystemSpawner = $SystemSpawner
@onready var orbit_guides: SystemOrbitGuidesController = $SystemOrbitGuidesController
@onready var selection: SystemSelectionController = $SystemSelectionController
@onready var system_ui: SystemUIController = $SystemUIController
@onready var automation_controller: AutomationController = $AutomationController
@onready var discovery_controller: SystemDiscoveryController = $SystemDiscoveryController
@onready var survey_probe_mission_controller: SurveyProbeMissionController = $SurveyProbeMissionController
@onready var base_sensor_pulse_controller: BaseSensorPulseController = $BaseSensorPulseController
@onready var pause_menu_overlay: Control = $UI/PauseMenuOverlay
# VISUAL_LIGHTING_EXPERIMENT_START
@onready var system_light_controller: SystemLightController = $SystemLightController
# VISUAL_LIGHTING_EXPERIMENT_END

var _resolved_start_body_id: String = ""


func _ready() -> void:
	_resolve_active_system_definition()

	if system_definition != null:
		GameSession.set_current_system(system_definition)

	_resolved_start_body_id = _resolve_start_body_id()

	_setup_controllers()
	_connect_system_scene_signals()

	spawner.spawn_from_definition(system_definition)
	GameSession.ensure_default_discovery_for_system(system_definition)
	if discovery_controller != null:
		discovery_controller.apply_for_system(system_definition)
	orbit_guides.update_orbit_guides()

	# VISUAL_LIGHTING_EXPERIMENT_START
	if system_light_controller != null:
		system_light_controller.setup_from_spawner(spawner)
	# VISUAL_LIGHTING_EXPERIMENT_END

	call_deferred("_finish_initial_setup")


func _process(_delta: float) -> void:
	if system_definition == null:
		return

	orbit_guides.update_orbit_guides()


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu_overlay != null and pause_menu_overlay.has_method("toggle_menu"):
		if pause_menu_overlay.visible:
			return
	if selection != null:
		selection.handle_empty_space_click(event)


func _finish_initial_setup() -> void:
	get_tree().paused = false

	await get_tree().process_frame
	await get_tree().process_frame

	if automation_controller.has_method("apply_automation_save_if_pending"):
		await automation_controller.apply_automation_save_if_pending()

	automation_controller.ensure_starting_units(_resolved_start_body_id)

	var restored_camera := _try_restore_saved_camera_state()

	if not restored_camera:
		var start_node: Node2D = null

		if not _resolved_start_body_id.is_empty():
			start_node = spawner.get_spawned_object(_resolved_start_body_id) as Node2D

		if start_node != null:
			camera.set_focus_target(start_node, true)

	system_ui.update_all()

	AudioManager.play_music_optional(_resolve_system_music_track_id())


func _try_restore_saved_camera_state() -> bool:
	if not GameSession.has_camera_state_pending_for_system(GameSession.current_system_id):
		return false

	var camera_state: Dictionary = GameSession.take_camera_state_pending()

	if camera_state.is_empty():
		return false

	var saved_sid: String = str(camera_state.get("system_id", "")).strip_edges()
	var current_sid: String = GameSession.current_system_id.strip_edges()

	if not saved_sid.is_empty() and not current_sid.is_empty() and saved_sid != current_sid:
		return false

	return camera.restore_saved_state(camera_state)


func _setup_controllers() -> void:
	spawner.setup(
		$WorldRoot/StarRoot,
		$WorldRoot/SystemBodiesRoot,
		$WorldRoot/PointOfInterestRoot
	)

	orbit_guides.setup(
		$BackgroundRoot/OrbitGuidesLayer,
		$WorldRoot/SystemBodiesRoot,
		$WorldRoot/PointOfInterestRoot
	)

	selection.setup(
		system_definition,
		spawner
	)

	if discovery_controller != null:
		discovery_controller.setup(spawner, selection)

	automation_controller.setup($WorldRoot/AutomationRoot, spawner, _resolved_start_body_id)

	if survey_probe_mission_controller != null:
		survey_probe_mission_controller.setup(
			automation_controller,
			spawner,
			discovery_controller,
			selection,
			system_definition.id if system_definition != null else "",
			_resolved_start_body_id,
		)

	if base_sensor_pulse_controller != null:
		base_sensor_pulse_controller.setup(
			spawner,
			discovery_controller,
			system_definition,
			system_definition.id if system_definition != null else "",
			_resolved_start_body_id,
		)

	system_ui.setup(
		system_definition,
		selection,
		$UI/ObjectInfoPanel,
		$UI/BaseManagementPanel,
		automation_controller,
		spawner,
		survey_probe_mission_controller,
		base_sensor_pulse_controller,
		discovery_controller,
		$UI/ProductionPanel,
		$UI/UpgradePanel,
		$UI/TopHUD,
		get_node_or_null("UI/TopHudHoverPanel"),
		$UI/StoragePanel,
		_resolved_start_body_id,
	)


func _connect_system_scene_signals() -> void:
	_connect_navigation_hud_signal()

	if selection != null:
		spawner.body_spawned.connect(selection.register_body)
		spawner.poi_spawned.connect(selection.register_poi)

	_wire_camera_follow_to_selection()


func _connect_navigation_hud_signal() -> void:
	var nav := get_node_or_null("UI/NavigationHUD") as NavigationHUD
	if nav == null:
		return
	if not nav.galaxy_requested.is_connected(_on_navigation_galaxy_requested):
		nav.galaxy_requested.connect(_on_navigation_galaxy_requested)


func _on_navigation_galaxy_requested() -> void:
	if system_definition != null:
		GameSession.set_current_system(system_definition)
	SceneFlow.goto_galaxy()


func _wire_camera_follow_to_selection() -> void:
	if selection != null:
		if not selection.selection_changed.is_connected(_on_selection_camera_follow):
			selection.selection_changed.connect(_on_selection_camera_follow)

		if not selection.focus_selected_requested.is_connected(_on_focus_selected_camera_follow):
			selection.focus_selected_requested.connect(_on_focus_selected_camera_follow)

	if not spawner.body_spawned.is_connected(_on_body_spawned_camera_refocus_wire):
		spawner.body_spawned.connect(_on_body_spawned_camera_refocus_wire)

	if not spawner.poi_spawned.is_connected(_on_poi_spawned_camera_refocus_wire):
		spawner.poi_spawned.connect(_on_poi_spawned_camera_refocus_wire)


func _on_selection_camera_follow(selected: Node) -> void:
	if selected is Node2D:
		camera.set_focus_target(selected as Node2D, true)
	else:
		camera.clear_focus_target()


func _on_focus_selected_camera_follow(target: Node2D) -> void:
	camera.set_focus_target(target, true)


func _on_body_spawned_camera_refocus_wire(body: SystemBody) -> void:
	if body != null and not body.refocus_camera_requested.is_connected(_on_surface_refocus_camera_requested):
		body.refocus_camera_requested.connect(_on_surface_refocus_camera_requested)


func _on_poi_spawned_camera_refocus_wire(poi: PointOfInterest) -> void:
	if poi != null and not poi.refocus_camera_requested.is_connected(_on_surface_refocus_camera_requested):
		poi.refocus_camera_requested.connect(_on_surface_refocus_camera_requested)


func _on_surface_refocus_camera_requested(node: Node2D) -> void:
	if selection != null:
		selection.notify_focus_selected_requested(node)


func _resolve_system_music_track_id() -> StringName:
	if system_definition != null:
		return AudioManager.resolve_music_track_id_optional(system_definition.music_track_id)
	if not music_track_id.is_empty():
		return AudioManager.resolve_music_track_id_optional(music_track_id)
	return AudioManager.resolve_music_track_id_optional(&"music_system_default")


func _resolve_active_system_definition() -> void:
	var staged_system := GameSession.consume_selected_system_definition()

	if staged_system != null:
		system_definition = staged_system
		return

	if GameSession.current_system_definition != null:
		system_definition = GameSession.current_system_definition
		return

	GameSession.ensure_default_system_loaded()
	system_definition = GameSession.current_system_definition


func _has_body_id(body_id: String) -> bool:
	if system_definition == null:
		return false
	var needle: String = body_id.strip_edges()
	if needle.is_empty():
		return false
	for body_def in system_definition.bodies:
		if body_def == null:
			continue
		if body_def.id == needle:
			return true
	return false


func _get_first_body_id() -> String:
	if system_definition == null:
		return ""
	for body_def in system_definition.bodies:
		if body_def == null:
			continue
		if not body_def.id.is_empty():
			return body_def.id
	return ""


func _resolve_start_body_id() -> String:
	if system_definition == null:
		return ""

	var system_id: String = system_definition.id.strip_edges()
	if not system_id.is_empty():
		var established_base_id: String = GameSession.get_established_base_id_for_system(
			system_id
		).strip_edges()
		if not established_base_id.is_empty() and _has_body_id(established_base_id):
			return established_base_id

	var explicit_id: String = system_definition.start_body_id.strip_edges()
	if not explicit_id.is_empty():
		if _has_body_id(explicit_id):
			return explicit_id
		push_warning(
			"SystemScene: start_body_id '%s' unbekannt in System '%s', verwende ersten Body."
			% [explicit_id, system_definition.id]
		)

	var fallback_id: String = _get_first_body_id()
	if fallback_id.is_empty():
		push_warning("SystemScene: Kein Körper in System '%s' — kein Start-Fokus." % system_definition.id)
	return fallback_id
