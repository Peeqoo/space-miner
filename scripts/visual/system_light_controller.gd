## Optional real 2D star lighting and planet sprite lighting for SpaceMiner.
## Cleaned version: one real star PointLight2D + CanvasModulate + planet direction shader.
class_name SystemLightController
extends Node

const _PLANET_SHADER: Shader = preload("res://shaders/visual/planet_sprite_lit_2d.gdshader")
const _VIGNETTE_SHADER: Shader = preload("res://shaders/visual/screen_vignette_2d.gdshader")
const VIGNETTE_CANVAS_LAYER: int = 1
const REAL_STAR_LIGHT_NODE_NAME: StringName = &"StarRealPointLight2D"
const STAR_GLOW_NODE_NAME: StringName = &"StarGlowVisual"
const WORLD_AMBIENT_CANVAS_MODULATE_NAME: StringName = &"WorldAmbientCanvasModulate"
const LEGACY_STAR_POINT_LIGHT_NAME: StringName = &"StarPointLight2D"
const LEGACY_STAR_WIDE_POINT_LIGHT_NAME: StringName = &"StarWidePointLight2D"
const LEGACY_STAR_WIDE_HALO_NAME: StringName = &"StarWideHaloVisual"

@export_group("References")
@export var star_node_path: NodePath
@export var planet_group_name: StringName = &"system_planets"
@export var background_root_path: NodePath = NodePath("BackgroundRoot")
@export var world_root_path: NodePath = NodePath("WorldRoot")

@export_group("True 2D Lighting")
@export var enable_true_2d_lighting_mode: bool = true
@export var true_lighting_canvas_modulate_color: Color = Color(0.16, 0.18, 0.26, 1.0)
@export var true_lighting_canvas_modulate_name: StringName = WORLD_AMBIENT_CANVAS_MODULATE_NAME

@export_group("Real Star Light")
@export var enable_real_star_light: bool = true
@export var real_star_light_color: Color = Color(0.86, 0.92, 1.0, 1.0)
@export_range(0.0, 5.0, 0.01) var real_star_light_energy: float = 1.15
@export_range(64.0, 20000.0, 1.0) var real_star_light_radius_px: float = 6000.0
@export_range(128, 4096, 1) var real_star_light_texture_size: int = 1024
@export var real_star_light_only_in_true_mode: bool = true
@export var enable_real_star_light_debug: bool = false

@export_group("Planet Lighting")
@export var enable_planet_lighting: bool = true
@export var update_every_frame: bool = true
@export var default_light_tint: Color = Color(1.0, 0.92, 0.72, 1.0)
@export var default_shadow_tint: Color = Color(0.08, 0.11, 0.20, 1.0)
@export_range(0.0, 1.0, 0.01) var default_shadow_strength: float = 0.55
@export_range(0.0, 1.0, 0.01) var default_light_boost: float = 0.12
@export_range(0.01, 0.8, 0.01) var default_terminator_softness: float = 0.18
@export_range(0.05, 1.0, 0.01) var default_light_height: float = 0.35
@export_range(0.0, 1.0, 0.01) var default_rim_strength: float = 0.08
@export_range(1.0, 12.0, 0.1) var default_rim_power: float = 4.0

@export_group("Star Glow Visual")
@export var enable_star_glow: bool = true
@export var star_glow_color: Color = Color(1.0, 0.72, 0.32, 0.35)
@export_range(1.0, 12.0, 0.1) var star_glow_scale: float = 4.0
@export_range(0.0, 1.0, 0.01) var star_glow_alpha: float = 0.32

@export_group("Fallback Scene Dimming")
@export var enable_scene_dimming: bool = true
@export var scene_dim_color: Color = Color(0.62, 0.68, 0.85, 1.0)
@export_range(0.0, 0.6, 0.01) var scene_dim_strength: float = 0.18

@export_group("Screen Vignette")
@export var enable_vignette: bool = true
@export var vignette_color: Color = Color(0.02, 0.03, 0.08, 1.0)
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.16
@export_range(0.0, 1.5, 0.01) var vignette_radius: float = 0.62
@export_range(0.01, 1.0, 0.01) var vignette_softness: float = 0.38
@export var true_lighting_keep_vignette: bool = true
@export var vignette_canvas_layer_name: StringName = &"AtmosphereOverlayCanvasLayer"
@export var vignette_rect_name: StringName = &"VignetteOverlay"

@export_group("Cleanup")
@export var remove_legacy_star_light_nodes: bool = true

static var _shared_real_star_light_texture: GradientTexture2D = null
static var _shared_real_star_light_texture_cached_size: int = 0

var _spawner: SystemSpawner = null
var _star_sprite: Sprite2D = null
var _star_glow_sprite: Sprite2D = null
var _star_real_point_light: PointLight2D = null
var _world_ambient_canvas_modulate: CanvasModulate = null
var _vignette_canvas_layer: CanvasLayer = null
var _vignette_rect: ColorRect = null

var _target_sprites: Array[Sprite2D] = []
var _target_materials: Array[ShaderMaterial] = []
var _original_materials: Array[Material] = []

var _scene_dim_nodes: Array[Node2D] = []
var _scene_dim_original_modulates: Array[Color] = []
var _scene_dimming_active: bool = false

var _star_path_warned: bool = false
var _ui_layer_warned: bool = false
var _real_star_light_debug_printed: bool = false


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not enable_planet_lighting or not update_every_frame:
		return
	_update_light_directions()


func setup_from_spawner(spawner: SystemSpawner) -> void:
	_spawner = spawner
	_resolve_star_sprite()

	if remove_legacy_star_light_nodes:
		_cleanup_legacy_star_light_nodes()

	refresh_world_lighting()
	refresh_star_glow()
	refresh_real_star_light()
	refresh_planet_lighting_targets()
	refresh_vignette()


func refresh_all_visual_lighting() -> void:
	_resolve_star_sprite()
	refresh_world_lighting()
	refresh_star_glow()
	refresh_real_star_light()
	refresh_planet_lighting_targets()
	refresh_vignette()


func refresh_world_lighting() -> void:
	_restore_scene_dimming()
	_teardown_world_ambient_canvas_modulate()

	if enable_true_2d_lighting_mode:
		if _can_use_canvas_modulate_safely():
			_setup_world_ambient_canvas_modulate()
		else:
			_apply_fallback_scene_dimming(true_lighting_canvas_modulate_color)
		return

	if enable_scene_dimming:
		_apply_fallback_scene_dimming(_compute_scene_dim_modulate())


func refresh_star_glow() -> void:
	_remove_star_glow()

	if not enable_star_glow:
		return

	_resolve_star_sprite()
	if _star_sprite == null or _star_sprite.texture == null:
		return

	_star_glow_sprite = Sprite2D.new()
	_star_glow_sprite.name = String(STAR_GLOW_NODE_NAME)
	_star_glow_sprite.texture = _star_sprite.texture
	_star_glow_sprite.scale = _star_sprite.scale * star_glow_scale
	_star_glow_sprite.modulate = Color(star_glow_color.r, star_glow_color.g, star_glow_color.b, star_glow_alpha)
	_star_glow_sprite.z_index = _star_sprite.z_index - 1
	_star_glow_sprite.show_behind_parent = true

	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_star_glow_sprite.material = glow_material

	_star_sprite.add_child(_star_glow_sprite)


func refresh_real_star_light() -> void:
	_remove_star_real_point_light()

	if not _should_use_real_star_light():
		return

	_resolve_star_sprite()
	if _star_sprite == null:
		_print_real_star_light_debug(false, "star_visual is null")
		return

	var texture_size_px := clampi(real_star_light_texture_size, 128, 4096)
	var light_texture := _get_real_star_light_texture(texture_size_px)
	var texture_scale := _calculate_real_star_light_texture_scale(texture_size_px)

	if texture_scale <= 0.0:
		push_warning("SystemLightController: StarRealPointLight2D skipped because texture_scale <= 0.")
		_print_real_star_light_debug(false, "texture_scale <= 0")
		return

	_star_real_point_light = PointLight2D.new()
	_star_real_point_light.name = String(REAL_STAR_LIGHT_NODE_NAME)
	_star_real_point_light.enabled = true
	_star_real_point_light.color = real_star_light_color
	_star_real_point_light.energy = real_star_light_energy
	_star_real_point_light.texture = light_texture
	_star_real_point_light.texture_scale = texture_scale
	_star_real_point_light.shadow_enabled = false
	_star_real_point_light.position = Vector2.ZERO
	_star_real_point_light.range_item_cull_mask = 0xFFFFFFFF

	_star_sprite.add_child(_star_real_point_light)
	_star_sprite.move_child(_star_real_point_light, 0)
	_print_real_star_light_debug(true, "")


func refresh_planet_lighting_targets() -> void:
	_restore_original_materials()
	_target_sprites.clear()
	_target_materials.clear()
	_original_materials.clear()
	set_process(false)

	if not enable_planet_lighting:
		return

	_resolve_star_sprite()

	var group_nodes: Array[Node] = get_tree().get_nodes_in_group(planet_group_name)
	for node: Node in group_nodes:
		if not (node is SystemBody):
			continue

		var body := node as SystemBody
		var sprite := body.body_visual
		if sprite == null or not is_instance_valid(sprite):
			continue
		if sprite.texture == null:
			continue

		var lighting_def: PlanetLightingVisualDefinition = null
		if body.definition != null:
			lighting_def = body.definition.planet_lighting
		if lighting_def != null and not lighting_def.enabled:
			continue

		var material := _create_planet_material(lighting_def)
		_original_materials.append(sprite.material)
		sprite.material = material
		_target_sprites.append(sprite)
		_target_materials.append(material)

	_update_light_directions()

	if update_every_frame and not _target_sprites.is_empty():
		set_process(true)


func refresh_vignette() -> void:
	var vignette_active := enable_vignette
	if enable_true_2d_lighting_mode and not true_lighting_keep_vignette:
		vignette_active = false

	if not vignette_active:
		_hide_vignette()
		return

	var scene_root := get_parent()
	if scene_root == null:
		return

	_warn_if_ui_layer_below_vignette(scene_root)
	_vignette_canvas_layer = _get_or_create_vignette_canvas_layer(scene_root)
	_vignette_rect = _get_or_create_vignette_rect(_vignette_canvas_layer)

	var material := ShaderMaterial.new()
	material.shader = _VIGNETTE_SHADER
	material.set_shader_parameter("vignette_color", vignette_color)
	material.set_shader_parameter("strength", vignette_strength)
	material.set_shader_parameter("radius", vignette_radius)
	material.set_shader_parameter("softness", vignette_softness)

	_vignette_rect.material = material
	_vignette_rect.color = Color.WHITE
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.visible = true
	_vignette_canvas_layer.visible = true


func _resolve_star_sprite() -> void:
	if _spawner != null and _spawner.star_visual != null and is_instance_valid(_spawner.star_visual):
		_star_sprite = _spawner.star_visual
		return

	if star_node_path.is_empty():
		if not _star_path_warned:
			push_warning("SystemLightController: star_node_path is empty and spawner has no star_visual.")
			_star_path_warned = true
		_star_sprite = null
		return

	var star_node := get_node_or_null(star_node_path)
	if star_node == null:
		if not _star_path_warned:
			push_warning("SystemLightController: star node not found at %s." % String(star_node_path))
			_star_path_warned = true
		_star_sprite = null
		return

	if star_node is Sprite2D:
		_star_sprite = star_node as Sprite2D
		return

	var star_children: Array[Node] = star_node.get_children()
	for child: Node in star_children:
		if child is Sprite2D:
			_star_sprite = child as Sprite2D
			return

	if not _star_path_warned:
		push_warning("SystemLightController: no Sprite2D found for star node %s." % String(star_node_path))
		_star_path_warned = true
	_star_sprite = null


func _cleanup_legacy_star_light_nodes() -> void:
	if _star_sprite == null or not is_instance_valid(_star_sprite):
		return

	var legacy_names: Array[StringName] = [
		LEGACY_STAR_POINT_LIGHT_NAME,
		LEGACY_STAR_WIDE_POINT_LIGHT_NAME,
		LEGACY_STAR_WIDE_HALO_NAME,
	]

	for legacy_name: StringName in legacy_names:
		var legacy_node := _star_sprite.get_node_or_null(NodePath(String(legacy_name)))
		if legacy_node != null:
			legacy_node.queue_free()

	var star_parent := _star_sprite.get_parent()
	if star_parent == null:
		return

	for legacy_name: StringName in legacy_names:
		var legacy_node := star_parent.get_node_or_null(NodePath(String(legacy_name)))
		if legacy_node != null:
			legacy_node.queue_free()


func _should_use_real_star_light() -> bool:
	if not enable_real_star_light:
		return false
	if real_star_light_only_in_true_mode:
		return enable_true_2d_lighting_mode
	return true


func _calculate_real_star_light_texture_scale(texture_size_px: int) -> float:
	if texture_size_px <= 0:
		return 0.0
	return (real_star_light_radius_px * 2.0) / float(texture_size_px)


func _get_real_star_light_texture(texture_size: int) -> GradientTexture2D:
	var size_px := clampi(texture_size, 128, 4096)
	if _shared_real_star_light_texture != null and _shared_real_star_light_texture_cached_size == size_px:
		return _shared_real_star_light_texture

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.36, 0.62, 0.84, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.95, 0.82, 0.70),
		Color(1.0, 0.82, 0.52, 0.34),
		Color(1.0, 0.68, 0.36, 0.12),
		Color(1.0, 0.55, 0.24, 0.03),
		Color(1.0, 0.45, 0.18, 0.0),
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size_px
	texture.height = size_px
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	_shared_real_star_light_texture = texture
	_shared_real_star_light_texture_cached_size = size_px
	return _shared_real_star_light_texture


func _print_real_star_light_debug(success: bool, reason: String) -> void:
	if not enable_real_star_light_debug or _real_star_light_debug_printed:
		return

	_real_star_light_debug_printed = true
	var texture_size_px := clampi(real_star_light_texture_size, 128, 4096)
	var texture_scale := _calculate_real_star_light_texture_scale(texture_size_px)
	var star_found := _star_sprite != null and is_instance_valid(_star_sprite)
	var light_created := _star_real_point_light != null and is_instance_valid(_star_real_point_light)
	var global_pos := Vector2.ZERO
	if _star_real_point_light != null and is_instance_valid(_star_real_point_light):
		global_pos = _star_real_point_light.global_position
	elif _star_sprite != null and is_instance_valid(_star_sprite):
		global_pos = _star_sprite.global_position

	print(
		(
			"SystemLightController RealStarLight debug: success=%s reason='%s' "
			+ "star_found=%s light_created=%s radius_px=%s texture_size=%s "
			+ "texture_scale=%s enabled=%s energy=%s global_position=%s true_mode=%s"
		)
		% [
			success,
			reason,
			star_found,
			light_created,
			real_star_light_radius_px,
			texture_size_px,
			texture_scale,
			enable_real_star_light,
			real_star_light_energy,
			global_pos,
			enable_true_2d_lighting_mode,
		]
	)


func _can_use_canvas_modulate_safely() -> bool:
	var scene_root := get_parent()
	if scene_root == null:
		return false

	var ui_node := scene_root.get_node_or_null(NodePath("UI"))
	if ui_node is not CanvasLayer:
		return false

	var ui_layer := ui_node as CanvasLayer
	return ui_layer.layer > VIGNETTE_CANVAS_LAYER


func _setup_world_ambient_canvas_modulate() -> void:
	var scene_root := get_parent()
	if scene_root == null:
		return

	var modulate_name := String(true_lighting_canvas_modulate_name)
	var existing := scene_root.get_node_or_null(NodePath(modulate_name))
	if existing is CanvasModulate:
		_world_ambient_canvas_modulate = existing as CanvasModulate
	else:
		_world_ambient_canvas_modulate = CanvasModulate.new()
		_world_ambient_canvas_modulate.name = modulate_name
		scene_root.add_child(_world_ambient_canvas_modulate)
		scene_root.move_child(_world_ambient_canvas_modulate, 0)

	_world_ambient_canvas_modulate.color = true_lighting_canvas_modulate_color
	_world_ambient_canvas_modulate.visible = true


func _teardown_world_ambient_canvas_modulate() -> void:
	if _world_ambient_canvas_modulate != null and is_instance_valid(_world_ambient_canvas_modulate):
		_world_ambient_canvas_modulate.visible = false
	_world_ambient_canvas_modulate = null

	var scene_root := get_parent()
	if scene_root == null:
		return

	var modulate_name := String(true_lighting_canvas_modulate_name)
	var existing := scene_root.get_node_or_null(NodePath(modulate_name))
	if existing is CanvasModulate:
		(existing as CanvasModulate).visible = false


func _apply_fallback_scene_dimming(dim_modulate: Color) -> void:
	_restore_scene_dimming()

	var background_root := get_node_or_null(background_root_path) as Node2D
	var world_root := get_node_or_null(world_root_path) as Node2D
	_apply_dim_to_node(background_root, dim_modulate)
	_apply_dim_to_node(world_root, dim_modulate)
	_scene_dimming_active = not _scene_dim_nodes.is_empty()


func _apply_dim_to_node(node: Node2D, dim_modulate: Color) -> void:
	if node == null:
		return
	_scene_dim_nodes.append(node)
	_scene_dim_original_modulates.append(node.modulate)
	node.modulate = node.modulate * dim_modulate


func _restore_scene_dimming() -> void:
	if not _scene_dimming_active:
		_scene_dim_nodes.clear()
		_scene_dim_original_modulates.clear()
		return

	for i in range(_scene_dim_nodes.size()):
		var node := _scene_dim_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if i < _scene_dim_original_modulates.size():
			node.modulate = _scene_dim_original_modulates[i]

	_scene_dim_nodes.clear()
	_scene_dim_original_modulates.clear()
	_scene_dimming_active = false


func _compute_scene_dim_modulate() -> Color:
	var strength := clampf(scene_dim_strength, 0.0, 0.6)
	return Color.WHITE.lerp(scene_dim_color, strength)


func _remove_star_glow() -> void:
	if _star_glow_sprite != null and is_instance_valid(_star_glow_sprite):
		_star_glow_sprite.queue_free()
	_star_glow_sprite = null

	if _star_sprite != null and is_instance_valid(_star_sprite):
		var existing := _star_sprite.get_node_or_null(NodePath(String(STAR_GLOW_NODE_NAME)))
		if existing is Sprite2D:
			(existing as Sprite2D).queue_free()


func _remove_star_real_point_light() -> void:
	if _star_real_point_light != null and is_instance_valid(_star_real_point_light):
		_star_real_point_light.queue_free()
	_star_real_point_light = null

	if _star_sprite != null and is_instance_valid(_star_sprite):
		var existing := _star_sprite.get_node_or_null(NodePath(String(REAL_STAR_LIGHT_NODE_NAME)))
		if existing is PointLight2D:
			(existing as PointLight2D).queue_free()


func _create_planet_material(lighting_def: PlanetLightingVisualDefinition) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _PLANET_SHADER
	_apply_lighting_to_material(material, lighting_def)
	return material


func _apply_lighting_to_material(
	material: ShaderMaterial,
	lighting_def: PlanetLightingVisualDefinition,
) -> void:
	if lighting_def != null:
		material.set_shader_parameter("light_tint", lighting_def.light_tint)
		material.set_shader_parameter("shadow_tint", lighting_def.shadow_tint)
		material.set_shader_parameter("shadow_strength", lighting_def.shadow_strength)
		material.set_shader_parameter("light_boost", lighting_def.light_boost)
		material.set_shader_parameter("terminator_softness", lighting_def.terminator_softness)
		material.set_shader_parameter("light_height", lighting_def.light_height)
		material.set_shader_parameter("rim_strength", lighting_def.rim_strength)
		material.set_shader_parameter("rim_power", lighting_def.rim_power)
		return

	material.set_shader_parameter("light_tint", default_light_tint)
	material.set_shader_parameter("shadow_tint", default_shadow_tint)
	material.set_shader_parameter("shadow_strength", default_shadow_strength)
	material.set_shader_parameter("light_boost", default_light_boost)
	material.set_shader_parameter("terminator_softness", default_terminator_softness)
	material.set_shader_parameter("light_height", default_light_height)
	material.set_shader_parameter("rim_strength", default_rim_strength)
	material.set_shader_parameter("rim_power", default_rim_power)


func _update_light_directions() -> void:
	if _target_sprites.is_empty():
		return

	_resolve_star_sprite()
	var star_position := Vector2.ZERO
	if _star_sprite != null and is_instance_valid(_star_sprite):
		star_position = _star_sprite.global_position

	for i in range(_target_sprites.size()):
		var sprite := _target_sprites[i]
		if sprite == null or not is_instance_valid(sprite):
			continue

		var material := _target_materials[i]
		if material == null:
			continue

		var to_star := star_position - sprite.global_position
		if to_star.length_squared() <= 0.0001:
			to_star = Vector2(-1.0, -0.25)
		else:
			to_star = to_star.normalized()

		material.set_shader_parameter("light_direction", to_star)


func _restore_original_materials() -> void:
	for i in range(_target_sprites.size()):
		var sprite := _target_sprites[i]
		if sprite == null or not is_instance_valid(sprite):
			continue
		if i < _original_materials.size():
			sprite.material = _original_materials[i]
		else:
			sprite.material = null


func _hide_vignette() -> void:
	if _vignette_rect != null and is_instance_valid(_vignette_rect):
		_vignette_rect.visible = false
		_vignette_rect.material = null
	if _vignette_canvas_layer != null and is_instance_valid(_vignette_canvas_layer):
		_vignette_canvas_layer.visible = false


func _warn_if_ui_layer_below_vignette(scene_root: Node) -> void:
	if _ui_layer_warned:
		return

	var ui_node := scene_root.get_node_or_null(NodePath("UI"))
	if ui_node is not CanvasLayer:
		return

	var ui_layer := ui_node as CanvasLayer
	if ui_layer.layer <= VIGNETTE_CANVAS_LAYER:
		push_warning(
			(
				"SystemLightController: UI CanvasLayer layer %d is not above vignette layer %d. "
				+ "Set UI.layer to 2 or higher in system_scene.tscn."
			)
			% [ui_layer.layer, VIGNETTE_CANVAS_LAYER]
		)
		_ui_layer_warned = true


func _get_or_create_vignette_canvas_layer(scene_root: Node) -> CanvasLayer:
	var layer_name := String(vignette_canvas_layer_name)
	var existing := scene_root.get_node_or_null(NodePath(layer_name))
	if existing is CanvasLayer:
		var existing_layer := existing as CanvasLayer
		existing_layer.layer = VIGNETTE_CANVAS_LAYER
		return existing_layer

	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = layer_name
	canvas_layer.layer = VIGNETTE_CANVAS_LAYER
	_scene_layer_add_before_ui(scene_root, canvas_layer)
	return canvas_layer


func _scene_layer_add_before_ui(scene_root: Node, new_node: Node) -> void:
	var ui_node := scene_root.get_node_or_null(NodePath("UI"))
	if ui_node != null:
		var ui_index := ui_node.get_index()
		scene_root.add_child(new_node)
		scene_root.move_child(new_node, ui_index)
		return
	scene_root.add_child(new_node)


func _get_or_create_vignette_rect(canvas_layer: CanvasLayer) -> ColorRect:
	var rect_name := String(vignette_rect_name)
	var existing := canvas_layer.get_node_or_null(NodePath(rect_name))
	if existing is ColorRect:
		return existing as ColorRect

	var rect := ColorRect.new()
	rect.name = rect_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE)
	rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rect.grow_vertical = Control.GROW_DIRECTION_BOTH
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	canvas_layer.add_child(rect)
	return rect
