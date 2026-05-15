## Loads and indexes `UpgradeDefinition` resources under `res://data/upgrades/`.
class_name UpgradeCatalog
extends RefCounted

const UPGRADES_ROOT := "res://data/upgrades/"

var _by_category: Dictionary = {}
var _loaded: bool = false


func load_all() -> void:
	_by_category.clear()
	_loaded = true
	_scan_dir_recursive(UPGRADES_ROOT)
	_validate_level_zero()


func _scan_dir_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		if path == UPGRADES_ROOT:
			push_error("UpgradeCatalog: cannot open %s" % UPGRADES_ROOT)
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
	if res is UpgradeDefinition:
		_register(res as UpgradeDefinition)


func _register(def: UpgradeDefinition) -> void:
	if def == null or def.category.is_empty():
		return
	if not _by_category.has(def.category):
		_by_category[def.category] = []
	(_by_category[def.category] as Array).append(def)


func _sort_category_arrays() -> void:
	for cat: Variant in _by_category.keys():
		var arr: Array = _by_category[cat] as Array
		arr.sort_custom(
			func(a: UpgradeDefinition, b: UpgradeDefinition) -> bool:
				return a.level < b.level
		)


func _validate_level_zero() -> void:
	_sort_category_arrays()
	for cat: Variant in _by_category.keys():
		var defs: Array = _by_category[cat] as Array
		var has_zero := false
		for d: Variant in defs:
			if (d as UpgradeDefinition).level == 0:
				has_zero = true
				break
		if not has_zero:
			push_error("UpgradeCatalog: missing level 0 definition for category %s" % str(cat))


func get_definition(category: StringName, level: int) -> UpgradeDefinition:
	if not _by_category.has(category):
		return null
	for d: Variant in _by_category[category] as Array:
		var ud := d as UpgradeDefinition
		if ud.level == level:
			return ud
	return null


func get_current_definition(category: StringName, current_level: int) -> UpgradeDefinition:
	return get_definition(category, current_level)


func get_next_definition(category: StringName, current_level: int) -> UpgradeDefinition:
	return get_definition(category, current_level + 1)


func get_max_level(category: StringName) -> int:
	if not _by_category.has(category):
		return 0
	var max_lv := 0
	for d: Variant in _by_category[category] as Array:
		max_lv = maxi(max_lv, (d as UpgradeDefinition).level)
	return max_lv


func has_next_level(category: StringName, current_level: int) -> bool:
	return get_next_definition(category, current_level) != null
