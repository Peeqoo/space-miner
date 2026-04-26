extends Node2D

@export var system_definition: SystemDefinition
@export var start_docked_body_id: String = "earth"
@export var scan_range: float = 140.0
@export var mining_range: float = 140.0
@export var mining_tick_interval: float = 0.5
@export var mining_session_duration: float = 5.0
@export var mining_cooldown_duration: float = 3.0
@export var scan_duration_seconds: float = 10.5
@export var dock_approach_range: float = 100.0
@export var approach_hold_range: float = 110.0

@onready var orbit_guides_layer: Node2D = $BackgroundRoot/OrbitGuidesLayer
@onready var star_root: Node2D = $WorldRoot/StarRoot
@onready var system_bodies_root: Node2D = $WorldRoot/SystemBodiesRoot
@onready var poi_root: Node2D = $WorldRoot/PointOfInterestRoot
@onready var player_ship: CharacterBody2D = $WorldRoot/PlayerShip
@onready var camera: SystemCameraController = $CameraRoot/SystemCamera2D

@onready var ship_hud: Node = $UI/ShipHud
@onready var action_bar: Node = $UI/ActionBar
@onready var object_info_panel: Node = $UI/ObjectInfoPanel

const SYSTEM_BODY_SCENE: PackedScene = preload("res://scenes/system/objects/system_body.tscn")
const POINT_OF_INTEREST_SCENE: PackedScene = preload("res://scenes/system/objects/point_of_interest.tscn")

var selected_node: Node = null
var spawned_lookup: Dictionary = {}
var star_visual: Sprite2D = null
var docked_body: SystemBody = null
var is_docked: bool = true
var entered_from_travel: bool = false

var mining_active: bool = false
var mining_target_node: Node2D = null
var mining_tick_accumulator: float = 0.0
var mining_timer_remaining: float = 0.0

var scan_active: bool = false
var scan_target_node: Node2D = null
var scan_timer_remaining: float = 0.0

var pending_auto_action: String = ""
var pending_action_target: Node2D = null
var autopilot_status_text: String = ""


func _ready() -> void:
	_resolve_active_system_definition()
	entered_from_travel = GameSession.consume_travel_entry_flag()

	if system_definition != null:
		GameSession.set_current_system(system_definition)

	_connect_ui_signals()

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav != null:
		if not nav.autopilot_state_changed.is_connected(_on_navigation_state_changed):
			nav.autopilot_state_changed.connect(_on_navigation_state_changed)
		if not nav.interaction_orbit_ready.is_connected(_on_navigation_orbit_ready):
			nav.interaction_orbit_ready.connect(_on_navigation_orbit_ready)

	_spawn_from_definition()
	_setup_orbit_guides()
	call_deferred("_finish_initial_setup")


func _finish_initial_setup() -> void:
	await _restore_ship_state()
	await _restore_camera_state()
	_update_ui()


func _process(delta: float) -> void:
	if system_definition == null:
		return

	if is_docked and docked_body != null:
		player_ship.global_position = docked_body.global_position
	else:
		var state: ShipRuntimeState = GameSession.get_or_create_ship_state(system_definition.id)
		if state != null:
			state.free_position = player_ship.global_position

	GameSession.tick_mining_cooldowns(delta)
	_update_scan(delta)
	_update_mining(delta)
	_setup_orbit_guides()
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return

		var world_position: Vector2 = get_global_mouse_position()
		if _is_click_on_interactable(world_position):
			return

		# Leerklick = Auswahl entfernen
		_clear_selection()

		# Nur im freien Flug zusätzlich Aktion abbrechen und Schiff bewegen
		if not is_docked:
			_stop_scan()
			_stop_mining()
			_cancel_ship_interaction(false)
			_send_ship_to_target(world_position)


func _connect_ui_signals() -> void:
	if ship_hud != null and ship_hud.has_signal("galaxy_map_requested"):
		if not ship_hud.is_connected("galaxy_map_requested", Callable(self, "_on_ship_hud_galaxy_map_requested")):
			ship_hud.connect("galaxy_map_requested", Callable(self, "_on_ship_hud_galaxy_map_requested"))

	if action_bar == null:
		return

	if action_bar.has_signal("undock_requested") and not action_bar.is_connected("undock_requested", Callable(self, "_on_action_bar_undock_requested")):
		action_bar.connect("undock_requested", Callable(self, "_on_action_bar_undock_requested"))
	if action_bar.has_signal("approach_requested") and not action_bar.is_connected("approach_requested", Callable(self, "_on_action_bar_approach_requested")):
		action_bar.connect("approach_requested", Callable(self, "_on_action_bar_approach_requested"))
	if action_bar.has_signal("dock_requested") and not action_bar.is_connected("dock_requested", Callable(self, "_on_action_bar_dock_requested")):
		action_bar.connect("dock_requested", Callable(self, "_on_action_bar_dock_requested"))
	if action_bar.has_signal("scan_requested") and not action_bar.is_connected("scan_requested", Callable(self, "_on_action_bar_scan_requested")):
		action_bar.connect("scan_requested", Callable(self, "_on_action_bar_scan_requested"))
	if action_bar.has_signal("mining_requested") and not action_bar.is_connected("mining_requested", Callable(self, "_on_action_bar_mining_requested")):
		action_bar.connect("mining_requested", Callable(self, "_on_action_bar_mining_requested"))
	if action_bar.has_signal("stop_mining_requested") and not action_bar.is_connected("stop_mining_requested", Callable(self, "_on_action_bar_stop_mining_requested")):
		action_bar.connect("stop_mining_requested", Callable(self, "_on_action_bar_stop_mining_requested"))


func _resolve_active_system_definition() -> void:
	var staged_system: SystemDefinition = GameSession.consume_selected_system_definition()
	if staged_system != null:
		system_definition = staged_system
		return

	if GameSession.current_system_definition != null:
		system_definition = GameSession.current_system_definition
		return

	GameSession.ensure_default_system_loaded()
	system_definition = GameSession.current_system_definition


func _get_ship_navigation() -> ShipNavigationComponent:
	return player_ship.get_node_or_null("ShipNavigationComponent") as ShipNavigationComponent


func _save_current_ship_state() -> void:
	if system_definition == null:
		return

	var state: ShipRuntimeState = GameSession.get_or_create_ship_state(system_definition.id)
	if state == null:
		return

	if is_docked and docked_body != null:
		state.is_docked = true
		state.docked_body_id = docked_body.body_id
		state.free_position = docked_body.global_position
	else:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = player_ship.global_position

	if selected_node is SystemBody:
		state.last_selected_object_id = (selected_node as SystemBody).body_id
	elif selected_node is PointOfInterest:
		state.last_selected_object_id = (selected_node as PointOfInterest).poi_id
	else:
		state.last_selected_object_id = ""


func _spawn_from_definition() -> void:
	if system_definition == null:
		push_error("SystemDefinition fehlt.")
		return

	spawned_lookup.clear()
	spawned_lookup["star"] = star_root

	_setup_star()
	_spawn_bodies()
	_spawn_pois()
	_resolve_orbits()


func _setup_star() -> void:
	star_visual = Sprite2D.new()
	star_visual.texture = system_definition.star_texture
	star_visual.scale = system_definition.star_scale
	star_visual.modulate = system_definition.star_modulate
	star_root.add_child(star_visual)


func _setup_orbit_guides() -> void:
	var orbit_entries: Array = []

	for child in system_bodies_root.get_children():
		var body: SystemBody = child as SystemBody
		if body == null or body.orbit_center == null:
			continue

		orbit_entries.append({
			"center": body.orbit_center.global_position,
			"radius": body.orbit_radius,
		})

	for child in poi_root.get_children():
		var poi: PointOfInterest = child as PointOfInterest
		if poi == null or poi.orbit_center == null:
			continue

		orbit_entries.append({
			"center": poi.orbit_center.global_position,
			"radius": poi.orbit_radius,
		})

	if orbit_guides_layer.has_method("set_orbits"):
		orbit_guides_layer.set_orbits(orbit_entries)


func _spawn_bodies() -> void:
	for body_def in system_definition.bodies:
		var body: SystemBody = SYSTEM_BODY_SCENE.instantiate() as SystemBody
		var presentation: Dictionary = CelestialPresentationCalculator.build_presentation(body_def, system_definition)

		body.set_definition(body_def)
		body.set_presentation(presentation)
		system_bodies_root.add_child(body)
		body.selected.connect(_on_body_selected)

		spawned_lookup[body_def.id] = body


func _spawn_pois() -> void:
	for poi_def in system_definition.pois:
		var poi: PointOfInterest = POINT_OF_INTEREST_SCENE.instantiate() as PointOfInterest
		poi.set_definition(poi_def)

		if poi_def.orbit_center_id == "star":
			poi.orbit_radius = system_definition.star_visual_radius + poi_def.orbit_radius

		poi_root.add_child(poi)
		poi.selected.connect(_on_poi_selected)

		spawned_lookup[poi_def.id] = poi


func _resolve_orbits() -> void:
	for body_def in system_definition.bodies:
		var body: SystemBody = spawned_lookup.get(body_def.id) as SystemBody
		var center: Node2D = spawned_lookup.get(body_def.orbit_center_id) as Node2D
		if body != null and center != null:
			body.set_orbit_center(center)
			body.refresh_orbit_position()

	for poi_def in system_definition.pois:
		var poi: PointOfInterest = spawned_lookup.get(poi_def.id) as PointOfInterest
		var center: Node2D = spawned_lookup.get(poi_def.orbit_center_id) as Node2D
		if poi != null and center != null:
			poi.set_orbit_center(center)
			poi.refresh_orbit_position()


func _restore_ship_state() -> void:
	await get_tree().process_frame

	if system_definition == null:
		return

	if entered_from_travel:
		_spawn_at_entry()
		return

	var state: ShipRuntimeState = GameSession.get_or_create_ship_state(system_definition.id)
	if state == null:
		_dock_to_start_body()
		return

	if state.is_docked and not state.docked_body_id.is_empty():
		var body: SystemBody = spawned_lookup.get(state.docked_body_id) as SystemBody
		if body != null:
			_dock_to_body(body)
			_restore_last_selection(state)
			return

	if not state.is_docked:
		_restore_undocked(state.free_position)
		_restore_last_selection(state)
		return

	_dock_to_start_body()


func _restore_last_selection(state: ShipRuntimeState) -> void:
	if state == null or state.last_selected_object_id.is_empty():
		return

	var candidate: Node = spawned_lookup.get(state.last_selected_object_id) as Node
	if candidate == null:
		return

	if candidate is SystemBody:
		_on_body_selected(candidate)
	elif candidate is PointOfInterest:
		_on_poi_selected(candidate)


func _restore_camera_state() -> void:
	await get_tree().process_frame
	_frame_camera_to_system()


func _frame_camera_to_system() -> void:
	if camera == null:
		return

	var targets: Array[Node2D] = []
	targets.append(star_root)

	for child in system_bodies_root.get_children():
		var body: SystemBody = child as SystemBody
		if body != null:
			targets.append(body)

	for child in poi_root.get_children():
		var poi: PointOfInterest = child as PointOfInterest
		if poi != null:
			targets.append(poi)

	targets.append(player_ship)
	camera.frame_nodes(targets)


func _spawn_at_entry() -> void:
	var angle: float = deg_to_rad(system_definition.entry_spawn_angle_degrees)
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	var spawn_position: Vector2 = star_root.global_position + direction * system_definition.entry_spawn_radius

	var state: ShipRuntimeState = GameSession.get_or_create_ship_state(system_definition.id)
	if state != null:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = spawn_position

	_restore_undocked(spawn_position)


func _restore_undocked(spawn_position: Vector2) -> void:
	is_docked = false
	docked_body = null
	player_ship.global_position = spawn_position

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav != null:
		nav.set_navigation_enabled(true)
		nav.clear_target()
		nav.cancel_interaction_autopilot(false)

	_clear_pending_action_only()
	_update_ui()


func _dock_to_start_body() -> void:
	var body: SystemBody = spawned_lookup.get(start_docked_body_id) as SystemBody
	if body != null:
		_dock_to_body(body)


func _dock_to_body(body: SystemBody) -> void:
	if body == null:
		return

	_stop_scan()
	_stop_mining()
	_cancel_ship_interaction(true)

	docked_body = body
	is_docked = true
	player_ship.global_position = body.global_position

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav != null:
		nav.set_navigation_enabled(false)
		nav.clear_target()
		nav.stop_immediately()

	var state: ShipRuntimeState = GameSession.get_or_create_ship_state(system_definition.id)
	if state != null:
		state.is_docked = true
		state.docked_body_id = body.body_id
		state.free_position = body.global_position

	_update_ui()


func _launch_ship() -> void:
	if docked_body == null:
		return

	var launch_position: Vector2 = docked_body.global_position + Vector2.RIGHT * 80.0

	is_docked = false
	docked_body = null
	player_ship.global_position = launch_position

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav != null:
		nav.set_navigation_enabled(true)
		nav.clear_target()
		nav.cancel_interaction_autopilot(false)

	var state: ShipRuntimeState = GameSession.get_or_create_ship_state(system_definition.id)
	if state != null:
		state.is_docked = false
		state.docked_body_id = ""
		state.free_position = launch_position

	_stop_scan()
	_clear_pending_action_only()
	_update_ui()


func _update_ui() -> void:
	_update_action_bar()
	_update_object_info_panel()

	if ship_hud != null and ship_hud.has_method("refresh_from_game_session"):
		ship_hud.call("refresh_from_game_session")


func _update_object_info_panel() -> void:
	if object_info_panel == null:
		return

	object_info_panel.visible = selected_node != null

	if selected_node == null:
		if object_info_panel.has_method("show_empty"):
			object_info_panel.call("show_empty")
		return

	var scan_state: String = GameSession.get_object_scan_state(system_definition.id, _get_selected_object_id())
	var scanner_tier: String = GameSession.get_active_scanner_tier()
	var info: Dictionary = {}

	if selected_node is SystemBody:
		info = (selected_node as SystemBody).build_scan_info(scan_state, scanner_tier)
		info["preview_texture"] = _get_preview_texture_for_node(selected_node)
		info["distance_text"] = _build_distance_text_for_node(selected_node)
		info["resources_visible"] = _build_resource_info_rows(info)
		info["lore_text"] = _build_object_lore_text(selected_node)
		if object_info_panel.has_method("show_body_info"):
			object_info_panel.call("show_body_info", info)
		return

	if selected_node is PointOfInterest:
		info = (selected_node as PointOfInterest).build_scan_info(scan_state, scanner_tier)
		info["preview_texture"] = _get_preview_texture_for_node(selected_node)
		info["distance_text"] = _build_distance_text_for_node(selected_node)
		info["resources_visible"] = _build_resource_info_rows(info)
		info["lore_text"] = _build_object_lore_text(selected_node)
		if object_info_panel.has_method("show_poi_info"):
			object_info_panel.call("show_poi_info", info)


func _get_preview_texture_for_node(node: Node) -> Texture2D:
	if node is SystemBody:
		var body: SystemBody = node as SystemBody
		if body.definition != null:
			return body.definition.texture
	elif node is PointOfInterest:
		var poi: PointOfInterest = node as PointOfInterest
		if poi.definition != null and poi.definition.texture != null:
			return poi.definition.texture
	return null


func _build_distance_text_for_node(node: Node) -> String:
	if node == null:
		return "-"
	var target: Node2D = node as Node2D
	if target == null:
		return "-"
	var distance_units: int = int(round(player_ship.global_position.distance_to(target.global_position)))
	return "%d u" % distance_units


func _build_resource_info_rows(info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var visible_resources_variant: Variant = info.get("resources_visible", [])
	if not (visible_resources_variant is Array):
		return result

	var visible_resources: Array = visible_resources_variant as Array
	for resource_entry in visible_resources:
		var resource_name: String = str(resource_entry)
		result.append({
			"name": resource_name,
			"percent": _get_resource_percent_for_name(resource_name),
		})

	return result


func _build_object_lore_text(node: Node) -> String:
	if node is SystemBody:
		var body: SystemBody = node as SystemBody
		if body.definition != null:
			return _get_optional_object_text(body.definition, "description")

	if node is PointOfInterest:
		var poi: PointOfInterest = node as PointOfInterest
		if poi.definition != null:
			return _get_optional_object_text(poi.definition, "description")

	return ""


func _get_optional_object_text(obj: Object, property_name: String) -> String:
	if obj == null:
		return ""

	for property_info in obj.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return str(obj.get(property_name)).strip_edges()

	return ""

func _get_resource_percent_for_name(resource_name: String) -> int:
	match resource_name.to_lower():
		"stone":
			return 42
		"iron":
			return 31
		"water":
			return 18
		"ice":
			return 24
		"metal":
			return 27
		"titanium":
			return 12
		_:
			return 15


func _build_object_hint_text(scan_state: String) -> String:
	if scan_active and selected_node == scan_target_node:
		return "Scan läuft. Ergebnisse werden nach Abschluss sichtbar."

	if mining_active and selected_node == mining_target_node:
		return "Mining aktiv. Ressourcen werden live ins Cargo übertragen."

	if pending_auto_action != "" and selected_node == pending_action_target:
		return autopilot_status_text

	if is_docked:
		return "Du bist angedockt. Abdocken, um wieder lokale Aktionen auszuführen."

	var next_state: String = GameSession.get_next_scan_state(scan_state)
	if next_state != scan_state and not GameSession.scanner_supports_scan_state(next_state):
		match next_state:
			GameSession.SCAN_DEEP:
				return "Deep Scan ist noch nicht verfügbar."
			GameSession.SCAN_SPECIAL:
				return "Spezialscan ist noch nicht verfügbar."
			_:
				return "Der aktuelle Scanner reicht für den nächsten Informationsschritt nicht aus."

	if _can_start_mining_selected():
		return "Mining ist verfügbar, sobald du das Manöver startest."
	if _can_scan_selected():
		return "Scan ist verfügbar. Erst nach der Scanzeit werden neue Daten sichtbar."
	if selected_node is SystemBody:
		return "Annäherung oder Docking verfügbar."
	return "Annäherung verfügbar."


func _update_action_bar() -> void:
	if action_bar == null:
		return

	action_bar.visible = selected_node != null
	if selected_node == null:
		return

	var has_selection: bool = selected_node != null
	var show_dock_button: bool = selected_node is SystemBody
	var state: Dictionary = {
		"is_docked": is_docked,
		"has_selection": has_selection,
		"can_undock": is_docked,
		"can_approach": has_selection and not is_docked and not scan_active and not mining_active,
		"show_dock": show_dock_button,
		"can_dock": _can_request_dock_selected(),
		"can_scan": _can_scan_selected(),
		"can_mine": _can_start_mining_selected(),
		"mining_active": mining_active,
		"scan_active": scan_active,
	}

	if action_bar.has_method("apply_state"):
		action_bar.call("apply_state", state)
	if action_bar.has_method("set_action_status"):
		action_bar.call("set_action_status", _build_action_status_text())


func _can_request_dock_selected() -> bool:
	if is_docked:
		return false
	if scan_active or mining_active:
		return false
	return selected_node is SystemBody


func _can_scan_selected() -> bool:
	if selected_node == null:
		return false
	if is_docked:
		return false
	if scan_active or mining_active:
		return false

	var current_scan_state: String = GameSession.get_object_scan_state(system_definition.id, _get_selected_object_id())
	return GameSession.can_scan_to_next_state(current_scan_state)


func _can_start_mining_selected() -> bool:
	if selected_node == null:
		return false
	if is_docked:
		return false
	if mining_active or scan_active:
		return false
	if not GameSession.has_cargo_space():
		return false

	var visible_resources: Array[String] = _get_selected_visible_resources()
	if visible_resources.is_empty():
		return false

	var object_id: String = _get_selected_object_id()
	if object_id.is_empty():
		return false

	GameSession.ensure_object_resource_runtime(system_definition.id, object_id, visible_resources)

	if GameSession.is_object_depleted(system_definition.id, object_id, visible_resources):
		return false

	if GameSession.get_object_mining_cooldown_remaining(system_definition.id, object_id) > 0.0:
		return false

	return true


func _clear_selection() -> void:
	if selected_node != null and selected_node.has_method("set_selected"):
		selected_node.set_selected(false)

	selected_node = null
	_update_ui()


func _on_body_selected(body: SystemBody) -> void:
	if scan_active and scan_target_node != body:
		_stop_scan()
	if mining_active and mining_target_node != body:
		_stop_mining()
	if _is_ship_interacting_with_other_target(body):
		_cancel_ship_interaction(false)

	_clear_selection()
	selected_node = body
	body.set_selected(true)
	_update_ui()


func _on_poi_selected(poi: PointOfInterest) -> void:
	if scan_active and scan_target_node != poi:
		_stop_scan()
	if mining_active and mining_target_node != poi:
		_stop_mining()
	if _is_ship_interacting_with_other_target(poi):
		_cancel_ship_interaction(false)

	_clear_selection()
	selected_node = poi
	poi.set_selected(true)
	_update_ui()


func _build_action_status_text() -> String:
	if selected_node == null:
		return ""

	if pending_auto_action != "" and selected_node == pending_action_target:
		return autopilot_status_text

	if scan_active and selected_node == scan_target_node:
		return "Scan läuft (%.1fs)" % [maxf(scan_timer_remaining, 0.0)]

	if mining_active and selected_node == mining_target_node:
		return "Mining aktiv (%.1fs)" % [maxf(mining_timer_remaining, 0.0)]

	var object_id: String = _get_selected_object_id()
	var visible_resources: Array[String] = _get_selected_visible_resources()
	if not object_id.is_empty() and not visible_resources.is_empty():
		if GameSession.is_object_depleted(system_definition.id, object_id, visible_resources):
			return "Vorkommen erschöpft"

		var cooldown_remaining: float = GameSession.get_object_mining_cooldown_remaining(system_definition.id, object_id)
		if cooldown_remaining > 0.0:
			return "Mining Cooldown (%.1fs)" % [cooldown_remaining]

	var nav: ShipNavigationComponent = _get_ship_navigation()
	var selected_target: Node2D = selected_node as Node2D
	if nav != null and selected_target != null and nav.is_orbiting_target(selected_target):
		return "Orbitposition gehalten"

	if is_docked:
		return "Angedockt"

	return "Bereit"


func _get_selected_object_id() -> String:
	if selected_node is SystemBody:
		return (selected_node as SystemBody).body_id
	if selected_node is PointOfInterest:
		return (selected_node as PointOfInterest).poi_id
	return ""


func _request_selected_action(action_name: String) -> void:
	if selected_node == null:
		return

	var target_node: Node2D = selected_node as Node2D
	if target_node == null:
		return

	if action_name != "scan":
		_stop_scan()
	if action_name != "mining":
		_stop_mining()

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav == null:
		return

	pending_auto_action = action_name
	pending_action_target = target_node
	autopilot_status_text = _get_initial_action_status_text(action_name)
	nav.begin_interaction_approach(target_node, action_name, _get_action_range(action_name))
	_update_ui()


func _get_action_range(action_name: String) -> float:
	match action_name:
		"scan":
			return scan_range
		"mining":
			return mining_range
		"dock", "land":
			return dock_approach_range
		"approach":
			return approach_hold_range
		_:
			return approach_hold_range


func _get_initial_action_status_text(action_name: String) -> String:
	match action_name:
		"scan", "mining", "dock", "land", "approach":
			return "Abfangkurs wird berechnet"
		_:
			return "Manöver läuft"


func _on_navigation_state_changed(_state_name: String, status_text: String) -> void:
	if pending_auto_action != "":
		autopilot_status_text = status_text
	elif status_text.is_empty():
		autopilot_status_text = ""

	_update_ui()


func _on_navigation_orbit_ready(action_name: String, target: Node2D) -> void:
	if target == null:
		return
	if pending_action_target != target:
		return

	match action_name:
		"approach":
			_clear_pending_action_only()
		"scan":
			_begin_scan_action(target)
		"mining":
			_begin_mining_action(target)
		"dock":
			_execute_dock_action(target)
		"land":
			_clear_pending_action_only()
		_:
			_clear_pending_action_only()

	_update_ui()


func _begin_scan_action(target: Node2D) -> void:
	if target == null:
		_clear_pending_action_only()
		return

	scan_active = true
	scan_target_node = target
	scan_timer_remaining = scan_duration_seconds
	_clear_pending_action_only()


func _begin_mining_action(target: Node2D) -> void:
	if target == null:
		_clear_pending_action_only()
		return

	var object_id: String = _get_object_id_for_node(target)
	if object_id.is_empty():
		_clear_pending_action_only()
		return

	var visible_resources: Array[String] = _get_visible_resources_for_node(target)
	if visible_resources.is_empty():
		_clear_pending_action_only()
		return

	GameSession.ensure_object_resource_runtime(system_definition.id, object_id, visible_resources)

	mining_active = true
	mining_target_node = target
	mining_tick_accumulator = 0.0
	mining_timer_remaining = mining_session_duration
	_clear_pending_action_only()


func _execute_dock_action(target: Node2D) -> void:
	_clear_pending_action_only()

	if not (target is SystemBody):
		return

	var body: SystemBody = target as SystemBody
	_dock_to_body(body)


func _stop_scan() -> void:
	scan_active = false
	scan_target_node = null
	scan_timer_remaining = 0.0


func _stop_mining() -> void:
	mining_active = false
	mining_target_node = null
	mining_tick_accumulator = 0.0
	mining_timer_remaining = 0.0


func _update_scan(delta: float) -> void:
	if not scan_active:
		return
	if scan_target_node == null or not is_instance_valid(scan_target_node):
		_stop_scan()
		return

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav == null or not nav.is_orbiting_target(scan_target_node):
		_stop_scan()
		_update_ui()
		return

	scan_timer_remaining = maxf(scan_timer_remaining - delta, 0.0)
	if scan_timer_remaining > 0.0:
		return

	var object_id: String = _get_object_id_for_node(scan_target_node)
	_stop_scan()
	if object_id.is_empty():
		_update_ui()
		return

	GameSession.advance_object_scan_state(system_definition.id, object_id)
	_update_ui()


func _update_mining(delta: float) -> void:
	if not mining_active:
		return
	if mining_target_node == null:
		_stop_mining()
		return
	if not GameSession.has_cargo_space():
		_stop_mining()
		_update_ui()
		return
	if not _is_mining_target_still_valid():
		_stop_mining()
		_update_ui()
		return

	mining_timer_remaining = maxf(mining_timer_remaining - delta, 0.0)
	if mining_timer_remaining <= 0.0:
		_start_mining_cooldown_for_node(mining_target_node)
		_stop_mining()
		_update_ui()
		return

	mining_tick_accumulator += delta
	while mining_tick_accumulator >= mining_tick_interval:
		mining_tick_accumulator -= mining_tick_interval
		_apply_mining_tick()
		if not mining_active:
			break
		if not GameSession.has_cargo_space():
			_stop_mining()
			break


func _is_mining_target_still_valid() -> bool:
	if mining_target_node == null:
		return false

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav == null or not nav.is_orbiting_target(mining_target_node):
		return false

	var visible_resources: Array[String] = _get_visible_resources_for_node(mining_target_node)
	if visible_resources.is_empty():
		return false

	var object_id: String = _get_object_id_for_node(mining_target_node)
	if object_id.is_empty():
		return false

	GameSession.ensure_object_resource_runtime(system_definition.id, object_id, visible_resources)
	return not GameSession.is_object_depleted(system_definition.id, object_id, visible_resources)


func _apply_mining_tick() -> void:
	var visible_resources: Array[String] = _get_visible_resources_for_node(mining_target_node)
	if visible_resources.is_empty():
		_stop_mining()
		return

	var tick_yield: Dictionary = _build_tick_yield(visible_resources)
	if tick_yield.is_empty():
		_stop_mining()
		_update_ui()
		return

	var object_id: String = _get_object_id_for_node(mining_target_node)
	if not object_id.is_empty() and GameSession.is_object_depleted(system_definition.id, object_id, visible_resources):
		_stop_mining()

	_update_ui()


func _build_tick_yield(visible_resources: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if mining_target_node == null:
		return result

	var object_id: String = _get_object_id_for_node(mining_target_node)
	if object_id.is_empty():
		return result

	for resource_id in visible_resources:
		var amount: int = _get_default_mining_amount_for_resource(resource_id)
		if amount <= 0:
			continue

		var free_space: int = GameSession.get_cargo_free_space()
		if free_space <= 0:
			break

		var requested_amount: int = min(amount, free_space)
		var mined_amount: int = GameSession.consume_object_resource(system_definition.id, object_id, resource_id, requested_amount)
		if mined_amount <= 0:
			continue

		var accepted: int = GameSession.add_cargo_item(resource_id, mined_amount)
		if accepted > 0:
			result[resource_id] = accepted

		if not GameSession.has_cargo_space():
			break

	return result


func _get_default_mining_amount_for_resource(resource_id: String) -> int:
	match resource_id.to_lower():
		"stone":
			return 4
		"iron", "metal", "titanium":
			return 1
		"water", "ice":
			return 2
		_:
			return 1


func _start_mining_cooldown_for_node(node: Node) -> void:
	if node == null:
		return

	var object_id: String = _get_object_id_for_node(node)
	if object_id.is_empty():
		return

	if GameSession.get_object_mining_cooldown_remaining(system_definition.id, object_id) > 0.0:
		return

	GameSession.set_object_mining_cooldown_remaining(system_definition.id, object_id, mining_cooldown_duration)


func _get_selected_visible_resources() -> Array[String]:
	return _get_visible_resources_for_node(selected_node)


func _get_visible_resources_for_node(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node == null:
		return result

	var object_id: String = _get_object_id_for_node(node)
	if object_id.is_empty():
		return result

	var scan_state: String = GameSession.get_object_scan_state(system_definition.id, object_id)
	if scan_state == GameSession.SCAN_UNKNOWN:
		return result

	var scanner_tier: String = GameSession.get_active_scanner_tier()
	var info: Dictionary = {}
	if node is SystemBody:
		info = (node as SystemBody).build_scan_info(scan_state, scanner_tier)
	elif node is PointOfInterest:
		info = (node as PointOfInterest).build_scan_info(scan_state, scanner_tier)

	var resources_variant: Variant = info.get("resources_visible", [])
	if resources_variant is Array:
		for entry in resources_variant:
			result.append(str(entry))

	return result


func _get_object_id_for_node(node: Node) -> String:
	if node is SystemBody:
		return (node as SystemBody).body_id
	if node is PointOfInterest:
		return (node as PointOfInterest).poi_id
	return ""


func _send_ship_to_target(target: Vector2) -> void:
	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav != null:
		nav.set_navigation_enabled(true)
		nav.set_target(target)


func _clear_pending_action_only() -> void:
	pending_auto_action = ""
	pending_action_target = null
	autopilot_status_text = ""


func _cancel_ship_interaction(stop_ship: bool) -> void:
	_clear_pending_action_only()
	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav != null:
		nav.cancel_interaction_autopilot(stop_ship)


func _is_ship_interacting_with_other_target(new_target: Node2D) -> bool:
	if new_target == null:
		return false

	var nav: ShipNavigationComponent = _get_ship_navigation()
	if nav == null:
		return false

	var current_target: Node2D = nav.get_interaction_target()
	if current_target == null:
		return false

	return current_target != new_target


func _on_ship_hud_galaxy_map_requested() -> void:
	_on_back_pressed()


func _on_action_bar_undock_requested() -> void:
	_on_start_pressed()


func _on_action_bar_approach_requested() -> void:
	if is_docked or selected_node == null:
		return
	_request_selected_action("approach")


func _on_action_bar_dock_requested() -> void:
	if not _can_request_dock_selected():
		return
	_stop_scan()
	_stop_mining()
	_request_selected_action("dock")


func _on_action_bar_scan_requested() -> void:
	if not _can_scan_selected():
		return
	_request_selected_action("scan")


func _on_action_bar_mining_requested() -> void:
	if not _can_start_mining_selected():
		return
	_request_selected_action("mining")


func _on_action_bar_stop_mining_requested() -> void:
	_stop_mining()
	_update_ui()


func _on_start_pressed() -> void:
	_launch_ship()


func _on_back_pressed() -> void:
	_save_current_ship_state()
	SceneFlow.goto_galaxy()


func _is_click_on_interactable(world_position: Vector2) -> bool:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var results: Array = space_state.intersect_point(query, 16)
	return results.size() > 0
