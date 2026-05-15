## StoragePanel — manual discard of base storage (player-initiated only).
extends PanelContainer

signal close_requested
signal discard_resource_requested(resource_id: String, amount: int)

const _TEXT_SMALL_LS: LabelSettings = preload("res://scenes/ui/font_labels/text_label_small.tres")
const _BT_FONT: FontFile = preload("res://assets/fonts/PixelOperator8.ttf")

## Row layout: fixed-width discard columns; HBox separation matches compact tabular rows.
const _ROW_SEP := 6
const _BT_DISCARD10_MIN := Vector2(35, 12)
const _BT_DISCARD_ALL_MIN := Vector2(35, 12)

@onready var close_button: Button = $Margin/Root/HeaderRow/CloseButton
@onready var resource_list: VBoxContainer = $Margin/Root/ResourceList
@onready var empty_label: Label = $Margin/Root/EmptyLabel

var _base_id: String = BaseStore.BASE_EARTH


func _ready() -> void:
	visible = false

	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if not GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.connect(_on_game_session_base_resources_changed)


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_game_session_base_resources_changed)


func set_base_id(base_id: String) -> void:
	_base_id = base_id if not base_id.is_empty() else BaseStore.BASE_EARTH


func refresh(base_id: String = "") -> void:
	var id := _base_id if base_id.is_empty() else base_id
	if not base_id.is_empty():
		_base_id = id

	for c: Node in resource_list.get_children():
		c.free()

	var resources: Dictionary = GameSession.get_base_resources(id)
	var keys: Array = resources.keys()
	keys.sort()

	var any_row := false

	for res_key: Variant in keys:
		var rid := str(res_key)
		var amt := int(resources.get(res_key, 0))

		if amt <= 0 or rid.is_empty():
			continue

		any_row = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _ROW_SEP)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.custom_minimum_size = Vector2.ZERO

		var name_l := Label.new()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_l.custom_minimum_size = Vector2(0, 0)
		name_l.text = "%s: %d" % [rid.capitalize(), amt]
		name_l.label_settings = _TEXT_SMALL_LS
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.clip_contents = true
		row.add_child(name_l)

		var b10 := Button.new()
		b10.text = "-10"
		b10.tooltip_text = ""
		b10.custom_minimum_size = _BT_DISCARD10_MIN
		b10.size_flags_horizontal = Control.SIZE_SHRINK_END
		b10.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_theme_list_button(b10)
		b10.pressed.connect(_on_discard_pressed.bind(rid, 10))
		row.add_child(b10)

		var ball := Button.new()
		ball.text = "All"
		ball.tooltip_text = ""
		ball.custom_minimum_size = _BT_DISCARD_ALL_MIN
		ball.size_flags_horizontal = Control.SIZE_SHRINK_END
		ball.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_theme_list_button(ball)
		ball.pressed.connect(_on_discard_pressed.bind(rid, amt))
		row.add_child(ball)

		resource_list.add_child(row)

	empty_label.visible = not any_row
	resource_list.visible = any_row

	call_deferred("_fit_height_to_content")


func _fit_height_to_content() -> void:
	if not is_inside_tree():
		return
	var target_h: float = get_combined_minimum_size().y
	size.y = target_h


func _theme_list_button(btn: Button) -> void:
	btn.flat = false
	btn.add_theme_font_override("font", _BT_FONT)
	btn.add_theme_font_size_override("font_size", 4)


func _on_close_pressed() -> void:
	call_deferred("_fit_height_to_content")
	close_requested.emit()


func _on_discard_pressed(resource_id: String, amount: int) -> void:
	discard_resource_requested.emit(resource_id, amount)


func _on_game_session_base_resources_changed(changed_base_id: String) -> void:
	if not visible:
		return
	if changed_base_id != _base_id:
		return
	refresh()
