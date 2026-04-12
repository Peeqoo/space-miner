extends CharacterBody2D
class_name ShipController

signal fuel_changed(current: float, max_value: float)
signal energy_changed(current: float, max_value: float)
signal hull_changed(current: float, max_value: float)
signal speed_changed(speed: float)
signal burst_triggered()

@export var stats: ShipStats

var input_component: ShipInputComponent
var movement_component: ShipMovementComponent
var resource_component: ShipResourceComponent

var burst_cooldown_left: float = 0.0

func _ready() -> void:
	if stats == null:
		push_error("ShipStats resource missing on PlayerShip.")
		set_physics_process(false)
		return

	input_component = ShipInputComponent.new()
	movement_component = ShipMovementComponent.new()
	resource_component = ShipResourceComponent.new()

	resource_component.initialize(stats)
	movement_component.set_from_body(velocity)

	_emit_all_stats()

func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_recharge_energy(delta)

	var input_state := input_component.get_input()

	var can_stabilize := _can_use_stabilizer(delta)
	var used_stabilizer_rotation := movement_component.handle_rotation(
		self,
		stats,
		input_state,
		can_stabilize,
		delta
	)

	var movement_result := movement_component.handle_movement(
		self,
		stats,
		input_state,
		can_stabilize,
		resource_component.fuel > 0.0,
		delta
	)

	if used_stabilizer_rotation or movement_result["used_stabilizer"]:
		resource_component.consume_energy(stats.stabilizer_energy_cost_per_sec * delta)

	if movement_result["used_thrust"]:
		resource_component.consume_fuel(stats.thrust_fuel_cost_per_sec * delta)

	_handle_burst(input_state)

	move_and_slide()

	movement_component.set_from_body(velocity)
	_emit_runtime_stats()

func _handle_burst(input_state: Dictionary) -> void:
	if not input_state["burst"]:
		return
	if burst_cooldown_left > 0.0:
		return
	if resource_component.fuel < stats.burst_fuel_cost:
		return

	movement_component.apply_burst(self, stats)
	resource_component.consume_fuel(stats.burst_fuel_cost)
	burst_cooldown_left = stats.burst_cooldown
	burst_triggered.emit()

func _tick_cooldowns(delta: float) -> void:
	if burst_cooldown_left > 0.0:
		burst_cooldown_left = max(0.0, burst_cooldown_left - delta)

func _recharge_energy(delta: float) -> void:
	resource_component.recharge_energy(
		stats.energy_recharge_per_sec * delta,
		stats.max_energy
	)

func _can_use_stabilizer(delta: float) -> bool:
	return resource_component.energy >= stats.stabilizer_energy_cost_per_sec * delta

func apply_damage(amount: float) -> void:
	resource_component.apply_damage(amount)
	hull_changed.emit(resource_component.hull, stats.max_hull)

func repair_full() -> void:
	resource_component.repair_full(stats.max_hull)
	hull_changed.emit(resource_component.hull, stats.max_hull)

func refuel_full() -> void:
	resource_component.refuel_full(stats.max_fuel)
	fuel_changed.emit(resource_component.fuel, stats.max_fuel)

func recharge_full() -> void:
	resource_component.recharge_full(stats.max_energy)
	energy_changed.emit(resource_component.energy, stats.max_energy)

func get_speed() -> float:
	return velocity.length()

func _emit_runtime_stats() -> void:
	fuel_changed.emit(resource_component.fuel, stats.max_fuel)
	energy_changed.emit(resource_component.energy, stats.max_energy)
	hull_changed.emit(resource_component.hull, stats.max_hull)
	speed_changed.emit(get_speed())

func _emit_all_stats() -> void:
	fuel_changed.emit(resource_component.fuel, stats.max_fuel)
	energy_changed.emit(resource_component.energy, stats.max_energy)
	hull_changed.emit(resource_component.hull, stats.max_hull)
	speed_changed.emit(get_speed())
