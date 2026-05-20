extends Node2D

const HUD_SCENE_PATH: String = "UI/GalaxyMapHUD"
## Optional override for camera center fallback (empty = use `GalaxyMapDefinition.default_center_system_id`).
@export var start_center_system_id: String = ""
@export var galaxy_definition: GalaxyMapDefinition
@export var system_node_scene: PackedScene

const ACCESS_CURRENT := "current"
const ACCESS_READY := "ready"
const ACCESS_LOCKED := "locked"
const ACCESS_UNREACHABLE := "unreachable"

const _TRANSIT_ROUTE_ACTIVE_COLOR := Color(0.35, 0.85, 1.0, 0.65)
const _TRANSIT_ROUTE_INACTIVE_COLOR := Color(0.45, 0.48, 0.58, 0.42)
const _TRANSIT_ROUTE_ACTIVE_WIDTH := 2.0
const _TRANSIT_ROUTE_INACTIVE_WIDTH := 2.0

@onready var camera: SystemCameraController = $CameraRoot/GalaxyCamera2D
@onready var hud: GalaxyMapHUD = get_node_or_null(HUD_SCENE_PATH) as GalaxyMapHUD
@onready var systems_root: Node2D = $SystemsRoot

var transit_route_root: Node2D = null

var selected_system: SystemDefinition = null
var _selected_system_node: Node = null
var _system_node_by_id: Dictionary = {}

## Leerraum-Klick: Auswahl erst bei kurzem Linksklick ohne nennenswerte Bewegung löschen (kein Drag).
var _empty_map_click_press_pos: Vector2 = Vector2.ZERO
var _empty_map_click_tracking: bool = false
const _EMPTY_MAP_CLICK_DRAG_THRESHOLD_PX: float = 4.0


func _ready() -> void:
	add_to_group("galaxy_map_root")
	_resolve_transit_route_root()
	GameSession.ensure_galaxy_progression_boot()
	_build_system_nodes_from_definition()
	_build_system_node_index()
	_refresh_system_node_progression_visuals()
	_refresh_transit_routes()

	_connect_galaxy_map_signals()

	GameSession.ensure_default_system_loaded()
	_update_current_system_display()

	if GameSession.current_system_definition != null:
		select_system(GameSession.current_system_definition)
	elif hud != null:
		hud.show_no_selection_state()

	call_deferred("_apply_start_camera_target")
	call_deferred("_debug_unlock_proxima")
	
func _debug_unlock_proxima() -> void:
	GameSession.unlock_system("proxima")

func _connect_galaxy_map_signals() -> void:
	if not GameSession.galaxy_progression_changed.is_connected(_on_galaxy_progression_changed):
		GameSession.galaxy_progression_changed.connect(_on_galaxy_progression_changed)

	if not GameSession.base_resources_changed.is_connected(_on_base_resources_changed_galaxy_refresh):
		GameSession.base_resources_changed.connect(_on_base_resources_changed_galaxy_refresh)

	if hud != null and not hud.enter_requested.is_connected(_on_enter_pressed):
		hud.enter_requested.connect(_on_enter_pressed)

	if hud != null and not hud.colonization_cancel_requested.is_connected(_on_colon_cancel_requested):
		hud.colonization_cancel_requested.connect(_on_colon_cancel_requested)

	if hud != null and not hud.colonization_dev_complete_requested.is_connected(_on_colon_dev_complete_requested):
		hud.colonization_dev_complete_requested.connect(_on_colon_dev_complete_requested)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if _is_screen_over_interactive_ui():
				_empty_map_click_tracking = false
				return
			_empty_map_click_press_pos = mb.position
			_empty_map_click_tracking = true
			return
		if not _empty_map_click_tracking:
			return
		_empty_map_click_tracking = false
		if _empty_map_click_press_pos.distance_to(mb.position) > _EMPTY_MAP_CLICK_DRAG_THRESHOLD_PX:
			return
		if _is_screen_over_interactive_ui():
			return
		if _is_screen_over_system_node(mb.position):
			return
		clear_selection()


func _is_screen_over_interactive_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _is_screen_over_system_node(screen_px: Vector2) -> bool:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var world_pt: Vector2 = inv * screen_px
	for child in systems_root.get_children():
		if not (child is Node2D):
			continue
		var n2 := child as Node2D
		var r: float = _galaxy_system_node_pick_radius(n2)
		if n2.global_position.distance_to(world_pt) <= r:
			return true
	return false


func _galaxy_system_node_pick_radius(node: Node2D) -> float:
	var cs := node.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius + 2.0
	return 36.0


func select_system(system_def: SystemDefinition) -> void:
	if system_def == null:
		push_warning("select_system(): system_def ist null")
		return

	_empty_map_click_tracking = false
	selected_system = system_def
	_set_selected_system_node(_system_node_by_id.get(system_def.id, null))
	_update_current_system_display()
	_update_hud_for_selected_system(system_def)


func clear_selection() -> void:
	_empty_map_click_tracking = false
	selected_system = null
	_set_selected_system_node(null)
	_update_current_system_display()
	if hud != null:
		hud.show_no_selection_state()


func _on_enter_pressed() -> void:
	if selected_system == null:
		push_warning("_on_enter_pressed(): kein selected_system")
		return

	var system_id: String = selected_system.id
	if not _can_enter_system(system_id):
		var state: String = _get_selected_system_access_state(system_id)
		push_warning("_on_enter_pressed(): Enter nicht erlaubt (access_state=%s, system_id=%s)" % [state, system_id])
		return

	var entering_current_system: bool = system_id == GameSession.current_system_id
	GameSession.stage_system_entry(selected_system, not entering_current_system)

	if entering_current_system:
		GameSession.set_current_system(selected_system)

	SceneFlow.goto_system()


func _update_hud_for_selected_system(system_def: SystemDefinition) -> void:
	if hud == null:
		return

	var access_state: String = _get_selected_system_access_state(system_def.id)
	var can_enter: bool = _can_enter_system(system_def.id)
	var known_planets_count: int = _count_known_bodies(system_def)
	var known_resources_text: String = _build_known_resources_summary(system_def)
	var info_text: String = system_def.description.strip_edges()

	hud.show_system_info(
		system_def.display_name,
		known_planets_count,
		known_resources_text,
		info_text,
		can_enter,
		access_state,
	)
	hud.update_colonization_preview(system_def, access_state)


func _on_colon_cancel_requested() -> void:
	if selected_system == null:
		return

	var rec := GameSession.get_pending_colonization_operation_for_system(selected_system.id)
	if rec.is_empty():
		return

	var oid := str(rec.get("operation_id", "")).strip_edges()
	if oid.is_empty():
		return

	if not GameSession.cancel_colonization_operation(oid):
		return

	_update_hud_for_selected_system(selected_system)


func _on_colon_dev_complete_requested() -> void:
	if selected_system == null:
		return

	var rec := GameSession.get_pending_colonization_operation_for_system(selected_system.id)
	if rec.is_empty():
		return

	var oid := str(rec.get("operation_id", "")).strip_edges()
	if oid.is_empty():
		return

	GameSession.complete_colonization_operation(oid)
	_update_hud_for_selected_system(selected_system)


func _are_systems_directly_connected(a_id: String, b_id: String) -> bool:
	var a: String = a_id.strip_edges()
	var b: String = b_id.strip_edges()
	if a.is_empty() or b.is_empty():
		return false
	if a == b:
		return true

	for route_entry in _get_transit_routes():
		if route_entry == null:
			continue
		if not (route_entry is GalaxyTransitRouteDefinition):
			continue
		var route_def: GalaxyTransitRouteDefinition = route_entry as GalaxyTransitRouteDefinition
		var from_id: String = route_def.from_system_id.strip_edges()
		var to_id: String = route_def.to_system_id.strip_edges()
		if from_id.is_empty() or to_id.is_empty():
			continue
		if from_id == a and to_id == b:
			return true
		if from_id == b and to_id == a:
			return true

	return false


func _get_selected_system_access_state(system_id: String) -> String:
	var sid: String = system_id.strip_edges()
	if sid.is_empty():
		return ACCESS_LOCKED

	if sid == GameSession.current_system_id:
		return ACCESS_CURRENT

	if not GameSession.is_system_unlocked(sid):
		return ACCESS_LOCKED

	var current_id: String = GameSession.current_system_id.strip_edges()
	if current_id.is_empty():
		return ACCESS_UNREACHABLE

	if _are_systems_directly_connected(current_id, sid):
		return ACCESS_READY

	return ACCESS_UNREACHABLE


func _can_enter_system(system_id: String) -> bool:
	var access_state: String = _get_selected_system_access_state(system_id)
	return access_state == ACCESS_CURRENT or access_state == ACCESS_READY


func _update_current_system_display() -> void:
	if hud == null:
		return

	var current_name: String = "-"
	if GameSession.current_system_definition != null:
		current_name = GameSession.current_system_definition.display_name
	elif not GameSession.current_system_id.is_empty():
		current_name = GameSession.current_system_id

	hud.set_current_system_name(current_name)


func _count_known_bodies(system_def: SystemDefinition) -> int:
	var count: int = 0
	for body_def in system_def.bodies:
		if body_def == null:
			continue
		if GameSession.get_object_scan_state(system_def.id, body_def.id) != GameSession.SCAN_UNKNOWN:
			count += 1
	return count


func _build_known_resources_summary(system_def: SystemDefinition) -> String:
	var frequency_by_resource: Dictionary = {}

	for body_def in system_def.bodies:
		if body_def == null:
			continue

		var scan_state: String = GameSession.get_object_scan_state(system_def.id, body_def.id)
		if scan_state == GameSession.SCAN_UNKNOWN:
			continue

		var visible_resources: Array[String] = _get_visible_resources_for_body(body_def, scan_state)
		for resource_id in visible_resources:
			var normalized: String = resource_id.strip_edges().to_lower()
			if normalized.is_empty():
				continue
			frequency_by_resource[normalized] = int(frequency_by_resource.get(normalized, 0)) + 1

	if frequency_by_resource.is_empty():
		return "Unknown"

	var resource_ids: Array[String] = []
	for key in frequency_by_resource.keys():
		resource_ids.append(str(key))

	resource_ids.sort_custom(func(a: String, b: String) -> bool:
		var count_a: int = int(frequency_by_resource.get(a, 0))
		var count_b: int = int(frequency_by_resource.get(b, 0))
		if count_a == count_b:
			return a < b
		return count_a > count_b
	)

	var top_count: int = min(resource_ids.size(), 3)
	var display_parts := PackedStringArray()
	for i in range(top_count):
		display_parts.append(_format_resource_name(resource_ids[i]))

	return ", ".join(display_parts)


func _get_visible_resources_for_body(body_def: SystemBodyDefinition, scan_state: String) -> Array[String]:
	var resources: Array[String] = []

	if scan_state == GameSession.SCAN_UNKNOWN:
		return resources

	for entry in body_def.get_basic_scan_resources():
		resources.append(str(entry.resource_id))

	if GameSession.scan_state_rank(scan_state) >= GameSession.scan_state_rank(GameSession.SCAN_DEEP):
		for entry in body_def.get_deep_scan_resources():
			resources.append(str(entry.resource_id))

	if GameSession.scan_state_rank(scan_state) >= GameSession.scan_state_rank(GameSession.SCAN_SPECIAL):
		for entry in body_def.get_special_scan_resources():
			resources.append(str(entry.resource_id))

	return resources


func _format_resource_name(resource_id: String) -> String:
	if resource_id.is_empty():
		return ""
	return resource_id.substr(0, 1).to_upper() + resource_id.substr(1)


func _apply_start_camera_target() -> void:
	# Rebuild index here in case resources finished loading after _ready().
	_build_system_node_index()
	_refresh_system_node_progression_visuals()
	_refresh_transit_routes()

	var target_node: Node2D = null
	if GameSession.current_system_definition != null and not GameSession.current_system_definition.id.is_empty():
		target_node = _find_system_node_by_definition_id(GameSession.current_system_definition.id)
	elif not GameSession.current_system_id.is_empty():
		target_node = _find_system_node_by_definition_id(GameSession.current_system_id)

	if target_node == null:
		var override_id: String = start_center_system_id.strip_edges()
		if not override_id.is_empty():
			target_node = _find_system_node_by_definition_id(override_id)

	if target_node == null:
		target_node = _find_system_node_by_definition_id(_get_default_center_system_id())

	if target_node == null:
		target_node = _find_first_system_node_from_definition_entries()

	# Fallback: use the first child of SystemsRoot that is a Node2D.
	if target_node == null:
		for child in systems_root.get_children():
			if child is Node2D:
				target_node = child as Node2D
				break

	if target_node == null:
		push_warning("Kein Start-Knoten für Galaxy-Kamera gefunden.")
		return

	camera.set_start_position(target_node.global_position)


func _on_galaxy_progression_changed() -> void:
	_refresh_system_node_progression_visuals()
	_refresh_transit_routes()
	if selected_system != null:
		_update_hud_for_selected_system(selected_system)


func _on_base_resources_changed_galaxy_refresh(_base_id: String) -> void:
	if selected_system != null:
		_update_hud_for_selected_system(selected_system)


func _refresh_system_node_progression_visuals() -> void:
	for child in systems_root.get_children():
		if child != null and child.has_method("apply_progression_state"):
			child.call("apply_progression_state")


func _resolve_transit_route_root() -> void:
	if transit_route_root != null and is_instance_valid(transit_route_root):
		return
	transit_route_root = get_node_or_null(NodePath("%TransitRouteRoot")) as Node2D
	if transit_route_root == null:
		transit_route_root = get_node_or_null("TransitRouteRoot") as Node2D
	if transit_route_root == null:
		push_warning("GalaxyMap: TransitRouteRoot nicht gefunden (%TransitRouteRoot und TransitRouteRoot). Transit Routes deaktiviert.")


func _refresh_transit_routes() -> void:
	_resolve_transit_route_root()
	if transit_route_root == null:
		return

	for child in transit_route_root.get_children():
		if child != null:
			child.queue_free()

	for route_entry in _get_transit_routes():
		if route_entry == null:
			continue
		if not (route_entry is GalaxyTransitRouteDefinition):
			continue
		var route_def: GalaxyTransitRouteDefinition = route_entry as GalaxyTransitRouteDefinition
		var from_system_id: String = route_def.from_system_id.strip_edges()
		var to_system_id: String = route_def.to_system_id.strip_edges()
		if from_system_id.is_empty() or to_system_id.is_empty():
			push_warning(
				"GalaxyMap: Transit Route mit leerer ID übersprungen (from='%s' to='%s')."
				% [route_def.from_system_id, route_def.to_system_id]
			)
			continue

		var from_node := _find_system_node_by_definition_id(from_system_id)
		var to_node := _find_system_node_by_definition_id(to_system_id)
		if from_node == null or to_node == null:
			push_warning(
				"GalaxyMap: Transit Route Endpunkt fehlt (from=%s to=%s, from_node=%s to_node=%s)."
				% [from_system_id, to_system_id, from_node, to_node]
			)
			continue

		var from_unlocked: bool = GameSession.is_system_unlocked(from_system_id)
		var to_unlocked: bool = GameSession.is_system_unlocked(to_system_id)
		var route_active: bool = from_unlocked and to_unlocked

		var line := Line2D.new()
		line.antialiased = true
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND

		if route_active:
			line.width = _TRANSIT_ROUTE_ACTIVE_WIDTH
			line.default_color = _TRANSIT_ROUTE_ACTIVE_COLOR
		else:
			line.width = _TRANSIT_ROUTE_INACTIVE_WIDTH
			line.default_color = _TRANSIT_ROUTE_INACTIVE_COLOR

		var p0: Vector2 = transit_route_root.to_local(from_node.global_position)
		var p1: Vector2 = transit_route_root.to_local(to_node.global_position)
		line.points = PackedVector2Array([p0, p1])

		transit_route_root.add_child(line)


func _get_transit_routes() -> Array:
	if galaxy_definition == null:
		return []
	return galaxy_definition.transit_routes


func _get_default_center_system_id() -> String:
	if galaxy_definition != null and not galaxy_definition.default_center_system_id.strip_edges().is_empty():
		return galaxy_definition.default_center_system_id.strip_edges()
	return "solar-system"


func _build_system_nodes_from_definition() -> void:
	if galaxy_definition == null:
		push_warning("GalaxyMap: galaxy_definition ist null — SystemsRoot bleibt leer.")
		return
	if system_node_scene == null:
		push_warning("GalaxyMap: system_node_scene ist null — Systemknoten werden nicht erzeugt.")
		return

	_clear_system_nodes()

	var seen_ids: Dictionary = {}
	for entry in galaxy_definition.systems:
		if entry == null:
			continue
		if not (entry is GalaxyMapSystemEntry):
			push_warning("GalaxyMap: Ungültiger Eintrag in galaxy_definition.systems übersprungen.")
			continue
		var typed_entry: GalaxyMapSystemEntry = entry as GalaxyMapSystemEntry
		if typed_entry.system_definition == null:
			push_warning("GalaxyMap: GalaxyMapSystemEntry ohne system_definition übersprungen.")
			continue

		var sid: String = typed_entry.system_definition.id.strip_edges()
		if sid.is_empty():
			push_warning("GalaxyMap: system_definition.id leer — Eintrag übersprungen.")
			continue

		if seen_ids.has(sid):
			push_warning("GalaxyMap: doppelte system_id auf der Karte: %s — überspringe Duplikat." % sid)
			continue
		seen_ids[sid] = true

		_create_system_node(typed_entry)


func _clear_system_nodes() -> void:
	for child in systems_root.get_children():
		if child != null and is_instance_valid(child):
			child.free()


func _create_system_node(entry: GalaxyMapSystemEntry) -> void:
	if entry.system_definition == null:
		return
	var instance: Node = system_node_scene.instantiate()
	if instance == null:
		push_warning("GalaxyMap: system_node_scene.instantiate() liefert null.")
		return
	if not (instance is Node2D):
		push_warning("GalaxyMap: system_node_scene Root ist kein Node2D.")
		instance.free()
		return

	var node2d: Node2D = instance as Node2D
	node2d.set("system_definition", entry.system_definition)
	node2d.position = entry.map_position
	systems_root.add_child(node2d)


func _find_first_system_node_from_definition_entries() -> Node2D:
	if galaxy_definition == null:
		return null
	for entry in galaxy_definition.systems:
		if entry == null or not (entry is GalaxyMapSystemEntry):
			continue
		var typed: GalaxyMapSystemEntry = entry as GalaxyMapSystemEntry
		if typed.system_definition == null:
			continue
		var sid: String = typed.system_definition.id.strip_edges()
		if sid.is_empty():
			continue
		var found := _find_system_node_by_definition_id(sid)
		if found != null:
			return found
	return null


func _build_system_node_index() -> void:
	_system_node_by_id.clear()
	for child in systems_root.get_children():
		if not (child is Node):
			continue
		var system_def: Variant = child.get("system_definition")
		if system_def is SystemDefinition:
			var typed_definition: SystemDefinition = system_def as SystemDefinition
			if typed_definition != null and not typed_definition.id.is_empty():
				_system_node_by_id[typed_definition.id] = child


func _find_system_node_by_definition_id(system_id: String) -> Node2D:
	var node: Variant = _system_node_by_id.get(system_id, null)
	if node is Node2D:
		return node as Node2D
	return null


func _set_selected_system_node(node: Node) -> void:
	if _selected_system_node != null and _selected_system_node.has_method("set_selected"):
		_selected_system_node.call("set_selected", false)

	_selected_system_node = node

	if _selected_system_node != null and _selected_system_node.has_method("set_selected"):
		_selected_system_node.call("set_selected", true)
