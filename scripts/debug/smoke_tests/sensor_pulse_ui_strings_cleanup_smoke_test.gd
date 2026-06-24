## SensorPulse UI strings cleanup smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/sensor_pulse_ui_strings_cleanup_smoke_runner.tscn
extends Node

const UI_TEXT_PATH: String = "res://data/ui_text/discovery_signal_ui_texts.tres"
const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const BASE_ID: String = BaseStore.BASE_EARTH
const HIDDEN_CANDIDATE_ID: String = "jupiter"

const SENSOR_PULSE_KEYS: Array[StringName] = [
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BUTTON_LABEL,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_PROGRESS,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_ACTIVE,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_COOLDOWN,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NO_HIDDEN,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_BASE_MISSING,
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_COST_FORMAT,
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _pulse_ctrl: BaseSensorPulseController = null
var _system_ui: SystemUIController = null
var _object_info: ObjectInfoPanel = null
var _selection: SystemSelectionController = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_resource_load()
	_load_system_scene()


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
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	_selection = _system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	_object_info = _system_ui.object_info_panel if _system_ui != null else null
	if _pulse_ctrl == null or _system_ui == null or _object_info == null:
		_fail("Missing BaseSensorPulseController, SystemUIController, or ObjectInfoPanel")
		_finish()
		return

	_ensure_hidden_candidate()
	_test_b_block_not_enough_survey_data()
	_test_d_block_no_candidates()
	_test_c_block_active_pulse()
	_test_e_progress_template()
	_regression_checks()
	_finish()


func _test_a_resource_load() -> void:
	var res: Resource = load(UI_TEXT_PATH)
	if res is not DiscoverySignalUiTextDefinition:
		_fail("Test A: could not load DiscoverySignalUiTextDefinition from .tres")
		return

	var def := res as DiscoverySignalUiTextDefinition
	var templates: Dictionary = def.templates
	_results["test_a_key_count"] = templates.size()

	for key: StringName in SENSOR_PULSE_KEYS:
		var text: String = str(templates.get(key, "")).strip_edges()
		_results["test_a_%s" % String(key)] = text
		if text.is_empty():
			_fail("Test A: empty template for key '%s'" % String(key))

	var button_label: String = DiscoverySignalUiTextDefinition.get_sensor_pulse_button_label()
	if button_label.is_empty():
		_fail("Test A: get_sensor_pulse_button_label() returned empty")


func _test_b_block_not_enough_survey_data() -> void:
	_ensure_hidden_candidate()
	var sd_amount: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if sd_amount > 0:
		GameSession.remove_base_resource(BASE_ID, "SurveyData", sd_amount)

	var gate: Dictionary = _pulse_ctrl.can_start_sensor_pulse(BASE_ID)
	var blocked: String = str(gate.get("blocked_reason", "")).strip_edges()
	var expected: String = _expected(
		DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA
	)
	_results["test_b_blocked"] = blocked
	_results["test_b_expected"] = expected
	if bool(gate.get("ok", false)):
		_fail("Test B: expected gate blocked with zero SurveyData")
	if blocked != expected:
		_fail("Test B: blocked text mismatch (got '%s')" % blocked)


func _test_c_block_active_pulse() -> void:
	_restore_survey_data_for_pulse()
	_ensure_hidden_candidate()
	if not _pulse_ctrl.try_start_sensor_pulse(BASE_ID):
		_fail("Test C: could not start sensor pulse for active test")
		return

	var gate: Dictionary = _pulse_ctrl.can_start_sensor_pulse(BASE_ID)
	var blocked: String = str(gate.get("blocked_reason", "")).strip_edges()
	var expected: String = _expected(DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_ACTIVE)
	_results["test_c_blocked"] = blocked
	_results["test_c_expected"] = expected
	if bool(gate.get("ok", false)):
		_fail("Test C: expected gate blocked while pulse active")
	if blocked != expected:
		_fail("Test C: blocked text mismatch (got '%s')" % blocked)

	_refresh_earth_object_info()
	var progress_text: String = str(
		_object_info._live_action_cache.get("sensor_pulse_progress_text", "")
	).strip_edges()
	var expected_progress: String = DiscoverySignalUiTextDefinition.format_sensor_pulse_progress(0)
	_results["test_c_progress"] = progress_text
	if progress_text != expected_progress and not progress_text.begins_with("Scanning for signals"):
		_fail("Test C: unexpected progress text '%s'" % progress_text)


func _test_d_block_no_candidates() -> void:
	_mark_all_objects_known()
	var gate: Dictionary = _pulse_ctrl.can_start_sensor_pulse(BASE_ID)
	var blocked: String = str(gate.get("blocked_reason", "")).strip_edges()
	var expected: String = _expected(DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NO_HIDDEN)
	_results["test_d_blocked"] = blocked
	_results["test_d_expected"] = expected
	if bool(gate.get("ok", false)):
		_fail("Test D: expected gate blocked with no hidden candidates")
	if blocked != expected:
		_fail("Test D: blocked text mismatch (got '%s')" % blocked)


func _test_e_progress_template() -> void:
	var formatted: String = DiscoverySignalUiTextDefinition.format_sensor_pulse_progress(42)
	var expected_prefix: String = _expected(
		DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_PROGRESS
	).split("%")[0].strip_edges()
	_results["test_e_formatted"] = formatted
	if formatted.is_empty():
		_fail("Test E: format_sensor_pulse_progress returned empty")
	if not formatted.contains("42"):
		_fail("Test E: progress format missing percent value")
	if not formatted.begins_with(expected_prefix):
		_fail("Test E: progress format prefix mismatch")
	if formatted.to_lower().contains("investigat"):
		_fail("Test E: progress must not use investigate wording")

	var cost_text: String = _pulse_ctrl.get_pulse_cost_display_text()
	var cost_expected_prefix: String = _expected(
		DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_COST_FORMAT
	).split("%")[0].strip_edges()
	_results["test_e_cost_text"] = cost_text
	if cost_text.is_empty():
		_fail("Test E: pulse cost display text empty")
	if not cost_text.begins_with(cost_expected_prefix):
		_fail("Test E: cost format prefix mismatch (got '%s')" % cost_text)


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)

	var balance := GameSession.get_game_balance()
	if balance == null or balance.base_sensor_pulse_cost.is_empty():
		_fail("Regression: base_sensor_pulse_cost missing from balance")
	else:
		_results["pulse_cost"] = balance.base_sensor_pulse_cost.duplicate(true)


func _expected(key: StringName) -> String:
	return DiscoverySignalUiTextDefinition.get_template(key)


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


func _restore_survey_data_for_pulse() -> void:
	var balance := GameSession.get_game_balance()
	var needed: int = 5
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		needed = int(balance.base_sensor_pulse_cost.get("SurveyData", 5))
	var current: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if current < needed:
		GameSession.add_base_resource(BASE_ID, "SurveyData", needed - current)


func _refresh_earth_object_info() -> void:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return
	var earth: Node = spawner.get_spawned_object(BASE_ID)
	if earth != null and _selection != null:
		_selection.select_world_node(earth as Node2D)
	if _system_ui != null:
		_system_ui.update_object_info()


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
	push_error("[SensorPulseUiStringsCleanupSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== SensorPulse UI Strings Cleanup Smoke ===")
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
