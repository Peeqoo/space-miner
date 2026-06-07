## Debug-only Balance Telemetry Logger — Space Miner v0.1
## ─────────────────────────────────────────────────────────────────────────────
## Records structured game-state snapshots to user://balance_runs/*.json during
## normal play for post-hoc balance analysis.
##
## Active ONLY when OS.is_debug_build() is true.
## GameSession adds this as a child in debug builds only.  No effect in release.
##
## Hotkeys (debug only):
##   F9  — start run  /  stop + save run
##   F10 — manual snapshot while running
##   F11 — save current run (without stopping)
##
## Reads all game state read-only.  Never mutates gameplay state.
class_name BalanceTelemetryLogger
extends Node

# ── Constants ─────────────────────────────────────────────────────────────────

const SCHEMA: String = "balance_telemetry_v1"
const OUTPUT_DIR: String = "user://balance_runs"
const DEFAULT_SNAPSHOT_INTERVAL: float = 60.0
const MILESTONE_CHECK_INTERVAL: float = 2.0

## Seconds and display names for auto timed-checkpoints.
const CHECKPOINT_SECONDS: Array[float] = [600.0, 1200.0, 1800.0, 2100.0, 2700.0]
const CHECKPOINT_NAMES: Array[String] = ["10_min", "20_min", "30_min", "35_min", "45_min"]

## Resources always logged even if zero.
const CORE_RESOURCE_IDS: Array[String] = [
	"Iron", "Silicon", "Copper", "Carbon", "Water",
	"Ice", "Aluminium", "Hydrogen", "SurveyData",
]

# ── Run state ─────────────────────────────────────────────────────────────────

var _running: bool = false
var _label: String = "balance_run"
var _started_at_unix: int = 0
var _elapsed: float = 0.0
var _since_last_interval: float = 0.0
var _since_last_milestone_check: float = 0.0
var _snapshot_interval: float = DEFAULT_SNAPSHOT_INTERVAL
var _next_checkpoint_idx: int = 0
var _snapshots: Array = []
var _milestone_times: Dictionary = {}
var _milestones_recorded: Dictionary = {}
var _first_storage_full_elapsed: float = -1.0

# ── Milestone prev-state (for transition detection) ───────────────────────────

var _prev_scan_drone_count: int = -1
var _prev_mining_ship_count: int = -1
var _prev_survey_probe_count: int = -1
var _prev_colony_ship_count: int = -1
var _prev_storage_upgrade_level: int = -1
var _prev_scan_drone_upgrade_level: int = -1
var _prev_mining_ship_upgrade_level: int = -1
var _prev_basic_scan_count: int = -1
var _prev_deep_scan_count: int = -1
var _prev_storage_full: bool = false
var _prev_sd_buildable: bool = false
var _prev_ms_buildable: bool = false
var _prev_sp_buildable: bool = false
var _prev_cs_affordable: bool = false
var _prev_storage_upgrade_buyable: bool = false
var _prev_sd_upgrade_buyable: bool = false
var _prev_ms_upgrade_buyable: bool = false
var _prev_sensor_pulse_can_start: bool = false
var _prev_active_mining_count: int = -1
var _prev_colonization_pending: bool = false
var _prev_established_base_count: int = -1
var _prev_current_system_id: String = ""
var _prev_storage_used: int = -1
var _prev_resource_iron: int = -1
var _prev_mining_unloading_count: int = 0
var _prev_mining_to_base_count: int = 0
var _mining_had_active_job: bool = false

# ── Cached scene-controller refs (invalidated on system change) ───────────────

var _automation_ctrl: AutomationController = null
var _survey_probe_ctrl: SurveyProbeMissionController = null
var _sensor_pulse_ctrl: BaseSensorPulseController = null


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

## Starts a new balance run.  Clears all previous run data.
func start_run(label: String = "balance_run") -> void:
	if not OS.is_debug_build():
		return
	var clean: String = label.strip_edges()
	_label = clean if not clean.is_empty() else "balance_run"
	_running = true
	_started_at_unix = int(Time.get_unix_time_from_system())
	_elapsed = 0.0
	_since_last_interval = 0.0
	_since_last_milestone_check = 0.0
	_next_checkpoint_idx = 0
	_snapshots.clear()
	_milestone_times.clear()
	_milestones_recorded.clear()
	_first_storage_full_elapsed = -1.0
	_reset_milestone_tracking()
	_capture_run_baseline()
	_invalidate_ctrl_cache()
	set_process(true)
	record_snapshot("run_start")
	print_debug(
		"[BalanceTelemetry] Run started: '%s' (unix=%d)  F9=stop+save | F10=snap | F11=save"
		% [_label, _started_at_unix]
	)


## Stops the run and records a final snapshot.  Call save_run() to persist.
func stop_run() -> void:
	if not _running:
		return
	record_snapshot("run_stop")
	_running = false
	set_process(false)
	print_debug(
		"[BalanceTelemetry] Run stopped at %.1f s (%.1f min)." % [_elapsed, _elapsed / 60.0]
	)


## Records a full state snapshot labelled event_name.
func record_snapshot(event_name: String = "manual", notes: String = "") -> void:
	if not OS.is_debug_build() or not _running:
		return
	_snapshots.append(_build_snapshot(event_name, notes))
	print_debug("[BalanceTelemetry] Snapshot '%s' @ %.0f s" % [event_name, _elapsed])


## Records a named milestone and a snapshot at that moment.
func record_marker(event_name: String, notes: String = "") -> void:
	if not OS.is_debug_build() or not _running:
		return
	_record_milestone_once(event_name)
	record_snapshot(event_name, notes)


## Writes all snapshots to disk.  Returns the output path (empty on failure).
func save_run() -> String:
	if not OS.is_debug_build():
		return ""
	if _snapshots.is_empty():
		print_debug("[BalanceTelemetry] Nothing to save.")
		return ""
	_ensure_output_dir()
	var fname: String = "%s_%s.json" % [_label, _format_timestamp()]
	var path: String = "%s/%s" % [OUTPUT_DIR, fname]
	var payload: Dictionary = {
		"schema": SCHEMA,
		"label": _label,
		"started_at_unix": _started_at_unix,
		"engine": "Godot 4.6.1",
		"snapshots": _snapshots,
		"milestone_times": _milestone_times,
	}
	var fa: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		push_warning("[BalanceTelemetry] Cannot write to '%s' (error %d)." % [path, FileAccess.get_open_error()])
		return ""
	fa.store_string(JSON.stringify(payload, "\t"))
	fa.close()
	_print_summary(path)
	return path


func is_running() -> bool:
	return _running


## Overrides the automatic snapshot interval (minimum 5 s).
func set_snapshot_interval(seconds: float) -> void:
	_snapshot_interval = maxf(5.0, seconds)


# ══════════════════════════════════════════════════════════════════════════════
# Node lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(OS.is_debug_build())
	if OS.is_debug_build():
		print_debug("[BalanceTelemetry] Ready — F9 start/stop | F10 snapshot | F11 save")


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_since_last_interval += delta
	_since_last_milestone_check += delta

	# Timed checkpoint (10 / 20 / 30 / 35 / 45 min)
	if _next_checkpoint_idx < CHECKPOINT_SECONDS.size():
		if _elapsed >= CHECKPOINT_SECONDS[_next_checkpoint_idx]:
			var cp: String = CHECKPOINT_NAMES[_next_checkpoint_idx]
			_next_checkpoint_idx += 1
			record_snapshot(cp)

	# Regular interval snapshot
	if _since_last_interval >= _snapshot_interval:
		_since_last_interval = 0.0
		record_snapshot("interval")

	# Milestone detection — throttled to avoid per-frame cost
	if _since_last_milestone_check >= MILESTONE_CHECK_INTERVAL:
		_since_last_milestone_check = 0.0
		_check_milestones()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	match ke.keycode:
		KEY_F9:
			if _running:
				stop_run()
				var p: String = save_run()
				print_debug("[BalanceTelemetry] F9 → stopped + saved: %s" % p)
			else:
				start_run("manual_balance_run")
		KEY_F10:
			if _running:
				record_snapshot("manual_marker")
			else:
				print_debug("[BalanceTelemetry] F10: no active run — press F9 to start.")
		KEY_F11:
			if not _snapshots.is_empty():
				var p: String = save_run()
				print_debug("[BalanceTelemetry] F11 → saved: %s" % p)
			else:
				print_debug("[BalanceTelemetry] F11: nothing to save yet.")


# ══════════════════════════════════════════════════════════════════════════════
# Snapshot root builder
# ══════════════════════════════════════════════════════════════════════════════

func _build_snapshot(event_name: String, notes: String) -> Dictionary:
	var base_id: String = _get_primary_base_id()
	var system_id: String = GameSession.current_system_id.strip_edges()
	return {
		"schema": SCHEMA,
		"run_id": _label,
		"elapsed_seconds": snappedf(_elapsed, 0.1),
		"event_name": event_name,
		"notes": notes,
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"current_system_id": system_id,
		"base_id": base_id,
		"resources": _snap_resources(base_id),
		"storage": _snap_storage(base_id),
		"units": _snap_units(base_id),
		"production_gates": _snap_production_gates(base_id),
		"upgrade_gates": _snap_upgrade_gates(base_id),
		"investigate": _snap_investigate(base_id, system_id),
		"scan": _snap_scan(base_id, system_id),
		"sensor_pulse": _snap_sensor_pulse(base_id),
		"mining": _snap_mining(base_id),
		"colony": _snap_colony(base_id, system_id),
		"discovery": _snap_discovery(system_id),
		"automation": _snap_automation(base_id),
		"milestones_at_snapshot": _milestone_times.duplicate(true),
	}


# ══════════════════════════════════════════════════════════════════════════════
# Snapshot sections
# ══════════════════════════════════════════════════════════════════════════════

# ─── Resources ────────────────────────────────────────────────────────────────

func _snap_resources(base_id: String) -> Dictionary:
	var out: Dictionary = {}
	for rid: String in CORE_RESOURCE_IDS:
		out[rid] = 0
	if not GameSession.has_established_base(base_id):
		return out
	var stored: Dictionary = GameSession.get_base_resources(base_id)
	var extra: Dictionary = {}
	for k: Variant in stored.keys():
		var rid: String = str(k)
		var amount: int = int(stored[k])
		if CORE_RESOURCE_IDS.has(rid):
			out[rid] = amount
		else:
			extra[rid] = amount
	if not extra.is_empty():
		out["extra_resources"] = extra
	return out


# ─── Storage ──────────────────────────────────────────────────────────────────

func _snap_storage(base_id: String) -> Dictionary:
	if not GameSession.has_established_base(base_id):
		return {
			"storage_used": 0, "storage_capacity": 0, "storage_free": 0,
			"storage_percent": 0, "storage_full": false,
			"first_storage_full_elapsed": _first_storage_full_elapsed,
		}
	var used: int = GameSession.get_base_storage_used(base_id)
	var cap: int = GameSession.get_base_storage_capacity(base_id)
	var free_v: int = maxi(0, cap - used)
	var pct: int = int(round(float(used) / float(maxi(1, cap)) * 100.0))
	return {
		"storage_used": used,
		"storage_capacity": cap,
		"storage_free": free_v,
		"storage_percent": pct,
		"storage_full": GameSession.is_base_storage_full(base_id),
		"first_storage_full_elapsed": _first_storage_full_elapsed,
	}


# ─── Units ────────────────────────────────────────────────────────────────────

func _snap_units(base_id: String) -> Dictionary:
	var sp_snap: Dictionary = _survey_probe_inventory_snap(base_id)
	return {
		"scan_drone": {
			"count": GameSession.get_base_drone_count(base_id),
			"current_count": GameSession.get_base_drone_count(base_id),
			"lifetime_count": GameSession.get_production_lifetime_count(
				base_id, BaseStore.PRODUCTION_SCAN_DRONE
			),
			"balance_reference_max_count": GameSession.get_max_base_scan_drone_count(),
			"build_limit_active": false,
			"hard_limit_removed_for_build": true,
		},
		"mining_ship": {
			"count": GameSession.get_base_mining_ship_count(base_id),
			"current_count": GameSession.get_base_mining_ship_count(base_id),
			"lifetime_count": GameSession.get_production_lifetime_count(
				base_id, BaseStore.PRODUCTION_MINING_SHIP
			),
			"balance_reference_max_count": GameSession.get_max_base_mining_ship_count(),
			"build_limit_active": false,
			"hard_limit_removed_for_build": true,
		},
		"survey_probe": sp_snap,
		"colony_ship": {
			"count": GameSession.get_base_colony_ship_count(base_id),
			"lifetime_count": GameSession.get_production_lifetime_count(
				base_id, BaseStore.PRODUCTION_COLONY_SHIP
			),
		},
	}


# ─── Production gates ─────────────────────────────────────────────────────────

func _snap_production_gates(base_id: String) -> Dictionary:
	if not GameSession.has_established_base(base_id):
		return {"_status": "no_established_base"}
	var res: Dictionary = GameSession.get_base_resources(base_id)
	return {
		"scan_drone": _unit_gate_snap(
			GameSession.get_build_base_scan_drone_gate(base_id),
			res,
			BaseStore.PRODUCTION_SCAN_DRONE,
			base_id,
		),
		"mining_ship": _unit_gate_snap(
			GameSession.get_build_base_mining_ship_gate(base_id),
			res,
			BaseStore.PRODUCTION_MINING_SHIP,
			base_id,
		),
		"survey_probe": _unit_gate_snap(
			GameSession.get_build_base_survey_probe_gate(base_id),
			res,
			BaseStore.PRODUCTION_SURVEY_PROBE,
			base_id,
		),
		"colony_ship": _colony_gate_snap(base_id, res),
	}


func _unit_gate_snap(
	gate: Dictionary,
	resources: Dictionary,
	production_id: String,
	base_id: String,
) -> Dictionary:
	var spend_cost: Dictionary = GameSession.get_scaled_production_cost(production_id, base_id)
	var info: Dictionary = GameSession.get_scaled_production_cost_preview_info(production_id, base_id)
	var base_cost_v: Variant = info.get("base_cost", {})
	var base_cost: Dictionary = {}
	if base_cost_v is Dictionary:
		base_cost = (base_cost_v as Dictionary).duplicate(true)
	return {
		"can_build": bool(gate.get("ok", false)),
		"blocked_reason": str(gate.get("blocked_reason", "")),
		"blocked_reason_key": str(gate.get("blocked_reason_key", "")),
		"cost": spend_cost.duplicate(true),
		"base_cost": base_cost,
		"cost_gap": _build_cost_gap(spend_cost, resources),
		"scaled_preview": _scaled_preview_snap(production_id, base_id),
	}


func _scaled_preview_snap(production_id: String, base_id: String) -> Dictionary:
	var info: Dictionary = GameSession.get_scaled_production_cost_preview_info(production_id, base_id)
	var out: Dictionary = {
		"built_count": int(info.get("built_count", 0)),
		"multiplier": float(info.get("multiplier", 1.0)),
		"base_cost": {},
		"scaled_cost": {},
		"used_for_gameplay": bool(info.get("used_for_gameplay", false)),
	}
	var base_v: Variant = info.get("base_cost", {})
	if base_v is Dictionary:
		out["base_cost"] = (base_v as Dictionary).duplicate(true)
	var scaled_v: Variant = info.get("scaled_cost", {})
	if scaled_v is Dictionary:
		out["scaled_cost"] = (scaled_v as Dictionary).duplicate(true)
	var count_source: String = str(info.get("count_source", "")).strip_edges()
	if not count_source.is_empty():
		out["count_source"] = count_source
	out["lifetime_count"] = int(info.get("lifetime_count", out["built_count"]))
	out["current_owned_count"] = int(info.get("current_owned_count", 0))
	return out


func _colony_gate_snap(base_id: String, resources: Dictionary) -> Dictionary:
	var gate: Dictionary = GameSession.get_build_base_colony_ship_gate(base_id)
	var cs_cost: Dictionary = GameSession.get_colony_ship_build_cost()
	var prereqs_out: Array = []
	var prereqs_var: Variant = gate.get("prerequisites", [])
	if prereqs_var is Array:
		for pv: Variant in (prereqs_var as Array):
			if not (pv is Dictionary):
				continue
			var p: Dictionary = pv as Dictionary
			prereqs_out.append({
				"id": str(p.get("id", "")),
				"label": str(p.get("label", "")),
				"met": bool(p.get("met", false)),
				"blocked_reason": str(p.get("blocked_reason", "")),
			})
	return {
		"can_build": bool(gate.get("ok", false)),
		"blocked_reason": str(gate.get("blocked_reason", "")),
		"blocked_reason_key": str(gate.get("blocked_reason_key", "")),
		"cost": cs_cost.duplicate(true),
		"cost_gap": _build_cost_gap(cs_cost, resources),
		"prerequisites": prereqs_out,
		"scaling_excluded": true,
	}


# ─── Upgrade gates ────────────────────────────────────────────────────────────

func _snap_upgrade_gates(base_id: String) -> Dictionary:
	if not GameSession.has_established_base(base_id):
		return {"_status": "no_established_base"}
	var res: Dictionary = GameSession.get_base_resources(base_id)
	return {
		"storage": _upgrade_gate_snap(base_id, &"storage", res),
		"scan_drone": _upgrade_gate_snap(base_id, &"scan_drone", res),
		"mining_ship": _upgrade_gate_snap(base_id, &"mining_ship", res),
	}


func _upgrade_gate_snap(base_id: String, category: StringName, resources: Dictionary) -> Dictionary:
	var gate: Dictionary = GameSession.get_buy_next_base_upgrade_gate(base_id, category)
	var cur_level: int = GameSession.get_base_upgrade_level(base_id, category)
	var has_next: bool = GameSession.has_next_base_upgrade(base_id, category)
	var upgrade_cost: Dictionary = {}
	if has_next:
		var nd: UpgradeDefinition = GameSession.get_next_upgrade_definition(base_id, category)
		if nd != null:
			var cv: Variant = nd.get("cost")
			if cv is Dictionary:
				upgrade_cost = (cv as Dictionary).duplicate(true)
	return {
		"current_level": cur_level,
		"has_next_level": has_next,
		"can_buy": bool(gate.get("ok", false)),
		"blocked_reason": str(gate.get("blocked_reason", "")),
		"blocked_reason_key": str(gate.get("blocked_reason_key", "")),
		"next_upgrade_cost": upgrade_cost,
		"cost_gap": _build_cost_gap(upgrade_cost, resources),
	}


# ─── Investigate / SurveyProbe ────────────────────────────────────────────────

func _snap_investigate(base_id: String, system_id: String) -> Dictionary:
	var sp_snap: Dictionary = _survey_probe_inventory_snap(base_id)
	var disc_counts: Array[int] = _get_discovery_counts(system_id)

	var sp_gate: Dictionary = {}
	var sp_cost: Dictionary = {}
	var sp_base_cost: Dictionary = {}
	var sp_gap: Dictionary = {}
	var sp_scaled_preview: Dictionary = {}
	if GameSession.has_established_base(base_id):
		var resources: Dictionary = GameSession.get_base_resources(base_id)
		sp_gate = GameSession.get_build_base_survey_probe_gate(base_id)
		sp_cost = GameSession.get_scaled_production_cost(
			BaseStore.PRODUCTION_SURVEY_PROBE, base_id
		)
		sp_gap = _build_cost_gap(sp_cost, resources)
		var sp_info: Dictionary = GameSession.get_scaled_production_cost_preview_info(
			BaseStore.PRODUCTION_SURVEY_PROBE, base_id
		)
		var base_cost_v: Variant = sp_info.get("base_cost", {})
		if base_cost_v is Dictionary:
			sp_base_cost = (base_cost_v as Dictionary).duplicate(true)
		sp_scaled_preview = _scaled_preview_snap(BaseStore.PRODUCTION_SURVEY_PROBE, base_id)

	var out: Dictionary = sp_snap.duplicate(true)
	out["active_investigate_count"] = sp_snap.get("survey_probe_active_deployed", "unknown")
	out["hidden_count_in_system"] = disc_counts[0]
	out["signal_count_in_system"] = disc_counts[1]
	out["known_count_in_system"] = disc_counts[2]
	out["survey_probe_gate"] = {
		"can_build": bool(sp_gate.get("ok", false)),
		"blocked_reason": str(sp_gate.get("blocked_reason", "")),
		"blocked_reason_key": str(sp_gate.get("blocked_reason_key", "")),
	}
	out["survey_probe_cost"] = sp_cost.duplicate(true)
	out["survey_probe_base_cost"] = sp_base_cost.duplicate(true)
	out["survey_probe_cost_gap"] = sp_gap
	out["survey_probe_scaled_preview"] = sp_scaled_preview.duplicate(true)
	out["milestone_first_signal_revealed"] = _milestone_times.get("first_signal_revealed", -1.0)
	out["milestone_first_investigate_started"] = _milestone_times.get("first_investigate_started", -1.0)
	out["milestone_first_object_revealed"] = _milestone_times.get("first_object_revealed", -1.0)
	return out


# ─── Scan / ScanDrone ─────────────────────────────────────────────────────────

func _snap_scan(base_id: String, system_id: String) -> Dictionary:
	var scan_counts: Array[int] = _get_scan_counts(system_id)

	var active_scan_jobs: Variant = "unknown"
	var ac: AutomationController = _find_automation_ctrl()
	if ac != null and is_instance_valid(ac):
		active_scan_jobs = ac.get_active_scan_job_count_for_session_base(base_id)

	var sd_gate: Dictionary = {}
	var sd_ug: Dictionary = {}
	var sd_level: int = 0
	if GameSession.has_established_base(base_id):
		sd_gate = GameSession.get_build_base_scan_drone_gate(base_id)
		sd_ug = GameSession.get_buy_next_base_upgrade_gate(base_id, &"scan_drone")
		sd_level = GameSession.get_base_upgrade_level(base_id, &"scan_drone")

	return {
		"scan_drone_count": GameSession.get_base_drone_count(base_id),
		"scan_drone_upgrade_level": sd_level,
		"active_scan_jobs": active_scan_jobs,
		"basic_scanned_count": scan_counts[0],
		"deep_scanned_count": scan_counts[1],
		"scan_drone_gate": {
			"can_build": bool(sd_gate.get("ok", false)),
			"blocked_reason": str(sd_gate.get("blocked_reason", "")),
			"blocked_reason_key": str(sd_gate.get("blocked_reason_key", "")),
		},
		"scan_drone_upgrade_gate": {
			"can_buy": bool(sd_ug.get("ok", false)),
			"blocked_reason": str(sd_ug.get("blocked_reason", "")),
		},
		"milestones": {
			"first_basic_scan_done": _milestone_times.get("first_basic_scan_done", -1.0),
			"first_deep_scan_done": _milestone_times.get("first_deep_scan_done", -1.0),
			"three_deep_scans_done": _milestone_times.get("three_deep_scans_done", -1.0),
		},
	}


# ─── SensorPulse ──────────────────────────────────────────────────────────────

func _snap_sensor_pulse(base_id: String) -> Dictionary:
	var spc: BaseSensorPulseController = _find_sensor_pulse_ctrl()
	if spc == null or not is_instance_valid(spc):
		return {
			"sensor_pulse_available": "unknown",
			"sensor_pulse_active": "unknown",
			"sensor_pulse_progress": "unknown",
			"sensor_pulse_blocked_reason": "unknown",
			"sensor_pulse_cost": {},
			"sensor_pulse_cost_gap": {},
			"cooldown_state": "unknown",
			"milestone_first_used": _milestone_times.get("sensor_pulse_used", -1.0),
		}
	var can_pulse: Dictionary = spc.can_start_sensor_pulse(base_id)
	var ok: bool = bool(can_pulse.get("ok", false))
	var br: String = str(can_pulse.get("blocked_reason", ""))
	var is_active: bool = spc.is_pulse_active()
	var cooldown_state: String
	if is_active:
		cooldown_state = "active"
	elif ok:
		cooldown_state = "ready"
	elif "cooldown" in br.to_lower():
		cooldown_state = "cooldown"
	else:
		cooldown_state = "blocked"

	# Cost via GameBalance (mirrors BaseSensorPulseController._pulse_cost_dictionary)
	var balance: GameBalanceDefinition = GameSession.get_game_balance()
	var pulse_cost: Dictionary = {}
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		pulse_cost = balance.base_sensor_pulse_cost.duplicate(true)
	else:
		pulse_cost = {"SurveyData": 5}

	var cost_gap: Dictionary = {}
	if GameSession.has_established_base(base_id):
		cost_gap = _build_cost_gap(pulse_cost, GameSession.get_base_resources(base_id))

	return {
		"sensor_pulse_available": ok,
		"sensor_pulse_active": is_active,
		"sensor_pulse_progress": spc.get_pulse_progress(),
		"sensor_pulse_blocked_reason": br,
		"sensor_pulse_cost": pulse_cost,
		"sensor_pulse_cost_gap": cost_gap,
		"cooldown_state": cooldown_state,
		"milestone_first_used": _milestone_times.get("sensor_pulse_used", -1.0),
	}


# ─── Mining / MiningShip ──────────────────────────────────────────────────────

func _snap_mining(base_id: String) -> Dictionary:
	var ms_gate: Dictionary = {}
	var ms_ug: Dictionary = {}
	var ms_level: int = 0
	if GameSession.has_established_base(base_id):
		ms_gate = GameSession.get_build_base_mining_ship_gate(base_id)
		ms_ug = GameSession.get_buy_next_base_upgrade_gate(base_id, &"mining_ship")
		ms_level = GameSession.get_base_upgrade_level(base_id, &"mining_ship")

	var ac: AutomationController = _find_automation_ctrl()
	if ac == null or not is_instance_valid(ac):
		return {
			"mining_ship_count": GameSession.get_base_mining_ship_count(base_id),
			"mining_ship_upgrade_level": ms_level,
			"active_mining_jobs": "unknown",
			"storage_waiting_count": 0,
			"mining_ship_gate": {
				"can_build": bool(ms_gate.get("ok", false)),
				"blocked_reason": str(ms_gate.get("blocked_reason", "")),
			},
			"mining_ship_upgrade_gate": {
				"can_buy": bool(ms_ug.get("ok", false)),
				"blocked_reason": str(ms_ug.get("blocked_reason", "")),
			},
			"mining_status_breakdown": {},
			"active_mining_details": [],
			"milestones": _mining_milestones_dict(),
		}

	var active_jobs: int = ac.get_active_mining_job_count_for_session_base(base_id)
	var storage_waiting: int = 0
	var breakdown: Dictionary = {
		"to_target": 0, "mining": 0, "to_base": 0,
		"unloading": 0, "waiting_for_storage": 0,
	}
	var details: Array = []

	for uid_v: Variant in ac.mining_ship_runtime_by_unit_id.keys():
		var rt_v: Variant = ac.mining_ship_runtime_by_unit_id.get(uid_v)
		if not (rt_v is Dictionary):
			continue
		var rt: Dictionary = rt_v as Dictionary
		var status: int = int(rt.get("status", -1))
		var sname: String = _mining_status_name(status)
		if breakdown.has(sname):
			breakdown[sname] = int(breakdown[sname]) + 1
		if status == 4:
			storage_waiting += 1
		var cargo: Dictionary = {}
		var cv: Variant = rt.get("cargo_resources")
		if cv is Dictionary:
			cargo = _sanitize_cargo(cv as Dictionary)
		var detail: Dictionary = {
			"target_id": str(rt.get("target_id", "")),
			"status_name": sname,
			"loop_active": bool(rt.get("loop_active", false)),
			"cargo_resources": cargo,
			"current_cargo": snappedf(float(rt.get("current_cargo", 0.0)), 0.1),
			"cargo_capacity": int(rt.get("cargo_capacity", 0)),
			"blocked_reason": "",
		}
		if status == 4:
			detail["blocked_reason"] = str(rt.get("blocked_reason", ""))
		details.append(detail)

	return {
		"mining_ship_count": GameSession.get_base_mining_ship_count(base_id),
		"mining_ship_upgrade_level": ms_level,
		"active_mining_jobs": active_jobs,
		"storage_waiting_count": storage_waiting,
		"mining_ship_gate": {
			"can_build": bool(ms_gate.get("ok", false)),
			"blocked_reason": str(ms_gate.get("blocked_reason", "")),
			"blocked_reason_key": str(ms_gate.get("blocked_reason_key", "")),
		},
		"mining_ship_upgrade_gate": {
			"can_buy": bool(ms_ug.get("ok", false)),
			"blocked_reason": str(ms_ug.get("blocked_reason", "")),
		},
		"mining_status_breakdown": breakdown,
		"active_mining_details": details,
		"milestones": _mining_milestones_dict(),
	}


func _mining_milestones_dict() -> Dictionary:
	var delivery_elapsed: float = float(_milestone_times.get("first_delivery", -1.0))
	return {
		"first_mining_started": _milestone_times.get("first_mining_started", -1.0),
		"first_delivery": delivery_elapsed,
		"first_delivery_status": "detected" if delivery_elapsed >= 0.0 else "pending",
	}


# ─── Colony / ColonyShip ──────────────────────────────────────────────────────

func _snap_colony(base_id: String, system_id: String) -> Dictionary:
	var eb_count: int = _count_established_bases()
	var pending_ops: int = GameSession.get_pending_colonization_operations().size()

	if not GameSession.has_established_base(base_id):
		return {
			"colony_ship_count": 0,
			"colony_ship_buildable": false,
			"colony_ship_blocked_reason": "no_established_base",
			"colony_ship_cost": {},
			"colony_ship_cost_gap": {},
			"prerequisites": [],
			"has_established_base_in_current_system": GameSession.has_established_base_in_system(system_id),
			"established_base_count": eb_count,
			"established_base_count_notes": (
				"All bases with GameSession.has_established_base (includes Earth start base)."
			),
			"pending_colonization_operations": pending_ops,
			"milestones": _colony_milestones_dict(),
		}

	var gate: Dictionary = GameSession.get_build_base_colony_ship_gate(base_id)
	var cs_cost: Dictionary = GameSession.get_colony_ship_build_cost()
	var res: Dictionary = GameSession.get_base_resources(base_id)

	var prereqs_out: Array = []
	var pv: Variant = gate.get("prerequisites", [])
	if pv is Array:
		for item: Variant in (pv as Array):
			if not (item is Dictionary):
				continue
			var p: Dictionary = item as Dictionary
			prereqs_out.append({
				"id": str(p.get("id", "")),
				"label": str(p.get("label", "")),
				"met": bool(p.get("met", false)),
				"blocked_reason": str(p.get("blocked_reason", "")),
			})

	return {
		"colony_ship_count": GameSession.get_base_colony_ship_count(base_id),
		"colony_ship_buildable": bool(gate.get("ok", false)),
		"colony_ship_blocked_reason": str(gate.get("blocked_reason", "")),
		"colony_ship_blocked_reason_key": str(gate.get("blocked_reason_key", "")),
		"colony_ship_cost": cs_cost.duplicate(true),
		"colony_ship_cost_gap": _build_cost_gap(cs_cost, res),
		"prerequisites": prereqs_out,
		"has_established_base_in_current_system": GameSession.has_established_base_in_system(system_id),
		"established_base_count": eb_count,
		"established_base_count_notes": (
			"All bases with GameSession.has_established_base (includes Earth start base)."
		),
		"pending_colonization_operations": pending_ops,
		"milestones": _colony_milestones_dict(),
	}


func _colony_milestones_dict() -> Dictionary:
	return {
		"colony_ship_affordable_elapsed": _milestone_times.get("colony_ship_affordable", -1.0),
		"colony_ship_built_elapsed": _milestone_times.get("colony_ship_built", -1.0),
		"colonization_started_elapsed": _milestone_times.get("colonization_started", -1.0),
		"colonization_completed_elapsed": _milestone_times.get("colonization_completed", -1.0),
		"new_system_entered_elapsed": _milestone_times.get("new_system_entered", -1.0),
	}


# ─── Discovery / System Progression ──────────────────────────────────────────

func _snap_discovery(system_id: String) -> Dictionary:
	var disc: Array[int] = _get_discovery_counts(system_id)
	var scan: Array[int] = _get_scan_counts(system_id)

	var body_resources: Array = []
	if not system_id.is_empty():
		var sys_def: SystemDefinition = GameSession.current_system_definition
		if sys_def != null:
			for bv: Variant in sys_def.bodies:
				var body: SystemBodyDefinition = bv as SystemBodyDefinition
				if body == null:
					continue
				var oid: String = body.id.strip_edges()
				if oid.is_empty():
					continue
				var ds: String = GameSession.get_object_discovery_state(system_id, oid)
				var ss: String = GameSession.get_object_scan_state(system_id, oid)
				if ds != GameSession.DISCOVERY_KNOWN:
					continue
				if ss == GameSession.SCAN_UNKNOWN:
					continue
				var visible_rids: Array[String] = []
				for ev: Variant in body.get_basic_scan_resources():
					var entry: ScannedResourceEntry = ev as ScannedResourceEntry
					if entry != null:
						visible_rids.append(str(entry.resource_id))
				if GameSession.scan_state_rank(ss) >= GameSession.scan_state_rank(GameSession.SCAN_DEEP):
					for ev: Variant in body.get_deep_scan_resources():
						var entry: ScannedResourceEntry = ev as ScannedResourceEntry
						if entry != null:
							visible_rids.append(str(entry.resource_id))
				body_resources.append({
					"body_id": oid,
					"scan_state": ss,
					"visible_resource_ids": visible_rids,
				})

	return {
		"current_system_id": system_id,
		"objects_hidden_count": disc[0],
		"objects_signal_count": disc[1],
		"objects_known_count": disc[2],
		"objects_basic_scanned_count": scan[0],
		"objects_deep_scanned_count": scan[1],
		"established_base_count": _count_established_bases(),
		"established_base_count_notes": (
			"All bases with GameSession.has_established_base (includes Earth start base)."
		),
		"discovered_system_count": GameSession.discovered_system_ids.size(),
		"unlocked_system_count": GameSession.unlocked_system_ids.size(),
		"known_body_resources": body_resources,
	}


# ─── Automation / Active Runtime ──────────────────────────────────────────────

func _snap_automation(base_id: String) -> Dictionary:
	var pending_ops: int = GameSession.get_pending_colonization_operations().size()
	var ac: AutomationController = _find_automation_ctrl()
	var spc: SurveyProbeMissionController = _find_survey_probe_ctrl()

	var active_scan: Variant = "unknown"
	var active_mining: Variant = "unknown"
	var active_investigate: Variant = "unknown"
	var storage_waiting: int = 0
	var breakdown: Dictionary = {
		"to_target": 0, "mining": 0, "to_base": 0,
		"unloading": 0, "waiting_for_storage": 0,
	}

	if ac != null and is_instance_valid(ac):
		active_scan = ac.get_active_scan_job_count_for_session_base(base_id)
		active_mining = ac.get_active_mining_job_count_for_session_base(base_id)
		for uid_v: Variant in ac.mining_ship_runtime_by_unit_id.keys():
			var rt_v: Variant = ac.mining_ship_runtime_by_unit_id.get(uid_v)
			if not (rt_v is Dictionary):
				continue
			var rt: Dictionary = rt_v as Dictionary
			var status: int = int(rt.get("status", -1))
			var sname: String = _mining_status_name(status)
			if breakdown.has(sname):
				breakdown[sname] = int(breakdown[sname]) + 1
			if status == 4:
				storage_waiting += 1

	if spc != null and is_instance_valid(spc):
		active_investigate = spc.get_active_investigate_count()

	return {
		"active_scan_jobs": active_scan,
		"active_mining_jobs": active_mining,
		"active_investigate_jobs": active_investigate,
		"storage_waiting_count": storage_waiting,
		"pending_colonization_operations": pending_ops,
		"mining_status_breakdown": breakdown,
	}


# ══════════════════════════════════════════════════════════════════════════════
# Milestone detection  (runs every MILESTONE_CHECK_INTERVAL seconds)
# ══════════════════════════════════════════════════════════════════════════════

func _check_milestones() -> void:
	var base_id: String = _get_primary_base_id()
	var has_base: bool = GameSession.has_established_base(base_id)
	var system_id: String = GameSession.current_system_id.strip_edges()

	# ── Fleet ──────────────────────────────────────────────────────────────────
	var sd_n: int = GameSession.get_base_drone_count(base_id)
	var ms_n: int = GameSession.get_base_mining_ship_count(base_id)
	var sp_n: int = GameSession.bases.get_survey_probe_count(base_id) if has_base else 0
	var cs_n: int = GameSession.get_base_colony_ship_count(base_id)

	if (
		sd_n >= 2
		and _prev_scan_drone_count >= 0
		and sd_n > _prev_scan_drone_count
		and _prev_scan_drone_count < 2
	):
		_record_milestone_once("scan_drone_2_built")
	if (
		ms_n >= 2
		and _prev_mining_ship_count >= 0
		and ms_n > _prev_mining_ship_count
		and _prev_mining_ship_count < 2
	):
		_record_milestone_once("mining_ship_2_built")
	if sp_n > _prev_survey_probe_count and _prev_survey_probe_count >= 0:
		_record_milestone_once("survey_probe_built")
	if cs_n > _prev_colony_ship_count and _prev_colony_ship_count >= 0:
		_record_milestone_once("colony_ship_built")

	_prev_scan_drone_count = sd_n
	_prev_mining_ship_count = ms_n
	_prev_survey_probe_count = sp_n
	_prev_colony_ship_count = cs_n

	# ── Build affordability ────────────────────────────────────────────────────
	if has_base:
		var sd_ok: bool = bool(GameSession.get_build_base_scan_drone_gate(base_id).get("ok", false))
		var ms_ok: bool = bool(GameSession.get_build_base_mining_ship_gate(base_id).get("ok", false))
		var sp_ok: bool = bool(GameSession.get_build_base_survey_probe_gate(base_id).get("ok", false))
		var cs_ok: bool = bool(GameSession.get_build_base_colony_ship_gate(base_id).get("ok", false))

		if sd_ok and not _prev_sd_buildable:
			_record_milestone_once("scan_drone_affordable")
		if ms_ok and not _prev_ms_buildable:
			_record_milestone_once("mining_ship_affordable")
		if sp_ok and not _prev_sp_buildable:
			_record_milestone_once("survey_probe_affordable")
		if cs_ok and not _prev_cs_affordable:
			_record_milestone_once("colony_ship_affordable")

		_prev_sd_buildable = sd_ok
		_prev_ms_buildable = ms_ok
		_prev_sp_buildable = sp_ok
		_prev_cs_affordable = cs_ok

	# ── Upgrades ──────────────────────────────────────────────────────────────
	if has_base:
		var s_lvl: int = GameSession.get_base_upgrade_level(base_id, &"storage")
		var sd_lvl: int = GameSession.get_base_upgrade_level(base_id, &"scan_drone")
		var ms_lvl: int = GameSession.get_base_upgrade_level(base_id, &"mining_ship")

		var any_now: bool = s_lvl > 0 or sd_lvl > 0 or ms_lvl > 0
		var any_prev: bool = _prev_storage_upgrade_level > 0 or _prev_scan_drone_upgrade_level > 0 or _prev_mining_ship_upgrade_level > 0
		if any_now and not any_prev:
			_record_milestone_once("first_upgrade_bought")

		if s_lvl >= 1 and _prev_storage_upgrade_level < 1:
			_record_milestone_once("storage_upgrade_1_bought")
		if sd_lvl >= 1 and _prev_scan_drone_upgrade_level < 1:
			_record_milestone_once("scan_drone_upgrade_1_bought")
			_record_milestone_once("deep_scan_unlocked")
		if ms_lvl >= 1 and _prev_mining_ship_upgrade_level < 1:
			_record_milestone_once("mining_upgrade_1_bought")

		# Upgrade buy affordability
		var s_ok: bool = bool(GameSession.get_buy_next_base_upgrade_gate(base_id, &"storage").get("ok", false))
		var sd_ok: bool = bool(GameSession.get_buy_next_base_upgrade_gate(base_id, &"scan_drone").get("ok", false))
		var ms_ok: bool = bool(GameSession.get_buy_next_base_upgrade_gate(base_id, &"mining_ship").get("ok", false))

		if s_ok and not _prev_storage_upgrade_buyable:
			_record_milestone_once("first_upgrade_affordable")
		if sd_ok and not _prev_sd_upgrade_buyable:
			_record_milestone_once("scan_drone_upgrade_1_affordable")
		if ms_ok and not _prev_ms_upgrade_buyable:
			_record_milestone_once("mining_upgrade_1_affordable")

		_prev_storage_upgrade_buyable = s_ok
		_prev_sd_upgrade_buyable = sd_ok
		_prev_ms_upgrade_buyable = ms_ok
		_prev_storage_upgrade_level = s_lvl
		_prev_scan_drone_upgrade_level = sd_lvl
		_prev_mining_ship_upgrade_level = ms_lvl

	# ── Resource thresholds ────────────────────────────────────────────────────
	if has_base:
		if GameSession.get_base_resource_amount(base_id, "Iron") >= 1500:
			_record_milestone_once("iron_1500_reached")
		if GameSession.get_base_resource_amount(base_id, "Silicon") >= 300:
			_record_milestone_once("silicon_300_reached")
		if GameSession.get_base_resource_amount(base_id, "Water") >= 350:
			_record_milestone_once("water_350_reached")
		if GameSession.get_base_resource_amount(base_id, "SurveyData") >= 150:
			_record_milestone_once("surveydata_150_reached")

	# ── Storage full ──────────────────────────────────────────────────────────
	if has_base:
		var full: bool = GameSession.is_base_storage_full(base_id)
		if full and not _prev_storage_full:
			_record_milestone_once("storage_full")
			if _first_storage_full_elapsed < 0.0:
				_first_storage_full_elapsed = _elapsed
		_prev_storage_full = full

	# ── Sensor pulse ──────────────────────────────────────────────────────────
	var spc_ref: BaseSensorPulseController = _find_sensor_pulse_ctrl()
	if spc_ref != null and is_instance_valid(spc_ref):
		var pulse_ok: bool = bool(spc_ref.can_start_sensor_pulse(base_id).get("ok", false))
		if pulse_ok and not _prev_sensor_pulse_can_start:
			_record_milestone_once("sensor_pulse_affordable")
		_prev_sensor_pulse_can_start = pulse_ok
		if spc_ref.is_pulse_active():
			_record_milestone_once("sensor_pulse_used")

	# ── Scan counts ────────────────────────────────────────────────────────────
	if not system_id.is_empty():
		var sc: Array[int] = _get_scan_counts(system_id)
		if sc[0] >= 1 and _prev_basic_scan_count <= 0:
			_record_milestone_once("first_basic_scan_done")
		if sc[1] >= 1 and _prev_deep_scan_count <= 0:
			_record_milestone_once("first_deep_scan_done")
		if sc[1] >= 3 and _prev_deep_scan_count < 3:
			_record_milestone_once("three_deep_scans_done")
		_prev_basic_scan_count = sc[0]
		_prev_deep_scan_count = sc[1]

	# ── Discovery signals ──────────────────────────────────────────────────────
	if not system_id.is_empty():
		var dc: Array[int] = _get_discovery_counts(system_id)
		if dc[1] >= 1:
			_record_milestone_once("first_signal_revealed")
		if dc[2] >= 3:
			_record_milestone_once("first_object_revealed")

	# ── Mining active / delivery ───────────────────────────────────────────────
	var ac: AutomationController = _find_automation_ctrl()
	if ac != null and is_instance_valid(ac):
		var mn: int = ac.get_active_mining_job_count_for_session_base(base_id)
		if mn > 0 and _prev_active_mining_count <= 0:
			_record_milestone_once("first_mining_started")
		if mn > 0:
			_mining_had_active_job = true
		_prev_active_mining_count = mn

		var unloading_count: int = 0
		var to_base_count: int = 0
		for uid_v: Variant in ac.mining_ship_runtime_by_unit_id.keys():
			var rt_v: Variant = ac.mining_ship_runtime_by_unit_id.get(uid_v)
			if not (rt_v is Dictionary):
				continue
			var rt: Dictionary = rt_v as Dictionary
			var status: int = int(rt.get("status", -1))
			if status == 3:
				unloading_count += 1
			elif status == 2:
				to_base_count += 1

		if has_base and _mining_had_active_job and not _milestones_recorded.has("first_delivery"):
			var storage_used: int = GameSession.get_base_storage_used(base_id)
			var iron_now: int = GameSession.get_base_resource_amount(base_id, "Iron")
			var storage_increased: bool = (
				_prev_storage_used >= 0 and storage_used > _prev_storage_used
			)
			var iron_increased: bool = _prev_resource_iron >= 0 and iron_now > _prev_resource_iron
			# After mining started: storage/resource gain counts as delivery (checked every 2s).
			if storage_increased or iron_increased:
				_record_milestone_once("first_delivery")

			_prev_storage_used = storage_used
			_prev_resource_iron = iron_now

		_prev_mining_unloading_count = unloading_count
		_prev_mining_to_base_count = to_base_count
	elif has_base and _mining_had_active_job and not _milestones_recorded.has("first_delivery"):
		var storage_used_fb: int = GameSession.get_base_storage_used(base_id)
		var iron_fb: int = GameSession.get_base_resource_amount(base_id, "Iron")
		if _prev_storage_used >= 0 and storage_used_fb > _prev_storage_used:
			_record_milestone_once("first_delivery")
		elif _prev_resource_iron >= 0 and iron_fb > _prev_resource_iron:
			_record_milestone_once("first_delivery")
		_prev_storage_used = storage_used_fb
		_prev_resource_iron = iron_fb

	# ── Colonization ───────────────────────────────────────────────────────────
	var col_pending: bool = GameSession.has_pending_colonization_operations()
	if col_pending and not _prev_colonization_pending:
		_record_milestone_once("colonization_started")
	_prev_colonization_pending = col_pending

	var eb: int = _count_established_bases()
	if eb > _prev_established_base_count and _prev_established_base_count >= 1:
		_record_milestone_once("colonization_completed")
	_prev_established_base_count = eb

	# ── System change ──────────────────────────────────────────────────────────
	if not system_id.is_empty() and not _prev_current_system_id.is_empty():
		if system_id != _prev_current_system_id:
			_record_milestone_once("new_system_entered")
			_invalidate_ctrl_cache()
	_prev_current_system_id = system_id


func _record_milestone_once(milestone_id: String) -> void:
	if _milestones_recorded.has(milestone_id):
		return
	_milestones_recorded[milestone_id] = true
	_milestone_times[milestone_id] = snappedf(_elapsed, 0.1)
	print_debug(
		"[BalanceTelemetry] ★ %s @ %.1f s (%.1f min)" % [milestone_id, _elapsed, _elapsed / 60.0]
	)


func _reset_milestone_tracking() -> void:
	_prev_scan_drone_count = -1
	_prev_mining_ship_count = -1
	_prev_survey_probe_count = -1
	_prev_colony_ship_count = -1
	_prev_storage_upgrade_level = -1
	_prev_scan_drone_upgrade_level = -1
	_prev_mining_ship_upgrade_level = -1
	_prev_basic_scan_count = -1
	_prev_deep_scan_count = -1
	_prev_storage_full = false
	_prev_sd_buildable = false
	_prev_ms_buildable = false
	_prev_sp_buildable = false
	_prev_cs_affordable = false
	_prev_storage_upgrade_buyable = false
	_prev_sd_upgrade_buyable = false
	_prev_ms_upgrade_buyable = false
	_prev_sensor_pulse_can_start = false
	_prev_active_mining_count = -1
	_prev_colonization_pending = false
	_prev_established_base_count = -1
	_prev_current_system_id = ""
	_prev_storage_used = -1
	_prev_resource_iron = -1
	_prev_mining_unloading_count = 0
	_prev_mining_to_base_count = 0
	_mining_had_active_job = false


## Seeds transition trackers from current game state so start inventory does not trigger built milestones.
func _capture_run_baseline() -> void:
	var base_id: String = _get_primary_base_id()
	var has_base: bool = GameSession.has_established_base(base_id)
	var system_id: String = GameSession.current_system_id.strip_edges()

	_prev_scan_drone_count = GameSession.get_base_drone_count(base_id)
	_prev_mining_ship_count = GameSession.get_base_mining_ship_count(base_id)
	_prev_survey_probe_count = GameSession.bases.get_survey_probe_count(base_id) if has_base else 0
	_prev_colony_ship_count = GameSession.get_base_colony_ship_count(base_id)
	_prev_established_base_count = _count_established_bases()
	_prev_current_system_id = system_id
	_prev_colonization_pending = GameSession.has_pending_colonization_operations()

	if has_base:
		_prev_storage_upgrade_level = GameSession.get_base_upgrade_level(base_id, &"storage")
		_prev_scan_drone_upgrade_level = GameSession.get_base_upgrade_level(base_id, &"scan_drone")
		_prev_mining_ship_upgrade_level = GameSession.get_base_upgrade_level(base_id, &"mining_ship")
		_prev_storage_full = GameSession.is_base_storage_full(base_id)
		_prev_storage_used = GameSession.get_base_storage_used(base_id)
		_prev_resource_iron = GameSession.get_base_resource_amount(base_id, "Iron")
		_prev_sd_buildable = bool(
			GameSession.get_build_base_scan_drone_gate(base_id).get("ok", false)
		)
		_prev_ms_buildable = bool(
			GameSession.get_build_base_mining_ship_gate(base_id).get("ok", false)
		)
		_prev_sp_buildable = bool(
			GameSession.get_build_base_survey_probe_gate(base_id).get("ok", false)
		)
		_prev_cs_affordable = bool(
			GameSession.get_build_base_colony_ship_gate(base_id).get("ok", false)
		)
		_prev_storage_upgrade_buyable = bool(
			GameSession.get_buy_next_base_upgrade_gate(base_id, &"storage").get("ok", false)
		)
		_prev_sd_upgrade_buyable = bool(
			GameSession.get_buy_next_base_upgrade_gate(base_id, &"scan_drone").get("ok", false)
		)
		_prev_ms_upgrade_buyable = bool(
			GameSession.get_buy_next_base_upgrade_gate(base_id, &"mining_ship").get("ok", false)
		)

	if not system_id.is_empty():
		var sc: Array[int] = _get_scan_counts(system_id)
		_prev_basic_scan_count = sc[0]
		_prev_deep_scan_count = sc[1]

	var spc_ref: BaseSensorPulseController = _find_sensor_pulse_ctrl()
	if spc_ref != null and is_instance_valid(spc_ref):
		_prev_sensor_pulse_can_start = bool(
			spc_ref.can_start_sensor_pulse(base_id).get("ok", false)
		)

	var ac: AutomationController = _find_automation_ctrl()
	if ac != null and is_instance_valid(ac):
		_prev_active_mining_count = ac.get_active_mining_job_count_for_session_base(base_id)
		if _prev_active_mining_count > 0:
			_mining_had_active_job = true


# ══════════════════════════════════════════════════════════════════════════════
# Scene-controller tree finders (cached, invalidated on system change)
# ══════════════════════════════════════════════════════════════════════════════

func _invalidate_ctrl_cache() -> void:
	_automation_ctrl = null
	_survey_probe_ctrl = null
	_sensor_pulse_ctrl = null


func _find_automation_ctrl() -> AutomationController:
	if is_instance_valid(_automation_ctrl):
		return _automation_ctrl
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	_automation_ctrl = _search_automation_ctrl(tree.root)
	return _automation_ctrl


func _search_automation_ctrl(node: Node) -> AutomationController:
	if node == null:
		return null
	if node is AutomationController:
		return node as AutomationController
	for child: Node in node.get_children():
		var found: AutomationController = _search_automation_ctrl(child)
		if found != null:
			return found
	return null


func _find_survey_probe_ctrl() -> SurveyProbeMissionController:
	if is_instance_valid(_survey_probe_ctrl):
		return _survey_probe_ctrl
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	_survey_probe_ctrl = _search_survey_probe_ctrl(tree.root)
	return _survey_probe_ctrl


func _search_survey_probe_ctrl(node: Node) -> SurveyProbeMissionController:
	if node == null:
		return null
	if node is SurveyProbeMissionController:
		return node as SurveyProbeMissionController
	for child: Node in node.get_children():
		var found: SurveyProbeMissionController = _search_survey_probe_ctrl(child)
		if found != null:
			return found
	return null


func _find_sensor_pulse_ctrl() -> BaseSensorPulseController:
	if is_instance_valid(_sensor_pulse_ctrl):
		return _sensor_pulse_ctrl
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	_sensor_pulse_ctrl = _search_sensor_pulse_ctrl(tree.root)
	return _sensor_pulse_ctrl


func _search_sensor_pulse_ctrl(node: Node) -> BaseSensorPulseController:
	if node == null:
		return null
	if node is BaseSensorPulseController:
		return node as BaseSensorPulseController
	for child: Node in node.get_children():
		var found: BaseSensorPulseController = _search_sensor_pulse_ctrl(child)
		if found != null:
			return found
	return null


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _get_primary_base_id() -> String:
	var system_id: String = GameSession.current_system_id.strip_edges()
	if not system_id.is_empty():
		var eb: String = GameSession.get_established_base_id_for_system(system_id).strip_edges()
		if not eb.is_empty():
			return eb
	var src: String = GameSession.get_colonization_source_base_id().strip_edges()
	return src if not src.is_empty() else "earth"


## Returns [hidden_count, signal_count, known_count] for the given system.
func _get_discovery_counts(system_id: String) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	if system_id.is_empty():
		return counts
	var sys_def: SystemDefinition = GameSession.current_system_definition
	if sys_def == null:
		return counts
	for bv: Variant in sys_def.bodies:
		var body: SystemBodyDefinition = bv as SystemBodyDefinition
		if body == null:
			continue
		var ds: String = GameSession.get_object_discovery_state(system_id, body.id.strip_edges())
		match ds:
			GameSession.DISCOVERY_HIDDEN: counts[0] += 1
			GameSession.DISCOVERY_SIGNAL: counts[1] += 1
			_: counts[2] += 1
	for pv: Variant in sys_def.pois:
		var poi: PointOfInterestDefinition = pv as PointOfInterestDefinition
		if poi == null:
			continue
		var ds: String = GameSession.get_object_discovery_state(system_id, poi.id.strip_edges())
		match ds:
			GameSession.DISCOVERY_HIDDEN: counts[0] += 1
			GameSession.DISCOVERY_SIGNAL: counts[1] += 1
			_: counts[2] += 1
	return counts


## Returns [basic_scanned_count, deep_scanned_count] for the given system.
func _get_scan_counts(system_id: String) -> Array[int]:
	var counts: Array[int] = [0, 0]
	if system_id.is_empty():
		return counts
	var sys_def: SystemDefinition = GameSession.current_system_definition
	if sys_def == null:
		return counts
	for bv: Variant in sys_def.bodies:
		var body: SystemBodyDefinition = bv as SystemBodyDefinition
		if body == null:
			continue
		var ss: String = GameSession.get_object_scan_state(system_id, body.id.strip_edges())
		match ss:
			GameSession.SCAN_BASIC:
				counts[0] += 1
			GameSession.SCAN_DEEP, GameSession.SCAN_SPECIAL:
				counts[0] += 1
				counts[1] += 1
	return counts


func _count_established_bases() -> int:
	var n: int = 0
	for bid_var: Variant in GameSession.bases.bases.keys():
		var bid: String = str(bid_var).strip_edges()
		if bid.is_empty():
			continue
		if GameSession.has_established_base(bid):
			n += 1
	return n


func _survey_probe_inventory_snap(base_id: String) -> Dictionary:
	if not GameSession.has_established_base(base_id):
		return {
			"survey_probe_total_owned": 0,
			"survey_probe_lifetime_count": 0,
			"survey_probe_available": 0,
			"survey_probe_reserved": 0,
			"survey_probe_active_deployed": 0,
			"notes": "no_established_base",
		}
	var owned: int = GameSession.bases.get_survey_probe_count(base_id)
	var lifetime: int = GameSession.get_production_lifetime_count(
		base_id, BaseStore.PRODUCTION_SURVEY_PROBE
	)
	var reserved: int = GameSession.bases.get_survey_probes_reserved(base_id)
	var available: int = GameSession.get_available_survey_probe_count(base_id)
	var deployed: Variant = "unknown"
	var spc: SurveyProbeMissionController = _find_survey_probe_ctrl()
	if spc != null and is_instance_valid(spc):
		deployed = spc.get_active_investigate_count()
	return {
		"survey_probe_total_owned": owned,
		"survey_probe_lifetime_count": lifetime,
		"survey_probe_available": available,
		"survey_probe_reserved": reserved,
		"survey_probe_active_deployed": deployed,
		"notes": (
			"total_owned decreases when probes are consumed; "
			+ "lifetime_count never decreases and drives scaled_preview built_count"
		),
	}


## Builds a per-resource shortfall dict:  { "Iron": { "have": 80, "need":1500, "missing":1420 } }
func _build_cost_gap(cost: Dictionary, resources: Dictionary) -> Dictionary:
	if cost.is_empty():
		return {}
	var gap: Dictionary = {}
	for k: Variant in cost.keys():
		var rid: String = str(k)
		var need: int = int(cost[k])
		var have: int = int(resources.get(rid, 0))
		gap[rid] = {"have": have, "need": need, "missing": maxi(0, need - have)}
	return gap


func _mining_status_name(status: int) -> String:
	match status:
		0: return "to_target"
		1: return "mining"
		2: return "to_base"
		3: return "unloading"
		4: return "waiting_for_storage"
		_: return "unknown"


## Converts a cargo Dictionary to JSON-safe String-keyed ints.
func _sanitize_cargo(cargo: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in cargo.keys():
		var v: Variant = cargo[k]
		if v is int:
			out[str(k)] = v as int
		elif v is float:
			out[str(k)] = int(v)
		else:
			out[str(k)] = str(v)
	return out


# ══════════════════════════════════════════════════════════════════════════════
# Summary print (after save_run)
# ══════════════════════════════════════════════════════════════════════════════

func _print_summary(path: String) -> void:
	print_debug("[BalanceTelemetry] ═══════════════════════════════════════")
	print_debug("[BalanceTelemetry] Saved → %s" % path)
	print_debug("[BalanceTelemetry] Snapshots: %d | Duration: %.0f s (%.1f min)" % [
		_snapshots.size(), _elapsed, _elapsed / 60.0,
	])

	if not _snapshots.is_empty():
		var last_v: Variant = _snapshots[_snapshots.size() - 1]
		if last_v is Dictionary:
			var last: Dictionary = last_v as Dictionary

			# Last resources
			var rv: Variant = last.get("resources", {})
			if rv is Dictionary:
				var r: Dictionary = rv as Dictionary
				print_debug("[BalanceTelemetry] Last resources:")
				print_debug("  Fe=%-6d  Si=%-6d  Water=%-6d  SurveyData=%-4d" % [
					int(r.get("Iron", 0)), int(r.get("Silicon", 0)),
					int(r.get("Water", 0)), int(r.get("SurveyData", 0)),
				])

			# Colony ship cost gap
			var colv: Variant = last.get("colony", {})
			if colv is Dictionary:
				var col: Dictionary = colv as Dictionary
				var gapv: Variant = col.get("colony_ship_cost_gap", {})
				if gapv is Dictionary:
					var gap: Dictionary = gapv as Dictionary
					var any_missing: bool = false
					for rk: Variant in gap.keys():
						var gv: Variant = gap[rk]
						if gv is Dictionary and int((gv as Dictionary).get("missing", 0)) > 0:
							any_missing = true
							break
					if any_missing:
						print_debug("[BalanceTelemetry] ColonyShip still needs:")
						for rk: Variant in gap.keys():
							var gv: Variant = gap[rk]
							if not (gv is Dictionary):
								continue
							var gd: Dictionary = gv as Dictionary
							var missing_v: int = int(gd.get("missing", 0))
							if missing_v > 0:
								print_debug("  %-14s have=%-6d need=%-6d MISSING=%d" % [
									str(rk), int(gd.get("have", 0)),
									int(gd.get("need", 0)), missing_v,
								])

			var pgv: Variant = last.get("production_gates", {})
			if pgv is Dictionary:
				_print_scaled_preview_summary(pgv as Dictionary)

	# Key milestone table
	var key_milestones: Array[String] = [
		"first_basic_scan_done",
		"first_deep_scan_done",
		"three_deep_scans_done",
		"sensor_pulse_used",
		"mining_ship_2_built",
		"water_350_reached",
		"surveydata_150_reached",
		"iron_1500_reached",
		"colony_ship_affordable",
		"colony_ship_built",
		"colonization_started",
		"colonization_completed",
		"storage_full",
		"first_upgrade_bought",
	]
	print_debug("[BalanceTelemetry] Key milestones:")
	for mk: String in key_milestones:
		if _milestone_times.has(mk):
			var t: float = float(_milestone_times[mk])
			print_debug("  ✓ %-38s %.0f s  (%.1f min)" % [mk, t, t / 60.0])
		else:
			print_debug("  – %-38s NOT REACHED" % mk)
	print_debug("[BalanceTelemetry] ═══════════════════════════════════════")


func _print_scaled_preview_summary(production_gates: Dictionary) -> void:
	print_debug("[BalanceTelemetry] Next scaled costs (preview only, not gameplay):")
	_print_one_scaled_preview_line("ScanDrone", production_gates.get("scan_drone", {}))
	_print_one_scaled_preview_line("MiningShip", production_gates.get("mining_ship", {}))
	_print_one_scaled_preview_line("SurveyProbe", production_gates.get("survey_probe", {}))


func _print_one_scaled_preview_line(label: String, gate_entry: Variant) -> void:
	if not (gate_entry is Dictionary):
		print_debug("  %s: (missing)" % label)
		return
	var entry: Dictionary = gate_entry as Dictionary
	var preview_v: Variant = entry.get("scaled_preview", {})
	if not (preview_v is Dictionary):
		print_debug("  %s: (no preview)" % label)
		return
	var preview: Dictionary = preview_v as Dictionary
	var scaled_v: Variant = preview.get("scaled_cost", {})
	if not (scaled_v is Dictionary) or (scaled_v as Dictionary).is_empty():
		print_debug("  %s: (empty)" % label)
		return
	var parts: PackedStringArray = []
	for rk: Variant in (scaled_v as Dictionary).keys():
		parts.append("%s=%d" % [str(rk), int((scaled_v as Dictionary)[rk])])
	var built: int = int(preview.get("built_count", 0))
	var mult: float = float(preview.get("multiplier", 1.0))
	print_debug("  %s (built=%d mult=%.2f): %s" % [label, built, mult, ", ".join(parts)])


# ══════════════════════════════════════════════════════════════════════════════
# I/O helpers
# ══════════════════════════════════════════════════════════════════════════════

func _ensure_output_dir() -> void:
	var da: DirAccess = DirAccess.open("user://")
	if da == null:
		push_warning("[BalanceTelemetry] Cannot open user:// directory.")
		return
	if not da.dir_exists("balance_runs"):
		var err: int = da.make_dir("balance_runs")
		if err != OK:
			push_warning("[BalanceTelemetry] Failed to create user://balance_runs (err=%d)." % err)


func _format_timestamp() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d_%02d_%02d_%02d%02d%02d" % [
		int(dt.get("year", 2026)),
		int(dt.get("month", 1)),
		int(dt.get("day", 1)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
		int(dt.get("second", 0)),
	]
