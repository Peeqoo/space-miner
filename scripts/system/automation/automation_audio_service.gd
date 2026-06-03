## World SFX / loop helpers for automation units. No mission or store logic.
class_name AutomationAudioService
extends RefCounted


func play_automation_sfx(event_id: StringName, source_node: Node = null) -> void:
	var source_2d := source_node as Node2D
	if source_2d == null or not is_instance_valid(source_2d):
		return
	AudioManager.play_world_sfx_optional(event_id, source_2d.global_position)


func play_unit_travel_sfx(
	event_id: StringName,
	unit: Node,
	target_node: Node = null,
) -> void:
	var source: Node2D = audio_source_node(unit as Node2D, target_node as Node2D)
	if source == null:
		return

	var cooldown_key: StringName = event_id
	if unit != null and is_instance_valid(unit):
		cooldown_key = StringName("%s_%d" % [String(event_id), unit.get_instance_id()])

	AudioManager.play_world_sfx_with_cooldown_optional(
		event_id,
		source.global_position,
		cooldown_key,
	)


func play_scan_drone_launch(unit: Node, target_node: Node = null) -> void:
	play_unit_travel_sfx(&"scan_drone_launch", unit, target_node)


func play_scan_drone_arrive(unit: Node, target_node: Node = null) -> void:
	play_unit_travel_sfx(&"scan_drone_arrive", unit, target_node)


func play_mining_ship_launch(unit: Node, target_node: Node = null) -> void:
	play_unit_travel_sfx(&"mining_ship_launch", unit, target_node)


func play_mining_ship_arrive(unit: Node, target_node: Node = null) -> void:
	play_unit_travel_sfx(&"mining_ship_arrive", unit, target_node)


func play_mining_resource_tick(unit: Node, _target_node: Node = null) -> void:
	var unit_2d := unit as Node2D
	if unit_2d == null or not is_instance_valid(unit_2d):
		return
	var cooldown_key := StringName("mining_resource_tick_%d" % unit_2d.get_instance_id())
	AudioManager.play_world_sfx_with_cooldown_optional(
		&"mining_resource_tick",
		unit_2d.global_position,
		cooldown_key,
	)


func start_scan_orbit_audio(unit: Node, target_node: Node = null) -> void:
	var audio_source: Node2D = audio_source_node(unit as Node2D, target_node as Node2D)
	if audio_source == null:
		return
	play_scan_drone_arrive(unit, target_node)
	AudioManager.play_world_loop_optional(
		&"scan_loop",
		scan_orbit_loop_id(unit),
		audio_source,
	)


func stop_scan_orbit_audio(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	AudioManager.stop_world_loop_optional(scan_orbit_loop_id(unit))


func scan_orbit_loop_id(unit: Node) -> StringName:
	return StringName("scan_orbit_%d" % unit.get_instance_id())


func audio_source_node(unit: Node, target_node: Node = null) -> Node:
	var unit_2d := unit as Node2D
	if unit_2d != null and is_instance_valid(unit_2d):
		return unit_2d
	var target_2d := target_node as Node2D
	if target_2d != null and is_instance_valid(target_2d):
		return target_2d
	return null


func audio_node_for_base(
	spawner: SystemSpawner,
	base_id: String,
	unit_fallback: Node = null,
) -> Node:
	var bid: String = base_id.strip_edges()
	if spawner != null and not bid.is_empty():
		var base_node: Node = spawner.get_spawned_object(bid)
		if base_node != null:
			return base_node
	if unit_fallback != null and is_instance_valid(unit_fallback):
		return unit_fallback
	return null
