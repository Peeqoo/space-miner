extends PanelContainer

const DEFAULT_STORAGE_ROW_SCENE: PackedScene = preload("res://scenes/ui/system/storage_row.tscn")

@export var storage_row_scene: PackedScene = DEFAULT_STORAGE_ROW_SCENE

@onready var base_name_label: Label = $Margin/Root/BaseNameLabel
@onready var dock_status_label: Label = $Margin/Root/DockStatusLabel
@onready var storage_list: VBoxContainer = $Margin/Root/StoragePanel/StorageMargin/StorageScroll/StorageList
@onready var empty_storage_label: Label = $Margin/Root/EmptyStorageLabel

var current_system_id: String = ""
var current_body_id: String = ""
var current_base_name: String = ""
var is_docked: bool = false


func _ready() -> void:
	if storage_row_scene == null:
		storage_row_scene = DEFAULT_STORAGE_ROW_SCENE
	visible = false
	_refresh_runtime_labels()
	_clear_storage_list()
	_update_empty_storage_visibility()


func show_for_base(system_id: String, body_id: String, base_name: String, docked: bool) -> void:
	current_system_id = system_id
	current_body_id = body_id
	current_base_name = base_name
	is_docked = docked

	visible = true
	_refresh_runtime_labels()
	refresh_from_game_session()


func hide_panel() -> void:
	visible = false
	current_system_id = ""
	current_body_id = ""
	current_base_name = ""
	is_docked = false
	_clear_storage_list()
	_refresh_runtime_labels()
	_update_empty_storage_visibility()


func set_base_name(base_name: String) -> void:
	current_base_name = base_name
	_refresh_runtime_labels()


func set_docked_state(value: bool) -> void:
	is_docked = value
	_refresh_runtime_labels()



func set_storage_from_dictionary(storage: Dictionary) -> void:
	_clear_storage_list()

	for resource_id in storage.keys():
		var amount: int = int(storage.get(resource_id, 0))
		if amount <= 0:
			continue
		_add_storage_row(str(resource_id), amount)

	_update_empty_storage_visibility()


func set_storage_from_array(items: Array) -> void:
	_clear_storage_list()

	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue

		var resource_name: String = str(item.get("resource_name", item.get("resource_id", "")))
		var amount: int = int(item.get("amount", 0))

		if resource_name.is_empty() or amount <= 0:
			continue

		_add_storage_row(resource_name, amount)

	_update_empty_storage_visibility()


func refresh_from_game_session() -> void:
	if typeof(GameSession) == TYPE_NIL:
		_clear_storage_list()
		_update_empty_storage_visibility()
		return

	if current_system_id.is_empty() or current_body_id.is_empty():
		_clear_storage_list()
		_update_empty_storage_visibility()
		return

	if GameSession.has_method("get_base_storage_items"):
		var items_variant: Variant = GameSession.get_base_storage_items(current_system_id, current_body_id)
		if items_variant is Array:
			set_storage_from_array(items_variant as Array)
			return
		elif items_variant is Dictionary:
			set_storage_from_dictionary(items_variant as Dictionary)
			return

	_clear_storage_list()
	_update_empty_storage_visibility()


func _refresh_runtime_labels() -> void:
	if base_name_label != null and not current_base_name.is_empty():
		base_name_label.text = current_base_name

	if dock_status_label != null:
		dock_status_label.text = "Status: Angedockt" if is_docked else "Status: Nicht angedockt"


func _add_storage_row(resource_name: String, amount: int) -> void:
	if storage_row_scene == null:
		storage_row_scene = DEFAULT_STORAGE_ROW_SCENE
	if storage_row_scene == null:
		return

	var row: Node = storage_row_scene.instantiate()
	if row == null:
		return

	if row.has_method("set_row_data"):
		row.call("set_row_data", resource_name, amount)

	storage_list.add_child(row)


func _clear_storage_list() -> void:
	if storage_list == null:
		return

	for child in storage_list.get_children():
		child.queue_free()


func _update_empty_storage_visibility() -> void:
	if empty_storage_label == null or storage_list == null:
		return

	empty_storage_label.visible = storage_list.get_child_count() == 0
