extends PanelContainer
class_name GalaxyTopBar

@onready var current_system_value_label: Label = $Margin/Row/CurrentSystemValueLabel


func set_current_system_name(system_name: String) -> void:
	var clean_name := system_name.strip_edges()
	current_system_value_label.text = clean_name if clean_name != "" else "-"


func clear_current_system_name() -> void:
	current_system_value_label.text = "-"
