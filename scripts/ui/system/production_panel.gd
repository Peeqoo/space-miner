## ProductionPanel — build ScanDrones, MiningShips, and ColonyShip inventory.
## Emits build_scan_drone_requested / build_mining_ship_requested for AutomationController spawning.
extends PanelContainer

signal build_scan_drone_requested
signal build_mining_ship_requested
signal close_requested

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
@onready var hover_info_section: PanelContainer = $Margin/Root/HoverInfoSection
@onready var hover_info_panel: PanelContainer = $Margin/Root/HoverInfoSection/HoverInfoPanel
@onready var hover_title_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverTitleLabel
@onready var hover_desc_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverDescLabel
@onready var hover_cost_label: Label = $Margin/Root/HoverInfoSection/HoverInfoPanel/HoverInfoMargin/HoverInfoRoot/HoverCostLabel


var _hover_desc_placeholder: String = ""
var _hover_cost_header: String = ""


func _ready() -> void:
	visible = false
	hover_info_section.visible = false
	hover_info_panel.visible = true
	_hover_desc_placeholder = hover_desc_label.text.strip_edges()
	_hover_cost_header = hover_cost_label.text.strip_edges()

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
	hover_info_section.visible = false
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
	var production_id := _production_id_from_button(button)
	var production_def: ProductionDefinition = GameSession.get_production_definition(production_id)

	hover_title_label.text = button.text
	hover_desc_label.text = _build_hover_description(production_def)
	hover_cost_label.text = _build_cost_text(production_id)
	hover_info_section.visible = true


func _on_button_hover_exited(_button: Button) -> void:
	hover_info_section.visible = false


func _production_id_from_button(button: Button) -> String:
	match button.name:
		"BuildScanDroneButton":
			return BaseStore.PRODUCTION_SCAN_DRONE
		"BuildMiningShipButton":
			return BaseStore.PRODUCTION_MINING_SHIP
		"BuildColonyShipButton":
			return BaseStore.PRODUCTION_COLONY_SHIP
		_:
			return ""


func _build_hover_description(production_def: ProductionDefinition) -> String:
	var lines := ProductionDefinition.build_hover_description_lines(production_def)
	if lines.is_empty():
		return _hover_desc_placeholder
	return "\n".join(lines)


func _build_cost_text(production_id: String) -> String:
	var resources := GameSession.get_base_resources(_economy_body_id_for_ops())
	var cost := GameSession.get_production_cost(production_id)
	var lines := ProductionDefinition.format_cost_lines_with_availability(cost, resources)
	if lines.is_empty():
		return _hover_cost_header

	var body := "\n".join(lines)
	if _hover_cost_header.is_empty():
		return body
	return "%s\n%s" % [_hover_cost_header, body]


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_resources_changed(_base_id: String) -> void:
	if not visible:
		return
	refresh_from_game_session()
