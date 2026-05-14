## TopHudHoverPanel — reusable detail popup for TopHUD widget hovers.
## API: show_details(title, details, hint, screen_position) / clear()
extends PanelContainer

@onready var title_label: Label = $Margin/Root/TitleLabel
@onready var detail_list: VBoxContainer = $Margin/Root/DetailList
@onready var detail_label_template: Label = $Margin/Root/DetailList/DetailLabelTemplate
@onready var divider_b: HSeparator = $Margin/Root/DividerB
@onready var hint_label: Label = $Margin/Root/HintLabel


func _ready() -> void:
	detail_label_template.hide()
	hint_label.hide()
	divider_b.hide()
	visible = false


func show_details(
	p_title: String,
	p_details: Array,
	p_hint: String,
	screen_position: Vector2
) -> void:
	_clear_detail_labels()

	title_label.text = p_title
	var clean_hint := p_hint.strip_edges()
	hint_label.text = clean_hint
	hint_label.visible = not clean_hint.is_empty()
	divider_b.visible = hint_label.visible

	for detail_text: Variant in p_details:
		var lbl := detail_label_template.duplicate() as Label
		lbl.text = str(detail_text)
		lbl.visible = true
		lbl.custom_minimum_size = Vector2(0, 0)
		lbl.size_flags_horizontal = Control.SIZE_FILL
		lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_list.add_child(lbl)

	## screen_position is the final top-left in screen space (clamped by SystemUIController safe zone).
	position = Vector2(screen_position.x, screen_position.y)

	visible = true
	call_deferred("_fit_height_after_layout")


func clear() -> void:
	_clear_detail_labels()
	hint_label.hide()
	divider_b.hide()
	size.y = 0.0
	visible = false


func _fit_height_after_layout() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not visible:
		return
	_fit_height_to_content()


func _fit_height_to_content() -> void:
	size.y = get_combined_minimum_size().y


func _clear_detail_labels() -> void:
	for child in detail_list.get_children():
		if child == detail_label_template:
			continue
		child.free()
	detail_label_template.hide()
