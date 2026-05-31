## Collects orbit data and forwards it to the orbit guides layer.
## Does not spawn, move or select objects.
class_name SystemOrbitGuidesController
extends Node


# --------------------------------------------------
# Node References
# --------------------------------------------------

var orbit_guides_layer: Node2D
var system_bodies_root: Node2D
var poi_root: Node2D


# --------------------------------------------------
# Setup
# --------------------------------------------------

func setup(p_orbit_guides_layer: Node2D, p_system_bodies_root: Node2D, p_poi_root: Node2D) -> void:
	orbit_guides_layer = p_orbit_guides_layer
	system_bodies_root = p_system_bodies_root
	poi_root = p_poi_root


# --------------------------------------------------
# Public API
# --------------------------------------------------

func update_orbit_guides() -> void:
	if orbit_guides_layer == null:
		return

	var orbit_entries: Array = []

	for child in system_bodies_root.get_children():
		var body := child as SystemBody

		if body == null or body.orbit_center == null:
			continue

		if not _should_draw_orbit_guide_for_object(body.body_id):
			continue

		orbit_entries.append({
			"center": body.orbit_center.global_position,
			"radius": body.orbit_radius,
		})

	for child in poi_root.get_children():
		var poi := child as PointOfInterest

		if poi == null or poi.orbit_center == null:
			continue

		if not _should_draw_orbit_guide_for_object(poi.poi_id):
			continue

		orbit_entries.append({
			"center": poi.orbit_center.global_position,
			"radius": poi.orbit_radius,
		})

	if orbit_guides_layer.has_method("set_orbits"):
		orbit_guides_layer.set_orbits(orbit_entries)


func _should_draw_orbit_guide_for_object(object_id: String) -> bool:
	var system_id := GameSession.current_system_id.strip_edges()
	var oid := object_id.strip_edges()

	if system_id.is_empty() or oid.is_empty():
		return true

	return GameSession.is_object_known(system_id, oid)
