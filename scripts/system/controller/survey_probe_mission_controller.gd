## Runtime for survey-probe investigate missions (signal → known). Separate from scan/mining automation.
class_name SurveyProbeMissionController
extends Node

signal investigate_mission_changed
signal investigation_progress_changed(object_id: String, progress: float)

const REASON_NO_PROBE: StringName = DiscoverySignalUiTextDefinition.KEY_BLOCKED_NO_PROBE
const REASON_NOT_SIGNAL: StringName = DiscoverySignalUiTextDefinition.KEY_BLOCKED_NOT_SIGNAL
const REASON_IN_PROGRESS: StringName = DiscoverySignalUiTextDefinition.KEY_BLOCKED_IN_PROGRESS
const REASON_TARGET_MISSING: StringName = DiscoverySignalUiTextDefinition.KEY_BLOCKED_TARGET_MISSING
const REASON_BASE_MISSING: StringName = DiscoverySignalUiTextDefinition.KEY_BLOCKED_BASE_MISSING
const REASON_ALREADY_KNOWN: StringName = DiscoverySignalUiTextDefinition.KEY_BLOCKED_ALREADY_KNOWN
const REASON_ACTIVE_PROBE_LIMIT: StringName = (
	DiscoverySignalUiTextDefinition.KEY_BLOCKED_ACTIVE_PROBE_LIMIT
)

const FALLBACK_MAX_ACTIVE_PROBES: int = 2

var automation_controller: AutomationController = null
var spawner: SystemSpawner = null
var discovery_controller: SystemDiscoveryController = null
var selection: SystemSelectionController = null

var _system_id: String = ""
var _primary_base_body_id: String = ""

## object_id -> mission runtime Dictionary
var _active_missions: Dictionary = {}
## Prevents duplicate starts before mission registration (double-click guard).
var _launch_guard_object_ids: Dictionary = {}


func setup(
	p_automation: AutomationController,
	p_spawner: SystemSpawner,
	p_discovery: SystemDiscoveryController,
	p_selection: SystemSelectionController,
	p_system_id: String,
	p_primary_base_body_id: String,
) -> void:
	automation_controller = p_automation
	spawner = p_spawner
	discovery_controller = p_discovery
	selection = p_selection
	_system_id = p_system_id.strip_edges()
	_primary_base_body_id = p_primary_base_body_id.strip_edges()


func is_investigate_active(object_id: String) -> bool:
	var oid := object_id.strip_edges()
	return not oid.is_empty() and _active_missions.has(oid)


func get_investigation_progress(object_id: String) -> float:
	var oid := object_id.strip_edges()
	if oid.is_empty() or not _active_missions.has(oid):
		return 0.0

	var mission: Dictionary = _active_missions[oid]
	var unit := mission.get("unit") as SurveyProbeUnit
	if unit == null or not is_instance_valid(unit):
		return 0.0

	return unit.get_investigate_progress()


func get_active_investigate_count() -> int:
	return _active_missions.size()


func get_max_active_probes() -> int:
	var balance := GameSession.get_game_balance()
	if balance != null:
		return maxi(1, balance.max_active_probes_start)
	return FALLBACK_MAX_ACTIVE_PROBES


func has_active_probe_slot_available() -> bool:
	return get_active_investigate_count() < get_max_active_probes()


func get_investigate_blocked_reason(object_id: String, base_id: String = "") -> String:
	return str(can_investigate_signal(object_id, base_id).get("blocked_reason", "")).strip_edges()


func _gate_allows(gate: Dictionary) -> bool:
	return gate.get("ok", false) == true


func can_investigate_signal(object_id: String, base_id: String = "") -> Dictionary:
	var oid := object_id.strip_edges()
	var bid := _resolve_base_id(base_id)

	if oid.is_empty():
		return _blocked(REASON_TARGET_MISSING)

	if _system_id.is_empty():
		return _blocked(REASON_TARGET_MISSING)

	if bid.is_empty() or not GameSession.has_established_base(bid):
		return _blocked(REASON_BASE_MISSING)

	if GameSession.get_object_discovery_state(_system_id, oid) != GameSession.DISCOVERY_SIGNAL:
		if GameSession.get_object_discovery_state(_system_id, oid) == GameSession.DISCOVERY_KNOWN:
			return _blocked(REASON_ALREADY_KNOWN)
		return _blocked(REASON_NOT_SIGNAL)

	# A) Same object must not be investigated twice in parallel.
	if _active_missions.has(oid) or _launch_guard_object_ids.has(oid):
		return _blocked(REASON_IN_PROGRESS)

	# B) Global concurrent mission cap (other objects may still be allowed).
	if get_active_investigate_count() >= get_max_active_probes():
		return _blocked(REASON_ACTIVE_PROBE_LIMIT)

	# C) Store must have an unassigned survey probe for this launch.
	if not GameSession.can_consume_survey_probe(bid):
		return _blocked(REASON_NO_PROBE)

	if spawner == null:
		return _blocked(REASON_TARGET_MISSING)

	if _resolve_investigate_target(oid).is_empty():
		return _blocked(REASON_TARGET_MISSING)

	if _resolve_base_node(bid) == null:
		return _blocked(REASON_BASE_MISSING)

	if automation_controller == null:
		return _blocked(REASON_NO_PROBE)

	return {"ok": true, "blocked_reason": ""}


func try_start_investigate_signal(object_id: String, base_id: String = "") -> bool:
	var oid := object_id.strip_edges()
	var bid := _resolve_base_id(base_id)

	var gate := can_investigate_signal(oid, bid)
	if not _gate_allows(gate):
		var blocked := str(gate.get("blocked_reason", "")).strip_edges()
		push_warning(
			"SurveyProbe investigate blocked (object_id=%s): %s" % [oid, blocked]
		)
		return false

	if _launch_guard_object_ids.has(oid):
		push_warning(
			"SurveyProbe investigate aborted: launch guard active for object_id=%s"
			% oid
		)
		return false

	_launch_guard_object_ids[oid] = true

	if automation_controller == null:
		_launch_guard_object_ids.erase(oid)
		push_warning("SurveyProbe investigate aborted: no AutomationController")
		return false

	var base_node: Node2D = _resolve_base_node(bid)
	var target_resolve: Dictionary = _resolve_investigate_target(oid)
	if base_node == null or target_resolve.is_empty():
		_launch_guard_object_ids.erase(oid)
		push_warning("SurveyProbe investigate aborted: base or target missing for object_id=%s" % oid)
		return false

	var world_node: Node2D = target_resolve.get("world_node") as Node2D
	var signal_marker: Node2D = target_resolve.get("signal_marker") as Node2D
	# Prefer the visible SignalMarker while discovery is SIGNAL (world body orbit layers are hidden).
	var target_node: Node2D = signal_marker if signal_marker != null else world_node

	if target_node == null or not is_instance_valid(target_node):
		_launch_guard_object_ids.erase(oid)
		push_warning("SurveyProbe investigate aborted: target_node missing for object_id=%s" % oid)
		return false

	var unit := automation_controller.take_idle_survey_probe_for_base(bid)
	if unit == null:
		_launch_guard_object_ids.erase(oid)
		push_warning("SurveyProbe investigate aborted: no idle survey probe unit available")
		return false

	_disconnect_probe_unit_signals(unit)
	_connect_probe_progress_signal(unit, oid)
	if not unit.investigation_finished.is_connected(_on_probe_investigation_finished):
		unit.investigation_finished.connect(_on_probe_investigation_finished)

	_active_missions[oid] = {
		"object_id": oid,
		"base_id": bid,
		"unit": unit,
	}

	var consume_ok: bool = GameSession.bases.consume_survey_probe(bid)
	if not consume_ok:
		_active_missions.erase(oid)
		automation_controller.return_survey_probe_to_idle_orbit(unit, bid)
		_launch_guard_object_ids.erase(oid)
		push_warning("SurveyProbe investigate aborted: consume_survey_probe failed")
		return false
	GameSession.base_resources_changed.emit(bid)

	var investigate_s: float = _sample_investigate_duration_seconds()
	_launch_survey_probe_investigation(unit, target_node, investigate_s)

	_launch_guard_object_ids.erase(oid)
	investigate_mission_changed.emit()
	return true


## Pre-save safety (v0.1): refund probes and tear down visuals without revealing signals.
func cancel_all_active_investigations_refund() -> int:
	var mission_entries: Array = []
	for oid_variant: Variant in _active_missions.keys():
		var oid := str(oid_variant).strip_edges()
		if oid.is_empty():
			continue
		var mission: Dictionary = _active_missions[oid_variant]
		mission_entries.append({
			"object_id": oid,
			"base_id": str(mission.get("base_id", "")).strip_edges(),
			"unit": mission.get("unit"),
		})

	var cancelled_count := 0
	for entry_variant: Variant in mission_entries:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var oid: String = str(entry.get("object_id", "")).strip_edges()
		if oid.is_empty() or not _active_missions.has(oid):
			continue
		var unit: SurveyProbeUnit = entry.get("unit") as SurveyProbeUnit
		var mission_bid: String = str(entry.get("base_id", "")).strip_edges()
		_abort_mission_with_refund(oid, unit, mission_bid)
		cancelled_count += 1

	_launch_guard_object_ids.clear()
	if cancelled_count > 0 and automation_controller != null:
		automation_controller.ensure_survey_probe_units_for_base(_resolve_base_id(""))
	return cancelled_count


func _on_probe_investigation_finished(unit: SurveyProbeUnit) -> void:
	var mission_oid: String = ""
	for oid_variant: Variant in _active_missions.keys():
		var mission: Dictionary = _active_missions[oid_variant]
		if mission.get("unit") == unit:
			mission_oid = str(oid_variant).strip_edges()
			break

	if mission_oid.is_empty():
		if automation_controller != null:
			automation_controller.release_survey_probe_unit(unit)
		if is_instance_valid(unit):
			unit.queue_free()
		return

	var mission: Dictionary = _active_missions.get(mission_oid, {})
	var mission_base_id: String = str(mission.get("base_id", "")).strip_edges()

	if unit.mission_succeeded:
		_complete_mission(mission_oid, unit)
	else:
		_abort_mission_with_refund(mission_oid, unit, mission_base_id)


func _complete_mission(object_id: String, unit: SurveyProbeUnit) -> void:
	var oid := object_id.strip_edges()
	_active_missions.erase(oid)

	if automation_controller != null:
		automation_controller.release_survey_probe_unit(unit)
	if is_instance_valid(unit):
		unit.queue_free()

	if oid.is_empty() or _system_id.is_empty():
		investigate_mission_changed.emit()
		return

	GameSession.set_object_discovery_state(_system_id, oid, GameSession.DISCOVERY_KNOWN)

	if discovery_controller != null and not discovery_controller.refresh_object(oid):
		push_warning(
			"SurveyProbeMissionController: discovery refresh failed for '%s'." % oid
		)

	var base_id: String = _resolve_base_id(_primary_base_body_id)
	_grant_survey_data_reward(base_id)

	_refresh_selection_after_reveal(oid)

	investigate_mission_changed.emit()


func _abort_mission_with_refund(object_id: String, unit: SurveyProbeUnit, base_id: String) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return
	if not _active_missions.has(oid):
		return

	var bid := _resolve_base_id(base_id)
	_active_missions.erase(oid)
	_launch_guard_object_ids.erase(oid)

	if is_instance_valid(unit):
		_disconnect_probe_unit_signals(unit)
		if automation_controller != null:
			automation_controller.release_survey_probe_unit(unit)
		unit.queue_free()

	GameSession.add_survey_probe(1, bid)
	if automation_controller != null:
		automation_controller.ensure_survey_probe_units_for_base(bid)
	investigate_mission_changed.emit()


func _launch_survey_probe_investigation(
	unit: SurveyProbeUnit,
	target_node: Node2D,
	investigate_seconds: float,
) -> void:
	unit.one_way_investigate = true
	unit.mission_succeeded = false
	unit.begin_investigate(investigate_seconds)
	unit.visible = true
	unit.start_mission_to_node(target_node)


func _on_probe_investigate_progress(progress: float, object_id: String) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty() or not _active_missions.has(oid):
		return
	investigation_progress_changed.emit(oid, progress)


func _connect_probe_progress_signal(unit: SurveyProbeUnit, object_id: String) -> void:
	var oid := object_id.strip_edges()
	_disconnect_probe_progress_signal(unit)
	unit.investigate_progress_changed.connect(_on_probe_investigate_progress.bind(oid))


func _disconnect_probe_progress_signal(unit: SurveyProbeUnit) -> void:
	if unit == null:
		return
	for conn: Dictionary in unit.investigate_progress_changed.get_connections():
		var callable_obj: Callable = conn.get("callable", Callable())
		if callable_obj.is_valid():
			unit.investigate_progress_changed.disconnect(callable_obj)


func _disconnect_probe_unit_signals(unit: SurveyProbeUnit) -> void:
	_disconnect_probe_progress_signal(unit)
	if unit.investigation_finished.is_connected(_on_probe_investigation_finished):
		unit.investigation_finished.disconnect(_on_probe_investigation_finished)


func _refresh_selection_after_reveal(object_id: String) -> void:
	if selection == null or spawner == null:
		return

	var revealed := spawner.get_spawned_object(object_id)
	if revealed == null:
		return

	var selected := selection.get_selected_node()
	if selected is SignalMarker and (selected as SignalMarker).object_id == object_id:
		selection.select_world_node(revealed)


func _grant_survey_data_reward(base_id: String) -> void:
	var balance := GameSession.get_game_balance()
	if balance == null:
		balance = GameBalanceDefinition.new()
	var amount: int = balance.get_survey_probe_investigate_survey_data_reward()
	if amount <= 0:
		return
	var resource_id := str(GameBalanceDefinition.RESOURCE_SURVEY_DATA)
	var added: int = GameSession.add_base_resource(base_id, resource_id, amount)
	if added <= 0:
		push_warning(
			"SurveyProbeMissionController: SurveyData reward skipped (added=%d, base=%s)."
			% [added, base_id]
		)


## World body/POI first, then signal marker fallback for targeting.
func _resolve_investigate_target(object_id: String) -> Dictionary:
	var oid := object_id.strip_edges()
	if oid.is_empty() or spawner == null:
		return {}

	var world_node: Node2D = spawner.get_spawned_object(oid) as Node2D
	var signal_marker: Node2D = null
	if discovery_controller != null:
		var marker := discovery_controller.get_signal_marker(oid)
		if marker != null and is_instance_valid(marker):
			signal_marker = marker

	if world_node == null and signal_marker == null:
		return {}

	return {"world_node": world_node, "signal_marker": signal_marker}


func _resolve_base_node(base_id: String) -> Node2D:
	if spawner == null:
		return null
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return null
	var base_node := spawner.get_spawned_object(bid) as Node2D
	if base_node == null or not is_instance_valid(base_node):
		return null
	return base_node


func _resolve_base_id(base_id: String) -> String:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		bid = _primary_base_body_id.strip_edges()
	return bid


func _sample_investigate_duration_seconds() -> float:
	var balance := GameSession.get_game_balance()
	if balance != null:
		return randf_range(
			balance.survey_probe_investigate_time_min,
			balance.survey_probe_investigate_time_max,
		)
	return randf_range(15.0, 25.0)


func _blocked(reason_key: StringName) -> Dictionary:
	return {
		"ok": false,
		"blocked_reason": DiscoverySignalUiTextDefinition.get_template(reason_key),
	}
