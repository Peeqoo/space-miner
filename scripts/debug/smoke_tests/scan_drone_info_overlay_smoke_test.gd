## ScanDroneInfoOverlay extraction smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/scan_drone_info_overlay_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const SCAN_BUTTON_TEXT: String = "Scan"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _system_ui: SystemUIController = null
var _selection: SystemSelectionController = null
var _automation: AutomationController = null


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_overlay_key_shape()
	_setup_mars_scannable()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_runtime_tests)


func _test_a_overlay_key_shape() -> void:
	var info: Dictionary = {}
	ScanDroneInfoOverlay.apply(
		info,
		null,
		TARGET_OBJECT_ID,
		SYSTEM_ID,
		BASE_ID,
		null,
		false,
		SCAN_BUTTON_TEXT,
		false,
	)

	for key: StringName in ScanDroneInfoOverlay.OVERLAY_KEYS:
		if String(key).is_empty():
			_fail("Test A: ObjectInfoDictKeys scan drone key is empty")
		if not info.has(key):
			_fail("Test A: missing overlay key %s" % String(key))

	_results["test_a_keys_present"] = true
	_results["test_a_show_scan"] = info.get(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE, true)
	if info.get(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE, true) != false:
		_fail("Test A: null node must leave show_scan_with_drone false")


func _setup_runtime_tests() -> void:
	_system_ui = _system_scene.get_node_or_null("SystemUIController") as SystemUIController
	_selection = _system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	_automation = _find_automation_controller(_system_scene)
	if _system_ui == null or _automation == null:
		_fail("Missing SystemUIController or AutomationController")
		_regression_checks()
		_finish()
		return

	_automation.ensure_starting_units(BASE_ID)
	_test_b_controller_delegation_equality()
	_test_d_support_count()
	_test_c_active_shared_scan_job_assign_path()
	_regression_checks()
	_finish()


func _test_b_controller_delegation_equality() -> void:
	var mars: Node = _get_spawned_object(TARGET_OBJECT_ID)
	if mars == null:
		_fail("Test B: Mars node missing")
		return

	var info_overlay: Dictionary = {}
	var info_controller: Dictionary = {}
	_apply_overlay_for_node(info_overlay, mars, TARGET_OBJECT_ID)
	_system_ui._apply_scan_drone_info_to_dict(info_controller, mars, TARGET_OBJECT_ID)

	_results["test_b_overlay"] = _snapshot_scan_drone_fields(info_overlay)
	_results["test_b_controller"] = _snapshot_scan_drone_fields(info_controller)

	if not _scan_drone_dicts_equal(info_overlay, info_controller):
		_fail("Test B: overlay output must match SystemUIController._apply_scan_drone_info_to_dict")

	if info_controller.get(ObjectInfoDictKeys.SCAN_BUTTON_TEXT, "") != SCAN_BUTTON_TEXT:
		_fail("Test B: scan_button_text must remain '%s'" % SCAN_BUTTON_TEXT)
	if bool(info_controller.get(ObjectInfoDictKeys.HAS_ACTIVE_SHARED_SCAN_JOB, true)):
		_fail("Test B: has_active_shared_scan_job must be false with no job")


func _test_c_active_shared_scan_job_assign_path() -> void:
	_grant_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	if not _automation.has_active_shared_scan_job_for_target(TARGET_OBJECT_ID):
		_fail("Test C: SharedScanJob missing after launch")
		return

	var mars: Node = _get_spawned_object(TARGET_OBJECT_ID)
	if mars == null:
		_fail("Test C: Mars node missing")
		return

	var info_overlay: Dictionary = {}
	var info_controller: Dictionary = {}
	_apply_overlay_for_node(info_overlay, mars, TARGET_OBJECT_ID)
	_system_ui._apply_scan_drone_info_to_dict(info_controller, mars, TARGET_OBJECT_ID)

	_results["test_c_overlay"] = _snapshot_scan_drone_fields(info_overlay)
	_results["test_c_controller"] = _snapshot_scan_drone_fields(info_controller)

	if not _scan_drone_dicts_equal(info_overlay, info_controller):
		_fail("Test C: overlay must match controller during active SharedScanJob")

	if info_controller.get(ObjectInfoDictKeys.HAS_ACTIVE_SHARED_SCAN_JOB, false) != true:
		_fail("Test C: has_active_shared_scan_job must be true")
	var assigned: int = int(info_controller.get(ObjectInfoDictKeys.ASSIGNED_SCAN_DRONE_COUNT, 0))
	_results["test_c_assigned"] = assigned
	if assigned < 1:
		_fail("Test C: assigned_scan_drone_count must be >= 1, got %d" % assigned)
	if info_controller.get(ObjectInfoDictKeys.SHOW_SCAN_WITH_DRONE, false) != true:
		_fail("Test C: show_scan_with_drone must be true during active job")
	if info_controller.get(ObjectInfoDictKeys.SCAN_BUTTON_TEXT, "") != SCAN_BUTTON_TEXT:
		_fail("Test C: scan_button_text must remain '%s'" % SCAN_BUTTON_TEXT)


func _test_d_support_count() -> void:
	_place_support_drone(TARGET_OBJECT_ID)
	var mars: Node = _get_spawned_object(TARGET_OBJECT_ID)
	if mars == null:
		_fail("Test D: Mars node missing")
		return

	var info: Dictionary = _system_ui._build_selected_object_info(mars)
	var support_ui: int = int(info.get(ObjectInfoDictKeys.SCAN_DRONE_SUPPORTING_COUNT, -1))
	var support_auto: int = _automation.get_orbiting_drone_count(TARGET_OBJECT_ID)
	_results["test_d_support_ui"] = support_ui
	_results["test_d_support_auto"] = support_auto

	if support_ui != support_auto:
		_fail("Test D: scan_drone_supporting_count mismatch ui=%d auto=%d" % [
			support_ui, support_auto,
		])
	if support_ui < 1:
		_fail("Test D: expected supporting count >= 1 after place_support_drone")


func _apply_overlay_for_node(info: Dictionary, selected_node: Node, object_id: String) -> void:
	var is_established_home_body := false
	if selected_node is SystemBody:
		is_established_home_body = _system_ui._selected_body_has_established_base(
			selected_node as SystemBody
		)
	var system_id := ""
	if _system_ui.system_definition != null:
		system_id = _system_ui.system_definition.id.strip_edges()
	ScanDroneInfoOverlay.apply(
		info,
		selected_node,
		object_id,
		system_id,
		_system_ui._economy_body_id_for_ui(),
		_automation,
		_system_ui._has_available_drone(),
		SCAN_BUTTON_TEXT,
		is_established_home_body,
	)


func _snapshot_scan_drone_fields(info: Dictionary) -> Dictionary:
	var snap: Dictionary = {}
	for key: StringName in ScanDroneInfoOverlay.OVERLAY_KEYS:
		snap[key] = info.get(key)
	return snap


func _scan_drone_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	for key: StringName in ScanDroneInfoOverlay.OVERLAY_KEYS:
		if a.get(key) != b.get(key):
			_results["mismatch_key"] = String(key)
			_results["mismatch_a"] = a.get(key)
			_results["mismatch_b"] = b.get(key)
			return false
	return true


func _place_support_drone(target_id: String) -> void:
	var unit: AutomationUnit = null
	for drone: AutomationUnit in _automation.idle_drones:
		if drone != null and is_instance_valid(drone):
			unit = drone
			break
	if unit == null:
		_fail("place_support_drone: no idle drone available")
		return
	_automation.idle_drones.erase(unit)
	var target_node: Node2D = _get_spawned_object(target_id) as Node2D
	if target_node == null:
		_fail("place_support_drone: target node missing")
		return
	var unit_id: int = unit.get_instance_id()
	_automation.scan_drone_target_by_unit_id[unit_id] = target_id
	unit.transfer_orbit_to_base(target_node)


func _get_spawned_object(object_id: String) -> Node:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return null
	return spawner.get_spawned_object(object_id)


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _grant_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 500)
	GameSession.add_base_resource(BASE_ID, "Copper", 500)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Carbon", 500)


func _find_automation_controller(root: Node) -> AutomationController:
	if root is AutomationController:
		return root as AutomationController
	for child: Node in root.get_children():
		var found: AutomationController = _find_automation_controller(child)
		if found != null:
			return found
	return null


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


func _wait_frames(count: int, callback: Callable) -> void:
	if not callback.is_valid():
		return
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[ScanDroneInfoOverlaySmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== ScanDrone Info Overlay Smoke ===")
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
