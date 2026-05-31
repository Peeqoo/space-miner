class_name SignalTypeDefinition
extends Resource

@export var id: String = "unknown"
@export var display_name: String = "Unknown Signature"
@export var short_label: String = "Unknown"
@export_multiline var description: String = ""
@export var marker_texture: Texture2D


func get_id() -> String:
	var trimmed := id.strip_edges()
	if trimmed.is_empty():
		return DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_TYPE_ID
	return trimmed


func get_display_name() -> String:
	var trimmed := display_name.strip_edges()
	if trimmed.is_empty():
		return DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_DISPLAY_NAME
	return trimmed


func get_short_label() -> String:
	var trimmed := short_label.strip_edges()
	if trimmed.is_empty():
		return DiscoveryDefinitionDefaults.DEFAULT_SIGNAL_SHORT_LABEL
	return trimmed


func get_description() -> String:
	return description.strip_edges()


func get_marker_texture() -> Texture2D:
	return marker_texture
