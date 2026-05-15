## Data-driven upgrade tier (Phase 5.5). Balancing lives in `.tres` files; code applies mechanics only.
class_name UpgradeDefinition
extends Resource

@export var id: StringName = &""
@export var category: StringName = &""
# Expected: "storage", "scan_drone", "mining_ship"

@export var level: int = 0
@export var title: String = ""
@export var cost: Dictionary = {}

## Level 0 is not purchasable.
@export var purchasable: bool = true

## Storage — total capacity units at this tier (-1 = unused).
@export var storage_capacity_units: int = -1

## ScanDrone — display / gameplay hints (-1 or <0 = unused).
@export var scan_speed_percent: int = -1
@export var scan_duration_multiplier: float = -1.0
@export var mining_yield_bonus_per_support_drone_percent: int = -1

## MiningShip — cargo as percent of base mission capacity (-1 = unused).
@export var cargo_capacity_percent: int = -1

@export var applies_to_new_jobs_only: bool = false
@export var note: String = ""
