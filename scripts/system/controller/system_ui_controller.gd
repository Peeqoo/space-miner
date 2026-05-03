## Controls the system scene UI.
## Toggles ShipHud and ObjectInfoPanel based on current selection.
class_name SystemUIController
extends Node

var system_definition: SystemDefinition
var player_ship: CharacterBody2D
var ship_state: SystemShipStateController
var selection: SystemSelectionController

var ship_hud: PanelContainer
var action_bar: PanelContainer
var object_info_panel: PanelContainer
var base_management_panel: PanelContainer

var scan_active: bool = false
var scan_target: Node = null
var scan_elapsed: float = 0.0
var scan_duration: float = 2.5


func setup(
	p_system_definition: SystemDefinition,
	p_player_ship: CharacterBody2D,
	p_ship_state: SystemShipStateController,
	p_selection: SystemSelectionController,
	p_ship_hud: PanelContainer,
	p_action_bar: PanelContainer,
	p_object_info_panel: PanelContainer,
	p_base_management_panel: PanelContainer
) -> void:
	system_definition = p_system_definition
	player_ship = p_player_ship
	ship_state = p_ship_state
	selection = p_selection

	ship_hud = p_ship_hud
	action_bar = p_action_bar
	object_info_panel = p_object_info_panel
	base_management_panel = p_base_management_panel

	if ship_hud != null:
		ship_hud.visible = false

	if object_info_panel != null:
		object_info_panel.visible = false

	_connect_ui_signals()
	update_all()


func _process(delta: float) -> void:
	if not scan_active:
		return

	if scan_target == null or not is_instance_valid(scan_target):
		_cancel_scan("Scan abgebrochen.")
		return

	scan_elapsed += delta

	var progress: float = clampf(scan_elapsed / scan_duration, 0.0, 1.0)
	set_action_status("Scan läuft... %d%%" % int(progress * 100.0))

	if scan_elapsed >= scan_duration:
		_complete_scan()


func update_all() -> void:
	update_ship_hud()
	update_object_info()
	update_action_bar()
	update_base_panel()


func update_ship_ui() -> void:
	update_all()


func update_ship_hud() -> void:
	if ship_hud == null:
		return

	ship_hud.visible = _should_show_ship_hud()

	if ship_hud.visible and ship_hud.has_method("refresh_from_game_session"):
		ship_hud.call("refresh_from_game_session")


func update_object_info() -> void:
	if object_info_panel == null:
		return

	var selected_node := selection.get_selected_node()

	if selected_node == null or selected_node == player_ship:
		object_info_panel.visible = false

		if object_info_panel.has_method("show_empty"):
			object_info_panel.call("show_empty")

		return

	object_info_panel.visible = true

	var info: Dictionary = _build_selected_object_info(selected_node)

	if selected_node is SystemBody:
		if object_info_panel.has_method("show_body_info"):
			object_info_panel.call("show_body_info", info)
	elif selected_node is PointOfInterest:
		if object_info_panel.has_method("show_poi_info"):
			object_info_panel.call("show_poi_info", info)


func update_action_bar() -> void:
	if action_bar == null or not action_bar.has_method("apply_state"):
		return

	action_bar.call("apply_state", _build_action_bar_state())


func update_base_panel() -> void:
	if base_management_panel == null:
		return

	var selected_node := selection.get_selected_node()

	if not selected_node is SystemBody:
		if base_management_panel.has_method("hide_panel"):
			base_management_panel.call("hide_panel")
		return

	var body := selected_node as SystemBody
	var has_base := _selected_body_has_base(body)

	if not has_base:
		if base_management_panel.has_method("hide_panel"):
			base_management_panel.call("hide_panel")
		return

	if base_management_panel.has_method("show_for_base"):
		base_management_panel.call(
			"show_for_base",
			system_definition.id,
			body.body_id,
			"%s Base" % body.display_name,
			ship_state.is_docked and ship_state.docked_body == body
		)


func set_action_status(text: String) -> void:
	if action_bar != null and action_bar.has_method("set_action_status"):
		action_bar.call("set_action_status", text)


func _connect_ui_signals() -> void:
	if selection != null and not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)

	if ship_hud != null and ship_hud.has_signal("galaxy_map_requested"):
		if not ship_hud.galaxy_map_requested.is_connected(_on_galaxy_map_requested):
			ship_hud.galaxy_map_requested.connect(_on_galaxy_map_requested)

	if action_bar == null:
		return

	_connect_action_signal("undock_requested", _on_undock_requested)
	_connect_action_signal("approach_requested", _on_approach_requested)
	_connect_action_signal("dock_requested", _on_dock_requested)
	_connect_action_signal("scan_requested", _on_scan_requested)
	_connect_action_signal("mining_requested", _on_mining_requested)
	_connect_action_signal("stop_mining_requested", _on_stop_mining_requested)
	_connect_action_signal("unload_cargo_requested", _on_unload_cargo_requested)
	_connect_action_signal("build_base_requested", _on_build_base_requested)


func _connect_action_signal(signal_name: StringName, callable_fn: Callable) -> void:
	if action_bar == null:
		return

	if not action_bar.has_signal(signal_name):
		return

	if not action_bar.is_connected(signal_name, callable_fn):
		action_bar.connect(signal_name, callable_fn)


func _build_action_bar_state() -> Dictionary:
	var selected_node := selection.get_selected_node()
	var selected_body := selected_node as SystemBody
	var has_selection := selected_node != null
	var is_ship_selected := selected_node == player_ship
	var is_docked := ship_state.is_docked
	var can_dock := false

	if selected_body != null and not is_docked:
		can_dock = _is_ship_in_range(selected_body, 100.0)

	return {
		"is_docked": is_docked,
		"can_undock": is_docked and (is_ship_selected or selected_body != null) and not scan_active,
		"can_approach": has_selection and not is_ship_selected and not is_docked and not scan_active,
		"can_dock": can_dock and not scan_active,
		"can_scan": has_selection and not is_ship_selected and not scan_active,
		"can_mine": has_selection and not is_ship_selected and not is_docked and not scan_active,
		"mining_active": scan_active,
		"show_unload_cargo": _should_show_ship_hud(),
		"can_unload_cargo": _should_show_ship_hud() and GameSession.get_cargo_used() > 0,
		"show_build_base": selected_body != null,
		"can_build_base": selected_body != null and is_docked and not _selected_body_has_base(selected_body),
	}


func _build_selected_object_info(selected_node: Node) -> Dictionary:
	var object_id := _get_object_id(selected_node)
	var scan_state := GameSession.get_object_scan_state(system_definition.id, object_id)
	var scanner_tier := GameSession.get_active_scanner_tier()

	var info: Dictionary = {}

	if selected_node.has_method("build_scan_info"):
		info = selected_node.call("build_scan_info", scan_state, scanner_tier)
	elif selected_node.has_method("get_info"):
		info = selected_node.call("get_info")

	info["scan_state"] = scan_state
	info["distance_text"] = _get_distance_text(selected_node)
	info["preview_texture"] = _get_preview_texture(selected_node)

	if not info.has("lore_text"):
		info["lore_text"] = "Keine Beschreibung verfügbar."

	return info


func _get_distance_text(node: Node) -> String:
	if not node is Node2D:
		return "-"

	var distance := player_ship.global_position.distance_to((node as Node2D).global_position)
	return "%d km" % int(round(distance))


func _get_preview_texture(node: Node) -> Texture2D:
	if node is SystemBody:
		var body := node as SystemBody

		if body.body_visual != null:
			return body.body_visual.texture

	if node is PointOfInterest:
		var poi := node as PointOfInterest

		if poi.poi_visual != null:
			return poi.poi_visual.texture

	return null


func _get_object_id(node: Node) -> String:
	if node is SystemBody:
		return (node as SystemBody).body_id

	if node is PointOfInterest:
		return (node as PointOfInterest).poi_id

	return ""


func _on_selection_changed(_selected_node: Node) -> void:
	if scan_active:
		_cancel_scan("Scan abgebrochen.")

	update_ship_hud()
	update_object_info()
	update_action_bar()
	update_base_panel()


func _on_undock_requested() -> void:
	ship_state.launch_ship()
	set_action_status("Abgedockt.")
	update_all()


func _on_approach_requested() -> void:
	var selected_node := selection.get_selected_node()

	if not selected_node is Node2D:
		return

	if selected_node == player_ship:
		return

	var nav := player_ship.get_node_or_null("ShipNavigationComponent") as ShipNavigationComponent

	if nav != null:
		nav.set_target((selected_node as Node2D).global_position)
		set_action_status("Anflug gestartet.")

	update_all()


func _on_dock_requested() -> void:
	var selected_node := selection.get_selected_node()

	if not selected_node is SystemBody:
		return

	var body := selected_node as SystemBody

	if not _is_ship_in_range(body, 100.0):
		set_action_status("Zu weit entfernt zum Andocken.")
		update_all()
		return

	ship_state.dock_to_body(body)
	set_action_status("Angedockt.")
	update_all()


func _on_scan_requested() -> void:
	var selected_node := selection.get_selected_node()

	if selected_node == null or selected_node == player_ship:
		return

	if scan_active:
		return

	var object_id := _get_object_id(selected_node)

	if object_id.is_empty():
		return

	scan_target = selected_node
	scan_elapsed = 0.0
	scan_active = true

	set_action_status("Scan gestartet...")
	update_action_bar()


func _on_mining_requested() -> void:
	set_action_status("Mining ist aktuell noch nicht wieder verbunden.")
	update_all()


func _on_stop_mining_requested() -> void:
	if scan_active:
		_cancel_scan("Scan abgebrochen.")
		update_all()
		return

	set_action_status("Mining gestoppt.")
	update_all()


func _on_unload_cargo_requested() -> void:
	GameSession.clear_cargo()
	set_action_status("Cargo entladen.")
	update_all()


func _on_build_base_requested() -> void:
	set_action_status("Base-Bau ist aktuell noch nicht wieder verbunden.")
	update_all()


func _on_galaxy_map_requested() -> void:
	ship_state.save_current_ship_state(selection.get_selected_node())
	SceneFlow.goto_galaxy()


func _complete_scan() -> void:
	if scan_target == null or not is_instance_valid(scan_target):
		_cancel_scan("Scan abgebrochen.")
		return

	var object_id := _get_object_id(scan_target)

	if object_id.is_empty():
		_cancel_scan("Scan abgebrochen.")
		return

	GameSession.set_object_scan_state(system_definition.id, object_id, GameSession.SCAN_BASIC)

	scan_active = false
	scan_target = null
	scan_elapsed = 0.0

	set_action_status("Scan abgeschlossen.")
	update_all()


func _cancel_scan(status_text: String) -> void:
	scan_active = false
	scan_target = null
	scan_elapsed = 0.0
	set_action_status(status_text)


func _should_show_ship_hud() -> bool:
	var selected_node := selection.get_selected_node()

	if selected_node == player_ship:
		return true

	if selected_node is SystemBody:
		var selected_body := selected_node as SystemBody
		return ship_state.is_docked and ship_state.docked_body == selected_body

	return false


func _is_ship_in_range(target: Node2D, distance: float) -> bool:
	return player_ship.global_position.distance_to(target.global_position) <= distance


func _selected_body_has_base(_body: SystemBody) -> bool:
	return false
