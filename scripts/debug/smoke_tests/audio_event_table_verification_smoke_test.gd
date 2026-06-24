## Audio event table verification smoke test (debug-only).
## Run:
##   godot --headless --path . --scene res://scripts/debug/smoke_tests/audio_event_table_verification_smoke_runner.tscn
extends Node

const AUDIO_EVENT_TABLE_PATH: String = "res://data/audio/audio_event_table.tres"

## SFX IDs referenced from gameplay / UI code (must resolve in table).
const CODE_USED_SFX_IDS: Array[StringName] = [
	&"ui_click",
	&"ui_hover",
	&"ui_blocked",
	&"not_enough_resources",
	&"build_success",
	&"object_selected",
	&"scan_complete",
	&"resource_revealed",
	&"scan_drone_launch",
	&"scan_drone_arrive",
	&"scan_loop",
	&"mining_ship_launch",
	&"mining_ship_arrive",
	&"mining_resource_tick",
	&"mining_complete",
	&"cargo_unload",
]

## Music track IDs requested from scene/UI code.
const CODE_USED_MUSIC_IDS: Array[StringName] = [
	&"music_main_menu",
	&"music_galaxy_map",
	&"music_solar_system",
	&"music_proxima_system",
	&"music_system_default",
]

## Registered in AudioManager / table but not wired in v0.1 gameplay code.
const OPTIONAL_SFX_IDS: Dictionary = {
	&"scan_start": "registered_in_audio_manager_not_wired_v0_1",
	&"mining_start": "path_fallback_asset_missing_not_wired_v0_1",
	&"ship_return": "path_fallback_asset_missing_not_wired_v0_1",
}

const CRITICAL_AUTOMATION_SFX_IDS: Array[StringName] = [
	&"scan_drone_launch",
	&"scan_drone_arrive",
	&"scan_complete",
	&"mining_ship_launch",
	&"mining_ship_arrive",
	&"mining_complete",
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _results: Dictionary = {}


func _ready() -> void:
	if not OS.is_debug_build():
		_notes.append("Not a debug build — runtime smoke skipped")
		_finish()
		return
	call_deferred("_begin")


func _begin() -> void:
	GameSession.reset_for_new_game()
	_test_a_table_loads_and_required_ids()
	_test_b_code_ids_exist_or_documented_optional()
	_test_c_automation_ship_scan_ids()
	_test_d_audio_manager_runtime_unchanged()
	_regression_checks()
	_finish()


func _test_a_table_loads_and_required_ids() -> void:
	var res: Resource = load(AUDIO_EVENT_TABLE_PATH)
	_results["test_a_tres_loaded"] = res is AudioEventTableDefinition
	if not (res is AudioEventTableDefinition):
		_fail("Test A: failed to load %s" % AUDIO_EVENT_TABLE_PATH)
		return

	var table: AudioEventTableDefinition = res as AudioEventTableDefinition
	_results["test_a_sfx_stream_count"] = table.sfx_streams.size()
	_results["test_a_music_stream_count"] = table.music_streams.size()

	var mgr: Node = AudioManager._get_instance()
	_results["test_a_audio_manager_present"] = mgr != null
	if mgr == null:
		_fail("Test A: AudioManager autoload missing")
		return

	var mgr_table: AudioEventTableDefinition = mgr.audio_event_table
	_results["test_a_manager_table_loaded"] = mgr_table != null
	if mgr_table == null:
		_fail("Test A: AudioManager.audio_event_table is null")
		return

	var missing_required: PackedStringArray = []
	for event_id: StringName in CODE_USED_SFX_IDS:
		if not _event_is_resolvable(table, event_id):
			missing_required.append(String(event_id))

	_results["test_a_missing_required_sfx"] = missing_required
	if not missing_required.is_empty():
		_fail("Test A: required SFX not resolvable: %s" % str(missing_required))


func _test_b_code_ids_exist_or_documented_optional() -> void:
	var table: AudioEventTableDefinition = load(AUDIO_EVENT_TABLE_PATH) as AudioEventTableDefinition
	if table == null:
		return

	var missing_code_sfx: PackedStringArray = []
	for event_id: StringName in CODE_USED_SFX_IDS:
		if not table.has_any_stream(event_id):
			missing_code_sfx.append(String(event_id))

	_results["test_b_missing_code_sfx_registry"] = missing_code_sfx
	if not missing_code_sfx.is_empty():
		_fail("Test B: code-used SFX missing from table registry: %s" % str(missing_code_sfx))

	var undocumented_optional: PackedStringArray = []
	for event_id: StringName in OPTIONAL_SFX_IDS.keys():
		if not table.has_any_stream(event_id) and not OPTIONAL_SFX_IDS.has(event_id):
			undocumented_optional.append(String(event_id))

	_results["test_b_optional_registry_count"] = OPTIONAL_SFX_IDS.size()

	var missing_music: PackedStringArray = []
	var missing_music_files: PackedStringArray = []
	for track_id: StringName in CODE_USED_MUSIC_IDS:
		if not table.has_any_stream(track_id):
			missing_music.append(String(track_id))
		elif not _event_is_resolvable(table, track_id):
			missing_music_files.append(String(track_id))

	_results["test_b_missing_music_registry"] = missing_music
	_results["test_b_missing_music_files"] = missing_music_files

	if not missing_music.is_empty():
		_fail("Test B: code-used music missing from table: %s" % str(missing_music))
	if not missing_music_files.is_empty():
		_notes.append(
			"Test B: music path registered but file missing on disk: %s"
			% str(missing_music_files)
		)


func _test_c_automation_ship_scan_ids() -> void:
	var table: AudioEventTableDefinition = load(AUDIO_EVENT_TABLE_PATH) as AudioEventTableDefinition
	if table == null:
		return

	var missing_critical: PackedStringArray = []
	for event_id: StringName in CRITICAL_AUTOMATION_SFX_IDS:
		if not _event_is_resolvable(table, event_id):
			missing_critical.append(String(event_id))

	_results["test_c_critical_ids_checked"] = CRITICAL_AUTOMATION_SFX_IDS.size()
	_results["test_c_missing_critical"] = missing_critical
	if not missing_critical.is_empty():
		_fail("Test C: critical automation SFX not resolvable: %s" % str(missing_critical))

	if table.get_world_loop_stream(&"scan_loop") == null:
		_fail("Test C: scan_loop missing from world_loop_streams")


func _test_d_audio_manager_runtime_unchanged() -> void:
	var mgr: Node = AudioManager._get_instance()
	if mgr == null:
		_fail("Test D: AudioManager missing")
		return

	var table_before: AudioEventTableDefinition = mgr.audio_event_table
	_results["test_d_table_before_play"] = table_before != null

	AudioManager.play_sfx_optional(&"object_selected")
	AudioManager.play_sfx_optional(&"build_success")
	AudioManager.play_world_sfx_optional(&"scan_drone_launch", Vector2.ZERO)

	var table_after: AudioEventTableDefinition = mgr.audio_event_table
	_results["test_d_table_after_play"] = table_after != null
	if table_before != table_after:
		_fail("Test D: AudioManager.audio_event_table reference changed after play calls")


func _event_is_resolvable(table: AudioEventTableDefinition, event_id: StringName) -> bool:
	if table.get_sfx_stream(event_id) != null:
		return true
	if table.get_world_sfx_stream(event_id) != null:
		return true
	if table.get_world_loop_stream(event_id) != null:
		return true
	if table.get_music_stream(event_id) != null:
		return true

	var sfx_path: String = table.get_sfx_path(event_id)
	if not sfx_path.is_empty() and ResourceLoader.exists(sfx_path):
		return true

	var music_path: String = table.get_music_path(event_id)
	if not music_path.is_empty() and ResourceLoader.exists(music_path):
		return true

	return false


func _regression_checks() -> void:
	if SaveManager.SAVE_VERSION != 1:
		_fail("SAVE_VERSION changed from 1")
	var tooltip_count: int = _count_tooltip_recursive(get_tree().root)
	_results["tooltip_text_count"] = tooltip_count
	if tooltip_count != 0:
		_fail("tooltip_text count expected 0, got %d" % tooltip_count)


func _count_tooltip_recursive(node: Node) -> int:
	var count: int = 0
	if node is Control:
		var ctl: Control = node as Control
		if not str(ctl.tooltip_text).is_empty():
			count += 1
	for child: Node in node.get_children():
		count += _count_tooltip_recursive(child)
	return count


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[AudioEventTableVerificationSmoke] FAIL: %s" % message)


func _finish() -> void:
	var status: String = "PASS"
	if not _failures.is_empty():
		status = "FAIL"
	elif not _notes.is_empty():
		status = "PASS WITH NOTES"
	print("=== Audio Event Table Verification Smoke ===")
	print("Status: %s" % status)
	print("Results: %s" % str(_results))
	for note: String in _notes:
		print("NOTE: %s" % note)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


class _FrameWaiter extends Node:
	signal done

	var frames: int = 1

	func _ready() -> void:
		_run()

	func _run() -> void:
		for _i: int in range(maxi(1, frames)):
			await get_tree().process_frame
		done.emit()
		queue_free()
