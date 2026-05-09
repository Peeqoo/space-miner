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
	var visible_resources: Array[Dictionary] = []

	if definition == null:
		return {
			"id": object_id,
			"display_name": visible_name,
			object_type_key: visible_type,
			"scan_state": scan_state,
			"resources_visible": visible_resources,
			"resources_hidden_count": 0,
			"is_scanned": false,
		}

	if scan_state != GameSession.SCAN_UNKNOWN:
		if bool(definition.get("scan_basic_reveal_name")):
			visible_name = display_name

		if bool(definition.get("scan_basic_reveal_type")):
			visible_type = object_type_value

		visible_resources.append_array(_filter_resources_for_scanner(
			scanner_tier,
			GameSession.SCANNER_BASIC,
			_get_layer_entries(definition, "get_basic_scan_resources")
		))
		visible_resources.append_array(_filter_resources_for_scanner(
			scanner_tier,
			GameSession.SCANNER_DEEP,
			_get_layer_entries(definition, "get_deep_scan_resources")
		))
		visible_resources.append_array(_filter_resources_for_scanner(
			scanner_tier,
			GameSession.SCANNER_SPECIAL,
			_get_layer_entries(definition, "get_special_scan_resources")
		))

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

static func _filter_resources_for_scanner(
	scanner_tier: String,
	resource_tier: String,
	resources: Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if not _can_scanner_see_resource_tier(scanner_tier, resource_tier):
		return result

	for entry: Variant in resources:
		var scan_resource := _entry_to_scan_resource(entry)
		if scan_resource.is_empty():
			continue

		result.append(scan_resource)

	return result


static func _can_scanner_see_resource_tier(scanner_tier: String, resource_tier: String) -> bool:
	match scanner_tier:
		GameSession.SCANNER_BASIC:
			return resource_tier == GameSession.SCANNER_BASIC

		GameSession.SCANNER_DEEP:
			return resource_tier == GameSession.SCANNER_BASIC or resource_tier == GameSession.SCANNER_DEEP

		GameSession.SCANNER_SPECIAL:
			return true

		_:
			return false


static func _entry_to_scan_resource(entry: Variant) -> Dictionary:
	if entry == null:
		return {}

	# New correct format:
	# ScannedResourceEntry Resource with:
	# - resource_id: StringName
	# - richness_percent: int
	if entry is Resource:
		var resource_id: Variant = entry.get("resource_id")
		var richness_percent: Variant = entry.get("richness_percent")

		if resource_id == null or String(resource_id).is_empty():
			return {}

		var percent := 0
		if richness_percent != null:
			percent = clampi(int(richness_percent), 0, 100)

		return {
			"id": StringName(resource_id),
			"richness_percent": percent,
			"display_text": "%s %d%%" % [String(resource_id), percent],
		}

	# Compatibility fallback for old PackedStringArray/String data.
	# This should only be temporary while old .tres files are converted.
	var fallback_id := String(entry)
	if fallback_id.is_empty():
		return {}

	return {
		"id": StringName(fallback_id),
		"richness_percent": -1,
		"display_text": "%s --" % fallback_id,
	}


static func _get_layer_entries(definition: Resource, method_name: StringName) -> Array:
	if definition == null or not definition.has_method(method_name):
		return []

	return definition.call(method_name)


static func _count_hidden_resource_slots(scanner_tier: String, definition: Resource) -> int:
	var hidden_count := 0

	match scanner_tier:
		GameSession.SCANNER_BASIC:
			hidden_count += _get_layer_entries(definition, "get_deep_scan_resources").size()
			hidden_count += _get_layer_entries(definition, "get_special_scan_resources").size()
			hidden_count += _get_scan_hidden_slots_after_special(definition)

		GameSession.SCANNER_DEEP:
			hidden_count += _get_layer_entries(definition, "get_special_scan_resources").size()
			hidden_count += _get_scan_hidden_slots_after_special(definition)

		GameSession.SCANNER_SPECIAL:
			hidden_count += _get_scan_hidden_slots_after_special(definition)

	return hidden_count


static func _get_scan_hidden_slots_after_special(definition: Resource) -> int:
	if definition == null:
		return 0

	var value: Variant = definition.get("scan_hidden_slots_after_special")
	if value == null:
		return 0

	return max(0, int(value))
