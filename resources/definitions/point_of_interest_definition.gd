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
