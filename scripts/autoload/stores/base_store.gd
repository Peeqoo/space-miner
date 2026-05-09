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

var bases: Dictionary = {
	BASE_EARTH: {
		"resources": {},
		"population": 1,
		"drones": 1,
		"mining_ships": 1,
	}
}


func get_base(base_id: String) -> Dictionary:
	if not bases.has(base_id):
		bases[base_id] = _create_empty_base()

	return bases[base_id]


func get_resource_amount(base_id: String, resource_id: String) -> int:
	var base := get_base(base_id)
	var resources: Dictionary = base.get("resources", {})
	return int(resources.get(resource_id, 0))


func add_resource(base_id: String, resource_id: String, amount: int) -> void:
	if amount <= 0:
		return

	var base := get_base(base_id)
	var resources: Dictionary = base.get("resources", {})

	resources[resource_id] = get_resource_amount(base_id, resource_id) + amount
	base["resources"] = resources
	bases[base_id] = base


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
	}
