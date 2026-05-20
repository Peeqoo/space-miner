## Phase 6.6 / 6.6b: multi-slot save/load for core session state (no UI).
extends Node

const SAVE_VERSION := 1
const MAX_SAVE_SLOTS := 3

var active_save_slot: int = 1


func get_save_path(slot_index: int) -> String:
	if not is_valid_slot(slot_index):
		return ""
	return "user://saves/save_%03d.json" % slot_index


func is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 1 and slot_index <= MAX_SAVE_SLOTS


func set_active_save_slot(slot_index: int) -> void:
	if is_valid_slot(slot_index):
		active_save_slot = slot_index


func get_active_save_slot() -> int:
	return active_save_slot


func has_save(slot_index: int = -1) -> bool:
	var idx := active_save_slot if slot_index < 1 else slot_index
	if not is_valid_slot(idx):
		return false
	return FileAccess.file_exists(get_save_path(idx))


func get_save_metadata(slot_index: int) -> Dictionary:
	if not is_valid_slot(slot_index):
		return {}
	if not has_save(slot_index):
		return {}
	var data := _read_save_file(slot_index)
	if data.is_empty():
		return {}
	return _metadata_from_payload(data, slot_index)


func save_game(slot_index: int = -1) -> bool:
	var idx := active_save_slot if slot_index < 1 else slot_index
	if not is_valid_slot(idx):
		return false
	var payload := build_save_data(idx)
	return _write_save_file(payload, idx)


func load_game(slot_index: int = -1) -> bool:
	var idx := active_save_slot if slot_index < 1 else slot_index
	if not is_valid_slot(idx):
		return false
	var data := _read_save_file(idx)
	if data.is_empty():
		return false
	var file_slot := int(data.get("slot_index", idx))
	if is_valid_slot(file_slot):
		active_save_slot = file_slot
	elif idx >= 1:
		active_save_slot = idx
	return apply_save_data(data)


func delete_save(slot_index: int) -> bool:
	if not is_valid_slot(slot_index):
		return false
	var path := get_save_path(slot_index)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return false
	return not has_save(slot_index)


func build_save_data(slot_index: int = -1) -> Dictionary:
	var idx := active_save_slot if slot_index < 1 else slot_index
	if not is_valid_slot(idx):
		idx = 1
	var session_data: Dictionary = GameSession.to_save_data()
	return {
		"save_version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"slot_index": idx,
		"current_system_id": GameSession.current_system_id,
		"established_base_count": _established_base_count_from_session(session_data),
		"colony_ship_total": _colony_ship_total_from_session(session_data),
		"pending_colonization_count": _pending_colonization_count_from_session(session_data),
		"game_session": session_data,
	}


func apply_save_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var version := int(data.get("save_version", 0))
	if version != SAVE_VERSION:
		push_warning("SaveManager: unsupported save_version %d (expected %d)" % [version, SAVE_VERSION])
		return false
	var file_slot := int(data.get("slot_index", 0))
	if is_valid_slot(file_slot):
		active_save_slot = file_slot
	var session_variant: Variant = data.get("game_session", {})
	if not session_variant is Dictionary:
		return false
	return GameSession.apply_save_data(session_variant as Dictionary)


func _metadata_from_payload(data: Dictionary, slot_index: int) -> Dictionary:
	var gs_variant: Variant = data.get("game_session", {})
	var gs: Dictionary = gs_variant as Dictionary if gs_variant is Dictionary else {}
	return {
		"exists": true,
		"slot_index": int(data.get("slot_index", slot_index)),
		"saved_at_unix": int(data.get("saved_at_unix", 0)),
		"current_system_id": str(data.get("current_system_id", gs.get("current_system_id", ""))).strip_edges(),
		"established_base_count": int(
			data.get("established_base_count", _established_base_count_from_session(gs))
		),
		"colony_ship_total": int(data.get("colony_ship_total", _colony_ship_total_from_session(gs))),
		"pending_colonization_count": int(
			data.get("pending_colonization_count", _pending_colonization_count_from_session(gs))
		),
	}


func _established_base_count_from_session(session_data: Dictionary) -> int:
	var recs_variant: Variant = session_data.get("established_base_records", {})
	if not recs_variant is Dictionary:
		return 0
	var count := 0
	for _bid: Variant in (recs_variant as Dictionary).keys():
		var rec_variant: Variant = (recs_variant as Dictionary)[_bid]
		if rec_variant is Dictionary and bool((rec_variant as Dictionary).get("established", false)):
			count += 1
	return count


func _colony_ship_total_from_session(session_data: Dictionary) -> int:
	var bases_variant: Variant = session_data.get("bases", {})
	if not bases_variant is Dictionary:
		return 0
	var total := 0
	for base_variant: Variant in (bases_variant as Dictionary).values():
		if base_variant is Dictionary:
			total += int((base_variant as Dictionary).get("colony_ships", 0))
	return total


func _pending_colonization_count_from_session(session_data: Dictionary) -> int:
	var count := 0
	for op_variant: Variant in session_data.get("colonization_operations", []):
		if op_variant is Dictionary:
			if str((op_variant as Dictionary).get("status", "")).strip_edges() == "pending":
				count += 1
	return count


func _read_save_file(slot_index: int) -> Dictionary:
	var path := get_save_path(slot_index)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: could not open save for read (%s)" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_warning("SaveManager: invalid save JSON (%s)" % path)
		return {}
	return parsed as Dictionary


func _write_save_file(payload: Dictionary, slot_index: int) -> bool:
	var path := get_save_path(slot_index)
	if path.is_empty():
		return false
	_ensure_save_directory()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open save for write (%s)" % path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func _ensure_save_directory() -> void:
	var dir_path := get_save_path(1).get_base_dir()
	if dir_path.is_empty():
		return
	if DirAccess.dir_exists_absolute(dir_path):
		return
	DirAccess.make_dir_recursive_absolute(dir_path)
