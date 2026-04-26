extends PanelContainer

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var type_label: Label = $VBoxContainer/TypeLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel


func show_empty() -> void:
	title_label.text = "Kein Objekt ausgewählt"
	type_label.text = "-"
	status_label.text = "Wähle einen Planeten oder ein Feld aus."


func show_body_info(info: Dictionary) -> void:
	title_label.text = str(info.get("display_name", "Unknown"))
	type_label.text = "Typ: %s" % str(info.get("body_type", "unknown"))
	status_label.text = _build_full_status_text(info)


func show_poi_info(info: Dictionary) -> void:
	title_label.text = str(info.get("display_name", "Unknown"))
	type_label.text = "Typ: %s" % str(info.get("poi_type", "unknown"))
	status_label.text = _build_full_status_text(info)


func _build_full_status_text(info: Dictionary) -> String:
	var lines: PackedStringArray = []

	var scan_state: String = str(info.get("scan_state", GameSession.SCAN_UNKNOWN))
	lines.append("Scanstatus: %s" % _scan_state_to_text(scan_state))

	var resources_visible: Array = info.get("resources_visible", [])
	var resources_hidden_count: int = int(info.get("resources_hidden_count", 0))

	lines.append("Ressourcen:")

	if scan_state == GameSession.SCAN_UNKNOWN:
		lines.append("- Unknown")
	else:
		for resource_name in resources_visible:
			lines.append("- %s" % str(resource_name))

		if resources_hidden_count > 0:
			lines.append("- Unknown")

	if info.has("status_text"):
		lines.append("")
		lines.append(str(info.get("status_text", "")))

	return "\n".join(lines)

func _scan_state_to_text(scan_state: String) -> String:
	match scan_state:
		GameSession.SCAN_BASIC:
			return "basic"
		GameSession.SCAN_DEEP:
			return "deep"
		GameSession.SCAN_SPECIAL:
			return "special"
		_:
			return "unknown"
