## Base sensor pulse: reveals HIDDEN objects as SIGNAL (not KNOWN). Survey probes still required after.
class_name BaseSensorPulseController
extends Node

signal sensor_pulse_changed
signal sensor_pulse_progress_changed(progress: float)

const REASON_NO_CANDIDATES: StringName = DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NO_HIDDEN
const REASON_IN_PROGRESS: StringName = DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_ACTIVE
const REASON_COOLDOWN: StringName = DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_COOLDOWN
const REASON_BASE_MISSING: StringName = DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_BASE_MISSING
const REASON_NOT_ENOUGH_SURVEY_DATA: StringName = (
	DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_BLOCK_NOT_ENOUGH_SURVEY_DATA
)

const FALLBACK_PULSE_DURATION_SECONDS := 12.0
const FALLBACK_REVEAL_COUNT := 1
const FALLBACK_SENSOR_TIER := 0
const FALLBACK_COOLDOWN_SECONDS := 3.0
const FALLBACK_PULSE_COST_SURVEY_DATA := 5

var spawner: SystemSpawner = null
var discovery_controller: SystemDiscoveryController = null
var system_definition: SystemDefinition = null

var _system_id: String = ""
var _base_body_id: String = ""

var _pulse_active: bool = false
var _pulse_elapsed: float = 0.0
var _pulse_duration: float = FALLBACK_PULSE_DURATION_SECONDS
var _cooldown_remaining: float = 0.0
var _last_progress_emit: float = -1.0
var _paid_pulse_cost: Dictionary = {}
var _paid_pulse_base_id: String = ""


func setup(
	p_spawner: SystemSpawner,
	p_discovery: SystemDiscoveryController,
	p_system_definition: SystemDefinition,
	p_system_id: String,
	p_base_body_id: String,
) -> void:
	spawner = p_spawner
	discovery_controller = p_discovery
	system_definition = p_system_definition
	_system_id = p_system_id.strip_edges()
	_base_body_id = p_base_body_id.strip_edges()


func is_pulse_active() -> bool:
	return _pulse_active


func get_pulse_progress() -> float:
	if not _pulse_active or _pulse_duration <= 0.0:
		return 0.0
	return clampf(_pulse_elapsed / _pulse_duration, 0.0, 1.0)


func get_pulse_progress_percent() -> int:
	return int(round(get_pulse_progress() * 100.0))


func get_pulse_cost_display_text() -> String:
	var cost: Dictionary = _pulse_cost_dictionary()
	if cost.is_empty():
		return ""

	var parts: PackedStringArray = []
	for resource_id: Variant in cost.keys():
		var amount: int = int(cost[resource_id])
		if amount <= 0:
			continue
		parts.append("%d %s" % [amount, str(resource_id)])

	if parts.is_empty():
		return ""

	return DiscoverySignalUiTextDefinition.format_sensor_pulse_cost(", ".join(parts))


func can_start_sensor_pulse(base_id: String = "") -> Dictionary:
	var bid := _resolve_base_id(base_id)

	if bid.is_empty() or not GameSession.has_established_base(bid):
		return _blocked(REASON_BASE_MISSING)

	if _pulse_active:
		return _blocked(REASON_IN_PROGRESS)

	if _cooldown_remaining > 0.0:
		return _blocked(REASON_COOLDOWN)

	var candidates: Array[Dictionary] = _build_sorted_candidates(bid)
	if candidates.is_empty():
		return _blocked(REASON_NO_CANDIDATES)

	if not _can_afford_pulse_cost(bid):
		return _blocked(REASON_NOT_ENOUGH_SURVEY_DATA)

	return {"ok": true, "blocked_reason": ""}


func try_start_sensor_pulse(base_id: String = "") -> bool:
	var bid := _resolve_base_id(base_id)
	var gate: Dictionary = can_start_sensor_pulse(bid)
	if not bool(gate.get("ok", false)):
		return false

	if not _spend_pulse_cost(bid):
		return false

	_pulse_active = true
	_pulse_elapsed = 0.0
	_pulse_duration = _pulse_duration_seconds()
	_last_progress_emit = -1.0
	_paid_pulse_cost = _pulse_cost_dictionary().duplicate(true)
	_paid_pulse_base_id = bid
	sensor_pulse_changed.emit()
	_emit_progress_if_changed()
	return true


func cancel_pulse_before_save() -> void:
	if not _pulse_active:
		return

	_pulse_active = false
	_pulse_elapsed = 0.0
	_last_progress_emit = -1.0
	_refund_paid_pulse_cost_if_any()
	push_warning("Cancelled active sensor pulse before save; cost refunded")
	sensor_pulse_changed.emit()


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)

	if not _pulse_active:
		return

	_pulse_elapsed += delta
	_emit_progress_if_changed()

	if _pulse_elapsed >= _pulse_duration:
		_complete_pulse()


func _complete_pulse() -> void:
	_pulse_active = false
	_pulse_elapsed = 0.0
	_last_progress_emit = -1.0
	_cooldown_remaining = _cooldown_seconds()
	_clear_paid_pulse_cost_tracking()

	var bid := _resolve_base_id("")
	var reveal_budget: int = _reveal_count()

	var candidates: Array[Dictionary] = _build_sorted_candidates(bid)
	var reveal_count: int = mini(reveal_budget, candidates.size())

	for i in range(reveal_count):
		var oid: String = str(candidates[i].get("object_id", "")).strip_edges()
		if oid.is_empty():
			continue
		GameSession.set_object_discovery_state(_system_id, oid, GameSession.DISCOVERY_SIGNAL)

	if discovery_controller != null and system_definition != null:
		discovery_controller.apply_for_system(system_definition)

	sensor_pulse_changed.emit()
	sensor_pulse_progress_changed.emit(1.0)


func _build_sorted_candidates(base_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _system_id.is_empty() or system_definition == null:
		return result

	var sensor_tier: int = _current_sensor_tier()
	var base_node := _get_base_node(base_id)

	for body_def_variant: Variant in system_definition.bodies:
		var body_def := body_def_variant as SystemBodyDefinition
		if body_def == null:
			continue
		_try_append_candidate(result, body_def.id, body_def, base_node, sensor_tier)

	for poi_def_variant: Variant in system_definition.pois:
		var poi_def := poi_def_variant as PointOfInterestDefinition
		if poi_def == null:
			continue
		_try_append_candidate(result, poi_def.id, poi_def, base_node, sensor_tier)

	result.sort_custom(_compare_candidates)
	return result


func _try_append_candidate(
	out: Array[Dictionary],
	object_id: String,
	definition: Resource,
	base_node: Node2D,
	sensor_tier: int,
) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return

	if oid == GameSession.SYSTEM_STAR_OBJECT_ID:
		return

	if _is_excluded_base_object(oid):
		return

	if GameSession.get_object_discovery_state(_system_id, oid) != GameSession.DISCOVERY_HIDDEN:
		return

	if not bool(definition.get("discoverable_by_base_sensor")):
		return

	var object_tier: int = int(definition.get("base_sensor_reveal_tier"))
	if object_tier > sensor_tier:
		return

	var distance: float = _distance_to_base(oid, base_node)
	out.append({
		"object_id": oid,
		"priority": int(definition.get("base_sensor_reveal_priority")),
		"distance": distance,
	})


func _compare_candidates(a: Dictionary, b: Dictionary) -> bool:
	var priority_a: int = int(a.get("priority", 0))
	var priority_b: int = int(b.get("priority", 0))
	if priority_a != priority_b:
		return priority_a < priority_b

	var distance_a: float = float(a.get("distance", 0.0))
	var distance_b: float = float(b.get("distance", 0.0))
	if not is_equal_approx(distance_a, distance_b):
		return distance_a < distance_b

	return str(a.get("object_id", "")) < str(b.get("object_id", ""))


func _is_excluded_base_object(object_id: String) -> bool:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return true

	var established: String = GameSession.get_established_base_id_for_system(_system_id).strip_edges()
	if not established.is_empty() and oid == established:
		return true

	if not _base_body_id.is_empty() and oid == _base_body_id:
		return true

	return false


func _distance_to_base(object_id: String, base_node: Node2D) -> float:
	if base_node == null or spawner == null:
		return 0.0

	var target := spawner.get_spawned_object(object_id) as Node2D
	if target == null:
		return INF

	return base_node.global_position.distance_to(target.global_position)


func _get_base_node(base_id: String) -> Node2D:
	var bid := _resolve_base_id(base_id)
	if bid.is_empty() or spawner == null:
		return null
	return spawner.get_spawned_object(bid) as Node2D


func _resolve_base_id(base_id: String) -> String:
	var bid := base_id.strip_edges()
	if not bid.is_empty():
		return bid

	var established: String = GameSession.get_established_base_id_for_system(_system_id).strip_edges()
	if not established.is_empty():
		return established

	return _base_body_id.strip_edges()


func _pulse_cost_dictionary() -> Dictionary:
	var balance := GameSession.get_game_balance()
	if balance != null and not balance.base_sensor_pulse_cost.is_empty():
		return balance.base_sensor_pulse_cost.duplicate(true)

	return {str(GameBalanceDefinition.RESOURCE_SURVEY_DATA): FALLBACK_PULSE_COST_SURVEY_DATA}


func _can_afford_pulse_cost(base_id: String) -> bool:
	var bid := _resolve_base_id(base_id)
	if bid.is_empty():
		return false
	return GameSession.bases.can_afford(bid, _pulse_cost_dictionary())


func _spend_pulse_cost(base_id: String) -> bool:
	var bid := _resolve_base_id(base_id)
	var cost: Dictionary = _pulse_cost_dictionary()
	if cost.is_empty():
		return true
	if not GameSession.bases.spend_cost(bid, cost):
		return false
	GameSession.base_resources_changed.emit(bid)
	return true


func _refund_paid_pulse_cost_if_any() -> void:
	if _paid_pulse_cost.is_empty() or _paid_pulse_base_id.is_empty():
		return

	for resource_id: Variant in _paid_pulse_cost.keys():
		var amount: int = int(_paid_pulse_cost[resource_id])
		if amount <= 0:
			continue
		GameSession.add_base_resource(_paid_pulse_base_id, str(resource_id), amount)

	_clear_paid_pulse_cost_tracking()


func _clear_paid_pulse_cost_tracking() -> void:
	_paid_pulse_cost.clear()
	_paid_pulse_base_id = ""


func _blocked(reason_key: StringName) -> Dictionary:
	return {
		"ok": false,
		"blocked_reason": DiscoverySignalUiTextDefinition.get_template(reason_key),
	}


func _emit_progress_if_changed() -> void:
	var progress: float = get_pulse_progress()
	var percent: int = int(round(progress * 100.0))
	var last_percent: int = int(round(_last_progress_emit * 100.0)) if _last_progress_emit >= 0.0 else -1
	if percent == last_percent:
		return

	_last_progress_emit = progress
	sensor_pulse_progress_changed.emit(progress)


func _pulse_duration_seconds() -> float:
	var balance := GameSession.get_game_balance()
	if balance != null and balance.base_sensor_pulse_duration_seconds > 0.0:
		return balance.base_sensor_pulse_duration_seconds
	return FALLBACK_PULSE_DURATION_SECONDS


func _reveal_count() -> int:
	var balance := GameSession.get_game_balance()
	if balance != null and balance.base_sensor_reveal_count > 0:
		return balance.base_sensor_reveal_count
	return FALLBACK_REVEAL_COUNT


func _current_sensor_tier() -> int:
	var balance := GameSession.get_game_balance()
	if balance != null:
		return maxi(0, balance.base_sensor_reveal_tier)
	return FALLBACK_SENSOR_TIER


func _cooldown_seconds() -> float:
	var balance := GameSession.get_game_balance()
	if balance != null and balance.base_sensor_cooldown_seconds >= 0.0:
		return balance.base_sensor_cooldown_seconds
	return FALLBACK_COOLDOWN_SECONDS
