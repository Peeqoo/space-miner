## Compact discovery-signal presentation block for ObjectInfoPanel (Phase C1).
class_name SignalInfoSubPanel
extends VBoxContainer

signal investigate_pressed()

@onready var lore_title_label: Label = $LoreTitleLabel
@onready var lore_panel: PanelContainer = $LorePanel
@onready var lore_text_label: Label = $LorePanel/LoreMargin/LoreTextLabel
@onready var economy_block_label: Label = $EconomyBlockLabel
@onready var investigate_progress_label: Label = $InvestigateProgressLabel
@onready var investigate_button: Button = $InvestigateButton
@onready var investigate_progress_format_template: Label = $InvestigateProgressFormatTemplate
@onready var no_description_lore_template: Label = $NoDescriptionLoreTemplate

var _no_description_lore: String = ""
var _investigate_progress_format: String = ""


func _ready() -> void:
	if no_description_lore_template != null:
		_no_description_lore = no_description_lore_template.text.strip_edges()
	if investigate_progress_format_template != null:
		_investigate_progress_format = investigate_progress_format_template.text.strip_edges()

	if investigate_button != null:
		if not investigate_button.pressed.is_connected(_on_investigate_button_pressed):
			investigate_button.pressed.connect(_on_investigate_button_pressed)
		AudioManager.bind_ui_button_optional(investigate_button)

	reset()


func apply_signal_info(info: Dictionary) -> void:
	var lore_text: String = str(info.get("lore_text", "")).strip_edges()
	if lore_text.is_empty():
		lore_text = _no_description_lore
	if lore_text_label != null:
		lore_text_label.text = lore_text

	var can_investigate: bool = info.get("can_investigate_signal", false) == true
	var in_progress: bool = info.get("investigate_in_progress", false) == true
	var blocked: String = str(info.get("investigate_blocked_reason", "")).strip_edges()
	var complete_msg: String = str(info.get("discovery_complete_message", "")).strip_edges()

	if investigate_button != null:
		if in_progress:
			investigate_button.visible = false
		else:
			investigate_button.visible = true
			investigate_button.disabled = not can_investigate

	if in_progress:
		var progress_text: String = str(info.get("investigate_progress_text", "")).strip_edges()
		if progress_text.is_empty():
			progress_text = _format_investigate_progress(
				int(round(float(info.get("investigate_progress", 0.0)) * 100.0))
			)
		show_investigate_progress(progress_text, float(info.get("investigate_progress", 0.0)))
	elif info.get("is_investigate_active", false) != true:
		hide_investigate_progress()

	_apply_economy_block(complete_msg, in_progress, can_investigate, blocked)


func show_investigate_progress(progress_text: String, _ratio: float) -> void:
	if investigate_progress_label == null:
		return
	investigate_progress_label.text = progress_text.strip_edges()
	investigate_progress_label.visible = true


func hide_investigate_progress() -> void:
	if investigate_progress_label == null:
		return
	investigate_progress_label.visible = false


func reset() -> void:
	if lore_text_label != null:
		lore_text_label.text = ""
	if economy_block_label != null:
		economy_block_label.text = ""
		economy_block_label.visible = false
	hide_investigate_progress()
	if investigate_button != null:
		investigate_button.visible = false
		investigate_button.disabled = true


func _apply_economy_block(
	complete_msg: String,
	in_progress: bool,
	can_investigate: bool,
	blocked: String,
) -> void:
	if economy_block_label == null:
		return

	if not complete_msg.is_empty():
		economy_block_label.text = complete_msg
		economy_block_label.visible = true
	elif in_progress:
		economy_block_label.visible = false
	elif not can_investigate and not blocked.is_empty():
		economy_block_label.text = blocked
		economy_block_label.visible = true
	else:
		economy_block_label.visible = false


func _format_investigate_progress(percent: int) -> String:
	var format_str := _investigate_progress_format.strip_edges()
	if format_str.is_empty():
		return DiscoverySignalUiTextDefinition.format_investigate_progress(percent)
	return format_str % maxi(0, percent)


func _on_investigate_button_pressed() -> void:
	if investigate_button == null or investigate_button.disabled:
		return
	investigate_pressed.emit()
