## UI metadata for a single resource id (amounts and deposits live elsewhere).
class_name ResourceDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var short_label: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
@export var sort_order: int = 0
@export var category: StringName = &""
@export var is_storable: bool = true
@export var is_deposit_resource: bool = true
@export var is_abstract_currency: bool = false
@export var show_in_top_hud: bool = false
@export var show_in_storage_panel: bool = true
