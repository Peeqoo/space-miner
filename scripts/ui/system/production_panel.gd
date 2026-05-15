## ProductionPanel — build ScanDrones, MiningShips, and ColonyShip inventory.
## Emits build_scan_drone_requested / build_mining_ship_requested for AutomationController spawning.
extends PanelContainer

signal build_scan_drone_requested
signal build_mining_ship_requested
signal close_requested

const BUTTON_INFO: Dictionary = {
	"BuildScanDroneButton": {
		"title": "ScanDrone",
		"desc": "Scans unknown objects. Required before mining.",
	},
	"BuildMiningShipButton": {
		"title": "MiningShip",
		"desc": "Mines resources from scanned objects.",
	},
	"BuildColonyShipButton": {
		"title": "ColonyShip",
		"desc": "Costs resources. Stored for future colony expansion.",
	},
}

## Target BaseStore base id (`SystemBody.body_id`). Set by SystemUI from session primary base.
var _economy_body_id: String = BaseStore.BASE_EARTH


func set_economy_body_id(body_id: String) -> void:
	var bid := body_id.strip_edges()
	if bid.is_empty():
		push_warning("ProductionPanel.set_economy_body_id: empty id ignored")
		return
	_economy_body_id = bid


func _economy_body_id_for_ops() -> String:
	var bid := _economy_body_id.strip_edges()
	return bid if not bid.is_empty() else BaseStore.BASE_EARTH


@onready var build_scan_drone_button: Button = $Margin/Root/ProductionList/BuildScanDroneButton
@onready var build_mining_ship_button: Button = $Margin/Root/ProductionList/BuildMiningShipButton
@onready var build_colony_ship_button: Button = $Margin/Root/ProductionList/BuildColonyShipButton
@onready var close_button: Button = $Margin/Root/HeaderRow/CloseButton
@onready var hover_info_panel: PanelContainer = $Margin/Root/HoverInfoPanel
@onready var hover_title_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverTitleLabel
@onready var hover_desc_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverDescLabel
@onready var hover_cost_label: Label = $Margin/Root/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverCostLabel


func _ready() -> void:
	visible = false
	hover_info_panel.visible = false

	_connect_button(close_button, _on_close_pressed)
	_connect_button(build_scan_drone_button, _on_build_scan_drone_pressed)
	_connect_button(build_mining_ship_button, _on_build_mining_ship_pressed)
	_connect_button(build_colony_ship_button, _on_build_colony_ship_pressed)

	_register_hover(build_scan_drone_button)
	_register_hover(build_mining_ship_button)
	_register_hover(build_colony_ship_button)

	if not GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.connect(_on_resources_changed)

	refresh_from_game_session()


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_resources_changed)


func refresh_from_game_session() -> void:
	var oid := _economy_body_id_for_ops()
	build_scan_drone_button.disabled = not GameSession.can_build_base_drone(oid)
	build_mining_ship_button.disabled = not GameSession.can_build_base_mining_ship(oid)
	build_colony_ship_button.disabled = not GameSession.can_build_base_colony_ship(oid)


func _on_close_pressed() -> void:
	hover_info_panel.visible = false
	call_deferred("_fit_height_to_content")
	close_requested.emit()


func _on_build_scan_drone_pressed() -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	if GameSession.build_base_drone(oid):
		build_scan_drone_requested.emit()
	refresh_from_game_session()


func _on_build_mining_ship_pressed() -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	if GameSession.build_base_mining_ship(oid):
		build_mining_ship_requested.emit()
	refresh_from_game_session()


func _on_build_colony_ship_pressed() -> void:
	var oid := _economy_body_id_for_ops()
	if not GameSession.has_established_base(oid):
		return
	GameSession.build_base_colony_ship(oid)
	refresh_from_game_session()


func _register_hover(button: Button) -> void:
	if button == null:
		return
	if not button.mouse_entered.is_connected(_on_button_hover_entered.bind(button)):
		button.mouse_entered.connect(_on_button_hover_entered.bind(button))
	if not button.mouse_exited.is_connected(_on_button_hover_exited.bind(button)):
		button.mouse_exited.connect(_on_button_hover_exited.bind(button))


func _on_button_hover_entered(button: Button) -> void:
	var info: Dictionary = BUTTON_INFO.get(button.name, {})
	if info.is_empty():
		return

	hover_title_label.text = str(info.get("title", ""))
	hover_desc_label.text = str(info.get("desc", ""))
	hover_cost_label.text = _build_cost_text(button.name)
	hover_info_panel.visible = true
	call_deferred("_fit_height_to_content")


func _on_button_hover_exited(_button: Button) -> void:
	hover_info_panel.visible = false
	call_deferred("_fit_height_to_content")


func _build_cost_text(button_name: String) -> String:
	var resources := GameSession.get_base_resources(_economy_body_id_for_ops())
	match button_name:
		"BuildScanDroneButton":
			return _format_cost_lines(BaseStore.DRONE_COST, resources)
		"BuildMiningShipButton":
			return _format_cost_lines(BaseStore.MINING_SHIP_COST, resources)
		"BuildColonyShipButton":
			return _format_cost_lines(BaseStore.COLONY_SHIP_COST, resources)
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
