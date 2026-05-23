## Loads and indexes `ProductionDefinition` resources under `res://data/production/`.
class_name ProductionCatalog
extends RefCounted

const PRODUCTION_ROOT := "res://data/production/"

var _by_id: Dictionary = {}
var _loaded: bool = false


func load_all() -> void:
	_by_id.clear()
	_loaded = true
	_scan_dir_recursive(PRODUCTION_ROOT)


func _scan_dir_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		if path == PRODUCTION_ROOT:
			push_error("ProductionCatalog: cannot open %s" % PRODUCTION_ROOT)
		return

	for sub: String in d.get_directories():
		if sub.begins_with("."):
			continue
		_scan_dir_recursive(path.path_join(sub))

	for file_name: String in d.get_files():
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			_try_load_file(path.path_join(file_name))


func _try_load_file(path: String) -> void:
	var res: Resource = load(path)
	if res is ProductionDefinition:
		_register(res as ProductionDefinition)


func _register(def: ProductionDefinition) -> void:
	if def == null:
		return
	var pid := def.id.strip_edges()
	if pid.is_empty():
		push_warning("ProductionCatalog: skipping definition with empty id (%s)" % str(def))
		return
	if _by_id.has(pid):
		push_warning("ProductionCatalog: duplicate id '%s', keeping first" % pid)
		return
	_by_id[pid] = def


func has_definition(production_id: String) -> bool:
	var pid := production_id.strip_edges()
	return not pid.is_empty() and _by_id.has(pid)


func get_definition(production_id: String) -> ProductionDefinition:
	var pid := production_id.strip_edges()
	if pid.is_empty():
		return null
	if not _by_id.has(pid):
		if _loaded:
			push_warning("ProductionCatalog: unknown production id '%s'" % pid)
		return null
	return _by_id[pid] as ProductionDefinition


func get_cost(production_id: String) -> Dictionary:
	var def := get_definition(production_id)
	if def == null:
		return {}
	return def.cost.duplicate(true)
