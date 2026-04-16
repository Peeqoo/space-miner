class_name SystemBodyDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var body_type: String

@export var orbit_center_id: String
@export var orbit_radius: float
@export var orbit_speed: float
@export var orbit_start_angle_degrees: float

@export var body_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var texture: Texture2D
