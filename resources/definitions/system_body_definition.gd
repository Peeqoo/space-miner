class_name SystemBodyDefinition
extends Resource

enum SizeAuthoringMode {
	AUTO,
	USE_REFERENCE_DATA,
	USE_ASSET_RATIO
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var body_type: String = ""
@export var orbit_center_id: String = ""

# Altbestand
@export var orbit_radius: float = 100.0
@export var orbit_speed: float = 1.0
@export var orbit_start_angle_degrees: float = 0.0
@export var body_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var texture: Texture2D
@export var can_build_base: bool = true

# Neu: kanonische Referenzdaten
@export var reference_radius_earth: float = 1.0
@export var reference_orbit_au: float = 1.0
@export var reference_period_days: float = 365.25

# Neu: Asset-Kalibrierung
@export var asset_body_diameter_px: float = 0.0
@export var asset_ring_diameter_px: float = 0.0
@export var authored_ratio_to_earth: float = 1.0
@export var size_authoring_mode: SizeAuthoringMode = SizeAuthoringMode.AUTO

# Neu: gezielte Feintuning-Biases
@export var gameplay_size_bias: float = 1.0
@export var gameplay_orbit_bias: float = 1.0
@export var gameplay_speed_bias: float = 1.0

# Neu: optionaler harter Override
@export var use_manual_scale_override: bool = false
@export var manual_scale_override: float = 1.0

# Sprint 4 Scan-Daten
@export var scan_basic_reveal_name: bool = true
@export var scan_basic_reveal_type: bool = true
@export var scan_basic_resources: PackedStringArray = []
@export var scan_deep_resources: PackedStringArray = []
@export var scan_special_resources: PackedStringArray = []
@export var scan_hidden_slots_after_special: int = 0
