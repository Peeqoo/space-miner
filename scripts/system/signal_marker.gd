## Clickable discovery placeholder for objects not yet revealed (SIGNAL state).
class_name SignalMarker
extends Node2D

signal selected(marker: SignalMarker)
signal refocus_camera_requested(node: Node2D)

var object_id: String = ""
var signal_type_id: String = ""
var signal_type_display_name: String = ""
var signal_type_short_label: String = ""
var signal_description: String = ""
## Per-object pre-reveal lore from body/POI definition (`signal_lore`).
var signal_lore: String = ""
var marker_texture: Texture2D
var target_object: Node2D = null

@onready var marker_visual: Sprite2D = $MarkerPivot/MarkerVisual
@onready var type_label: Label = $MarkerPivot/TypeLabel
@onready var selection_ring: Node2D = $MarkerPivot/SelectionRing
@onready var click_area: Area2D = $MarkerPivot/ClickArea
@onready var click_collision: CollisionShape2D = $MarkerPivot/ClickArea/CollisionShape2D

var selectable := SelectableObjectComponent.new()

var _is_selected: bool = false
var _selection_ring_radius: float = 22.0


func _ready() -> void:
	_apply_marker_text()
	_apply_marker_texture()
	set_selected(false)

	selectable.set_selection_ring_radius(selection_ring, _selection_ring_radius)
	selectable.setup_click_area(click_area, click_collision, _on_click_area_input_event)
	selectable.update_click_shape(click_collision)

	if marker_visual != null and marker_visual.texture == null:
		marker_visual.texture = _build_fallback_texture()


func configure(
	p_object_id: String,
	p_signal_type_id: String,
	p_signal_type_display_name: String,
	p_signal_type_short_label: String,
	p_signal_description: String,
	p_signal_lore: String,
	p_marker_texture: Texture2D,
	p_target_object: Node2D,
) -> void:
	object_id = p_object_id.strip_edges()
	signal_type_id = p_signal_type_id.strip_edges()
	signal_type_display_name = p_signal_type_display_name.strip_edges()
	signal_type_short_label = p_signal_type_short_label.strip_edges()
	signal_description = p_signal_description.strip_edges()
	signal_lore = p_signal_lore.strip_edges()
	marker_texture = p_marker_texture
	target_object = p_target_object

	if is_inside_tree():
		_apply_marker_text()
		_apply_marker_texture()
		if marker_visual != null and marker_visual.texture == null:
			marker_visual.texture = _build_fallback_texture()


func set_selected(value: bool) -> void:
	_is_selected = value
	selectable.set_selected(selection_ring, value)


func get_info() -> Dictionary:
	return {
		"id": object_id,
		"display_name": _resolved_panel_display_name(),
		"signal_type": _resolved_panel_object_type_label(),
		"signal_type_id": signal_type_id,
		"is_signal_marker": true,
	}


func build_signal_info() -> Dictionary:
	var panel_name := _resolved_panel_display_name()
	var panel_object_type := _resolved_panel_object_type_label()

	return {
		"id": object_id,
		"object_id": object_id,
		"display_name": panel_name,
		"body_type": panel_object_type,
		"scan_state": GameSession.SCAN_UNKNOWN,
		"is_signal_marker": true,
		"is_discovery_signal": true,
		"signal_type": panel_object_type,
		"signal_type_id": signal_type_id,
		"signal_type_display_name": signal_type_display_name.strip_edges(),
		"signal_type_short_label": signal_type_short_label.strip_edges(),
		"signal_description": signal_description.strip_edges(),
		"resources_visible": [],
		"resources_hidden_count": 0,
		"is_scanned": false,
		"can_scan_with_drone": false,
		"can_mine_with_ship": false,
		"can_recall_drone": false,
		"can_recall_mining_ship": false,
		"is_home_base": false,
		"mining_exhausted": false,
		"active_scan_drone_count": 0,
		"active_mining_ship_count": 0,
		"scan_drone_supporting_count": 0,
		"mining_ship_mining_count": 0,
		"mining_bonus": 0.0,
		"lore_text": _resolved_signal_lore_text(),
		"preview_texture": null,
		"distance_text": "-",
	}


func _resolved_signal_lore_text() -> String:
	var lore := DiscoverySignalUiTextDefinition.get_unknown_signal_lore()
	if not lore.is_empty():
		return lore
	return DiscoverySignalUiTextDefinition.get_template(
		DiscoverySignalUiTextDefinition.KEY_SIGNAL_LORE_FALLBACK
	)


func _resolved_panel_display_name() -> String:
	return DiscoverySignalUiTextDefinition.get_unknown_signal_name()


func _resolved_panel_object_type_label() -> String:
	return DiscoverySignalUiTextDefinition.get_signal_object_type_label()


func _apply_marker_text() -> void:
	if type_label == null:
		return

	type_label.text = DiscoverySignalUiTextDefinition.get_template(
		DiscoverySignalUiTextDefinition.KEY_MARKER_LABEL_FALLBACK
	)


func _apply_marker_texture() -> void:
	if marker_visual == null or marker_texture == null:
		return

	marker_visual.texture = marker_texture


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int,
) -> void:
	if not (event is InputEventMouseButton):
		return

	var mb := event as InputEventMouseButton

	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	get_viewport().set_input_as_handled()

	if mb.double_click and _is_selected:
		refocus_camera_requested.emit(self)
		return

	if _is_selected:
		return

	selected.emit(self)


func _build_fallback_texture() -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(24):
		for x in range(24):
			var dist := Vector2(x - 11.5, y - 11.5).length()

			if dist <= 8.0:
				image.set_pixel(x, y, Color(1.0, 0.85, 0.35, 1.0))
			elif dist <= 10.5:
				image.set_pixel(x, y, Color(1.0, 0.85, 0.35, 0.45))

	return ImageTexture.create_from_image(image)
