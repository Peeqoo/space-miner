extends HBoxContainer

@onready var resource_name_label: Label = $ResourceNameLabel
@onready var resource_value_label: Label = $ResourceValueLabel


func set_row_data(resource_name: String, amount: int) -> void:
	resource_name_label.text = resource_name
	resource_value_label.text = str(amount)
