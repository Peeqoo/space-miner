## SharedScanJob Step 6 — UI Assign ScanDrone smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_job_step_6_ui_assign_scan_drone_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const TEST_SAVE_SLOT: int = 3

const SCAN_BUTTON_BASIC: String = "Basic Scan"
const SCAN_BUTTON_ASSIGN: String = "Assign ScanDrone"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _scan_count_label: Label = null
var _scan_button: Button = null

var _sd_at_scan_start: int = 0
var _scan_state_at_start: String = ""


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	GameSession.reset_for_new_game()
	_setup_mars_scannable()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_and_run)


func _setup_and_run() -> void:
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	_selection = _system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	_automation = _find_automation_controller(_system_scene)
	_object_info = _system_ui.object_info_panel if _system_ui != null else null
	if _system_ui == null or _selection == null or _automation == null or _object_info == null:
		_fail("Missing controllers or ObjectInfoPanel")
		_finish()
		return
	_scan_count_label = _object_info.get_node_or_null(
		"Margin/Root/OrbitStatusSection/ScanDroneCountLabel"
	) as Label
	_scan_button = _object_info.get_node_or_null(
		"Margin/Root/GridContainer/ScanWithDroneButton"
	) as Button
	if _scan_count_label == null or _scan_button == null:
		_fail("ScanDroneCountLabel or ScanWithDroneButton missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_sd_at_scan_start = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_at_start = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_test_a_baseline()
	_test_b_assign_second()
	_test_c_no_idle()
	_test_f_galaxy_with_two_assigned()


func _test_a_baseline() -> void:
	_refresh_mars_selection()
	var assigned: int = _read_scan_assigned_count()
	_results["test_a_assigned"] = assigned
	_results["test_a_button"] = _scan_button.text
	if assigned != 0:
		_fail("Test A: expected assigned count 0, got %d" % assigned)
	if _scan_button.text != SCAN_BUTTON_BASIC:
		_fail("Test A: expected button '%s', got '%s'" % [SCAN_BUTTON_BASIC, _scan_button.text])
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if not _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test A: launch_scan_drone did not create SharedScanJob")
	_refresh_mars_selection()
	var assigned_after_launch: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_a_after_launch_assigned"] = assigned_after_launch
	if assigned_after_launch < 1:
		_fail("Test A: expected assigned count >= 1 after launch")
	_refresh_mars_selection()
	if _has_idle_scan_drone() and _scan_button.text != SCAN_BUTTON_ASSIGN:
		_fail("Test A: expected Assign button after launch when idle drone exists")
	_results["test_a_after_launch_button"] = _scan_button.text


func _test_b_assign_second() -> void:
	_grant_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
		_fail("Test B: assign_scan_drone_to_shared_job failed")
		return
	_refresh_mars_selection()
	var assigned: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_b_assigned"] = assigned
	_results["test_b_button"] = _scan_button.text
	if assigned != 2:
		_fail("Test B: expected assigned count 2, got %d" % assigned)
	if _has_idle_scan_drone() and _scan_button.text != SCAN_BUTTON_ASSIGN:
		_fail("Test B: expected button '%s' when idle drone remains, got '%s'" % [
			SCAN_BUTTON_ASSIGN, _scan_button.text,
		])
	var sd_now: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	if sd_now != _sd_at_scan_start:
		_fail("Test B: SurveyData changed on assign (got %d vs %d)" % [sd_now, _sd_at_scan_start])
	if GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID) != _scan_state_at_start:
		_fail("Test B: scan state changed on assign")


func _test_c_no_idle() -> void:
	while _has_idle_scan_drone():
		if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
			break
	_refresh_mars_selection()
	_results["test_c_button_disabled"] = _scan_button.disabled
	_results["test_c_assigned"] = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	if _has_idle_scan_drone():
		_notes.append("Test C: idle drone still available after assign loop")
	if not _scan_button.disabled:
		_fail("Test C: scan button should be disabled when no idle ScanDrone")


func _poll_completion_two_assigned(frames_left: int = 4000) -> void:
	var scene: Node = SceneFlow.get_current_scene()
	if scene == null:
		scene = _system_scene
	_automation = _find_automation_controller(scene)
	if _automation == null:
		_fail("Completion poll: AutomationController missing")
		_regression_checks()
		_finish()
		return
	var active_jobs: int = _automation.get_active_shared_scan_job_count()
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	if active_jobs == 0 and support_n >= 1:
		_test_d_completion_once()
		return
	if frames_left <= 0:
		_notes.append("Test D: completion poll timed out")
		_test_d_completion_once()
		return
	_wait_frames(30, _poll_completion_two_assigned.bind(frames_left - 30))


func _test_d_completion_once() -> void:
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_results["test_d_sd_after"] = sd_after
	_results["test_d_scan_after"] = scan_after
	_results["test_d_active_jobs"] = _automation.get_active_shared_scan_job_count()
	if sd_after <= _sd_at_scan_start:
		_fail("Test D: expected SurveyData reward once")
	if scan_after == _scan_state_at_start:
		_fail("Test D: scan state unchanged after completion")
	if _automation.get_active_shared_scan_job_count() != 0:
		_fail("Test D: stale active SharedScanJob")
	var support_n: int = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	_results["test_d_support"] = support_n
	if support_n < 1:
		_notes.append("Test D: support count < 1 after completion with 2 drones")
	_test_e_no_false_already_in_progress()
	_regression_checks()
	_finish()


func _test_e_no_false_already_in_progress() -> void:
	if _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test E: active SharedScanJob should be cleared after completion")
	var gate: Dictionary = GameSession.can_scan_object(
		SYSTEM_ID,
		TARGET_OBJECT_ID,
		BASE_ID,
		_has_idle_scan_drone(),
		_automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID),
	)
	var gate_key: String = str(gate.get("blocked_reason_key", ""))
	_results["test_e_gate_key"] = gate_key
	_results["test_e_support"] = int(
		(_automation.get_scan_drone_support_counts_by_target() as Dictionary).get(TARGET_OBJECT_ID, 0)
	)
	if gate_key == str(GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS):
		_fail("Test E: support-only must not block with KEY_SCAN_ALREADY_IN_PROGRESS")


func _test_f_galaxy_with_two_assigned() -> void:
	if _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID) < 2:
		_fail("Test F prep: expected 2 assigned drones before galaxy")
		return
	var sd_before: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	GameSession.capture_system_scene_processes_before_leave()
	_system_scene.queue_free()
	_setup_scene_flow()
	SceneFlow.goto_galaxy()
	_wait_frames(30, _galaxy_back_with_active_job.bind(sd_before))


func _setup_scene_flow() -> void:
	var scene_root := Node.new()
	scene_root.name = "SceneRoot"
	add_child(scene_root)
	var slot := Node.new()
	slot.name = "CurrentSceneSlot"
	scene_root.add_child(slot)
	SceneFlow.register_main_root(self)


func _galaxy_back_with_active_job(sd_before: int) -> void:
	SceneFlow.goto_system()
	_wait_frames(150, _after_galaxy_two_assigned.bind(sd_before))


func _after_galaxy_two_assigned(sd_before: int) -> void:
	_automation = _find_automation_controller(SceneFlow.get_current_scene())
	if _automation == null:
		_fail("Test F: AutomationController missing after galaxy")
		_regression_checks()
		_finish()
		return
	var assigned: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_f_assigned_after_galaxy"] = assigned
	if assigned != 2:
		_fail("Test F: expected assigned count 2 after galaxy, got %d" % assigned)
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != sd_before:
		_fail("Test F: SurveyData changed on galaxy restore")
	_run_save_load_on_current_scene()


func _run_save_load_on_current_scene() -> void:
	if _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID) != 2:
		_fail("Test G prep: expected 2 assigned before save")
		_poll_completion_two_assigned()
		return
	if not SaveManager.save_game(TEST_SAVE_SLOT):
		_fail("Test G: save failed")
		_poll_completion_two_assigned()
		return
	var sd_before_load: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	SaveManager.load_game(TEST_SAVE_SLOT)
	SceneFlow.goto_system()
	_wait_frames(150, _after_save_load.bind(sd_before_load))


func _after_save_load(sd_before_load: int) -> void:
	_automation = _find_automation_controller(SceneFlow.get_current_scene())
	if _automation == null:
		_fail("Test G: AutomationController missing after load")
		_poll_completion_two_assigned()
		return
	var assigned: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_g_assigned_after_load"] = assigned
	if assigned != 2:
		_fail("Test G: expected assigned count 2 after load, got %d" % assigned)
	if GameSession.get_base_resource_amount(BASE_ID, "SurveyData") != sd_before_load:
		_fail("Test G: SurveyData changed on load")
	_poll_completion_two_assigned()


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	if GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS.is_empty():
		_fail("KEY_SCAN_ALREADY_IN_PROGRESS missing")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _read_scan_assigned_count() -> int:
	if _scan_count_label == null or not _scan_count_label.visible:
		return int(_object_info._live_action_cache.get("assigned_scan_drone_count", 0))
	var text: String = _scan_count_label.text
	var parts: PackedStringArray = text.split(":")
	if parts.size() < 2:
		return 0
	return int(parts[1].strip_edges())


func _has_idle_scan_drone() -> bool:
	if _automation == null:
		return false
	return not _automation.idle_drones.is_empty()


func _refresh_mars_selection() -> void:
	var mars: Node = _system_scene.get_node_or_null("SystemSpawner") as Node
	if mars == null:
		return
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return
	var body: Node = spawner.get_spawned_object(TARGET_OBJECT_ID)
	if body != null and _selection != null:
		_selection.select_world_node(body as Node2D)
	if _system_ui != null:
		_system_ui.update_object_info()
	_wait_frames(1, func() -> void: pass)


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _grant_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 500)
	GameSession.add_base_resource(BASE_ID, "Copper", 500)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Carbon", 500)


func _find_automation_controller(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _find_automation_controller(child)
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
	push_error("[SharedScanJobStep6Smoke] FAIL: %s" % message)


func _finish() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	_print_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _print_report() -> void:
	var overall: String = "PASS"
	if not _failures.is_empty():
		overall = "FAIL"
	elif not _notes.is_empty():
		overall = "PASS WITH NOTES"
	print("")
	print("=== SharedScanJob Step 6 UI Assign ScanDrone SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("==========================================================")


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
