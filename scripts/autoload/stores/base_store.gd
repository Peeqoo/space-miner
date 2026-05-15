class_name BaseStore
extends RefCounted

const RESOURCE_ORE := "ore"  # deprecated
const RESOURCE_FUEL := "fuel"  # deprecated
const RESOURCE_FOOD := "food"  # deprecated

const BASE_EARTH := "earth"

# deprecated — ersetzt durch DRONE_COST / MINING_SHIP_COST
const DRONE_ORE_COST: int = 10  # deprecated
const MINING_SHIP_ORE_COST: int = 25  # deprecated

const DRONE_COST: Dictionary = {
	"Iron": 10,
	"Copper": 5,
}

const MINING_SHIP_COST: Dictionary = {
	"Iron": 25,
	"Aluminum": 10,
	"Hydrogen": 5,
}

const COLONY_SHIP_COST: Dictionary = {
	"Iron": 80,
	"Aluminum": 40,
	"Water": 30,
	"Carbon": 20,
	"Hydrogen": 20,
}

## Total cargo units (summed stack sizes) Earth can hold at game start (Phase 5.1).
## Also used as fallback when no upgrade catalog is bound.
const INITIAL_STORAGE_CAPACITY: int = 100

var bases: Dictionary = {
	BASE_EARTH: {
		"resources": {},
		"population": 1,
		"drones": 1,
		"mining_ships": 1,
		"storage_capacity": INITIAL_STORAGE_CAPACITY,
		"storage_upgrade_level": 0,
		"scan_drone_upgrade_level": 0,
		"mining_ship_upgrade_level": 0,
	}
}

## Phase 5.5: loaded by `GameSession`; balancing comes from `data/upgrades/*.tres`.
var _upgrade_catalog: UpgradeCatalog = null


func set_upgrade_catalog(catalog: UpgradeCatalog) -> void:
	_upgrade_catalog = catalog


func get_upgrade_catalog() -> UpgradeCatalog:
	return _upgrade_catalog


func get_base(base_id: String) -> Dictionary:
	if not bases.has(base_id):
		bases[base_id] = _create_empty_base()

	var base_entry: Dictionary = bases[base_id]
	_normalize_base_storage_fields(base_entry)
	_normalize_scan_drone_upgrade_fields(base_entry)
	_normalize_mining_ship_upgrade_fields(base_entry)

	_sync_storage_capacity_from_definition(base_id, base_entry)

	return base_entry


func _normalize_mining_ship_upgrade_fields(base: Dictionary) -> void:
	if not base.has("mining_ship_upgrade_level"):
		base["mining_ship_upgrade_level"] = 0


func _normalize_scan_drone_upgrade_fields(base: Dictionary) -> void:
	if not base.has("scan_drone_upgrade_level"):
		base["scan_drone_upgrade_level"] = 0


func _normalize_base_storage_fields(base: Dictionary) -> void:
	if not base.has("storage_capacity"):
		base["storage_capacity"] = INITIAL_STORAGE_CAPACITY
	elif int(base["storage_capacity"]) < 0:
		base["storage_capacity"] = INITIAL_STORAGE_CAPACITY

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

	return maxi(0, int(get_base(base_id).get("storage_capacity", INITIAL_STORAGE_CAPACITY)))


func get_storage_free(base_id: String) -> int:
	return maxi(0, get_storage_capacity(base_id) - get_storage_used(base_id))


func can_accept_resource(base_id: String, amount: int) -> bool:
	return amount <= 0 or get_storage_free(base_id) >= amount


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


## --- Phase 5.5 upgrades (data-driven). Legacy `*_upgrade_i_*` names remain as thin wrappers. ---


func get_storage_upgrade_i_cost(base_id: String = BASE_EARTH) -> Dictionary:
	if _upgrade_catalog == null:
		return {}
	var nxt := _upgrade_catalog.get_next_definition(&"storage", get_upgrade_level(base_id, &"storage"))
	if nxt == null:
		return {}
	return nxt.cost.duplicate(true)


func is_storage_upgrade_i_bought(base_id: String) -> bool:
	return get_upgrade_level(base_id, &"storage") >= 1


func can_buy_storage_upgrade_i(base_id: String) -> bool:
	if _upgrade_catalog == null:
		return false
	var nxt := _upgrade_catalog.get_next_definition(&"storage", get_upgrade_level(base_id, &"storage"))
	if nxt == null:
		return false
	return can_afford_upgrade(base_id, nxt)


func buy_storage_upgrade_i(base_id: String) -> bool:
	if _upgrade_catalog == null:
		return false
	var nxt := _upgrade_catalog.get_next_definition(&"storage", get_upgrade_level(base_id, &"storage"))
	if nxt == null:
		return false
	return buy_next_upgrade(base_id, nxt)


func get_scan_drone_upgrade_i_cost(base_id: String = BASE_EARTH) -> Dictionary:
	if _upgrade_catalog == null:
		return {}
	var nxt := _upgrade_catalog.get_next_definition(&"scan_drone", get_upgrade_level(base_id, &"scan_drone"))
	if nxt == null:
		return {}
	return nxt.cost.duplicate(true)


func is_scan_drone_upgrade_i_bought(base_id: String) -> bool:
	return get_upgrade_level(base_id, &"scan_drone") >= 1


func get_scan_drone_scan_duration_multiplier(base_id: String) -> float:
	if _upgrade_catalog != null:
		var def := _upgrade_catalog.get_current_definition(
			&"scan_drone",
			get_upgrade_level(base_id, &"scan_drone")
		)
		if def != null and def.scan_duration_multiplier >= 0.0:
			return def.scan_duration_multiplier
	return 1.0


func can_buy_scan_drone_upgrade_i(base_id: String) -> bool:
	if _upgrade_catalog == null:
		return false
	var nxt := _upgrade_catalog.get_next_definition(&"scan_drone", get_upgrade_level(base_id, &"scan_drone"))
	if nxt == null:
		return false
	return can_afford_upgrade(base_id, nxt)


func buy_scan_drone_upgrade_i(base_id: String) -> bool:
	if _upgrade_catalog == null:
		return false
	var nxt := _upgrade_catalog.get_next_definition(&"scan_drone", get_upgrade_level(base_id, &"scan_drone"))
	if nxt == null:
		return false
	return buy_next_upgrade(base_id, nxt)


func get_mining_ship_upgrade_i_cost(base_id: String = BASE_EARTH) -> Dictionary:
	if _upgrade_catalog == null:
		return {}
	var nxt := _upgrade_catalog.get_next_definition(&"mining_ship", get_upgrade_level(base_id, &"mining_ship"))
	if nxt == null:
		return {}
	return nxt.cost.duplicate(true)


func is_mining_ship_upgrade_i_bought(base_id: String) -> bool:
	return get_upgrade_level(base_id, &"mining_ship") >= 1


func get_mining_ship_cargo_capacity_multiplier(base_id: String) -> float:
	if _upgrade_catalog != null:
		var def := _upgrade_catalog.get_current_definition(
			&"mining_ship",
			get_upgrade_level(base_id, &"mining_ship")
		)
		if def != null and def.cargo_capacity_percent >= 0:
			return float(def.cargo_capacity_percent) / 100.0
	return 1.0


func can_buy_mining_ship_upgrade_i(base_id: String) -> bool:
	if _upgrade_catalog == null:
		return false
	var nxt := _upgrade_catalog.get_next_definition(&"mining_ship", get_upgrade_level(base_id, &"mining_ship"))
	if nxt == null:
		return false
	return can_afford_upgrade(base_id, nxt)


func buy_mining_ship_upgrade_i(base_id: String) -> bool:
	if _upgrade_catalog == null:
		return false
	var nxt := _upgrade_catalog.get_next_definition(&"mining_ship", get_upgrade_level(base_id, &"mining_ship"))
	if nxt == null:
		return false
	return buy_next_upgrade(base_id, nxt)


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


func format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for resource_id in cost:
		parts.append("%s: %d" % [str(resource_id), int(cost[resource_id])])
	return ", ".join(parts)


func get_population(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("population", 0))


func get_drone_count(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("drones", 0))


func get_mining_ship_count(base_id: String) -> int:
	var base := get_base(base_id)
	return int(base.get("mining_ships", 0))


func can_build_drone(base_id: String) -> bool:
	return can_afford(base_id, DRONE_COST)


func build_drone(base_id: String) -> bool:
	if not spend_cost(base_id, DRONE_COST):
		return false

	var base := get_base(base_id)
	base["drones"] = int(base.get("drones", 0)) + 1
	bases[base_id] = base

	return true


func can_build_mining_ship(base_id: String) -> bool:
	return can_afford(base_id, MINING_SHIP_COST)


func build_mining_ship(base_id: String) -> bool:
	if not spend_cost(base_id, MINING_SHIP_COST):
		return false

	var base := get_base(base_id)
	base["mining_ships"] = int(base.get("mining_ships", 0)) + 1
	bases[base_id] = base

	return true


func can_build_colony_ship(base_id: String) -> bool:
	return can_afford(base_id, COLONY_SHIP_COST)


func build_colony_ship(base_id: String) -> bool:
	return spend_cost(base_id, COLONY_SHIP_COST)


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
		"storage_capacity": INITIAL_STORAGE_CAPACITY,
		"storage_upgrade_level": 0,
		"scan_drone_upgrade_level": 0,
		"mining_ship_upgrade_level": 0,
	}
