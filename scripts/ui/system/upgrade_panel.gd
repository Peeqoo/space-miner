## UpgradePanel — buy permanent upgrades for storage, scan drones, and mining ships (Phase 5.5 tiers).
class_name UpgradePanel
extends PanelContainer

signal close_requested

## Target BaseStore base id (`SystemBody.body_id`). Set by SystemUI from session primary base.
var _economy_body_id: String = BaseStore.BASE_EARTH


func set_economy_body_id(body_id: String) -> void:
	var bid := body_id.strip_edges()
	if bid.is_empty():
		push_warning("UpgradePanel.set_economy_body_id: empty id ignored")
		return
	_economy_body_id = bid


func _economy_body_id_for_ops() -> String:
	var bid := _economy_body_id.strip_edges()
	return bid if not bid.is_empty() else BaseStore.BASE_EARTH


@onready var storage_upgrade_button: Button = $Margin/Root/UpgradeList/StorageUpgradeButton
@onready var scan_drone_upgrade_button: Button = $Margin/Root/UpgradeList/ScanDroneUpgradeButton
@onready var mining_ship_upgrade_button: Button = $Margin/Root/UpgradeList/MiningShipUpgradeButton
@onready var close_button: Button = $Margin/Root/HeaderRow/CloseButton
@onready var hover_info_section: PanelContainer = $Margin/Root/HoverInfoSection
@onready var hover_info_panel: PanelContainer = $Margin/Root/HoverInfoSection/HoverInfoPanel
@onready var hover_title_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverTitleLabel
@onready var hover_desc_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverDescLabel
@onready var hover_cost_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverCostLabel
@onready var hover_effects_section_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverEffectsSectionLabel
@onready var hover_status_section_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverStatusSectionLabel
@onready var hover_max_level_message_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverMaxLevelMessageLabel
@onready var hover_upgrade_fallback_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverUpgradeFallbackLabel
@onready var max_level_caption_storage: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/MaxLevelCaptionStorage
@onready var max_level_caption_scan_drone: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/MaxLevelCaptionScanDrone
@onready var max_level_caption_mining_ship: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/MaxLevelCaptionMiningShip
@onready var max_level_caption_default: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/MaxLevelCaptionDefault

var _upgrade_fallback_caption: String = ""
var _hover_section_label_texts: Dictionary = {}


func _ready() -> void:
	visible = false
	hover_info_section.visible = false
	hover_info_panel.visible = true
	_upgrade_fallback_caption = hover_upgrade_fallback_label.text.strip_edges()
	_hover_section_label_texts = {
		"cost": hover_cost_label.text.strip_edges(),
		"effects": hover_effects_section_label.text.strip_edges(),
		"status": hover_status_section_label.text.strip_edges(),
		"max_level_message": hover_max_level_message_label.text.strip_edges(),
	}

	_connect_button(close_button, _on_close_pressed)
	_connect_button(storage_upgrade_button, _on_storage_upgrade_pressed)
	_connect_button(scan_drone_upgrade_button, _on_scan_drone_upgrade_pressed)
	_connect_button(mining_ship_upgrade_button, _on_mining_ship_upgrade_pressed)

	_register_hover(storage_upgrade_button)
	_register_hover(scan_drone_upgrade_button)
	_register_hover(mining_ship_upgrade_button)

	if not GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.connect(_on_resources_changed)

	if not GameSession.base_upgrades_changed.is_connected(_on_upgrades_changed):
		GameSession.base_upgrades_changed.connect(_on_upgrades_changed)

	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_resources_changed)
	if GameSession.base_upgrades_changed.is_connected(_on_upgrades_changed):
		GameSession.base_upgrades_changed.disconnect(_on_upgrades_changed)


func _on_upgrades_changed(_base_id: String) -> void:
	refresh_from_game_session()


func refresh_from_game_session() -> void:
	_refresh_upgrade_button(storage_upgrade_button, &"storage")
	_refresh_upgrade_button(scan_drone_upgrade_button, &"scan_drone")
	_refresh_upgrade_button(mining_ship_upgrade_button, &"mining_ship")


func _refresh_upgrade_button(button: Button, category: StringName) -> void:
	if button == null:
		return
	var base_id := _economy_body_id_for_ops()
	var is_max := not GameSession.has_next_base_upgrade(base_id, category)
	var gate: Dictionary = GameSession.get_buy_next_base_upgrade_gate(base_id, category)
	var can_buy := bool(gate.get("ok", false))
	button.disabled = is_max or not can_buy
	button.text = _upgrade_button_caption(category, is_max)

func _upgrade_button_caption(category: StringName, is_max: bool) -> String:
	if is_max:
		return _max_level_caption_for_category(category)
	var nxt := GameSession.get_next_upgrade_definition(_economy_body_id_for_ops(), category)
	if nxt != null and not nxt.title.is_empty():
		return nxt.title
	if not _upgrade_fallback_caption.is_empty():
		return _upgrade_fallback_caption
	return max_level_caption_default.text.strip_edges()


func _max_level_caption_for_category(category: StringName) -> String:
	match String(category):
		"storage":
			return max_level_caption_storage.text.strip_edges()
		"scan_drone":
			return max_level_caption_scan_drone.text.strip_edges()
		"mining_ship":
			return max_level_caption_mining_ship.text.strip_edges()
		_:
			return max_level_caption_default.text.strip_edges()


func _on_close_pressed() -> void:
	hover_info_section.visible = false
	close_requested.emit()


func _on_storage_upgrade_pressed() -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	if GameSession.buy_next_base_upgrade(oid, &"storage"):
		AudioManager.play_sfx_optional(&"build_success")
		refresh_from_game_session()
	else:
		AudioManager.play_sfx_optional(&"not_enough_resources")


func _on_scan_drone_upgrade_pressed() -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	if GameSession.buy_next_base_upgrade(oid, &"scan_drone"):
		AudioManager.play_sfx_optional(&"build_success")
		refresh_from_game_session()
	else:
		AudioManager.play_sfx_optional(&"not_enough_resources")


func _on_mining_ship_upgrade_pressed() -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	if GameSession.buy_next_base_upgrade(oid, &"mining_ship"):
		AudioManager.play_sfx_optional(&"build_success")
		refresh_from_game_session()
	else:
		AudioManager.play_sfx_optional(&"not_enough_resources")


func _register_hover(button: Button) -> void:
	if button == null:
		return
	if not button.mouse_entered.is_connected(_on_button_hover_entered.bind(button)):
		button.mouse_entered.connect(_on_button_hover_entered.bind(button))
	if not button.mouse_exited.is_connected(_on_button_hover_exited.bind(button)):
		button.mouse_exited.connect(_on_button_hover_exited.bind(button))


func _on_button_hover_entered(button: Button) -> void:
	var cat := _category_from_button(button)
	if cat.is_empty():
		return
	hover_title_label.text = _hover_title_for_category(cat)
	hover_desc_label.text = _build_upgrade_hover_description(cat, button)
	hover_cost_label.text = ""
	hover_info_section.visible = true


func _on_button_hover_exited(_button: Button) -> void:
	hover_info_section.visible = false


func _category_from_button(button: Button) -> StringName:
	match button.name:
		"StorageUpgradeButton":
			return &"storage"
		"ScanDroneUpgradeButton":
			return &"scan_drone"
		"MiningShipUpgradeButton":
			return &"mining_ship"
		_:
			return &""


func _hover_title_for_category(category: StringName) -> String:
	if not GameSession.has_next_base_upgrade(_economy_body_id_for_ops(), category):
		return _max_level_caption_for_category(category)
	var nxt := GameSession.get_next_upgrade_definition(_economy_body_id_for_ops(), category)
	if nxt != null and not nxt.title.is_empty():
		return nxt.title
	if not _upgrade_fallback_caption.is_empty():
		return _upgrade_fallback_caption
	return max_level_caption_default.text.strip_edges()


func _hover_section_labels() -> Dictionary:
	return _hover_section_label_texts


func _build_upgrade_hover_description(category: StringName, button: Button) -> String:
	var base_id := _economy_body_id_for_ops()
	var cur: UpgradeDefinition = GameSession.get_current_upgrade_definition(base_id, category)
	var nxt: UpgradeDefinition = GameSession.get_next_upgrade_definition(base_id, category)
	var has_next := GameSession.has_next_base_upgrade(base_id, category)
	var lines := UpgradeDefinition.build_panel_hover_lines(cur, nxt, has_next, _hover_section_labels())
	var reason := _blocked_reason_for_category(category)
	if not reason.is_empty():
		lines.append(reason)
	return "\n".join(lines)


func _blocked_reason_for_category(category: StringName) -> String:
	var base_id := _economy_body_id_for_ops()
	if not GameSession.has_next_base_upgrade(base_id, category):
		return ""
	return str(
		GameSession.get_buy_next_base_upgrade_gate(base_id, category).get("blocked_reason", "")
	).strip_edges()


func _connect_button(button: Button, callback: Callable) -> void:
	if button == null:
		return
	AudioManager.bind_ui_button_optional(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_resources_changed(_base_id: String) -> void:
	if not visible:
		return
	refresh_from_game_session()
