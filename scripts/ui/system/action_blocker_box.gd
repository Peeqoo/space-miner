extends PanelContainer
class_name ActionBlockerBox

@onready var title_label: Label = $Margin/Root/TitleLabel
@onready var reason_list: VBoxContainer = $Margin/Root/ReasonList
@onready var reason_label_template: Label = $Margin/Root/ReasonList/ReasonLabelTemplate


func _ready() -> void:
	reason_label_template.hide()
	hide()


func show_reasons(title: String, reasons: Array[String]) -> void:
	_clear_reasons()

	if reasons.is_empty():
		hide()
		return

	title_label.text = title

	for reason in reasons:
		var label := reason_label_template.duplicate() as Label
		label.text = "- %s" % reason
		label.visible = true
		label.custom_minimum_size = Vector2(0, 0)
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason_list.add_child(label)

	show()


func clear() -> void:
	_clear_reasons()
	hide()


func _clear_reasons() -> void:
	for child in reason_list.get_children():
		if child == reason_label_template:
			continue

		child.queue_free()
