class_name SystemLightingDefinition
extends Resource

const DEFAULT_RESOURCE_PATH: String = "res://data/visuals/default_system_lighting.tres"

static var _cached_default: SystemLightingDefinition = null

@export_group("Ambient")
@export var enable_true_2d_lighting_mode: bool = true
@export var ambient_color: Color = Color(0.059911326, 0.070476435, 0.112851225, 1.0)

@export_group("Star Point Light")
@export var enable_real_star_light: bool = true
@export var star_light_color: Color = Color(0.91654724, 0.9510632, 0.9999996, 1.0)
@export_range(0.0, 5.0, 0.01) var star_light_energy: float = 1.15
@export_range(64.0, 20000.0, 1.0) var star_light_radius_px: float = 12000.0
@export_range(128, 4096, 1) var star_light_texture_size: int = 1024

@export_group("Star Glow")
@export var enable_star_glow: bool = true
@export var star_glow_color: Color = Color(1.0, 0.72, 0.32, 0.35)
@export_range(1.0, 12.0, 0.1) var star_glow_scale: float = 4.0
@export_range(0.0, 1.0, 0.01) var star_glow_alpha: float = 0.32

@export_group("Planet Lighting")
@export var enable_planet_lighting: bool = true
@export var default_planet_lighting: PlanetLightingVisualDefinition

@export_group("Vignette")
@export var enable_vignette: bool = false
@export var vignette_color: Color = Color(0.05882353, 0.07058824, 0.11372549, 1.0)
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.8
@export_range(0.0, 1.5, 0.01) var vignette_radius: float = 0.19
@export_range(0.01, 1.0, 0.01) var vignette_softness: float = 0.9


static func get_default() -> SystemLightingDefinition:
	if _cached_default != null:
		return _cached_default

	var loaded: Resource = load(DEFAULT_RESOURCE_PATH)
	if loaded is SystemLightingDefinition:
		_cached_default = loaded as SystemLightingDefinition
		return _cached_default

	push_warning(
		"SystemLightingDefinition.get_default: failed to load '%s', using script defaults."
		% DEFAULT_RESOURCE_PATH
	)
	_cached_default = SystemLightingDefinition.new()
	return _cached_default


func apply_to(controller: SystemLightController) -> void:
	if controller == null:
		return

	controller.enable_true_2d_lighting_mode = enable_true_2d_lighting_mode
	controller.true_lighting_canvas_modulate_color = ambient_color

	controller.enable_real_star_light = enable_real_star_light
	controller.real_star_light_color = star_light_color
	controller.real_star_light_energy = star_light_energy
	controller.real_star_light_radius_px = star_light_radius_px
	controller.real_star_light_texture_size = star_light_texture_size

	controller.enable_star_glow = enable_star_glow
	controller.star_glow_color = star_glow_color
	controller.star_glow_scale = star_glow_scale
	controller.star_glow_alpha = star_glow_alpha

	controller.enable_planet_lighting = enable_planet_lighting
	_apply_planet_defaults_to_controller(controller)

	controller.enable_vignette = enable_vignette
	controller.vignette_color = vignette_color
	controller.vignette_strength = vignette_strength
	controller.vignette_radius = vignette_radius
	controller.vignette_softness = vignette_softness


func _apply_planet_defaults_to_controller(controller: SystemLightController) -> void:
	if default_planet_lighting == null:
		return

	controller.default_light_tint = default_planet_lighting.light_tint
	controller.default_shadow_tint = default_planet_lighting.shadow_tint
	controller.default_shadow_strength = default_planet_lighting.shadow_strength
	controller.default_light_boost = default_planet_lighting.light_boost
	controller.default_terminator_softness = default_planet_lighting.terminator_softness
	controller.default_light_height = default_planet_lighting.light_height
	controller.default_rim_strength = default_planet_lighting.rim_strength
	controller.default_rim_power = default_planet_lighting.rim_power
