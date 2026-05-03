## Main orchestrator for the system scene.
## Wires controllers together and handles scene-level flow.
extends Node2D

@export var system_definition: SystemDefinition
@export var start_docked_body_id: String = "earth"

@onready var player_ship: CharacterBody2D = $WorldRoot/PlayerShip
@onready var camera: SystemCameraController = $CameraRoot/SystemCamera2D

@onready var spawner: SystemSpawner = $SystemSpawner
@onready var orbit_guides: SystemOrbitGuidesController = $SystemOrbitGuidesController
@onready var ship_state: SystemShipStateController = $SystemShipStateController
@onready var selection: SystemSelectionController = $SystemSelectionController
@onready var system_ui: SystemUIController = $SystemUIController

var entered_from_travel: bool = false


func _ready() -> void:
	_resolve_active_system_definition()

	entered_from_travel = GameSession.consume_travel_entry_flag()

	if system_definition != null:
		GameSession.set_current_system(system_definition)

	_setup_controllers()

	spawner.spawn_from_definition(system_definition)
	orbit_guides.update_orbit_guides()

	call_deferred("_finish_initial_setup")


func _process(_delta: float) -> void:
	if system_definition == null:
		return

	ship_state.sync_ship_position()
	orbit_guides.update_orbit_guides()


func _unhandled_input(event: InputEvent) -> void:
	if selection != null:
		selection.handle_empty_space_click(event)


func _finish_initial_setup() -> void:
	await ship_state.restore_ship_state(entered_from_travel)

	var state := GameSession.get_or_create_ship_state(system_definition.id)
	selection.restore_last_selection(state)

	await ship_state.restore_camera_state()
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

	ship_state.setup(
		system_definition,
		start_docked_body_id,
		player_ship,
		camera,
		spawner,
		system_ui
	)

	selection.setup(
		system_definition,
		player_ship,
		spawner,
		ship_state
	)

	system_ui.setup(
		system_definition,
		player_ship,
		ship_state,
		selection,
		$UI/ShipHud,
		$UI/ActionBar,
		$UI/ObjectInfoPanel,
		$UI/BaseManagementPanel
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
