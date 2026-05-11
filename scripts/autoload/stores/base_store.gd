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
const INITIAL_STORAGE_CAPACITY: int = 100
const STORAGE_UPGRADE_I_CAPACITY_BONUS: int = 100
const STORAGE_UPGRADE_I_COST: Dictionary = {
	"Iron": 30,
	"Copper": 10,
}

var bases: Dictionary = {
	BASE_EARTH: {
		"resources": {},
		"population": 1,
		"drones": 1,
		"mining_ships": 1,
		"storage_capacity": INITIAL_STORAGE_CAPACITY,
		"storage_upgrade_level": 0,
	}
}


func get_base(base_id: String) -> Dictionary:
	if not bases.has(base_id):
		bases[base_id] = _create_empty_base()

	var base_entry: Dictionary = bases[base_id]
	_normalize_base_storage_fields(base_entry)

	return base_entry


func _normalize_base_storage_fields(base: Dictionary) -> void:
	if not base.has("storage_capacity"):
		base["storage_capacity"] = INITIAL_STORAGE_CAPACITY
	elif int(base["storage_capacity"]) < 0:
		base["storage_capacity"] = INITIAL_STORAGE_CAPACITY

	if not base.has("storage_upgrade_level"):
		base["storage_upgrade_level"] = 0


func get_storage_used(base_id: String) -> int:
	var resources: Variant = get_base(base_id).get("resources", {})
	if not resources is Dictionary:
		return 0

	var total: int = 0

	for amt_var: Variant in (resources as Dictionary).values():
		total += maxi(0, int(amt_var))

	return total


func get_storage_capacity(base_id: String) -> int:
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


func get_storage_upgrade_i_cost() -> Dictionary:
	return STORAGE_UPGRADE_I_COST.duplicate(true)


func is_storage_upgrade_i_bought(base_id: String) -> bool:
	return int(get_base(base_id).get("storage_upgrade_level", 0)) >= 1


func can_buy_storage_upgrade_i(base_id: String) -> bool:
	if is_storage_upgrade_i_bought(base_id):
		return false

	return can_afford(base_id, STORAGE_UPGRADE_I_COST)


func buy_storage_upgrade_i(base_id: String) -> bool:
	if not can_buy_storage_upgrade_i(base_id):
		return false

	if not spend_cost(base_id, STORAGE_UPGRADE_I_COST):
		return false

	var base_up: Dictionary = get_base(base_id)
	var cap_now: int = get_storage_capacity(base_id)
	base_up["storage_capacity"] = cap_now + STORAGE_UPGRADE_I_CAPACITY_BONUS
	base_up["storage_upgrade_level"] = 1
	bases[base_id] = base_up

	return true


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
	}
