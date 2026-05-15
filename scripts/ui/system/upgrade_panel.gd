## UpgradePanel — buy permanent upgrades for storage, scan drones, and mining ships (Phase 5.5 tiers).
extends PanelContainer

signal close_requested

const BASE_ID: String = "earth"

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
	_refresh_upgrade_button(storage_upgrade_button, &"storage")
	_refresh_upgrade_button(scan_drone_upgrade_button, &"scan_drone")
	_refresh_upgrade_button(mining_ship_upgrade_button, &"mining_ship")


func _refresh_upgrade_button(button: Button, category: StringName) -> void:
	if button == null:
		return
	var is_max := not GameSession.has_next_base_upgrade(BASE_ID, category)
	var can_buy := GameSession.can_buy_next_base_upgrade(BASE_ID, category)
	button.disabled = is_max or not can_buy
	button.text = _upgrade_button_caption(category, is_max)


func _upgrade_button_caption(category: StringName, is_max: bool) -> String:
	if is_max:
		match String(category):
			"storage":
				return "Storage Max Level"
			"scan_drone":
				return "ScanDrone Max Level"
			"mining_ship":
				return "MiningShip Max Level"
			_:
				return "Max Level"
	var nxt := GameSession.get_next_upgrade_definition(BASE_ID, category)
	if nxt != null and not nxt.title.is_empty():
		return nxt.title
	return "Upgrade"


func _on_close_pressed() -> void:
	hover_info_panel.visible = false
	call_deferred("_fit_height_to_content")
	close_requested.emit()


func _on_storage_upgrade_pressed() -> void:
	if GameSession.buy_next_base_upgrade(BASE_ID, &"storage"):
		refresh_from_game_session()


func _on_scan_drone_upgrade_pressed() -> void:
	if GameSession.buy_next_base_upgrade(BASE_ID, &"scan_drone"):
		refresh_from_game_session()


func _on_mining_ship_upgrade_pressed() -> void:
	if GameSession.buy_next_base_upgrade(BASE_ID, &"mining_ship"):
		refresh_from_game_session()


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
	hover_desc_label.text = _build_upgrade_hover_description(cat)
	hover_cost_label.text = ""
	hover_info_panel.visible = true
	call_deferred("_fit_height_to_content")


func _on_button_hover_exited(_button: Button) -> void:
	hover_info_panel.visible = false
	call_deferred("_fit_height_to_content")


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
	if not GameSession.has_next_base_upgrade(BASE_ID, category):
		match String(category):
			"storage":
				return "Storage Max Level"
			"scan_drone":
				return "ScanDrone Max Level"
			"mining_ship":
				return "MiningShip Max Level"
	var nxt := GameSession.get_next_upgrade_definition(BASE_ID, category)
	if nxt != null and not nxt.title.is_empty():
		return nxt.title
	return "Upgrade"


func _storage_level0_units() -> int:
	var z := GameSession.upgrade_catalog.get_definition(&"storage", 0) if GameSession.upgrade_catalog != null else null
	if z != null and z.storage_capacity_units >= 0:
		return z.storage_capacity_units
	return BaseStore.INITIAL_STORAGE_CAPACITY


func _build_upgrade_hover_description(category: StringName) -> String:
	var lines: PackedStringArray = []
	var cur: UpgradeDefinition = GameSession.get_current_upgrade_definition(BASE_ID, category)
	var nxt: UpgradeDefinition = GameSession.get_next_upgrade_definition(BASE_ID, category)

	if not GameSession.has_next_base_upgrade(BASE_ID, category):
		lines.append("Status:")
		lines.append("Max Level reached.")
		lines.append("Effects:")
		match String(category):
			"storage":
				lines.append(
					"Base Storage Capacity: %d%%" % GameSession.get_base_storage_capacity_percent(BASE_ID)
				)
			"scan_drone":
				lines.append("Scan Speed: %d%%" % GameSession.get_scan_drone_scan_speed_percent(BASE_ID))
				lines.append(
					"Mining Support: +%d%% Mining Yield per supporting ScanDrone"
					% GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(BASE_ID)
				)
			"mining_ship":
				lines.append(
					"Cargo Capacity: %d%%" % GameSession.get_mining_ship_cargo_capacity_percent(BASE_ID)
				)
				if cur != null and cur.applies_to_new_jobs_only:
					lines.append("Applies to newly launched mining missions.")
		return "\n".join(lines)

	## Next tier preview
	if nxt == null:
		return ""

	lines.append("Cost:")
	lines.append_array(_format_cost_required_amount_lines(nxt.cost))
	lines.append("Effects:")
	match String(category):
		"storage":
			if cur != null and nxt.storage_capacity_units >= 0 and cur.storage_capacity_units >= 0:
				var u0 := maxi(1, _storage_level0_units())
				var delta_u := nxt.storage_capacity_units - cur.storage_capacity_units
				var d_pct := int(round(float(delta_u) / float(u0) * 100.0))
				lines.append("+%d%% Base Storage Capacity" % d_pct)
		"scan_drone":
			if cur != null and nxt.scan_speed_percent >= 0 and cur.scan_speed_percent >= 0:
				lines.append("+%d%% Scan Speed" % (nxt.scan_speed_percent - cur.scan_speed_percent))
			if (
				cur != null
				and nxt.mining_yield_bonus_per_support_drone_percent >= 0
				and cur.mining_yield_bonus_per_support_drone_percent >= 0
			):
				var d_m := (
					nxt.mining_yield_bonus_per_support_drone_percent
					- cur.mining_yield_bonus_per_support_drone_percent
				)
				if d_m != 0:
					lines.append(
						"+%d%% Mining Yield per supporting ScanDrone" % d_m
					)
		"mining_ship":
			if cur != null and nxt.cargo_capacity_percent >= 0 and cur.cargo_capacity_percent >= 0:
				lines.append("+%d%% Cargo Capacity" % (nxt.cargo_capacity_percent - cur.cargo_capacity_percent))

	if nxt.note.strip_edges() != "":
		lines.append(nxt.note.strip_edges())

	return "\n".join(lines)


func _format_cost_required_amount_lines(cost: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var keys: Array = cost.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return str(a).to_lower() < str(b).to_lower()
	)
	for res_id: Variant in keys:
		var need := int(cost.get(res_id, 0))
		out.append("%s: %d" % [_format_title(str(res_id)), need])
	return out


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
	if hover_info_panel.visible:
		call_deferred("_fit_height_to_content_after_hover_layout")
	else:
		_apply_panel_body_height_fit()


func _fit_height_to_content_after_hover_layout() -> void:
	await get_tree().process_frame
	_apply_panel_body_height_fit()


func _apply_panel_body_height_fit() -> void:
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
