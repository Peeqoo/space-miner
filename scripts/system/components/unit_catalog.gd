## Loads and indexes `UnitDefinition` resources under `res://data/units/`.
class_name UnitCatalog
extends RefCounted

const UNITS_ROOT := "res://data/units/"

var _by_id: Dictionary = {}
var _loaded: bool = false


func load_all() -> void:
	_by_id.clear()
	_loaded = true
	_scan_dir_recursive(UNITS_ROOT)


func _scan_dir_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		if path == UNITS_ROOT:
			push_error("UnitCatalog: cannot open %s" % UNITS_ROOT)
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
	if res is UnitDefinition:
		_register(res as UnitDefinition)


func _register(def: UnitDefinition) -> void:
	if def == null:
		return
	var uid := def.id.strip_edges()
	if uid.is_empty():
		push_warning("UnitCatalog: skipping definition with empty id (%s)" % str(def))
		return
	if _by_id.has(uid):
		push_warning("UnitCatalog: duplicate id '%s', keeping first" % uid)
		return
	_by_id[uid] = def


func has_definition(unit_id: String) -> bool:
	var uid := unit_id.strip_edges()
	return not uid.is_empty() and _by_id.has(uid)


func get_definition(unit_id: String) -> UnitDefinition:
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return null
	if not _by_id.has(uid):
		if _loaded:
			push_warning("UnitCatalog: unknown unit id '%s'" % uid)
		return null
	return _by_id[uid] as UnitDefinition
