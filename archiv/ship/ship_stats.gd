extends Resource
class_name ShipStats

@export_category("Flight")
@export var max_speed: float = 160.0
@export var acceleration: float = 180.0
@export var brake_acceleration: float = 110.0
@export var rotation_speed_deg: float = 200.0
@export var passive_drag: float = 8.0

@export_category("Steering")
@export var steering_lerp_speed: float = 7.0
@export var turn_steering_lerp_speed: float = 100.0

@export_category("Precision / Stabilizer")
@export var stabilizer_drag: float = 220.0
@export var stabilizer_rotation_multiplier: float = 1.0
@export var stabilizer_energy_cost_per_sec: float = 8.0
@export var stabilizer_steering_multiplier: float = 1.8
@export var stabilizer_speed_reduction: float = 60.0

@export_category("Emergency")
@export var burst_acceleration: float = 220.0
@export var burst_fuel_cost: float = 8.0
@export var burst_cooldown: float = 10.0
@export var burst_max_speed: float = 260.0
@export var burst_duration: float = 2.8
@export var burst_decay: float = 90.0

@export_category("Resources")
@export var max_hull: float = 100.0
@export var max_fuel: float = 100.0
@export var max_energy: float = 100.0
@export var energy_recharge_per_sec: float = 6.0

@export_category("Consumption")
@export var thrust_fuel_cost_per_sec: float = 3.0

@export_category("Damage")
@export var impact_damage_multiplier: float = 0.05
@export var impact_damage_minimum: float = 1.0
@export var impact_damage_speed_threshold: float = 20.0
@export var impact_glancing_min_factor: float = 0.35

@export_category("Feedback")
@export var impact_shake_min: float = 0.25
@export var impact_shake_max: float = 0.75
@export var impact_shake_damage_reference: float = 8.0
@export var impact_shake_curve_power: float = 1.3
