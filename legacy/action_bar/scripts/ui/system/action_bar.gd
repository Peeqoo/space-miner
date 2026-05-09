extends PanelContainer

signal undock_requested
signal approach_requested
signal dock_requested
signal scan_requested
signal mining_requested
signal stop_mining_requested
signal unload_cargo_requested
signal build_base_requested

var header_label: Label = null
var actions_container: Control = null
var undock_button: Button = null
var approach_button: Button = null
var dock_button: Button = null
var scan_button: Button = null
var mining_button: Button = null
var stop_mining_button: Button = null
var unload_cargo_button: Button = null
var build_base_button: Button = null
var action_status_label: Label = null


func _ready() -> void:
	header_label = get_node_or_null("Margin/Root/HeaderLabel") as Label
	actions_container = _get_actions_container()
	undock_button = _find_action_button("UndockButton")
	approach_button = _find_action_button("ApproachButton")
	dock_button = _find_action_button("DockButton")
	scan_button = _find_action_button("ScanButton")
	mining_button = _find_action_button("MiningButton")
	stop_mining_button = _find_action_button("StopMiningButton")
	unload_cargo_button = _find_action_button("UnloadCargoButton")
	build_base_button = _find_action_button("BuildBaseButton")
	action_status_label = get_node_or_null("Margin/Root/ActionStatusPanel/ActionStatusMargin/ActionStatusLabel") as Label

	if header_label != null:
		header_label.visible = false

	_connect_button_signals()
	set_action_status("Bereit")
	apply_state({
		"is_docked": false,
		"can_undock": false,
		"can_approach": false,
		"can_dock": false,
		"can_scan": false,
		"can_mine": false,
		"mining_active": false,
		"show_unload_cargo": false,
		"can_unload_cargo": false,
		"show_build_base": false,
		"can_build_base": false,
	})


func apply_state(state: Dictionary) -> void:
	var is_docked: bool = bool(state.get("is_docked", false))
	var can_undock: bool = bool(state.get("can_undock", false))
	var can_approach: bool = bool(state.get("can_approach", false))
	var can_dock: bool = bool(state.get("can_dock", false))
	var can_scan: bool = bool(state.get("can_scan", false))
	var can_mine: bool = bool(state.get("can_mine", false))
	var mining_active: bool = bool(state.get("mining_active", false))
	var show_unload_cargo: bool = bool(state.get("show_unload_cargo", false))
	var can_unload_cargo: bool = bool(state.get("can_unload_cargo", false))
	var show_build_base: bool = bool(state.get("show_build_base", false))
	var can_build_base: bool = bool(state.get("can_build_base", false))

	visible = true
	if actions_container != null:
		actions_container.visible = true

	_set_button_state(undock_button, is_docked and can_undock, can_undock)
	_set_button_state(approach_button, can_approach, can_approach)
	_set_button_state(dock_button, can_dock, can_dock)
	_set_button_state(scan_button, can_scan, can_scan)
	_set_button_state(mining_button, can_mine, can_mine)
	_set_button_state(stop_mining_button, mining_active, mining_active)
	_set_button_state(unload_cargo_button, show_unload_cargo, can_unload_cargo)
	_set_button_state(build_base_button, show_build_base, can_build_base)


func set_action_status(text: String) -> void:
	if action_status_label != null:
		action_status_label.text = text


func _get_actions_container() -> Control:
	var row: Control = get_node_or_null("Margin/Root/ActionsRow") as Control
	if row != null:
		return row
	return get_node_or_null("Margin/Root/ActionsGrid") as Control


func _find_action_button(button_name: String) -> Button:
	if actions_container != null:
		var node: Button = actions_container.get_node_or_null(button_name) as Button
		if node != null:
			return node
	return null


func _set_button_state(button: Button, should_show: bool, is_enabled: bool) -> void:
	if button == null:
		return

	button.visible = should_show
	button.disabled = not is_enabled


func _connect_button_signals() -> void:
	_connect_pressed(undock_button, _on_undock_button_pressed)
	_connect_pressed(approach_button, _on_approach_button_pressed)
	_connect_pressed(dock_button, _on_dock_button_pressed)
	_connect_pressed(scan_button, _on_scan_button_pressed)
	_connect_pressed(mining_button, _on_mining_button_pressed)
	_connect_pressed(stop_mining_button, _on_stop_mining_button_pressed)
	_connect_pressed(unload_cargo_button, _on_unload_cargo_button_pressed)
	_connect_pressed(build_base_button, _on_build_base_button_pressed)


func _connect_pressed(button: Button, callable_fn: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(callable_fn):
		button.pressed.connect(callable_fn)


func _on_undock_button_pressed() -> void:
	undock_requested.emit()


func _on_approach_button_pressed() -> void:
	approach_requested.emit()


func _on_dock_button_pressed() -> void:
	dock_requested.emit()


func _on_scan_button_pressed() -> void:
	scan_requested.emit()


func _on_mining_button_pressed() -> void:
	mining_requested.emit()


func _on_stop_mining_button_pressed() -> void:
	stop_mining_requested.emit()


func _on_unload_cargo_button_pressed() -> void:
	unload_cargo_requested.emit()


func _on_build_base_button_pressed() -> void:
	build_base_requested.emit()
