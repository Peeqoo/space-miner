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

# Sprint 4 Scan-Daten
@export var scan_basic_reveal_name: bool = true
@export var scan_basic_reveal_type: bool = true
@export var scan_basic_resources: PackedStringArray = []
@export var scan_deep_resources: PackedStringArray = []
@export var scan_special_resources: PackedStringArray = []
@export var scan_hidden_slots_after_special: int = 0
