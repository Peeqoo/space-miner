## Central SFX / UI / music playback. Safe when audio files or buses are missing (warn + skip).
##
## Import dock (per .ogg):
## - Loop On: scan_loop.ogg, music_*.ogg (all music tracks; reimport after rename)
## - Loop Off: all one-shot SFX
##
## Mixing in this script (not in external editors):
## - Per-event level: EVENT_VOLUME_DB
## - Per-event pitch variation: EVENT_PITCH_RANGE (random between x and y; default 1.0)
##
## World SFX: EVENT_VOLUME_DB + linear_to_db(distance/zoom factor); per-event cooldown.
## World loops: distance/zoom only mute/pause (-80 dB); logical stop via stop_world_loop() or invalid source.
extends Node

const AUDIO_EVENT_TABLE_PATH := "res://data/audio/audio_event_table.tres"

const DEFAULT_SYSTEM_MUSIC_TRACK_ID: StringName = &"music_system_default"

## Legacy id -> canonical id (same .ogg path; avoids duplicate play_music restarts).
const MUSIC_TRACK_CANONICAL: Dictionary = {
	&"menu_theme": &"music_main_menu",
	&"galaxy_ambient": &"music_galaxy_map",
	&"system_ambient_01": &"music_system_default",
	&"system_ambient": &"music_system_default",
}

const UI_EVENT_IDS: Array[StringName] = [
	&"ui_click",
	&"ui_hover",
	&"ui_blocked",
	&"not_enough_resources",
]

const GAME_EVENT_IDS: Array[StringName] = [
	&"scan_start",
	&"scan_complete",
	&"resource_revealed",
	&"scan_drone_launch",
	&"scan_drone_arrive",
	&"scan_loop",
	&"mining_start",
	&"mining_ship_launch",
	&"mining_ship_arrive",
	&"mining_resource_tick",
	&"mining_complete",
	&"ship_return",
	&"cargo_unload",
	&"build_success",
	&"object_selected",
]

const WORLD_LOOP_EVENT_IDS: Array[StringName] = [&"scan_loop"]

const AMBIENT_MUSIC_TRACK_IDS: Array[StringName] = [
	&"music_main_menu",
	&"music_galaxy_map",
	&"music_system_default",
	&"music_solar_system",
	&"music_proxima_system",
]

const EVENT_VOLUME_DB: Dictionary[StringName, float] = {
	&"ui_click": -10.0,
	&"ui_hover": -10.0,
	&"ui_blocked": -10.0,
	&"not_enough_resources": -10.0,
	&"object_selected": -10.0,
	&"build_success": -20.0,
	
	&"scan_drone_launch": 5.0,
	&"scan_drone_arrive": 5.0,
	&"scan_loop": 5.0,
	&"scan_complete": -10.0,
	&"resource_revealed": 0.0,
	
	&"mining_ship_launch": 5.0,
	&"mining_ship_arrive": 5.0,
	&"mining_resource_tick": -10.0,
	&"mining_complete": -10.0,
	&"cargo_unload": -30.0,
	
	&"music_main_menu": 0.0,
	&"music_galaxy_map": 0.0,
	&"music_system_default": 0.0,
	&"music_solar_system": 0.0,
	&"music_proxima_system": 0.0,
}

const EVENT_PITCH_RANGE: Dictionary[StringName, Vector2] = {
	&"ui_hover": Vector2(0.98, 1.02),
	&"mining_resource_tick": Vector2(0.94, 1.06),
	&"cargo_unload": Vector2(0.96, 1.04),
}

const WORLD_SFX_FULL_VOLUME_DISTANCE := 180.0
const WORLD_SFX_MAX_DISTANCE := 950.0
const WORLD_SFX_MIN_VOLUME_FACTOR := 0.06
const WORLD_SFX_MIN_ZOOM_FOR_AUDIO := 0.45

const POOL_SIZE: int = 8

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_AMBIENT: StringName = &"Ambient"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"
const BUS_GAME: StringName = &"Game"

const FALLBACK_UI: Array[StringName] = [&"SFX", &"Master"]
const FALLBACK_GAME: Array[StringName] = [&"SFX", &"Master"]
const FALLBACK_SFX: Array[StringName] = [&"Master"]
const FALLBACK_AMBIENT: Array[StringName] = [&"Music", &"Master"]
const FALLBACK_MUSIC: Array[StringName] = [&"Master"]

var audio_event_table: AudioEventTableDefinition = null

var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _stream_cache: Dictionary = {}
var _audio_table_load_warned: bool = false
var _music_fade_tween: Tween
var _current_music_track: StringName = &""
var _last_played_msec_by_event: Dictionary = {}
var _world_loops: Dictionary = {}


func _ready() -> void:
	_load_audio_event_table()
	set_process(true)
	_build_sfx_pool()
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = _resolve_existing_bus(BUS_MUSIC, FALLBACK_MUSIC)
	add_child(_music_player)


func play_sfx(event_id: StringName) -> void:
	if not _can_play_event(event_id):
		return
	_play_event(event_id, _bus_for_sfx_event(event_id), 1.0)


func play_ui(event_id: StringName) -> void:
	if not _can_play_event(event_id):
		return
	_play_event(event_id, _resolve_existing_bus(BUS_UI, FALLBACK_UI), 1.0)


func play_world_sfx(event_id: StringName, world_position: Vector2) -> void:
	play_world_sfx_with_cooldown(event_id, world_position, &"")


func play_world_sfx_with_cooldown(
	event_id: StringName,
	world_position: Vector2,
	cooldown_key: StringName,
) -> void:
	var volume_factor := _world_sfx_volume_factor(world_position)
	if volume_factor <= WORLD_SFX_MIN_VOLUME_FACTOR:
		return
	if not _can_play_event(event_id, cooldown_key):
		return
	_play_event(event_id, _bus_for_sfx_event(event_id), volume_factor)


func play_world_loop(event_id: StringName, loop_id: StringName, source_node: Node2D) -> void:
	if loop_id.is_empty():
		return
	if source_node == null or not is_instance_valid(source_node):
		return
	if event_id not in WORLD_LOOP_EVENT_IDS:
		push_warning("AudioManager.play_world_loop: unsupported loop event '%s'" % String(event_id))
		return

	stop_world_loop(loop_id)

	var stream := _resolve_world_loop_stream(event_id)
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.name = "WorldLoop_%s" % String(loop_id)
	player.bus = _bus_for_sfx_event(event_id)
	player.stream = stream
	add_child(player)

	player.pitch_scale = _event_pitch_scale(event_id)
	_update_world_loop_player(player, event_id, _world_sfx_volume_factor(source_node.global_position))

	_world_loops[loop_id] = {
		"player": player,
		"source_id": source_node.get_instance_id(),
		"event_id": event_id,
	}


func stop_world_loop(loop_id: StringName) -> void:
	if loop_id.is_empty() or not _world_loops.has(loop_id):
		return

	var entry: Variant = _world_loops[loop_id]
	_world_loops.erase(loop_id)

	if entry is not Dictionary:
		return

	var player_variant: Variant = (entry as Dictionary).get("player", null)
	if player_variant is AudioStreamPlayer:
		var player := player_variant as AudioStreamPlayer
		if is_instance_valid(player):
			player.stop()
			player.queue_free()


func _process(_delta: float) -> void:
	if _world_loops.is_empty():
		return

	var stale_loop_ids: Array[StringName] = []

	for loop_id_variant: Variant in _world_loops.keys():
		var loop_id: StringName = loop_id_variant as StringName
		var entry: Dictionary = _world_loops[loop_id] as Dictionary
		var player_variant: Variant = entry.get("player", null)
		var source_id: int = int(entry.get("source_id", 0))

		if not (player_variant is AudioStreamPlayer):
			stale_loop_ids.append(loop_id)
			continue

		var player := player_variant as AudioStreamPlayer
		if not is_instance_valid(player):
			stale_loop_ids.append(loop_id)
			continue

		var source := instance_from_id(source_id) as Node2D
		if source == null or not is_instance_valid(source):
			stale_loop_ids.append(loop_id)
			continue

		var event_id: StringName = entry.get("event_id", &"") as StringName
		var volume_factor := _world_sfx_volume_factor(source.global_position)
		_update_world_loop_player(player, event_id, volume_factor)

	for stale_id: StringName in stale_loop_ids:
		stop_world_loop(stale_id)


func resolve_music_track_id(track_id: StringName) -> StringName:
	if track_id.is_empty():
		return DEFAULT_SYSTEM_MUSIC_TRACK_ID

	var canonical_id := _canonical_music_track_id(track_id)
	if _has_music_track(track_id) or _has_music_track(canonical_id):
		return canonical_id

	push_warning(
		"AudioManager: unknown music track '%s', fallback to '%s'"
		% [String(track_id), String(DEFAULT_SYSTEM_MUSIC_TRACK_ID)]
	)
	return DEFAULT_SYSTEM_MUSIC_TRACK_ID


func play_music(track_id: StringName, fade_time: float = 0.5) -> void:
	var resolved_id := resolve_music_track_id(track_id)
	var canonical_id := _canonical_music_track_id(resolved_id)
	if canonical_id == _canonical_music_track_id(_current_music_track) and _music_player.playing:
		return

	var stream := _resolve_music_stream(canonical_id)
	if stream == null:
		push_warning("AudioManager.play_music: no stream for track '%s'" % String(resolved_id))
		return
	if stream == null:
		return

	_music_player.bus = _bus_for_music_track(canonical_id)
	_music_player.pitch_scale = _event_pitch_scale(canonical_id)
	_current_music_track = canonical_id
	var target_db := _event_volume_db(canonical_id)
	var fade := maxf(fade_time, 0.0)

	if _music_player.playing and fade > 0.0:
		_fade_music_to(stream, fade, target_db)
	else:
		_music_player.stream = stream
		_music_player.volume_db = target_db
		_music_player.play()


func stop_music(fade_time: float = 0.5) -> void:
	if not _music_player.playing:
		_current_music_track = &""
		return

	var fade := maxf(fade_time, 0.0)
	_current_music_track = &""
	_kill_music_tween()

	if fade <= 0.0:
		_music_player.stop()
		_music_player.volume_db = 0.0
		return

	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(_music_player, "volume_db", -80.0, fade)
	_music_fade_tween.tween_callback(_music_player.stop)
	_music_fade_tween.tween_callback(func() -> void: _music_player.volume_db = 0.0)


func set_bus_volume_linear(bus_name: StringName, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(String(bus_name))
	if bus_index < 0:
		push_warning("AudioManager.set_bus_volume_linear: bus '%s' not found" % String(bus_name))
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(value, 0.0, 1.0)))


func mute_bus(bus_name: StringName, muted: bool) -> void:
	var bus_index := AudioServer.get_bus_index(String(bus_name))
	if bus_index < 0:
		push_warning("AudioManager.mute_bus: bus '%s' not found" % String(bus_name))
		return
	AudioServer.set_bus_mute(bus_index, muted)


## Optional entry points for gameplay/UI when Autoload is absent (tests, partial scenes).
static func play_sfx_optional(event_id: StringName) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.play_sfx(event_id)


static func play_world_sfx_optional(event_id: StringName, world_position: Vector2) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.play_world_sfx(event_id, world_position)


static func play_world_sfx_with_cooldown_optional(
	event_id: StringName,
	world_position: Vector2,
	cooldown_key: StringName,
) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.play_world_sfx_with_cooldown(event_id, world_position, cooldown_key)


static func play_world_loop_optional(
	event_id: StringName,
	loop_id: StringName,
	source_node: Node2D,
) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.play_world_loop(event_id, loop_id, source_node)


static func stop_world_loop_optional(loop_id: StringName) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.stop_world_loop(loop_id)


static func play_ui_optional(event_id: StringName) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.play_ui(event_id)


static func play_music_optional(track_id: StringName, fade_time: float = 0.5) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.play_music(track_id, fade_time)


static func resolve_music_track_id_optional(track_id: StringName) -> StringName:
	var mgr := _get_instance()
	if mgr != null:
		return mgr.resolve_music_track_id(track_id)
	return DEFAULT_SYSTEM_MUSIC_TRACK_ID


static func bind_ui_button_optional(button: Button) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.bind_ui_button(button)


static func bind_ui_buttons_in_tree_optional(root: Node) -> void:
	var mgr := _get_instance()
	if mgr != null:
		mgr.bind_ui_buttons_in_tree(root)


func bind_ui_buttons_in_tree(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	_bind_ui_buttons_recursive(root)


func bind_ui_button(button: Button) -> void:
	if button == null or not is_instance_valid(button):
		return
	if button.has_meta(&"audio_ui_bound"):
		return
	button.set_meta(&"audio_ui_bound", true)

	if not button.mouse_entered.is_connected(_on_ui_button_mouse_entered):
		button.mouse_entered.connect(_on_ui_button_mouse_entered)

	if not button.pressed.is_connected(_on_ui_button_pressed):
		button.pressed.connect(_on_ui_button_pressed)

	if not button.gui_input.is_connected(_on_ui_button_gui_input.bind(button)):
		button.gui_input.connect(_on_ui_button_gui_input.bind(button))


func _bind_ui_buttons_recursive(node: Node) -> void:
	if node is Button:
		bind_ui_button(node as Button)
	for child in node.get_children():
		if child != null and is_instance_valid(child):
			_bind_ui_buttons_recursive(child)


func _canonical_music_track_id(track_id: StringName) -> StringName:
	var mapped: Variant = MUSIC_TRACK_CANONICAL.get(track_id, track_id)
	return mapped as StringName


static func _get_instance() -> Node:
	var tree := Engine.get_main_loop()
	if tree is not SceneTree:
		return null
	return (tree as SceneTree).root.get_node_or_null(NodePath("AudioManager"))


func _play_event(event_id: StringName, bus: StringName, volume_factor: float = 1.0) -> void:
	if event_id.is_empty():
		push_warning("AudioManager: empty event_id")
		return

	var stream := _resolve_sfx_stream(event_id)
	if stream == null:
		push_warning("AudioManager: unknown or missing event '%s'" % String(event_id))
		return
	if stream == null:
		return

	var player := _acquire_sfx_player()
	if player == null:
		return

	player.bus = bus
	player.stream = stream
	_configure_player_for_event(player, event_id, volume_factor)
	player.play()


func _load_audio_event_table() -> void:
	if not ResourceLoader.exists(AUDIO_EVENT_TABLE_PATH):
		_warn_audio_table_once(
			"AudioManager: audio event table missing at '%s'" % AUDIO_EVENT_TABLE_PATH
		)
		return

	var loaded: Resource = load(AUDIO_EVENT_TABLE_PATH)
	if loaded == null or not (loaded is AudioEventTableDefinition):
		_warn_audio_table_once(
			"AudioManager: invalid audio event table at '%s'" % AUDIO_EVENT_TABLE_PATH
		)
		return

	audio_event_table = loaded as AudioEventTableDefinition


func _warn_audio_table_once(message: String) -> void:
	if _audio_table_load_warned:
		return
	_audio_table_load_warned = true
	push_warning(message)


func _resolve_sfx_stream(event_id: StringName) -> AudioStream:
	if audio_event_table != null:
		var embedded := audio_event_table.get_sfx_stream(event_id)
		if embedded != null:
			return embedded
		var path := audio_event_table.get_sfx_path(event_id)
		if not path.is_empty():
			return _load_stream(path)
	return null


func _resolve_world_loop_stream(event_id: StringName) -> AudioStream:
	if audio_event_table != null:
		var loop_stream := audio_event_table.get_world_loop_stream(event_id)
		if loop_stream != null:
			return loop_stream
	return _resolve_sfx_stream(event_id)


func _resolve_music_stream(track_id: StringName) -> AudioStream:
	if audio_event_table != null:
		var embedded := audio_event_table.get_music_stream(track_id)
		if embedded != null:
			return embedded
		var path := audio_event_table.get_music_path(track_id)
		if not path.is_empty():
			return _load_stream(path)
	return null


func _has_music_track(track_id: StringName) -> bool:
	if track_id.is_empty():
		return false
	if audio_event_table == null:
		return false
	if audio_event_table.get_music_stream(track_id) != null:
		return true
	return not audio_event_table.get_music_path(track_id).is_empty()


func _event_cooldown_seconds(event_id: StringName) -> float:
	if audio_event_table != null:
		return audio_event_table.get_cooldown_seconds(event_id, 0.0)
	return 0.0


func _can_play_event(event_id: StringName, cooldown_key: StringName = &"") -> bool:
	var cooldown_sec := _event_cooldown_seconds(event_id)
	if cooldown_sec <= 0.0:
		return true

	var key: StringName = cooldown_key if not cooldown_key.is_empty() else event_id
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(_last_played_msec_by_event.get(key, -1))
	if last_msec >= 0 and (now_msec - last_msec) < int(cooldown_sec * 1000.0):
		return false

	_last_played_msec_by_event[key] = now_msec
	return true


func _event_volume_db(event_id: StringName) -> float:
	return float(EVENT_VOLUME_DB.get(event_id, 0.0))


func _event_pitch_scale(event_id: StringName) -> float:
	var pitch_range_variant: Variant = EVENT_PITCH_RANGE.get(event_id, Vector2(1.0, 1.0))
	if pitch_range_variant is not Vector2:
		return 1.0

	var pitch_range: Vector2 = pitch_range_variant as Vector2
	if pitch_range.x >= pitch_range.y:
		return pitch_range.x

	return randf_range(pitch_range.x, pitch_range.y)


func _configure_player_for_event(
	player: AudioStreamPlayer,
	event_id: StringName,
	volume_factor: float,
) -> void:
	player.pitch_scale = _event_pitch_scale(event_id)
	_apply_player_volume(player, event_id, volume_factor)


func _apply_player_volume(
	player: AudioStreamPlayer,
	event_id: StringName,
	volume_factor: float,
) -> void:
	var event_db := _event_volume_db(event_id)
	var vol := clampf(volume_factor, 0.0, 1.0)

	if vol <= WORLD_SFX_MIN_VOLUME_FACTOR:
		player.volume_db = -80.0
		return

	player.volume_db = event_db + linear_to_db(vol)


func _update_world_loop_player(
	player: AudioStreamPlayer,
	event_id: StringName,
	volume_factor: float,
) -> void:
	if not player.playing:
		player.play()

	if volume_factor <= WORLD_SFX_MIN_VOLUME_FACTOR:
		player.volume_db = -80.0
		player.stream_paused = true
		return

	player.stream_paused = false
	_apply_player_volume(player, event_id, volume_factor)


func _world_sfx_volume_factor(world_position: Vector2) -> float:
	var camera := _get_active_camera_2d()
	if camera == null:
		return 0.0

	var distance := camera.global_position.distance_to(world_position)
	if distance > WORLD_SFX_MAX_DISTANCE:
		return 0.0

	var zoom_scalar := minf(camera.zoom.x, camera.zoom.y)
	if zoom_scalar <= WORLD_SFX_MIN_ZOOM_FOR_AUDIO:
		return 0.0

	var distance_factor := 1.0
	if distance > WORLD_SFX_FULL_VOLUME_DISTANCE:
		var span := WORLD_SFX_MAX_DISTANCE - WORLD_SFX_FULL_VOLUME_DISTANCE
		if span > 0.0:
			var t := (distance - WORLD_SFX_FULL_VOLUME_DISTANCE) / span
			distance_factor = clampf(1.0 - t, 0.0, 1.0)
		else:
			distance_factor = 0.0

	var zoom_factor := 1.0
	if zoom_scalar < 1.0:
		var zoom_span := 1.0 - WORLD_SFX_MIN_ZOOM_FOR_AUDIO
		if zoom_span > 0.0:
			zoom_factor = clampf((zoom_scalar - WORLD_SFX_MIN_ZOOM_FOR_AUDIO) / zoom_span, 0.0, 1.0)
		else:
			zoom_factor = 0.0

	return clampf(distance_factor * zoom_factor, 0.0, 1.0)


func _get_active_camera_2d() -> Camera2D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_2d()


func _bus_for_sfx_event(event_id: StringName) -> StringName:
	if _is_ui_event(event_id):
		return _resolve_existing_bus(BUS_UI, FALLBACK_UI)
	if _is_game_event(event_id):
		return _resolve_existing_bus(BUS_GAME, FALLBACK_GAME)
	return _resolve_existing_bus(BUS_SFX, FALLBACK_SFX)


func _bus_for_music_track(track_id: StringName) -> StringName:
	if track_id in AMBIENT_MUSIC_TRACK_IDS:
		return _resolve_existing_bus(BUS_AMBIENT, FALLBACK_AMBIENT)
	return _resolve_existing_bus(BUS_MUSIC, FALLBACK_MUSIC)


func _is_ui_event(event_id: StringName) -> bool:
	return event_id in UI_EVENT_IDS


func _is_game_event(event_id: StringName) -> bool:
	return event_id in GAME_EVENT_IDS


func _resolve_existing_bus(preferred: StringName, fallbacks: Array[StringName]) -> StringName:
	if AudioServer.get_bus_index(String(preferred)) >= 0:
		return preferred
	for bus_name: StringName in fallbacks:
		if AudioServer.get_bus_index(String(bus_name)) >= 0:
			return bus_name
	return BUS_MASTER


func _load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null

	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream

	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing audio file '%s'" % path)
		_stream_cache[path] = null
		return null

	var loaded: Resource = load(path)
	if loaded == null or not (loaded is AudioStream):
		push_warning("AudioManager: failed to load audio '%s'" % path)
		_stream_cache[path] = null
		return null

	_stream_cache[path] = loaded as AudioStream
	return _stream_cache[path]


func _build_sfx_pool() -> void:
	_sfx_pool.clear()
	var default_bus := _resolve_existing_bus(BUS_GAME, FALLBACK_GAME)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer_%d" % i
		player.bus = default_bus
		add_child(player)
		_sfx_pool.append(player)


func _acquire_sfx_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx_pool:
		if not player.playing:
			return player
	return _sfx_pool[0] if not _sfx_pool.is_empty() else null


func _fade_music_to(stream: AudioStream, fade_time: float, target_db: float) -> void:
	_kill_music_tween()
	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(_music_player, "volume_db", -80.0, fade_time * 0.5)
	_music_fade_tween.tween_callback(
		func() -> void:
			_music_player.stop()
			_music_player.stream = stream
			_music_player.pitch_scale = _event_pitch_scale(_current_music_track)
			_music_player.volume_db = -80.0
			_music_player.play()
	)
	_music_fade_tween.tween_property(_music_player, "volume_db", target_db, fade_time * 0.5)


func _kill_music_tween() -> void:
	if _music_fade_tween != null and _music_fade_tween.is_valid():
		_music_fade_tween.kill()
	_music_fade_tween = null


func _on_ui_button_mouse_entered() -> void:
	play_ui(&"ui_hover")


func _on_ui_button_pressed() -> void:
	play_ui(&"ui_click")


func _on_ui_button_gui_input(event: InputEvent, button: Button) -> void:
	if button == null or not button.disabled:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	play_ui(&"ui_blocked")
