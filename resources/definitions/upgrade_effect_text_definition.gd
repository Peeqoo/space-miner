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
	return template.format({"value": str(value)})
