## Data-driven production unit build cost (Phase 5.5+). Balancing lives in `data/production/*.tres`.
class_name ProductionDefinition
extends Resource

@export var id: String = ""
@export var unit_key: String = ""
@export var cost: Dictionary = {}
@export var sort_order: int = 0

## Production-specific hover copy (not global UI section labels).
@export_multiline var short_description: String = ""
@export var effect_lines: PackedStringArray = []


static func format_resource_title(resource_id: String) -> String:
	var cleaned := resource_id.strip_edges().replace("_", " ")
	if cleaned.is_empty():
		return "-"
	var words := cleaned.split(" ", false)
	var result: PackedStringArray = []
	for word in words:
		if not word.is_empty():
			result.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())
	return " ".join(result)


static func build_hover_description_lines(production: ProductionDefinition) -> PackedStringArray:
	var lines: PackedStringArray = []
	if production == null:
		return lines

	var desc := production.short_description.strip_edges()
	if not desc.is_empty():
		lines.append(desc)

	for line: String in production.effect_lines:
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			lines.append(trimmed)

	return lines


static func format_cost_lines_with_availability(p_cost: Dictionary, available: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var keys: Array = p_cost.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return str(a).to_lower() < str(b).to_lower()
	)
	for res_id: Variant in keys:
		var need := int(p_cost.get(res_id, 0))
		var have := int(available.get(res_id, 0))
		lines.append("%s: %d / %d" % [format_resource_title(str(res_id)), have, need])
	return lines
