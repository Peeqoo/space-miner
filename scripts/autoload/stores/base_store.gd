class_name BaseStore
extends RefCounted

const RESOURCE_ORE := "ore"
const RESOURCE_FUEL := "fuel"
const RESOURCE_FOOD := "food"

const BASE_EARTH := "earth"

const DRONE_ORE_COST: int = 10
const MINING_SHIP_ORE_COST: int = 25

var bases: Dictionary = {
	BASE_EARTH: {
		"resources": {
			RESOURCE_ORE: 50,
			RESOURCE_FUEL: 0,
			RESOURCE_FOOD: 0,
		},
		"population": 1,
		"drones": 0,
		"mining_ships": 0,
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
	return get_resource_amount(base_id, RESOURCE_ORE) >= DRONE_ORE_COST


func build_drone(base_id: String) -> bool:
	if not spend_resource(base_id, RESOURCE_ORE, DRONE_ORE_COST):
		return false

	var base := get_base(base_id)
	base["drones"] = int(base.get("drones", 0)) + 1
	bases[base_id] = base

	return true


func can_build_mining_ship(base_id: String) -> bool:
	return get_resource_amount(base_id, RESOURCE_ORE) >= MINING_SHIP_ORE_COST


func build_mining_ship(base_id: String) -> bool:
	if not spend_resource(base_id, RESOURCE_ORE, MINING_SHIP_ORE_COST):
		return false

	var base := get_base(base_id)
	base["mining_ships"] = int(base.get("mining_ships", 0)) + 1
	bases[base_id] = base

	return true


func _create_empty_base() -> Dictionary:
	return {
		"resources": {
			RESOURCE_ORE: 0,
			RESOURCE_FUEL: 0,
			RESOURCE_FOOD: 0,
		},
		"population": 0,
		"drones": 0,
		"mining_ships": 0,
	}
