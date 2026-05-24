## TopHUD — compact status bar for the active system's primary base (body id = `base_id` in BaseStore).
## Emits hover_requested and hover_cleared signals for the TopHudHoverPanel.
extends PanelContainer

signal hover_requested(kind: String, source_control: Control)
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

var _storage_prefix: String = ""
var _scan_drone_prefix: String = ""
var _mining_ship_prefix: String = ""
var _colony_ship_prefix: String = ""
var _jobs_prefix: String = ""


func _ready() -> void:
	_capture_widget_prefixes()

	_connect_widget_hover(storage_widget, "storage")
	_connect_widget_hover(scan_drone_widget, "scan_drones")
	_connect_widget_hover(mining_ship_widget, "mining_ships")
	_connect_widget_hover(colony_ship_widget, "colony_ships")
	_connect_widget_hover(jobs_widget, "jobs")

	if not GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.connect(_on_resources_changed)


func _capture_widget_prefixes() -> void:
	_storage_prefix = _numeric_prefix(storage_label.text)
	_scan_drone_prefix = _numeric_prefix(scan_drone_label.text)
	_mining_ship_prefix = _numeric_prefix(mining_ship_label.text)
	_colony_ship_prefix = _numeric_prefix(colony_ship_label.text)
	_jobs_prefix = _numeric_prefix(jobs_label.text)


func _numeric_prefix(text: String) -> String:
	var cleaned := text.strip_edges()
	for i in range(cleaned.length()):
		var ch: String = cleaned.substr(i, 1)
		if ch.is_valid_int():
			return cleaned.substr(0, i)
		if ch == "-" and i + 1 < cleaned.length() and cleaned.substr(i + 1, 1).is_valid_int():
			return cleaned.substr(0, i)
	return cleaned if cleaned.ends_with(" ") else cleaned + " "


func _exit_tree() -> void:
	if GameSession.base_resources_changed.is_connected(_on_resources_changed):
		GameSession.base_resources_changed.disconnect(_on_resources_changed)


func set_primary_base_body_id(body_id: String) -> void:
	_primary_base_body_id = body_id.strip_edges()
	_warned_empty_primary_base = false
	refresh_from_game_session()


func set_jobs_count(count: int) -> void:
	jobs_label.text = "%s%s" % [_jobs_prefix, NumberFormat.format_compact(maxi(0, count))]


func _effective_display_base_id() -> String:
	return _primary_base_body_id.strip_edges()


func refresh_from_game_session() -> void:
	var bid: String = _effective_display_base_id()
	if bid.is_empty():
		if not _warned_empty_primary_base:
			push_warning("TopHUD: Keine primäre base_id — Anzeige 0.")
			_warned_empty_primary_base = true
		storage_label.text = "%s0/0" % _storage_prefix
		scan_drone_label.text = "%s0" % _scan_drone_prefix
		mining_ship_label.text = "%s0" % _mining_ship_prefix
		colony_ship_label.text = "%s0" % _colony_ship_prefix
		set_jobs_count(0)
		return

	var used: int = GameSession.get_base_storage_used(bid)
	var cap: int = GameSession.get_base_storage_capacity(bid)
	storage_label.text = "%s%s/%s" % [
		_storage_prefix,
		NumberFormat.format_compact(used),
		NumberFormat.format_compact(cap),
	]

	var drones: int = GameSession.get_base_drone_count(bid)
	scan_drone_label.text = "%s%s" % [_scan_drone_prefix, NumberFormat.format_compact(drones)]

	var ships: int = GameSession.get_base_mining_ship_count(bid)
	mining_ship_label.text = "%s%s" % [_mining_ship_prefix, NumberFormat.format_compact(ships)]

	colony_ship_label.text = "%s%s" % [
		_colony_ship_prefix,
		NumberFormat.format_compact(GameSession.get_base_colony_ship_count(bid)),
	]


func _connect_widget_hover(widget: Control, kind: String) -> void:
	if widget == null:
		return
	if not widget.mouse_entered.is_connected(_on_widget_entered.bind(kind, widget)):
		widget.mouse_entered.connect(_on_widget_entered.bind(kind, widget))
	if not widget.mouse_exited.is_connected(_on_widget_exited):
		widget.mouse_exited.connect(_on_widget_exited)


func _on_widget_entered(kind: String, widget: Control) -> void:
	hover_requested.emit(kind, widget)


func _on_widget_exited() -> void:
	hover_cleared.emit()


func _on_resources_changed(emitted_base_id: String) -> void:
	var bid: String = _effective_display_base_id()
	if not bid.is_empty() and emitted_base_id != bid:
		return
	refresh_from_game_session()
