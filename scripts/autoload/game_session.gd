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

const COLONIZATION_OPERATION_DURATION_MS := 60000

const SCANNER_BASIC := ScannerStore.SCANNER_BASIC
const SCANNER_DEEP := ScannerStore.SCANNER_DEEP
const SCANNER_SPECIAL := ScannerStore.SCANNER_SPECIAL

var current_system_definition: SystemDefinition = null
var current_system_id: String = ""

var object_scans := ObjectScanStore.new()
var system_entry := SystemEntryStore.new()
var bases := BaseStore.new()
var automation := AutomationStore.new()

var scanner := ScannerStore.new()

## Phase 5.5: data-driven upgrade tiers (`data/upgrades/*.tres`).
var upgrade_catalog: UpgradeCatalog = null

## Phase 6.1b: session-only galaxy progression (no savegame).
var discovered_system_ids: Array[String] = []
var unlocked_system_ids: Array[String] = []
var _galaxy_progression_seeded: bool = false

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
## Emitted when `discovered_system_ids` or `unlocked_system_ids` change (not during initial seed).
signal galaxy_progression_changed()


# --------------------------------------------------
# Lifecycle
# --------------------------------------------------

func _ready() -> void:
	upgrade_catalog = UpgradeCatalog.new()
	upgrade_catalog.load_all()
	bases.set_upgrade_catalog(upgrade_catalog)
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


func _seed_default_galaxy_progression() -> void:
	discovered_system_ids.clear()
	unlocked_system_ids.clear()
	discovered_system_ids.append(START_SYSTEM_ID)
	unlocked_system_ids.append(START_SYSTEM_ID)
	discovered_system_ids.append(PROXIMA_SYSTEM_ID)


func is_system_discovered(system_id: String) -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return false
	return discovered_system_ids.has(sid)


func is_system_unlocked(system_id: String) -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return false
	return unlocked_system_ids.has(sid)


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
	var rec: Dictionary = {
		"operation_id": op_id,
		"source_base_id": src,
		"target_system_id": tsid,
		"target_body_id": tbod,
		"status": "pending",
		"reserved_colony_ships": 1,
		"created_at_tick": created_tick,
		"completed_at_tick": -1,
		"duration_ms": COLONIZATION_OPERATION_DURATION_MS,
		"arrival_at_tick": created_tick + COLONIZATION_OPERATION_DURATION_MS,
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


func get_colonization_operation_status_text(operation_id: String) -> String:
	var rec := get_colonization_operation(operation_id)
	if rec.is_empty():
		return ""
	if str(rec.get("status", "")).strip_edges() != "pending":
		return ""
	var remaining_ms: int = get_colonization_operation_remaining_ms(operation_id)
	if remaining_ms <= 0:
		return "Bereit zur Ankunft"
	var sec: int = int(ceil(float(remaining_ms) / 1000.0))
	return "Läuft %ds" % sec


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

	var earth_id: String = BaseStore.BASE_EARTH
	for c in candidates:
		var cid: String = str(c).strip_edges()
		if cid == earth_id:
			return earth_id

	candidates.sort()
	return candidates[0]


func _allocate_colonization_operation_id() -> String:
	var id_str: String = "colony_%d" % _next_colonization_operation_id
	_next_colonization_operation_id += 1
	return id_str


## DEV / foundation: uses colonization operation flow (start → complete) for tests.
func dev_consume_colony_ship_and_establish_base(source_base_id: String, target_system_id: String, target_body_id: String) -> bool:
	var op_id := start_colonization_operation(source_base_id, target_system_id, target_body_id)
	if op_id.is_empty():
		return false
	return complete_colonization_operation(op_id)


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
	var rec: Dictionary = {
		"base_id": base_id,
		"system_id": system_id.strip_edges(),
		"body_id": body_id.strip_edges(),
		"established": true,
	}
	_established_base_records[base_id] = rec


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


func set_active_scanner_tier(scanner_tier: String) -> void:
	scanner.set_active_tier(scanner_tier)


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
	return true


func get_base_storage_capacity_percent(base_id: String = BaseStore.BASE_EARTH) -> int:
	var base0 := upgrade_catalog.get_definition(&"storage", 0) if upgrade_catalog != null else null
	var units0 := BaseStore.INITIAL_STORAGE_CAPACITY
	if base0 != null and base0.storage_capacity_units >= 0:
		units0 = base0.storage_capacity_units
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


func can_buy_base_storage_upgrade_i(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return can_buy_next_base_upgrade(base_id, &"storage")


func buy_base_storage_upgrade_i(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return buy_next_base_upgrade(base_id, &"storage")


func get_base_storage_upgrade_i_cost(base_id: String = BaseStore.BASE_EARTH) -> Dictionary:
	return bases.get_storage_upgrade_i_cost(base_id)


func is_base_storage_upgrade_i_bought(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return bases.is_storage_upgrade_i_bought(base_id)


func can_buy_scan_drone_upgrade_i(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return can_buy_next_base_upgrade(base_id, &"scan_drone")


func buy_scan_drone_upgrade_i(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return buy_next_base_upgrade(base_id, &"scan_drone")


func is_scan_drone_upgrade_i_bought(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return bases.is_scan_drone_upgrade_i_bought(base_id)


func get_scan_drone_upgrade_i_cost(base_id: String = BaseStore.BASE_EARTH) -> Dictionary:
	return bases.get_scan_drone_upgrade_i_cost(base_id)


func get_scan_drone_scan_duration_multiplier(base_id: String = BaseStore.BASE_EARTH) -> float:
	return clampf(bases.get_scan_drone_scan_duration_multiplier(base_id), 0.05, 10.0)


func can_buy_mining_ship_upgrade_i(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return can_buy_next_base_upgrade(base_id, &"mining_ship")


func buy_mining_ship_upgrade_i(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return buy_next_base_upgrade(base_id, &"mining_ship")


func is_mining_ship_upgrade_i_bought(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return bases.is_mining_ship_upgrade_i_bought(base_id)


func get_mining_ship_upgrade_i_cost(base_id: String = BaseStore.BASE_EARTH) -> Dictionary:
	return bases.get_mining_ship_upgrade_i_cost(base_id)


func get_mining_ship_cargo_capacity_multiplier(base_id: String = BaseStore.BASE_EARTH) -> float:
	return clampf(bases.get_mining_ship_cargo_capacity_multiplier(base_id), 1.0, 4.0)


func can_build_base_drone(base_id: String) -> bool:
	return bases.can_afford(base_id, BaseStore.DRONE_COST)


func can_build_base_mining_ship(base_id: String) -> bool:
	return bases.can_afford(base_id, BaseStore.MINING_SHIP_COST)


func can_build_base_colony_ship(base_id: String) -> bool:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return false
	if not has_established_base(bid):
		return false
	return bases.can_build_colony_ship(bid)


func get_build_cost_text(unit_type: String) -> String:
	match unit_type:
		"drone":
			return bases.format_cost(BaseStore.DRONE_COST)
		"mining_ship":
			return bases.format_cost(BaseStore.MINING_SHIP_COST)
		"colony_ship":
			return bases.format_cost(BaseStore.COLONY_SHIP_COST)
		_:
			return ""


# Adds units without cost. Used for starting units and event grants.
func add_base_mining_ship(base_id: String, amount: int = 1) -> void:
	bases.add_mining_ship(base_id, amount)


func add_base_drone(base_id: String, amount: int = 1) -> void:
	bases.add_drone(base_id, amount)


# Temporary Earth aliases for current UI
func get_earth_resource_amount(resource_id: String) -> int:
	return get_base_resource_amount(BaseStore.BASE_EARTH, resource_id)


func add_earth_resource(resource_id: String, amount: int) -> void:
	add_base_resource(BaseStore.BASE_EARTH, resource_id, amount)


func spend_earth_resource(resource_id: String, amount: int) -> bool:
	return spend_base_resource(BaseStore.BASE_EARTH, resource_id, amount)


func get_earth_population() -> int:
	return get_base_population(BaseStore.BASE_EARTH)


func get_drone_count() -> int:
	return get_base_drone_count(BaseStore.BASE_EARTH)


func get_mining_ship_count() -> int:
	return get_base_mining_ship_count(BaseStore.BASE_EARTH)


func build_drone() -> bool:
	return build_base_drone(BaseStore.BASE_EARTH)


func build_mining_ship() -> bool:
	return build_base_mining_ship(BaseStore.BASE_EARTH)


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
