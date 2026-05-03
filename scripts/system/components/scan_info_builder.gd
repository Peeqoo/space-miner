## Builds public scan information dictionaries for system objects.
## Keeps scan presentation logic shared between bodies and POIs.
class_name ScanInfoBuilder
extends RefCounted


# --------------------------------------------------
# Public API
# --------------------------------------------------

static func build_scan_info(
	definition: Resource,
	object_id: String,
	display_name: String,
	object_type_key: String,
	object_type_value: String,
	scan_state: String,
	scanner_tier: String
) -> Dictionary:
	var visible_name := "Unknown"
	var visible_type := "unknown"
	var visible_resources: Array[String] = []

	if scan_state != GameSession.SCAN_UNKNOWN:
		if definition.scan_basic_reveal_name:
			visible_name = display_name

		if definition.scan_basic_reveal_type:
			visible_type = object_type_value

		visible_resources.append_array(_filter_resources_for_scanner(scanner_tier, definition, definition.scan_basic_resources))
		visible_resources.append_array(_filter_resources_for_scanner(scanner_tier, definition, definition.scan_deep_resources))
		visible_resources.append_array(_filter_resources_for_scanner(scanner_tier, definition, definition.scan_special_resources))

	return {
		"id": object_id,
		"display_name": visible_name,
		object_type_key: visible_type,
		"scan_state": scan_state,
		"resources_visible": visible_resources,
		"resources_hidden_count": _count_hidden_resource_slots(scanner_tier, definition),
		"is_scanned": scan_state != GameSession.SCAN_UNKNOWN,
	}


# --------------------------------------------------
# Helpers
# --------------------------------------------------

static func _filter_resources_for_scanner(scanner_tier: String, definition: Resource, resources: PackedStringArray) -> Array[String]:
	var result: Array[String] = []

	for resource_name in resources:
		match scanner_tier:
			GameSession.SCANNER_BASIC:
				if resources == definition.scan_basic_resources:
					result.append(resource_name)

			GameSession.SCANNER_DEEP:
				if resources == definition.scan_basic_resources or resources == definition.scan_deep_resources:
					result.append(resource_name)

			GameSession.SCANNER_SPECIAL:
				result.append(resource_name)

	return result


static func _count_hidden_resource_slots(scanner_tier: String, definition: Resource) -> int:
	var hidden_count := 0

	match scanner_tier:
		GameSession.SCANNER_BASIC:
			hidden_count += definition.scan_deep_resources.size()
			hidden_count += definition.scan_special_resources.size()
			hidden_count += definition.scan_hidden_slots_after_special

		GameSession.SCANNER_DEEP:
			hidden_count += definition.scan_special_resources.size()
			hidden_count += definition.scan_hidden_slots_after_special

		GameSession.SCANNER_SPECIAL:
			hidden_count += definition.scan_hidden_slots_after_special

	return hidden_count
