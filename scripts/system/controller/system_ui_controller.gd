## Controls the system scene UI.
## ObjectInfoPanel follows selection. BaseManagementPanel can stay open across selection (held state).
class_name SystemUIController
extends Node

var system_definition: SystemDefinition
var selection: SystemSelectionController
var spawner: SystemSpawner = null

var object_info_panel: PanelContainer
var base_management_panel: PanelContainer
var automation_controller: AutomationController = null

var production_panel: Control = null
var upgrade_panel: Control = null
var top_hud: Control = null
var top_hud_hover_panel: Control = null

const _TOP_HUD_HOVER_SIDE_MARGIN := 12.0

## Mirrors `AutomationController.MiningShipStatus` order (read-only; do not change automation enums here).
const _MS_RT_TO_TARGET := 0
const _MS_RT_MINING := 1
const _MS_RT_TO_BASE := 2
const _MS_RT_UNLOADING := 3
const _MS_RT_WAITING_STORAGE := 4

const _SCAN_PHRASE_ORDER: Array[String] = ["traveling", "scanning", "returning", "idle"]
const _MINING_PHRASE_ORDER: Array[String] = [
	"traveling",
	"mining",
	"returning",
	"unloading",
	"waiting for storage",
	"active",
]


func setup(
	p_system_definition: SystemDefinition,
	p_selection: SystemSelectionController,
	p_object_info_panel: PanelContainer,
	p_base_management_panel: PanelContainer,
	p_automation_controller: AutomationController = null,
	p_spawner: SystemSpawner = null,
	p_production_panel: Control = null,
	p_upgrade_panel: Control = null,
	p_top_hud: Control = null,
	p_top_hud_hover_panel: Control = null,
) -> void:
	system_definition = p_system_definition
	selection = p_selection
	spawner = p_spawner

	object_info_panel = p_object_info_panel
	base_management_panel = p_base_management_panel
	automation_controller = p_automation_controller

	production_panel = p_production_panel
	upgrade_panel = p_upgrade_panel
	top_hud = p_top_hud
	top_hud_hover_panel = p_top_hud_hover_panel

	if object_info_panel != null:
		object_info_panel.visible = false

	if base_management_panel != null:
		if base_management_panel.has_method("hide_panel"):
			base_management_panel.call("hide_panel")
		else:
			base_management_panel.visible = false

	_connect_ui_signals()
	update_all()


func update_all() -> void:
	update_object_info()
	update_base_panel()
	_update_top_hud()


func _process(_delta: float) -> void:
	if object_info_panel == null or not object_info_panel.visible:
		return

	var selected := selection.get_selected_node()
	if selected == null or not (selected is Node2D):
		return

	if spawner == null:
		return

	var base_node := spawner.get_spawned_object(BaseStore.BASE_EARTH) as Node2D
	if base_node == null:
		return

	var dist: float = base_node.global_position.distance_to((selected as Node2D).global_position)
	object_info_panel.call("set_distance_text", "Distanz: %.0f u" % dist)


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


func update_base_panel() -> void:
	if base_management_panel == null:
		return

	var selected_node := selection.get_selected_node()

	var hold_open: bool = false
	if base_management_panel.has_method("is_hold_open_across_selection"):
		hold_open = bool(base_management_panel.call("is_hold_open_across_selection"))

	if selected_node is SystemBody:
		var body := selected_node as SystemBody

		if _selected_body_has_base(body):
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

			return

	if hold_open:
		if base_management_panel.has_method("refresh_while_hold_open"):
			base_management_panel.call("refresh_while_hold_open")
		return

	if base_management_panel.has_method("hide_panel"):
		base_management_panel.call("hide_panel")
	else:
		base_management_panel.visible = false


func _connect_ui_signals() -> void:
	if selection != null and not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)

	if automation_controller != null and automation_controller.has_signal("automation_state_changed"):
		if not automation_controller.automation_state_changed.is_connected(_on_automation_state_changed):
			automation_controller.automation_state_changed.connect(_on_automation_state_changed)

	if not GameSession.object_remaining_resources_changed.is_connected(
		_on_object_remaining_resources_changed
	):
		GameSession.object_remaining_resources_changed.connect(_on_object_remaining_resources_changed)

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

		if object_info_panel.has_signal("close_requested"):
			if not object_info_panel.close_requested.is_connected(_on_object_info_close_requested):
				object_info_panel.close_requested.connect(_on_object_info_close_requested)

	if base_management_panel != null:
		if base_management_panel.has_signal("build_drone_requested"):
			if not base_management_panel.build_drone_requested.is_connected(_on_build_drone_requested):
				base_management_panel.build_drone_requested.connect(_on_build_drone_requested)

		if base_management_panel.has_signal("build_mining_ship_requested"):
			if not base_management_panel.build_mining_ship_requested.is_connected(_on_build_mining_ship_requested):
				base_management_panel.build_mining_ship_requested.connect(_on_build_mining_ship_requested)

		if base_management_panel.has_signal("open_production_requested"):
			if not base_management_panel.open_production_requested.is_connected(_on_base_open_production):
				base_management_panel.open_production_requested.connect(_on_base_open_production)

		if base_management_panel.has_signal("open_upgrades_requested"):
			if not base_management_panel.open_upgrades_requested.is_connected(_on_base_open_upgrades):
				base_management_panel.open_upgrades_requested.connect(_on_base_open_upgrades)

	if production_panel != null:
		if production_panel.has_signal("build_scan_drone_requested"):
			if not production_panel.build_scan_drone_requested.is_connected(_on_build_drone_requested):
				production_panel.build_scan_drone_requested.connect(_on_build_drone_requested)

		if production_panel.has_signal("build_mining_ship_requested"):
			if not production_panel.build_mining_ship_requested.is_connected(_on_build_mining_ship_requested):
				production_panel.build_mining_ship_requested.connect(_on_build_mining_ship_requested)

		if production_panel.has_signal("close_requested"):
			if not production_panel.close_requested.is_connected(_on_production_close):
				production_panel.close_requested.connect(_on_production_close)

	if upgrade_panel != null:
		if upgrade_panel.has_signal("close_requested"):
			if not upgrade_panel.close_requested.is_connected(_on_upgrade_close):
				upgrade_panel.close_requested.connect(_on_upgrade_close)

	if top_hud != null:
		if top_hud.has_signal("hover_requested"):
			if not top_hud.hover_requested.is_connected(_on_top_hud_hover_requested):
				top_hud.hover_requested.connect(_on_top_hud_hover_requested)

		if top_hud.has_signal("hover_cleared"):
			if not top_hud.hover_cleared.is_connected(_on_top_hud_hover_cleared):
				top_hud.hover_cleared.connect(_on_top_hud_hover_cleared)


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
	info["preview_texture"] = _get_preview_texture(selected_node)
	info["distance_text"] = "-"  # Overwritten every frame by _process().

	info["can_scan_with_drone"] = _can_scan_selected_object(selected_node, scan_state)
	info["can_mine_with_ship"] = _can_mine_selected_object(selected_node, scan_state)
	info["is_home_base"] = selected_node is SystemBody and _selected_body_has_base(selected_node as SystemBody)

	var mining_exhausted: bool = false

	if (
		automation_controller != null
		and scan_state != GameSession.SCAN_UNKNOWN
		and not object_id.is_empty()
		and GameSession.has_object_resources(system_definition.id, object_id)
	):
		mining_exhausted = not automation_controller.has_mining_candidates_for_target(object_id)

	info["mining_exhausted"] = mining_exhausted

	if bool(info["is_home_base"]):
		info["active_scan_drone_count"] = 0
		info["active_mining_ship_count"] = 0
		info["scan_drone_supporting_count"] = 0
		info["mining_ship_mining_count"] = 0
		info["mining_bonus"] = 0.0
		info["can_recall_drone"] = false
		info["can_recall_mining_ship"] = false
	else:
		info["active_scan_drone_count"] = _get_active_scan_drone_count(object_id)
		info["active_mining_ship_count"] = _get_active_mining_ship_count(object_id)
		info["scan_drone_supporting_count"] = _get_orbiting_drone_count(object_id)
		info["mining_ship_mining_count"] = _get_mining_ship_mining_status_count(object_id)
		info["mining_bonus"] = _get_mining_bonus_for_object(object_id)
		info["can_recall_drone"] = _get_orbiting_drone_count(object_id) > 0
		info["can_recall_mining_ship"] = _get_active_mining_ship_count(object_id) > 0

	# Lore text comes directly from the definition — not scan-gated.
	if selected_node is SystemBody:
		var body := selected_node as SystemBody
		if body.definition != null and not body.definition.description.is_empty():
			info["lore_text"] = body.definition.description
	elif selected_node is PointOfInterest:
		var poi := selected_node as PointOfInterest
		if poi.definition != null and not poi.definition.description.is_empty():
			info["lore_text"] = poi.definition.description

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

	var object_mid: String = _get_object_id(selected_node)

	if automation_controller != null:
		if not automation_controller.has_mining_candidates_for_target(object_mid):
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
	update_base_panel()


func _on_object_info_close_requested() -> void:
	if selection == null:
		return
	selection.clear_selection(true)


func _on_automation_state_changed() -> void:
	update_object_info()
	update_base_panel()
	_update_top_hud()


func _on_object_remaining_resources_changed(_changed_system_id: String, _changed_object_id: String) -> void:
	update_object_info()


func _on_build_drone_requested() -> void:
	if automation_controller == null:
		return

	automation_controller.spawn_idle_drone_at_base(BaseStore.BASE_EARTH)
	update_all()


func _on_build_mining_ship_requested() -> void:
	if automation_controller == null:
		return

	automation_controller.spawn_idle_mining_ship_at_base(BaseStore.BASE_EARTH)
	update_all()


func _on_object_scan_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		return

	if not _has_available_drone():
		update_object_info()
		return

	automation_controller.launch_scan_drone(object_id)
	update_object_info()


func _on_object_mining_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		return

	if not _has_available_mining_ship():
		update_object_info()
		return

	automation_controller.launch_mining_ship(object_id)
	update_object_info()


func _on_recall_drone_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		return

	automation_controller.recall_one_drone_from_target(object_id)
	update_object_info()


func _on_recall_mining_ship_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if automation_controller == null:
		return

	automation_controller.recall_one_mining_ship_from_target(object_id)
	update_object_info()


func _selected_body_has_base(body: SystemBody) -> bool:
	if body == null:
		return false

	if body.definition != null:
		return body.definition.can_build_base

	return false


func _has_available_drone() -> bool:
	if automation_controller != null:
		return automation_controller.has_idle_drone()

	return _get_base_drone_count() > 0


func _has_available_mining_ship() -> bool:
	if automation_controller != null:
		return automation_controller.has_available_mining_ship()

	return _get_base_mining_ship_count() > 0


func _get_base_drone_count() -> int:
	return GameSession.get_base_drone_count(BaseStore.BASE_EARTH)


func _get_base_mining_ship_count() -> int:
	return GameSession.get_base_mining_ship_count(BaseStore.BASE_EARTH)


func _get_orbiting_drone_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller != null:
		return automation_controller.get_orbiting_drone_count(object_id)

	return 0


func _get_orbiting_mining_ship_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller != null:
		return automation_controller.get_orbiting_mining_ship_count(object_id)

	return 0


func _get_active_scan_drone_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller != null:
		return automation_controller.get_active_scan_drone_count_for_target(object_id)

	return 0


func _get_active_mining_ship_count(object_id: String) -> int:
	return _get_assigned_mining_ship_count(object_id)


func _get_assigned_mining_ship_count(object_id: String) -> int:
	if object_id.is_empty():
		return 0

	if automation_controller != null:
		return automation_controller.get_assigned_mining_ship_count(object_id)

	return 0


func _get_mining_ship_mining_status_count(object_id: String) -> int:
	if object_id.is_empty() or automation_controller == null:
		return 0

	var count := 0

	for uid_var: Variant in automation_controller.mining_ship_runtime_by_unit_id.keys():
		var rt: Dictionary = automation_controller.mining_ship_runtime_by_unit_id[uid_var]

		if str(rt.get("target_id", "")) != object_id:
			continue

		var st := int(rt.get("status", _MS_RT_TO_TARGET))

		if st == AutomationController.MiningShipStatus.MINING:
			count += 1

	return count


func _get_mining_bonus_for_object(object_id: String) -> float:
	if object_id.is_empty():
		return 0.0

	if automation_controller != null:
		return automation_controller.get_mining_bonus_for_target(object_id)

	return 0.0


func _update_top_hud() -> void:
	if top_hud != null and top_hud.has_method("refresh_from_game_session"):
		top_hud.call("refresh_from_game_session")


func _clear_top_hud_hover_panel() -> void:
	if top_hud_hover_panel != null and top_hud_hover_panel.has_method("clear"):
		top_hud_hover_panel.call("clear")


func _get_visible_hover_anchor_panels() -> Array[Control]:
	var panels: Array[Control] = []

	if base_management_panel != null and base_management_panel.visible:
		panels.append(base_management_panel)

	if object_info_panel != null and object_info_panel.visible:
		panels.append(object_info_panel)

	return panels


func _find_nearest_panel_to_x(panels: Array[Control], x: float) -> Control:
	var best_panel: Control = null
	var best_distance: float = INF

	for panel: Control in panels:
		var rect: Rect2 = panel.get_global_rect()
		var center_x: float = rect.position.x + rect.size.x * 0.5
		var distance: float = absf(center_x - x)

		if distance < best_distance:
			best_distance = distance
			best_panel = panel

	return best_panel


func _get_top_hud_hover_position(screen_position: Vector2) -> Vector2:
	var panels: Array[Control] = _get_visible_hover_anchor_panels()

	if panels.is_empty():
		return _get_hover_position_under_widget(screen_position)

	var nearest_panel: Control = _find_nearest_panel_to_x(panels, screen_position.x)

	if nearest_panel == null:
		return _get_hover_position_under_widget(screen_position)

	return _get_hover_position_next_to_panel(nearest_panel, screen_position)


func _get_top_hud_hover_width() -> float:
	if top_hud_hover_panel == null:
		return 180.0
	var c: Control = top_hud_hover_panel as Control
	var width: float = c.size.x
	if width <= 0.0:
		width = c.custom_minimum_size.x
	if width <= 0.0:
		width = 180.0
	return width


func _clamp_hover_position_to_viewport(pos: Vector2, hover_width: float) -> Vector2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return pos
	var margin: float = _TOP_HUD_HOVER_SIDE_MARGIN
	var viewport_width: float = vp.get_visible_rect().size.x
	var min_x: float = margin
	var max_x: float = viewport_width - hover_width - margin
	if max_x < min_x:
		pos.x = viewport_width * 0.5 - hover_width * 0.5
	else:
		pos.x = clampf(pos.x, min_x, max_x)
	return pos


func _get_hover_position_under_widget(screen_position: Vector2) -> Vector2:
	var hover_width: float = _get_top_hud_hover_width()
	var x: float = screen_position.x - hover_width * 0.5
	var y: float = screen_position.y
	return _clamp_hover_position_to_viewport(Vector2(x, y), hover_width)


func _get_hover_position_next_to_panel(panel: Control, screen_position: Vector2) -> Vector2:
	var margin: float = _TOP_HUD_HOVER_SIDE_MARGIN
	var hover_width: float = _get_top_hud_hover_width()
	var vp: Viewport = get_viewport()
	if vp == null:
		return screen_position
	var viewport_width: float = vp.get_visible_rect().size.x

	var rect: Rect2 = panel.get_global_rect()
	var panel_center_x: float = rect.position.x + rect.size.x * 0.5
	var viewport_center_x: float = viewport_width * 0.5

	var x: float = 0.0
	if panel_center_x < viewport_center_x:
		x = rect.position.x + rect.size.x + margin
	else:
		x = rect.position.x - hover_width - margin

	var y: float = rect.position.y
	return _clamp_hover_position_to_viewport(Vector2(x, y), hover_width)


func _on_base_open_production() -> void:
	_clear_top_hud_hover_panel()
	if upgrade_panel != null:
		upgrade_panel.visible = false
	if production_panel != null:
		production_panel.visible = true
		if production_panel.has_method("refresh_from_game_session"):
			production_panel.call("refresh_from_game_session")


func _on_base_open_upgrades() -> void:
	_clear_top_hud_hover_panel()
	if production_panel != null:
		production_panel.visible = false
	if upgrade_panel != null:
		upgrade_panel.visible = true
		if upgrade_panel.has_method("refresh_from_game_session"):
			upgrade_panel.call("refresh_from_game_session")


func _on_production_close() -> void:
	if production_panel != null:
		production_panel.visible = false


func _on_upgrade_close() -> void:
	if upgrade_panel != null:
		upgrade_panel.visible = false


func _on_top_hud_hover_requested(kind: String, screen_position: Vector2) -> void:
	if top_hud_hover_panel == null:
		return

	var content := _build_hover_details(kind)
	var title: String = str(content.get("title", ""))
	var details: Array = content.get("details", [])
	var hint: String = str(content.get("hint", ""))
	var hover_position: Vector2 = _get_top_hud_hover_position(screen_position)
	if top_hud_hover_panel.has_method("show_details"):
		top_hud_hover_panel.call("show_details", title, details, hint, hover_position)


func _on_top_hud_hover_cleared() -> void:
	if top_hud_hover_panel != null and top_hud_hover_panel.has_method("clear"):
		top_hud_hover_panel.call("clear")


func _hover_display_name_for_object_id(object_id: String) -> String:
	if object_id.is_empty():
		return ""
	if spawner != null:
		var node := spawner.get_spawned_object(object_id)
		if node is SystemBody:
			return (node as SystemBody).display_name
		if node is PointOfInterest:
			return (node as PointOfInterest).display_name
	return object_id.capitalize()


func _hover_scan_drone_status_phrase(unit: AutomationUnit) -> String:
	if unit == null or not is_instance_valid(unit):
		return "idle"
	match unit.state:
		AutomationUnit.State.WORKING:
			return "scanning"
		AutomationUnit.State.RETURNING:
			return "returning"
		AutomationUnit.State.TRAVEL_TO_TARGET, AutomationUnit.State.APPROACH_ORBIT:
			return "traveling"
		_:
			return "idle"


func _hover_mining_ship_status_phrase(status: int) -> String:
	match status:
		_MS_RT_MINING:
			return "mining"
		_MS_RT_TO_BASE:
			return "returning"
		_MS_RT_TO_TARGET:
			return "traveling"
		_MS_RT_UNLOADING:
			return "unloading"
		_MS_RT_WAITING_STORAGE:
			return "waiting for storage"
		_:
			return "active"


func _hover_mining_ship_group_object_id(runtime: Dictionary, status: int) -> String:
	if status == _MS_RT_UNLOADING or status == _MS_RT_WAITING_STORAGE:
		return BaseStore.BASE_EARTH
	return str(runtime.get("target_id", ""))


func _hover_unique_object_ids_sorted(count_map: Dictionary) -> Array[String]:
	var ids: Dictionary = {}
	for key_variant: Variant in count_map.keys():
		var key_str := str(key_variant)
		var sep := key_str.find("|")
		if sep < 0:
			continue
		var oid := key_str.substr(0, sep)
		if oid.is_empty():
			continue
		ids[oid] = true
	var out: Array[String] = []
	for id_variant: Variant in ids.keys():
		out.append(str(id_variant))
	out.sort_custom(
		func(a: String, b: String) -> bool:
			var da := _hover_display_name_for_object_id(a).to_lower()
			var db := _hover_display_name_for_object_id(b).to_lower()
			if da == db:
				return a < b
			return da < db
	)
	return out


func _hover_append_aggregate_lines(
	details: Array,
	count_map: Dictionary,
	phrase_order: Array[String]
) -> void:
	for oid: String in _hover_unique_object_ids_sorted(count_map):
		var disp := _hover_display_name_for_object_id(oid)
		for phrase: String in phrase_order:
			var compound := "%s|%s" % [oid, phrase]
			if not count_map.has(compound):
				continue
			var n: int = int(count_map[compound])
			if n <= 0:
				continue
			details.append("%s: %d %s" % [disp, n, phrase])


func _hover_append_scan_drone_supporting_lines(details: Array) -> void:
	if automation_controller == null:
		return

	var per_drone_pct: int = GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(
		BaseStore.BASE_EARTH
	)

	for tid: String in _hover_sorted_scan_assignment_targets():
		var n_sup := automation_controller.get_orbiting_drone_count(tid)

		if n_sup <= 0:
			continue

		var disp := _hover_display_name_for_object_id(tid)
		var yield_pct := n_sup * per_drone_pct
		details.append("%s: %d supporting mining (+%d%%)" % [disp, n_sup, yield_pct])


func _hover_sorted_scan_assignment_targets() -> Array[String]:
	var seen: Dictionary = {}

	if automation_controller != null:
		for v: Variant in automation_controller.scan_drone_target_by_unit_id.values():
			var s := str(v)

			if s.is_empty():
				continue

			seen[s] = true

	var out: Array[String] = []

	for id_variant: Variant in seen.keys():
		out.append(str(id_variant))

	out.sort_custom(
		func(a: String, b: String) -> bool:
			var da := _hover_display_name_for_object_id(a).to_lower()
			var db := _hover_display_name_for_object_id(b).to_lower()

			if da == db:
				return a < b

			return da < db
	)

	return out


func _hover_build_scan_drone_mission_activity() -> Dictionary:
	var count_map: Dictionary = {}

	if automation_controller == null:
		return count_map

	for unit_id_variant: Variant in automation_controller.scan_drone_target_by_unit_id.keys():
		var tid: String = str(automation_controller.scan_drone_target_by_unit_id[unit_id_variant])

		if tid.is_empty():
			continue

		var unit := instance_from_id(int(unit_id_variant)) as AutomationUnit

		if unit == null or not is_instance_valid(unit):
			continue

		if unit.is_available():
			continue

		var phrase := _hover_scan_drone_status_phrase(unit)
		var compound := "%s|%s" % [tid, phrase]
		count_map[compound] = int(count_map.get(compound, 0)) + 1

	return count_map


func _hover_build_mining_ship_activity() -> Dictionary:
	var count_map: Dictionary = {}
	if automation_controller == null:
		return count_map
	for unit_id_variant: Variant in automation_controller.mining_ship_runtime_by_unit_id.keys():
		var rt: Dictionary = automation_controller.mining_ship_runtime_by_unit_id[unit_id_variant]
		if rt.is_empty():
			continue
		var st: int = int(rt.get("status", _MS_RT_TO_TARGET))
		var phrase := _hover_mining_ship_status_phrase(st)
		var oid := _hover_mining_ship_group_object_id(rt, st)
		if oid.is_empty():
			continue
		var compound := "%s|%s" % [oid, phrase]
		count_map[compound] = int(count_map.get(compound, 0)) + 1
	return count_map


func _build_hover_details(kind: String) -> Dictionary:
	var base_id: String = BaseStore.BASE_EARTH
	var details: Array = []
	var title: String = ""
	var hint: String = ""

	match kind:
		"storage":
			title = "Storage"
			var resources_s: Dictionary = GameSession.get_base_resources(base_id)
			var keys_sorted: Array = resources_s.keys()
			keys_sorted.sort()
			var has_any := false
			for res_id: Variant in keys_sorted:
				var amt_s := int(resources_s.get(res_id, 0))
				if amt_s <= 0:
					continue
				has_any = true
				details.append("%s: %d" % [str(res_id).capitalize(), amt_s])
			if not has_any:
				details.append("No resources stored.")
			details.append("Effects:")
			details.append(
				"Base Storage Capacity: %d%%" % GameSession.get_base_storage_capacity_percent(base_id)
			)
			hint = "Storage capacity."

		"scan_drones":
			var total_sd := GameSession.get_base_drone_count(base_id)
			var busy_sd := 0
			if automation_controller != null:
				busy_sd = automation_controller.scan_drone_target_by_unit_id.size()
			var idle_sd := maxi(0, total_sd - busy_sd)
			title = "ScanDrones"
			details.append("Total: %d" % total_sd)
			details.append("Idle: %d" % idle_sd)
			_hover_append_scan_drone_supporting_lines(details)
			var scan_mission := _hover_build_scan_drone_mission_activity()
			if not scan_mission.is_empty():
				_hover_append_aggregate_lines(details, scan_mission, _SCAN_PHRASE_ORDER)
			details.append("Effects:")
			details.append(
				"Mining Support: +%d%% Mining Yield per supporting ScanDrone"
				% GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(base_id)
			)
			details.append("Scan Speed: %d%%" % GameSession.get_scan_drone_scan_speed_percent(base_id))
			hint = "Used for scanning unknown objects."

		"mining_ships":
			var total_ms := GameSession.get_base_mining_ship_count(base_id)
			var busy_ms := 0
			if automation_controller != null:
				busy_ms = automation_controller.mining_ship_runtime_by_unit_id.size()
			var idle_ms := maxi(0, total_ms - busy_ms)
			title = "MiningShips"
			details.append("Total: %d" % total_ms)
			details.append("Idle: %d" % idle_ms)
			var mining_activity := _hover_build_mining_ship_activity()
			if not mining_activity.is_empty():
				_hover_append_aggregate_lines(details, mining_activity, _MINING_PHRASE_ORDER)
			details.append("Effects:")
			details.append(
				"Cargo Capacity: %d%%" % GameSession.get_mining_ship_cargo_capacity_percent(base_id)
			)
			var ms_def: UpgradeDefinition = GameSession.get_current_upgrade_definition(base_id, &"mining_ship")
			if ms_def != null and ms_def.applies_to_new_jobs_only:
				details.append("Applies to newly launched mining missions.")
			hint = "Used for automated resource extraction."

		"colony_ships":
			title = "ColonyShips"
			details = ["Total: 0", "Status: Locked"]
			hint = "Used for system expansion later."

		"jobs":
			var scan_jobs := 0
			var mining_jobs := 0
			if automation_controller != null:
				scan_jobs = automation_controller.scan_drone_target_by_unit_id.size()
				mining_jobs = automation_controller.mining_ship_runtime_by_unit_id.size()
			title = "Jobs"
			details = [
				"Active: %d" % (scan_jobs + mining_jobs),
				"Scanning: %d" % scan_jobs,
				"Mining: %d" % mining_jobs,
			]
			hint = "Current automation tasks."

	return {"title": title, "details": details, "hint": hint}
