extends Resource
class_name ShipStats

@export_category("Flight")
@export var max_speed: float = 320.0
@export var acceleration: float = 180.0
@export var brake_acceleration: float = 150.0
@export var rotation_speed_deg: float = 80.0
@export var passive_drag: float = 8.0

@export_category("Precision / Stabilizer")
@export var stabilizer_drag: float = 20.0
@export var stabilizer_rotation_multiplier: float = 0.75
@export var stabilizer_energy_cost_per_sec: float = 8.0

@export_category("Emergency")
@export var burst_impulse: float = 180.0
@export var burst_fuel_cost: float = 12.0
@export var burst_cooldown: float = 0.75

@export_category("Resources")
@export var max_hull: float = 100.0
@export var max_fuel: float = 100.0
@export var max_energy: float = 100.0
@export var energy_recharge_per_sec: float = 6.0

@export_category("Consumption")
@export var thrust_fuel_cost_per_sec: float = 10.0
