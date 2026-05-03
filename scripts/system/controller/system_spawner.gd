## Spawns stars, system bodies and points of interest from a SystemDefinition.
## Does not handle selection, docking, scanning or UI.
class_name SystemSpawner
extends Node


# --------------------------------------------------
# Signals
# --------------------------------------------------

signal body_spawned(body: SystemBody)
signal poi_spawned(poi: PointOfInterest)


# --------------------------------------------------
# Constants
# --------------------------------------------------

const SYSTEM_BODY_SCENE: PackedScene = preload("res://scenes/system/objects/system_body.tscn")
const POINT_OF_INTEREST_SCENE: PackedScene = preload("res://scenes/system/objects/point_of_interest.tscn")


# --------------------------------------------------
# Node References
# --------------------------------------------------

var star_root: Node2D
var system_bodies_root: Node2D
var poi_root: Node2D


# --------------------------------------------------
# State
# --------------------------------------------------

var spawned_lookup: Dictionary = {}
var star_visual: Sprite2D = null


# --------------------------------------------------
# Setup
# --------------------------------------------------

func setup(p_star_root: Node2D, p_system_bodies_root: Node2D, p_poi_root: Node2D) -> void:
	star_root = p_star_root
	system_bodies_root = p_system_bodies_root
	poi_root = p_poi_root


# --------------------------------------------------
# Public API
# --------------------------------------------------

func spawn_from_definition(system_definition: SystemDefinition) -> void:
	if system_definition == null:
		push_error("SystemDefinition fehlt.")
		return

	_clear_previous_spawned_objects()

	spawned_lookup.clear()
	spawned_lookup["star"] = star_root

	_setup_star(system_definition)
	_spawn_bodies(system_definition)
	_spawn_pois(system_definition)
	_resolve_orbits(system_definition)


func get_spawned_object(object_id: String) -> Node:
	return spawned_lookup.get(object_id) as Node


func get_spawned_lookup() -> Dictionary:
	return spawned_lookup


# --------------------------------------------------
# Internal Spawning
# --------------------------------------------------

func _clear_previous_spawned_objects() -> void:
	if star_visual != null and is_instance_valid(star_visual):
		star_visual.queue_free()
		star_visual = null

	if system_bodies_root != null:
		for child in system_bodies_root.get_children():
			child.queue_free()

	if poi_root != null:
		for child in poi_root.get_children():
			child.queue_free()


func _setup_star(system_definition: SystemDefinition) -> void:
	star_visual = Sprite2D.new()
	star_visual.texture = system_definition.star_texture
	star_visual.scale = system_definition.star_scale
	star_visual.modulate = system_definition.star_modulate
	star_root.add_child(star_visual)


func _spawn_bodies(system_definition: SystemDefinition) -> void:
	for body_def in system_definition.bodies:
		var body := SYSTEM_BODY_SCENE.instantiate() as SystemBody
		var presentation := CelestialPresentationCalculator.build_presentation(body_def, system_definition)

		body.set_definition(body_def)
		body.set_presentation(presentation)

		system_bodies_root.add_child(body)
		spawned_lookup[body_def.id] = body

		body_spawned.emit(body)


func _spawn_pois(system_definition: SystemDefinition) -> void:
	for poi_def in system_definition.pois:
		var poi := POINT_OF_INTEREST_SCENE.instantiate() as PointOfInterest

		poi.set_definition(poi_def)

		if poi_def.orbit_center_id == "star":
			poi.orbit_radius = system_definition.star_visual_radius + poi_def.orbit_radius

		poi_root.add_child(poi)
		spawned_lookup[poi_def.id] = poi
		poi_spawned.emit(poi)


func _resolve_orbits(system_definition: SystemDefinition) -> void:
	for body_def in system_definition.bodies:
		var body := spawned_lookup.get(body_def.id) as SystemBody
		var center := spawned_lookup.get(body_def.orbit_center_id) as Node2D

		if body != null and center != null:
			body.set_orbit_center(center)
			body.refresh_orbit_position()

	for poi_def in system_definition.pois:
		var poi := spawned_lookup.get(poi_def.id) as PointOfInterest
		var center := spawned_lookup.get(poi_def.orbit_center_id) as Node2D

		if poi != null and center != null:
			poi.set_orbit_center(center)
			poi.refresh_orbit_position()
