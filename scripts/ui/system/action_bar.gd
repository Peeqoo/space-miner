extends PanelContainer

signal undock_requested
signal approach_requested
signal dock_requested
signal scan_requested
signal mining_requested
signal stop_mining_requested

@onready var header_label: Label = $Margin/Root/HeaderLabel
@onready var undock_button: Button = $Margin/Root/ActionsGrid/UndockButton
@onready var approach_button: Button = $Margin/Root/ActionsGrid/ApproachButton
@onready var dock_button: Button = $Margin/Root/ActionsGrid/DockButton
@onready var scan_button: Button = $Margin/Root/ActionsGrid/ScanButton
@onready var mining_button: Button = $Margin/Root/ActionsGrid/MiningButton
@onready var stop_mining_button: Button = $Margin/Root/ActionsGrid/StopMiningButton
@onready var action_status_label: Label = $Margin/Root/ActionStatusPanel/ActionStatusMargin/ActionStatusLabel


func _ready() -> void:
	header_label.text = "AKTIONEN"
	_connect_button_signals()
	set_action_status("Kein aktives Manöver")
	apply_state({
		"is_docked": false,
		"has_selection": false,
		"can_undock": false,
		"can_approach": false,
		"show_dock": false,
		"can_dock": false,
		"can_scan": false,
		"can_mine": false,
		"mining_active": false,
		"scan_active": false,
	})


func apply_state(state: Dictionary) -> void:
	var is_docked: bool = bool(state.get("is_docked", false))
	var has_selection: bool = bool(state.get("has_selection", false))
	var can_undock: bool = bool(state.get("can_undock", false))
	var can_approach: bool = bool(state.get("can_approach", false))
	var show_dock: bool = bool(state.get("show_dock", false))
	var can_dock: bool = bool(state.get("can_dock", false))
	var can_scan: bool = bool(state.get("can_scan", false))
	var can_mine: bool = bool(state.get("can_mine", false))
	var mining_active: bool = bool(state.get("mining_active", false))
	var scan_active: bool = bool(state.get("scan_active", false))

	undock_button.visible = is_docked
	undock_button.disabled = not can_undock

	approach_button.visible = has_selection and not is_docked and not mining_active and not scan_active
	approach_button.disabled = not can_approach

	dock_button.visible = show_dock and not is_docked and not mining_active and not scan_active
	dock_button.disabled = not can_dock

	scan_button.visible = has_selection and not is_docked and not mining_active and not scan_active
	scan_button.disabled = not can_scan

	mining_button.visible = has_selection and not is_docked and not mining_active and not scan_active
	mining_button.disabled = not can_mine

	stop_mining_button.visible = mining_active
	stop_mining_button.disabled = not mining_active


func set_action_status(text: String) -> void:
	action_status_label.text = text


func _connect_button_signals() -> void:
	if not undock_button.pressed.is_connected(_on_undock_button_pressed):
		undock_button.pressed.connect(_on_undock_button_pressed)
	if not approach_button.pressed.is_connected(_on_approach_button_pressed):
		approach_button.pressed.connect(_on_approach_button_pressed)
	if not dock_button.pressed.is_connected(_on_dock_button_pressed):
		dock_button.pressed.connect(_on_dock_button_pressed)
	if not scan_button.pressed.is_connected(_on_scan_button_pressed):
		scan_button.pressed.connect(_on_scan_button_pressed)
	if not mining_button.pressed.is_connected(_on_mining_button_pressed):
		mining_button.pressed.connect(_on_mining_button_pressed)
	if not stop_mining_button.pressed.is_connected(_on_stop_mining_button_pressed):
		stop_mining_button.pressed.connect(_on_stop_mining_button_pressed)


func _on_undock_button_pressed() -> void:
	emit_signal("undock_requested")


func _on_approach_button_pressed() -> void:
	emit_signal("approach_requested")


func _on_dock_button_pressed() -> void:
	emit_signal("dock_requested")


func _on_scan_button_pressed() -> void:
	emit_signal("scan_requested")


func _on_mining_button_pressed() -> void:
	emit_signal("mining_requested")


func _on_stop_mining_button_pressed() -> void:
	emit_signal("stop_mining_requested")
