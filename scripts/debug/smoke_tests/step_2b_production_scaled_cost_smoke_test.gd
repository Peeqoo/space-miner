## Step 2b smoke test — scaled costs active for SD/MS/SP spend path.
## Debug-only. Does NOT auto-run. Execute manually:
##   godot --headless --path . --script res://scripts/debug/smoke_tests/step_2b_production_scaled_cost_smoke_test.gd
extends SceneTree

var _failures: Array[String] = []
var _notes: Array[String] = []


func _init() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		call_deferred("_finish")
		return
	call_deferred("_run_all")


func _run_all() -> void:
	GameSession.reset_for_new_game()
	var bid: String = _primary_base_id()
	if not GameSession.has_established_base(bid):
		_fail("Base not established after reset_for_new_game")
		_finish()
		return

	_test_start_scaled_costs(bid)
	_test_scan_drone_build_spend(bid)
	_test_mining_ship_build_spend(bid)
	_test_survey_probe_consume_and_build(bid)
	_test_colony_ship_flat(bid)
	_test_preview_used_for_gameplay(bid)
	_test_save_load_scaled_state(bid)
	_finish()


func _primary_base_id() -> String:
	if GameSession.has_established_base(BaseStore.BASE_EARTH):
		return BaseStore.BASE_EARTH
	var src: String = GameSession.get_colonization_source_base_id().strip_edges()
	if not src.is_empty():
		return src
	return BaseStore.BASE_EARTH


func _test_start_scaled_costs(base_id: String) -> void:
	_expect_scaled_cost(base_id, BaseStore.PRODUCTION_SCAN_DRONE, {"Iron": 108})
	_expect_scaled_cost(base_id, BaseStore.PRODUCTION_MINING_SHIP, {"Iron": 300, "Silicon": 50})
	_expect_scaled_cost(base_id, BaseStore.PRODUCTION_SURVEY_PROBE, {"Iron": 53})


func _test_scan_drone_build_spend(base_id: String) -> void:
	GameSession.add_base_resource(base_id, "Iron", 500)
	var expected: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SCAN_DRONE, base_id
	)
	var iron_before: int = GameSession.get_base_resource_amount(base_id, "Iron")
	var life_before: int = GameSession.get_production_lifetime_count(
		base_id, BaseStore.PRODUCTION_SCAN_DRONE
	)

	if not GameSession.build_base_drone(base_id):
		_fail("build_base_drone failed at start lifetime")
		return

	var iron_spent: int = iron_before - GameSession.get_base_resource_amount(base_id, "Iron")
	_expect_amount(iron_spent, int(expected.get("Iron", 0)), "ScanDrone first build Iron spend")
	if GameSession.get_production_lifetime_count(base_id, BaseStore.PRODUCTION_SCAN_DRONE) != life_before + 1:
		_fail("ScanDrone lifetime did not increment")

	var next_cost: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SCAN_DRONE, base_id
	)
	_expect_amount(int(next_cost.get("Iron", 0)), 130, "ScanDrone next cost after build")


func _test_mining_ship_build_spend(base_id: String) -> void:
	GameSession.add_base_resource(base_id, "Iron", 2000)
	GameSession.add_base_resource(base_id, "Silicon", 500)
	var expected: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_MINING_SHIP, base_id
	)
	var fe_before: int = GameSession.get_base_resource_amount(base_id, "Iron")
	var si_before: int = GameSession.get_base_resource_amount(base_id, "Silicon")

	if not GameSession.build_base_mining_ship(base_id):
		_fail("build_base_mining_ship failed at start lifetime")
		return

	var fe_spent: int = fe_before - GameSession.get_base_resource_amount(base_id, "Iron")
	var si_spent: int = si_before - GameSession.get_base_resource_amount(base_id, "Silicon")
	_expect_amount(fe_spent, int(expected.get("Iron", 0)), "MiningShip first build Iron spend")
	_expect_amount(si_spent, int(expected.get("Silicon", 0)), "MiningShip first build Silicon spend")

	var next_cost: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_MINING_SHIP, base_id
	)
	_expect_amount(int(next_cost.get("Iron", 0)), 375, "MiningShip next Iron after build")
	_expect_amount(int(next_cost.get("Silicon", 0)), 63, "MiningShip next Silicon after build")


func _test_survey_probe_consume_and_build(base_id: String) -> void:
	var cost_before_consume: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SURVEY_PROBE, base_id
	)
	_expect_amount(int(cost_before_consume.get("Iron", 0)), 53, "SurveyProbe start scaled cost")

	var life_before: int = GameSession.get_production_lifetime_count(
		base_id, BaseStore.PRODUCTION_SURVEY_PROBE
	)
	if GameSession.bases.consume_survey_probe(base_id, 1):
		var cost_after_consume: Dictionary = GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_SURVEY_PROBE, base_id
		)
		if GameSession.get_production_lifetime_count(base_id, BaseStore.PRODUCTION_SURVEY_PROBE) != life_before:
			_fail("SurveyProbe consume changed lifetime count")
		if int(cost_after_consume.get("Iron", 0)) != int(cost_before_consume.get("Iron", 0)):
			_fail("SurveyProbe consume changed scaled build cost")
	else:
		_notes.append("SurveyProbe consume skipped (no probe available)")

	GameSession.add_base_resource(base_id, "Iron", 200)
	var expected: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SURVEY_PROBE, base_id
	)
	var iron_before: int = GameSession.get_base_resource_amount(base_id, "Iron")
	if not GameSession.build_base_survey_probe(base_id):
		_fail("build_base_survey_probe failed")
		return
	var iron_spent: int = iron_before - GameSession.get_base_resource_amount(base_id, "Iron")
	_expect_amount(iron_spent, int(expected.get("Iron", 0)), "SurveyProbe build Iron spend")

	var next_cost: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_SURVEY_PROBE, base_id
	)
	_expect_amount(int(next_cost.get("Iron", 0)), 61, "SurveyProbe next cost after build")


func _test_colony_ship_flat(base_id: String) -> void:
	var info: Dictionary = GameSession.get_scaled_production_cost_preview_info(
		BaseStore.PRODUCTION_COLONY_SHIP, base_id
	)
	if not bool(info.get("scaling_excluded", false)):
		_fail("ColonyShip scaling_excluded expected true")
	if bool(info.get("used_for_gameplay", true)):
		_fail("ColonyShip used_for_gameplay expected false")

	var cost: Dictionary = GameSession.get_scaled_production_cost(
		BaseStore.PRODUCTION_COLONY_SHIP, base_id
	)
	_expect_amount(int(cost.get("Iron", 0)), 1500, "ColonyShip flat Iron")
	_expect_amount(int(cost.get("Silicon", 0)), 300, "ColonyShip flat Silicon")
	_expect_amount(int(cost.get("Water", 0)), 350, "ColonyShip flat Water")
	_expect_amount(int(cost.get("SurveyData", 0)), 150, "ColonyShip flat SurveyData")


func _test_preview_used_for_gameplay(base_id: String) -> void:
	for pid: String in [
		BaseStore.PRODUCTION_SCAN_DRONE,
		BaseStore.PRODUCTION_MINING_SHIP,
		BaseStore.PRODUCTION_SURVEY_PROBE,
	]:
		var info: Dictionary = GameSession.get_scaled_production_cost_preview_info(pid, base_id)
		if not bool(info.get("used_for_gameplay", false)):
			_fail("%s used_for_gameplay expected true" % pid)
		if str(info.get("count_source", "")) != "production_lifetime_count":
			_notes.append("%s count_source=%s" % [pid, str(info.get("count_source", ""))])


func _test_save_load_scaled_state(base_id: String) -> void:
	var sd_life: int = GameSession.get_production_lifetime_count(
		base_id, BaseStore.PRODUCTION_SCAN_DRONE
	)
	var next_before: int = int(
		GameSession.get_scaled_production_cost(BaseStore.PRODUCTION_SCAN_DRONE, base_id).get("Iron", 0)
	)
	var payload: Dictionary = GameSession.to_save_data()
	GameSession.reset_for_new_game()
	if not GameSession.apply_save_data(payload):
		_fail("apply_save_data failed")
		return
	var next_after: int = int(
		GameSession.get_scaled_production_cost(BaseStore.PRODUCTION_SCAN_DRONE, base_id).get("Iron", 0)
	)
	if next_after != next_before:
		_fail("Save/load changed next ScanDrone scaled cost")
	if GameSession.get_production_lifetime_count(base_id, BaseStore.PRODUCTION_SCAN_DRONE) != sd_life:
		_fail("Save/load changed ScanDrone lifetime")
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")


func _expect_scaled_cost(base_id: String, production_id: String, expected: Dictionary) -> void:
	var cost: Dictionary = GameSession.get_scaled_production_cost(production_id, base_id)
	for res_id: String in expected.keys():
		_expect_amount(int(cost.get(res_id, -1)), int(expected[res_id]), "%s %s start cost" % [production_id, res_id])


func _expect_amount(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[Step2bSmoke] FAIL: %s" % message)


func _finish() -> void:
	var overall: String = "PASS" if _failures.is_empty() else "FAIL"
	if _failures.is_empty() and not _notes.is_empty():
		overall = "PASS WITH NOTES"
	print("")
	print("=== Step 2b Scaled-Cost SmokeTest Result ===")
	print("Overall: %s" % overall)
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("===========================================")
	quit(1 if not _failures.is_empty() else 0)
