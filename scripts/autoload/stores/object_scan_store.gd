class_name ObjectScanStore
extends RefCounted


const SCAN_UNKNOWN := "unknown"
const SCAN_BASIC := "basic"
const SCAN_DEEP := "deep"
const SCAN_SPECIAL := "special"

const DISCOVERY_HIDDEN := "hidden"
const DISCOVERY_SIGNAL := "signal"
const DISCOVERY_KNOWN := "known"

## Legacy fallback for dict/null scan entries without `deposit_amount`.
## `ScannedResourceEntry` resources use export default `deposit_amount` (10000) from `.tres`/class.
const DEPOSIT_AMOUNT_LEGACY_FALLBACK: int = 100


var object_scan_states: Dictionary = {}

## Per-object discovery (`hidden` / `signal` / `known`). Independent of `object_scan_states`.
var object_discovery_states: Dictionary = {}

# {
#   system_id: {
#     object_id: {
#       resource_id: remaining_amount
#     }
#   }
# }
var remaining_resources_by_object: Dictionary = {}


func set_object_scan_state(system_id: String, object_id: String, scan_state: String) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not object_scan_states.has(system_id):
		object_scan_states[system_id] = {}

	var system_scan_state: Dictionary = object_scan_states[system_id]
	system_scan_state[object_id] = scan_state
	object_scan_states[system_id] = system_scan_state


func get_object_scan_state(system_id: String, object_id: String) -> String:
	if system_id.is_empty() or object_id.is_empty():
		return SCAN_UNKNOWN

	var system_scan_state: Variant = object_scan_states.get(system_id, {})
	if system_scan_state is Dictionary:
		return str((system_scan_state as Dictionary).get(object_id, SCAN_UNKNOWN))

	return SCAN_UNKNOWN


func normalize_discovery_state(discovery_state: String) -> String:
	var normalized := discovery_state.strip_edges().to_lower()

	match normalized:
		DISCOVERY_HIDDEN, DISCOVERY_SIGNAL, DISCOVERY_KNOWN:
			return normalized
		_:
			if not discovery_state.is_empty():
				push_warning(
					"ObjectScanStore: unknown discovery_state '%s', using '%s'."
					% [discovery_state, DISCOVERY_KNOWN]
				)
			return DISCOVERY_KNOWN


func set_object_discovery_state(system_id: String, object_id: String, discovery_state: String) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	var normalized := normalize_discovery_state(discovery_state)

	if not object_discovery_states.has(system_id):
		object_discovery_states[system_id] = {}

	var system_discovery: Dictionary = object_discovery_states[system_id]
	system_discovery[object_id] = normalized
	object_discovery_states[system_id] = system_discovery


func get_object_discovery_state(system_id: String, object_id: String) -> String:
	if system_id.is_empty() or object_id.is_empty():
		return DISCOVERY_KNOWN

	var system_discovery: Variant = object_discovery_states.get(system_id, {})

	if system_discovery is Dictionary:
		var entry: Variant = (system_discovery as Dictionary).get(object_id, null)

		if entry == null:
			return DISCOVERY_KNOWN

		return normalize_discovery_state(str(entry))

	return DISCOVERY_KNOWN


func is_object_hidden(system_id: String, object_id: String) -> bool:
	return get_object_discovery_state(system_id, object_id) == DISCOVERY_HIDDEN


func is_object_signal(system_id: String, object_id: String) -> bool:
	return get_object_discovery_state(system_id, object_id) == DISCOVERY_SIGNAL


func is_object_known(system_id: String, object_id: String) -> bool:
	return get_object_discovery_state(system_id, object_id) == DISCOVERY_KNOWN


func has_explicit_object_discovery_state(system_id: String, object_id: String) -> bool:
	if system_id.is_empty() or object_id.is_empty():
		return false

	var system_discovery: Variant = object_discovery_states.get(system_id, {})

	if system_discovery is Dictionary:
		return (system_discovery as Dictionary).has(object_id)

	return false


func ensure_object_resources_initialized(
	system_id: String,
	object_id: String,
	visible_resources: Array
) -> void:
	if system_id.is_empty() or object_id.is_empty():
		return

	if not remaining_resources_by_object.has(system_id):
		remaining_resources_by_object[system_id] = {}

	var system_resources: Dictionary = remaining_resources_by_object[system_id]

	var object_resources: Dictionary = {}

	if system_resources.has(object_id):
		var existing_variant: Variant = system_resources.get(object_id, {})
		if existing_variant is Dictionary:
			object_resources = (existing_variant as Dictionary).duplicate(true)
		else:
			object_resources = {}

	for entry: Variant in visible_resources:
		var resource_id: String = _get_resource_id_from_entry(entry)

		if resource_id.is_empty():
			continue

		if object_resources.has(resource_id):
			continue

		var amount_init: int = _get_deposit_amount_from_entry(entry, system_id, object_id, resource_id)
		object_resources[resource_id] = amount_init

	system_resources[object_id] = object_resources
	remaining_resources_by_object[system_id] = system_resources


func has_object_resources(system_id: String, object_id: String) -> bool:
	if system_id.is_empty() or object_id.is_empty():
		return false

	var system_resources: Variant = remaining_resources_by_object.get(system_id, {})
	if not system_resources is Dictionary:
		return false

	return (system_resources as Dictionary).has(object_id)


func get_object_remaining_resources(system_id: String, object_id: String) -> Dictionary:
	if system_id.is_empty() or object_id.is_empty():
		return {}

	var system_resources: Variant = remaining_resources_by_object.get(system_id, {})
	if not system_resources is Dictionary:
		return {}

	var object_resources: Variant = (system_resources as Dictionary).get(object_id, {})
	if object_resources is Dictionary:
		return (object_resources as Dictionary).duplicate(true)

	return {}


func get_remaining_resource_amount(system_id: String, object_id: String, resource_id: String) -> int:
	if system_id.is_empty() or object_id.is_empty() or resource_id.is_empty():
		return 0

	var object_resources: Dictionary = get_object_remaining_resources(system_id, object_id)
	return max(0, int(object_resources.get(resource_id, 0)))


func extract_resource_amount(
	system_id: String,
	object_id: String,
	resource_id: String,
	requested_amount: int
) -> int:
	if system_id.is_empty() or object_id.is_empty() or resource_id.is_empty():
		return 0

	if requested_amount <= 0:
		return 0

	var system_resources: Variant = remaining_resources_by_object.get(system_id, {})
	if not system_resources is Dictionary:
		return 0

	var object_resources: Variant = (system_resources as Dictionary).get(object_id, {})
	if not object_resources is Dictionary:
		return 0

	var resources_dict: Dictionary = object_resources as Dictionary
	var remaining: int = max(0, int(resources_dict.get(resource_id, 0)))
	var extracted: int = mini(requested_amount, remaining)

	if extracted <= 0:
		return 0

	resources_dict[resource_id] = remaining - extracted

	var system_dict: Dictionary = system_resources as Dictionary
	system_dict[object_id] = resources_dict
	remaining_resources_by_object[system_id] = system_dict

	return extracted


func is_resource_depleted(system_id: String, object_id: String, resource_id: String) -> bool:
	return get_remaining_resource_amount(system_id, object_id, resource_id) <= 0


func has_any_remaining_among(system_id: String, object_id: String, resource_ids: Array) -> bool:
	if system_id.is_empty() or object_id.is_empty():
		return false

	for vid: Variant in resource_ids:
		var rid: String = str(vid)

		if rid.is_empty():
			continue

		if get_remaining_resource_amount(system_id, object_id, rid) > 0:
			return true

	return false


func is_object_depleted(system_id: String, object_id: String) -> bool:
	var object_resources: Dictionary = get_object_remaining_resources(system_id, object_id)

	if object_resources.is_empty():
		return true

	for amount_variant: Variant in object_resources.values():
		if int(amount_variant) > 0:
			return false

	return true


func _get_resource_id_from_entry(entry: Variant) -> String:
	if entry == null:
		return ""

	if entry is Dictionary:
		var dict: Dictionary = entry as Dictionary

		if dict.has("id"):
			return String(dict.get("id", ""))

		if dict.has("resource_id"):
			return String(dict.get("resource_id", ""))

		if dict.has("name"):
			return str(dict.get("name", ""))

		return ""

	if entry is Resource:
		var resource_id: Variant = (entry as Resource).get("resource_id")
		if resource_id != null:
			return String(resource_id)

	return str(entry)


func _get_deposit_amount_from_entry(
	entry: Variant,
	system_id: String = "",
	object_id: String = "",
	resource_id: String = "",
) -> int:
	if entry == null:
		return _legacy_deposit_fallback(system_id, object_id, resource_id)

	if entry is Dictionary:
		var dict: Dictionary = entry as Dictionary

		if dict.has("deposit_amount"):
			return max(0, int(dict.get("deposit_amount", DEPOSIT_AMOUNT_LEGACY_FALLBACK)))

		if dict.has("amount"):
			return max(0, int(dict.get("amount", DEPOSIT_AMOUNT_LEGACY_FALLBACK)))

		return _legacy_deposit_fallback(system_id, object_id, resource_id)

	if entry is Resource:
		var deposit_amount: Variant = (entry as Resource).get("deposit_amount")
		if deposit_amount != null:
			return max(0, int(deposit_amount))

		var amount: Variant = (entry as Resource).get("amount")
		if amount != null:
			return max(0, int(amount))

		return _legacy_deposit_fallback(system_id, object_id, resource_id)

	return _legacy_deposit_fallback(system_id, object_id, resource_id)


func _legacy_deposit_fallback(system_id: String, object_id: String, resource_id: String) -> int:
	var oid := object_id.strip_edges()
	var rid := resource_id.strip_edges()
	if oid.is_empty() and rid.is_empty():
		push_warning(
			"Resource amount missing for unknown object/resource, using legacy fallback %d"
			% DEPOSIT_AMOUNT_LEGACY_FALLBACK
		)
	else:
		push_warning(
			"Resource amount missing for %s/%s, using legacy fallback %d"
			% [oid, rid, DEPOSIT_AMOUNT_LEGACY_FALLBACK]
		)
	return DEPOSIT_AMOUNT_LEGACY_FALLBACK


func to_save_data() -> Dictionary:
	return {
		"object_scan_states": object_scan_states.duplicate(true),
		"object_discovery_states": object_discovery_states.duplicate(true),
		"remaining_resources_by_object": remaining_resources_by_object.duplicate(true),
	}


func apply_save_data(data: Dictionary) -> void:
	object_scan_states = {}
	object_discovery_states = {}
	remaining_resources_by_object = {}
	if data.is_empty():
		return
	var scans_variant: Variant = data.get("object_scan_states", {})
	if scans_variant is Dictionary:
		object_scan_states = (scans_variant as Dictionary).duplicate(true)
	var discovery_variant: Variant = data.get("object_discovery_states", {})
	if discovery_variant is Dictionary:
		object_discovery_states = (discovery_variant as Dictionary).duplicate(true)
	var remaining_variant: Variant = data.get("remaining_resources_by_object", {})
	if remaining_variant is Dictionary:
		remaining_resources_by_object = (remaining_variant as Dictionary).duplicate(true)
