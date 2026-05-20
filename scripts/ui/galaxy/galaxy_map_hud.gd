extends Control
class_name GalaxyMapHUD

## Must match `galaxy_map.gd` access constants.
const ACCESS_CURRENT := "current"
const ACCESS_READY := "ready"
const ACCESS_LOCKED := "locked"
const ACCESS_UNREACHABLE := "unreachable"

signal enter_requested
signal colonization_deploy_requested
signal colonization_cancel_requested
signal colonization_dev_complete_requested

## Unter `UI` neben diesem HUD (siehe `galaxy_map.tscn`); in `galaxy_map_hud.tscn` nicht als Kind vorhanden.
@onready var current_system_value_label: Label = (
	self.get_node_or_null("../GalaxyTopBar/Margin/Row/CurrentSystemValueLabel") as Label
)
@onready var galaxy_info_panel: Control = $GalaxyInfoPanel
@onready var system_name_label: Label = $GalaxyInfoPanel/Margin/Root/SystemHeaderSection/SystemNameLabel
@onready var access_status_label: Label = $GalaxyInfoPanel/Margin/Root/SystemHeaderSection/AccessStatusLabel
@onready var known_planets_value_label: Label = $GalaxyInfoPanel/Margin/Root/ScanIntelSection/StatsGrid/KnownPlanetsValueLabel
@onready var known_resources_value_label: Label = $GalaxyInfoPanel/Margin/Root/ScanIntelSection/StatsGrid/KnownResourcesValueLabel
@onready var info_popup_text_label: Label = $InfoPopupPanel/Margin/InfoPopupTextLabel
@onready var info_popup_panel: Control = $InfoPopupPanel
@onready var divider_c: Control = $GalaxyInfoPanel/Margin/Root/DividerC
@onready var colonization_section: Control = $GalaxyInfoPanel/Margin/Root/ColonizationSection
@onready var colonization_title_label: Label = $GalaxyInfoPanel/Margin/Root/ColonizationSection/ColonizationTitleLabel
## Grid: linke Labels editor-owned; nur *ValueLabel* beschreiben.
@onready var colonization_state_value_label: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/GridContainer/ColonizationStateValueLabel
)
@onready var colonization_target_value_label: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/GridContainer/ColonizationTargetValueLabel
)
@onready var colonization_ships_value_label: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/GridContainer/ColonizationShipsValueLabel
)
@onready var colonization_intel_value_label: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/GridContainer/ColonizationIntelValueLabel
)
@onready var colonization_deploy_button: Button = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/ColonizationSecondaryRow/ColonizationDeployButton
)
@onready var colonization_secondary_row: GridContainer = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/ColonizationSecondaryRow
)
@onready var colonization_cancel_button: Button = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/ColonizationSecondaryRow/ColonizationCancelButton
)
@onready var colonization_dev_button: Button = (
	$GalaxyInfoPanel/Margin/Root/ColonizationSection/ColonizationSecondaryRow/ColonizationDevButton
)
@onready var enter_button: Button = $GalaxyInfoPanel/Margin/Root/ActionSection/EnterButton

var _colonization_preview_system_def: SystemDefinition = null


func _ready() -> void:
	set_current_system_name("-")
	show_no_selection_state()
	set_process(false)


func _process(_delta: float) -> void:
	if _colonization_preview_system_def == null:
		set_process(false)
		return
	var sid := _colonization_preview_system_def.id.strip_edges()
	if sid.is_empty():
		return
	var pending_rec := GameSession.get_pending_colonization_operation_for_system(sid)
	if pending_rec.is_empty():
		set_process(false)
		return
	if not is_instance_valid(colonization_state_value_label):
		return
	var op_id := str(pending_rec.get("operation_id", "")).strip_edges()
	if op_id.is_empty():
		return
	var status_txt := GameSession.get_colonization_operation_status_text(op_id)
	colonization_state_value_label.text = status_txt if not status_txt.is_empty() else "Läuft"


func _hide_info_popup() -> void:
	if is_instance_valid(info_popup_panel):
		info_popup_panel.visible = false


func show_info_panel() -> void:
	if is_instance_valid(galaxy_info_panel):
		galaxy_info_panel.visible = true


func hide_info_panel() -> void:
	if is_instance_valid(galaxy_info_panel):
		galaxy_info_panel.visible = false
	_hide_info_popup()


func set_current_system_name(system_name: String) -> void:
	var clean_name := system_name.strip_edges()
	var display := clean_name if clean_name != "" else "-"
	if is_instance_valid(current_system_value_label):
		current_system_value_label.text = display


func show_no_selection_state() -> void:
	hide_info_panel()
	if is_instance_valid(system_name_label):
		system_name_label.text = "Kein System gewählt"
	if is_instance_valid(access_status_label):
		access_status_label.text = ""
	if is_instance_valid(known_planets_value_label):
		known_planets_value_label.text = "0"
	if is_instance_valid(known_resources_value_label):
		known_resources_value_label.text = "Unknown"
	_set_info_text("Kein System ausgewählt")
	if is_instance_valid(enter_button):
		enter_button.disabled = true
		enter_button.tooltip_text = ""
	_hide_colonization_section()


func show_system_info(
	system_name: String,
	known_planets_count: int,
	known_resources_text: String,
	info_text: String,
	can_enter: bool,
	access_state: String,
) -> void:
	show_info_panel()
	if is_instance_valid(system_name_label):
		system_name_label.text = system_name
	if is_instance_valid(access_status_label):
		access_status_label.text = _access_status_text_for_state(access_state)
	if is_instance_valid(known_planets_value_label):
		known_planets_value_label.text = str(max(known_planets_count, 0))
	if is_instance_valid(known_resources_value_label):
		if access_state == ACCESS_LOCKED:
			known_resources_value_label.text = "Unknown"
		else:
			known_resources_value_label.text = (
				known_resources_text if not known_resources_text.is_empty() else "Unknown"
			)
	_set_info_text(info_text)
	if is_instance_valid(enter_button):
		enter_button.disabled = not can_enter
	_apply_enter_button_tooltip(can_enter, access_state)


func _set_info_text(value: String) -> void:
	var t := value.strip_edges()
	if t == "":
		t = "Keine Beschreibung verfügbar"
	if is_instance_valid(info_popup_text_label):
		info_popup_text_label.text = t


func _on_info_button_pressed() -> void:
	if not is_instance_valid(info_popup_panel):
		return
	info_popup_panel.visible = not info_popup_panel.visible


func _apply_enter_button_tooltip(can_enter: bool, access_state: String) -> void:
	if not is_instance_valid(enter_button):
		return
	if can_enter:
		enter_button.tooltip_text = ""
		return
	match access_state:
		ACCESS_LOCKED:
			enter_button.tooltip_text = "Zugriff gesperrt"
		ACCESS_UNREACHABLE:
			enter_button.tooltip_text = "System nicht erreichbar"
		_:
			enter_button.tooltip_text = "Zugang derzeit nicht möglich"


func _access_status_text_for_state(access_state: String) -> String:
	match access_state:
		ACCESS_CURRENT:
			return "Aktuelles System"
		ACCESS_READY:
			return "Bereit"
		ACCESS_LOCKED:
			return "Gesperrt"
		ACCESS_UNREACHABLE:
			return "Nicht erreichbar"
		_:
			return ""


## Phase 6.4d / 6.5 Colonization preview (nur Value-Labels; Start über ObjectInfoPanel).
func update_colonization_preview(system_def: SystemDefinition, access_state: String) -> void:
	if system_def == null:
		_colonization_preview_system_def = null
		set_process(false)
		return
	if not is_instance_valid(colonization_deploy_button):
		return

	_colonization_preview_system_def = system_def

	_show_colonization_section()

	if is_instance_valid(colonization_deploy_button):
		colonization_deploy_button.visible = false

	var sid: String = system_def.id.strip_edges()
	var start_body: String = system_def.start_body_id.strip_edges()
	var pending_rec: Dictionary = GameSession.get_pending_colonization_operation_for_system(sid)

	if access_state == ACCESS_LOCKED or access_state == ACCESS_UNREACHABLE:
		_set_colonization_block(
			"Gesperrt",
			_colonization_target_value_text(system_def, sid),
			_colonization_ships_count_text(sid),
			_colonization_intel_value_text(system_def, sid, pending_rec, start_body),
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	if sid.is_empty():
		_set_colonization_block()
		_set_deploy_cancel_dev_disabled()
		return

	if GameSession.has_established_base_in_system(sid):
		var eb: String = GameSession.get_established_base_id_for_system(sid).strip_edges()
		var state_short := "Etabliert"
		if sid == GameSession.START_SYSTEM_ID:
			state_short = "Heimat"
		var ships_n := 0
		if not eb.is_empty():
			ships_n = GameSession.get_base_colony_ship_count(eb)
		_set_colonization_block(
			state_short,
			_colonization_target_value_text(system_def, sid),
			str(ships_n),
			_colonization_intel_value_text(system_def, sid, pending_rec, start_body),
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	if not pending_rec.is_empty():
		var op_id := str(pending_rec.get("operation_id", "")).strip_edges()
		var state_txt := GameSession.get_colonization_operation_status_text(op_id)
		if state_txt.is_empty():
			state_txt = "Läuft"
		_set_colonization_block(
			state_txt,
			_colonization_target_value_text(system_def, sid),
			_colonization_ships_count_text(sid),
			_colonization_intel_value_text(system_def, sid, pending_rec, start_body),
		)
		if is_instance_valid(colonization_deploy_button):
			colonization_deploy_button.visible = false
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = false
		colonization_dev_button.disabled = false
		set_process(true)
		return

	set_process(false)

	if start_body.is_empty():
		_set_colonization_block(
			"-",
			"-",
			"0",
			_colonization_intel_value_text(system_def, sid, pending_rec, start_body),
		)
		_set_deploy_cancel_dev_disabled()
		return

	var source_id := GameSession.get_colonization_source_base_id().strip_edges()

	if source_id.is_empty():
		_set_colonization_block(
			"Unkolonisiert",
			_colonization_target_value_text(system_def, sid),
			_colonization_ships_count_text(sid),
			_colonization_intel_value_text(system_def, sid, pending_rec, start_body),
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	var cs_n: int = GameSession.get_base_colony_ship_count(source_id)

	_set_colonization_block(
		"Unkolonisiert",
		_colonization_target_value_text(system_def, sid),
		str(cs_n),
		_colonization_intel_value_text(system_def, sid, pending_rec, start_body),
	)
	colonization_deploy_button.disabled = cs_n < 1
	colonization_cancel_button.disabled = true
	colonization_dev_button.disabled = true
	set_process(false)


func _set_colonization_block(
	state_value: String = "-",
	target_value: String = "-",
	ships_value: String = "0",
	intel_value: String = "Unbekannt",
) -> void:
	if is_instance_valid(colonization_state_value_label):
		colonization_state_value_label.text = state_value
	if is_instance_valid(colonization_target_value_label):
		colonization_target_value_label.text = target_value
	if is_instance_valid(colonization_ships_value_label):
		colonization_ships_value_label.text = ships_value
	if is_instance_valid(colonization_intel_value_label):
		colonization_intel_value_label.text = intel_value


func _colonization_target_value_text(system_def: SystemDefinition, sid: String) -> String:
	var pending := GameSession.get_pending_colonization_operation_for_system(sid)
	if not pending.is_empty():
		var tid := str(pending.get("target_body_id", "")).strip_edges()
		if not tid.is_empty():
			var dn := _get_body_display_name(system_def, tid).strip_edges()
			return dn if not dn.is_empty() else "-"
		return "-"
	if not GameSession.has_established_base_in_system(sid):
		return "-"
	var eb := GameSession.get_established_base_id_for_system(sid).strip_edges()
	if eb.is_empty():
		return "-"
	var t := _colonization_target_for_established_base(system_def, eb).strip_edges()
	return t if not t.is_empty() else "-"


func _colonization_ships_count_text(sid: String) -> String:
	if GameSession.has_established_base_in_system(sid):
		var bid := GameSession.get_established_base_id_for_system(sid).strip_edges()
		if not bid.is_empty():
			return str(GameSession.get_base_colony_ship_count(bid))
	var src := GameSession.get_colonization_source_base_id().strip_edges()
	if src.is_empty():
		return "0"
	return str(GameSession.get_base_colony_ship_count(src))


func _colonization_intel_value_text(
	system_def: SystemDefinition,
	sid: String,
	pending_rec: Dictionary,
	start_body: String,
) -> String:
	var body_id := ""
	if GameSession.has_established_base_in_system(sid):
		var ebs := GameSession.get_established_base_id_for_system(sid).strip_edges()
		if not ebs.is_empty():
			body_id = GameSession.get_established_base_body_id(ebs).strip_edges()
	elif not pending_rec.is_empty():
		body_id = str(pending_rec.get("target_body_id", "")).strip_edges()
	else:
		body_id = start_body.strip_edges()

	if body_id.is_empty():
		return "Unbekannt"

	var st := GameSession.get_object_scan_state(sid, body_id)
	if (
		st == GameSession.SCAN_BASIC
		or st == GameSession.SCAN_DEEP
		or st == GameSession.SCAN_SPECIAL
	):
		return "Bekannt"
	return "Unbekannt"


func _get_body_display_name(system_def: SystemDefinition, body_id: String) -> String:
	var clean_id := body_id.strip_edges()
	if clean_id == "":
		return ""
	if system_def != null:
		for body in system_def.bodies:
			if body == null:
				continue
			if str(body.id).strip_edges() != clean_id:
				continue
			var dn := str(body.display_name).strip_edges()
			return dn if not dn.is_empty() else clean_id
	return clean_id


func _colonization_target_for_established_base(
	system_def: SystemDefinition,
	base_id: String,
) -> String:
	var bid := GameSession.get_established_base_body_id(base_id).strip_edges()
	if not bid.is_empty():
		return _get_body_display_name(system_def, bid)
	return base_id.strip_edges()


func _show_colonization_section() -> void:
	if is_instance_valid(divider_c):
		divider_c.visible = true
	if is_instance_valid(colonization_section):
		colonization_section.visible = true
	if is_instance_valid(colonization_title_label):
		colonization_title_label.visible = true
	if is_instance_valid(colonization_state_value_label):
		colonization_state_value_label.visible = true
	if is_instance_valid(colonization_target_value_label):
		colonization_target_value_label.visible = true
	if is_instance_valid(colonization_ships_value_label):
		colonization_ships_value_label.visible = true
	if is_instance_valid(colonization_intel_value_label):
		colonization_intel_value_label.visible = true
	if is_instance_valid(colonization_deploy_button):
		colonization_deploy_button.visible = false
	if is_instance_valid(colonization_secondary_row):
		colonization_secondary_row.visible = true


func _hide_colonization_section() -> void:
	_colonization_preview_system_def = null
	set_process(false)
	if is_instance_valid(divider_c):
		divider_c.visible = false
	if is_instance_valid(colonization_section):
		colonization_section.visible = false
	if is_instance_valid(colonization_title_label):
		colonization_title_label.visible = false
	_set_colonization_block()
	if is_instance_valid(colonization_deploy_button):
		colonization_deploy_button.visible = false
	if is_instance_valid(colonization_secondary_row):
		colonization_secondary_row.visible = false


func _set_deploy_cancel_dev_disabled() -> void:
	colonization_deploy_button.disabled = true
	colonization_cancel_button.disabled = true
	colonization_dev_button.disabled = true


func _on_enter_button_pressed() -> void:
	enter_requested.emit()


func _on_colon_deploy_pressed() -> void:
	colonization_deploy_requested.emit()


func _on_colon_cancel_pressed() -> void:
	colonization_cancel_requested.emit()


func _on_colon_dev_pressed() -> void:
	colonization_dev_complete_requested.emit()
