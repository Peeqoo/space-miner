## Global game session facade.
## Keeps the public API stable and delegates state to stores.
extends Node

const DEFAULT_SYSTEM_PATH := "res://data/galaxy_systems/solar_system.tres"
const START_SYSTEM_ID: String = "solar-system"
## Default locked neighbour for Phase 6.1b (must match `SystemDefinition.id` on the map).
const PROXIMA_SYSTEM_ID: String = "proxima"

const SCAN_UNKNOWN := ObjectScanStore.SCAN_UNKNOWN
const SCAN_BASIC := ObjectScanStore.SCAN_BASIC
const SCAN_DEEP := ObjectScanStore.SCAN_DEEP
const SCAN_SPECIAL := ObjectScanStore.SCAN_SPECIAL

const DEFAULT_GAME_START_DEFINITION_PATH := "res://data/game_start/default_start.tres"
const DEFAULT_COLONIZATION_DEFINITION_PATH := "res://data/colonization/default_colonization.tres"
const DEFAULT_UPGRADE_EFFECT_TEXTS_PATH := "res://data/ui_text/upgrade_effect_texts.tres"
## Safety fallback only when `ColonizationDefinition` fails to load — not the primary data source.
const COLONIZATION_OPERATION_DURATION_MS_FALLBACK := 60000

const SCANNER_BASIC := ScannerStore.SCANNER_BASIC
const SCANNER_DEEP := ScannerStore.SCANNER_DEEP
const SCANNER_SPECIAL := ScannerStore.SCANNER_SPECIAL

var current_system_definition: SystemDefinition = null
var current_system_id: String = ""

var object_scans := ObjectScanStore.new()
var system_entry := SystemEntryStore.new()
var bases := BaseStore.new()
var automation := AutomationStore.new()

## Pending automation runtime from save; consumed when SystemScene hydrates AutomationController.
var _automation_runtime_pending: Dictionary = {}

## Pending system camera state from save; consumed when SystemScene finishes setup.
var _camera_state_pending: Dictionary = {}

var scanner := ScannerStore.new()

## Phase 5.5: data-driven upgrade tiers (`data/upgrades/*.tres`).
var upgrade_catalog: UpgradeCatalog = null
## Data-driven production build costs (`data/production/*.tres`).
var production_catalog: ProductionCatalog = null
## Data-driven colonization operation balancing (`data/colonization/*.tres`).
var colonization_definition: ColonizationDefinition = null
## Data-driven new-game start (`data/game_start/*.tres`). Not applied on Continue/Load.
var game_start_definition: GameStartDefinition = null

## Phase 6.1b: session-only galaxy progression (no savegame).
var discovered_system_ids: Array[String] = []
var unlocked_system_ids: Array[String] = []
var _galaxy_progression_seeded: bool = false
var _system_definition_by_id: Dictionary = {}

## Phase 6.3e: bases that truly exist (`BaseStore.get_base` auto-inserts placeholders — NOT established).
## Mirrors keys in `_established_base_records` for quick membership checks / compatibility.
var _established_base_ids: Dictionary = {}

## Phase 6.4: `base_id` -> record. Geography for colony bases (`system_id`, `body_id`).
## Later, `base_id` may diverge from `body_id` (e.g. named settlement id); callers should use accessors.
var _established_base_records: Dictionary = {}

## Phase 6.4c: colonization ops (pending → complete/cancel). No travel visuals or timers.
var _colonization_operations: Dictionary = {}
var _next_colonization_operation_id: int = 1

signal object_remaining_resources_changed(system_id: String, object_id: String)
signal base_resources_changed(base_id: String)
signal base_upgrades_changed(base_id: String)
## Emitted when `discovered_system_ids` or `unlocked_system_ids` change (not during initial seed).
signal galaxy_progression_changed()


# --------------------------------------------------
# Lifecycle
# --------------------------------------------------

func _ready() -> void:
	upgrade_catalog = UpgradeCatalog.new()
	upgrade_catalog.load_all()
	bases.set_upgrade_catalog(upgrade_catalog)

	production_catalog = ProductionCatalog.new()
	production_catalog.load_all()
	bases.set_production_catalog(production_catalog)

	_load_colonization_definition()
	_load_game_start_definition()
	_load_upgrade_effect_texts()

	mark_base_established(BaseStore.BASE_EARTH)
	ensure_default_system_loaded()


# --------------------------------------------------
# Boot State
# --------------------------------------------------

func ensure_boot_state() -> void:
	ensure_default_system_loaded()
	ensure_galaxy_progression_boot()

	if not has_established_base(BaseStore.BASE_EARTH):
		mark_base_established(BaseStore.BASE_EARTH)

	if current_system_id.is_empty():
		current_system_id = START_SYSTEM_ID


# --------------------------------------------------
# Current System
# --------------------------------------------------

func ensure_default_system_loaded() -> void:
	if current_system_definition != null:
		return

	var default_system := load(DEFAULT_SYSTEM_PATH) as SystemDefinition

	if default_system == null:
		push_error("Default-System konnte nicht geladen werden: %s" % DEFAULT_SYSTEM_PATH)
		return

	set_current_system(default_system)


func set_current_system(system_definition: SystemDefinition) -> void:
	if system_definition == null:
		return

	current_system_definition = system_definition
	current_system_id = system_definition.id


# --------------------------------------------------
# Galaxy progression (Phase 6.1b)
# --------------------------------------------------

func ensure_galaxy_progression_boot() -> void:
	if _galaxy_progression_seeded:
		return
	_galaxy_progression_seeded = true
	_seed_default_galaxy_progression()


func _load_game_start_definition() -> void:
	var res: Resource = load(DEFAULT_GAME_START_DEFINITION_PATH)
	if res is GameStartDefinition:
		game_start_definition = res as GameStartDefinition
		return
	push_warning(
		"GameSession: failed to load GameStartDefinition from %s"
		% DEFAULT_GAME_START_DEFINITION_PATH
	)
	game_start_definition = null


func _get_game_start_definition() -> GameStartDefinition:
	if game_start_definition == null:
		_load_game_start_definition()
	return game_start_definition


func _get_preferred_colonization_source_base_id() -> String:
	var def := _get_game_start_definition()
	if def != null:
		var pid := def.preferred_colonization_source_base_id.strip_edges()
		if not pid.is_empty():
			return pid
	return BaseStore.BASE_EARTH


func _apply_galaxy_progression_from_game_start(def: GameStartDefinition) -> void:
	discovered_system_ids.clear()
	unlocked_system_ids.clear()
	if def == null:
		push_warning("GameSession: using fallback galaxy progression seed (GameStartDefinition missing)")
		discovered_system_ids.append(START_SYSTEM_ID)
		unlocked_system_ids.append(START_SYSTEM_ID)
		discovered_system_ids.append(PROXIMA_SYSTEM_ID)
		return
	for sid_var: Variant in def.discovered_system_ids:
		var sid := str(sid_var).strip_edges()
		if sid.is_empty() or discovered_system_ids.has(sid):
			continue
		discovered_system_ids.append(sid)
	for uid_var: Variant in def.unlocked_system_ids:
		var uid := str(uid_var).strip_edges()
		if uid.is_empty() or unlocked_system_ids.has(uid):
			continue
		unlocked_system_ids.append(uid)


func _seed_default_galaxy_progression() -> void:
	_apply_galaxy_progression_from_game_start(_get_game_start_definition())


func is_system_discovered(system_id: String) -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return false
	return discovered_system_ids.has(sid)


func discover_system(system_id: String) -> void:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return
	if discovered_system_ids.has(sid):
		return
	discovered_system_ids.append(sid)
	galaxy_progression_changed.emit()


func unlock_system(system_id: String) -> void:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return
	var changed: bool = false
	if not discovered_system_ids.has(sid):
		discovered_system_ids.append(sid)
		changed = true
	if not unlocked_system_ids.has(sid):
		unlocked_system_ids.append(sid)
		changed = true
	if changed:
		galaxy_progression_changed.emit()


## Galaxy map / system entry: whether the player may open this system view.
func can_enter_system(system_id: String) -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return false
	if sid == START_SYSTEM_ID:
		return true
	if has_established_base_in_system(sid):
		return true
	if has_pending_colonization_to_system(sid):
		return true

	var source_base_id := get_colonization_source_base_id()
	if source_base_id.is_empty():
		return false

	return get_base_colony_ship_count(source_base_id) > 0


# --------------------------------------------------
# System Entry
# --------------------------------------------------

func stage_system_entry(system_definition: SystemDefinition, from_travel: bool) -> void:
	system_entry.stage_system_entry(system_definition, from_travel)


func consume_selected_system_definition() -> SystemDefinition:
	return system_entry.consume_selected_system_definition()


func consume_travel_entry_flag() -> bool:
	return system_entry.consume_travel_entry_flag()


func can_leave_current_system() -> bool:
	return true


# --------------------------------------------------
# Established bases (Phase 6.3e–6.4)
# --------------------------------------------------

func mark_base_established_at(base_id: String, system_id: String, body_id: String) -> void:
	var bid := base_id.strip_edges()
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()
	if bid.is_empty():
		push_warning("GameSession.mark_base_established_at: empty base_id ignored")
		return
	if sid.is_empty() or bod.is_empty():
		push_warning(
			"GameSession.mark_base_established_at: empty system_id or body_id ignored (base_id=%s)"
			% bid
		)
		return
	_apply_established_base_record(bid, sid, bod)


func mark_base_established(base_id: String) -> void:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		push_warning("GameSession.mark_base_established: empty base_id ignored")
		return

	if bid == BaseStore.BASE_EARTH:
		mark_base_established_at(bid, START_SYSTEM_ID, BaseStore.BASE_EARTH)
		return

	var cur_sys_id := current_system_id.strip_edges()
	if current_system_definition != null and cur_sys_id != "":
		var start_body_in_def: String = current_system_definition.start_body_id.strip_edges()
		if start_body_in_def == bid:
			mark_base_established_at(bid, cur_sys_id, bid)
			return

	push_warning(
		(
			"GameSession.mark_base_established('%s'): could not derive system/body mapping; "
			+ "use mark_base_established_at(base_id, system_id, body_id)."
		)
		% bid
	)


func get_established_base_record(base_id: String) -> Dictionary:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return {}
	var rec_variant: Variant = _established_base_records.get(bid, null)
	if rec_variant == null:
		return {}
	if rec_variant is Dictionary:
		var rec_dict: Dictionary = rec_variant as Dictionary
		return rec_dict.duplicate(true)
	return {}


func get_established_base_body_id(base_id: String) -> String:
	var rec := get_established_base_record(base_id)
	return str(rec.get("body_id", "")).strip_edges()


func get_established_base_system_id(base_id: String) -> String:
	var rec := get_established_base_record(base_id)
	return str(rec.get("system_id", "")).strip_edges()


## Colony foundation (Phase 6.4): no ColonyShip-, travel-, or habitability checks yet.
## Returns true only when a *new* base was established (`base_id` == `body_id` for now — may diverge later).
func establish_base_at_body(system_id: String, body_id: String) -> bool:
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()

	if sid.is_empty():
		push_warning("GameSession.establish_base_at_body: empty system_id")
		return false
	if bod.is_empty():
		push_warning("GameSession.establish_base_at_body: empty body_id")
		return false

	## Colony placeholder: canonical BaseStore slot id mirrors body until dedicated settlement ids exist.
	var base_id := bod
	if has_established_base(base_id):
		return false

	bases.get_base(base_id)
	mark_base_established_at(base_id, sid, bod)
	return true


# --------------------------------------------------
# Colonization operations (Phase 6.4c)
# --------------------------------------------------


func _load_colonization_definition() -> void:
	var res: Resource = load(DEFAULT_COLONIZATION_DEFINITION_PATH)
	if res is ColonizationDefinition:
		colonization_definition = res as ColonizationDefinition
		return
	push_warning(
		"GameSession: failed to load ColonizationDefinition from %s"
		% DEFAULT_COLONIZATION_DEFINITION_PATH
	)
	colonization_definition = null


func _load_upgrade_effect_texts() -> void:
	var res: Resource = load(DEFAULT_UPGRADE_EFFECT_TEXTS_PATH)
	if res is UpgradeEffectTextDefinition:
		UpgradeDefinition.set_effect_texts(res as UpgradeEffectTextDefinition)
		return
	push_warning(
		"GameSession: failed to load UpgradeEffectTextDefinition from %s"
		% DEFAULT_UPGRADE_EFFECT_TEXTS_PATH
	)
	UpgradeDefinition.set_effect_texts(null)


func get_colonization_operation_duration_ms() -> int:
	if colonization_definition != null and colonization_definition.operation_duration_ms > 0:
		return colonization_definition.operation_duration_ms
	push_warning("GameSession: using fallback colonization operation duration (definition missing or invalid)")
	return COLONIZATION_OPERATION_DURATION_MS_FALLBACK


func start_colonization_operation(source_base_id: String, target_system_id: String, target_body_id: String) -> String:
	var src := source_base_id.strip_edges()
	var tsid := target_system_id.strip_edges()
	var tbod := target_body_id.strip_edges()

	if src.is_empty() or tsid.is_empty() or tbod.is_empty():
		push_warning("GameSession.start_colonization_operation: empty source or target id")
		return ""

	if not has_established_base(src):
		push_warning("GameSession.start_colonization_operation: source base not established (%s)" % src)
		return ""

	if has_established_base_in_system(tsid):
		push_warning("GameSession.start_colonization_operation: target system already has an established base (%s)" % tsid)
		return ""

	if has_established_base(tbod):
		push_warning("GameSession.start_colonization_operation: target body already established (%s)" % tbod)
		return ""

	if has_pending_colonization_to_system(tsid):
		push_warning("GameSession.start_colonization_operation: pending operation already targets system %s" % tsid)
		return ""

	if bases.get_colony_ship_count(src) < 1:
		return ""

	if not bases.consume_colony_ships(src, 1):
		return ""

	var op_id := _allocate_colonization_operation_id()
	var created_tick: int = Time.get_ticks_msec()
	var duration_ms: int = get_colonization_operation_duration_ms()
	var rec: Dictionary = {
		"operation_id": op_id,
		"source_base_id": src,
		"target_system_id": tsid,
		"target_body_id": tbod,
		"status": "pending",
		"reserved_colony_ships": 1,
		"created_at_tick": created_tick,
		"completed_at_tick": -1,
		"duration_ms": duration_ms,
		"arrival_at_tick": created_tick + duration_ms,
	}
	_colonization_operations[op_id] = rec
	base_resources_changed.emit(src)
	return op_id


func complete_colonization_operation(operation_id: String) -> bool:
	var oid := operation_id.strip_edges()
	if oid.is_empty() or not _colonization_operations.has(oid):
		return false

	var rec_variant: Variant = _colonization_operations[oid]
	if rec_variant == null or not rec_variant is Dictionary:
		return false
	var rec: Dictionary = (rec_variant as Dictionary).duplicate(true)

	if str(rec.get("status", "")).strip_edges() != "pending":
		return false

	var src: String = str(rec.get("source_base_id", "")).strip_edges()
	var tsid: String = str(rec.get("target_system_id", "")).strip_edges()
	var tbod: String = str(rec.get("target_body_id", "")).strip_edges()
	var ships_reserved: int = maxi(1, int(rec.get("reserved_colony_ships", 1)))

	if not establish_base_at_body(tsid, tbod):
		rec["status"] = "failed"
		rec["completed_at_tick"] = Time.get_ticks_msec()
		bases.add_colony_ship(src, ships_reserved)
		_colonization_operations[oid] = rec
		base_resources_changed.emit(src)
		return false

	rec["status"] = "completed"
	rec["completed_at_tick"] = Time.get_ticks_msec()
	_colonization_operations[oid] = rec
	base_resources_changed.emit(tbod)
	return true


func cancel_colonization_operation(operation_id: String) -> bool:
	var oid := operation_id.strip_edges()
	if oid.is_empty() or not _colonization_operations.has(oid):
		return false

	var rec_variant: Variant = _colonization_operations[oid]
	if rec_variant == null or not rec_variant is Dictionary:
		return false
	var rec: Dictionary = (rec_variant as Dictionary).duplicate(true)

	if str(rec.get("status", "")).strip_edges() != "pending":
		return false

	var src: String = str(rec.get("source_base_id", "")).strip_edges()
	var reserved: int = maxi(1, int(rec.get("reserved_colony_ships", 1)))

	rec["status"] = "cancelled"
	rec["completed_at_tick"] = Time.get_ticks_msec()
	bases.add_colony_ship(src, reserved)
	_colonization_operations[oid] = rec
	base_resources_changed.emit(src)
	return true


func get_colonization_operation(operation_id: String) -> Dictionary:
	var oid := operation_id.strip_edges()
	if oid.is_empty() or not _colonization_operations.has(oid):
		return {}
	var rec_variant: Variant = _colonization_operations[oid]
	if rec_variant != null and rec_variant is Dictionary:
		return (rec_variant as Dictionary).duplicate(true)
	return {}


func get_colonization_operations() -> Array:
	var out: Array = []
	var ks: Array = _colonization_operations.keys()
	ks.sort()
	for k: Variant in ks:
		var rec_variant: Variant = _colonization_operations[k]
		if rec_variant != null and rec_variant is Dictionary:
			out.append((rec_variant as Dictionary).duplicate(true))
	return out


func get_pending_colonization_operations() -> Array:
	var out: Array = []
	for rec_variant: Variant in _colonization_operations.values():
		if rec_variant == null or not rec_variant is Dictionary:
			continue
		var d: Dictionary = rec_variant as Dictionary
		if str(d.get("status", "")).strip_edges() == "pending":
			out.append(d.duplicate(true))
	return out


func has_pending_colonization_to_system(system_id: String) -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return false
	for rec_variant: Variant in _colonization_operations.values():
		if rec_variant == null or not rec_variant is Dictionary:
			continue
		var d: Dictionary = rec_variant as Dictionary
		if str(d.get("status", "")).strip_edges() != "pending":
			continue
		if str(d.get("target_system_id", "")).strip_edges() == sid:
			return true
	return false


func get_pending_colonization_operation_for_system(system_id: String) -> Dictionary:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return {}

	for rec_variant: Variant in _colonization_operations.values():
		if rec_variant == null or not rec_variant is Dictionary:
			continue
		var d: Dictionary = rec_variant as Dictionary
		if str(d.get("status", "")).strip_edges() != "pending":
			continue
		if str(d.get("target_system_id", "")).strip_edges() == sid:
			return d.duplicate(true)

	return {}


func get_colonization_operation_remaining_ms(operation_id: String) -> int:
	var rec := get_colonization_operation(operation_id)
	if rec.is_empty():
		return 0
	if str(rec.get("status", "")).strip_edges() != "pending":
		return 0
	var arrival: int = int(rec.get("arrival_at_tick", 0))
	if arrival <= 0:
		return 0
	return maxi(0, arrival - Time.get_ticks_msec())


func get_colonization_operation_status_view(operation_id: String) -> Dictionary:
	var rec := get_colonization_operation(operation_id)
	if rec.is_empty():
		return {}

	var status := str(rec.get("status", "")).strip_edges()
	if status != "pending":
		return {"status_key": status}

	var remaining_ms: int = get_colonization_operation_remaining_ms(operation_id)
	if remaining_ms <= 0:
		return {"status_key": "ready", "remaining_sec": 0}

	var sec: int = int(ceil(float(remaining_ms) / 1000.0))
	return {"status_key": "pending", "remaining_sec": sec}


func get_colonization_source_base_id() -> String:
	var candidates: Array[String] = []

	for bid_var: Variant in _established_base_records.keys():
		var bid: String = str(bid_var).strip_edges()
		if bid.is_empty():
			continue
		if not has_established_base(bid):
			continue
		if bases.get_colony_ship_count(bid) < 1:
			continue
		candidates.append(bid)

	if candidates.is_empty():
		return ""

	var preferred_id: String = _get_preferred_colonization_source_base_id()
	for c in candidates:
		var cid: String = str(c).strip_edges()
		if cid == preferred_id:
			return preferred_id

	candidates.sort()
	return candidates[0]


func _allocate_colonization_operation_id() -> String:
	var id_str: String = "colony_%d" % _next_colonization_operation_id
	_next_colonization_operation_id += 1
	return id_str


func has_established_base(base_id: String) -> bool:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return false
	var rec_variant: Variant = _established_base_records.get(bid, null)
	if rec_variant != null and rec_variant is Dictionary:
		return bool((rec_variant as Dictionary).get("established", false))
	return bool(_established_base_ids.get(bid, false))


func has_established_base_in_system(system_id: String) -> bool:
	return not get_established_base_id_for_system(system_id.strip_edges()).is_empty()


func get_established_base_id_for_system(system_id: String) -> String:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return ""

	for bid_var: Variant in _established_base_records.keys():
		var bid: String = str(bid_var).strip_edges()
		if bid.is_empty():
			continue
		var rec_variant: Variant = _established_base_records[bid_var]
		if rec_variant == null or not rec_variant is Dictionary:
			continue
		var rec_dict: Dictionary = rec_variant as Dictionary
		if not bool(rec_dict.get("established", false)):
			continue
		var rec_sid: String = str(rec_dict.get("system_id", "")).strip_edges()
		if rec_sid == sid:
			# TODO(multi-base-per-system): deterministic selection when >1 bases share a system_id.
			return bid

	return ""


func _apply_established_base_record(base_id: String, system_id: String, body_id: String) -> void:
	_established_base_ids[base_id] = true

	## Design note: Today `body_id` is the celestial id; tomorrow `base_id` may encode a colony key.
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()
	var rec: Dictionary = {
		"base_id": base_id,
		"system_id": sid,
		"body_id": bod,
		"established": true,
	}
	_established_base_records[base_id] = rec
	ensure_basic_intel_for_established_base(sid, bod)


func _has_established_base_at_body(system_id: String, body_id: String) -> bool:
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()
	if sid.is_empty() or bod.is_empty():
		return false

	for bid_var: Variant in _established_base_records.keys():
		var bid := str(bid_var).strip_edges()
		if bid.is_empty():
			continue
		var rec := get_established_base_record(bid)
		if rec.is_empty():
			continue
		if not bool(rec.get("established", false)):
			continue
		if str(rec.get("system_id", "")).strip_edges() != sid:
			continue
		if str(rec.get("body_id", "")).strip_edges() != bod:
			continue
		return true

	return false


## Established bases grant BASIC scan intel for that body only (no resources, no Deep/Special).
func ensure_basic_intel_for_established_base(system_id: String, body_id: String) -> void:
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()
	if sid.is_empty() or bod.is_empty():
		return
	if not _has_established_base_at_body(sid, bod):
		return

	var current: String = get_object_scan_state(sid, bod)
	if scan_state_rank(current) < scan_state_rank(SCAN_BASIC):
		set_object_scan_state(sid, bod, SCAN_BASIC)

	_ensure_object_resources_for_scan_state(sid, bod)


func _load_body_definition_for_system(system_id: String, body_id: String) -> Resource:
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()
	if sid.is_empty() or bod.is_empty():
		return null

	var system_def := get_system_definition_by_id(sid)
	if system_def == null:
		return null

	for body_variant: Variant in system_def.bodies:
		var body_def := body_variant as SystemBodyDefinition
		if body_def != null and body_def.id == bod:
			return body_def

	return null


func _collect_body_scan_entries_for_scan_state(body_def: Resource, scan_state: String) -> Array:
	var result: Array = []
	if body_def == null or not body_def.has_method(&"get_basic_scan_resources"):
		return result

	var rank: int = scan_state_rank(scan_state)
	if rank < scan_state_rank(SCAN_BASIC):
		return result

	for entry: Variant in body_def.call(&"get_basic_scan_resources"):
		if entry != null:
			result.append(entry)

	if rank >= scan_state_rank(SCAN_DEEP):
		for entry_deep: Variant in body_def.call(&"get_deep_scan_resources"):
			if entry_deep != null:
				result.append(entry_deep)

	if rank >= scan_state_rank(SCAN_SPECIAL):
		for entry_special: Variant in body_def.call(&"get_special_scan_resources"):
			if entry_special != null:
				result.append(entry_special)

	return result


## Initializes deposit remaining amounts for visible scan layers (no base storage grant).
func _ensure_object_resources_for_scan_state(system_id: String, body_id: String) -> void:
	var sid := system_id.strip_edges()
	var bod := body_id.strip_edges()
	if sid.is_empty() or bod.is_empty():
		return

	if get_object_scan_state(sid, bod) == SCAN_UNKNOWN:
		return

	var body_def := _load_body_definition_for_system(sid, bod)
	if body_def == null:
		return

	var entries: Array = _collect_body_scan_entries_for_scan_state(
		body_def,
		get_object_scan_state(sid, bod)
	)
	if entries.is_empty():
		return

	ensure_object_resources_initialized(sid, bod, entries)


func _sync_basic_intel_from_all_established_bases() -> void:
	for bid_var: Variant in _established_base_records.keys():
		var bid := str(bid_var).strip_edges()
		if bid.is_empty():
			continue
		var rec := get_established_base_record(bid)
		if rec.is_empty():
			push_warning(
				"GameSession._sync_basic_intel_from_all_established_bases: invalid record (base_id=%s)"
				% bid
			)
			continue
		if not bool(rec.get("established", false)):
			continue
		var sid := str(rec.get("system_id", "")).strip_edges()
		var bod := str(rec.get("body_id", "")).strip_edges()
		if sid.is_empty() or bod.is_empty():
			push_warning(
				(
					"GameSession._sync_basic_intel_from_all_established_bases: "
					+ "missing system_id/body_id (base_id=%s)"
				)
				% bid
			)
			continue
		ensure_basic_intel_for_established_base(sid, bod)


# --------------------------------------------------
# Object Scan State
# --------------------------------------------------

func set_object_scan_state(system_id: String, object_id: String, scan_state: String) -> void:
	object_scans.set_object_scan_state(system_id, object_id, scan_state)

func ensure_object_resources_initialized(system_id: String, object_id: String, visible_resources: Array) -> void:
	object_scans.ensure_object_resources_initialized(system_id, object_id, visible_resources)


func has_remaining_resources_among(system_id: String, object_id: String, resource_ids: Array) -> bool:
	return object_scans.has_any_remaining_among(system_id, object_id, resource_ids)


func has_object_resources(system_id: String, object_id: String) -> bool:
	return object_scans.has_object_resources(system_id, object_id)


func get_object_remaining_resources(system_id: String, object_id: String) -> Dictionary:
	return object_scans.get_object_remaining_resources(system_id, object_id)


func get_remaining_resource_amount(system_id: String, object_id: String, resource_id: String) -> int:
	return object_scans.get_remaining_resource_amount(system_id, object_id, resource_id)


func extract_resource_amount(system_id: String, object_id: String, resource_id: String, requested_amount: int) -> int:
	var extracted: int = object_scans.extract_resource_amount(
		system_id,
		object_id,
		resource_id,
		requested_amount
	)
	if extracted > 0:
		object_remaining_resources_changed.emit(system_id, object_id)
	return extracted


func is_resource_depleted(system_id: String, object_id: String, resource_id: String) -> bool:
	return object_scans.is_resource_depleted(system_id, object_id, resource_id)


func is_object_depleted(system_id: String, object_id: String) -> bool:
	return object_scans.is_object_depleted(system_id, object_id)
	

func get_object_scan_state(system_id: String, object_id: String) -> String:
	return object_scans.get_object_scan_state(system_id, object_id)


func scan_state_rank(scan_state: String) -> int:
	match scan_state:
		SCAN_BASIC:
			return 1
		SCAN_DEEP:
			return 2
		SCAN_SPECIAL:
			return 3
		_:
			return 0


# --------------------------------------------------
# Scanner API
# --------------------------------------------------

func get_active_scanner_tier() -> String:
	return scanner.get_active_tier()


func get_scanner_tier_for_base(base_id: String) -> String:
	var layer := get_unlocked_scan_layer_for_base(base_id)
	match layer:
		ScannedResourceEntry.Layer.DEEP:
			return SCANNER_DEEP
		ScannedResourceEntry.Layer.SPECIAL:
			return SCANNER_SPECIAL
		_:
			return SCANNER_BASIC


# --------------------------------------------------
# Base API
# --------------------------------------------------

func get_base_resource_amount(base_id: String, resource_id: String) -> int:
	return bases.get_resource_amount(base_id, resource_id)


func get_base_resources(base_id: String) -> Dictionary:
	return bases.get_resources(base_id)


func add_base_resource(base_id: String, resource_id: String, amount: int) -> int:
	var added: int = bases.add_resource(base_id, resource_id, amount)

	if added > 0:
		base_resources_changed.emit(base_id)

	return added


func spend_base_resource(base_id: String, resource_id: String, amount: int) -> bool:
	var spent_ok: bool = bases.spend_resource(base_id, resource_id, amount)
	if spent_ok:
		base_resources_changed.emit(base_id)
	return spent_ok


func remove_base_resource(base_id: String, resource_id: String, amount: int) -> int:
	var removed: int = bases.remove_resource(base_id, resource_id, amount)

	if removed > 0:
		base_resources_changed.emit(base_id)

	return removed


func discard_base_resource(base_id: String, resource_id: String, amount: int) -> int:
	return remove_base_resource(base_id, resource_id, amount)


func get_base_population(base_id: String) -> int:
	return bases.get_population(base_id)


func get_base_drone_count(base_id: String) -> int:
	return bases.get_drone_count(base_id)


func get_base_mining_ship_count(base_id: String) -> int:
	return bases.get_mining_ship_count(base_id)


func get_base_colony_ship_count(base_id: String) -> int:
	return bases.get_colony_ship_count(base_id)


func build_base_drone(base_id: String) -> bool:
	if not bases.build_drone(base_id):
		return false

	base_resources_changed.emit(base_id)
	return true


func build_base_mining_ship(base_id: String) -> bool:
	if not bases.build_mining_ship(base_id):
		return false

	base_resources_changed.emit(base_id)
	return true


func build_base_colony_ship(base_id: String) -> bool:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		push_warning("GameSession: cannot build ColonyShip without base_id.")
		return false
	if not has_established_base(bid):
		push_warning("GameSession: cannot build ColonyShip for non-established base_id=%s." % bid)
		return false
	if not bases.build_colony_ship(bid):
		return false

	base_resources_changed.emit(bid)
	return true


func get_base_storage_used(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_storage_used(base_id)


func get_base_storage_capacity(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_storage_capacity(base_id)


func get_base_storage_free(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_storage_free(base_id)


func get_base_upgrade_level(base_id: String, category: StringName) -> int:
	return bases.get_upgrade_level(base_id, category)


func get_current_upgrade_definition(base_id: String, category: StringName) -> UpgradeDefinition:
	if upgrade_catalog == null:
		return null
	return upgrade_catalog.get_current_definition(category, bases.get_upgrade_level(base_id, category))


func get_next_upgrade_definition(base_id: String, category: StringName) -> UpgradeDefinition:
	if upgrade_catalog == null:
		return null
	return upgrade_catalog.get_next_definition(category, bases.get_upgrade_level(base_id, category))


func has_next_base_upgrade(base_id: String, category: StringName) -> bool:
	if upgrade_catalog == null:
		return false
	return upgrade_catalog.has_next_level(category, bases.get_upgrade_level(base_id, category))


func can_buy_next_base_upgrade(base_id: String, category: StringName) -> bool:
	var nxt := get_next_upgrade_definition(base_id, category)
	if nxt == null:
		return false
	return bases.can_afford_upgrade(base_id, nxt)


func buy_next_base_upgrade(base_id: String, category: StringName) -> bool:
	var nxt := get_next_upgrade_definition(base_id, category)
	if nxt == null:
		return false
	if not bases.buy_next_upgrade(base_id, nxt):
		return false
	base_resources_changed.emit(base_id)
	base_upgrades_changed.emit(base_id)
	return true


func get_unlocked_scan_layer_for_base(base_id: String) -> int:
	return bases.get_unlocked_scan_layer(base_id)


func get_unlocked_mining_layer_for_base(base_id: String) -> int:
	return bases.get_unlocked_mining_layer(base_id)


func resource_tier_string_to_layer_int(resource_tier: String) -> int:
	match resource_tier:
		SCANNER_DEEP:
			return ScannedResourceEntry.Layer.DEEP
		SCANNER_SPECIAL:
			return ScannedResourceEntry.Layer.SPECIAL
		_:
			return ScannedResourceEntry.Layer.BASIC


func scan_completion_state_for_unlocked_scan_layer(unlocked_scan_layer: int) -> String:
	if unlocked_scan_layer >= ScannedResourceEntry.Layer.DEEP:
		return SCAN_DEEP
	return SCAN_BASIC


func get_base_storage_capacity_percent(base_id: String = BaseStore.BASE_EARTH) -> int:
	var units0 := bases.get_storage_capacity_level_zero_units()
	var cur := get_base_storage_capacity(base_id)
	return int(round(float(cur) / float(maxi(1, units0)) * 100.0))


func get_scan_drone_scan_speed_percent(base_id: String = BaseStore.BASE_EARTH) -> int:
	var def := get_current_upgrade_definition(base_id, &"scan_drone")
	if def != null and def.scan_speed_percent >= 0:
		return def.scan_speed_percent
	return 100 + int(round((1.0 - get_scan_drone_scan_duration_multiplier(base_id)) * 100.0))


func get_scan_drone_mining_yield_bonus_per_support_drone_percent(base_id: String = BaseStore.BASE_EARTH) -> int:
	var def := get_current_upgrade_definition(base_id, &"scan_drone")
	if def != null and def.mining_yield_bonus_per_support_drone_percent >= 0:
		return def.mining_yield_bonus_per_support_drone_percent
	return 2


func get_mining_ship_cargo_capacity_percent(base_id: String = BaseStore.BASE_EARTH) -> int:
	var def := get_current_upgrade_definition(base_id, &"mining_ship")
	if def != null and def.cargo_capacity_percent >= 0:
		return def.cargo_capacity_percent
	return int(round(get_mining_ship_cargo_capacity_multiplier(base_id) * 100.0))


func get_scan_drone_scan_duration_multiplier(base_id: String = BaseStore.BASE_EARTH) -> float:
	return clampf(bases.get_scan_drone_scan_duration_multiplier(base_id), 0.05, 10.0)


func get_mining_ship_cargo_capacity_multiplier(base_id: String = BaseStore.BASE_EARTH) -> float:
	return clampf(bases.get_mining_ship_cargo_capacity_multiplier(base_id), 1.0, 4.0)


func can_build_base_drone(base_id: String) -> bool:
	return bases.can_build_drone(base_id)


func can_build_base_mining_ship(base_id: String) -> bool:
	return bases.can_build_mining_ship(base_id)


func can_build_base_colony_ship(base_id: String) -> bool:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return false
	if not has_established_base(bid):
		return false
	return bases.can_build_colony_ship(bid)


func get_production_cost(production_id: String) -> Dictionary:
	return bases.get_production_cost(production_id)


func get_production_definition(production_id: String) -> ProductionDefinition:
	return bases.get_production_definition(production_id)


# --------------------------------------------------
# Automation API
# --------------------------------------------------

func create_scan_mission(base_id: String, target_id: String) -> int:
	return automation.create_scan_mission(base_id, target_id)


func create_mining_mission(base_id: String, target_id: String) -> int:
	return automation.create_mining_mission(base_id, target_id)


func get_automation_mission(mission_id: int) -> Dictionary:
	return automation.get_mission(mission_id)


func complete_automation_mission(mission_id: int) -> Dictionary:
	return automation.complete_mission(mission_id)


# --------------------------------------------------
# Save / Load / New Game (Phase 6.6)
# --------------------------------------------------


func reset_for_new_game() -> void:
	var def := _get_game_start_definition()

	var primary_base_id: String = BaseStore.BASE_EARTH
	var start_system_id: String = START_SYSTEM_ID
	if def != null:
		primary_base_id = def.primary_base_body_id.strip_edges()
		if primary_base_id.is_empty():
			primary_base_id = BaseStore.BASE_EARTH
		start_system_id = def.start_system_id.strip_edges()
		if start_system_id.is_empty():
			start_system_id = START_SYSTEM_ID
	else:
		push_warning("GameSession.reset_for_new_game: using fallback start ids (GameStartDefinition missing)")

	_colonization_operations.clear()
	_next_colonization_operation_id = 1
	_established_base_ids.clear()
	_established_base_records.clear()

	var start_resources: Dictionary = {}
	var start_population: int = 1
	var start_drones: int = 1
	var start_mining_ships: int = 1
	var start_colony_ships: int = 0
	if def != null:
		start_resources = def.start_resources.duplicate(true)
		start_population = def.start_population
		start_drones = def.start_drones
		start_mining_ships = def.start_mining_ships
		start_colony_ships = def.start_colony_ships

	bases.bases = {
		primary_base_id: bases.create_new_game_base_entry(
			start_population,
			start_drones,
			start_mining_ships,
			start_colony_ships,
			start_resources,
		),
	}

	object_scans.object_scan_states = {}
	object_scans.remaining_resources_by_object = {}

	automation.missions.clear()
	automation.next_mission_id = 1
	_automation_runtime_pending.clear()

	_galaxy_progression_seeded = true
	_apply_galaxy_progression_from_game_start(def)

	mark_base_established_at(primary_base_id, start_system_id, primary_base_id)

	current_system_definition = null
	current_system_id = start_system_id
	ensure_default_system_loaded()

	base_resources_changed.emit(primary_base_id)
	galaxy_progression_changed.emit()


func refresh_automation_snapshot_from_scene() -> void:
	_automation_runtime_pending = _capture_live_automation_runtime_snapshot()


func refresh_camera_snapshot_from_scene() -> void:
	_camera_state_pending = _capture_live_camera_snapshot()


func take_camera_state_pending() -> Dictionary:
	var pending := _camera_state_pending.duplicate(true)
	_camera_state_pending.clear()
	return pending


func has_camera_state_pending_for_system(system_id: String) -> bool:
	if _camera_state_pending.is_empty():
		return false

	var saved_sid: String = str(_camera_state_pending.get("system_id", "")).strip_edges()
	var want_sid: String = system_id.strip_edges()

	if saved_sid.is_empty() or want_sid.is_empty():
		return false

	return saved_sid == want_sid


func take_automation_runtime_pending() -> Dictionary:
	var pending := _automation_runtime_pending.duplicate(true)
	_automation_runtime_pending.clear()
	return pending


func has_automation_runtime_pending() -> bool:
	return not _automation_runtime_pending.is_empty()


func _capture_live_automation_runtime_snapshot() -> Dictionary:
	var controller := _find_automation_controller_in_tree()
	if controller != null and controller.has_method("to_save_data"):
		var live_variant: Variant = controller.call("to_save_data")
		if live_variant is Dictionary:
			return (live_variant as Dictionary).duplicate(true)

	return _automation_runtime_pending.duplicate(true)


func _build_automation_save_payload() -> Dictionary:
	return {
		"store": automation.to_save_data(),
		"runtime": _capture_live_automation_runtime_snapshot(),
	}


func _find_automation_controller_in_tree() -> Node:
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return null
	return _find_automation_controller_recursive(root)


func _find_automation_controller_recursive(node: Node) -> Node:
	if node is AutomationController:
		return node
	for child: Node in node.get_children():
		var found := _find_automation_controller_recursive(child)
		if found != null:
			return found
	return null


func _capture_live_camera_snapshot() -> Dictionary:
	var camera := _find_system_camera_controller_in_tree()

	if camera != null and camera.has_method("to_save_state"):
		var live_variant: Variant = camera.call("to_save_state")

		if live_variant is Dictionary:
			return (live_variant as Dictionary).duplicate(true)

	return _camera_state_pending.duplicate(true)


func _find_system_camera_controller_in_tree() -> Node:
	var root := get_tree().root if is_inside_tree() else null

	if root == null:
		return null

	return _find_system_camera_controller_recursive(root)


func _find_system_camera_controller_recursive(node: Node) -> Node:
	if node is SystemCameraController:
		return node

	for child: Node in node.get_children():
		var found := _find_system_camera_controller_recursive(child)

		if found != null:
			return found

	return null


func to_save_data() -> Dictionary:
	return {
		"current_system_id": current_system_id,
		"discovered_system_ids": discovered_system_ids.duplicate(),
		"unlocked_system_ids": unlocked_system_ids.duplicate(),
		"established_base_records": _established_base_records.duplicate(true),
		"colonization_operations": _colonization_operations_to_save_array(),
		"next_colonization_operation_id": _next_colonization_operation_id,
		"bases": bases.to_save_data(),
		"object_scans": object_scans.to_save_data(),
		"automation": _build_automation_save_payload(),
		"camera_state": _capture_live_camera_snapshot(),
	}


func apply_save_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	current_system_id = str(data.get("current_system_id", START_SYSTEM_ID)).strip_edges()
	if current_system_id.is_empty():
		current_system_id = START_SYSTEM_ID

	discovered_system_ids.clear()
	for sid_var: Variant in data.get("discovered_system_ids", []):
		var sid := str(sid_var).strip_edges()
		if not sid.is_empty():
			discovered_system_ids.append(sid)

	unlocked_system_ids.clear()
	for uid_var: Variant in data.get("unlocked_system_ids", []):
		var uid := str(uid_var).strip_edges()
		if not uid.is_empty():
			unlocked_system_ids.append(uid)

	_galaxy_progression_seeded = true

	_established_base_ids.clear()
	_established_base_records.clear()
	var recs_variant: Variant = data.get("established_base_records", {})
	if recs_variant is Dictionary:
		for bid_var: Variant in (recs_variant as Dictionary).keys():
			var bid := str(bid_var).strip_edges()
			if bid.is_empty():
				continue
			var rec_variant: Variant = (recs_variant as Dictionary)[bid_var]
			if rec_variant is Dictionary:
				_established_base_records[bid] = (rec_variant as Dictionary).duplicate(true)
				_established_base_ids[bid] = true

	_colonization_operations.clear()
	_next_colonization_operation_id = maxi(1, int(data.get("next_colonization_operation_id", 1)))
	for op_entry: Variant in data.get("colonization_operations", []):
		if not op_entry is Dictionary:
			continue
		_apply_colonization_operation_from_save(op_entry as Dictionary)

	var bases_variant: Variant = data.get("bases", {})
	if bases_variant is Dictionary:
		bases.apply_save_data(bases_variant as Dictionary)
		_refresh_all_base_upgrade_derived_fields()

	var scans_variant: Variant = data.get("object_scans", {})
	if scans_variant is Dictionary:
		object_scans.apply_save_data(scans_variant as Dictionary)

	_sync_basic_intel_from_all_established_bases()

	_apply_automation_from_save_data(data.get("automation", {}))
	_apply_camera_state_from_save_data(data.get("camera_state", {}))

	current_system_definition = null
	_load_system_definition_for_id(current_system_id)

	galaxy_progression_changed.emit()
	for bid_var: Variant in bases.bases.keys():
		var bid := str(bid_var)
		base_resources_changed.emit(bid)
		base_upgrades_changed.emit(bid)

	return true


func _refresh_all_base_upgrade_derived_fields() -> void:
	for base_id_variant: Variant in bases.bases.keys():
		var base_id := str(base_id_variant).strip_edges()

		if base_id.is_empty():
			continue

		bases.get_base(base_id)


func _apply_camera_state_from_save_data(camera_variant: Variant) -> void:
	_camera_state_pending.clear()

	if camera_variant is Dictionary:
		_camera_state_pending = (camera_variant as Dictionary).duplicate(true)


func _apply_automation_from_save_data(automation_variant: Variant) -> void:
	_automation_runtime_pending.clear()

	if not automation_variant is Dictionary:
		automation.missions.clear()
		automation.next_mission_id = 1
		return

	var automation_data: Dictionary = automation_variant as Dictionary
	var store_variant: Variant = automation_data.get("store", {})

	if store_variant is Dictionary:
		automation.apply_save_data(store_variant as Dictionary)
	else:
		automation.missions.clear()
		automation.next_mission_id = 1

	var runtime_variant: Variant = automation_data.get("runtime", {})

	if runtime_variant is Dictionary:
		_automation_runtime_pending = (runtime_variant as Dictionary).duplicate(true)


func _colonization_operations_to_save_array() -> Array:
	var out: Array = []
	var now_tick: int = Time.get_ticks_msec()
	for op_id_var: Variant in _colonization_operations.keys():
		var op_id := str(op_id_var).strip_edges()
		if op_id.is_empty():
			continue
		var rec_variant: Variant = _colonization_operations[op_id_var]
		if rec_variant == null or not rec_variant is Dictionary:
			continue
		var rec: Dictionary = (rec_variant as Dictionary).duplicate(true)
		if str(rec.get("status", "")).strip_edges() == "pending":
			var arrival: int = int(rec.get("arrival_at_tick", 0))
			rec["remaining_ms"] = maxi(0, arrival - now_tick)
			rec.erase("arrival_at_tick")
			rec.erase("created_at_tick")
		out.append(rec)
	return out


func _apply_colonization_operation_from_save(rec: Dictionary) -> void:
	var op_id := str(rec.get("operation_id", "")).strip_edges()
	if op_id.is_empty():
		return
	var stored: Dictionary = rec.duplicate(true)
	var status := str(stored.get("status", "")).strip_edges()
	if status == "pending":
		var remaining_ms: int = maxi(0, int(stored.get("remaining_ms", 0)))
		var now_tick: int = Time.get_ticks_msec()
		stored["arrival_at_tick"] = now_tick + remaining_ms
		stored["created_at_tick"] = now_tick
		stored.erase("remaining_ms")
	_colonization_operations[op_id] = stored


func _load_system_definition_for_id(system_id: String) -> void:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		ensure_default_system_loaded()
		return
	var def := get_system_definition_by_id(sid)
	if def == null:
		push_warning("GameSession: SystemDefinition nicht gefunden für '%s'" % sid)
		ensure_default_system_loaded()
		return
	set_current_system(def)


func get_system_definition_by_id(system_id: String) -> SystemDefinition:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return null
	if _system_definition_by_id.is_empty():
		_build_system_definition_catalog()
	if _system_definition_by_id.has(sid):
		return _system_definition_by_id[sid] as SystemDefinition
	push_warning("GameSession: SystemDefinition nicht gefunden für id '%s'" % sid)
	return null


func get_system_display_name(system_id: String) -> String:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return ""
	var def := get_system_definition_by_id(sid)
	if def == null:
		return sid
	var display_name := str(def.display_name).strip_edges()
	if display_name.is_empty():
		return sid
	return display_name


func _build_system_definition_catalog() -> void:
	_system_definition_by_id.clear()
	var dir := DirAccess.open("res://data/galaxy_systems")
	if dir == null:
		push_warning("GameSession: Verzeichnis data/galaxy_systems nicht lesbar")
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var def := load("res://data/galaxy_systems/%s" % file_name) as SystemDefinition
		if def == null:
			continue
		var def_id := def.id.strip_edges()
		if def_id.is_empty():
			push_warning("GameSession: SystemDefinition ohne id in '%s'" % file_name)
			continue
		_system_definition_by_id[def_id] = def
