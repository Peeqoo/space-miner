## Data-driven resource UI metadata. Loaded from `data/resources/resource_catalog.tres`.
class_name ResourceCatalogDefinition
extends Resource

@export var resources: Array[ResourceDefinition] = []


func get_resource(id: StringName) -> ResourceDefinition:
	if id.is_empty():
		return null

	var id_str := String(id)
	for entry: ResourceDefinition in resources:
		if entry == null:
			continue
		if entry.id == id or String(entry.id) == id_str:
			return entry

	return null


func get_display_name(id: StringName, fallback: String = "") -> String:
	var def := get_resource(id)
	if def != null:
		var name := def.display_name.strip_edges()
		if not name.is_empty():
			return name
	return fallback


func get_short_label(id: StringName, fallback: String = "") -> String:
	var def := get_resource(id)
	if def != null:
		var label := def.short_label.strip_edges()
		if not label.is_empty():
			return label
	return fallback


func get_sort_order(id: StringName, fallback: int = 9999) -> int:
	var def := get_resource(id)
	if def != null:
		return def.sort_order
	return fallback


func get_resource_ids_for_storage() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: ResourceDefinition in resources:
		if entry == null:
			continue
		if not entry.is_storable or not entry.show_in_storage_panel:
			continue
		if entry.id.is_empty():
			continue
		ids.append(entry.id)

	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var order_a := get_sort_order(a)
			var order_b := get_sort_order(b)
			if order_a != order_b:
				return order_a < order_b
			return String(a) < String(b)
	)
	return ids
