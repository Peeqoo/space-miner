class_name ResourceInfoRow
extends HBoxContainer

## Right column: scan richness (e.g. "42%"), finite store amount ("18 remaining"), or "depleted".
@onready var resource_name_label: Label = $ResourceNameLabel
@onready var resource_value_label: Label = $ResourceValueLabel


func set_row_data(resource_name: String, percent_text: String) -> void:
	resource_name_label.text = resource_name
	resource_value_label.text = percent_text
