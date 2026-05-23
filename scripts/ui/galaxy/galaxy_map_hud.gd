extends Control
class_name GalaxyMapHUD

## Must match `galaxy_map.gd` access constants.
const ACCESS_CURRENT := "current"
const ACCESS_READY := "ready"
const ACCESS_LOCKED := "locked"
const ACCESS_UNREACHABLE := "unreachable"

signal enter_requested
signal colonization_cancel_requested
signal colonization_dev_complete_requested
signal close_requested

## Unter `UI` neben diesem HUD (siehe `galaxy_map.tscn`); in `galaxy_map_hud.tscn` nicht als Kind vorhanden.
@onready var current_system_value_label: Label = (
	self.get_node_or_null("../GalaxyTopBar/Margin/Row/CurrentSystemValueLabel") as Label
)
@onready var galaxy_info_panel: Control = $GalaxyInfoPanel
@onready var close_button: Button = (
	$GalaxyInfoPanel/Margin/Root/SystemHeaderSection/HeaderRow/CloseButton
)
@onready var system_name_label: Label = $GalaxyInfoPanel/Margin/Root/SystemHeaderSection/SystemNameLabel
@onready var access_status_label: Label = $GalaxyInfoPanel/Margin/Root/SystemHeaderSection/AccessStatusLabel
@onready var known_planets_value_label: Label = $GalaxyInfoPanel/Margin/Root/ScanIntelSection/StatsGrid/KnownPlanetsValueLabel
@onready var known_resources_value_label: Label = (
	$GalaxyInfoPanel/Margin/Root/ScanIntelSection/KnownResourcesPanel/KnownResourcesMargin/KnownResourcesScroll/KnownResourcesValueLabel
)
@onready var info_text_label: Label = (
	$GalaxyInfoPanel/Margin/Root/InfoSection/InfoTextPanel/InfoTextMargin/InfoTextScroll/InfoTextLabel
)
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

@onready var access_status_current_template: Label = (
	$GalaxyInfoPanel/Margin/Root/AccessStatusCurrentTemplate
)
@onready var access_status_ready_template: Label = $GalaxyInfoPanel/Margin/Root/AccessStatusReadyTemplate
@onready var access_status_locked_template: Label = $GalaxyInfoPanel/Margin/Root/AccessStatusLockedTemplate
@onready var access_status_unreachable_template: Label = (
	$GalaxyInfoPanel/Margin/Root/AccessStatusUnreachableTemplate
)
@onready var enter_tooltip_locked_template: Label = $GalaxyInfoPanel/Margin/Root/EnterTooltipLockedTemplate
@onready var enter_tooltip_unreachable_template: Label = (
	$GalaxyInfoPanel/Margin/Root/EnterTooltipUnreachableTemplate
)
@onready var enter_tooltip_default_template: Label = $GalaxyInfoPanel/Margin/Root/EnterTooltipDefaultTemplate
@onready var colonization_established_template: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationEstablishedTemplate
)
@onready var colonization_home_template: Label = $GalaxyInfoPanel/Margin/Root/ColonizationHomeTemplate
@onready var colonization_uncolonized_template: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationUncolonizedTemplate
)
@onready var colonization_blocked_template: Label = $GalaxyInfoPanel/Margin/Root/ColonizationBlockedTemplate
@onready var colonization_pending_fallback_template: Label = (
	$GalaxyInfoPanel/Margin/Root/ColonizationPendingFallbackTemplate
)
@onready var intel_known_template: Label = $GalaxyInfoPanel/Margin/Root/IntelKnownTemplate
@onready var intel_unknown_template: Label = $GalaxyInfoPanel/Margin/Root/IntelUnknownTemplate
@onready var no_description_template: Label = $GalaxyInfoPanel/Margin/Root/NoDescriptionTemplate
@onready var no_selection_info_template: Label = $GalaxyInfoPanel/Margin/Root/NoSelectionInfoTemplate

var _colonization_preview_system_def: SystemDefinition = null

var _no_selection_system_name: String = ""
var _access_status_prefix: String = ""
var _access_status_texts: Dictionary = {}
var _enter_tooltips: Dictionary = {}
var _colonization_state_texts: Dictionary = {}
var _colonization_pending_fallback: String = ""
var _intel_known_text: String = ""
var _intel_unknown_text: String = ""
var _no_description_text: String = ""
var _no_selection_info_text: String = ""
var _empty_value_text: String = "-"


func _ready() -> void:
	_capture_editor_text_templates()
	set_current_system_name("-")
	show_no_selection_state()
	set_process(false)


func _capture_editor_text_templates() -> void:
	_no_selection_system_name = system_name_label.text.strip_edges()
	_access_status_prefix = _label_prefix(access_status_label)
	_empty_value_text = _label_value_from_default(access_status_label, _access_status_prefix)
	_intel_unknown_text = known_resources_value_label.text.strip_edges()
	if intel_unknown_template != null:
		_intel_unknown_text = intel_unknown_template.text.strip_edges()

	_access_status_texts = {
		ACCESS_CURRENT: access_status_current_template.text.strip_edges(),
		ACCESS_READY: access_status_ready_template.text.strip_edges(),
		ACCESS_LOCKED: access_status_locked_template.text.strip_edges(),
		ACCESS_UNREACHABLE: access_status_unreachable_template.text.strip_edges(),
	}
	_enter_tooltips = {
		ACCESS_LOCKED: enter_tooltip_locked_template.text.strip_edges(),
		ACCESS_UNREACHABLE: enter_tooltip_unreachable_template.text.strip_edges(),
		"default": enter_tooltip_default_template.text.strip_edges(),
	}
	_colonization_state_texts = {
		"established": colonization_established_template.text.strip_edges(),
		"home": colonization_home_template.text.strip_edges(),
		"uncolonized": colonization_uncolonized_template.text.strip_edges(),
		"blocked": colonization_blocked_template.text.strip_edges(),
	}
	_colonization_pending_fallback = colonization_pending_fallback_template.text.strip_edges()
	_intel_known_text = intel_known_template.text.strip_edges()
	_no_description_text = no_description_template.text.strip_edges()
	_no_selection_info_text = no_selection_info_template.text.strip_edges()


func _label_prefix(label: Label) -> String:
	if label == null:
		return ""

	var text := label.text.strip_edges()
	var separator_index := text.find(": ")
	if separator_index >= 0:
		return text.substr(0, separator_index + 2)

	return ""


func _label_value_from_default(label: Label, prefix: String) -> String:
	if label == null:
		return "-"

	var text := label.text.strip_edges()
	if prefix.is_empty():
		return text

	if text.length() > prefix.length():
		return text.substr(prefix.length()).strip_edges()

	return "-"


func _meta_label(prefix: String, value: String) -> String:
	if prefix.is_empty():
		return value
	return "%s%s" % [prefix, value]


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
	colonization_state_value_label.text = _format_colonization_operation_status(op_id)


func show_info_panel() -> void:
	if is_instance_valid(galaxy_info_panel):
		galaxy_info_panel.visible = true


func hide_info_panel() -> void:
	if is_instance_valid(galaxy_info_panel):
		galaxy_info_panel.visible = false


func _on_close_button_pressed() -> void:
	hide_info_panel()
	close_requested.emit()


func set_current_system_name(system_name: String) -> void:
	var clean_name := system_name.strip_edges()
	var display := clean_name if clean_name != "" else "-"
	if is_instance_valid(current_system_value_label):
		current_system_value_label.text = display


func show_no_selection_state() -> void:
	hide_info_panel()
	if is_instance_valid(system_name_label):
		system_name_label.text = _no_selection_system_name
	if is_instance_valid(access_status_label):
		access_status_label.text = _meta_label(_access_status_prefix, _empty_value_text)
	if is_instance_valid(known_planets_value_label):
		known_planets_value_label.text = "0"
	if is_instance_valid(known_resources_value_label):
		known_resources_value_label.text = _intel_unknown_text
	_set_info_text(_no_selection_info_text)
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
		if access_state == ACCESS_LOCKED or _is_unknown_resources_summary(known_resources_text):
			known_resources_value_label.text = _intel_unknown_text
		else:
			known_resources_value_label.text = known_resources_text
	_set_info_text(info_text)
	if is_instance_valid(enter_button):
		enter_button.disabled = not can_enter
	_apply_enter_button_tooltip(can_enter, access_state)


func _is_unknown_resources_summary(summary_text: String) -> bool:
	var clean := summary_text.strip_edges()
	return clean.is_empty() or clean.to_lower() == "unknown"


func _set_info_text(value: String) -> void:
	var t := value.strip_edges()
	if t.is_empty():
		t = _no_description_text
	if is_instance_valid(info_text_label):
		info_text_label.text = t


func _apply_enter_button_tooltip(can_enter: bool, access_state: String) -> void:
	if not is_instance_valid(enter_button):
		return
	if can_enter:
		enter_button.tooltip_text = ""
		return
	match access_state:
		ACCESS_LOCKED:
			enter_button.tooltip_text = str(_enter_tooltips.get(ACCESS_LOCKED, ""))
		ACCESS_UNREACHABLE:
			enter_button.tooltip_text = str(_enter_tooltips.get(ACCESS_UNREACHABLE, ""))
		_:
			enter_button.tooltip_text = str(_enter_tooltips.get("default", ""))


func _access_status_text_for_state(access_state: String) -> String:
	var value := str(_access_status_texts.get(access_state, "")).strip_edges()
	return _meta_label(_access_status_prefix, value)


func _format_colonization_operation_status(operation_id: String) -> String:
	var status_view := GameSession.get_colonization_operation_status_view(operation_id)
	if status_view.is_empty():
		return _colonization_pending_fallback

	var def: ColonizationDefinition = GameSession.colonization_definition
	if def != null:
		var formatted := def.format_operation_status_view(status_view).strip_edges()
		if not formatted.is_empty():
			return formatted

	return _colonization_pending_fallback


## Phase 6.4d / 6.5 Colonization preview (nur Value-Labels; Start über ObjectInfoPanel).
func update_colonization_preview(system_def: SystemDefinition, access_state: String) -> void:
	if system_def == null:
		_colonization_preview_system_def = null
		set_process(false)
		return

	_colonization_preview_system_def = system_def
	_show_colonization_section()

	var sid: String = system_def.id.strip_edges()
	var pending_rec: Dictionary = GameSession.get_pending_colonization_operation_for_system(sid)

	if access_state == ACCESS_LOCKED or access_state == ACCESS_UNREACHABLE:
		_set_colonization_block(
			str(_colonization_state_texts.get("blocked", "")),
			_colonization_target_value_text(system_def, sid),
			_colonization_ships_count_text(sid),
			_colonization_intel_value_text(system_def, sid, pending_rec),
		)
		_set_cancel_dev_disabled()
		return

	if sid.is_empty():
		_set_colonization_block()
		_set_cancel_dev_disabled()
		return

	if GameSession.has_established_base_in_system(sid):
		var eb: String = GameSession.get_established_base_id_for_system(sid).strip_edges()
		var state_short := str(_colonization_state_texts.get("established", ""))
		if sid == GameSession.START_SYSTEM_ID:
			state_short = str(_colonization_state_texts.get("home", ""))
		var ships_n := 0
		if not eb.is_empty():
			ships_n = GameSession.get_base_colony_ship_count(eb)
		_set_colonization_block(
			state_short,
			_colonization_target_value_text(system_def, sid),
			str(ships_n),
			_colonization_intel_value_text(system_def, sid, pending_rec),
		)
		_set_cancel_dev_disabled()
		return

	if not pending_rec.is_empty():
		var op_id := str(pending_rec.get("operation_id", "")).strip_edges()
		_set_colonization_block(
			_format_colonization_operation_status(op_id),
			_colonization_target_value_text(system_def, sid),
			_colonization_ships_count_text(sid),
			_colonization_intel_value_text(system_def, sid, pending_rec),
		)
		colonization_cancel_button.disabled = false
		colonization_dev_button.disabled = false
		set_process(true)
		return

	set_process(false)

	var source_id := GameSession.get_colonization_source_base_id().strip_edges()
	var uncolonized_text := str(_colonization_state_texts.get("uncolonized", ""))

	if source_id.is_empty():
		_set_colonization_block(
			uncolonized_text,
			_colonization_target_value_text(system_def, sid),
			_colonization_ships_count_text(sid),
			_colonization_intel_value_text(system_def, sid, pending_rec),
		)
		_set_cancel_dev_disabled()
		return

	var cs_n: int = GameSession.get_base_colony_ship_count(source_id)

	_set_colonization_block(
		uncolonized_text,
		_colonization_target_value_text(system_def, sid),
		str(cs_n),
		_colonization_intel_value_text(system_def, sid, pending_rec),
	)
	_set_cancel_dev_disabled()
	set_process(false)


func _set_colonization_block(
	state_value: String = "-",
	target_value: String = "-",
	ships_value: String = "0",
	intel_value: String = "",
) -> void:
	var intel_display := intel_value.strip_edges()
	if intel_display.is_empty():
		intel_display = _intel_unknown_text

	if is_instance_valid(colonization_state_value_label):
		colonization_state_value_label.text = state_value
	if is_instance_valid(colonization_target_value_label):
		colonization_target_value_label.text = target_value
	if is_instance_valid(colonization_ships_value_label):
		colonization_ships_value_label.text = ships_value
	if is_instance_valid(colonization_intel_value_label):
		colonization_intel_value_label.text = intel_display


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
) -> String:
	var body_id := ""
	if GameSession.has_established_base_in_system(sid):
		var ebs := GameSession.get_established_base_id_for_system(sid).strip_edges()
		if not ebs.is_empty():
			body_id = GameSession.get_established_base_body_id(ebs).strip_edges()
	elif not pending_rec.is_empty():
		body_id = str(pending_rec.get("target_body_id", "")).strip_edges()

	if body_id.is_empty():
		return _intel_unknown_text

	var st := GameSession.get_object_scan_state(sid, body_id)
	if (
		st == GameSession.SCAN_BASIC
		or st == GameSession.SCAN_DEEP
		or st == GameSession.SCAN_SPECIAL
	):
		return _intel_known_text
	return _intel_unknown_text


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
	if is_instance_valid(colonization_secondary_row):
		colonization_secondary_row.visible = false


func _set_cancel_dev_disabled() -> void:
	colonization_cancel_button.disabled = true
	colonization_dev_button.disabled = true


func _on_enter_button_pressed() -> void:
	enter_requested.emit()


func _on_colon_cancel_pressed() -> void:
	colonization_cancel_requested.emit()


func _on_colon_dev_pressed() -> void:
	colonization_dev_complete_requested.emit()
