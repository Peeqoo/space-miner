## TopHUD — compact status bar for the active system's primary base (body id = `base_id` in BaseStore).
## Emits hover_requested and hover_cleared signals for the TopHudHoverPanel.
extends PanelContainer

signal hover_requested(kind: String, screen_position: Vector2)
signal hover_cleared

var _primary_base_body_id: String = ""
var _warned_empty_primary_base: bool = false

@onready var storage_label: Label = $Margin/Root/StorageWidget/StorageMargin/StorageRow/StorageLabel
@onready var scan_drone_label: Label = $Margin/Root/ScanDroneWidget/ScanDroneMargin/ScanDroneRow/ScanDroneLabel
@onready var mining_ship_label: Label = $Margin/Root/MiningShipWidget/MiningShipMargin/MiningShipRow/MiningShipLabel
@onready var colony_ship_label: Label = $Margin/Root/ColonyShipWidget/ColonyShipMargin/ColonyShipRow/ColonyShipLabel
@onready var jobs_label: Label = $Margin/Root/JobsWidget/JobsMargin/JobsRow/JobsLabel

@onready var storage_widget: PanelContainer = $Margin/Root/StorageWidget
@onready var scan_drone_widget: PanelContainer = $Margin/Root/ScanDroneWidget
@onready var mining_ship_widget: PanelContainer = $Margin/Root/MiningShipWidget
@onready var colony_ship_widget: PanelContainer = $Margin/Root/ColonyShipWidget
@onready var jobs_widget: PanelContainer = $Margin/Root/JobsWidget


func _ready() -> void:
	_connect_widget_hover(storage_widget, "storage")
	_connect_widget_hover(scan_drone_widget, "scan_drones")
	_connect_widget_hover(mining_ship_widget, "mining_ships")
	_connect_widget_hover(colony_ship_widget, "colony_ships")
	_connect_widget_hover(jobs_widget, "jobs")

	if not GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.connect(_on_resources_changed)


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_resources_changed)


func set_primary_base_body_id(body_id: String) -> void:
	_primary_base_body_id = body_id.strip_edges()
	_warned_empty_primary_base = false
	refresh_from_game_session()


func set_jobs_count(count: int) -> void:
	jobs_label.text = "JBS %d" % maxi(0, count)


func _effective_display_base_id() -> String:
	return _primary_base_body_id.strip_edges()


func refresh_from_game_session() -> void:
	var bid: String = _effective_display_base_id()
	if bid.is_empty():
		if not _warned_empty_primary_base:
			push_warning("TopHUD: Keine primäre base_id — Anzeige 0.")
			_warned_empty_primary_base = true
		storage_label.text = "STR 0/0"
		scan_drone_label.text = "SD 0"
		mining_ship_label.text = "MS 0"
		colony_ship_label.text = "CS 0"
		set_jobs_count(0)
		return

	var used: int = GameSession.get_base_storage_used(bid)
	var cap: int = GameSession.get_base_storage_capacity(bid)
	storage_label.text = "STR %d/%d" % [used, cap]

	var drones: int = GameSession.get_base_drone_count(bid)
	scan_drone_label.text = "SD %d" % drones

	var ships: int = GameSession.get_base_mining_ship_count(bid)
	mining_ship_label.text = "MS %d" % ships

	colony_ship_label.text = "CS %d" % GameSession.get_base_colony_ship_count(bid)


func _connect_widget_hover(widget: Control, kind: String) -> void:
	if widget == null:
		return
	if not widget.mouse_entered.is_connected(_on_widget_entered.bind(kind, widget)):
		widget.mouse_entered.connect(_on_widget_entered.bind(kind, widget))
	if not widget.mouse_exited.is_connected(_on_widget_exited):
		widget.mouse_exited.connect(_on_widget_exited)


func _on_widget_entered(kind: String, widget: Control) -> void:
	hover_requested.emit(kind, _get_hover_anchor_screen_position(widget))


func _on_widget_exited() -> void:
	hover_cleared.emit()


## Returns screen space for hover placement: x = widget center, y = TopHUD bottom + 8.
func _get_hover_anchor_screen_position(widget: Control) -> Vector2:
	var wrect := widget.get_global_rect()
	var hud_rect := get_global_rect()
	var center_x: float = wrect.position.x + wrect.size.x * 0.5
	var top_y: float = hud_rect.position.y + hud_rect.size.y + 8.0
	return Vector2(center_x, top_y)


func _on_resources_changed(emitted_base_id: String) -> void:
	var bid: String = _effective_display_base_id()
	if not bid.is_empty() and emitted_base_id != bid:
		return
	refresh_from_game_session()
