extends CharacterBody2D

@export var visual_rotation_offset_degrees: float = 0.0

@onready var visual_root: Node2D = $VisualRoot
@onready var camera_anchor: Marker2D = $CameraAnchor
@onready var navigation: ShipNavigationComponent = $ShipNavigationComponent

func _ready() -> void:
	visual_root.rotation_degrees = visual_rotation_offset_degrees
