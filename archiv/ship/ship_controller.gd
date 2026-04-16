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
var damage_component: ShipDamageComponent

var burst_cooldown_left: float = 0.0
var burst_recovery_pending: bool = false

var debug_label: Label
var display_speed: float = 0.0
var last_pre_impact_speed: float = 0.0

var damage_number_scene: PackedScene = preload("res://scenes/ui/damage_number.tscn")
var ship_camera: ShipCamera
var camera_rig: ShipCameraRig

func _ready() -> void:
	if stats == null:
		push_error("ShipStats resource missing on PlayerShip.")
		set_physics_process(false)
		return

	input_component = ShipInputComponent.new()
	movement_component = ShipMovementComponent.new()
	resource_component = ShipResourceComponent.new()
	damage_component = ShipDamageComponent.new()

	resource_component.initialize(stats)
	movement_component.set_from_body(velocity)

	camera_rig = $ShipCameraRig as ShipCameraRig
	ship_camera = $ShipCameraRig/ShipCamera as ShipCamera

	if ship_camera != null:
		ship_camera.set_target(self)

	debug_label = get_tree().current_scene.find_child("DebugLabel", true, false) as Label
	display_speed = 0.0
	last_pre_impact_speed = 0.0

	_emit_all_stats()

func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_recharge_energy(delta)
	movement_component.tick(delta)

	var input_state: Dictionary = input_component.get_input()
	var can_stabilize: bool = _can_use_stabilizer(delta)

	var used_stabilizer_rotation: bool = movement_component.handle_rotation(
		self,
		stats,
		input_state,
		can_stabilize,
		delta
	)

	var movement_result: Dictionary = movement_component.handle_movement(
		self,
		stats,
		input_state,
		can_stabilize,
		resource_component.fuel > 0.0,
		delta
	)

	if used_stabilizer_rotation or bool(movement_result["used_stabilizer"]):
		resource_component.consume_energy(stats.stabilizer_energy_cost_per_sec * delta)

	if bool(movement_result["used_thrust"]):
		resource_component.consume_fuel(stats.thrust_fuel_cost_per_sec * delta)

	_handle_burst(input_state)

	last_pre_impact_speed = velocity.length()

	move_and_slide()
	_handle_impact_damage()

	movement_component.set_from_body(velocity)
	_update_burst_cooldown_state()

	display_speed = lerp(display_speed, get_speed(), 0.2)

	_emit_runtime_stats()
	_update_debug_label(input_state)

func _handle_burst(input_state: Dictionary) -> void:
	if not bool(input_state["burst"]):
		return
	if burst_cooldown_left > 0.0:
		return
	if burst_recovery_pending:
		return
	if resource_component.fuel < stats.burst_fuel_cost:
		return

	movement_component.apply_burst(self, stats)
	resource_component.consume_fuel(stats.burst_fuel_cost)
	burst_recovery_pending = true
	burst_triggered.emit()

func _handle_impact_damage() -> void:
	var collision_count: int = get_slide_collision_count()
	var is_colliding_now: bool = collision_count > 0

	if not damage_component.should_apply_impact_damage(is_colliding_now):
		return

	var impact_speed: float = last_pre_impact_speed
	if impact_speed < stats.impact_damage_speed_threshold:
		return

	var collision: KinematicCollision2D = get_slide_collision(0)
	if collision == null:
		return

	var collision_normal: Vector2 = collision.get_normal()
	if last_pre_impact_speed <= 0.001:
		return

	# PRE-IMPACT Richtung benutzen, nicht die evtl. schon korrigierte post-collision velocity
	var velocity_direction: Vector2 = movement_component.current_velocity.normalized()
	if velocity_direction.length() <= 0.001:
		velocity_direction = Vector2.UP.rotated(rotation)

	var damage: float = damage_component.compute_impact_damage(
		impact_speed,
		collision_normal,
		velocity_direction,
		stats.impact_damage_multiplier,
		stats.impact_damage_minimum,
		stats.impact_glancing_min_factor
	)

	apply_damage(damage)
	_spawn_damage_number(damage)
	_apply_impact_feedback(damage)

func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		push_error("Damage number scene is not loaded.")
		return

	var instance: Node = damage_number_scene.instantiate()
	if instance == null:
		push_error("Failed to instantiate damage number scene.")
		return

	var spawn_position: Vector2 = global_position + Vector2(
		randf_range(-8.0, 8.0),
		-12.0
	)

	if instance is Node2D:
		(instance as Node2D).global_position = spawn_position
	else:
		push_error("Damage number instance is not a Node2D.")
		instance.queue_free()
		return

	get_tree().current_scene.add_child(instance)

	if instance.has_method("setup"):
		instance.call("setup", amount)
	else:
		push_error("Damage number instance has no setup(amount) method.")

func _apply_impact_feedback(damage_amount: float) -> void:
	if camera_rig == null:
		print("camera_rig is NULL")
		return

	var normalized_damage: float = clamp(
		damage_amount / stats.impact_shake_damage_reference,
		0.0,
		1.0
	)
	var curved_damage: float = pow(normalized_damage, stats.impact_shake_curve_power)

	var trauma: float = lerp(
		stats.impact_shake_min,
		stats.impact_shake_max,
		curved_damage
	)

	print("damage: ", damage_amount, " trauma: ", trauma)
	camera_rig.add_trauma(trauma)
func _update_burst_cooldown_state() -> void:
	if not burst_recovery_pending:
		return

	if movement_component.is_burst_active():
		return

	if movement_component.is_above_normal_speed(stats):
		return

	burst_recovery_pending = false
	burst_cooldown_left = stats.burst_cooldown

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

func _update_debug_label(input_state: Dictionary) -> void:
	if debug_label == null:
		return

	var speed_to_show: float = display_speed

	if abs(speed_to_show - stats.max_speed) < 1.0:
		speed_to_show = stats.max_speed

	if abs(speed_to_show - stats.burst_max_speed) < 1.0:
		speed_to_show = stats.burst_max_speed

	debug_label.text = \
		"Speed: %d\nPreImpact: %d\nFuel: %.1f\nEnergy: %.1f\nHull: %.1f\nStabilize: %s\nBurst Active: %s\nBurst Recovery: %s\nBurst CD: %.2f\nColliding: %s" % [
			int(round(speed_to_show)),
			int(round(last_pre_impact_speed)),
			resource_component.fuel,
			resource_component.energy,
			resource_component.hull,
			str(bool(input_state["stabilize"])),
			str(movement_component.is_burst_active()),
			str(burst_recovery_pending),
			burst_cooldown_left,
			str(get_slide_collision_count() > 0)
		]
