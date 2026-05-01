extends Control
class_name GalaxyMapHUD

signal enter_requested

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
@onready var enter_button: Button = $GalaxyInfoPanel/Margin/Root/EnterButton


func _ready() -> void:
	if not enter_button.pressed.is_connected(_on_enter_button_pressed):
		enter_button.pressed.connect(_on_enter_button_pressed)

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
	enter_button.disabled = true


func show_system_info(
	system_name: String,
	known_planets_count: int,
	known_resources_text: String,
	info_text: String,
	can_enter: bool,
	is_current_system: bool
) -> void:
	var display_text: String = system_name
	if is_current_system:
		display_text += " (aktuell)"

	system_name_label.text = display_text
	known_planets_value_label.text = str(max(known_planets_count, 0))
	known_resources_value_label.text = known_resources_text if not known_resources_text.is_empty() else "Unknown"
	info_text_label.text = info_text if not info_text.is_empty() else "Keine Beschreibung verfügbar."
	enter_button.disabled = not can_enter


func _on_enter_button_pressed() -> void:
	enter_requested.emit()
