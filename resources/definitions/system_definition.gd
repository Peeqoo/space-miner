class_name SystemDefinition
extends Resource


@export_group("Core")
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

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
