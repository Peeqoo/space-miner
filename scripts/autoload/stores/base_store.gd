class_name BaseStore
extends RefCounted

const BASE_EARTH := "earth"

const PRODUCTION_SCAN_DRONE := "scan_drone"
const PRODUCTION_MINING_SHIP := "mining_ship"
const PRODUCTION_COLONY_SHIP := "colony_ship"
const PRODUCTION_SURVEY_PROBE := "survey_probe"

## Keys tracked in `production_lifetime_counts` (units ever received at base; never decremented).
const PRODUCTION_LIFETIME_COUNT_IDS: Array[String] = [
	PRODUCTION_SCAN_DRONE,
	PRODUCTION_MINING_SHIP,
	PRODUCTION_SURVEY_PROBE,
	PRODUCTION_COLONY_SHIP,
]

## Safety fallback only when `storage_0_base.tres` / UpgradeCatalog is unavailable.
const STORAGE_CAPACITY_LEVEL_ZERO_FALLBACK: int = 1000

const FALLBACK_MAX_SCAN_DRONES: int = 2
const FALLBACK_MAX_MINING_SHIPS: int = 2

var bases: Dictionary = {
	BASE_EARTH: {
		"resources": {},
		"population": 1,
		"drones": 1,
		"mining_ships": 1,
		"colony_ships": 0,
		"survey_probes": 0,
		## Bootstrap until `get_base()` syncs from `data/upgrades/storage/storage_0_base.tres`.
		"storage_capacity": STORAGE_CAPACITY_LEVEL_ZERO_FALLBACK,
		"storage_upgrade_level": 0,
		"scan_drone_upgrade_level": 0,
		"mining_ship_upgrade_level": 0,
	}
}

## Phase 5.5: balancing data — catalog is bound externally (see project autoload).
var _upgrade_catalog: UpgradeCatalog = null
var _production_catalog: ProductionCatalog = null
var _game_balance: GameBalanceDefinition = null


func set_upgrade_catalog(catalog: UpgradeCatalog) -> void:
	_upgrade_catalog = catalog


func get_upgrade_catalog() -> UpgradeCatalog:
	return _upgrade_catalog


func set_production_catalog(catalog: ProductionCatalog) -> void:
	_production_catalog = catalog


func get_production_catalog() -> ProductionCatalog:
	return _production_catalog


func set_game_balance(balance: GameBalanceDefinition) -> void:
	_game_balance = balance


## Legacy v0.1 balance reference (`max_scan_drones_start`). Not used for build gates — telemetry/diagnostics only.
func get_max_scan_drone_count() -> int:
	if _game_balance != null:
		return maxi(1, _game_balance.max_scan_drones_start)
	return FALLBACK_MAX_SCAN_DRONES


## Legacy v0.1 balance reference (`max_mining_ships_start`). Not used for build gates — telemetry/diagnostics only.
func get_max_mining_ship_count() -> int:
	if _game_balance != null:
		return maxi(1, _game_balance.max_mining_ships_start)
	return FALLBACK_MAX_MINING_SHIPS


## Primary source: `data/upgrades/storage/storage_0_base.tres` (`storage_capacity_units`).
func get_storage_capacity_level_zero_units() -> int:
	return _resolve_storage_capacity_level_zero_units()


func _resolve_storage_capacity_level_zero_units() -> int:
	if _upgrade_catalog != null:
		var def := _upgrade_catalog.get_current_definition(&"storage", 0)
		if def != null and def.storage_capacity_units >= 0:
			return def.storage_capacity_units
	push_warning(
		"BaseStore: using fallback storage capacity level 0 (upgrade catalog or storage_0_base missing)"
	)
	return STORAGE_CAPACITY_LEVEL_ZERO_FALLBACK


func get_production_cost(production_id: String) -> Dictionary:
	if _production_catalog == null:
		push_warning("BaseStore.get_production_cost: production catalog not bound (%s)" % production_id)
		return {}
	return _production_catalog.get_cost(production_id)


func get_production_definition(production_id: String) -> ProductionDefinition:
	if _production_catalog == null:
		return null
	return _production_catalog.get_definition(production_id)


func get_base(base_id: String) -> Dictionary:
	if not bases.has(base_id):
		bases[base_id] = _create_empty_base()

	var base_entry: Dictionary = bases[base_id]
	_normalize_base_storage_fields(base_entry)
	_normalize_scan_drone_upgrade_fields(base_entry)
	_normalize_mining_ship_upgrade_fields(base_entry)
	_normalize_colony_ship_fields(base_entry)
	_normalize_survey_probe_fields(base_entry)

	_sync_storage_capacity_from_definition(base_id, base_entry)

	return base_entry


func has_production_lifetime_counts_field(base_id: String) -> bool:
	var bid: String = base_id.strip_edges()
	if bid.is_empty() or not bases.has(bid):
		return false
	var counts_v: Variant = bases[bid].get("production_lifetime_counts", null)
	return counts_v is Dictionary


func ensure_production_lifetime_counts(base_id: String) -> void:
	var bid: String = base_id.strip_edges()
	if bid.is_empty() or not bases.has(bid):
		return

	var base: Dictionary = bases[bid]
	var existing_v: Variant = base.get("production_lifetime_counts", null)
	if existing_v is Dictionary:
		base["production_lifetime_counts"] = _sanitize_production_lifetime_counts(
			existing_v as Dictionary,
			base,
		)
		bases[bid] = base
		return

	base["production_lifetime_counts"] = _production_lifetime_counts_from_fleet(base)
	bases[bid] = base


func get_production_lifetime_count(base_id: String, production_id: String) -> int:
	var bid: String = base_id.strip_edges()
	var pid: String = production_id.strip_edges()
	if bid.is_empty():
		return 0
	if not _is_known_production_lifetime_id(pid):
		if not pid.is_empty():
			push_warning("BaseStore: unknown production_lifetime id '%s'" % pid)
		return 0
	if not bases.has(bid):
		return 0

	ensure_production_lifetime_counts(bid)
	var counts_v: Variant = bases[bid].get("production_lifetime_counts", {})
	if not counts_v is Dictionary:
		return 0
	return maxi(0, int((counts_v as Dictionary).get(pid, 0)))


func set_production_lifetime_count(base_id: String, production_id: String, count: int) -> void:
	var bid: String = base_id.strip_edges()
	var pid: String = production_id.strip_edges()
	if bid.is_empty() or not _is_known_production_lifetime_id(pid):
		return
	if not bases.has(bid):
		push_warning("BaseStore: set_production_lifetime_count — base '%s' missing" % bid)
		return

	ensure_production_lifetime_counts(bid)
	var base: Dictionary = bases[bid]
	var counts: Dictionary = (base.get("production_lifetime_counts", {}) as Dictionary).duplicate(true)
	counts[pid] = maxi(0, count)
	base["production_lifetime_counts"] = counts
	bases[bid] = base


func increment_production_lifetime_count(
	base_id: String,
	production_id: String,
	amount: int = 1,
) -> void:
	if amount <= 0:
		return
	var bid: String = base_id.strip_edges()
	var pid: String = production_id.strip_edges()
	if bid.is_empty() or not _is_known_production_lifetime_id(pid):
		return
	if not bases.has(bid):
		push_warning("BaseStore: increment_production_lifetime_count — base '%s' missing" % bid)
		return

	var next_count: int = get_production_lifetime_count(bid, pid) + amount
	set_production_lifetime_count(bid, pid, next_count)


func _is_known_production_lifetime_id(production_id: String) -> bool:
	return PRODUCTION_LIFETIME_COUNT_IDS.has(production_id)


func _production_lifetime_counts_from_fleet(base: Dictionary) -> Dictionary:
	return {
		PRODUCTION_SCAN_DRONE: maxi(0, int(base.get("drones", 0))),
		PRODUCTION_MINING_SHIP: maxi(0, int(base.get("mining_ships", 0))),
		PRODUCTION_SURVEY_PROBE: maxi(0, int(base.get("survey_probes", 0))),
		PRODUCTION_COLONY_SHIP: maxi(0, int(base.get("colony_ships", 0))),
	}


func _sanitize_production_lifetime_counts(counts: Dictionary, base: Dictionary) -> Dictionary:
	var fleet_defaults: Dictionary = _production_lifetime_counts_from_fleet(base)
	var out: Dictionary = {}
	for pid: String in PRODUCTION_LIFETIME_COUNT_IDS:
		if counts.has(pid):
			out[pid] = maxi(0, int(counts[pid]))
		else:
			out[pid] = int(fleet_defaults.get(pid, 0))
	return out


func _normalize_mining_ship_upgrade_fields(base: Dictionary) -> void:
	if not base.has("mining_ship_upgrade_level"):
		base["mining_ship_upgrade_level"] = 0


func _normalize_colony_ship_fields(base: Dictionary) -> void:
	if not base.has("colony_ships"):
		base["colony_ships"] = 0
	elif int(base["colony_ships"]) < 0:
		base["colony_ships"] = 0


func _normalize_survey_probe_fields(base: Dictionary) -> void:
	if not base.has("survey_probes"):
		base["survey_probes"] = 0
	elif int(base["survey_probes"]) < 0:
		base["survey_probes"] = 0
	if not base.has("survey_probes_reserved"):
		base["survey_probes_reserved"] = 0
	elif int(base["survey_probes_reserved"]) < 0:
		base["survey_probes_reserved"] = 0


func _normalize_scan_drone_upgrade_fields(base: Dictionary) -> void:
	if not base.has("scan_drone_upgrade_level"):
		base["scan_drone_upgrade_level"] = 0


func _normalize_base_storage_fields(base: Dictionary) -> void:
	if not base.has("storage_capacity"):
		base["storage_capacity"] = _resolve_storage_capacity_level_zero_units()
	elif int(base["storage_capacity"]) < 0:
		base["storage_capacity"] = _resolve_storage_capacity_level_zero_units()

	if not base.has("storage_upgrade_level"):
		base["storage_upgrade_level"] = 0


func _sync_storage_capacity_from_definition(_base_id: String, base_entry: Dictionary) -> void:
	if _upgrade_catalog == null:
		return
	var lvl := int(base_entry.get("storage_upgrade_level", 0))
	var def := _upgrade_catalog.get_current_definition(&"storage", lvl)
	if def != null and def.storage_capacity_units >= 0:
		base_entry["storage_capacity"] = def.storage_capacity_units


func get_upgrade_level(base_id: String, category: StringName) -> int:
	if not bases.has(base_id):
		return 0
	var b: Dictionary = bases[base_id]
	match String(category):
		"storage":
			return int(b.get("storage_upgrade_level", 0))
		"scan_drone":
			return int(b.get("scan_drone_upgrade_level", 0))
		"mining_ship":
			return int(b.get("mining_ship_upgrade_level", 0))
		_:
			return 0


func set_upgrade_level(base_id: String, category: StringName, level: int) -> void:
	var b := get_base(base_id)
	match String(category):
		"storage":
			b["storage_upgrade_level"] = level
		"scan_drone":
			b["scan_drone_upgrade_level"] = level
		"mining_ship":
			b["mining_ship_upgrade_level"] = level
	bases[base_id] = b


func get_upgrade_levels(base_id: String) -> Dictionary:
	return {
		"storage": get_upgrade_level(base_id, &"storage"),
		"scan_drone": get_upgrade_level(base_id, &"scan_drone"),
		"mining_ship": get_upgrade_level(base_id, &"mining_ship"),
	}


func can_afford_upgrade(base_id: String, upgrade_definition: UpgradeDefinition) -> bool:
	if upgrade_definition == null:
		return false
	return can_afford(base_id, upgrade_definition.cost)


func get_buy_next_upgrade_blocked_reason_key(base_id: String, category: StringName) -> StringName:
	if _upgrade_catalog == null:
		return GateUiTextDefinition.KEY_UPGRADE_NOT_ENOUGH_RESOURCES
	var cur := get_upgrade_level(base_id, category)
	var nxt := _upgrade_catalog.get_next_definition(category, cur)
	if nxt == null:
		return GateUiTextDefinition.KEY_NONE
	if not nxt.purchasable:
		return GateUiTextDefinition.KEY_NONE
	if not can_afford_upgrade(base_id, nxt):
		return GateUiTextDefinition.KEY_UPGRADE_NOT_ENOUGH_RESOURCES
	return GateUiTextDefinition.KEY_NONE


func get_buy_next_upgrade_blocked_reason(base_id: String, category: StringName) -> String:
	var key := get_buy_next_upgrade_blocked_reason_key(base_id, category)
	if key == GateUiTextDefinition.KEY_NONE or String(key).is_empty():
		return ""
	return GateUiTextDefinition.get_text(key)


func buy_next_upgrade(base_id: String, upgrade_definition: UpgradeDefinition) -> bool:
	if upgrade_definition == null or not upgrade_definition.purchasable:
		return false
	var cat := upgrade_definition.category
	var cur := get_upgrade_level(base_id, cat)
	if upgrade_definition.level != cur + 1:
		return false
	if not can_afford_upgrade(base_id, upgrade_definition):
		return false
	if not spend_cost(base_id, upgrade_definition.cost.duplicate(true)):
		return false
	set_upgrade_level(base_id, cat, upgrade_definition.level)
	return true


func get_storage_used(base_id: String) -> int:
	var resources: Variant = get_base(base_id).get("resources", {})
	if not resources is Dictionary:
		return 0

	var total: int = 0

	for amt_var: Variant in (resources as Dictionary).values():
		total += maxi(0, int(amt_var))

	return total


func get_storage_capacity(base_id: String) -> int:
	if _upgrade_catalog != null:
		var lvl := get_upgrade_level(base_id, &"storage")
		var def := _upgrade_catalog.get_current_definition(&"storage", lvl)
		if def != null and def.storage_capacity_units >= 0:
			return maxi(0, def.storage_capacity_units)

	return maxi(0, int(get_base(base_id).get("storage_capacity", _resolve_storage_capacity_level_zero_units())))


func get_storage_free(base_id: String) -> int:
	return get_remaining_storage_capacity(base_id)


func get_remaining_storage_capacity(base_id: String) -> int:
	return maxi(0, get_storage_capacity(base_id) - get_storage_used(base_id))


func is_storage_full(base_id: String) -> bool:
	return get_remaining_storage_capacity(base_id) <= 0


func can_accept_resource(base_id: String, _resource_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	return get_remaining_storage_capacity(base_id) >= amount


func get_accepted_resource_amount(base_id: String, requested_amount: int) -> int:
	var req := maxi(0, requested_amount)
	if req <= 0:
		return 0

	return mini(req, get_storage_free(base_id))


func get_resource_amount(base_id: String, resource_id: String) -> int:
	var base := get_base(base_id)
	var resources: Dictionary = base.get("resources", {})
	return int(resources.get(resource_id, 0))


func add_resource(base_id: String, resource_id: String, amount: int) -> int:
	if amount <= 0:
		return 0

	var accept_amount: int = get_accepted_resource_amount(base_id, amount)

	if accept_amount <= 0:
		return 0

	var base := get_base(base_id)
	var resources: Dictionary = base.get("resources", {})

	resources[resource_id] = get_resource_amount(base_id, resource_id) + accept_amount
	base["resources"] = resources
	bases[base_id] = base

	return accept_amount


func add_resource_with_capacity_check(base_id: String, resource_id: String, amount: int) -> int:
	return add_resource(base_id, resource_id, amount)


func get_scan_drone_scan_duration_multiplier(base_id: String) -> float:
	if _upgrade_catalog != null:
		var def := _upgrade_catalog.get_current_definition(
			&"scan_drone",
			get_upgrade_level(base_id, &"scan_drone")
		)
		if def != null and def.scan_duration_multiplier >= 0.0:
			return def.scan_duration_multiplier
	return 1.0


func get_mining_ship_cargo_capacity_multiplier(base_id: String) -> float:
	if _upgrade_catalog != null:
		var def := _upgrade_catalog.get_current_definition(
			&"mining_ship",
			get_upgrade_level(base_id, &"mining_ship")
		)
		if def != null and def.cargo_capacity_percent >= 0:
			return float(def.cargo_capacity_percent) / 100.0
	return 1.0


func get_mining_ship_mining_rate_multiplier(base_id: String) -> float:
	if _upgrade_catalog != null:
		var def := _upgrade_catalog.get_current_definition(
			&"mining_ship",
			get_upgrade_level(base_id, &"mining_ship")
		)
		if def != null and def.mining_rate_multiplier >= 0.0:
			return def.mining_rate_multiplier
	return 1.0


func get_unlocked_scan_layer(base_id: String) -> int:
	if _upgrade_catalog == null:
		push_warning("BaseStore.get_unlocked_scan_layer: upgrade catalog not bound")
		return ScannedResourceEntry.Layer.BASIC
	var def := _upgrade_catalog.get_current_definition(
		&"scan_drone",
		get_upgrade_level(base_id, &"scan_drone")
	)
	if def == null:
		push_warning(
			"BaseStore.get_unlocked_scan_layer: missing scan_drone definition (base_id=%s)"
			% base_id
		)
		return ScannedResourceEntry.Layer.BASIC
	return clampi(int(def.unlock_scan_layer), ScannedResourceEntry.Layer.BASIC, ScannedResourceEntry.Layer.SPECIAL)


func get_unlocked_mining_layer(base_id: String) -> int:
	if _upgrade_catalog == null:
		push_warning("BaseStore.get_unlocked_mining_layer: upgrade catalog not bound")
		return ScannedResourceEntry.Layer.BASIC
	var def := _upgrade_catalog.get_current_definition(
		&"mining_ship",
		get_upgrade_level(base_id, &"mining_ship")
	)
	if def == null:
		push_warning(
			"BaseStore.get_unlocked_mining_layer: missing mining_ship definition (base_id=%s)"
			% base_id
		)
		return ScannedResourceEntry.Layer.BASIC
	return clampi(int(def.unlock_mining_layer), ScannedResourceEntry.Layer.BASIC, ScannedResourceEntry.Layer.SPECIAL)


func spend_resource(base_id: String, resource_id: String, amount: int) -> bool:
	if amount <= 0:
		return true

	var current := get_resource_amount(base_id, resource_id)

	if current < amount:
		return false

	var base := get_base(base_id)
	var resources: Dictionary = base.get("resources", {})

	resources[resource_id] = current - amount
	base["resources"] = resources
	bases[base_id] = base

	return true


## Removes up to `amount` from base storage (player discard). Returns amount actually removed.
func remove_resource(base_id: String, resource_id: String, amount: int) -> int:
	if amount <= 0:
		return 0

	var current := get_resource_amount(base_id, resource_id)

	if current <= 0:
		return 0

	var removed: int = mini(current, amount)
	var base := get_base(base_id)
	var resources: Dictionary = base.get("resources", {})
	var after: int = current - removed

	if after <= 0:
		resources.erase(resource_id)
	else:
		resources[resource_id] = after

	base["resources"] = resources
	bases[base_id] = base

	return removed


func can_afford(base_id: String, cost: Dictionary) -> bool:
	for resource_id in cost:
		var needed: int = int(cost[resource_id])
		var available: int = get_resource_amount(base_id, resource_id)
		if available < needed:
			return false
	return true


func spend_cost(base_id: String, cost: Dictionary) -> bool:
	if not can_afford(base_id, cost):
		return false
	for resource_id in cost:
		var amount: int = int(cost[resource_id])
		spend_resource(base_id, resource_id, amount)
	return true


func get_population(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("population", 0))


func get_drone_count(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("drones", 0))


func get_mining_ship_count(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("mining_ships", 0))


func get_colony_ship_count(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("colony_ships", 0))


func get_survey_probe_count(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("survey_probes", 0))


func get_survey_probes_reserved(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("survey_probes_reserved", 0))


func get_available_survey_probe_count(base_id: String) -> int:
	return maxi(0, get_survey_probe_count(base_id) - get_survey_probes_reserved(base_id))


func can_consume_survey_probe(base_id: String) -> bool:
	return get_available_survey_probe_count(base_id) > 0


func reserve_or_consume_survey_probe(base_id: String) -> bool:
	return consume_survey_probe(base_id, 1)


func consume_survey_probe(base_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if get_available_survey_probe_count(base_id) < amount:
		return false
	var base := get_base(base_id)
	base["survey_probes"] = int(base.get("survey_probes", 0)) - amount
	bases[base_id] = base
	return true


func add_survey_probe(base_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var base := get_base(base_id)
	base["survey_probes"] = int(base.get("survey_probes", 0)) + amount
	bases[base_id] = base


func get_build_survey_probe_blocked_reason(base_id: String) -> String:
	var key := get_build_survey_probe_blocked_reason_key(base_id)
	if key == GateUiTextDefinition.KEY_NONE or String(key).is_empty():
		return ""
	return GateUiTextDefinition.get_text(key)


func get_build_survey_probe_blocked_reason_key(base_id: String) -> StringName:
	var cost := _get_scaled_automation_build_cost(base_id, PRODUCTION_SURVEY_PROBE)
	if cost.is_empty():
		return GateUiTextDefinition.KEY_BUILD_NOT_ENOUGH_RESOURCES
	if not can_afford(base_id, cost):
		return GateUiTextDefinition.KEY_BUILD_NOT_ENOUGH_RESOURCES
	return GateUiTextDefinition.KEY_NONE


func can_build_survey_probe(base_id: String) -> bool:
	return get_build_survey_probe_blocked_reason(base_id).is_empty()


func build_survey_probe(base_id: String) -> bool:
	if not can_build_survey_probe(base_id):
		return false
	var cost := _get_scaled_automation_build_cost(base_id, PRODUCTION_SURVEY_PROBE)
	if cost.is_empty():
		return false
	if not spend_cost(base_id, cost):
		return false
	add_survey_probe(base_id, 1)
	increment_production_lifetime_count(base_id, PRODUCTION_SURVEY_PROBE, 1)
	return true


func get_build_scan_drone_blocked_reason_key(base_id: String) -> StringName:
	var cost := _get_scaled_automation_build_cost(base_id, PRODUCTION_SCAN_DRONE)
	if cost.is_empty() or not can_afford(base_id, cost):
		return GateUiTextDefinition.KEY_BUILD_NOT_ENOUGH_RESOURCES
	return GateUiTextDefinition.KEY_NONE


func get_build_scan_drone_blocked_reason(base_id: String) -> String:
	var key := get_build_scan_drone_blocked_reason_key(base_id)
	if key == GateUiTextDefinition.KEY_NONE or String(key).is_empty():
		return ""
	return GateUiTextDefinition.get_text(key)


func can_build_drone(base_id: String) -> bool:
	return get_build_scan_drone_blocked_reason(base_id).is_empty()


func build_drone(base_id: String) -> bool:
	if not can_build_drone(base_id):
		return false
	var cost := _get_scaled_automation_build_cost(base_id, PRODUCTION_SCAN_DRONE)
	if cost.is_empty():
		return false
	if not spend_cost(base_id, cost):
		return false

	var base := get_base(base_id)
	base["drones"] = int(base.get("drones", 0)) + 1
	bases[base_id] = base
	increment_production_lifetime_count(base_id, PRODUCTION_SCAN_DRONE, 1)

	return true


func get_build_mining_ship_blocked_reason_key(base_id: String) -> StringName:
	var cost := _get_scaled_automation_build_cost(base_id, PRODUCTION_MINING_SHIP)
	if cost.is_empty() or not can_afford(base_id, cost):
		return GateUiTextDefinition.KEY_BUILD_NOT_ENOUGH_RESOURCES
	return GateUiTextDefinition.KEY_NONE


func get_build_mining_ship_blocked_reason(base_id: String) -> String:
	var key := get_build_mining_ship_blocked_reason_key(base_id)
	if key == GateUiTextDefinition.KEY_NONE or String(key).is_empty():
		return ""
	return GateUiTextDefinition.get_text(key)


func can_build_mining_ship(base_id: String) -> bool:
	return get_build_mining_ship_blocked_reason(base_id).is_empty()


func build_mining_ship(base_id: String) -> bool:
	if not can_build_mining_ship(base_id):
		return false
	var cost := _get_scaled_automation_build_cost(base_id, PRODUCTION_MINING_SHIP)
	if cost.is_empty():
		return false
	if not spend_cost(base_id, cost):
		return false

	var base := get_base(base_id)
	base["mining_ships"] = int(base.get("mining_ships", 0)) + 1
	bases[base_id] = base
	increment_production_lifetime_count(base_id, PRODUCTION_MINING_SHIP, 1)

	return true


func _get_scaled_automation_build_cost(base_id: String, production_id: String) -> Dictionary:
	return GameSession.get_scaled_production_cost(production_id, base_id)


func get_build_colony_ship_blocked_reason_key(
	base_id: String,
	prerequisite_reason_key: StringName = GateUiTextDefinition.KEY_NONE,
) -> StringName:
	if (
		prerequisite_reason_key != GateUiTextDefinition.KEY_NONE
		and not String(prerequisite_reason_key).is_empty()
	):
		return prerequisite_reason_key
	var cost := get_production_cost(PRODUCTION_COLONY_SHIP)
	if cost.is_empty() or not can_afford(base_id, cost):
		return GateUiTextDefinition.KEY_COLONY_NOT_ENOUGH_RESOURCES
	return GateUiTextDefinition.KEY_NONE


func get_build_colony_ship_blocked_reason(
	base_id: String,
	prerequisite_reason_key: StringName = GateUiTextDefinition.KEY_NONE,
) -> String:
	var key := get_build_colony_ship_blocked_reason_key(base_id, prerequisite_reason_key)
	if key == GateUiTextDefinition.KEY_NONE or String(key).is_empty():
		return ""
	return GateUiTextDefinition.get_text(key)


func can_build_colony_ship(
	base_id: String,
	prerequisite_reason_key: StringName = GateUiTextDefinition.KEY_NONE,
) -> bool:
	return get_build_colony_ship_blocked_reason_key(base_id, prerequisite_reason_key) == (
		GateUiTextDefinition.KEY_NONE
	)


func build_colony_ship(
	base_id: String,
	prerequisite_reason_key: StringName = GateUiTextDefinition.KEY_NONE,
) -> bool:
	if not can_build_colony_ship(base_id, prerequisite_reason_key):
		return false
	var cost := get_production_cost(PRODUCTION_COLONY_SHIP)
	if cost.is_empty():
		return false
	if not spend_cost(base_id, cost):
		return false

	var base := get_base(base_id)
	base["colony_ships"] = int(base.get("colony_ships", 0)) + 1
	bases[base_id] = base
	increment_production_lifetime_count(base_id, PRODUCTION_COLONY_SHIP, 1)
	return true


## Grants colony ships without cost (events / dev rollback).
func add_colony_ship(base_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var base := get_base(base_id)
	base["colony_ships"] = int(base.get("colony_ships", 0)) + amount
	bases[base_id] = base


## Removes colony ships without spending resources (consumption for travel / colony drop).
func consume_colony_ships(base_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	var base := get_base(base_id)
	var cur: int = int(base.get("colony_ships", 0))
	if cur < amount:
		return false
	base["colony_ships"] = cur - amount
	bases[base_id] = base
	return true


# Adds mining ships without any cost. Used for starting units and grants.
func add_mining_ship(base_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return

	var base := get_base(base_id)
	base["mining_ships"] = int(base.get("mining_ships", 0)) + amount
	bases[base_id] = base


# Adds drones without any cost. Used for starting units and grants.
func add_drone(base_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return

	var base := get_base(base_id)
	base["drones"] = int(base.get("drones", 0)) + amount
	bases[base_id] = base


func get_resources(base_id: String) -> Dictionary:
	var base := get_base(base_id)
	return (base.get("resources", {}) as Dictionary).duplicate(true)


func _create_empty_base() -> Dictionary:
	return {
		"resources": {},
		"population": 0,
		"drones": 0,
		"mining_ships": 0,
		"colony_ships": 0,
		"survey_probes": 0,
		"survey_probes_reserved": 0,
		"storage_capacity": _resolve_storage_capacity_level_zero_units(),
		"storage_upgrade_level": 0,
		"scan_drone_upgrade_level": 0,
		"mining_ship_upgrade_level": 0,
	}


func create_new_game_base_entry(
	population: int,
	drones: int,
	mining_ships: int,
	colony_ships: int,
	resources: Dictionary = {},
	storage_capacity: int = -1,
	survey_probes: int = 0,
) -> Dictionary:
	var base_entry: Dictionary = _create_empty_base()
	base_entry["population"] = population
	base_entry["drones"] = drones
	base_entry["mining_ships"] = mining_ships
	base_entry["colony_ships"] = colony_ships
	base_entry["survey_probes"] = maxi(0, survey_probes)
	base_entry["storage_capacity"] = (
		storage_capacity if storage_capacity >= 0 else _resolve_storage_capacity_level_zero_units()
	)
	base_entry["resources"] = resources.duplicate(true)
	base_entry["production_lifetime_counts"] = {
		PRODUCTION_SCAN_DRONE: maxi(0, drones),
		PRODUCTION_MINING_SHIP: maxi(0, mining_ships),
		PRODUCTION_SURVEY_PROBE: maxi(0, survey_probes),
		PRODUCTION_COLONY_SHIP: maxi(0, colony_ships),
	}
	return base_entry


## Replaces a base slot with the v0.1 new-game kit (colonization start package).
func apply_start_kit_to_base(
	base_id: String,
	population: int,
	drones: int,
	mining_ships: int,
	colony_ships: int,
	resources: Dictionary,
	storage_capacity: int,
	survey_probes: int,
) -> void:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return
	bases[bid] = create_new_game_base_entry(
		population,
		drones,
		mining_ships,
		colony_ships,
		resources,
		storage_capacity,
		survey_probes,
	)


func to_save_data() -> Dictionary:
	return bases.duplicate(true)


func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	bases = data.duplicate(true)
	for bid_var: Variant in bases.keys():
		var bid: String = str(bid_var).strip_edges()
		if bid.is_empty():
			continue
		ensure_production_lifetime_counts(bid)
