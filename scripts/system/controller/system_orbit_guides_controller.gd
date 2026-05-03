class_name SystemOrbitGuidesController
extends Node

var orbit_guides_layer: Node2D
var system_bodies_root: Node2D
var poi_root: Node2D


func setup(
	p_orbit_guides_layer: Node2D,
	p_system_bodies_root: Node2D,
	p_poi_root: Node2D
) -> void:
	orbit_guides_layer = p_orbit_guides_layer
	system_bodies_root = p_system_bodies_root
	poi_root = p_poi_root


func update_orbit_guides() -> void:
	if orbit_guides_layer == null:
		return

	var orbit_entries: Array = []

	for child in system_bodies_root.get_children():
		var body := child as SystemBody

		if body == null or body.orbit_center == null:
			continue

		orbit_entries.append({
			"center": body.orbit_center.global_position,
			"radius": body.orbit_radius,
		})

	for child in poi_root.get_children():
		var poi := child as PointOfInterest

		if poi == null or poi.orbit_center == null:
			continue

		orbit_entries.append({
			"center": poi.orbit_center.global_position,
			"radius": poi.orbit_radius,
		})

	if orbit_guides_layer.has_method("set_orbits"):
		orbit_guides_layer.set_orbits(orbit_entries)
