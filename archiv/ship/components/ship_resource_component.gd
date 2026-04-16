extends RefCounted
class_name ShipResourceComponent

var fuel: float = 0.0
var energy: float = 0.0
var hull: float = 0.0

func initialize(stats: ShipStats) -> void:
	fuel = stats.max_fuel
	energy = stats.max_energy
	hull = stats.max_hull

func consume_fuel(amount: float) -> void:
	fuel = max(0.0, fuel - amount)

func consume_energy(amount: float) -> void:
	energy = max(0.0, energy - amount)

func recharge_energy(amount: float, max_value: float) -> void:
	energy = min(max_value, energy + amount)

func apply_damage(amount: float) -> void:
	hull = max(0.0, hull - amount)

func repair_full(max_value: float) -> void:
	hull = max_value

func refuel_full(max_value: float) -> void:
	fuel = max_value

func recharge_full(max_value: float) -> void:
	energy = max_value
