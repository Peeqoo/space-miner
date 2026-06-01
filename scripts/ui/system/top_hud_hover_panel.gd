## TopHudHoverPanel — reusable detail popup for TopHUD widget hovers.
## API: show_details(title, details, hint, source_control) / clear()
class_name TopHUDHoverPanel
extends PanelContainer

const _HOVER_BELOW_MARGIN := 4.0
const _VIEWPORT_MARGIN := 8.0

var _source_control: Control = null

@onready var title_label: Label = $Margin/Root/TitleLabel
@onready var detail_list: VBoxContainer = $Margin/Root/DetailList
@onready var detail_label_template: Label = $Margin/Root/DetailList/DetailLabelTemplate
@onready var divider_b: HSeparator = $Margin/Root/DividerB
@onready var hint_label: Label = $Margin/Root/HintLabel
@onready var _effects_section_label: Label = $Margin/Root/EffectsSectionLabelTemplate


func _ready() -> void:
	detail_label_template.hide()
	hint_label.hide()
	divider_b.hide()
	visible = false


func show_details(
	p_title: String,
	p_details: Array,
	p_hint: String,
	source_control: Control
) -> void:
	_source_control = source_control
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

	_position_below_source_control()
	visible = true
	call_deferred("_fit_height_after_layout")


func clear() -> void:
	_source_control = null
	_clear_detail_labels()
	hint_label.hide()
	divider_b.hide()
	size.y = 0.0
	visible = false


func get_effects_section_caption() -> String:
	if _effects_section_label != null:
		return _effects_section_label.text.strip_edges()
	return ""


func _fit_height_after_layout() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not visible:
		return
	_fit_height_to_content()


func _fit_height_to_content() -> void:
	size.y = get_combined_minimum_size().y
	_position_below_source_control()


func _position_below_source_control() -> void:
	if _source_control == null or not is_instance_valid(_source_control):
		return

	var source_rect := _source_control.get_global_rect()
	var hover_size := size
	if hover_size.x <= 0.0:
		hover_size.x = custom_minimum_size.x
	if hover_size.x <= 0.0:
		hover_size.x = get_combined_minimum_size().x

	var x := source_rect.position.x + source_rect.size.x * 0.5 - hover_size.x * 0.5
	var y := source_rect.position.y + source_rect.size.y + _HOVER_BELOW_MARGIN
	global_position = _clamp_hover_position_to_viewport(Vector2(x, y), hover_size)


func _clamp_hover_position_to_viewport(pos: Vector2, hover_size: Vector2) -> Vector2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return pos

	var margin := _VIEWPORT_MARGIN
	var viewport_size := vp.get_visible_rect().size
	var min_x := margin
	var max_x := viewport_size.x - hover_size.x - margin
	if max_x < min_x:
		pos.x = viewport_size.x * 0.5 - hover_size.x * 0.5
	else:
		pos.x = clampf(pos.x, min_x, max_x)

	var max_y := viewport_size.y - hover_size.y - margin
	if hover_size.y > 0.0 and pos.y > max_y:
		pos.y = maxf(margin, max_y)

	return pos


func _clear_detail_labels() -> void:
	for child in detail_list.get_children():
		if child == detail_label_template:
			continue
		child.free()
	detail_label_template.hide()
