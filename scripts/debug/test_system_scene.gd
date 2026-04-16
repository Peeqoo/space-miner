extends Node2D

@onready var player_ship: CharacterBody2D = $PlayerShip
@onready var camera: Camera2D = $Camera2D
@onready var debug_label: Label = $CanvasLayer/DebugLabel
@export var manual_cancel_action: StringName = &"clear_navigation_target"

func _ready() -> void:
	camera.make_current()

func _process(_delta: float) -> void:
	if player_ship:
		camera.global_position = camera.global_position.lerp(player_ship.global_position, 0.12)

	var nav := player_ship.get_node("ShipNavigationComponent") as ShipNavigationComponent
	var debug := nav.get_debug_data()

	debug_label.text = (
		"Speed: %.1f\nHas Target: %s\nTarget: %s\nShip Pos: %s"
		% [
			debug.speed,
			str(debug.has_target),
			str(debug.target_position),
			str(player_ship.global_position)
		]
	)
