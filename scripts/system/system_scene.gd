## Main orchestrator for the system scene.
## Wires controllers together and handles scene-level flow.
extends Node2D

@export var system_definition: SystemDefinition
@export var start_body_id: String = "earth"

@onready var camera: SystemCameraController = $CameraRoot/SystemCamera2D

@onready var spawner: SystemSpawner = $SystemSpawner
@onready var orbit_guides: SystemOrbitGuidesController = $SystemOrbitGuidesController
@onready var selection: SystemSelectionController = $SystemSelectionController
@onready var system_ui: SystemUIController = $SystemUIController
@onready var automation_controller: AutomationController = $AutomationController


func _ready() -> void:
	_resolve_active_system_definition()

	if system_definition != null:
		GameSession.set_current_system(system_definition)

	_setup_controllers()

	spawner.spawn_from_definition(system_definition)
	orbit_guides.update_orbit_guides()

	call_deferred("_finish_initial_setup")


func _process(_delta: float) -> void:
	if system_definition == null:
		return

	orbit_guides.update_orbit_guides()


func _unhandled_input(event: InputEvent) -> void:
	if selection != null:
		selection.handle_empty_space_click(event)


func _finish_initial_setup() -> void:
	await get_tree().process_frame

	var state := GameSession.get_or_create_ship_state(system_definition.id)
	selection.restore_last_selection(state)

	var start_node := spawner.get_spawned_object(start_body_id) as Node2D
	if start_node != null:
		camera.set_follow_target(start_node, true)

	system_ui.update_all()


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

	system_ui.setup(
		system_definition,
		selection,
		$UI/ActionBar,
		$UI/ObjectInfoPanel,
		$UI/BaseManagementPanel
	)

	automation_controller.setup(
		$WorldRoot/AutomationRoot,
		spawner
	)

	spawner.body_spawned.connect(selection.register_body)
	spawner.poi_spawned.connect(selection.register_poi)


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
