## StoragePanel — manual discard of base storage (player-initiated only).
extends PanelContainer

signal close_requested
signal discard_resource_requested(resource_id: String, amount: int)

const _TEXT_SMALL_LS: LabelSettings = preload("res://scenes/ui/font_labels/text_label_small.tres")

## Row layout: fixed-width discard column; HBox separation matches compact tabular rows.
const _ROW_SEP := 6

@onready var close_button: Button = $Margin/Root/HeaderRow/CloseButton
@onready var storage_info_label: Label = $Margin/Root/StorageInfoLabel
@onready var resource_list: VBoxContainer = (
	$Margin/Root/ResourcePanel/ResourceMargin/ResourceScroll/ResourceList
)
@onready var empty_label: Label = $Margin/Root/EmptyLabel
@onready var discard_10_button_template: Button = $Margin/Root/Discard10ButtonTemplate

var _base_id: String = BaseStore.BASE_EARTH
var _refresh_queued: bool = false


func _ready() -> void:
	visible = false

	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	AudioManager.bind_ui_button_optional(close_button)

	if not GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.connect(_on_game_session_base_resources_changed)


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_game_session_base_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_game_session_base_resources_changed)


func set_base_id(base_id: String) -> void:
	_base_id = base_id if not base_id.is_empty() else BaseStore.BASE_EARTH


func refresh(base_id: String = "") -> void:
	if not base_id.is_empty():
		_base_id = base_id
	_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_run_deferred_refresh")


func _run_deferred_refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	_apply_refresh()


func _apply_refresh() -> void:
	_update_storage_capacity_line()

	for c: Node in resource_list.get_children():
		c.free()

	var resources: Dictionary = GameSession.get_base_resources(_base_id)
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

		var name_l := Label.new()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_l.size_flags_stretch_ratio = 1.0
		name_l.text = "%s: %s" % [rid.capitalize(), NumberFormat.format_compact(amt)]
		name_l.label_settings = _TEXT_SMALL_LS
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_l)

		var b10 := discard_10_button_template.duplicate() as Button
		b10.visible = true
		b10.size_flags_horizontal = Control.SIZE_SHRINK_END
		b10.tooltip_text = ""
		b10.pressed.connect(_on_discard_pressed.bind(rid, 10))
		AudioManager.bind_ui_button_optional(b10)
		row.add_child(b10)

		resource_list.add_child(row)

	empty_label.visible = not any_row
	resource_list.visible = any_row


func _update_storage_capacity_line() -> void:
	if storage_info_label == null:
		return

	var used: int = GameSession.get_base_storage_used(_base_id)
	var cap: int = GameSession.get_base_storage_capacity(_base_id)
	var line := "%s / %s" % [
		NumberFormat.format_compact(used),
		NumberFormat.format_compact(cap),
	]

	if GameSession.is_base_storage_full(_base_id):
		line += " — %s" % GameSession.get_base_storage_blocked_reason_full()

	storage_info_label.text = line
	storage_info_label.visible = true


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_discard_pressed(resource_id: String, amount: int) -> void:
	discard_resource_requested.emit(resource_id, amount)


func _on_game_session_base_resources_changed(changed_base_id: String) -> void:
	if not visible:
		return
	if changed_base_id != _base_id:
		return
	_queue_refresh()
