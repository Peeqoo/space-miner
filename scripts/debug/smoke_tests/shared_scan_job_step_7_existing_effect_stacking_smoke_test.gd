## SharedScanJob Step 7 — existing ScanDrone effect stacking smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const SYSTEM_ID: String = "solar-system"
const TARGET_OBJECT_ID: String = "mars"
const BASE_ID: String = BaseStore.BASE_EARTH
const TEST_SAVE_SLOT: int = 3

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _automation: AutomationController = null
var _object_info: ObjectInfoPanel = null
var _mining_bonus_label: Label = null

var _per_drone_pct: int = 0
var _sd_at_start: int = 0
var _scan_state_at_start: String = ""
var _scan_duration_one_drone: float = -1.0


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	GameSession.reset_for_new_game()
	_setup_mars_mineable()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(100, _setup_and_run)


func _setup_and_run() -> void:
	var system_ui: SystemUIController = (
		_system_scene.get_node_or_null("SystemUIController") as SystemUIController
	)
	_automation = _find_automation_controller(_system_scene)
	_object_info = system_ui.object_info_panel if system_ui != null else null
	_mining_bonus_label = _object_info.get_node_or_null(
		"Margin/Root/OrbitStatusSection/MiningBonusLabel"
	) as Label if _object_info != null else null
	if _automation == null:
		_fail("AutomationController missing")
		_finish()
		return
	_automation.ensure_starting_units(BASE_ID)
	_per_drone_pct = GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(BASE_ID)
	_results["per_drone_pct"] = _per_drone_pct
	_test_a_zero_support()
	_test_b_one_support()
	_test_c_two_support()
	_test_d_three_support()
	_test_g_ui_telemetry()
	_test_e_no_scan_speed_change()
	_poll_scan_completion(400)


func _test_a_zero_support() -> void:
	var bonus: float = _automation.get_mining_bonus_for_target(TARGET_OBJECT_ID)
	var support_n: int = _automation.get_scan_drone_support_effect_count_for_target(TARGET_OBJECT_ID)
	_results["test_a_support"] = support_n
	_results["test_a_bonus"] = bonus
	if support_n != 0:
		_fail("Test A: expected 0 support drones, got %d" % support_n)
	if absf(bonus) > 0.0001:
		_fail("Test A: expected 0 mining bonus, got %s" % bonus)


func _test_b_one_support() -> void:
	_place_support_drone(TARGET_OBJECT_ID)
	_assert_support_stacking(1, "Test B")


func _test_c_two_support() -> void:
	_place_support_drone(TARGET_OBJECT_ID)
	_assert_support_stacking(2, "Test C")


func _test_d_three_support() -> void:
	_grant_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	_place_support_drone(TARGET_OBJECT_ID)
	_assert_support_stacking(3, "Test D")


func _assert_support_stacking(expected_count: int, test_name: String) -> void:
	var support_n: int = _automation.get_scan_drone_support_effect_count_for_target(TARGET_OBJECT_ID)
	var bonus: float = _automation.get_mining_bonus_for_target(TARGET_OBJECT_ID)
	var expected_bonus: float = (float(expected_count) * float(_per_drone_pct)) / 100.0
	var expected_mult: float = 1.0 + expected_bonus
	_results["%s_support" % test_name.to_lower().replace(" ", "_")] = support_n
	_results["%s_bonus" % test_name.to_lower().replace(" ", "_")] = bonus
	_results["%s_mult" % test_name.to_lower().replace(" ", "_")] = 1.0 + bonus
	if support_n != expected_count:
		_fail("%s: expected %d support drones, got %d" % [test_name, expected_count, support_n])
	if absf(bonus - expected_bonus) > 0.0001:
		_fail(
			"%s: expected bonus %s, got %s (per_drone=%d%%)"
			% [test_name, expected_bonus, bonus, _per_drone_pct]
		)
	var effects: Dictionary = _automation.get_scan_drone_support_effects_by_target()
	var mars_fx: Dictionary = effects.get(TARGET_OBJECT_ID, {}) as Dictionary
	if mars_fx.is_empty():
		_fail("%s: scan_support_effects missing mars entry" % test_name)
		return
	if int(mars_fx.get("support_drone_count", -1)) != expected_count:
		_fail("%s: telemetry support_drone_count mismatch" % test_name)
	if absf(float(mars_fx.get("mining_rate_multiplier", 0.0)) - expected_mult) > 0.0001:
		_fail("%s: telemetry mining_rate_multiplier mismatch" % test_name)


func _test_e_no_scan_speed_change() -> void:
	_reset_support_drones_for_scan_test()
	_setup_mars_scannable()
	_sd_at_start = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	_scan_state_at_start = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_automation.launch_scan_drone(TARGET_OBJECT_ID)
	var unit_one: AutomationUnit = _first_active_scan_drone()
	if unit_one == null:
		_fail("Test E: no active scan drone after launch")
		return
	_scan_duration_one_drone = unit_one.work_duration
	_grant_build_resources()
	if GameSession.build_base_drone(BASE_ID):
		_automation.spawn_idle_drone_at_base(BASE_ID)
	if not _automation.assign_scan_drone_to_shared_job(TARGET_OBJECT_ID):
		_fail("Test E: assign second scan drone failed")
		return
	var assigned: int = _automation.get_assigned_scan_drone_count_for_target(TARGET_OBJECT_ID)
	_results["test_e_assigned"] = assigned
	if assigned != 2:
		_fail("Test E: expected 2 assigned drones, got %d" % assigned)
	var unit_two: AutomationUnit = _second_active_scan_drone(unit_one)
	if unit_two != null and absf(unit_two.work_duration - _scan_duration_one_drone) > 0.001:
		_fail(
			"Test E: scan duration changed with 2 drones (%s vs %s)"
			% [unit_two.work_duration, _scan_duration_one_drone]
		)
	var support_during_scan: int = _automation.get_scan_drone_support_effect_count_for_target(
		TARGET_OBJECT_ID
	)
	_results["test_e_support_during_scan"] = support_during_scan
	if support_during_scan > 0:
		_notes.append("Test E: support count > 0 during in-flight scan — expected 0")


func _poll_scan_completion(frames_left: int) -> void:
	if _automation.get_active_shared_scan_job_count() == 0:
		_verify_single_reward()
		return
	if frames_left <= 0:
		_notes.append("Test F: scan completion poll timed out")
		_verify_single_reward()
		return
	_wait_frames(30, _poll_scan_completion.bind(frames_left - 1))


func _verify_single_reward() -> void:
	var sd_after: int = GameSession.get_base_resource_amount(BASE_ID, "SurveyData")
	var scan_after: String = GameSession.get_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID)
	_results["test_f_sd_delta"] = sd_after - _sd_at_start
	_results["test_f_scan_after"] = scan_after
	if sd_after <= _sd_at_start:
		_fail("Test F: expected SurveyData reward once")
	if scan_after == _scan_state_at_start:
		_fail("Test F: scan state unchanged after completion")
	_regression_checks()
	_finish()


func _test_g_ui_telemetry() -> void:
	var tel: BalanceTelemetryLogger = BalanceTelemetryLogger.new()
	add_child(tel)
	var snap: Dictionary = tel.peek_scan_telemetry_section(BASE_ID, SYSTEM_ID)
	var effects: Dictionary = snap.get("scan_support_effects", {}) as Dictionary
	var mars_fx: Dictionary = effects.get(TARGET_OBJECT_ID, {}) as Dictionary
	_results["test_g_support_count"] = int(mars_fx.get("support_drone_count", 0))
	_results["test_g_telemetry_bonus"] = float(mars_fx.get("total_mining_bonus", -1.0))
	if mars_fx.is_empty():
		_fail("Test G: telemetry scan_support_effects missing mars")
	elif _per_drone_pct == 2:
		var expected_total: float = float(_results["test_g_support_count"]) * 0.02
		if absf(float(mars_fx.get("total_mining_bonus", 0.0)) - expected_total) > 0.0001:
			_fail("Test G: total_mining_bonus mismatch for support count")
	tel.queue_free()
	if _object_info != null and _mining_bonus_label != null:
		_select_mars()
		if _mining_bonus_label.text.to_lower().contains("scan speed"):
			_fail("Test G: MiningBonusLabel must not show scan speed")


func _reset_support_drones_for_scan_test() -> void:
	var unit_ids: Array[int] = []
	for uid_variant: Variant in _automation.scan_drone_target_by_unit_id.keys():
		if str(_automation.scan_drone_target_by_unit_id.get(uid_variant, "")) == TARGET_OBJECT_ID:
			unit_ids.append(int(uid_variant))
	for uid: int in unit_ids:
		_automation.scan_drone_target_by_unit_id.erase(uid)
		var unit := instance_from_id(uid) as AutomationUnit
		if unit != null and is_instance_valid(unit):
			_automation.idle_drones.erase(unit)
			unit.queue_free()


func _place_support_drone(target_id: String) -> void:
	_automation.spawn_idle_drone_at_base(BASE_ID)
	var unit: AutomationUnit = null
	for drone: AutomationUnit in _automation.idle_drones:
		if drone != null and is_instance_valid(drone):
			unit = drone
			break
	if unit == null:
		_fail("place_support_drone: no idle drone available")
		return
	_automation.idle_drones.erase(unit)
	var target_node: Node2D = _get_spawned_object(target_id)
	if target_node == null:
		_fail("place_support_drone: target node missing")
		return
	var unit_id: int = unit.get_instance_id()
	_automation.scan_drone_target_by_unit_id[unit_id] = target_id
	unit.transfer_orbit_to_base(target_node)


func _first_active_scan_drone() -> AutomationUnit:
	for unit: Variant in _automation.active_units_by_mission_id.values():
		var drone: AutomationUnit = unit as AutomationUnit
		if drone != null and is_instance_valid(drone):
			return drone
	return null


func _second_active_scan_drone(exclude: AutomationUnit) -> AutomationUnit:
	for unit: Variant in _automation.active_units_by_mission_id.values():
		var drone: AutomationUnit = unit as AutomationUnit
		if drone != null and is_instance_valid(drone) and drone != exclude:
			return drone
	for unit_id_variant: Variant in _automation.scan_drone_target_by_unit_id.keys():
		var drone: AutomationUnit = instance_from_id(int(unit_id_variant)) as AutomationUnit
		if drone != null and is_instance_valid(drone) and drone != exclude:
			if str(_automation.scan_drone_target_by_unit_id.get(unit_id_variant, "")) == TARGET_OBJECT_ID:
				return drone
	return null


func _get_spawned_object(object_id: String) -> Node2D:
	var spawner: SystemSpawner = _system_scene.get_node_or_null("SystemSpawner") as SystemSpawner
	if spawner == null:
		return null
	var node: Node = spawner.get_spawned_object(object_id)
	return node as Node2D


func _select_mars() -> void:
	var selection: SystemSelectionController = (
		_system_scene.get_node_or_null("SystemSelectionController") as SystemSelectionController
	)
	var body: Node2D = _get_spawned_object(TARGET_OBJECT_ID)
	if selection != null and body != null:
		selection.select_world_node(body)
	var system_ui: SystemUIController = (
		_system_scene.get_node_or_null("SystemUIController") as SystemUIController
	)
	if system_ui != null:
		system_ui.update_object_info()


func _setup_mars_mineable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)


func _setup_mars_scannable() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_UNKNOWN)


func _grant_build_resources() -> void:
	GameSession.add_base_resource(BASE_ID, "Iron", 500)
	GameSession.add_base_resource(BASE_ID, "Copper", 500)
	GameSession.add_base_resource(BASE_ID, "Silicon", 500)
	GameSession.add_base_resource(BASE_ID, "Carbon", 500)


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("Regression: SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("Regression: tooltip_text count expected 0, got %d" % tooltip_count)


func _find_automation_controller(root: Node) -> AutomationController:
	if root is AutomationController:
		return root as AutomationController
	for child: Node in root.get_children():
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
	push_error("[SharedScanJobStep7EffectStackingSmoke] FAIL: %s" % message)


func _finish() -> void:
	SaveManager.delete_save(TEST_SAVE_SLOT)
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== SharedScanJob Step 7 Existing Effect Stacking Smoke ===")
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
