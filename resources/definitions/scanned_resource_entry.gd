class_name ScannedResourceEntry
extends Resource

enum Layer {
	BASIC,
	DEEP,
	SPECIAL
}

@export var resource_id: StringName = &""
@export_range(0, 100, 1) var richness_percent: int = 35
@export var deposit_amount: int = 10000
@export var layer: Layer = Layer.BASIC
@export_range(1, 10, 1) var extraction_difficulty: int = 1


func get_richness_label() -> String:
	if richness_percent >= 80:
		return "Dense"
	if richness_percent >= 50:
		return "Rich"
	if richness_percent >= 25:
		return "Moderate"
	if richness_percent >= 10:
		return "Sparse"
	return "Trace"


func get_richness_multiplier() -> float:
	return float(richness_percent) / 100.0


func is_depleted() -> bool:
	return deposit_amount <= 0


func can_be_mined_by_tier(mining_tier: int) -> bool:
	return mining_tier >= extraction_difficulty


func get_layer_id() -> StringName:
	match layer:
		Layer.BASIC:
			return &"basic"
		Layer.DEEP:
			return &"deep"
		Layer.SPECIAL:
			return &"special"
		_:
			return &"basic"
