class_name PlanetLightingVisualDefinition
extends Resource

@export var enabled: bool = true
@export var light_tint: Color = Color(1.0, 0.92, 0.72, 1.0)
@export var shadow_tint: Color = Color(0.08, 0.11, 0.20, 1.0)
@export_range(0.0, 1.0) var shadow_strength: float = 0.55
@export_range(0.0, 1.0) var light_boost: float = 0.12
@export_range(0.01, 0.8) var terminator_softness: float = 0.18
@export_range(0.05, 1.0) var light_height: float = 0.35
@export_range(0.0, 1.0) var rim_strength: float = 0.08
@export_range(1.0, 12.0) var rim_power: float = 4.0
