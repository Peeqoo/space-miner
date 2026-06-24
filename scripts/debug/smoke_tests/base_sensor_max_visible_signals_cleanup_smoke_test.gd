## base_sensor_max_visible_signals cleanup smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/base_sensor_max_visible_signals_cleanup_smoke_runner.tscn
extends Node

const BALANCE_PATH: String = "res://data/balance/v0_1_balance.tres"
const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const BASE_ID: String = BaseStore.BASE_EARTH
const HIDDEN_CANDIDATE_ID: String = "jupiter"

const REMOVED_FIELD_NAME: String = "base_sensor_max_visible_signals"
const NO_HIDDEN_BLOCK_KEY: StringName = (
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NO_HIDDEN
)

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _pulse_ctrl: BaseSensorPulseController = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_no_active_references()
	_load_system_scene()


func _test_a_no_active_references() -> void:
	var default_balance := GameBalanceDefinition.new()
	var tres_balance: GameBalanceDefinition = load(BALANCE_PATH) as GameBalanceDefinition
	if tres_balance == null:
		_fail("Test A: could not load v0_1_balance.tres")
		return

	_results["test_a_default_has_field"] = _resource_has_property(default_balance, REMOVED_FIELD_NAME)
	_results["test_a_tres_has_field"] = _resource_has_property(tres_balance, REMOVED_FIELD_NAME)

	if _resource_has_property(default_balance, REMOVED_FIELD_NAME):
		_fail("Test A: GameBalanceDefinition still exports %s" % REMOVED_FIELD_NAME)
	if _resource_has_property(tres_balance, REMOVED_FIELD_NAME):
		_fail("Test A: v0_1_balance.tres still stores %s" % REMOVED_FIELD_NAME)

	var runtime_hits: int = _grep_runtime_scripts_for_field()
	_results["test_a_runtime_script_hits"] = runtime_hits
	if runtime_hits > 0:
		_fail("Test A: runtime .gd still references %s (%d files)" % [REMOVED_FIELD_NAME, runtime_hits])


func _load_system_scene() -> void:
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_runtime_tests)


func _setup_runtime_tests() -> void:
	_pulse_ctrl = _find_pulse_controller(_system_scene)
	if _pulse_ctrl == null:
		_fail("BaseSensorPulseController missing")
		_finish()
		return

	_restore_survey_data_for_pulse()
	_test_b_pulse_not_capped_by_visible_signals()
	_test_d_no_hidden_candidates_block()
	_test_c_normal_pulse()
	_regression_checks()
	_finish()


func _test_b_pulse_not_capped_by_visible_signals() -> void:
	_ensure_multiple_visible_signals()
	_ensure_hidden_candidate()

	var visible_signal_count: int = _count_discovery_state(GameSession.DISCOVERY_SIGNAL)
	var hidden_count: int = _count_discovery_state(GameSession.DISCOVERY_HIDDEN)
	var gate: Dictionary = _pulse_ctrl.can_start_sensor_pulse(BASE_ID)
	var blocked: String = str(gate.get("blocked_reason", "")).strip_edges()

	_results["test_b_visible_signals"] = visible_signal_count
	_results["test_b_hidden_candidates"] = hidden_count
	_results["test_b_gate_ok"] = bool(gate.get("ok", false))
	_results["test_b_blocked"] = blocked

	if visible_signal_count < 2:
		_notes.append("Test B: fewer than 2 visible SIGNAL objects — partial cap scenario")
	if hidden_count < 1:
		_fail("Test B: expected at least one hidden candidate")
	if not bool(gate.get("ok", false)):
		_fail("Test B: pulse gate blocked with visible signals + hidden candidate (got '%s')" % blocked)
	if blocked.to_lower().contains("max") and blocked.to_lower().contains("signal"):
		_fail("Test B: block text suggests legacy signal cap: '%s'" % blocked)


func _test_c_normal_pulse() -> void:
	_restore_survey_data_for_pulse()
	_ensure_hidden_candidate()

	var balance := GameSession.get_game_balance()
	var expected_cost: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		expected_cost = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))

	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var hidden_before: String = GameSession.get_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID)

	if not _pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_fail("Test C: try_start_sensor_pulse failed")
		return

	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_results["test_c_sd_before"] = sd_before
	_results["test_c_sd_after"] = sd_after
	_results["test_c_expected_cost"] = expected_cost
	_results["test_c_pulse_active"] = _pulse_ctrl.is_pulse_active()

	if sd_before - sd_after != expected_cost:
		_fail("Test C: pulse cost mismatch (expected %d, delta %d)" % [
			expected_cost, sd_before - sd_after,
		])
	if not _pulse_ctrl.is_pulse_active():
		_fail("Test C: pulse should be active after start")
	if hidden_before != GameSession.DISCOVERY_HIDDEN:
		_notes.append("Test C: jupiter was not HIDDEN before pulse — reveal check skipped")


func _test_d_no_hidden_candidates_block() -> void:
	_mark_all_objects_known()

	var gate: Dictionary = _pulse_ctrl.can_start_sensor_pulse(BASE_ID)
	var blocked: String = str(gate.get("blocked_reason", "")).strip_edges()
	var expected: String = DiscoverySignalUiTextDefinition.get_template(NO_HIDDEN_BLOCK_KEY)

	_results["test_d_gate_ok"] = bool(gate.get("ok", false))
	_results["test_d_blocked"] = blocked
	_results["test_d_expected"] = expected

	if bool(gate.get("ok", false)):
		_fail("Test D: expected gate blocked when no hidden candidates")
	if blocked != expected:
		_fail("Test D: expected no_hidden block text, got '%s'" % blocked)
	if blocked.to_lower().contains("max") and blocked.to_lower().contains("visible"):
		_fail("Test D: block must not reference max_visible_signals")


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for entry: Dictionary in resource.get_property_list():
		if str(entry.get("name", "")) == property_name:
			return true
	return false


func _grep_runtime_scripts_for_field() -> int:
	var hits: int = 0
	var roots: PackedStringArray = [
		"res://scripts/autoload",
		"res://scripts/system",
		"res://resources/definitions",
		"res://scripts/ui",
	]
	for root_path: String in roots:
		var files: PackedStringArray = _collect_gd_files(root_path)
		for path: String in files:
			var text: String = FileAccess.get_file_as_string(path)
			if text.contains(REMOVED_FIELD_NAME):
				hits += 1
	return hits


func _collect_gd_files(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			for sub: String in _collect_gd_files(full):
				result.append(sub)
		elif name.ends_with(".gd"):
			result.append(full)
	dir.list_dir_end()
	return result


func _ensure_multiple_visible_signals() -> void:
	for object_id: String in ["mars", "venus"]:
		GameSession.set_object_discovery_state(SYSTEM_ID, object_id, GameSession.DISCOVERY_SIGNAL)


func _ensure_hidden_candidate() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, HIDDEN_CANDIDATE_ID, GameSession.DISCOVERY_HIDDEN)


func _mark_all_objects_known() -> void:
	if _pulse_ctrl == null or _pulse_ctrl.system_definition == null:
		return
	var sys_def: SystemDefinition = _pulse_ctrl.system_definition
	for body_def_variant: Variant in sys_def.bodies:
		var body_def := body_def_variant as SystemBodyDefinition
		if body_def == null:
			continue
		GameSession.set_object_discovery_state(SYSTEM_ID, body_def.id, GameSession.DISCOVERY_KNOWN)
	for poi_def_variant: Variant in sys_def.pois:
		var poi_def := poi_def_variant as PointOfInterestDefinition
		if poi_def == null:
			continue
		GameSession.set_object_discovery_state(SYSTEM_ID, poi_def.id, GameSession.DISCOVERY_KNOWN)


func _count_discovery_state(state: String) -> int:
	if _pulse_ctrl == null or _pulse_ctrl.system_definition == null:
		return 0
	var count: int = 0
	var sys_def: SystemDefinition = _pulse_ctrl.system_definition
	for body_def_variant: Variant in sys_def.bodies:
		var body_def := body_def_variant as SystemBodyDefinition
		if body_def == null:
			continue
		if GameSession.get_object_discovery_state(SYSTEM_ID, body_def.id) == state:
			count += 1
	for poi_def_variant: Variant in sys_def.pois:
		var poi_def := poi_def_variant as PointOfInterestDefinition
		if poi_def == null:
			continue
		if GameSession.get_object_discovery_state(SYSTEM_ID, poi_def.id) == state:
			count += 1
	return count


func _restore_survey_data_for_pulse() -> void:
	var balance := GameSession.get_game_balance()
	var needed: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		needed = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))
	var current: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if current < needed * 2:
		GameSession.add_base_resource(BASE_ID, "SurveyData", needed * 2 - current)


func _find_pulse_controller(root: Node) -> BaseSensorPulseController:
	if root is BaseSensorPulseController:
		return root as BaseSensorPulseController
	for child: Node in root.get_children():
		var found: BaseSensorPulseController = _find_pulse_controller(child)
		if found != null:
			return found
	return null


func _count_tooltip_recursive(node: Node) -> int:
	var count: int = 0
	if node is Control:
		var ctl: Control = node as Control
		if not str(ctl.tooltip_text).is_empty():
			count += 1
	for child: Node in node.get_children():
		count += _count_tooltip_recursive(child)
	return count


func _wait_frames(count: int, callback: Callable) -> void:
	if not callback.is_valid():
		return
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[BaseSensorMaxVisibleSignalsCleanupSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== Base Sensor Max Visible Signals Cleanup Smoke ===")
	print("Status: %s" % status)
	print("Results: %s" % str(_results))
	for note: String in _notes:
		print("NOTE: %s" % note)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


class _FrameWaiter extends Node:
	signal done

	var frames: int = 1

	func _ready() -> void:
		_run()

	func _run() -> void:
		for _i: int in range(maxi(1, frames)):
			await get_tree().process_frame
		done.emit()
		queue_free()
