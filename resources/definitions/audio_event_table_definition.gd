## Data-driven audio streams and optional path fallbacks for AudioManager.
## Loaded from `data/audio/audio_event_table.tres`.
class_name AudioEventTableDefinition
extends Resource

@export var sfx_streams: Dictionary = {}
@export var music_streams: Dictionary = {}
@export var world_sfx_streams: Dictionary = {}
@export var world_loop_streams: Dictionary = {}
## Path fallbacks when a stream is not embedded (e.g. missing import); resolved via AudioManager cache.
@export var sfx_paths: Dictionary = {}
@export var music_paths: Dictionary = {}
@export var cooldown_seconds_by_id: Dictionary = {}


func get_sfx_stream(id: StringName) -> AudioStream:
	return _get_stream_from_dict(sfx_streams, id)


func get_music_stream(id: StringName) -> AudioStream:
	return _get_stream_from_dict(music_streams, id)


func get_world_sfx_stream(id: StringName) -> AudioStream:
	var stream := _get_stream_from_dict(world_sfx_streams, id)
	if stream != null:
		return stream
	return get_sfx_stream(id)


func get_world_loop_stream(id: StringName) -> AudioStream:
	return _get_stream_from_dict(world_loop_streams, id)


func get_sfx_path(id: StringName) -> String:
	return _get_path_from_dict(sfx_paths, id)


func get_music_path(id: StringName) -> String:
	return _get_path_from_dict(music_paths, id)


func get_cooldown_seconds(id: StringName, fallback: float = 0.0) -> float:
	if id.is_empty():
		return fallback
	if cooldown_seconds_by_id.has(id):
		return float(cooldown_seconds_by_id[id])
	var id_str := String(id)
	if cooldown_seconds_by_id.has(id_str):
		return float(cooldown_seconds_by_id[id_str])
	return fallback


func has_any_stream(id: StringName) -> bool:
	if get_sfx_stream(id) != null:
		return true
	if get_music_stream(id) != null:
		return true
	if get_world_sfx_stream(id) != null:
		return true
	if get_world_loop_stream(id) != null:
		return true
	if not get_sfx_path(id).is_empty():
		return true
	if not get_music_path(id).is_empty():
		return true
	return false


func _get_stream_from_dict(streams: Dictionary, id: StringName) -> AudioStream:
	if id.is_empty() or streams.is_empty():
		return null
	if streams.has(id):
		return _variant_to_audio_stream(streams[id])
	var id_str := String(id)
	if streams.has(id_str):
		return _variant_to_audio_stream(streams[id_str])
	return null


func _get_path_from_dict(paths: Dictionary, id: StringName) -> String:
	if id.is_empty() or paths.is_empty():
		return ""
	if paths.has(id):
		return str(paths[id]).strip_edges()
	var id_str := String(id)
	if paths.has(id_str):
		return str(paths[id_str]).strip_edges()
	return ""


func _variant_to_audio_stream(value: Variant) -> AudioStream:
	if value is AudioStream:
		return value as AudioStream
	return null
