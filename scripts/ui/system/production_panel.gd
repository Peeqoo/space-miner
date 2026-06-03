## ProductionPanel — build ScanDrones, MiningShips, Survey Probes, and ColonyShip inventory.
## Emits build_*_requested for AutomationController spawning where applicable.
class_name ProductionPanel
extends PanelContainer

signal build_scan_drone_requested
signal build_mining_ship_requested
signal build_survey_probe_requested
signal build_colony_ship_requested
signal close_requested

## Target BaseStore base id (`SystemBody.body_id`). Set by SystemUI from session primary base.
var _economy_body_id: String = BaseStore.BASE_EARTH


func set_economy_body_id(body_id: String) -> void:
	var bid := body_id.strip_edges()
	if bid.is_empty():
		push_warning("ProductionPanel.set_economy_body_id: empty id ignored")
		return
	_economy_body_id = bid


func _economy_body_id_for_ops() -> String:
	var bid := _economy_body_id.strip_edges()
	return bid if not bid.is_empty() else BaseStore.BASE_EARTH


@onready var build_scan_drone_button: Button = $Margin/Root/ProductionList/BuildScanDroneButton
@onready var build_mining_ship_button: Button = $Margin/Root/ProductionList/BuildMiningShipButton
@onready var build_survey_probe_button: Button = $Margin/Root/ProductionList/BuildSurveyProbeButton
@onready var build_colony_ship_button: Button = $Margin/Root/ProductionList/BuildColonyShipButton
@onready var close_button: Button = $Margin/Root/HeaderRow/CloseButton
@onready var hover_info_section: PanelContainer = $Margin/Root/HoverInfoSection
@onready var hover_info_panel: PanelContainer = $Margin/Root/HoverInfoSection/HoverInfoPanel
@onready var hover_title_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverTitleLabel
@onready var hover_desc_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverDescLabel
@onready var hover_cost_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverCostLabel


var _hover_desc_placeholder: String = ""
var _hover_cost_header: String = ""


func _ready() -> void:
	visible = false
	hover_info_section.visible = false
	hover_info_panel.visible = true
	_hover_desc_placeholder = hover_desc_label.text.strip_edges()
	_hover_cost_header = hover_cost_label.text.strip_edges()

	_connect_button(close_button, _on_close_pressed)
	_connect_button(build_scan_drone_button, _on_build_scan_drone_pressed)
	_connect_button(build_mining_ship_button, _on_build_mining_ship_pressed)
	_connect_button(build_survey_probe_button, _on_build_survey_probe_pressed)
	_connect_button(build_colony_ship_button, _on_build_colony_ship_pressed)

	_register_hover(build_scan_drone_button)
	_register_hover(build_mining_ship_button)
	_register_hover(build_survey_probe_button)
	_register_hover(build_colony_ship_button)

	if not GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.connect(_on_resources_changed)
	if not GameSession.base_upgrades_changed.is_connected(_on_upgrades_changed):
		GameSession.base_upgrades_changed.connect(_on_upgrades_changed)

	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_resources_changed)
	if GameSession.base_upgrades_changed.is_connected(_on_upgrades_changed):
		GameSession.base_upgrades_changed.disconnect(_on_upgrades_changed)


func refresh_from_game_session() -> void:
	var oid := _economy_body_id_for_ops()
	_refresh_build_button(
		build_scan_drone_button,
		GameSession.get_build_base_scan_drone_gate(oid),
	)
	_refresh_build_button(
		build_mining_ship_button,
		GameSession.get_build_base_mining_ship_gate(oid),
	)
	_refresh_build_button(
		build_survey_probe_button,
		GameSession.get_build_base_survey_probe_gate(oid),
	)
	_refresh_colony_ship_button(oid)


func _refresh_build_button(button: Button, gate: Dictionary) -> void:
	if button == null:
		return
	button.disabled = not bool(gate.get("ok", false))


func _refresh_colony_ship_button(base_id: String) -> void:
	if build_colony_ship_button == null:
		return
	var gate: Dictionary = GameSession.get_build_base_colony_ship_gate(base_id)
	build_colony_ship_button.disabled = not bool(gate.get("ok", false))


func _on_close_pressed() -> void:
	hover_info_section.visible = false
	close_requested.emit()


func _on_build_scan_drone_pressed() -> void:
	_try_build_unit(
		GameSession.get_build_base_scan_drone_gate(_economy_body_id_for_ops()),
		GameSession.build_base_drone,
		build_scan_drone_requested,
	)


func _on_build_mining_ship_pressed() -> void:
	_try_build_unit(
		GameSession.get_build_base_mining_ship_gate(_economy_body_id_for_ops()),
		GameSession.build_base_mining_ship,
		build_mining_ship_requested,
	)


func _on_build_survey_probe_pressed() -> void:
	_try_build_unit(
		GameSession.get_build_base_survey_probe_gate(_economy_body_id_for_ops()),
		GameSession.build_base_survey_probe,
		build_survey_probe_requested,
	)


func _on_build_colony_ship_pressed() -> void:
	_try_build_unit(
		GameSession.get_build_base_colony_ship_gate(_economy_body_id_for_ops()),
		GameSession.build_base_colony_ship,
		build_colony_ship_requested,
	)


func _try_build_unit(
	gate: Dictionary,
	build_callable: Callable,
	success_signal: Signal,
) -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	if not bool(gate.get("ok", false)):
		AudioManager.play_sfx_optional(&"not_enough_resources")
		refresh_from_game_session()
		return
	if build_callable.call(oid):
		AudioManager.play_sfx_optional(&"build_success")
		success_signal.emit()
	else:
		AudioManager.play_sfx_optional(&"not_enough_resources")
	refresh_from_game_session()


func _register_hover(button: Button) -> void:
	if button == null:
		return
	if not button.mouse_entered.is_connected(_on_button_hover_entered.bind(button)):
		button.mouse_entered.connect(_on_button_hover_entered.bind(button))
	if not button.mouse_exited.is_connected(_on_button_hover_exited.bind(button)):
		button.mouse_exited.connect(_on_button_hover_exited.bind(button))


func _on_button_hover_entered(button: Button) -> void:
	var production_id := _production_id_from_button(button)
	var production_def: ProductionDefinition = GameSession.get_production_definition(production_id)

	hover_title_label.text = button.text
	hover_desc_label.text = _build_hover_description(production_def, button)
	hover_cost_label.text = _build_cost_text(production_id)
	hover_info_section.visible = true


func _on_button_hover_exited(_button: Button) -> void:
	hover_info_section.visible = false


func _production_id_from_button(button: Button) -> String:
	match button.name:
		"BuildScanDroneButton":
			return BaseStore.PRODUCTION_SCAN_DRONE
		"BuildMiningShipButton":
			return BaseStore.PRODUCTION_MINING_SHIP
		"BuildSurveyProbeButton":
			return BaseStore.PRODUCTION_SURVEY_PROBE
		"BuildColonyShipButton":
			return BaseStore.PRODUCTION_COLONY_SHIP
		_:
			return ""


func _build_hover_description(production_def: ProductionDefinition, button: Button) -> String:
	var lines := ProductionDefinition.build_hover_description_lines(production_def)
	if production_def != null and production_def.id == BaseStore.PRODUCTION_COLONY_SHIP:
		# v0.1: builds are instant; build_time_seconds is data-only until a queue UI exists.
		lines.append_array(_colony_prerequisite_hover_lines())
	var reason := _blocked_reason_for_button(button)
	if not reason.is_empty():
		lines.append(reason)
	if lines.is_empty():
		return _hover_desc_placeholder
	return "\n".join(lines)


func _blocked_reason_for_button(button: Button) -> String:
	var base_id := _economy_body_id_for_ops()
	match button.name:
		"BuildScanDroneButton":
			return str(GameSession.get_build_base_scan_drone_gate(base_id).get("blocked_reason", "")).strip_edges()
		"BuildMiningShipButton":
			return str(GameSession.get_build_base_mining_ship_gate(base_id).get("blocked_reason", "")).strip_edges()
		"BuildSurveyProbeButton":
			return str(GameSession.get_build_base_survey_probe_gate(base_id).get("blocked_reason", "")).strip_edges()
		"BuildColonyShipButton":
			var gate: Dictionary = GameSession.get_build_base_colony_ship_gate(base_id)
			var reason := str(gate.get("blocked_reason", "")).strip_edges()
			if not reason.is_empty():
				return reason
			for entry: Variant in gate.get("prerequisites", []):
				if not (entry is Dictionary):
					continue
				var row: Dictionary = entry
				if bool(row.get("met", false)):
					continue
				reason = str(row.get("blocked_reason", "")).strip_edges()
				if not reason.is_empty():
					return reason
			return ""
		_:
			return ""


func _colony_prerequisite_hover_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("Prerequisites:")
	for entry: Variant in GameSession.get_colony_ship_build_prerequisite_status(_economy_body_id_for_ops()):
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry
		var mark := "✓" if bool(row.get("met", false)) else "✗"
		lines.append("%s %s" % [mark, str(row.get("label", ""))])
	return lines


func _build_cost_text(production_id: String) -> String:
	var resources := GameSession.get_base_resources(_economy_body_id_for_ops())
	var cost := GameSession.get_production_cost(production_id)
	if production_id == BaseStore.PRODUCTION_COLONY_SHIP:
		var colony_cost := GameSession.get_colony_ship_build_cost()
		if not colony_cost.is_empty():
			cost = colony_cost
	var lines := _format_cost_lines_with_availability_for_display(cost, resources)
	if lines.is_empty():
		return _hover_cost_header

	var body := "\n".join(lines)
	if _hover_cost_header.is_empty():
		return body
	return "%s\n%s" % [_hover_cost_header, body]


func _format_cost_lines_with_availability_for_display(
	p_cost: Dictionary,
	available: Dictionary,
) -> PackedStringArray:
	var lines: PackedStringArray = []
	var keys: Array = p_cost.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return str(a).to_lower() < str(b).to_lower()
	)
	for res_id: Variant in keys:
		var need := int(p_cost.get(res_id, 0))
		var have := int(available.get(res_id, 0))
		var res_key := str(res_id).strip_edges()
		var title := GameSession.get_resource_display_name(
			StringName(res_key),
			ProductionDefinition.format_resource_title(res_key)
		)
		lines.append(
			"%s: %s / %s"
			% [
				title,
				NumberFormat.format_compact(have),
				NumberFormat.format_compact(need),
			]
		)
	return lines


func _connect_button(button: Button, callback: Callable) -> void:
	if button == null:
		return
	AudioManager.bind_ui_button_optional(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_resources_changed(_base_id: String) -> void:
	if not visible:
		return
	refresh_from_game_session()


func _on_upgrades_changed(_base_id: String) -> void:
	if not visible:
		return
	refresh_from_game_session()
