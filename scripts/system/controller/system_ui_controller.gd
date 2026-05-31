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
var survey_probe_mission_controller: SurveyProbeMissionController = null
var base_sensor_pulse_controller: BaseSensorPulseController = null

var production_panel: Control = null
var upgrade_panel: Control = null
var storage_panel: Control = null
var top_hud: Control = null
var top_hud_hover_panel: Control = null

## Primary celestial body id for fleet/storage TopHUD hovers (= `BaseStore` key).
var _primary_base_body_id: String = ""

var _storage_context_base_id: String = ""

## Mirrors `AutomationController.MiningShipStatus` order (read-only; do not change automation enums here).
const _MS_RT_TO_TARGET := 0
const _MS_RT_MINING := 1
const _MS_RT_TO_BASE := 2
const _MS_RT_UNLOADING := 3
const _MS_RT_WAITING_STORAGE := 4


func setup(
	p_system_definition: SystemDefinition,
	p_selection: SystemSelectionController,
	p_object_info_panel: PanelContainer,
	p_base_management_panel: PanelContainer,
	p_automation_controller: AutomationController = null,
	p_spawner: SystemSpawner = null,
	p_survey_probe_mission_controller: SurveyProbeMissionController = null,
	p_base_sensor_pulse_controller: BaseSensorPulseController = null,
	p_production_panel: Control = null,
	p_upgrade_panel: Control = null,
	p_top_hud: Control = null,
	p_top_hud_hover_panel: Control = null,
	p_storage_panel: Control = null,
	p_primary_base_body_id: String = "",
) -> void:
	system_definition = p_system_definition
	selection = p_selection
	spawner = p_spawner

	object_info_panel = p_object_info_panel
	base_management_panel = p_base_management_panel
	automation_controller = p_automation_controller
	survey_probe_mission_controller = p_survey_probe_mission_controller
	base_sensor_pulse_controller = p_base_sensor_pulse_controller

	production_panel = p_production_panel
	upgrade_panel = p_upgrade_panel
	top_hud = p_top_hud
	top_hud_hover_panel = p_top_hud_hover_panel
	storage_panel = p_storage_panel
	_primary_base_body_id = p_primary_base_body_id.strip_edges()
	add_to_group(&"system_ui_controller")

	if top_hud != null and top_hud.has_method("set_primary_base_body_id"):
		top_hud.call("set_primary_base_body_id", _primary_base_body_id)

	if object_info_panel != null:
		object_info_panel.visible = false

	if base_management_panel != null:
		if base_management_panel.has_method("hide_panel"):
			base_management_panel.call("hide_panel")
		else:
			base_management_panel.visible = false

	_connect_ui_signals()
	_hide_base_subpanels()
	update_all()


func update_all() -> void:
	update_object_info()
	update_base_panel()
	_apply_session_economy_gate()
	_update_top_hud()


## Session focus / spawn reference from `SystemScene` (`start_body_id`). Economy uses established base when present.
func _current_system_definition_id() -> String:
	if system_definition == null:
		return ""
	return system_definition.id.strip_edges()


## BaseStore / UI economy key: established base in this system, else start/focus body (economy usually gated then).
func _economy_body_id_for_ui() -> String:
	var sid := _current_system_definition_id()
	if not sid.is_empty():
		var est := GameSession.get_established_base_id_for_system(sid).strip_edges()
		if not est.is_empty():
			return est
	return _primary_base_body_id.strip_edges()


func _session_primary_base_established() -> bool:
	var sid := _current_system_definition_id()
	if sid.is_empty():
		return false
	return not GameSession.get_established_base_id_for_system(sid).is_empty()


func _apply_session_economy_gate() -> void:
	var ok := _session_primary_base_established()
	if base_management_panel != null and base_management_panel.has_method("set_economy_actions_enabled"):
		base_management_panel.call("set_economy_actions_enabled", ok)
	if not ok:
		if production_panel != null:
			production_panel.visible = false
		if upgrade_panel != null:
			upgrade_panel.visible = false
	else:
		_sync_production_upgrade_economy_body_ids()


func _sync_production_upgrade_economy_body_ids() -> void:
	var bid := _economy_body_id_for_ui().strip_edges()
	if bid.is_empty():
		return
	if production_panel != null and production_panel.has_method("set_economy_body_id"):
		production_panel.call("set_economy_body_id", bid)
	if upgrade_panel != null and upgrade_panel.has_method("set_economy_body_id"):
		upgrade_panel.call("set_economy_body_id", bid)


func _process(_delta: float) -> void:
	if not GameSession.get_pending_colonization_operations().is_empty():
		var completed_colonization: Array[String] = GameSession.process_colonization_operations()
		if not completed_colonization.is_empty():
			update_object_info()
			_update_top_hud()

	if object_info_panel == null or not object_info_panel.visible:
		return

	var selected := selection.get_selected_node()
	if selected == null or not (selected is Node2D):
		return

	if spawner == null:
		return

	var base_ref: String = _economy_body_id_for_ui().strip_edges()
	if base_ref.is_empty():
		return

	var base_node := spawner.get_spawned_object(base_ref) as Node2D
	if base_node == null:
		return

	var dist: float = base_node.global_position.distance_to((selected as Node2D).global_position)
	object_info_panel.call("set_distance_text", "%.0f u" % dist)


func update_object_info() -> void:
	if object_info_panel == null:
		return

	var selected_node := selection.get_selected_node()

	if selected_node == null:
		var was_object_info_visible := object_info_panel.visible

		if was_object_info_visible and object_info_panel.has_method("show_empty"):
			object_info_panel.call("show_empty")

		object_info_panel.visible = false
		return

	object_info_panel.visible = true

	var info: Dictionary = _build_selected_object_info(selected_node)

	if selected_node is SignalMarker:
		if object_info_panel.has_method("show_body_info"):
			object_info_panel.call("show_body_info", info)
	elif selected_node is SystemBody:
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

		if _selected_body_has_established_base(body):
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

	_hide_base_subpanels()


func _hide_base_subpanels() -> void:
	_clear_top_hud_hover_panel()
	if production_panel != null:
		production_panel.visible = false
	if upgrade_panel != null:
		upgrade_panel.visible = false
	if storage_panel != null:
		storage_panel.visible = false
	_storage_context_base_id = ""


func _on_base_management_close_requested() -> void:
	_hide_base_subpanels()


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

	if not GameSession.base_resources_changed.is_connected(_on_base_resources_changed_ui_refresh):
		GameSession.base_resources_changed.connect(_on_base_resources_changed_ui_refresh)

	if not GameSession.base_upgrades_changed.is_connected(_on_base_upgrades_changed_ui_refresh):
		GameSession.base_upgrades_changed.connect(_on_base_upgrades_changed_ui_refresh)

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

		if object_info_panel.has_signal("colonization_requested"):
			if not object_info_panel.colonization_requested.is_connected(_on_colonization_requested):
				object_info_panel.colonization_requested.connect(_on_colonization_requested)

		_connect_object_info_investigate_signal()
		_connect_object_info_sensor_pulse_signal()

	if survey_probe_mission_controller != null:
		if not survey_probe_mission_controller.investigate_mission_changed.is_connected(
			_on_survey_probe_mission_changed
		):
			survey_probe_mission_controller.investigate_mission_changed.connect(
				_on_survey_probe_mission_changed
			)
		if not survey_probe_mission_controller.investigation_progress_changed.is_connected(
			_on_investigation_progress_changed
		):
			survey_probe_mission_controller.investigation_progress_changed.connect(
				_on_investigation_progress_changed
			)

	if base_sensor_pulse_controller != null:
		if not base_sensor_pulse_controller.sensor_pulse_changed.is_connected(_on_sensor_pulse_changed):
			base_sensor_pulse_controller.sensor_pulse_changed.connect(_on_sensor_pulse_changed)
		if not base_sensor_pulse_controller.sensor_pulse_progress_changed.is_connected(
			_on_sensor_pulse_progress_changed
		):
			base_sensor_pulse_controller.sensor_pulse_progress_changed.connect(
				_on_sensor_pulse_progress_changed
			)

	if base_management_panel != null:
		if base_management_panel.has_signal("open_production_requested"):
			if not base_management_panel.open_production_requested.is_connected(_on_base_open_production):
				base_management_panel.open_production_requested.connect(_on_base_open_production)

		if base_management_panel.has_signal("open_upgrades_requested"):
			if not base_management_panel.open_upgrades_requested.is_connected(_on_base_open_upgrades):
				base_management_panel.open_upgrades_requested.connect(_on_base_open_upgrades)

		if base_management_panel.has_signal("open_storage_requested"):
			if not base_management_panel.open_storage_requested.is_connected(_on_base_open_storage):
				base_management_panel.open_storage_requested.connect(_on_base_open_storage)

		if base_management_panel.has_signal("close_requested"):
			if not base_management_panel.close_requested.is_connected(_on_base_management_close_requested):
				base_management_panel.close_requested.connect(_on_base_management_close_requested)

	if production_panel != null:
		if production_panel.has_signal("build_scan_drone_requested"):
			if not production_panel.build_scan_drone_requested.is_connected(_on_build_drone_requested):
				production_panel.build_scan_drone_requested.connect(_on_build_drone_requested)

		if production_panel.has_signal("build_mining_ship_requested"):
			if not production_panel.build_mining_ship_requested.is_connected(_on_build_mining_ship_requested):
				production_panel.build_mining_ship_requested.connect(_on_build_mining_ship_requested)

		if production_panel.has_signal("build_survey_probe_requested"):
			if not production_panel.build_survey_probe_requested.is_connected(_on_build_survey_probe_requested):
				production_panel.build_survey_probe_requested.connect(_on_build_survey_probe_requested)

		if production_panel.has_signal("build_colony_ship_requested"):
			if not production_panel.build_colony_ship_requested.is_connected(_on_build_colony_ship_requested):
				production_panel.build_colony_ship_requested.connect(_on_build_colony_ship_requested)

		if production_panel.has_signal("close_requested"):
			if not production_panel.close_requested.is_connected(_on_production_close):
				production_panel.close_requested.connect(_on_production_close)

	if upgrade_panel != null:
		if upgrade_panel.has_signal("close_requested"):
			if not upgrade_panel.close_requested.is_connected(_on_upgrade_close):
				upgrade_panel.close_requested.connect(_on_upgrade_close)

	if storage_panel != null:
		if storage_panel.has_signal("close_requested"):
			if not storage_panel.close_requested.is_connected(_on_storage_panel_close_requested):
				storage_panel.close_requested.connect(_on_storage_panel_close_requested)

		if storage_panel.has_signal("discard_resource_requested"):
			if not storage_panel.discard_resource_requested.is_connected(_on_storage_panel_discard_requested):
				storage_panel.discard_resource_requested.connect(_on_storage_panel_discard_requested)

	if top_hud != null:
		if top_hud.has_signal("hover_requested"):
			if not top_hud.hover_requested.is_connected(_on_top_hud_hover_requested):
				top_hud.hover_requested.connect(_on_top_hud_hover_requested)

		if top_hud.has_signal("hover_cleared"):
			if not top_hud.hover_cleared.is_connected(_on_top_hud_hover_cleared):
				top_hud.hover_cleared.connect(_on_top_hud_hover_cleared)


func _build_signal_marker_info(marker: SignalMarker) -> Dictionary:
	var info: Dictionary = marker.build_signal_info()
	var object_id: String = marker.object_id.strip_edges()
	var base_id: String = _economy_body_id_for_ui()

	var can_investigate: bool = false
	var blocked_reason: String = ""
	var in_progress: bool = false

	if survey_probe_mission_controller != null:
		in_progress = survey_probe_mission_controller.is_investigate_active(object_id)
		var gate: Dictionary = survey_probe_mission_controller.can_investigate_signal(object_id, base_id)
		can_investigate = gate.get("ok", false) == true
		blocked_reason = str(gate.get("blocked_reason", "")).strip_edges()
	else:
		blocked_reason = DiscoverySignalUiTextDefinition.get_template(
			SurveyProbeMissionController.REASON_BASE_MISSING
		)

	if in_progress and not can_investigate and blocked_reason.is_empty():
		blocked_reason = DiscoverySignalUiTextDefinition.get_template(
			SurveyProbeMissionController.REASON_IN_PROGRESS
		)

	info["can_investigate_signal"] = can_investigate
	info["investigate_blocked_reason"] = blocked_reason
	info["investigate_in_progress"] = in_progress

	if in_progress:
		info["lore_text"] = DiscoverySignalUiTextDefinition.get_template(
			DiscoverySignalUiTextDefinition.KEY_INVESTIGATE_LORE_ACTIVE
		)
		info["scan_state"] = GameSession.SCAN_UNKNOWN

	info["is_investigate_active"] = in_progress
	var progress: float = 0.0
	if in_progress and survey_probe_mission_controller != null:
		progress = survey_probe_mission_controller.get_investigation_progress(object_id)
	info["investigate_progress"] = progress
	info["investigate_progress_text"] = DiscoverySignalUiTextDefinition.format_investigate_progress(
		int(round(progress * 100.0))
	)

	return info


func _build_selected_object_info(selected_node: Node) -> Dictionary:
	if selected_node is SignalMarker:
		return _build_signal_marker_info(selected_node as SignalMarker)

	var object_id := _get_object_id(selected_node)
	var scan_state := GameSession.get_object_scan_state(system_definition.id, object_id)
	var unlocked_scan_layer := GameSession.get_unlocked_scan_layer_for_base(_economy_body_id_for_ui())

	var info: Dictionary = {}

	if selected_node.has_method("build_scan_info"):
		info = selected_node.call("build_scan_info", scan_state, unlocked_scan_layer)
	elif selected_node.has_method("get_info"):
		info = selected_node.call("get_info")

	info["scan_state"] = scan_state
	info["preview_texture"] = _get_preview_texture(selected_node)
	info["distance_text"] = "-"  # Overwritten every frame by _process().

	info["mining_yield_upgrade_base_id"] = _economy_body_id_for_ui().strip_edges()

	_apply_scan_drone_info_to_dict(info, selected_node, object_id)
	_apply_mining_ship_info_to_dict(info, selected_node, object_id, scan_state)
	info["is_home_base"] = (
		selected_node is SystemBody
		and _selected_body_has_established_base(selected_node as SystemBody)
	)

	info["mining_exhausted"] = bool(info.get("mining_exhausted", false))

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
		info["can_recall_drone"] = (
			_get_active_scan_drone_count(object_id) > 0
			or _get_orbiting_drone_count(object_id) > 0
		)
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
		info["lore_text"] = "No description available."

	_apply_colonization_info_to_dict(info, selected_node)
	_apply_sensor_pulse_info_to_dict(info)

	var sys_gate_id := _current_system_definition_id()
	if sys_gate_id.is_empty() or GameSession.get_established_base_id_for_system(sys_gate_id).is_empty():
		info["system_economy_blocked_reason"] = ""
		info["show_scan_with_drone"] = false
		info["can_scan_with_drone"] = false
		info["scan_blocked_reason"] = ""
		info["show_mine_with_ship"] = false
		info["can_mine_with_ship"] = false
		info["mine_blocked_reason"] = ""
		info["mining_exhausted"] = false
		info["can_recall_drone"] = false
		info["can_recall_mining_ship"] = false
		if not bool(info.get("is_home_base", false)):
			info["active_scan_drone_count"] = 0
			info["active_mining_ship_count"] = 0
			info["scan_drone_supporting_count"] = 0
			info["mining_ship_mining_count"] = 0
			info["mining_bonus"] = 0.0

	return info


func _apply_colonization_info_to_dict(info: Dictionary, selected_node: Node) -> void:
	var sys_id := _current_system_definition_id()
	info["system_id"] = sys_id
	info["object_id"] = _get_object_id(selected_node)

	var is_home: bool = sys_id == GameSession.START_SYSTEM_ID
	var has_base: bool = GameSession.has_established_base_in_system(sys_id)
	var pending: bool = GameSession.has_pending_colonization_to_system(sys_id)

	var is_colonizable: bool = false
	if selected_node is SystemBody:
		var body := selected_node as SystemBody
		if body.definition != null and body.definition.can_build_base:
			is_colonizable = true

	var show_button: bool = (
		selected_node is SystemBody
		and not is_home
		and not has_base
		and is_colonizable
	)

	info["colonization_button_visible"] = show_button
	info["colonization_pending"] = pending and show_button
	info["colonization_can_start"] = (
		show_button
		and not pending
		and not GameSession.get_colonization_source_base_id().strip_edges().is_empty()
	)


func _body_definition_allows_base(body_id: String) -> bool:
	var bid := body_id.strip_edges()
	if bid.is_empty() or system_definition == null:
		return false
	for body_def in system_definition.bodies:
		if body_def == null:
			continue
		if str(body_def.id).strip_edges() != bid:
			continue
		return body_def.can_build_base
	return false


func _apply_scan_drone_info_to_dict(info: Dictionary, selected_node: Node, object_id: String) -> void:
	info["show_scan_with_drone"] = false
	info["can_scan_with_drone"] = false
	info["scan_blocked_reason"] = ""

	if selected_node == null:
		return

	if selected_node is SignalMarker:
		return

	if not selected_node is SystemBody and not selected_node is PointOfInterest:
		return

	if selected_node is SystemBody and _selected_body_has_established_base(selected_node as SystemBody):
		return

	var sys_id: String = system_definition.id.strip_edges()
	if sys_id.is_empty() or object_id.is_empty():
		return

	var base_id: String = _economy_body_id_for_ui()
	var scan_active: bool = _get_active_scan_drone_count(object_id) > 0
	var scan_gate: Dictionary = GameSession.can_scan_object(
		sys_id,
		object_id,
		base_id,
		_has_available_drone(),
		scan_active,
	)
	var target_state: String = str(scan_gate.get("target_scan_state", "")).strip_edges()

	info["show_scan_with_drone"] = not target_state.is_empty()
	info["can_scan_with_drone"] = bool(scan_gate.get("ok", false))
	info["scan_blocked_reason"] = str(scan_gate.get("blocked_reason", "")).strip_edges()


func _apply_sensor_pulse_info_to_dict(info: Dictionary) -> void:
	info["show_sensor_pulse"] = false
	info["can_sensor_pulse"] = false
	info["sensor_pulse_blocked_reason"] = ""
	info["sensor_pulse_in_progress"] = false
	info["sensor_pulse_progress_text"] = ""
	info["sensor_pulse_cost_text"] = ""

	if not bool(info.get("is_home_base", false)):
		return

	if base_sensor_pulse_controller == null:
		return

	var base_id: String = _economy_body_id_for_ui()
	var in_progress: bool = base_sensor_pulse_controller.is_pulse_active()
	info["sensor_pulse_in_progress"] = in_progress
	info["show_sensor_pulse"] = true

	if in_progress:
		var percent: int = base_sensor_pulse_controller.get_pulse_progress_percent()
		info["sensor_pulse_progress_text"] = DiscoverySignalUiTextDefinition.format_sensor_pulse_progress(
			percent
		)
		return

	info["sensor_pulse_cost_text"] = base_sensor_pulse_controller.get_pulse_cost_display_text()
	var gate: Dictionary = base_sensor_pulse_controller.can_start_sensor_pulse(base_id)
	info["can_sensor_pulse"] = bool(gate.get("ok", false))
	info["sensor_pulse_blocked_reason"] = str(gate.get("blocked_reason", "")).strip_edges()


func _apply_mining_ship_info_to_dict(
	info: Dictionary,
	selected_node: Node,
	object_id: String,
	scan_state: String,
) -> void:
	info["show_mine_with_ship"] = false
	info["can_mine_with_ship"] = false
	info["mine_blocked_reason"] = ""
	info["mining_exhausted"] = false

	if selected_node == null:
		return

	if selected_node is SignalMarker:
		return

	if not selected_node is SystemBody and not selected_node is PointOfInterest:
		return

	if selected_node is SystemBody and _selected_body_has_established_base(selected_node as SystemBody):
		return

	var sys_id: String = system_definition.id.strip_edges()
	if sys_id.is_empty() or object_id.is_empty():
		return

	var mine_gate: Dictionary = GameSession.can_mine_object(
		sys_id,
		object_id,
		_economy_body_id_for_ui(),
		_has_available_mining_ship(),
	)

	info["show_mine_with_ship"] = bool(mine_gate.get("show_mine_button", false))
	info["can_mine_with_ship"] = bool(mine_gate.get("ok", false))
	info["mine_blocked_reason"] = str(mine_gate.get("blocked_reason", "")).strip_edges()

	var block_reason: String = info["mine_blocked_reason"]
	info["mining_exhausted"] = (
		bool(info["show_mine_with_ship"])
		and not bool(info["can_mine_with_ship"])
		and block_reason == GameSession.MINE_BLOCK_DEPLETED
	)


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
	if node is SignalMarker:
		return (node as SignalMarker).object_id

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
	_refresh_economy_panels()
	_update_top_hud()


func _on_object_remaining_resources_changed(_changed_system_id: String, _changed_object_id: String) -> void:
	update_object_info()
	_refresh_economy_panels()
	_update_top_hud()


func _on_base_resources_changed_ui_refresh(_base_id: String) -> void:
	update_object_info()
	update_base_panel()
	_refresh_economy_panels()
	_update_top_hud()


func _on_base_upgrades_changed_ui_refresh(_base_id: String) -> void:
	update_object_info()
	update_base_panel()
	_refresh_economy_panels()
	_update_top_hud()


func _refresh_economy_panels() -> void:
	if production_panel != null and production_panel.visible:
		if production_panel.has_method("refresh_from_game_session"):
			production_panel.call("refresh_from_game_session")
	if upgrade_panel != null and upgrade_panel.visible:
		if upgrade_panel.has_method("refresh_from_game_session"):
			upgrade_panel.call("refresh_from_game_session")
	if storage_panel != null and storage_panel.visible:
		if storage_panel.has_method("refresh"):
			var sid := _storage_context_base_id.strip_edges()
			if sid.is_empty():
				sid = _economy_body_id_for_ui()
			storage_panel.call("refresh", sid)
	if base_management_panel != null and base_management_panel.visible:
		if base_management_panel.has_method("refresh_from_game_session"):
			base_management_panel.call("refresh_from_game_session")


func _on_colonization_requested(object_id: String) -> void:
	var sys_id := _current_system_definition_id()
	var body_id := object_id.strip_edges()
	if sys_id.is_empty() or body_id.is_empty():
		return
	if sys_id == GameSession.START_SYSTEM_ID:
		return
	if GameSession.has_established_base_in_system(sys_id):
		return
	if GameSession.has_pending_colonization_to_system(sys_id):
		return
	if not _body_definition_allows_base(body_id):
		return

	var src := GameSession.get_colonization_source_base_id().strip_edges()
	if src.is_empty():
		update_object_info()
		return

	var op_id := GameSession.start_colonization_operation(src, sys_id, body_id)
	if op_id.is_empty():
		update_object_info()
		return

	update_object_info()
	_update_top_hud()


func _on_build_drone_requested() -> void:
	if automation_controller == null:
		return

	if not _session_primary_base_established():
		return

	var bid_bd: String = _economy_body_id_for_ui().strip_edges()
	if bid_bd.is_empty():
		return

	automation_controller.spawn_idle_drone_at_base(bid_bd)
	update_all()


func _on_build_mining_ship_requested() -> void:
	if automation_controller == null:
		return

	if not _session_primary_base_established():
		return

	var bid_ms: String = _economy_body_id_for_ui().strip_edges()
	if bid_ms.is_empty():
		return

	automation_controller.spawn_idle_mining_ship_at_base(bid_ms)
	update_all()


func _on_build_survey_probe_requested() -> void:
	if automation_controller == null:
		return

	if not _session_primary_base_established():
		return

	var bid_sp: String = _economy_body_id_for_ui().strip_edges()
	if bid_sp.is_empty():
		return

	automation_controller.spawn_idle_survey_probe_at_base(bid_sp)
	update_all()


func _on_build_colony_ship_requested() -> void:
	if not _session_primary_base_established():
		return
	update_all()


func _connect_object_info_investigate_signal() -> void:
	if object_info_panel == null:
		return
	var panel := object_info_panel as ObjectInfoPanel
	if panel == null:
		push_warning("SystemUIController: ObjectInfoPanel script mismatch; investigate signal not connected.")
		return
	var handler := _on_investigate_requested
	if not panel.investigate_requested.is_connected(handler):
		panel.investigate_requested.connect(handler)


## Public entry for ObjectInfoPanel fallback when signal had zero listeners at click time.
func handle_investigate_requested(object_id: String) -> void:
	_on_investigate_requested(object_id)


func handle_sensor_pulse_requested() -> void:
	_on_sensor_pulse_requested()


func _connect_object_info_sensor_pulse_signal() -> void:
	if object_info_panel == null:
		return
	var panel := object_info_panel as ObjectInfoPanel
	if panel == null:
		push_warning("SystemUIController: ObjectInfoPanel script mismatch; sensor pulse signal not connected.")
		return
	var handler := _on_sensor_pulse_requested
	if not panel.sensor_pulse_requested.is_connected(handler):
		panel.sensor_pulse_requested.connect(handler)


func _on_sensor_pulse_requested() -> void:
	if base_sensor_pulse_controller == null:
		return

	if not _session_primary_base_established():
		return

	var base_id: String = _economy_body_id_for_ui()
	if base_sensor_pulse_controller.try_start_sensor_pulse(base_id):
		update_object_info()
		_update_top_hud()
		return

	update_object_info()


func _on_sensor_pulse_changed() -> void:
	update_object_info()
	_update_top_hud()


func _on_sensor_pulse_progress_changed(_progress: float) -> void:
	update_object_info()


func _on_investigate_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if survey_probe_mission_controller == null:
		return

	if not _session_primary_base_established():
		return

	var base_id: String = _economy_body_id_for_ui()
	if survey_probe_mission_controller.try_start_investigate_signal(object_id, base_id):
		AudioManager.play_sfx_optional(&"build_success")
	else:
		AudioManager.play_sfx_optional(&"not_enough_resources")
		var blocked := survey_probe_mission_controller.get_investigate_blocked_reason(
			object_id,
			base_id,
		)
		if not blocked.is_empty():
			push_warning("Investigate failed for '%s': %s" % [object_id, blocked])

	update_object_info()
	update_base_panel()


func _on_survey_probe_mission_changed() -> void:
	update_object_info()
	update_base_panel()
	_update_top_hud()


func _on_investigation_progress_changed(object_id: String, progress: float) -> void:
	if object_info_panel == null or not object_info_panel.visible:
		return

	var oid := object_id.strip_edges()
	if oid.is_empty():
		return

	var selected := selection.get_selected_node()
	if selected is not SignalMarker:
		return

	if (selected as SignalMarker).object_id.strip_edges() != oid:
		return

	if object_info_panel.has_method("apply_investigate_progress"):
		object_info_panel.call("apply_investigate_progress", progress)


func _on_object_scan_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if not _session_primary_base_established():
		return

	if automation_controller == null:
		return

	var sys_id: String = system_definition.id.strip_edges()
	var scan_gate: Dictionary = GameSession.can_scan_object(
		sys_id,
		object_id,
		_economy_body_id_for_ui(),
		_has_available_drone(),
		_get_active_scan_drone_count(object_id) > 0,
	)
	if not bool(scan_gate.get("ok", false)):
		AudioManager.play_sfx_optional(&"not_enough_resources")
		update_object_info()
		return

	automation_controller.launch_scan_drone(object_id)
	update_object_info()


func _on_object_mining_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if not _session_primary_base_established():
		return

	if automation_controller == null:
		return

	var mine_gate: Dictionary = GameSession.can_mine_object(
		system_definition.id,
		object_id,
		_economy_body_id_for_ui(),
		_has_available_mining_ship(),
	)
	if not bool(mine_gate.get("ok", false)):
		AudioManager.play_sfx_optional(&"not_enough_resources")
		update_object_info()
		return

	automation_controller.launch_mining_ship(object_id)
	update_object_info()


func _on_recall_drone_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if not _session_primary_base_established():
		return

	if automation_controller == null:
		return

	automation_controller.recall_one_drone_from_target(object_id)
	update_object_info()


func _on_recall_mining_ship_requested(object_id: String) -> void:
	if object_id.is_empty():
		return

	if not _session_primary_base_established():
		return

	if automation_controller == null:
		return

	automation_controller.recall_one_mining_ship_from_target(object_id)
	update_object_info()


func _selected_body_has_established_base(body: SystemBody) -> bool:
	if body == null:
		return false
	var bid := str(body.body_id).strip_edges()
	return _body_has_established_base(_current_system_definition_id(), bid)


func _body_has_established_base(system_id: String, body_id: String) -> bool:
	var bid := body_id.strip_edges()
	if bid.is_empty():
		return false
	if not GameSession.has_established_base(bid):
		return false
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return true
	var rec := GameSession.get_established_base_record(bid)
	if rec.is_empty():
		return false
	return str(rec.get("system_id", "")).strip_edges() == sid


func _has_available_drone() -> bool:
	if automation_controller != null:
		return automation_controller.has_idle_drone()

	return _get_base_drone_count() > 0


func _has_available_mining_ship() -> bool:
	if automation_controller != null:
		return automation_controller.has_available_mining_ship()

	return _get_base_mining_ship_count() > 0


func _get_base_drone_count() -> int:
	var bid_bc: String = _economy_body_id_for_ui().strip_edges()
	if bid_bc.is_empty():
		return 0
	return GameSession.get_base_drone_count(bid_bc)


func _get_base_mining_ship_count() -> int:
	var bid_bm: String = _economy_body_id_for_ui().strip_edges()
	if bid_bm.is_empty():
		return 0
	return GameSession.get_base_mining_ship_count(bid_bm)


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
	if top_hud != null and top_hud.has_method("set_primary_base_body_id"):
		top_hud.call("set_primary_base_body_id", _economy_body_id_for_ui())

	if top_hud != null and top_hud.has_method("refresh_from_game_session"):
		top_hud.call("refresh_from_game_session")

	if top_hud != null and top_hud.has_method("set_survey_probe_counts"):
		var bid_sp: String = _economy_body_id_for_ui().strip_edges()
		var available_sp: int = 0
		if not bid_sp.is_empty():
			available_sp = GameSession.get_available_survey_probe_count(bid_sp)
		var active_sp: int = 0
		if survey_probe_mission_controller != null:
			active_sp = survey_probe_mission_controller.get_active_investigate_count()
		top_hud.call("set_survey_probe_counts", available_sp, active_sp)

	if top_hud != null and top_hud.has_method("set_jobs_count"):
		var job_n: int = 0
		if automation_controller != null:
			job_n = automation_controller.get_active_job_count_for_base(_economy_body_id_for_ui().strip_edges())
		top_hud.call("set_jobs_count", job_n)


func _clear_top_hud_hover_panel() -> void:
	if top_hud_hover_panel != null and top_hud_hover_panel.has_method("clear"):
		top_hud_hover_panel.call("clear")


func _on_base_open_production() -> void:
	if not _session_primary_base_established():
		return
	_sync_production_upgrade_economy_body_ids()
	_clear_top_hud_hover_panel()
	if upgrade_panel != null:
		upgrade_panel.visible = false
	if storage_panel != null:
		storage_panel.visible = false
		_storage_context_base_id = ""
	if production_panel != null:
		production_panel.visible = true
		if production_panel.has_method("refresh_from_game_session"):
			production_panel.call("refresh_from_game_session")


func _on_base_open_upgrades() -> void:
	if not _session_primary_base_established():
		return
	_sync_production_upgrade_economy_body_ids()
	_clear_top_hud_hover_panel()
	if production_panel != null:
		production_panel.visible = false
	if storage_panel != null:
		storage_panel.visible = false
		_storage_context_base_id = ""
	if upgrade_panel != null:
		upgrade_panel.visible = true
		if upgrade_panel.has_method("refresh_from_game_session"):
			upgrade_panel.call("refresh_from_game_session")


func _on_base_open_storage() -> void:
	if not _session_primary_base_established():
		return
	_clear_top_hud_hover_panel()
	if production_panel != null:
		production_panel.visible = false
	if upgrade_panel != null:
		upgrade_panel.visible = false

	if base_management_panel != null and base_management_panel.has_method("get_managed_base_id"):
		_storage_context_base_id = str(base_management_panel.call("get_managed_base_id"))
	else:
		_storage_context_base_id = BaseStore.BASE_EARTH

	if storage_panel != null:
		storage_panel.visible = true
		if storage_panel.has_method("set_base_id"):
			storage_panel.call("set_base_id", _storage_context_base_id)
		if storage_panel.has_method("refresh"):
			storage_panel.call("refresh", _storage_context_base_id)


func _on_storage_panel_close_requested() -> void:
	if storage_panel != null:
		storage_panel.visible = false
	_storage_context_base_id = ""


func _on_storage_panel_discard_requested(resource_id: String, amount: int) -> void:
	if _storage_context_base_id.is_empty():
		return
	GameSession.remove_base_resource(_storage_context_base_id, resource_id, amount)
	update_all()


func _on_production_close() -> void:
	if production_panel != null:
		production_panel.visible = false


func _on_upgrade_close() -> void:
	if upgrade_panel != null:
		upgrade_panel.visible = false


func _on_top_hud_hover_requested(kind: String, source_control: Control) -> void:
	if top_hud_hover_panel == null or source_control == null:
		return

	var content := _build_hover_details(kind)
	var title: String = str(content.get("title", ""))
	var details: Array = content.get("details", [])
	var hint: String = str(content.get("hint", ""))
	if top_hud_hover_panel.has_method("show_details"):
		top_hud_hover_panel.call("show_details", title, details, hint, source_control)


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


func _hover_mining_ship_group_object_id(runtime: Dictionary, status: int) -> String:
	if status == _MS_RT_UNLOADING or status == _MS_RT_WAITING_STORAGE:
		return _economy_body_id_for_ui().strip_edges()
	return str(runtime.get("target_id", ""))


func _hover_scan_drone_counts_by_target() -> Dictionary:
	var m: Dictionary = {}
	if automation_controller == null:
		return m
	for unit_id_variant: Variant in automation_controller.scan_drone_target_by_unit_id.keys():
		var tid: String = str(automation_controller.scan_drone_target_by_unit_id[unit_id_variant])
		if tid.is_empty():
			continue
		m[tid] = int(m.get(tid, 0)) + 1
	return m


func _hover_mining_ship_counts_by_group_object() -> Dictionary:
	var m: Dictionary = {}
	if automation_controller == null:
		return m
	for unit_id_variant: Variant in automation_controller.mining_ship_runtime_by_unit_id.keys():
		var rt: Dictionary = automation_controller.mining_ship_runtime_by_unit_id[unit_id_variant]
		if rt.is_empty():
			continue
		var st: int = int(rt.get("status", _MS_RT_TO_TARGET))
		var oid := _hover_mining_ship_group_object_id(rt, st)
		if oid.is_empty():
			continue
		m[oid] = int(m.get(oid, 0)) + 1
	return m


func _hover_append_simple_object_count_lines(details: Array, counts_by_object: Dictionary) -> void:
	if counts_by_object.is_empty():
		return
	var ids: Array[String] = []
	for k_var: Variant in counts_by_object.keys():
		ids.append(str(k_var))
	ids.sort_custom(
		func(a: String, b: String) -> bool:
			var da := _hover_display_name_for_object_id(a).to_lower()
			var db := _hover_display_name_for_object_id(b).to_lower()
			if da == db:
				return a < b
			return da < db
	)
	for oid: String in ids:
		var n: int = int(counts_by_object.get(oid, 0))
		if n <= 0:
			continue
		details.append(
			"%s: %s" % [_hover_display_name_for_object_id(oid), NumberFormat.format_compact(n)]
		)


func _top_hud_effects_section_caption() -> String:
	if top_hud_hover_panel != null and top_hud_hover_panel.has_method("get_effects_section_caption"):
		return str(top_hud_hover_panel.call("get_effects_section_caption")).strip_edges()
	return ""


func _build_hover_details(kind: String) -> Dictionary:
	var base_id: String = _economy_body_id_for_ui().strip_edges()
	if base_id.is_empty() and (
		kind == "storage"
		or kind == "scan_drones"
		or kind == "mining_ships"
		or kind == "survey_probes"
	):
		return {
			"title": "—",
			"details": ["No base context ID for this system."],
			"hint": "",
		}

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
				details.append(
					"%s: %s" % [str(res_id).capitalize(), NumberFormat.format_compact(amt_s)]
				)
			if not has_any:
				details.append("No resources stored.")
			var storage_def: UpgradeDefinition = GameSession.get_current_upgrade_definition(
				base_id, &"storage"
			)
			UpgradeDefinition.append_current_tier_effect_block(
				details,
				storage_def,
				not GameSession.has_next_base_upgrade(base_id, &"storage"),
				_top_hud_effects_section_caption()
			)
			hint = "Storage capacity."

		"scan_drones":
			var total_sd := GameSession.get_base_drone_count(base_id)
			var busy_sd := 0
			if automation_controller != null:
				busy_sd = automation_controller.scan_drone_target_by_unit_id.size()
			var idle_sd := maxi(0, total_sd - busy_sd)
			title = "ScanDrones"
			details.append("Total: %s" % NumberFormat.format_compact(total_sd))
			details.append("Base: %s" % NumberFormat.format_compact(idle_sd))
			_hover_append_simple_object_count_lines(details, _hover_scan_drone_counts_by_target())
			var scan_def: UpgradeDefinition = GameSession.get_current_upgrade_definition(
				base_id, &"scan_drone"
			)
			UpgradeDefinition.append_current_tier_effect_block(
				details,
				scan_def,
				not GameSession.has_next_base_upgrade(base_id, &"scan_drone"),
				_top_hud_effects_section_caption()
			)
			hint = "Used for scanning unknown objects."

		"mining_ships":
			var total_ms := GameSession.get_base_mining_ship_count(base_id)
			var busy_ms := 0
			if automation_controller != null:
				busy_ms = automation_controller.mining_ship_runtime_by_unit_id.size()
			var idle_ms := maxi(0, total_ms - busy_ms)
			title = "MiningShips"
			details.append("Total: %s" % NumberFormat.format_compact(total_ms))
			details.append("Base: %s" % NumberFormat.format_compact(idle_ms))
			_hover_append_simple_object_count_lines(details, _hover_mining_ship_counts_by_group_object())
			var ms_def: UpgradeDefinition = GameSession.get_current_upgrade_definition(
				base_id, &"mining_ship"
			)
			UpgradeDefinition.append_current_tier_effect_block(
				details,
				ms_def,
				not GameSession.has_next_base_upgrade(base_id, &"mining_ship"),
				_top_hud_effects_section_caption()
			)
			hint = "Used for automated resource extraction."

		"colony_ships":
			var total_cs: int = GameSession.get_base_colony_ship_count(base_id)
			title = "ColonyShips"
			details = [
				"Total: %s" % NumberFormat.format_compact(total_cs),
				"Status: stored",
			]
			hint = "Used later to establish colonies in other systems."

		"survey_probes":
			var available_sp := GameSession.get_available_survey_probe_count(base_id)
			var active_sp := 0
			if survey_probe_mission_controller != null:
				active_sp = survey_probe_mission_controller.get_active_investigate_count()
			title = "Survey Probes"
			details = [
				"Available: %s" % NumberFormat.format_compact(available_sp),
				"Investigating: %s" % NumberFormat.format_compact(active_sp),
				"Total: %s" % NumberFormat.format_compact(available_sp + active_sp),
			]
			hint = "Stored probes available for new investigate missions."

		"jobs":
			var scan_jobs := 0
			var mining_jobs := 0
			if automation_controller != null:
				scan_jobs = automation_controller.get_active_scan_job_count_for_session_base(base_id)
				mining_jobs = automation_controller.get_active_mining_job_count_for_session_base(base_id)
			title = "Jobs"
			details = [
				"Active: %s" % NumberFormat.format_compact(scan_jobs + mining_jobs),
				"Scanning: %s" % NumberFormat.format_compact(scan_jobs),
				"Mining: %s" % NumberFormat.format_compact(mining_jobs),
			]
			hint = "Current automation tasks."

	return {"title": title, "details": details, "hint": hint}
