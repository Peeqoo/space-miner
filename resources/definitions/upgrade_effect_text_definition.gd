## Data-driven templates for computed upgrade hover effect lines.
## UI wording lives in `data/ui_text/upgrade_effect_texts.tres`; code uses template keys only.
class_name UpgradeEffectTextDefinition
extends Resource

@export var templates: Dictionary = {}


func get_template(template_key: String) -> String:
	return str(templates.get(template_key, "")).strip_edges()


func format_template(template_key: String, value: Variant) -> String:
	var template := get_template(template_key)
	if template.is_empty():
		push_warning("UpgradeEffectTextDefinition: missing template '%s'" % template_key)
		return ""
	var display_value: String
	if value is int:
		display_value = NumberFormat.format_compact(value)
	elif value is float:
		display_value = NumberFormat.format_compact_float(value)
	else:
		display_value = str(value)
	return template.format({"value": display_value})
