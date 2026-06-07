class_name SystemDefinition
extends Resource


@export_group("Core")
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Audio")
## Music track id for `AudioManager.play_music` when this system is loaded (see `MUSIC_TRACKS`).
@export var music_track_id: StringName = &"music_system_default"

@export_group("Visuals")
## Optional per-system lighting override. When null, `default_system_lighting.tres` is used.
@export var lighting_definition: SystemLightingDefinition

@export_group("Star")
@export var star_texture: Texture2D
@export var star_scale: Vector2 = Vector2.ONE
@export var star_modulate: Color = Color.WHITE
@export var star_visual_radius: float = 80.0

@export_group("Entry")
@export var entry_spawn_radius: float = 220.0
@export var entry_spawn_angle_degrees: float = 0.0
## Preferred body id for camera focus and starting automation orbit (must match a `bodies[].id`).
@export var start_body_id: String = ""
## v0.1: fixed colony establish target when colonizing this system (player picks system only).
@export var colonization_start_body_id: StringName = &""


@export_group("Presentation")
@export var earth_target_body_diameter_px: float = 46.0
@export var earth_target_orbit_offset_px: float = 185.0
@export var earth_orbit_angular_speed: float = 0.22

@export var size_curve_exponent: float = 0.38
@export var orbit_curve_exponent: float = 0.42
@export var speed_curve_exponent: float = 0.50

@export var minimum_body_diameter_px: float = 10.0
@export var selection_ring_padding_px: float = 14.0
@export var min_angular_speed: float = 0.03
@export var max_angular_speed: float = 1.50

@export_group("Content")
@export var bodies: Array[SystemBodyDefinition] = []
@export var pois: Array[PointOfInterestDefinition] = []


func get_resolved_lighting_definition() -> SystemLightingDefinition:
	if lighting_definition != null:
		return lighting_definition
	return SystemLightingDefinition.get_default()


func get_resolved_colonization_start_body_id() -> String:
	var explicit := String(colonization_start_body_id).strip_edges()
	if not explicit.is_empty() and _body_allows_colonization(explicit):
		return explicit

	var start_body := start_body_id.strip_edges()
	if not start_body.is_empty() and _body_allows_colonization(start_body):
		return start_body

	for body_def: SystemBodyDefinition in bodies:
		if body_def == null:
			continue
		var body_id := str(body_def.id).strip_edges()
		if body_id.is_empty():
			continue
		if _body_allows_colonization(body_id):
			return body_id

	return ""


func _body_allows_colonization(body_id: String) -> bool:
	var needle := body_id.strip_edges()
	if needle.is_empty():
		return false
	for body_def: SystemBodyDefinition in bodies:
		if body_def == null:
			continue
		if str(body_def.id).strip_edges() != needle:
			continue
		return body_def.can_build_base
	return false
