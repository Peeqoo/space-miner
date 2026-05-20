extends Control

@onready var continue_game_button: Button = $RootPanel/Margin/Root/ContinueGameButton
@onready var save_success_label: Label = $RootPanel/Margin/Root/SaveSuccessLabel
@onready var save_failed_label: Label = $RootPanel/Margin/Root/SaveFailedLabel
@onready var save_slot_value_label: Label = $RootPanel/Margin/Root/SaveSlotRow/SaveSlotValueLabel
@onready var save_timestamp_value_label: Label = (
	$RootPanel/Margin/Root/SaveTimestampRow/SaveTimestampValueLabel
)


func _ready() -> void:
	_hide_save_feedback()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if _is_pause_open_input(event):
			open_menu()
			get_viewport().set_input_as_handled()
		return
	if _is_pause_close_input(event):
		close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	_hide_save_feedback()
	_refresh_save_slot_display()
	_refresh_save_timestamp()
	visible = true


func close_menu() -> void:
	_hide_save_feedback()
	visible = false


func toggle_menu() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func show_pause_menu() -> void:
	open_menu()


func hide_pause_menu() -> void:
	close_menu()


func is_open() -> bool:
	return visible


func _hide_save_feedback() -> void:
	save_success_label.visible = false
	save_failed_label.visible = false


func _refresh_save_slot_display() -> void:
	if not is_instance_valid(save_slot_value_label):
		return
	var slot_idx := SaveManager.get_active_save_slot()
	if not SaveManager.is_valid_slot(slot_idx):
		slot_idx = 1
	save_slot_value_label.text = str(slot_idx)


func _refresh_save_timestamp() -> void:
	if not is_instance_valid(save_timestamp_value_label):
		return
	var slot_idx := SaveManager.get_active_save_slot()
	if not SaveManager.is_valid_slot(slot_idx):
		slot_idx = 1
	if not SaveManager.has_save(slot_idx):
		return
	var meta := SaveManager.get_save_metadata(slot_idx)
	var unix_ts := int(meta.get("saved_at_unix", 0))
	if unix_ts <= 0:
		return
	save_timestamp_value_label.text = _format_unix_timestamp(unix_ts)


func _format_unix_timestamp(unix_ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_ts, true)


func _is_pause_open_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		return key_ev.pressed and not key_ev.echo and key_ev.keycode == KEY_ESCAPE
	return false


func _is_pause_close_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		return key_ev.pressed and not key_ev.echo and key_ev.keycode == KEY_ESCAPE
	if event.is_action_pressed("ui_cancel"):
		return true
	return false


func _on_continue_game_pressed() -> void:
	close_menu()


func _on_save_game_pressed() -> void:
	_hide_save_feedback()
	var slot_idx := SaveManager.get_active_save_slot()
	if not SaveManager.is_valid_slot(slot_idx):
		SaveManager.set_active_save_slot(1)
		slot_idx = 1
	if SaveManager.save_game(slot_idx):
		save_success_label.visible = true
		_refresh_save_slot_display()
		_refresh_save_timestamp()
	else:
		save_failed_label.visible = true


func _on_exit_to_main_menu_pressed() -> void:
	close_menu()
	SceneFlow.goto_main_menu()
