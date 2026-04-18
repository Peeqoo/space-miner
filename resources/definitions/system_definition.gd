class_name SystemDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""

@export var star_texture: Texture2D
@export var star_scale: Vector2 = Vector2.ONE
@export var star_modulate: Color = Color.WHITE
@export var star_visual_radius: float = 80.0

@export var entry_spawn_radius: float = 220.0
@export var entry_spawn_angle_degrees: float = 0.0

@export var bodies: Array[SystemBodyDefinition] = []
@export var pois: Array[PointOfInterestDefinition] = []
