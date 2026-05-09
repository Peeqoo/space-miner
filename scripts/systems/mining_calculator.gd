class_name MiningCalculator
extends RefCounted


static func calculate_yield_per_second(
	base_rate: float,
	entry: ScannedResourceEntry,
	mining_efficiency: float = 1.0,
	planet_modifier: float = 1.0
) -> float:
	if entry == null:
		return 0.0
	return base_rate * entry.get_richness_multiplier() * mining_efficiency * planet_modifier


static func calculate_extract_amount(
	delta: float,
	base_rate: float,
	entry: ScannedResourceEntry,
	mining_efficiency: float = 1.0,
	planet_modifier: float = 1.0
) -> int:
	if entry == null or entry.is_depleted():
		return 0
	var raw_amount := calculate_yield_per_second(base_rate, entry, mining_efficiency, planet_modifier) * delta
	var amount := max(1, int(floor(raw_amount)))
	return mini(amount, entry.deposit_amount)
