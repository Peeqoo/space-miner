## Applies discovery visibility (hidden / signal / known) to spawned system objects.
class_name SystemDiscoveryController
extends Node

const SIGNAL_MARKER_SCENE: PackedScene = preload("res://scenes/system/objects/signal_marker.tscn")

var spawner: SystemSpawner = null
var selection: SystemSelectionController = null

var _markers_by_object_id: Dictionary = {}


func setup(p_spawner: SystemSpawner, p_selection: SystemSelectionController) -> void:
	spawner = p_spawner
	selection = p_selection


func apply_for_system(system_definition: SystemDefinition) -> void:
	_clear_all_markers()

	if system_definition == null or spawner == null:
		return

	var system_id := system_definition.id.strip_edges()
	if system_id.is_empty():
		return

	for body_def_variant: Variant in system_definition.bodies:
		var body_def := body_def_variant as SystemBodyDefinition
		if body_def == null:
			continue

		var body := spawner.get_spawned_object(body_def.id) as SystemBody
		if body == null:
			continue

		_apply_discovery_to_world_object(system_id, body_def.id, body, body_def)

	for poi_def_variant: Variant in system_definition.pois:
		var poi_def := poi_def_variant as PointOfInterestDefinition
		if poi_def == null:
			continue

		var poi := spawner.get_spawned_object(poi_def.id) as PointOfInterest
		if poi == null:
			continue

		_apply_discovery_to_world_object(system_id, poi_def.id, poi, poi_def)


func reveal_object(object_id: String) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return

	_remove_marker(oid)

	if spawner == null:
		return

	var world_object := spawner.get_spawned_object(oid) as Node2D
	if world_object == null:
		return

	if world_object is SystemBody:
		(world_object as SystemBody).set_discovery_surface_visible(true)
		(world_object as SystemBody).set_discovery_interactable(true)
	elif world_object is PointOfInterest:
		(world_object as PointOfInterest).set_discovery_surface_visible(true)
		(world_object as PointOfInterest).set_discovery_interactable(true)


func get_signal_marker(object_id: String) -> SignalMarker:
	return _markers_by_object_id.get(object_id.strip_edges()) as SignalMarker


func _apply_discovery_to_world_object(
	system_id: String,
	object_id: String,
	world_object: Node2D,
	definition: Resource,
) -> void:
	var discovery_state := GameSession.get_object_discovery_state(system_id, object_id)
	var signal_config := _resolve_signal_marker_config(definition)

	match discovery_state:
		GameSession.DISCOVERY_HIDDEN:
			_set_world_object_hidden(world_object, true)
			_remove_marker(object_id)
		GameSession.DISCOVERY_SIGNAL:
			_set_world_object_hidden(world_object, true)
			_spawn_or_refresh_marker(world_object, object_id, signal_config)
		_:
			_set_world_object_known(world_object)
			_remove_marker(object_id)


func _resolve_signal_marker_config(definition: Resource) -> Dictionary:
	if definition is SystemBodyDefinition:
		var body_def := definition as SystemBodyDefinition
		return {
			"signal_type_id": body_def.get_resolved_signal_type_id(),
			"signal_type_display_name": body_def.get_resolved_signal_type_display_name(),
			"signal_type_short_label": body_def.get_resolved_signal_type_short_label(),
			"signal_description": body_def.get_resolved_signal_description(),
			"signal_lore": body_def.signal_lore,
			"marker_texture": body_def.get_resolved_signal_marker_texture(),
		}

	if definition is PointOfInterestDefinition:
		var poi_def := definition as PointOfInterestDefinition
		return {
			"signal_type_id": poi_def.get_resolved_signal_type_id(),
			"signal_type_display_name": poi_def.get_resolved_signal_type_display_name(),
			"signal_type_short_label": poi_def.get_resolved_signal_type_short_label(),
			"signal_description": poi_def.get_resolved_signal_description(),
			"signal_lore": poi_def.signal_lore,
			"marker_texture": poi_def.get_resolved_signal_marker_texture(),
		}

	return {
		"signal_type_id": DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_TYPE_ID,
		"signal_type_display_name": DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_DISPLAY_NAME,
		"signal_type_short_label": DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_SHORT_LABEL,
		"signal_description": "",
		"signal_lore": "",
		"marker_texture": null,
	}


func _set_world_object_hidden(world_object: Node2D, hidden: bool) -> void:
	if world_object is SystemBody:
		var body := world_object as SystemBody
		body.set_discovery_surface_visible(not hidden)
		body.set_discovery_interactable(not hidden)
	elif world_object is PointOfInterest:
		var poi := world_object as PointOfInterest
		poi.set_discovery_surface_visible(not hidden)
		poi.set_discovery_interactable(not hidden)


func _set_world_object_known(world_object: Node2D) -> void:
	_set_world_object_hidden(world_object, false)


func _spawn_or_refresh_marker(
	world_object: Node2D,
	object_id: String,
	signal_config: Dictionary,
) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty() or world_object == null:
		return

	_remove_marker(oid)

	var marker := SIGNAL_MARKER_SCENE.instantiate() as SignalMarker
	if marker == null:
		push_warning("SystemDiscoveryController: failed to spawn SignalMarker for '%s'." % oid)
		return

	marker.configure(
		oid,
		str(signal_config.get("signal_type_id", "")),
		str(signal_config.get("signal_type_display_name", "")),
		str(signal_config.get("signal_type_short_label", "")),
		str(signal_config.get("signal_description", "")),
		str(signal_config.get("signal_lore", "")),
		signal_config.get("marker_texture") as Texture2D,
		world_object,
	)
	world_object.add_child(marker)
	_markers_by_object_id[oid] = marker

	if selection != null:
		selection.register_signal_marker(marker)


func _remove_marker(object_id: String) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return

	if not _markers_by_object_id.has(oid):
		return

	var marker_variant: Variant = _markers_by_object_id[oid]
	_markers_by_object_id.erase(oid)

	var marker := marker_variant as SignalMarker
	if marker == null or not is_instance_valid(marker):
		return

	if selection != null and selection.get_selected_node() == marker:
		selection.clear_selection(true)

	marker.queue_free()


func _clear_all_markers() -> void:
	var ids: Array = _markers_by_object_id.keys()
	for id_variant: Variant in ids:
		_remove_marker(str(id_variant))
