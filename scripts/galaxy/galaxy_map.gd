extends Node2D

const HUD_SCENE_PATH: String = "UI/GalaxyMapHUD"
@export var start_center_system_id: String = "sol"

@onready var camera: SystemCameraController = $CameraRoot/GalaxyCamera2D
@onready var hud: GalaxyMapHUD = get_node_or_null(HUD_SCENE_PATH) as GalaxyMapHUD
@onready var systems_root: Node2D = $SystemsRoot

var selected_system: SystemDefinition = null
var _selected_system_node: Node = null
var _system_node_by_id: Dictionary = {}


func _ready() -> void:
	add_to_group("galaxy_map_root")
	_build_system_node_index()

	if hud != null and not hud.enter_requested.is_connected(_on_enter_pressed):
		hud.enter_requested.connect(_on_enter_pressed)

	GameSession.ensure_default_system_loaded()
	_update_current_system_display()

	if GameSession.current_system_definition != null:
		select_system(GameSession.current_system_definition)
	elif hud != null:
		hud.show_no_selection_state()

	call_deferred("_apply_start_camera_target")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			clear_selection()


func select_system(system_def: SystemDefinition) -> void:
	if system_def == null:
		push_warning("select_system(): system_def ist null")
		return

	selected_system = system_def
	_set_selected_system_node(_system_node_by_id.get(system_def.id, null))
	_update_current_system_display()
	_update_hud_for_selected_system(system_def)


func clear_selection() -> void:
	selected_system = null
	_set_selected_system_node(null)
	_update_current_system_display()
	if hud != null:
		hud.show_no_selection_state()


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


func _update_hud_for_selected_system(system_def: SystemDefinition) -> void:
	if hud == null:
		return

	var is_current: bool = system_def.id == GameSession.current_system_id
	var can_enter: bool = is_current or GameSession.can_leave_current_system()
	var known_planets_count: int = _count_known_bodies(system_def)
	var known_resources_text: String = _build_known_resources_summary(system_def)
	var info_text: String = system_def.description.strip_edges()

	hud.show_system_info(
		system_def.display_name,
		known_planets_count,
		known_resources_text,
		info_text,
		can_enter,
		is_current
	)


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
	var display_parts: Array[String] = []
	for i in range(top_count):
		display_parts.append(_format_resource_name(resource_ids[i]))

	return ", ".join(PackedStringArray(display_parts))


func _get_visible_resources_for_body(body_def: SystemBodyDefinition, scan_state: String) -> Array[String]:
	var resources: Array[String] = []

	if scan_state == GameSession.SCAN_UNKNOWN:
		return resources

	for resource_id in body_def.scan_basic_resources:
		resources.append(str(resource_id))

	if GameSession._scan_state_rank(scan_state) >= GameSession._scan_state_rank(GameSession.SCAN_DEEP):
		for resource_id in body_def.scan_deep_resources:
			resources.append(str(resource_id))

	if GameSession._scan_state_rank(scan_state) >= GameSession._scan_state_rank(GameSession.SCAN_SPECIAL):
		for resource_id in body_def.scan_special_resources:
			resources.append(str(resource_id))

	return resources


func _format_resource_name(resource_id: String) -> String:
	if resource_id.is_empty():
		return ""
	return resource_id.substr(0, 1).to_upper() + resource_id.substr(1)


func _apply_start_camera_target() -> void:
	var target_node: Node2D = _find_system_node_by_definition_id(start_center_system_id)

	if target_node == null and GameSession.current_system_definition != null:
		target_node = _find_system_node_by_definition_id(GameSession.current_system_definition.id)

	if target_node == null:
		push_warning("Kein Start-Knoten für Galaxy-Kamera gefunden.")
		return

	camera.set_start_position(target_node.global_position)


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
