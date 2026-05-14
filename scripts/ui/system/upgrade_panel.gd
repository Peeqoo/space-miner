## UpgradePanel — buy permanent upgrades for storage, scan drones, and mining ships.
## Uses Phase 5.1/5.2/5.3 GameSession APIs.
extends PanelContainer

signal close_requested

const BASE_ID: String = "earth"

const UPGRADE_INFO: Dictionary = {
	"StorageUpgradeButton": {
		"title": "Storage Upgrade I",
		"desc": "+100 storage capacity.",
	},
	"ScanDroneUpgradeButton": {
		"title": "ScanDrone Upgrade I",
		"desc": "ScanDrones scan 25% faster.",
	},
	"MiningShipUpgradeButton": {
		"title": "MiningShip Upgrade I",
		"desc": "MiningShips carry 25% more cargo.",
	},
}

@onready var storage_upgrade_button: Button = $Margin/Root/UpgradeList/StorageUpgradeButton
@onready var scan_drone_upgrade_button: Button = $Margin/Root/UpgradeList/ScanDroneUpgradeButton
@onready var mining_ship_upgrade_button: Button = $Margin/Root/UpgradeList/MiningShipUpgradeButton
@onready var close_button: Button = $Margin/Root/HeaderRow/CloseButton
@onready var hover_info_panel: PanelContainer = $Margin/Root/HoverInfoPanel
@onready var hover_title_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverTitleLabel
@onready var hover_desc_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverDescLabel
@onready var hover_cost_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverCostLabel


func _ready() -> void:
	visible = false
	hover_info_panel.visible = false

	_connect_button(close_button, _on_close_pressed)
	_connect_button(storage_upgrade_button, _on_storage_upgrade_pressed)
	_connect_button(scan_drone_upgrade_button, _on_scan_drone_upgrade_pressed)
	_connect_button(mining_ship_upgrade_button, _on_mining_ship_upgrade_pressed)

	_register_hover(storage_upgrade_button)
	_register_hover(scan_drone_upgrade_button)
	_register_hover(mining_ship_upgrade_button)

	if not GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.connect(_on_resources_changed)

	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_resources_changed)


func refresh_from_game_session() -> void:
	_refresh_upgrade_button(
		storage_upgrade_button,
		GameSession.is_base_storage_upgrade_i_bought(BASE_ID),
		GameSession.can_buy_base_storage_upgrade_i(BASE_ID)
	)
	_refresh_upgrade_button(
		scan_drone_upgrade_button,
		GameSession.is_scan_drone_upgrade_i_bought(BASE_ID),
		GameSession.can_buy_scan_drone_upgrade_i(BASE_ID)
	)
	_refresh_upgrade_button(
		mining_ship_upgrade_button,
		GameSession.is_mining_ship_upgrade_i_bought(BASE_ID),
		GameSession.can_buy_mining_ship_upgrade_i(BASE_ID)
	)


func _refresh_upgrade_button(button: Button, is_bought: bool, can_buy: bool) -> void:
	if button == null:
		return
	button.disabled = is_bought or not can_buy


func _on_close_pressed() -> void:
	hover_info_panel.visible = false
	call_deferred("_fit_height_to_content")
	close_requested.emit()


func _on_storage_upgrade_pressed() -> void:
	if GameSession.buy_base_storage_upgrade_i(BASE_ID):
		refresh_from_game_session()


func _on_scan_drone_upgrade_pressed() -> void:
	if GameSession.buy_scan_drone_upgrade_i(BASE_ID):
		refresh_from_game_session()


func _on_mining_ship_upgrade_pressed() -> void:
	if GameSession.buy_mining_ship_upgrade_i(BASE_ID):
		refresh_from_game_session()


func _register_hover(button: Button) -> void:
	if button == null:
		return
	if not button.mouse_entered.is_connected(_on_button_hover_entered.bind(button)):
		button.mouse_entered.connect(_on_button_hover_entered.bind(button))
	if not button.mouse_exited.is_connected(_on_button_hover_exited.bind(button)):
		button.mouse_exited.connect(_on_button_hover_exited.bind(button))


func _on_button_hover_entered(button: Button) -> void:
	var info: Dictionary = UPGRADE_INFO.get(button.name, {})
	if info.is_empty():
		return

	hover_title_label.text = str(info.get("title", ""))

	if _is_upgrade_bought(button.name):
		hover_desc_label.text = "Already installed."
		hover_cost_label.text = ""
	else:
		hover_desc_label.text = str(info.get("desc", ""))
		hover_cost_label.text = _build_cost_text(button.name)

	hover_info_panel.visible = true
	call_deferred("_fit_height_to_content")


func _on_button_hover_exited(_button: Button) -> void:
	hover_info_panel.visible = false
	call_deferred("_fit_height_to_content")


func _is_upgrade_bought(button_name: String) -> bool:
	match button_name:
		"StorageUpgradeButton":
			return GameSession.is_base_storage_upgrade_i_bought(BASE_ID)
		"ScanDroneUpgradeButton":
			return GameSession.is_scan_drone_upgrade_i_bought(BASE_ID)
		"MiningShipUpgradeButton":
			return GameSession.is_mining_ship_upgrade_i_bought(BASE_ID)
	return false


func _build_cost_text(button_name: String) -> String:
	var resources := GameSession.get_base_resources(BASE_ID)
	match button_name:
		"StorageUpgradeButton":
			return _format_cost_lines(GameSession.get_base_storage_upgrade_i_cost(), resources)
		"ScanDroneUpgradeButton":
			return _format_cost_lines(GameSession.get_scan_drone_upgrade_i_cost(), resources)
		"MiningShipUpgradeButton":
			return _format_cost_lines(GameSession.get_mining_ship_upgrade_i_cost(), resources)
	return ""


func _format_cost_lines(cost: Dictionary, available: Dictionary) -> String:
	var lines: PackedStringArray = []
	for res_id: Variant in cost.keys():
		var need := int(cost.get(res_id, 0))
		var have := int(available.get(res_id, 0))
		lines.append("%s: %d / %d" % [_format_title(str(res_id)), have, need])
	return "\n".join(lines)


func _format_title(value: String) -> String:
	var cleaned := value.strip_edges().replace("_", " ")
	if cleaned.is_empty():
		return "-"
	var words := cleaned.split(" ", false)
	var result: PackedStringArray = []
	for word in words:
		if not word.is_empty():
			result.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())
	return " ".join(result)


func _fit_height_to_content() -> void:
	var fixed_width := custom_minimum_size.x
	if fixed_width <= 0.0:
		fixed_width = size.x
	var saved_pos := position
	var target_size := get_combined_minimum_size()
	size = Vector2(fixed_width, target_size.y)
	position = saved_pos


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_resources_changed(_base_id: String) -> void:
	if not visible:
		return
	refresh_from_game_session()
