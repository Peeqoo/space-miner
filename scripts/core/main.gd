extends Node

@export_file("*.tscn") var startup_scene_path: String = "res://scenes/galaxy/galaxy_map.tscn"

func _ready() -> void:
	SceneFlow.register_main_root(self)
	GameSession.ensure_boot_state()

	if $SceneRoot/CurrentSceneSlot.get_child_count() > 0:
		return

	SceneFlow.goto_scene(startup_scene_path)
