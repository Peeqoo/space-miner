extends Node

const DEFAULT_SLOT_PATH: NodePath = NodePath("SceneRoot/CurrentSceneSlot")

var _main_root: Node = null
var _current_scene: Node = null


func register_main_root(root: Node) -> void:
	_main_root = root


func goto_galaxy() -> void:
	goto_scene("res://scenes/galaxy/galaxy_map.tscn")


func goto_system() -> void:
	goto_scene("res://scenes/system/system_scene.tscn")


func goto_hub() -> void:
	goto_scene("res://scenes/hub/earth_hub.tscn")


func goto_scene(scene_path: String) -> void:

	var scene_resource: PackedScene = load(scene_path) as PackedScene
	if scene_resource == null:
		push_error("Szene konnte nicht geladen werden: %s" % scene_path)
		return

	# Fallback: falls Main nicht registriert ist, normaler Szenenwechsel
	if _main_root == null:
		push_warning("SceneFlow: Kein Main-Root registriert, fallback via change_scene_to_packed().")
		get_tree().change_scene_to_packed(scene_resource)
		return

	var slot: Node = _main_root.get_node_or_null(DEFAULT_SLOT_PATH)
	if slot == null:
		push_warning("SceneFlow: CurrentSceneSlot fehlt, fallback via change_scene_to_packed().")
		get_tree().change_scene_to_packed(scene_resource)
		return

	for child in slot.get_children():
		child.queue_free()

	var next_scene: Node = scene_resource.instantiate()
	slot.add_child(next_scene)
	_current_scene = next_scene

func get_current_scene() -> Node:
	return _current_scene
