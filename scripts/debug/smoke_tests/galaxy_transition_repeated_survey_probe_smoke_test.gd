## Repeated GalaxyMap roundtrip + SurveyProbe idle visual smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/galaxy_transition_repeated_survey_probe_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const SIGNAL_A: String = "mars"
const SIGNAL_B: String = "venus"
const BASE_ID: String = BaseStore.BASE_EARTH

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _scene_slot: Node = null
var _automation: AutomationController = null
var _spc: SurveyProbeMissionController = null
var _probes_at_start: int = 0


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	_setup_scene_flow()
	call_deferred("_begin")


func _setup_scene_flow() -> void:
	var scene_root := Node.new()
	scene_root.name = "SceneRoot"
	add_child(scene_root)
	_scene_slot = Node.new()
	_scene_slot.name = "CurrentSceneSlot"
	scene_root.add_child(_scene_slot)
	SceneFlow.register_main_root(self)


func _begin() -> void:
	GameSession.reset_for_new_game()
	_set_signal(SIGNAL_A)
	_set_signal(SIGNAL_B)
	SceneFlow.goto_system()
	_wait_frames(120, _run_all)


func _run_all() -> void:
	_automation = _find_automation(_current_scene())
	_spc = _find_survey_probe(_current_scene())
	if _automation == null or _spc == null:
		_fail("Missing AutomationController or SurveyProbeMissionController")
		_finish()
		return

	_automation.ensure_starting_units(BASE_ID)
	_probes_at_start = GameSession.get_available_survey_probe_count(BASE_ID)
	_results["probes_at_start"] = _probes_at_start
	if _probes_at_start < 2:
		_fail("Expected >= 2 survey probes at start, got %d" % _probes_at_start)
		_finish()
		return

	_test_a_idle_visual_first_roundtrip()


func _test_a_idle_visual_first_roundtrip() -> void:
	var idle_before: int = _automation.get_idle_survey_probe_count_at_home(BASE_ID)
	_results["test_a_idle_before"] = idle_before
	if idle_before != _probes_at_start:
		_fail("Test A setup: idle visuals %d != store %d" % [idle_before, _probes_at_start])

	if not _spc.try_start_investigate_signal(SIGNAL_A, BASE_ID):
		_fail("Test A: try_start_investigate_signal(%s) failed" % SIGNAL_A)
		_finish()
		return

	var store_after_a: int = GameSession.get_available_survey_probe_count(BASE_ID)
	_results["test_a_store_after_start_a"] = store_after_a
	if store_after_a != _probes_at_start - 1:
		_fail("Test A: expected store %d after start A" % (_probes_at_start - 1))

	_simulate_galaxy_roundtrip(_after_first_roundtrip)


func _after_first_roundtrip() -> void:
	_refresh_controllers()
	var store: int = GameSession.get_available_survey_probe_count(BASE_ID)
	var idle_home: int = _automation.get_idle_survey_probe_count_at_home(BASE_ID)
	var active_a: bool = _spc.is_investigate_active(SIGNAL_A)
	var known_a: bool = (
		GameSession.get_object_discovery_state(SYSTEM_ID, SIGNAL_A) == GameSession.DISCOVERY_KNOWN
	)
	_results["test_a_store_after_rt1"] = store
	_results["test_a_idle_after_rt1"] = idle_home
	_results["test_a_active_a"] = active_a
	_results["test_a_known_a"] = known_a

	if store != _probes_at_start - 1:
		_fail("Test A: store wrong after roundtrip 1 (got %d)" % store)
	if idle_home != store:
		_fail("Test A: idle visual %d != store %d after roundtrip 1" % [idle_home, store])
	if not active_a and not known_a:
		_fail("Test A: mission A neither active nor completed after roundtrip 1")

	_test_b_second_probe_after_roundtrip()


func _test_b_second_probe_after_roundtrip() -> void:
	if GameSession.get_object_discovery_state(SYSTEM_ID, SIGNAL_A) == GameSession.DISCOVERY_KNOWN:
		_notes.append("Test B: signal A already KNOWN — using B only")

	var store_before_b: int = GameSession.get_available_survey_probe_count(BASE_ID)
	if store_before_b < 1:
		_fail("Test B: no probe available before investigate B")
		_finish()
		return

	if not _spc.try_start_investigate_signal(SIGNAL_B, BASE_ID):
		_fail("Test B: try_start_investigate_signal(%s) failed" % SIGNAL_B)
		_finish()
		return

	var store_after_b: int = GameSession.get_available_survey_probe_count(BASE_ID)
	_results["test_b_store_after_start"] = store_after_b
	if store_after_b != store_before_b - 1:
		_fail("Test B: probe not consumed once (before=%d after=%d)" % [store_before_b, store_after_b])

	_simulate_galaxy_roundtrip(_after_second_roundtrip)


func _after_second_roundtrip() -> void:
	_refresh_controllers()
	var store: int = GameSession.get_available_survey_probe_count(BASE_ID)
	var active_b: bool = _spc.is_investigate_active(SIGNAL_B)
	var known_b: bool = (
		GameSession.get_object_discovery_state(SYSTEM_ID, SIGNAL_B) == GameSession.DISCOVERY_KNOWN
	)
	_results["test_b_store_after_rt2"] = store
	_results["test_b_active_b"] = active_b
	_results["test_b_known_b"] = known_b

	if not active_b and not known_b:
		_fail("Test B: mission B lost after roundtrip 2")
	if store != _results.get("test_b_store_after_start", -1):
		_fail("Test B: store changed unexpectedly after roundtrip 2")

	_test_c_triple_roundtrip_on_active()


func _test_c_triple_roundtrip_on_active() -> void:
	var target: String = SIGNAL_B if _spc.is_investigate_active(SIGNAL_B) else SIGNAL_A
	if not _spc.is_investigate_active(target):
		_notes.append("Test C: no active mission for triple roundtrip — skipped")
		_regression_checks()
		_finish()
		return

	var store_before: int = GameSession.get_available_survey_probe_count(BASE_ID)
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_triple_roundtrip_chain(3, target, store_before, sd_before)


func _triple_roundtrip_chain(remaining: int, target: String, store_before: int, sd_before: int) -> void:
	if remaining <= 0:
		_refresh_controllers()
		var active: bool = _spc.is_investigate_active(target)
		var known: bool = (
			GameSession.get_object_discovery_state(SYSTEM_ID, target) == GameSession.DISCOVERY_KNOWN
		)
		_results["test_c_active_after_3"] = active
		_results["test_c_known_after_3"] = known
		if not active and not known:
			_fail("Test C: mission lost after 3 roundtrips")
		if GameSession.get_available_survey_probe_count(BASE_ID) != store_before:
			_fail("Test C: store count changed across roundtrips")
		if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") < sd_before:
			_fail("Test C: SurveyData decreased unexpectedly")
		_regression_checks()
		_finish()
		return
	_simulate_galaxy_roundtrip(_triple_roundtrip_chain.bind(remaining - 1, target, store_before, sd_before))


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")


func _set_signal(object_id: String) -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, object_id, GameSession.DISCOVERY_SIGNAL)


func _simulate_galaxy_roundtrip(done: Callable) -> void:
	GameSession.capture_system_scene_processes_before_leave()
	SceneFlow.goto_galaxy()
	_wait_frames(20, func() -> void:
		SceneFlow.goto_system()
		_wait_frames(150, done)
	)


func _refresh_controllers() -> void:
	_automation = _find_automation(_current_scene())
	_spc = _find_survey_probe(_current_scene())


func _current_scene() -> Node:
	return SceneFlow.get_current_scene()


func _find_automation(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _find_automation(child)
		if found != null:
			return found
	return null


func _find_survey_probe(node: Node) -> SurveyProbeMissionController:
	if node is SurveyProbeMissionController:
		return node as SurveyProbeMissionController
	for child: Node in node.get_children():
		var found: SurveyProbeMissionController = _find_survey_probe(child)
		if found != null:
			return found
	return null


func _wait_frames(count: int, callback: Callable) -> void:
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[GalaxyRepeatedSpSmoke] FAIL: %s" % message)


func _finish() -> void:
	_print_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _print_report() -> void:
	var overall: String = "PASS"
	if not _failures.is_empty():
		overall = "FAIL"
	elif not _notes.is_empty():
		overall = "PASS WITH NOTES"
	print("")
	print("=== Galaxy Repeated SurveyProbe SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("===========================================")


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
