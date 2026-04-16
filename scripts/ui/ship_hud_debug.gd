extends CanvasLayer

@export var player_ship_path: NodePath

@onready var player_ship: CharacterBody2D = get_node(player_ship_path)
@onready var fuel_label: Label = $Control/VBoxContainer/FuelLabel
@onready var cargo_label: Label = $Control/VBoxContainer/CargoLabel
@onready var hull_label: Label = $Control/VBoxContainer/HullLabel
@onready var target_label: Label = $Control/VBoxContainer/TargetLabel

func _process(_delta: float) -> void:
	if player_ship == null:
		return

	var nav := player_ship.get_node("ShipNavigationComponent") as ShipNavigationComponent

	fuel_label.text = "Fuel: 100"
	cargo_label.text = "Cargo: 0 / 20"
	hull_label.text = "Hull: 100%"
	target_label.text = "Target: %s" % (
		str(nav.target_position) if nav.has_target else "None"
	)
