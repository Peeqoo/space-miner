## Read-only UI metadata for resource ids (`resource_catalog.tres`). No amounts, costs, or stores.
class_name ResourceCatalogFacade
extends RefCounted

const RESOURCE_CATALOG_PATH := "res://data/resources/resource_catalog.tres"

var resource_catalog: ResourceCatalogDefinition = null


func is_loaded() -> bool:
	return resource_catalog != null


func load_catalog() -> void:
	if not ResourceLoader.exists(RESOURCE_CATALOG_PATH):
		push_warning(
			"ResourceCatalogFacade: resource catalog missing at '%s'" % RESOURCE_CATALOG_PATH
		)
		resource_catalog = null
		return

	var res: Resource = load(RESOURCE_CATALOG_PATH)
	if res is ResourceCatalogDefinition:
		resource_catalog = res as ResourceCatalogDefinition
		return

	push_warning(
		"ResourceCatalogFacade: failed to load ResourceCatalogDefinition from '%s'"
		% RESOURCE_CATALOG_PATH
	)
	resource_catalog = null


func get_resource_definition(resource_id: StringName) -> ResourceDefinition:
	if resource_id.is_empty() or resource_catalog == null:
		return null
	return resource_catalog.get_resource(resource_id)


func get_resource_display_name(resource_id: StringName, fallback: String = "") -> String:
	if resource_id.is_empty():
		return fallback

	if resource_catalog != null:
		var from_catalog := resource_catalog.get_display_name(resource_id, "")
		if not from_catalog.is_empty():
			return from_catalog

	if not fallback.is_empty():
		return fallback

	return ProductionDefinition.format_resource_title(String(resource_id))


func get_resource_short_label(resource_id: StringName, fallback: String = "") -> String:
	if resource_id.is_empty():
		return fallback

	if resource_catalog != null:
		var from_catalog := resource_catalog.get_short_label(resource_id, "")
		if not from_catalog.is_empty():
			return from_catalog

	if not fallback.is_empty():
		return fallback

	var display_name := get_resource_display_name(resource_id, "")
	if not display_name.is_empty():
		return display_name

	return String(resource_id)


func get_resource_sort_order(resource_id: StringName, fallback: int = 9999) -> int:
	if resource_id.is_empty():
		return fallback
	if resource_catalog != null:
		return resource_catalog.get_sort_order(resource_id, fallback)
	return fallback


func get_storage_resource_ids_sorted(resource_ids: Array[StringName]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id_variant: Variant in resource_ids:
		var id: StringName
		if id_variant is StringName:
			id = id_variant as StringName
		else:
			id = StringName(str(id_variant))
		if id.is_empty():
			continue
		ids.append(id)

	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var order_a := get_resource_sort_order(a)
			var order_b := get_resource_sort_order(b)
			if order_a != order_b:
				return order_a < order_b
			return String(a) < String(b)
	)
	return ids
