extends Control

const _SLOT_ROW_NAMES: PackedStringArray = ["Slot1Row", "Slot2Row", "Slot3Row"]

@onready var main_menu_buttons: Control = $RootPanel/Margin/Root/MainMenuButtons
@onready var save_slot_panel: Control = $RootPanel/Margin/Root/SaveSlotPanel

var _slot_ui: Array[Dictionary] = []


func _ready() -> void:
	_build_slot_ui()
	_show_main_menu_buttons()
	_refresh_all_slots()


func _build_slot_ui() -> void:
	_slot_ui.clear()
	for i in range(SaveManager.MAX_SAVE_SLOTS):
		var slot_index := i + 1
		var row_name := _SLOT_ROW_NAMES[i]
		var row := save_slot_panel.get_node_or_null(row_name)
		if row == null:
			continue
		var filled := row.get_node_or_null("FilledStateContainer") as Control
		var empty := row.get_node_or_null("EmptyStateContainer") as Control
		var delete_confirm := row.get_node_or_null("DeleteConfirmContainer") as Control
		var timestamp_value := row.get_node_or_null(
			"FilledStateContainer/SaveTimestampRow/SaveTimestampValueLabel"
		) as Label
		var system_value := row.get_node_or_null(
			"FilledStateContainer/SaveSystemRow/SaveSystemValueLabel"
		) as Label
		var load_button := row.get_node_or_null(
			"FilledStateContainer/SlotActionsRow/LoadSlotButton"
		) as Button
		var delete_button := row.get_node_or_null(
			"FilledStateContainer/SlotActionsRow/DeleteSlotButton"
		) as Button
		var confirm_delete_button := row.get_node_or_null(
			"DeleteConfirmContainer/DeleteConfirmActionsRow/ConfirmDeleteButton"
		) as Button
		var cancel_delete_button := row.get_node_or_null(
			"DeleteConfirmContainer/DeleteConfirmActionsRow/CancelDeleteButton"
		) as Button

		if load_button != null and not load_button.pressed.is_connected(_on_load_slot_pressed):
			load_button.pressed.connect(_on_load_slot_pressed.bind(slot_index))
		if delete_button != null and not delete_button.pressed.is_connected(_on_delete_slot_pressed):
			delete_button.pressed.connect(_on_delete_slot_pressed.bind(slot_index))
		if confirm_delete_button != null and not confirm_delete_button.pressed.is_connected(
			_on_confirm_delete_pressed
		):
			confirm_delete_button.pressed.connect(_on_confirm_delete_pressed.bind(slot_index))
		if cancel_delete_button != null and not cancel_delete_button.pressed.is_connected(
			_on_cancel_delete_pressed
		):
			cancel_delete_button.pressed.connect(_on_cancel_delete_pressed.bind(slot_index))

		_slot_ui.append(
			{
				"slot_index": slot_index,
				"row": row,
				"filled": filled,
				"empty": empty,
				"delete_confirm": delete_confirm,
				"timestamp_value": timestamp_value,
				"system_value": system_value,
				"load_button": load_button,
				"delete_button": delete_button,
			}
		)


func _show_main_menu_buttons() -> void:
	main_menu_buttons.visible = true
	save_slot_panel.visible = false
	_hide_all_delete_confirms()


func _show_save_slot_panel() -> void:
	main_menu_buttons.visible = false
	save_slot_panel.visible = true
	_hide_all_delete_confirms()
	_refresh_all_slots()


func _hide_all_delete_confirms() -> void:
	for slot_data: Dictionary in _slot_ui:
		var confirm: Control = slot_data.get("delete_confirm") as Control
		if is_instance_valid(confirm):
			confirm.visible = false


func _refresh_all_slots() -> void:
	for slot_data: Dictionary in _slot_ui:
		_refresh_slot(slot_data)


func _refresh_slot(slot_data: Dictionary) -> void:
	var slot_index: int = int(slot_data.get("slot_index", 0))
	var filled: Control = slot_data.get("filled") as Control
	var empty: Control = slot_data.get("empty") as Control
	var load_button: Button = slot_data.get("load_button") as Button
	var delete_button: Button = slot_data.get("delete_button") as Button
	var timestamp_value: Label = slot_data.get("timestamp_value") as Label
	var system_value: Label = slot_data.get("system_value") as Label

	var meta := SaveManager.get_save_metadata(slot_index)
	var exists: bool = bool(meta.get("exists", false)) and SaveManager.has_save(slot_index)

	if is_instance_valid(filled):
		filled.visible = exists
	if is_instance_valid(empty):
		empty.visible = not exists
	if is_instance_valid(load_button):
		load_button.disabled = not exists
	if is_instance_valid(delete_button):
		delete_button.disabled = not exists

	if not exists:
		return

	var unix_ts := int(meta.get("saved_at_unix", 0))
	if is_instance_valid(timestamp_value):
		if unix_ts > 0:
			timestamp_value.text = _format_unix_timestamp(unix_ts)
		else:
			timestamp_value.text = "—"

	if is_instance_valid(system_value):
		var system_id := str(meta.get("current_system_id", "")).strip_edges()
		system_value.text = _system_display_for_id(system_id)


func _format_unix_timestamp(unix_ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_ts, true)


func _system_display_for_id(system_id: String) -> String:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return "—"
	var path := "res://data/galaxy_systems/%s_system.tres" % sid.replace("-", "_")
	var def := load(path) as SystemDefinition
	if def != null:
		var dn := str(def.display_name).strip_edges()
		if not dn.is_empty():
			return dn
	return sid


func _get_slot_ui(slot_index: int) -> Dictionary:
	for slot_data: Dictionary in _slot_ui:
		if int(slot_data.get("slot_index", 0)) == slot_index:
			return slot_data
	return {}


func _on_start_game_pressed() -> void:
	SaveManager.set_active_save_slot(1)
	GameSession.reset_for_new_game()
	SceneFlow.goto_system()


func _on_load_game_pressed() -> void:
	_show_save_slot_panel()


func _on_back_pressed() -> void:
	_show_main_menu_buttons()


func _on_load_slot_pressed(slot_index: int) -> void:
	if not SaveManager.has_save(slot_index):
		return
	SaveManager.set_active_save_slot(slot_index)
	if not SaveManager.load_game(slot_index):
		_refresh_all_slots()
		return
	SceneFlow.goto_system()


func _on_delete_slot_pressed(slot_index: int) -> void:
	if not SaveManager.has_save(slot_index):
		return
	var slot_data := _get_slot_ui(slot_index)
	var confirm: Control = slot_data.get("delete_confirm") as Control
	if is_instance_valid(confirm):
		confirm.visible = true


func _on_confirm_delete_pressed(slot_index: int) -> void:
	SaveManager.delete_save(slot_index)
	var slot_data := _get_slot_ui(slot_index)
	var confirm: Control = slot_data.get("delete_confirm") as Control
	if is_instance_valid(confirm):
		confirm.visible = false
	_refresh_slot(slot_data)


func _on_cancel_delete_pressed(slot_index: int) -> void:
	var slot_data := _get_slot_ui(slot_index)
	var confirm: Control = slot_data.get("delete_confirm") as Control
	if is_instance_valid(confirm):
		confirm.visible = false


func _on_exit_pressed() -> void:
	get_tree().quit()
