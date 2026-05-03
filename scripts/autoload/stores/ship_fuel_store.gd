class_name ShipFuelStore
extends RefCounted

var current_fuel: float = 100.0
var max_fuel: float = 100.0


func get_current() -> float:
	return current_fuel


func get_max() -> float:
	return max_fuel


func get_percent() -> float:
	if max_fuel <= 0.0:
		return 0.0

	return current_fuel / max_fuel


func has_fuel(amount: float) -> bool:
	return current_fuel >= amount


func consume(amount: float) -> bool:
	if amount <= 0.0:
		return true

	if current_fuel < amount:
		return false

	current_fuel = maxf(current_fuel - amount, 0.0)
	return true


func add(amount: float) -> void:
	if amount <= 0.0:
		return

	current_fuel = minf(current_fuel + amount, max_fuel)


func set_current(amount: float) -> void:
	current_fuel = clampf(amount, 0.0, max_fuel)


func set_max(amount: float, refill: bool = false) -> void:
	max_fuel = maxf(amount, 0.0)

	if refill:
		current_fuel = max_fuel
	else:
		current_fuel = minf(current_fuel, max_fuel)
