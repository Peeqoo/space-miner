## Controls the system scene UI.
## Toggles ObjectInfoPanel and BaseManagementPanel based on current selection.
class_name SystemUIController
extends Node

var system_definition: SystemDefinition
var selection: SystemSelectionController

var action_bar: PanelContainer
var object_info_panel: PanelContainer
var base_management_panel: PanelContainer
var automation_controller: AutomationController = null


func setup(
	p_system_definition: SystemDefinition,
	p_selection: SystemSelectionController,
	p_action_bar: PanelContainer,
	p_object_info_panel: PanelContainer,
	p_base_management_panel: PanelContainer
) -> void:
	system_definition = p_system_definition
	selection = p_selection

	action_bar = p_action_bar
	object_info_panel = p_object_info_panel
	base_management_panel = p_base_management_panel
	automation_controller = _find_automation_controller()

	if object_info_panel != null:
		object_info_panel.visible = false

	if base_management_panel != null:
		base_management_panel.visible = false

	_connect_ui_signals()
	update_all()


func update_all() -> void:
	update_object_info()
	update_action_bar()
	update_base_panel()


func update_ship_ui() -> void:
	update_all()


func update_object_info() -> void:
	if object_info_panel == null:
		return

	var selected_node := selection.get_selected_node()

	if selected_node == null:
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
		else:
			base_management_panel.visible = false

		return

	var body := selected_node as SystemBody

	if not _selected_body_has_base(body):
		if base_management_panel.has_method("hide_panel"):
			base_management_panel.call("hide_panel")
		else:
			base_management_panel.visible = false

		return

	if base_management_panel.has_method("show_for_base"):
		base_management_panel.call(
			"show_for_base",
			system_definition.id,
			body.body_id,
			"%s Base" % body.display_name,
			true
		)
	else:
		base_management_panel.visible = true


func set_action_status(text: String) -> void:
	if action_bar != null and action_bar.has_method("set_action_status"):
		action_bar.call("set_action_status", text)


func _connect_ui_signals() -> void:
	if selection != null and not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)

	if automation_controller != null and automation_controller.has_signal("automation_state_changed"):
		if not automation_controller.automation_state_changed.is_connected(_on_automation_state_changed):
			automation_controller.automation_state_changed.connect(_on_automation_state_changed)

	if object_info_panel != null:
		if object_info_panel.has_signal("scan_requested"):
			if not object_info_panel.scan_requested.is_connected(_on_object_scan_requested):
				object_info_panel.scan_requested.connect(_on_object_scan_requested)

		if object_info_panel.has_signal("mining_requested"):
			if not object_info_panel.mining_requested.is_connected(_on_object_mining_requested):
				object_info_panel.mining_requested.connect(_on_object_mining_requested)

		if object_info_panel.has_signal("recall_drone_requested"):
			if not object_info_panel.recall_drone_requested.is_connected(_on_recall_drone_requested):
				object_info_panel.recall_drone_requested.connect(_on_recall_drone_requested)

		if object_info_panel.has_signal("recall_mining_ship_requested"):
			if not object_info_panel.recall_mining_ship_requested.is_connected(_on_recall_mining_ship_requested):
				object_info_panel.recall_mining_ship_requested.connect(_on_recall_mining_ship_requested)

	if base_management_panel != null:
		if base_management_panel.has_signal("build_drone_requested"):
			if not base_management_panel.build_drone_requested.is_connected(_on_build_drone_requested):
				base_management_panel.build_drone_requested.connect(_on_build_drone_requested)

		if base_management_panel.has_signal("build_mining_ship_requested"):
			if not base_management_panel.build_mining_ship_requested.is_connected(_on_build_mining_ship_requested):
				base_management_panel.build_mining_ship_requested.connect(_on_build_mining_ship_requested)


func _build_action_bar_state() -> Dictionary:
	return {
		"is_docked": false,
		"can_undock": false,
		"can_approach": false,
		"can_dock": false,
		"can_scan": false,
		"can_mine": false,
		"mining_active": false,
		"show_unload_cargo": false,
		"can_unload_cargo": false,
		"show_build_base": false,
		"can_build_base": false,
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
	info["distance_text"] = "-"
	info["preview_texture"] = _get_preview_texture(selected_node)

	info["can_scan_with_drone"] = _can_scan_selected_object(selected_node, scan_state)
	info["can_mine_with_ship"] = _can_mine_selected_object(selected_node, scan_state)
	info["is_home_base"] = selected_node is SystemBody and _selected_body_has_base(selected_node as SystemBody)

	if bool(info["is_home_base"]):
		info["orbiting_drone_count"] = 0
		info["orbiting_mining_ship_count"] = 0
		info["mining_bonus"] = 0.0
		info["can_recall_drone"] = false
		info["can_recall_mining_ship"] = false
	else:
		info["orbiting_drone_count"] = _get_orbiting_drone_count(object_id)
		info["orbiting_mining_ship_count"] = _get_orbiting_mining_ship_count(object_id)
		info["mining_bonus"] = _get_mining_bonus_for_object(object_id)
		info["can_recall_drone"] = int(info["orbiting_drone_count"]) > 0
		info["can_recall_mining_ship"] = _get_assigned_mining_ship_count(object_id) > 0

	if not info.has("lore_text"):
		info["lore_text"] = "Keine Beschreibung verfügbar."

	return info


func _can_scan_selected_object(selected_node: Node, _scan_state: String) -> bool:
	if selected_node == null:
		return false

	if not selected_node is SystemBody and not selected_node is PointOfInterest:
		return false

	if selected_node is SystemBody and _selected_body_has_base(selected_node as SystemBody):
		return false

	return _has_available_drone()


func _can_mine_selected_object(selected_node: Node, scan_state: String) -> bool:
	if selected_node == null:
		return false

	if not selected_node is SystemBody and not selected_node is PointOfInterest:
		return false

	if selected_node is SystemBody and _selected_body_has_base(selected_node as SystemBody):
		return false

	if scan_state == GameSession.SCAN_UNKNOWN:
		return false

	return _has_available_mining_ship()


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
	update_object_info()
	update_action_bar()
	update_base_panel()


func _on_automation_state_changed() -> void:
	update_object_info()
	update_base_panel()


func _on_build_drone_requested() -> void:
	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller == null:
		set_action_status("AutomationController fehlt.")
		return

	automation_controller.spawn_idle_drone_at_base("earth")
	set_action_status("Drone gebaut.")
	update_all()


func _on_build_mining_ship_requested() -> void:
	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller == null:
		set_action_status("AutomationController fehlt.")
		return

	automation_controller.spawn_idle_mining_ship_at_base("earth")
	set_action_status("Mining Ship gebaut.")
	update_all()


func _on_object_scan_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller == null:
		set_action_status("AutomationController fehlt.")
		return

	if not _has_available_drone():
		set_action_status("Keine freie Drone verfügbar.")
		update_object_info()
		return

	automation_controller.launch_scan_drone(object_id)
	set_action_status("Scan-Drone gestartet: %s" % object_id)
	update_object_info()


func _on_object_mining_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller == null:
		set_action_status("AutomationController fehlt.")
		return

	if not _has_available_mining_ship():
		set_action_status("Kein freies Mining Ship verfügbar.")
		update_object_info()
		return

	automation_controller.launch_mining_ship(object_id)
	set_action_status("Mining Ship gestartet: %s" % object_id)
	update_object_info()


func _on_recall_drone_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller == null:
		set_action_status("AutomationController fehlt.")
		return

	if not automation_controller.recall_one_drone_from_target(object_id):
		set_action_status("Keine Drone im Orbit von %s." % object_id)
	else:
		set_action_status("Eine Drone kehrt zu Earth zurück.")

	update_object_info()


func _on_recall_mining_ship_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller == null:
		set_action_status("AutomationController fehlt.")
		return

	if not automation_controller.recall_one_mining_ship_from_target(object_id):
		set_action_status("Kein Mining Ship im Orbit von %s." % object_id)
	else:
		set_action_status("Ein Mining Ship kehrt zu Earth zurück.")

	update_object_info()


func _selected_body_has_base(body: SystemBody) -> bool:
	if body == null:
		return false

	return body.body_id == "earth"


func _has_available_drone() -> bool:
	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller != null and automation_controller.has_method("has_idle_drone"):
		return bool(automation_controller.call("has_idle_drone"))

	return _get_base_drone_count() > 0


func _has_available_mining_ship() -> bool:
	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller != null and automation_controller.has_method("has_idle_mining_ship"):
		return bool(automation_controller.call("has_idle_mining_ship"))

	return _get_base_mining_ship_count() > 0


func _get_base_drone_count() -> int:
	if GameSession.has_method("get_base_drone_count"):
		return int(GameSession.call("get_base_drone_count", BaseStore.BASE_EARTH))

	if GameSession.has_method("get_drone_count"):
		return int(GameSession.call("get_drone_count"))

	return 0


func _get_base_mining_ship_count() -> int:
	if GameSession.has_method("get_base_mining_ship_count"):
		return int(GameSession.call("get_base_mining_ship_count", BaseStore.BASE_EARTH))

	if GameSession.has_method("get_mining_ship_count"):
		return int(GameSession.call("get_mining_ship_count"))

	return 0


func _get_orbiting_drone_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller != null and automation_controller.has_method("get_orbiting_drone_count"):
		return int(automation_controller.call("get_orbiting_drone_count", object_id))

	return 0


func _get_orbiting_mining_ship_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller != null and automation_controller.has_method("get_orbiting_mining_ship_count"):
		return int(automation_controller.call("get_orbiting_mining_ship_count", object_id))

	return 0


func _get_assigned_mining_ship_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller != null and automation_controller.has_method("get_assigned_mining_ship_count"):
		return int(automation_controller.call("get_assigned_mining_ship_count", object_id))

	return 0


func _get_mining_bonus_for_object(object_id: String) -> float:
	if object_id.is_empty():
		return 0.0

	if automation_controller == null:
		automation_controller = _find_automation_controller()

	if automation_controller != null and automation_controller.has_method("get_mining_bonus_for_target"):
		return float(automation_controller.call("get_mining_bonus_for_target", object_id))

	return 0.0


func _find_automation_controller() -> AutomationController:
	var parent_node := get_parent()

	if parent_node == null:
		return null

	return parent_node.get_node_or_null("AutomationController") as AutomationController
