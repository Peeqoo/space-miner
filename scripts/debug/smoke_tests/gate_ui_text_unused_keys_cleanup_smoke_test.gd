## Gate UI text unused-keys cleanup smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/gate_ui_text_unused_keys_cleanup_smoke_runner.tscn
extends Node

const GATE_TEXTS_PATH: String = "res://data/ui_text/gate_ui_texts.tres"

## Keys emitted by runtime gates or wired player-facing UI (must have non-empty copy).
const RUNTIME_GATE_KEYS: Array[StringName] = [
	GateUiTextDefinition.KEY_SCAN_NOT_DISCOVERED,
	GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS,
	GateUiTextDefinition.KEY_SCAN_NO_DRONE,
	GateUiTextDefinition.KEY_SCAN_NO_LAYER,
	GateUiTextDefinition.KEY_MINE_NOT_DISCOVERED,
	GateUiTextDefinition.KEY_MINE_NOT_SCANNED,
	GateUiTextDefinition.KEY_MINE_NO_RESOURCES,
	GateUiTextDefinition.KEY_MINE_DEPLETED,
	GateUiTextDefinition.KEY_MINE_NO_SHIP,
	GateUiTextDefinition.KEY_BUILD_NOT_ENOUGH_RESOURCES,
	GateUiTextDefinition.KEY_UPGRADE_NOT_ENOUGH_RESOURCES,
	GateUiTextDefinition.KEY_STORAGE_FULL,
	GateUiTextDefinition.KEY_COLONY_NO_SHIP,
	GateUiTextDefinition.KEY_COLONY_NOT_ENOUGH_RESOURCES,
	GateUiTextDefinition.KEY_COLONY_SHIPYARD_REQUIRED,
	GateUiTextDefinition.KEY_COLONY_PROTOCOL_REQUIRED,
	GateUiTextDefinition.KEY_COLONY_DEEP_SCAN_REQUIRED,
	GateUiTextDefinition.KEY_COLONY_ICE_SOURCE_REQUIRED,
	GateUiTextDefinition.KEY_COLONY_FULLY_SCAN_THREE,
]

## Prepared / legacy keys — no runtime gate emission; must stay documented (audit + comments).
const RESERVED_KEYS: Dictionary = {
	GateUiTextDefinition.KEY_MINE_STORAGE_FULL: "reserved_v0_1_mine_uses_storage_full",
	GateUiTextDefinition.KEY_UPGRADE_MAX_LEVEL: "reserved_v0_1_max_level_uses_key_none",
	GateUiTextDefinition.KEY_BUILD_SCAN_DRONE_LIMIT: "deprecated_step_2a_unlimited_production",
	GateUiTextDefinition.KEY_BUILD_MINING_SHIP_LIMIT: "deprecated_step_2a_unlimited_production",
}

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_definition_loads_and_runtime_texts()
	_test_b_code_keys_have_copy()
	_test_c_no_undocumented_unused_keys()
	_regression_checks()
	_finish()


func _test_a_definition_loads_and_runtime_texts() -> void:
	var global_def: GateUiTextDefinition = GateUiTextDefinition.get_global()
	_results["test_a_global_loaded"] = global_def != null
	if global_def == null:
		_fail("Test A: GateUiTextDefinition global not loaded after GameSession.reset")
		return

	var res: Resource = load(GATE_TEXTS_PATH)
	_results["test_a_tres_loaded"] = res is GateUiTextDefinition
	if not (res is GateUiTextDefinition):
		_fail("Test A: failed to load %s" % GATE_TEXTS_PATH)
		return

	var empty_runtime: PackedStringArray = []
	for key: StringName in RUNTIME_GATE_KEYS:
		var text: String = GateUiTextDefinition.get_text(key).strip_edges()
		if text.is_empty():
			empty_runtime.append(String(key))

	_results["test_a_runtime_key_count"] = RUNTIME_GATE_KEYS.size()
	_results["test_a_empty_runtime_keys"] = empty_runtime
	if not empty_runtime.is_empty():
		_fail("Test A: runtime gate keys with empty text: %s" % str(empty_runtime))


func _test_b_code_keys_have_copy() -> void:
	var missing: PackedStringArray = []
	for key: StringName in RUNTIME_GATE_KEYS:
		if not _key_has_tres_or_fallback(key):
			missing.append(String(key))

	for key: StringName in RESERVED_KEYS.keys():
		if key == GateUiTextDefinition.KEY_BUILD_SCAN_DRONE_LIMIT:
			continue
		if key == GateUiTextDefinition.KEY_BUILD_MINING_SHIP_LIMIT:
			continue
		if not _key_has_tres_or_fallback(key):
			missing.append(String(key))

	_results["test_b_missing_copy_keys"] = missing
	if not missing.is_empty():
		_fail("Test B: keys without .tres entry or built-in fallback: %s" % str(missing))


func _test_c_no_undocumented_unused_keys() -> void:
	var global_def: GateUiTextDefinition = GateUiTextDefinition.get_global()
	if global_def == null:
		return

	var runtime_set: Dictionary = {}
	for key: StringName in RUNTIME_GATE_KEYS:
		runtime_set[key] = true

	var undocumented_tres: PackedStringArray = []
	for raw_key: Variant in global_def.templates.keys():
		var key: StringName = StringName(str(raw_key))
		if runtime_set.has(key):
			continue
		if RESERVED_KEYS.has(key):
			continue
		undocumented_tres.append(String(key))

	_results["test_c_tres_key_count"] = global_def.templates.size()
	_results["test_c_undocumented_tres_keys"] = undocumented_tres
	if not undocumented_tres.is_empty():
		_fail(
			"Test C: .tres keys without runtime use or RESERVED registry: %s"
			% str(undocumented_tres)
		)

	var all_definition_keys: Array[StringName] = _all_definition_key_constants()
	var undocumented_def: PackedStringArray = []
	for key: StringName in all_definition_keys:
		if key == GateUiTextDefinition.KEY_NONE:
			continue
		if runtime_set.has(key):
			continue
		if RESERVED_KEYS.has(key):
			continue
		undocumented_def.append(String(key))

	_results["test_c_definition_key_count"] = all_definition_keys.size()
	_results["test_c_undocumented_definition_keys"] = undocumented_def
	if not undocumented_def.is_empty():
		_fail(
			"Test C: definition KEY_* without runtime use or RESERVED registry: %s"
			% str(undocumented_def)
		)


func _key_has_tres_or_fallback(key: StringName) -> bool:
	var global_def: GateUiTextDefinition = GateUiTextDefinition.get_global()
	if global_def != null:
		var from_tres: String = str(global_def.templates.get(key, "")).strip_edges()
		if not from_tres.is_empty():
			return true
	var from_fallback: String = GateUiTextDefinition.get_text(key).strip_edges()
	return not from_fallback.is_empty()


func _all_definition_key_constants() -> Array[StringName]:
	return [
		GateUiTextDefinition.KEY_NONE,
		GateUiTextDefinition.KEY_SCAN_NOT_DISCOVERED,
		GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS,
		GateUiTextDefinition.KEY_SCAN_NO_DRONE,
		GateUiTextDefinition.KEY_SCAN_NO_LAYER,
		GateUiTextDefinition.KEY_MINE_NOT_DISCOVERED,
		GateUiTextDefinition.KEY_MINE_NOT_SCANNED,
		GateUiTextDefinition.KEY_MINE_NO_RESOURCES,
		GateUiTextDefinition.KEY_MINE_DEPLETED,
		GateUiTextDefinition.KEY_MINE_NO_SHIP,
		GateUiTextDefinition.KEY_MINE_STORAGE_FULL,
		GateUiTextDefinition.KEY_BUILD_NOT_ENOUGH_RESOURCES,
		GateUiTextDefinition.KEY_BUILD_SCAN_DRONE_LIMIT,
		GateUiTextDefinition.KEY_BUILD_MINING_SHIP_LIMIT,
		GateUiTextDefinition.KEY_UPGRADE_NOT_ENOUGH_RESOURCES,
		GateUiTextDefinition.KEY_UPGRADE_MAX_LEVEL,
		GateUiTextDefinition.KEY_STORAGE_FULL,
		GateUiTextDefinition.KEY_COLONY_NO_SHIP,
		GateUiTextDefinition.KEY_COLONY_NOT_ENOUGH_RESOURCES,
		GateUiTextDefinition.KEY_COLONY_SHIPYARD_REQUIRED,
		GateUiTextDefinition.KEY_COLONY_PROTOCOL_REQUIRED,
		GateUiTextDefinition.KEY_COLONY_DEEP_SCAN_REQUIRED,
		GateUiTextDefinition.KEY_COLONY_ICE_SOURCE_REQUIRED,
		GateUiTextDefinition.KEY_COLONY_FULLY_SCAN_THREE,
	]


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _count_tooltip_recursive(node: Node) -> int:
	var count: int = 0
	if node is Control:
		var ctl: Control = node as Control
		if not str(ctl.tooltip_text).is_empty():
			count += 1
	for child: Node in node.get_children():
		count += _count_tooltip_recursive(child)
	return count


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[GateUiTextUnusedKeysCleanupSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== Gate UI Text Unused Keys Cleanup Smoke ===")
	print("Status: %s" % status)
	print("Results: %s" % str(_results))
	for note: String in _notes:
		print("NOTE: %s" % note)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
