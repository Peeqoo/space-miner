class_name PointOfInterestDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var poi_type: String = ""
@export var orbit_center_id: String = ""
@export var orbit_radius: float = 100.0
@export var orbit_speed: float = 1.0
@export var orbit_start_angle_degrees: float = 0.0
@export var poi_color: Color = Color.WHITE
@export var texture: Texture2D

@export var scan_basic_reveal_name: bool = true
@export var scan_basic_reveal_type: bool = true
@export var scan_resources: Array[ScannedResourceEntry] = []
@export var scan_hidden_slots_after_special: int = 0

@export_group("Discovery")
## `hidden` / `signal` / `known`. Empty = legacy (runtime KNOWN until explicitly set).
@export var default_discovery_state: String = ""
@export var signal_type: SignalTypeDefinition
## Optional pre-reveal lore for SIGNAL state; does not use the real `description`.
@export_multiline var signal_lore: String = ""


func get_normalized_default_discovery_state() -> String:
	var context := "PointOfInterestDefinition '%s'" % id.strip_edges()
	return DiscoveryDefinitionDefaults.normalize_default_discovery_state(default_discovery_state, context)


func get_resolved_signal_type_id() -> String:
	if signal_type != null:
		return signal_type.get_id()
	return DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_TYPE_ID


func get_resolved_signal_type_display_name() -> String:
	if signal_type != null:
		return signal_type.get_display_name()
	return DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_DISPLAY_NAME


func get_resolved_signal_type_short_label() -> String:
	if signal_type != null:
		return signal_type.get_short_label()
	return DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_SHORT_LABEL


func get_resolved_signal_description() -> String:
	if signal_type != null:
		return signal_type.get_description()
	return ""


func get_resolved_signal_marker_texture() -> Texture2D:
	if signal_type != null:
		return signal_type.get_marker_texture()
	return null


func get_scan_resources_by_layer(layer: ScannedResourceEntry.Layer) -> Array[ScannedResourceEntry]:
	var result: Array[ScannedResourceEntry] = []
	for entry in scan_resources:
		if entry != null and entry.layer == layer:
			result.append(entry)
	return result


func get_basic_scan_resources() -> Array[ScannedResourceEntry]:
	return get_scan_resources_by_layer(ScannedResourceEntry.Layer.BASIC)


func get_deep_scan_resources() -> Array[ScannedResourceEntry]:
	return get_scan_resources_by_layer(ScannedResourceEntry.Layer.DEEP)


func get_special_scan_resources() -> Array[ScannedResourceEntry]:
	return get_scan_resources_by_layer(ScannedResourceEntry.Layer.SPECIAL)
