## Step 2a smoke test — SD/MS hard production limits removed.
## Debug-only. Does NOT auto-run. Execute manually:
##   godot --headless --path . --script res://scripts/debug/smoke_tests/step_2a_production_limit_smoke_test.gd
extends SceneTree

const BASE_ID: String = "earth"

const KEY_SD_LIMIT: StringName = GateUiTextDefinition.KEY_BUILD_SCAN_DRONE_LIMIT
const KEY_MS_LIMIT: StringName = GateUiTextDefinition.KEY_BUILD_MINING_SHIP_LIMIT

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}


func _init() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		call_deferred("_finish")
		return
	call_deferred("_run_all")


func _run_all() -> void:
	_setup_session()
	_test_start_state()
	_grant_test_resources()
	_test_gates_no_limit()
	_test_scan_drone_builds()
	_test_mining_ship_builds()
	_test_survey_probe_unchanged()
	_test_colony_ship_unchanged()
	_test_scaled_preview()
	_test_save_load_roundtrip()
	_finish()


func _setup_session() -> void:
	GameSession.reset_for_new_game()
	var bid: String = _primary_base_id()
	if not GameSession.has_established_base(bid):
		_fail("Base '%s' not established after reset_for_new_game" % bid)


func _primary_base_id() -> String:
	var earth: String = BaseStore.BASE_EARTH
	if GameSession.has_established_base(earth):
		return earth
	var src: String = GameSession.get_colonization_source_base_id().strip_edges()
	if not src.is_empty():
		return src
	return earth


func _test_start_state() -> void:
	var bid: String = _primary_base_id()
	var sd: int = GameSession.get_base_drone_count(bid)
	var ms: int = GameSession.get_base_mining_ship_count(bid)
	var sp: int = GameSession.bases.get_survey_probe_count(bid)
	var sd_life: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_SCAN_DRONE
	)
	var ms_life: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_MINING_SHIP
	)
	var sp_life: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_SURVEY_PROBE
	)

	if sd != 1:
		_fail("Start scan_drone count expected 1, got %d" % sd)
	if ms != 1:
		_fail("Start mining_ship count expected 1, got %d" % ms)
	if sp != 2:
		_fail("Start survey_probe count expected 2, got %d" % sp)
	if sd_life != 1:
		_fail("Start scan_drone lifetime expected 1, got %d" % sd_life)
	if ms_life != 1:
		_fail("Start mining_ship lifetime expected 1, got %d" % ms_life)
	if sp_life != 2:
		_fail("Start survey_probe lifetime expected 2, got %d" % sp_life)

	_results["start_state"] = _failures.is_empty()


func _grant_test_resources() -> void:
	var bid: String = _primary_base_id()
	GameSession.add_base_resource(bid, "Iron", 2000)
	GameSession.add_base_resource(bid, "Silicon", 500)
	GameSession.add_base_resource(bid, "Copper", 100)
	GameSession.add_base_resource(bid, "Water", 500)
	GameSession.add_base_resource(bid, "SurveyData", 200)


func _test_gates_no_limit() -> void:
	var bid: String = _primary_base_id()
	var sd_gate: Dictionary = GameSession.get_build_base_scan_drone_gate(bid)
	var ms_gate: Dictionary = GameSession.get_build_base_mining_ship_gate(bid)
	var sd_key: StringName = sd_gate.get("blocked_reason_key", GateUiTextDefinition.KEY_NONE)
	var ms_key: StringName = ms_gate.get("blocked_reason_key", GateUiTextDefinition.KEY_NONE)

	if sd_key == KEY_SD_LIMIT:
		_fail("ScanDrone gate returned KEY_BUILD_SCAN_DRONE_LIMIT with resources granted")
	if ms_key == KEY_MS_LIMIT:
		_fail("MiningShip gate returned KEY_BUILD_MINING_SHIP_LIMIT with resources granted")
	if not bool(sd_gate.get("ok", false)):
		_fail(
			"ScanDrone gate not ok with resources (key=%s reason=%s)"
			% [str(sd_key), str(sd_gate.get("blocked_reason", ""))]
		)
	if not bool(ms_gate.get("ok", false)):
		_fail(
			"MiningShip gate not ok with resources (key=%s reason=%s)"
			% [str(ms_key), str(ms_gate.get("blocked_reason", ""))]
		)

	_results["gates_no_limit"] = _failures.is_empty()


func _test_scan_drone_builds() -> void:
	var bid: String = _primary_base_id()

	for build_idx: int in range(2):
		var gate: Dictionary = GameSession.get_build_base_scan_drone_gate(bid)
		var key: StringName = gate.get("blocked_reason_key", GateUiTextDefinition.KEY_NONE)
		if key == KEY_SD_LIMIT:
			_fail("ScanDrone build #%d blocked by limit key" % (build_idx + 2))

		var expected_cost: Dictionary = GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_SCAN_DRONE, bid
		)
		if expected_cost.is_empty():
			_fail("ScanDrone scaled cost empty before build #%d" % (build_idx + 2))
			_results["sd_build"] = false
			return

		var iron_before: int = GameSession.get_base_resource_amount(bid, "Iron")
		var count_before: int = GameSession.get_base_drone_count(bid)
		var life_before: int = GameSession.get_production_lifetime_count(
			bid, BaseStore.PRODUCTION_SCAN_DRONE
		)

		if not GameSession.build_base_drone(bid):
			_fail("build_base_drone failed for build #%d" % (build_idx + 2))
			_results["sd_build"] = false
			return

		var iron_spent: int = iron_before - GameSession.get_base_resource_amount(bid, "Iron")
		var need_iron: int = int(expected_cost.get("Iron", 0))
		if need_iron > 0 and iron_spent != need_iron:
			_fail(
				"ScanDrone build #%d spent %d Iron, expected scaled %d"
				% [build_idx + 2, iron_spent, need_iron]
			)

		if GameSession.get_base_drone_count(bid) != count_before + 1:
			_fail("ScanDrone count did not increment on build #%d" % (build_idx + 2))
		if GameSession.get_production_lifetime_count(bid, BaseStore.PRODUCTION_SCAN_DRONE) != life_before + 1:
			_fail("ScanDrone lifetime did not increment on build #%d" % (build_idx + 2))

	var final_count: int = GameSession.get_base_drone_count(bid)
	var final_life: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_SCAN_DRONE
	)
	if final_count < 3:
		_fail("ScanDrone count after builds expected >= 3, got %d" % final_count)
	if final_life < 3:
		_fail("ScanDrone lifetime after builds expected >= 3, got %d" % final_life)

	_results["sd_build"] = true


func _test_mining_ship_builds() -> void:
	var bid: String = _primary_base_id()

	for build_idx: int in range(2):
		var gate: Dictionary = GameSession.get_build_base_mining_ship_gate(bid)
		var key: StringName = gate.get("blocked_reason_key", GateUiTextDefinition.KEY_NONE)
		if key == KEY_MS_LIMIT:
			_fail("MiningShip build #%d blocked by limit key" % (build_idx + 2))

		var expected_cost: Dictionary = GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_MINING_SHIP, bid
		)
		if expected_cost.is_empty():
			_fail("MiningShip scaled cost empty before build #%d" % (build_idx + 2))
			_results["ms_build"] = false
			return

		var fe_before: int = GameSession.get_base_resource_amount(bid, "Iron")
		var si_before: int = GameSession.get_base_resource_amount(bid, "Silicon")
		var count_before: int = GameSession.get_base_mining_ship_count(bid)
		var life_before: int = GameSession.get_production_lifetime_count(
			bid, BaseStore.PRODUCTION_MINING_SHIP
		)

		if not GameSession.build_base_mining_ship(bid):
			_fail("build_base_mining_ship failed for build #%d" % (build_idx + 2))
			_results["ms_build"] = false
			return

		var fe_spent: int = fe_before - GameSession.get_base_resource_amount(bid, "Iron")
		var si_spent: int = si_before - GameSession.get_base_resource_amount(bid, "Silicon")
		if int(expected_cost.get("Iron", 0)) > 0 and fe_spent != int(expected_cost.get("Iron", 0)):
			_fail("MiningShip build #%d Iron spend mismatch" % (build_idx + 2))
		if int(expected_cost.get("Silicon", 0)) > 0 and si_spent != int(expected_cost.get("Silicon", 0)):
			_fail("MiningShip build #%d Silicon spend mismatch" % (build_idx + 2))

		if GameSession.get_base_mining_ship_count(bid) != count_before + 1:
			_fail("MiningShip count did not increment on build #%d" % (build_idx + 2))
		if GameSession.get_production_lifetime_count(bid, BaseStore.PRODUCTION_MINING_SHIP) != life_before + 1:
			_fail("MiningShip lifetime did not increment on build #%d" % (build_idx + 2))

	var final_count: int = GameSession.get_base_mining_ship_count(bid)
	var final_life: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_MINING_SHIP
	)
	if final_count < 3:
		_fail("MiningShip count after builds expected >= 3, got %d" % final_count)
	if final_life < 3:
		_fail("MiningShip lifetime after builds expected >= 3, got %d" % final_life)

	_results["ms_build"] = true


func _test_survey_probe_unchanged() -> void:
	var bid: String = _primary_base_id()
	var key: StringName = GameSession.bases.get_build_survey_probe_blocked_reason_key(bid)
	if key == KEY_SD_LIMIT or key == KEY_MS_LIMIT:
		_fail("SurveyProbe gate returned SD/MS limit key unexpectedly")

	var sp_life_before: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_SURVEY_PROBE
	)
	var sp_owned_before: int = GameSession.bases.get_survey_probe_count(bid)

	var sp_built: bool = GameSession.build_base_survey_probe(bid)
	if sp_built:
		if GameSession.get_production_lifetime_count(bid, BaseStore.PRODUCTION_SURVEY_PROBE) != sp_life_before + 1:
			_fail("SurveyProbe lifetime did not increment on build")
	else:
		_notes.append("SurveyProbe build skipped (gate blocked — may be resource-only)")

	var expected_life: int = sp_life_before + (1 if sp_built else 0)
	if GameSession.bases.consume_survey_probe(bid, 1):
		var sp_life_after: int = GameSession.get_production_lifetime_count(
			bid, BaseStore.PRODUCTION_SURVEY_PROBE
		)
		var sp_owned_after: int = GameSession.bases.get_survey_probe_count(bid)
		if sp_owned_after >= sp_owned_before + (1 if sp_built else 0):
			_fail("SurveyProbe consume did not reduce owned count")
		if sp_life_after != expected_life:
			_fail("SurveyProbe consume changed lifetime count")
	else:
		_notes.append("SurveyProbe consume not tested (no probe available)")

	var balance := GameSession.get_game_balance()
	if balance != null and balance.max_active_probes_start != 2:
		_notes.append(
			"max_active_probes_start is %d (expected 2 for v0.1)" % balance.max_active_probes_start
		)

	_notes.append("Investigate per-signal cap: NOT TESTED (requires SystemScene)")
	_results["sp_unchanged"] = true


func _test_colony_ship_unchanged() -> void:
	var bid: String = _primary_base_id()
	var preview: Dictionary = GameSession.get_scaled_production_cost_preview_info(
		BaseStore.PRODUCTION_COLONY_SHIP, bid
	)
	if not bool(preview.get("scaling_excluded", false)):
		_fail("ColonyShip scaling_excluded expected true")

	var cost: Dictionary = GameSession.get_colony_ship_build_cost()
	_expect_cost_amount(cost, "Iron", 900)
	_expect_cost_amount(cost, "Silicon", 300)
	_expect_cost_amount(cost, "Water", 350)
	_expect_cost_amount(cost, "SurveyData", 150)

	var gate: Dictionary = GameSession.get_build_base_colony_ship_gate(bid)
	if bool(gate.get("ok", false)):
		_notes.append("ColonyShip gate ok unexpectedly (prereqs may be met in test)")

	_results["cs_unchanged"] = _failures.is_empty()


func _expect_cost_amount(cost: Dictionary, resource_id: String, expected: int) -> void:
	var actual: int = int(cost.get(resource_id, -1))
	if actual != expected:
		_fail("ColonyShip %s cost expected %d, got %d" % [resource_id, expected, actual])


func _test_scaled_preview() -> void:
	var bid: String = _primary_base_id()
	var sd_info: Dictionary = GameSession.get_scaled_production_cost_preview_info(
		BaseStore.PRODUCTION_SCAN_DRONE, bid
	)
	var ms_info: Dictionary = GameSession.get_scaled_production_cost_preview_info(
		BaseStore.PRODUCTION_MINING_SHIP, bid
	)

	if not bool(sd_info.get("used_for_gameplay", false)):
		_fail("ScanDrone scaled_preview used_for_gameplay should be true (Step 2b)")
	if not bool(ms_info.get("used_for_gameplay", false)):
		_fail("MiningShip scaled_preview used_for_gameplay should be true (Step 2b)")
	if int(sd_info.get("built_count", 0)) < 3:
		_fail("ScanDrone scaled_preview built_count expected >= 3")
	if int(ms_info.get("built_count", 0)) < 3:
		_fail("MiningShip scaled_preview built_count expected >= 3")

	var cs_info: Dictionary = GameSession.get_scaled_production_cost_preview_info(
		BaseStore.PRODUCTION_COLONY_SHIP, bid
	)
	if not bool(cs_info.get("scaling_excluded", false)):
		_fail("ColonyShip preview scaling_excluded expected true")

	_notes.append("BalanceTelemetryLogger snapshot: NOT TESTED (use preview API)")
	_results["scaled_preview"] = _failures.is_empty()


func _test_save_load_roundtrip() -> void:
	var bid: String = _primary_base_id()
	var sd_before: int = GameSession.get_base_drone_count(bid)
	var ms_before: int = GameSession.get_base_mining_ship_count(bid)
	var sd_life_before: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_SCAN_DRONE
	)
	var ms_life_before: int = GameSession.get_production_lifetime_count(
		bid, BaseStore.PRODUCTION_MINING_SHIP
	)

	var payload: Dictionary = GameSession.to_save_data()
	var bases_v: Variant = payload.get("bases", {})
	if bases_v is Dictionary:
		var earth_v: Variant = (bases_v as Dictionary).get(bid, {})
		if earth_v is Dictionary:
			if not (earth_v as Dictionary).has("production_lifetime_counts"):
				_fail("Save payload missing production_lifetime_counts on base")

	GameSession.reset_for_new_game()
	if not GameSession.apply_save_data(payload):
		_fail("GameSession.apply_save_data roundtrip failed")
		_results["save_load"] = false
		return

	if GameSession.get_base_drone_count(bid) != sd_before:
		_fail("Save roundtrip SD count mismatch")
	if GameSession.get_base_mining_ship_count(bid) != ms_before:
		_fail("Save roundtrip MS count mismatch")
	if GameSession.get_production_lifetime_count(bid, BaseStore.PRODUCTION_SCAN_DRONE) != sd_life_before:
		_fail("Save roundtrip SD lifetime mismatch")
	if GameSession.get_production_lifetime_count(bid, BaseStore.PRODUCTION_MINING_SHIP) != ms_life_before:
		_fail("Save roundtrip MS lifetime mismatch")

	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")

	_results["save_load"] = _failures.is_empty()


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[Step2aSmoke] FAIL: %s" % message)


func _finish() -> void:
	_print_report()
	quit(1 if not _failures.is_empty() else 0)


func _print_report() -> void:
	var overall: String = "PASS"
	if not _failures.is_empty():
		overall = "FAIL"
	elif not _notes.is_empty():
		overall = "PASS WITH NOTES"

	print("")
	print("=== Step 2a Mini-SmokeTest Result ===")
	print("Overall: %s" % overall)
	print("Godot CLI: (see host runner)")
	print("Failures: %d" % _failures.size())
	for msg: String in _failures:
		print("  FAIL: %s" % msg)
	for note: String in _notes:
		print("  NOTE: %s" % note)
	print("===================================")
