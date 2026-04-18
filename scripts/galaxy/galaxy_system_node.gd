extends Node2D

@export var system_definition: SystemDefinition

func _ready():
	$Area2D.input_event.connect(_on_click)

func _on_click(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed:
		get_tree().current_scene.select_system(system_definition)
