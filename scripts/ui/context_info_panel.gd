extends PanelContainer

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var type_label: Label = $VBoxContainer/TypeLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel

func show_empty() -> void:
	title_label.text = "Kein Objekt ausgewählt"
	type_label.text = "-"
	status_label.text = "-"

func show_body_info(info: Dictionary) -> void:
	title_label.text = str(info.get("display_name", "Unknown"))
	type_label.text = "Typ: %s" % str(info.get("body_type", "unknown"))
	status_label.text = "Status: Scan ausstehend"

func show_poi_info(info: Dictionary) -> void:
	title_label.text = str(info.get("display_name", "Unknown"))
	type_label.text = "Typ: %s" % str(info.get("poi_type", "unknown"))
	status_label.text = "Status: Interaktion verfügbar"
