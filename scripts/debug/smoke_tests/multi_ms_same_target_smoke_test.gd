## Multi-MiningShip same target smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/multi_ms_smoke_runner.tscn
extends Node

const SYSTEM_SCENE_PATH: String = "res://scenes/system/system_scene.tscn"
const TARGET_OBJECT_ID: String = "mars"
const SYSTEM_ID: String = "solar-system"

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}

var _system_scene: Node = null
var _automation: AutomationController = null
var _base_id: String = BaseStore.BASE_EARTH


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_grant_build_resources()
	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load system scene")
		_finish()
		return
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(90, _run_tests)


func _wait_frames(count: int, callback: Callable) -> void:
	var waiter := _FrameWaiter.new()
	waiter.frames = count
	waiter.done.connect(callback, CONNECT_ONE_SHOT)
	add_child(waiter)


func _run_tests() -> void:
	_automation = _find_automation_controller(_system_scene)
	if _automation == null:
		_fail("AutomationController not found")
		_finish()
		return

	if not GameSession.has_established_base(_base_id):
		_fail("Earth base not established")
		_finish()
		return

	_setup_mars_for_mining()
	_build_extra_mining_ships(2)
	_automation.ensure_starting_units(_base_id)
	_wait_frames(30, _test_launches)


func _test_launches() -> void:
	var launched: int = 0
	var ms_owned: int = GameSession.get_base_mining_ship_count(_base_id)
	_results["mining_ship_count"] = ms_owned
	_results["target_object"] = TARGET_OBJECT_ID

	if ms_owned < 3:
		_fail("Expected >= 3 mining ships, got %d" % ms_owned)

	for attempt: int in range(ms_owned):
		var gate: Dictionary = GameSession.can_mine_object(
			SYSTEM_ID,
			TARGET_OBJECT_ID,
			_base_id,
			true,
		)
		var key: StringName = gate.get("blocked_reason_key", GateUiTextDefinition.KEY_NONE)
		if not bool(gate.get("ok", false)):
			_fail("can_mine_object blocked launch #%d: key=%s reason=%s" % [
				attempt + 1, str(key), str(gate.get("blocked_reason", "")),
			])
			break
		if str(key).contains("already") or str(key).contains("limit"):
			_fail("Unexpected mine block key: %s" % str(key))

		if not _automation.launch_mining_ship(TARGET_OBJECT_ID):
			_fail("launch_mining_ship failed for ship #%d" % (attempt + 1))
			break
		launched += 1

	_results["launches_ok"] = launched
	_results["active_mining_jobs"] = _automation.mining_ship_runtime_by_unit_id.size()
	_results["assigned_to_mars"] = _automation.get_assigned_mining_ship_count(TARGET_OBJECT_ID)

	if launched < 3:
		_fail("Only %d/3 mining launches succeeded" % launched)
	if _automation.get_assigned_mining_ship_count(TARGET_OBJECT_ID) < 3:
		_fail(
			"assigned count %d < 3"
			% _automation.get_assigned_mining_ship_count(TARGET_OBJECT_ID)
		)

	_verify_runtime_targets()
	_wait_frames(120, _test_mining_extraction)


func _test_mining_extraction() -> void:
	var iron_before: int = GameSession.get_remaining_resource_amount(
		SYSTEM_ID, TARGET_OBJECT_ID, "Iron"
	)
	_wait_frames(180, _after_mining_ticks.bind(iron_before))


func _after_mining_ticks(iron_before: int) -> void:
	var iron_after: int = GameSession.get_remaining_resource_amount(
		SYSTEM_ID, TARGET_OBJECT_ID, "Iron"
	)
	_results["mars_iron_before"] = iron_before
	_results["mars_iron_after"] = iron_after
	_results["iron_extracted"] = iron_before - iron_after
	_results["active_mining_jobs_after_ticks"] = _automation.mining_ship_runtime_by_unit_id.size()

	if iron_after > iron_before:
		_fail("Mars Iron increased (duplication?) before=%d after=%d" % [iron_before, iron_after])
	if iron_after < 0:
		_fail("Negative remaining Iron: %d" % iron_after)

	var any_cargo: bool = false
	for uid_v: Variant in _automation.mining_ship_runtime_by_unit_id.keys():
		var rt: Dictionary = _automation.mining_ship_runtime_by_unit_id[uid_v] as Dictionary
		if str(rt.get("target_id", "")) != TARGET_OBJECT_ID:
			continue
		var cargo: Dictionary = rt.get("cargo_resources", {}) as Dictionary
		for amt_v: Variant in cargo.values():
			if int(amt_v) > 0:
				any_cargo = true
	if not any_cargo and iron_before == iron_after:
		_notes.append("No cargo/extraction in window — ships may still be in transit")

	_test_save_load_roundtrip()


func _test_save_load_roundtrip() -> void:
	var jobs_before: int = _automation.mining_ship_runtime_by_unit_id.size()
	var mars_jobs_before: int = _automation.get_assigned_mining_ship_count(TARGET_OBJECT_ID)
	GameSession.refresh_automation_snapshot_from_scene()
	var payload: Dictionary = GameSession.to_save_data()

	_system_scene.queue_free()
	_system_scene = null
	_automation = null
	_wait_frames(10, _reload_scene_after_save.bind(payload, jobs_before, mars_jobs_before))


func _reload_scene_after_save(
	payload: Dictionary,
	jobs_before: int,
	mars_jobs_before: int,
) -> void:
	GameSession.reset_for_new_game()
	if not GameSession.apply_save_data(payload):
		_fail("apply_save_data failed")
		_finish()
		return

	var packed: PackedScene = load(SYSTEM_SCENE_PATH) as PackedScene
	_system_scene = packed.instantiate()
	add_child(_system_scene)
	_wait_frames(120, _verify_save_restore.bind(jobs_before, mars_jobs_before))


func _verify_save_restore(jobs_before: int, mars_jobs_before: int) -> void:
	_automation = _find_automation_controller(_system_scene)
	if _automation == null:
		_fail("AutomationController missing after reload")
		_finish()
		return

	var jobs_after: int = _automation.mining_ship_runtime_by_unit_id.size()
	var mars_after: int = _automation.get_assigned_mining_ship_count(TARGET_OBJECT_ID)
	_results["save_load_jobs_before"] = jobs_before
	_results["save_load_jobs_after"] = jobs_after
	_results["save_load_mars_jobs_after"] = mars_after

	if jobs_after < mini(2, jobs_before):
		_fail("Save/load lost mining jobs: before=%d after=%d" % [jobs_before, jobs_after])
	if mars_after < mini(2, mars_jobs_before):
		_fail("Save/load lost mars-target jobs: before=%d after=%d" % [mars_jobs_before, mars_after])

	_finish()


func _setup_mars_for_mining() -> void:
	GameSession.set_object_discovery_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.DISCOVERY_KNOWN)
	GameSession.set_object_scan_state(SYSTEM_ID, TARGET_OBJECT_ID, GameSession.SCAN_BASIC)
	GameSession.ensure_mining_resources_for_object(SYSTEM_ID, TARGET_OBJECT_ID)


func _grant_build_resources() -> void:
	# Start storage cap 1000 — grant both within total capacity.
	GameSession.add_base_resource(_base_id, "Silicon", 200)
	GameSession.add_base_resource(_base_id, "Iron", 800)


func _build_extra_mining_ships(count: int) -> void:
	for i: int in range(count):
		var gate: Dictionary = GameSession.get_build_base_mining_ship_gate(_base_id)
		if not bool(gate.get("ok", false)):
			_fail(
				"MS build gate blocked #%d: key=%s reason=%s iron=%d si=%d"
				% [
					i + 1,
					str(gate.get("blocked_reason_key", "")),
					str(gate.get("blocked_reason", "")),
					GameSession.get_base_resource_amount(_base_id, "Iron"),
					GameSession.get_base_resource_amount(_base_id, "Silicon"),
				]
			)
			return
		if not GameSession.build_base_mining_ship(_base_id):
			_fail("build_base_mining_ship failed after gate ok #%d" % (i + 1))
			return
		_automation.spawn_idle_mining_ship_at_base(_base_id)


func _verify_runtime_targets() -> void:
	var mars_count: int = 0
	for uid_v: Variant in _automation.mining_ship_runtime_by_unit_id.keys():
		var rt: Dictionary = _automation.mining_ship_runtime_by_unit_id[uid_v] as Dictionary
		if str(rt.get("target_id", "")) == TARGET_OBJECT_ID:
			mars_count += 1
	_results["runtime_mars_target_entries"] = mars_count
	if mars_count < 3:
		_fail("runtime entries with target mars: %d (expected 3)" % mars_count)


func _find_automation_controller(node: Node) -> AutomationController:
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _find_automation_controller(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[MultiMsSmoke] FAIL: %s" % message)


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
	print("=== Multi-MS Same Target SmokeTest ===")
	print("Overall: %s" % overall)
	for key: String in _results.keys():
		print("  %s: %s" % [key, str(_results[key])])
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("======================================")


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
