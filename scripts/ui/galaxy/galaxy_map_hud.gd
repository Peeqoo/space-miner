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

@onready var title_label: Label = $TopBar/Margin/Row/TitleLabel
@onready var current_system_title_label: Label = $TopBar/Margin/Row/CurrentSystemTitleLabel
@onready var current_system_value_label: Label = $TopBar/Margin/Row/CurrentSystemValueLabel

@onready var header_label: Label = $GalaxyInfoPanel/Margin/Root/HeaderLabel
@onready var system_name_label: Label = $GalaxyInfoPanel/Margin/Root/SystemNameLabel
@onready var scan_title_label: Label = $GalaxyInfoPanel/Margin/Root/ScanTitleLabel
@onready var known_planets_value_label: Label = $GalaxyInfoPanel/Margin/Root/StatsGrid/KnownPlanetsValueLabel
@onready var known_resources_value_label: Label = $GalaxyInfoPanel/Margin/Root/StatsGrid/KnownResourcesValueLabel
@onready var info_title_label: Label = $GalaxyInfoPanel/Margin/Root/InfoTitleLabel
@onready var info_text_label: Label = $GalaxyInfoPanel/Margin/Root/InfoTextLabel
@onready var colonization_divider_a: Control = $GalaxyInfoPanel/Margin/Root/ColonizationDividerA
@onready var colonization_title_label: Label = $GalaxyInfoPanel/Margin/Root/ColonizationTitleLabel
@onready var colonization_status_label: Label = $GalaxyInfoPanel/Margin/Root/ColonizationStatusLabel
@onready var colonization_deploy_button: Button = $GalaxyInfoPanel/Margin/Root/ColonizationDeployButton
@onready var colonization_cancel_button: Button = $GalaxyInfoPanel/Margin/Root/ColonizationSecondaryRow/ColonizationCancelButton
@onready var colonization_dev_button: Button = $GalaxyInfoPanel/Margin/Root/ColonizationSecondaryRow/ColonizationDevButton
@onready var enter_button: Button = $GalaxyInfoPanel/Margin/Root/EnterButton


func _ready() -> void:
	title_label.text = "GALAXY MAP"
	current_system_title_label.text = "Aktuelles System:"
	header_label.text = "SYSTEM"
	scan_title_label.text = "SCANDATEN"
	info_title_label.text = "INFO"

	set_current_system_name("-")
	show_no_selection_state()


func set_current_system_name(system_name: String) -> void:
	current_system_value_label.text = system_name if not system_name.is_empty() else "-"


func show_no_selection_state() -> void:
	system_name_label.text = "Kein System gewählt"
	known_planets_value_label.text = "0"
	known_resources_value_label.text = "Unknown"
	info_text_label.text = "Kein System ausgewählt."
	header_label.text = "SYSTEM"
	scan_title_label.text = "SCANDATEN"
	enter_button.disabled = true
	enter_button.text = "Enter"
	_hide_colonization_section()


func show_system_info(
	system_name: String,
	known_planets_count: int,
	known_resources_text: String,
	info_text: String,
	can_enter: bool,
	access_state: String,
) -> void:
	system_name_label.text = system_name
	known_planets_value_label.text = str(max(known_planets_count, 0))
	header_label.text = _header_text_for_access(access_state)

	if access_state == ACCESS_LOCKED:
		scan_title_label.text = "STATUS"
		known_resources_value_label.text = "Unknown"
	else:
		scan_title_label.text = "SCANDATEN"
		known_resources_value_label.text = (
			known_resources_text if not known_resources_text.is_empty() else "Unknown"
		)

	info_text_label.text = (
		info_text if not info_text.is_empty() else "Keine Beschreibung verfügbar."
	)
	enter_button.disabled = not can_enter
	_apply_enter_button_caption(can_enter, access_state)


## Phase 6.4d Colonization preview (generic copy only — keine Ressourcendaten aus .tres).
func update_colonization_preview(system_def: SystemDefinition, access_state: String) -> void:
	if colonization_status_label == null or colonization_deploy_button == null:
		return

	_show_colonization_section()

	if access_state == ACCESS_LOCKED or access_state == ACCESS_UNREACHABLE:
		colonization_status_label.text = (
			"Expansion hier nicht möglich (Zugriffsstatus).\n"
			+ "Wähle ein erreichbares, freigeschaltetes System."
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	var sid: String = system_def.id.strip_edges()
	var start_body: String = system_def.start_body_id.strip_edges()

	if sid.is_empty():
		colonization_status_label.text = "Kein gültiges Zielsystem."
		_set_deploy_cancel_dev_disabled()
		return

	if sid == GameSession.START_SYSTEM_ID and GameSession.has_established_base_in_system(sid):
		colonization_status_label.text = (
			"Heimatsystem\n"
			+ "Basis etabliert — lokale Expansion nutzt Produktion/Systemansicht.\n\n"
			+ "Keine Fremdkolonisierung von der Galaxy-Map hier erforderlich."
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	if GameSession.has_established_base_in_system(sid):
		var eb: String = GameSession.get_established_base_id_for_system(sid).strip_edges()
		colonization_status_label.text = (
			"Basis etabliert\n"
			+ "Basis: %s\n\n"
			+ "Nutze „System betreten“ für lokale Economy und Automation." % eb
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	var pending_rec: Dictionary = GameSession.get_pending_colonization_operation_for_system(sid)
	if not pending_rec.is_empty():
		var tgt_body := str(pending_rec.get("target_body_id", "")).strip_edges()
		colonization_status_label.text = (
			"Kolonisierung läuft.\n"
			+ "Ein ColonyShip ist unterwegs (Status: pending).\n"
			+ "Zielobjekt-ID: %s\n\n"
			% tgt_body
			+ "(Reise-/Ankunftslogik folgt später; DEV-Endpunkt unten nur für Tests.)"
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = false
		colonization_dev_button.disabled = false
		return

	if start_body.is_empty():
		colonization_status_label.text = (
			"Kein gültiger Koloniezielkörper definiert (start_body_id leer)."
		)
		_set_deploy_cancel_dev_disabled()
		return

	var source_id := GameSession.get_colonization_source_base_id().strip_edges()

	var coarse_hint := _coarse_hint_for_body(system_def)

	if source_id.is_empty():
		colonization_status_label.text = (
			"Unkolonisiertes System\n"
			+ coarse_hint
			+ "\nColonyShips verfügbar: 0\n\n"
			+ "Kein ColonyShip verfügbar.\nBaue zuerst ein ColonyShip in einer etablierten Basis.\n\n"
			+ "%s\n"
			% _colonization_intel_block()
		)
		colonization_deploy_button.disabled = true
		colonization_cancel_button.disabled = true
		colonization_dev_button.disabled = true
		return

	var cs_n: int = GameSession.get_base_colony_ship_count(source_id)

	colonization_status_label.text = (
		"Unkolonisiertes System\n"
		+ coarse_hint
		+ ("\nColonyShips verfügbar: %d bei Basis %s\n\n" % [cs_n, source_id])
		+ "%s\n" % _colonization_intel_block()
	)
	colonization_deploy_button.disabled = cs_n < 1
	colonization_cancel_button.disabled = true
	colonization_dev_button.disabled = true


func _colonization_intel_block() -> String:
	return (
		"Ressourcen-Intel: Unbekannt\n"
		+ "Unbestätigte Oberflächensignaturen.\n"
		+ "Basic-Scan ist erforderlich, um ein Ressourcenprofil zu bestätigen.\n"
		+ "Passive Basis-Erträge werden später durch Base-Upgrades freigeschaltet."
	)


func _coarse_hint_for_body(system_def: SystemDefinition) -> String:
	var sid := system_def.start_body_id.strip_edges()
	if sid.is_empty():
		return ""
	for bd in system_def.bodies:
		if bd != null and str(bd.id).strip_edges() == sid:
			var bt := str(bd.body_type).strip_edges()
			if not bt.is_empty():
				return "Vorschlagskörper: %s (Kategorie: %s)" % [
					system_def.start_body_id,
					bt,
				]
			return "Vorschlagskörper: %s" % system_def.start_body_id
	return "Vorschlagskörper: %s (Details folgen erst nach Exploration)" % system_def.start_body_id


func _header_text_for_access(access_state: String) -> String:
	match access_state:
		ACCESS_CURRENT:
			return "CURRENT SYSTEM"
		ACCESS_READY:
			return "READY"
		ACCESS_LOCKED:
			return "LOCKED"
		ACCESS_UNREACHABLE:
			return "UNREACHABLE"
		_:
			return "SYSTEM"


func _apply_enter_button_caption(can_enter: bool, access_state: String) -> void:
	if can_enter:
		enter_button.text = "System betreten"
		return
	if access_state == ACCESS_LOCKED:
		enter_button.text = "LOCKED"
	elif access_state == ACCESS_UNREACHABLE:
		enter_button.text = "UNREACHABLE"
	else:
		enter_button.text = "Enter"


func _show_colonization_section() -> void:
	colonization_divider_a.visible = true
	colonization_title_label.visible = true
	colonization_status_label.visible = true
	colonization_deploy_button.visible = true
	colonization_cancel_button.get_parent().visible = true


func _hide_colonization_section() -> void:
	if colonization_divider_a == null:
		return
	colonization_divider_a.visible = false
	colonization_title_label.visible = false
	colonization_status_label.visible = false
	colonization_status_label.text = ""
	colonization_deploy_button.visible = false
	colonization_cancel_button.get_parent().visible = false


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
