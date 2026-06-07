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

const DISCOVERY_HIDDEN := ObjectScanStore.DISCOVERY_HIDDEN
const DISCOVERY_SIGNAL := ObjectScanStore.DISCOVERY_SIGNAL
const DISCOVERY_KNOWN := ObjectScanStore.DISCOVERY_KNOWN

const SYSTEM_STAR_OBJECT_ID := "star"

const DEFAULT_GAME_START_DEFINITION_PATH := "res://data/game_start/default_start.tres"
const DEFAULT_GAME_BALANCE_PATH := "res://data/balance/v0_1_balance.tres"
const DEFAULT_COLONIZATION_DEFINITION_PATH := "res://data/colonization/default_colonization.tres"
const DEFAULT_UPGRADE_EFFECT_TEXTS_PATH := "res://data/ui_text/upgrade_effect_texts.tres"
const DEFAULT_DISCOVERY_SIGNAL_UI_TEXTS_PATH := (
	"res://data/ui_text/discovery_signal_ui_texts.tres"
)
const DEFAULT_GATE_UI_TEXTS_PATH := "res://data/ui_text/gate_ui_texts.tres"
## Safety fallback only when `ColonizationDefinition` fails to load — not the primary data source.
const COLONIZATION_OPERATION_DURATION_MS_FALLBACK := 60000
## v0.1 colony systems: initial signal markers (matches solar new-game intent).
const COLONY_SYSTEM_START_SIGNAL_COUNT := 2

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
## Space Miner v0.1 balance profile (`data/balance/v0_1_balance.tres`). Read via `get_game_balance()`.
var game_balance: GameBalanceDefinition = null
## UI metadata for resource ids (`data/resources/resource_catalog.tres`). Not a source for amounts or costs.
var resource_catalog: ResourceCatalogDefinition = null

## Debug-only balance telemetry logger. null in release builds.
var _balance_telemetry_logger: BalanceTelemetryLogger = null

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

var _resource_catalog_facade: ResourceCatalogFacade = ResourceCatalogFacade.new()

signal object_remaining_resources_changed(system_id: String, object_id: String)
signal base_resources_changed(base_id: String)
signal base_upgrades_changed(base_id: String)
## Emitted when `discovered_system_ids` or `unlocked_system_ids` change (not during initial seed).
signal galaxy_progression_changed()
## Runtime-only: established body set to KNOWN — scene may call `SystemDiscoveryController.refresh_object`.
signal established_body_discovery_visual_refresh_requested(system_id: String, body_id: String)


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
	_load_game_balance_definition()
	bases.set_game_balance(get_game_balance())
	_load_upgrade_effect_texts()
	_load_discovery_signal_ui_texts()
	_load_gate_ui_texts()
	_resource_catalog_facade.load_catalog()
	resource_catalog = _resource_catalog_facade.resource_catalog

	mark_base_established(BaseStore.BASE_EARTH)
	ensure_default_system_loaded()

	if OS.is_debug_build():
		_balance_telemetry_logger = BalanceTelemetryLogger.new()
		_balance_telemetry_logger.name = "BalanceTelemetryLogger"
		add_child(_balance_telemetry_logger)

	set_process(true)


func _process(_delta: float) -> void:
	if not is_colonization_auto_complete_enabled():
		return
	if not has_pending_colonization_operations():
		return
	process_colonization_operations()


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
	ensure_default_discovery_for_system(system_definition)


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


func _load_game_balance_definition() -> void:
	var res: Resource = load(DEFAULT_GAME_BALANCE_PATH)
	if res is GameBalanceDefinition:
		game_balance = res as GameBalanceDefinition
		return
	push_warning(
		"GameSession: failed to load GameBalanceDefinition from %s"
		% DEFAULT_GAME_BALANCE_PATH
	)
	game_balance = null


func get_game_balance() -> GameBalanceDefinition:
	if game_balance == null:
		_load_game_balance_definition()
	return game_balance


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
	_initialize_colony_system_discovery(sid, bod)
	_apply_colony_base_start_kit(base_id)
	base_resources_changed.emit(base_id)
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


func _load_discovery_signal_ui_texts() -> void:
	var res: Resource = load(DEFAULT_DISCOVERY_SIGNAL_UI_TEXTS_PATH)
	if res is DiscoverySignalUiTextDefinition:
		DiscoverySignalUiTextDefinition.set_global(res as DiscoverySignalUiTextDefinition)
		return
	push_warning(
		"GameSession: failed to load DiscoverySignalUiTextDefinition from %s"
		% DEFAULT_DISCOVERY_SIGNAL_UI_TEXTS_PATH
	)
	DiscoverySignalUiTextDefinition.set_global(null)


func _load_gate_ui_texts() -> void:
	var res: Resource = load(DEFAULT_GATE_UI_TEXTS_PATH)
	if res is GateUiTextDefinition:
		GateUiTextDefinition.set_global(res as GateUiTextDefinition)
		return
	push_warning(
		"GameSession: failed to load GateUiTextDefinition from %s" % DEFAULT_GATE_UI_TEXTS_PATH
	)
	GateUiTextDefinition.set_global(null)


func get_gate_ui_texts() -> GateUiTextDefinition:
	return GateUiTextDefinition.get_global()


func get_gate_text(key: StringName, fallback: String = "") -> String:
	return GateUiTextDefinition.get_text(key, fallback)


func get_resource_definition(resource_id: StringName) -> ResourceDefinition:
	return _resource_catalog_facade.get_resource_definition(resource_id)


func get_resource_display_name(resource_id: StringName, fallback: String = "") -> String:
	return _resource_catalog_facade.get_resource_display_name(resource_id, fallback)


func get_resource_short_label(resource_id: StringName, fallback: String = "") -> String:
	return _resource_catalog_facade.get_resource_short_label(resource_id, fallback)


func get_resource_sort_order(resource_id: StringName, fallback: int = 9999) -> int:
	return _resource_catalog_facade.get_resource_sort_order(resource_id, fallback)


func get_storage_resource_ids_sorted(resource_ids: Array[StringName]) -> Array[StringName]:
	return _resource_catalog_facade.get_storage_resource_ids_sorted(resource_ids)


func _gate_fail(reason_key: StringName, extra: Dictionary = {}) -> Dictionary:
	var gate := {
		"ok": false,
		"blocked_reason_key": reason_key,
		"blocked_reason": get_gate_text(reason_key),
	}
	for k: Variant in extra.keys():
		gate[k] = extra[k]
	return gate


func get_colonization_operation_duration_ms() -> int:
	if colonization_definition != null and colonization_definition.operation_duration_ms > 0:
		return colonization_definition.operation_duration_ms
	push_warning("GameSession: using fallback colonization operation duration (definition missing or invalid)")
	return COLONIZATION_OPERATION_DURATION_MS_FALLBACK


func resolve_colonization_target_body_id(target_system_id: String) -> String:
	var tsid := target_system_id.strip_edges()
	if tsid.is_empty():
		return ""
	var system_def := get_system_definition_by_id(tsid)
	if system_def == null:
		push_warning(
			"GameSession.resolve_colonization_target_body_id: missing SystemDefinition for '%s'."
			% tsid
		)
		return ""
	var body_id := system_def.get_resolved_colonization_start_body_id().strip_edges()
	if body_id.is_empty():
		push_warning(
			"GameSession.resolve_colonization_target_body_id: no colonization target for '%s'."
			% tsid
		)
	return body_id


func can_start_colonization_for_system(target_system_id: String) -> bool:
	return bool(get_colonization_start_gate(target_system_id).get("ok", false))


func get_colonization_start_gate(target_system_id: String) -> Dictionary:
	var tsid := target_system_id.strip_edges()
	if tsid.is_empty() or tsid == START_SYSTEM_ID:
		return {"ok": false, "target_body_id": ""}
	if has_established_base_in_system(tsid):
		return {"ok": false, "target_body_id": ""}
	if has_pending_colonization_to_system(tsid):
		return {"ok": false, "target_body_id": ""}

	var src := get_colonization_source_base_id().strip_edges()
	if src.is_empty() or get_base_colony_ship_count(src) < 1:
		return {"ok": false, "target_body_id": ""}

	var tbod := resolve_colonization_target_body_id(tsid)
	if tbod.is_empty() or has_established_base(tbod):
		return {"ok": false, "target_body_id": ""}

	return {"ok": true, "target_body_id": tbod}


func start_colonization_operation(
	source_base_id: String,
	target_system_id: String,
	target_body_id: String = "",
) -> String:
	var src := source_base_id.strip_edges()
	var tsid := target_system_id.strip_edges()
	var tbod := target_body_id.strip_edges()
	if tbod.is_empty():
		tbod = resolve_colonization_target_body_id(tsid)

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


func has_pending_colonization_operations() -> bool:
	for rec_variant: Variant in _colonization_operations.values():
		if rec_variant == null or not rec_variant is Dictionary:
			continue
		if str((rec_variant as Dictionary).get("status", "")).strip_edges() == "pending":
			return true
	return false


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


func is_colonization_auto_complete_enabled() -> bool:
	return colonization_definition != null and colonization_definition.allow_auto_complete


## Completes expired pending operations when auto-complete is enabled. Returns completed operation ids.
func process_colonization_operations() -> Array[String]:
	if not is_colonization_auto_complete_enabled():
		return []

	var to_complete: Array[String] = []
	var op_ids: Array = _colonization_operations.keys()
	op_ids.sort()

	for op_id_var: Variant in op_ids:
		var op_id := str(op_id_var).strip_edges()
		if op_id.is_empty():
			continue
		if get_colonization_operation_remaining_ms(op_id) > 0:
			continue
		var rec := get_colonization_operation(op_id)
		if rec.is_empty():
			continue
		if str(rec.get("status", "")).strip_edges() != "pending":
			continue
		to_complete.append(op_id)

	var completed_ids: Array[String] = []
	for op_id_complete: String in to_complete:
		if complete_colonization_operation(op_id_complete):
			completed_ids.append(op_id_complete)
	return completed_ids


## DEBUG ONLY — internal gate for galaxy instant-colonize dev button (no side effects).
func can_dev_instant_colonize_system(target_system_id: String) -> bool:
	if not OS.is_debug_build():
		return false

	var tsid := target_system_id.strip_edges()
	if tsid.is_empty() or tsid == START_SYSTEM_ID:
		return false
	if tsid == current_system_id.strip_edges():
		return false
	if has_established_base_in_system(tsid):
		return false
	if has_pending_colonization_to_system(tsid):
		return false

	var tbod := resolve_colonization_target_body_id(tsid)
	if tbod.is_empty() or has_established_base(tbod):
		return false

	return not _dev_resolve_colonization_source_base_id().is_empty()


## DEBUG ONLY: start + immediately complete a real colonization operation (editor/debug builds).
func dev_instant_colonize_system(target_system_id: String) -> bool:
	if not OS.is_debug_build():
		push_warning("GameSession: dev_instant_colonize_system is debug-only.")
		return false

	if not can_dev_instant_colonize_system(target_system_id):
		return false

	var tsid := target_system_id.strip_edges()
	var src := _dev_resolve_colonization_source_base_id()
	if src.is_empty():
		return false

	# DEV ONLY: grant one ColonyShip when the source base has none (no build-cost bypass elsewhere).
	if get_base_colony_ship_count(src) < 1:
		bases.add_colony_ship(src, 1)
		base_resources_changed.emit(src)

	var op_id := start_colonization_operation(src, tsid)
	if op_id.is_empty():
		return false

	return complete_colonization_operation(op_id)


func _dev_resolve_colonization_source_base_id() -> String:
	var candidates: Array[String] = []

	for bid_var: Variant in _established_base_records.keys():
		var bid: String = str(bid_var).strip_edges()
		if bid.is_empty() or not has_established_base(bid):
			continue
		candidates.append(bid)

	if candidates.is_empty():
		return ""

	var preferred_id: String = _get_preferred_colonization_source_base_id()
	for candidate in candidates:
		var cid: String = str(candidate).strip_edges()
		if cid == preferred_id:
			return preferred_id

	candidates.sort()
	return candidates[0]


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


func _resolve_v01_start_kit(include_colony_ships: bool) -> Dictionary:
	var def := _get_game_start_definition()
	var start_resources: Dictionary = {}
	var start_population: int = 1
	var start_drones: int = 1
	var start_mining_ships: int = 1
	var start_colony_ships: int = 0
	var start_survey_probes: int = 2
	if def != null:
		start_resources = def.start_resources.duplicate(true)
		if start_resources.is_empty():
			var start_balance := def.load_balance_profile()
			if start_balance != null:
				start_resources = start_balance.build_start_resources_dictionary()
		start_population = def.start_population
		start_drones = def.start_drones
		start_mining_ships = def.start_mining_ships
		if include_colony_ships:
			start_colony_ships = def.start_colony_ships
		start_survey_probes = maxi(0, def.start_survey_probes)
	else:
		var balance_fallback := get_game_balance()
		if balance_fallback != null:
			start_survey_probes = maxi(0, balance_fallback.survey_probe_start_count)
			if start_resources.is_empty():
				start_resources = balance_fallback.build_start_resources_dictionary()
			start_drones = maxi(1, balance_fallback.scan_drone_start_count)
			start_mining_ships = maxi(1, balance_fallback.mining_ship_start_count)

	var start_storage_capacity: int = -1
	if def != null and def.start_storage_capacity >= 0:
		start_storage_capacity = def.start_storage_capacity
	else:
		var balance_storage := get_game_balance()
		if balance_storage != null:
			start_storage_capacity = balance_storage.get_storage_capacity_for_upgrade_level(0)

	return {
		"population": start_population,
		"drones": start_drones,
		"mining_ships": start_mining_ships,
		"colony_ships": start_colony_ships,
		"survey_probes": start_survey_probes,
		"resources": start_resources,
		"storage_capacity": start_storage_capacity,
	}


func _apply_colony_base_start_kit(base_id: String) -> void:
	var bid := base_id.strip_edges()
	if bid.is_empty():
		return
	var kit: Dictionary = _resolve_v01_start_kit(false)
	bases.apply_start_kit_to_base(
		bid,
		int(kit.get("population", 1)),
		int(kit.get("drones", 1)),
		int(kit.get("mining_ships", 1)),
		0,
		kit.get("resources", {}) as Dictionary,
		int(kit.get("storage_capacity", -1)),
		int(kit.get("survey_probes", 0)),
	)


func _initialize_colony_system_discovery(system_id: String, colony_body_id: String) -> void:
	var sid := system_id.strip_edges()
	var colony_bod := colony_body_id.strip_edges()
	if sid.is_empty() or colony_bod.is_empty():
		return

	var system_def := get_system_definition_by_id(sid)
	if system_def == null:
		push_warning(
			"GameSession._initialize_colony_system_discovery: missing SystemDefinition for '%s'."
			% sid
		)
		return

	set_object_discovery_state(sid, SYSTEM_STAR_OBJECT_ID, DISCOVERY_KNOWN)
	set_object_discovery_state(sid, colony_bod, DISCOVERY_KNOWN)

	var signal_budget: int = maxi(0, COLONY_SYSTEM_START_SIGNAL_COUNT)
	var signal_candidates: Array[Dictionary] = []

	signal_budget = _collect_colony_discovery_signal_candidates(
		sid,
		colony_bod,
		system_def.bodies,
		signal_candidates,
		true,
		signal_budget,
	)
	signal_budget = _collect_colony_discovery_signal_candidates(
		sid,
		colony_bod,
		system_def.pois,
		signal_candidates,
		false,
		signal_budget,
	)

	signal_candidates.sort_custom(_compare_colony_discovery_signal_candidates)

	for row: Dictionary in signal_candidates:
		if signal_budget <= 0:
			set_object_discovery_state(sid, str(row.get("object_id", "")), DISCOVERY_HIDDEN)
			continue
		set_object_discovery_state(sid, str(row.get("object_id", "")), DISCOVERY_SIGNAL)
		signal_budget -= 1


func _collect_colony_discovery_signal_candidates(
	system_id: String,
	colony_body_id: String,
	definitions: Array,
	signal_candidates: Array[Dictionary],
	read_orbit_radius: bool,
	signal_budget: int,
) -> int:
	var budget: int = signal_budget
	for def_variant: Variant in definitions:
		var object_id := _colony_discovery_object_id(def_variant)
		if object_id.is_empty() or object_id == colony_body_id:
			continue

		var default_state := _colony_discovery_default_state(def_variant)
		if not default_state.is_empty():
			set_object_discovery_state(system_id, object_id, default_state)
			if default_state == DISCOVERY_SIGNAL:
				budget -= 1
			continue

		if not _colony_discovery_is_sensor_eligible(def_variant):
			set_object_discovery_state(system_id, object_id, DISCOVERY_HIDDEN)
			continue

		var row: Dictionary = {
			"object_id": object_id,
			"priority": _colony_discovery_sensor_priority(def_variant),
		}
		if read_orbit_radius and def_variant is SystemBodyDefinition:
			row["orbit_radius"] = (def_variant as SystemBodyDefinition).orbit_radius
		else:
			row["orbit_radius"] = 0.0
		signal_candidates.append(row)
	return budget


func _colony_discovery_object_id(definition: Variant) -> String:
	if definition is SystemBodyDefinition:
		return str((definition as SystemBodyDefinition).id).strip_edges()
	if definition is PointOfInterestDefinition:
		return str((definition as PointOfInterestDefinition).id).strip_edges()
	return ""


func _colony_discovery_default_state(definition: Variant) -> String:
	if definition is SystemBodyDefinition:
		return (definition as SystemBodyDefinition).get_normalized_default_discovery_state()
	if definition is PointOfInterestDefinition:
		return (definition as PointOfInterestDefinition).get_normalized_default_discovery_state()
	return ""


func _colony_discovery_is_sensor_eligible(definition: Variant) -> bool:
	if definition is SystemBodyDefinition:
		return (definition as SystemBodyDefinition).discoverable_by_base_sensor
	if definition is PointOfInterestDefinition:
		return (definition as PointOfInterestDefinition).discoverable_by_base_sensor
	return true


func _colony_discovery_sensor_priority(definition: Variant) -> int:
	if definition is SystemBodyDefinition:
		return (definition as SystemBodyDefinition).base_sensor_reveal_priority
	if definition is PointOfInterestDefinition:
		return (definition as PointOfInterestDefinition).base_sensor_reveal_priority
	return 100


func _compare_colony_discovery_signal_candidates(a: Dictionary, b: Dictionary) -> bool:
	var priority_a: int = int(a.get("priority", 0))
	var priority_b: int = int(b.get("priority", 0))
	if priority_a != priority_b:
		return priority_a > priority_b
	return float(a.get("orbit_radius", 0.0)) < float(b.get("orbit_radius", 0.0))


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
	set_object_discovery_state(sid, bod, DISCOVERY_KNOWN)
	ensure_basic_intel_for_established_base(sid, bod)
	established_body_discovery_visual_refresh_requested.emit(sid, bod)


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

	var entries: Array = _collect_scan_entries_for_definition(
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


func ensure_mining_resources_for_object(system_id: String, object_id: String) -> void:
	var sid := system_id.strip_edges()
	var oid := object_id.strip_edges()
	if sid.is_empty() or oid.is_empty():
		return

	var scan_state: String = get_object_scan_state(sid, oid)
	if scan_state == SCAN_UNKNOWN:
		return

	var definition: Resource = _load_object_definition_for_system(sid, oid)
	if definition == null:
		return

	var entries: Array = _collect_scan_entries_for_definition(definition, scan_state)
	ensure_object_resources_initialized(sid, oid, entries)


func can_mine_object(
	system_id: String,
	object_id: String,
	base_id: String = BaseStore.BASE_EARTH,
	has_idle_mining_ship: bool = false,
) -> Dictionary:
	var sid := system_id.strip_edges()
	var oid := object_id.strip_edges()
	var bid := _economy_base_id(base_id)

	if oid.is_empty() or sid.is_empty():
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NO_RESOURCES, false)

	if not is_object_known(sid, oid):
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NOT_DISCOVERED, false)

	var scan_state: String = get_object_scan_state(sid, oid)
	if scan_state == SCAN_UNKNOWN:
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NOT_SCANNED, false)

	var definition: Resource = _load_object_definition_for_system(sid, oid)
	if definition == null:
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NO_RESOURCES, false)

	var entries: Array = _collect_scan_entries_for_definition(definition, scan_state)
	if entries.is_empty():
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NO_RESOURCES, false)

	ensure_mining_resources_for_object(sid, oid)

	var probe_ids: Array = _resource_ids_from_scan_entries(entries)
	if probe_ids.is_empty():
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NO_RESOURCES, true)

	if not has_object_resources(sid, oid):
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NO_RESOURCES, true)

	if is_object_depleted(sid, oid) or not has_remaining_resources_among(sid, oid, probe_ids):
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_DEPLETED, true)

	if not has_idle_mining_ship:
		return _mine_blocked(GateUiTextDefinition.KEY_MINE_NO_SHIP, true)

	return {
		"ok": true,
		"blocked_reason": "",
		"blocked_reason_key": GateUiTextDefinition.KEY_NONE,
		"show_mine_button": true,
	}


func _mine_blocked(reason_key: StringName, show_mine_button: bool) -> Dictionary:
	var gate := _gate_fail(reason_key)
	gate["show_mine_button"] = show_mine_button
	return gate


func _resource_ids_from_scan_entries(entries: Array) -> Array:
	var ids: Array = []
	for entry_variant: Variant in entries:
		var entry: ScannedResourceEntry = entry_variant as ScannedResourceEntry
		if entry == null:
			continue
		var rid := String(entry.resource_id).strip_edges()
		if rid.is_empty() or ids.has(rid):
			continue
		ids.append(rid)
	return ids


func _load_object_definition_for_system(system_id: String, object_id: String) -> Resource:
	var body_def := _load_body_definition_for_system(system_id, object_id)
	if body_def != null:
		return body_def

	var sid := system_id.strip_edges()
	var oid := object_id.strip_edges()
	if sid.is_empty() or oid.is_empty():
		return null

	var system_def := get_system_definition_by_id(sid)
	if system_def == null:
		return null

	for poi_variant: Variant in system_def.pois:
		var poi_def := poi_variant as PointOfInterestDefinition
		if poi_def != null and poi_def.id == oid:
			return poi_def

	return null


func _collect_scan_entries_for_definition(definition: Resource, scan_state: String) -> Array:
	var result: Array = []
	if definition == null:
		return result

	var rank: int = scan_state_rank(scan_state)
	if rank < scan_state_rank(SCAN_BASIC):
		return result

	if definition.has_method(&"get_basic_scan_resources"):
		for entry: Variant in definition.call(&"get_basic_scan_resources"):
			if entry != null:
				result.append(entry)

	if rank >= scan_state_rank(SCAN_DEEP) and definition.has_method(&"get_deep_scan_resources"):
		for entry_deep: Variant in definition.call(&"get_deep_scan_resources"):
			if entry_deep != null:
				result.append(entry_deep)

	if rank >= scan_state_rank(SCAN_SPECIAL) and definition.has_method(&"get_special_scan_resources"):
		for entry_special: Variant in definition.call(&"get_special_scan_resources"):
			if entry_special != null:
				result.append(entry_special)

	return result


func get_object_scan_state(system_id: String, object_id: String) -> String:
	return object_scans.get_object_scan_state(system_id, object_id)


func set_object_discovery_state(system_id: String, object_id: String, discovery_state: String) -> void:
	object_scans.set_object_discovery_state(system_id, object_id, discovery_state)


func get_object_discovery_state(system_id: String, object_id: String) -> String:
	return object_scans.get_object_discovery_state(system_id, object_id)


func is_object_hidden(system_id: String, object_id: String) -> bool:
	return object_scans.is_object_hidden(system_id, object_id)


func is_object_signal(system_id: String, object_id: String) -> bool:
	return object_scans.is_object_signal(system_id, object_id)


func is_object_known(system_id: String, object_id: String) -> bool:
	return object_scans.is_object_known(system_id, object_id)


func has_explicit_object_discovery_state(system_id: String, object_id: String) -> bool:
	return object_scans.has_explicit_object_discovery_state(system_id, object_id)


## Ensures star, session start body, and established bases are never discovery-hidden.
func ensure_default_discovery_for_system(system_definition: SystemDefinition) -> void:
	if system_definition == null:
		return

	var sid := system_definition.id.strip_edges()
	if sid.is_empty():
		return

	_seed_discovery_from_system_definition(system_definition, sid)

	set_object_discovery_state(sid, SYSTEM_STAR_OBJECT_ID, DISCOVERY_KNOWN)

	var start_body_id := system_definition.start_body_id.strip_edges()
	if start_body_id.is_empty() and not system_definition.bodies.is_empty():
		var first_body: SystemBodyDefinition = system_definition.bodies[0]
		if first_body != null:
			start_body_id = first_body.id.strip_edges()

	if not start_body_id.is_empty():
		set_object_discovery_state(sid, start_body_id, DISCOVERY_KNOWN)

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

		var body_id := str(rec.get("body_id", bid)).strip_edges()
		if body_id.is_empty():
			continue

		set_object_discovery_state(sid, body_id, DISCOVERY_KNOWN)


func _seed_discovery_from_system_definition(
	system_definition: SystemDefinition,
	system_id: String
) -> void:
	for body_def_variant: Variant in system_definition.bodies:
		var body_def := body_def_variant as SystemBodyDefinition
		if body_def == null:
			continue
		_apply_definition_discovery_default(system_id, body_def.id, body_def.get_normalized_default_discovery_state())

	for poi_def_variant: Variant in system_definition.pois:
		var poi_def := poi_def_variant as PointOfInterestDefinition
		if poi_def == null:
			continue
		_apply_definition_discovery_default(system_id, poi_def.id, poi_def.get_normalized_default_discovery_state())


func _apply_definition_discovery_default(
	system_id: String,
	object_id: String,
	normalized_default_state: String
) -> void:
	var oid := object_id.strip_edges()
	if oid.is_empty():
		return

	if object_scans.has_explicit_object_discovery_state(system_id, oid):
		return

	if normalized_default_state.is_empty():
		return

	set_object_discovery_state(system_id, oid, normalized_default_state)


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


const _SCAN_DRONE_UNIT_PATH := "res://data/units/scan_drone.tres"

var _scan_drone_unit_definition: UnitDefinition = null


func scan_state_to_resource_layer(scan_state: String) -> int:
	match scan_state:
		SCAN_DEEP:
			return ScannedResourceEntry.Layer.DEEP
		SCAN_SPECIAL:
			return ScannedResourceEntry.Layer.SPECIAL
		_:
			return ScannedResourceEntry.Layer.BASIC


func get_next_scan_target_state(
	system_id: String,
	object_id: String,
	base_id: String = BaseStore.BASE_EARTH,
) -> String:
	var sid := system_id.strip_edges()
	var oid := object_id.strip_edges()
	if sid.is_empty() or oid.is_empty():
		return ""

	var unlocked_layer: int = get_unlocked_scan_layer_for_base(_economy_base_id(base_id))
	var current_rank: int = scan_state_rank(get_object_scan_state(sid, oid))

	if current_rank <= 0:
		return SCAN_BASIC
	if current_rank == scan_state_rank(SCAN_BASIC):
		if unlocked_layer >= ScannedResourceEntry.Layer.DEEP:
			return SCAN_DEEP
		return ""
	if current_rank == scan_state_rank(SCAN_DEEP):
		if unlocked_layer >= ScannedResourceEntry.Layer.SPECIAL:
			return SCAN_SPECIAL
		return ""

	return ""


func get_scan_target_state_or_rescan_state(
	system_id: String,
	object_id: String,
	base_id: String = BaseStore.BASE_EARTH,
) -> Dictionary:
	var sid := system_id.strip_edges()
	var oid := object_id.strip_edges()
	var bid := _economy_base_id(base_id)

	if sid.is_empty() or oid.is_empty():
		return {"target_scan_state": "", "scan_is_progression": false}

	var progress_state: String = get_next_scan_target_state(sid, oid, bid)
	if not progress_state.is_empty():
		return {"target_scan_state": progress_state, "scan_is_progression": true}

	var current_state: String = get_object_scan_state(sid, oid)
	var current_rank: int = scan_state_rank(current_state)

	if current_rank <= 0:
		return {"target_scan_state": SCAN_BASIC, "scan_is_progression": true}

	if current_rank >= scan_state_rank(SCAN_SPECIAL):
		return {"target_scan_state": SCAN_SPECIAL, "scan_is_progression": false}
	if current_rank >= scan_state_rank(SCAN_DEEP):
		return {"target_scan_state": SCAN_DEEP, "scan_is_progression": false}

	return {"target_scan_state": SCAN_BASIC, "scan_is_progression": false}


func can_scan_object(
	system_id: String,
	object_id: String,
	base_id: String = BaseStore.BASE_EARTH,
	has_idle_scan_drone: bool = false,
	target_has_active_scan: bool = false,
) -> Dictionary:
	var sid := system_id.strip_edges()
	var oid := object_id.strip_edges()
	var bid := _economy_base_id(base_id)
	var scan_target: Dictionary = get_scan_target_state_or_rescan_state(sid, oid, bid)
	var target_state: String = str(scan_target.get("target_scan_state", "")).strip_edges()
	var scan_is_progression: bool = bool(scan_target.get("scan_is_progression", true))

	if oid.is_empty() or sid.is_empty():
		return _scan_blocked(
			GateUiTextDefinition.KEY_SCAN_NOT_DISCOVERED,
			"",
			false,
		)

	if not is_object_known(sid, oid):
		return _scan_blocked(
			GateUiTextDefinition.KEY_SCAN_NOT_DISCOVERED,
			target_state,
			scan_is_progression,
		)

	if target_state.is_empty():
		return _scan_blocked_no_layer("", false)

	if scan_is_progression and not _scan_layer_allows_target_state(bid, target_state):
		return _scan_blocked_no_layer(target_state, scan_is_progression)

	if target_has_active_scan:
		return _scan_blocked(
			GateUiTextDefinition.KEY_SCAN_ALREADY_IN_PROGRESS,
			target_state,
			scan_is_progression,
		)

	if not has_idle_scan_drone:
		return _scan_blocked(
			GateUiTextDefinition.KEY_SCAN_NO_DRONE,
			target_state,
			scan_is_progression,
		)

	return {
		"ok": true,
		"blocked_reason": "",
		"blocked_reason_key": GateUiTextDefinition.KEY_NONE,
		"target_scan_state": target_state,
		"scan_is_progression": scan_is_progression,
	}


func _scan_blocked(
	reason_key: StringName,
	target_scan_state: String,
	scan_is_progression: bool,
) -> Dictionary:
	return _gate_fail(
		reason_key,
		{
			"target_scan_state": target_scan_state,
			"scan_is_progression": scan_is_progression,
		},
	)


func _scan_blocked_no_layer(target_scan_state: String, scan_is_progression: bool) -> Dictionary:
	return _scan_blocked(
		GateUiTextDefinition.KEY_SCAN_NO_LAYER,
		target_scan_state,
		scan_is_progression,
	)


func _scan_layer_allows_target_state(base_id: String, target_scan_state: String) -> bool:
	var unlocked_layer: int = get_unlocked_scan_layer_for_base(_economy_base_id(base_id))
	match target_scan_state:
		SCAN_BASIC:
			return true
		SCAN_DEEP:
			return unlocked_layer >= ScannedResourceEntry.Layer.DEEP
		SCAN_SPECIAL:
			return unlocked_layer >= ScannedResourceEntry.Layer.SPECIAL
		_:
			return false


func get_scan_duration_seconds_for_target_state(
	target_scan_state: String,
	base_id: String = BaseStore.BASE_EARTH,
) -> float:
	var bid := _economy_base_id(base_id)
	var seconds: float = 0.0
	var unit_def := _get_scan_drone_unit_definition()

	if unit_def != null:
		match target_scan_state:
			SCAN_DEEP:
				if unit_def.deep_scan_duration_seconds > 0.0:
					seconds = unit_def.deep_scan_duration_seconds
			SCAN_SPECIAL:
				if unit_def.special_scan_duration_seconds > 0.0:
					seconds = unit_def.special_scan_duration_seconds
			_:
				if unit_def.basic_scan_duration_seconds > 0.0:
					seconds = unit_def.basic_scan_duration_seconds

	if seconds <= 0.0:
		var balance := get_game_balance()
		if balance != null:
			seconds = balance.get_scan_duration_for_layer(scan_state_to_resource_layer(target_scan_state))
		else:
			match target_scan_state:
				SCAN_DEEP:
					seconds = 85.0
				SCAN_SPECIAL:
					seconds = 140.0
				_:
					seconds = 35.0

	return maxf(seconds * get_scan_drone_scan_duration_multiplier(bid), 0.001)


func grant_scan_survey_data_reward(base_id: String, completed_scan_state: String) -> void:
	var balance := get_game_balance()
	if balance == null:
		balance = GameBalanceDefinition.new()
	var amount: int = balance.get_scan_survey_data_reward_for_state(StringName(completed_scan_state))
	if amount <= 0:
		return

	var resource_id := str(GameBalanceDefinition.RESOURCE_SURVEY_DATA)
	var added: int = add_base_resource(_economy_base_id(base_id), resource_id, amount)
	if added <= 0:
		push_warning(
			"GameSession: SurveyData scan reward skipped (state=%s, added=%d)."
			% [completed_scan_state, added]
		)


func _get_scan_drone_unit_definition() -> UnitDefinition:
	if _scan_drone_unit_definition != null:
		return _scan_drone_unit_definition
	var res: Resource = load(_SCAN_DRONE_UNIT_PATH)
	if res is UnitDefinition:
		_scan_drone_unit_definition = res as UnitDefinition
	return _scan_drone_unit_definition


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


func _economy_base_id(base_id: String) -> String:
	var bid := base_id.strip_edges()
	return bid if not bid.is_empty() else BaseStore.BASE_EARTH


func get_available_survey_probe_count(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_available_survey_probe_count(_economy_base_id(base_id))


func can_consume_survey_probe(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return bases.can_consume_survey_probe(_economy_base_id(base_id))


func reserve_or_consume_survey_probe(base_id: String = BaseStore.BASE_EARTH) -> bool:
	var bid := _economy_base_id(base_id)
	if not bases.reserve_or_consume_survey_probe(bid):
		return false
	base_resources_changed.emit(bid)
	return true


func add_survey_probe(amount: int, base_id: String = BaseStore.BASE_EARTH) -> void:
	if amount <= 0:
		return
	var bid := _economy_base_id(base_id)
	bases.add_survey_probe(bid, amount)
	base_resources_changed.emit(bid)


func get_survey_probe_build_time_seconds() -> float:
	var balance := get_game_balance()
	if balance != null:
		return maxf(0.0, balance.survey_probe_build_time)
	return 8.0


func get_survey_probe_build_cost() -> Dictionary:
	var cost := get_production_cost(BaseStore.PRODUCTION_SURVEY_PROBE)
	if not cost.is_empty():
		return cost
	var balance := get_game_balance()
	if balance != null:
		return balance.survey_probe_build_cost.duplicate(true)
	return {GameBalanceDefinition.RESOURCE_IRON: 40}


func can_build_base_survey_probe(base_id: String) -> bool:
	return get_build_base_survey_probe_gate(base_id).get("ok", false)


func get_build_base_survey_probe_gate(base_id: String) -> Dictionary:
	var bid := _economy_base_id(base_id)
	return _build_gate_from_key(bases.get_build_survey_probe_blocked_reason_key(bid))


func get_build_base_scan_drone_gate(base_id: String) -> Dictionary:
	var bid := _economy_base_id(base_id)
	return _build_gate_from_key(bases.get_build_scan_drone_blocked_reason_key(bid))


func get_build_base_mining_ship_gate(base_id: String) -> Dictionary:
	var bid := _economy_base_id(base_id)
	return _build_gate_from_key(bases.get_build_mining_ship_blocked_reason_key(bid))


func _build_gate_from_key(reason_key: StringName) -> Dictionary:
	if reason_key == GateUiTextDefinition.KEY_NONE or String(reason_key).is_empty():
		return {"ok": true, "blocked_reason": "", "blocked_reason_key": GateUiTextDefinition.KEY_NONE}
	return _gate_fail(reason_key)


func build_base_survey_probe(base_id: String) -> bool:
	var bid := _economy_base_id(base_id)
	if not bases.build_survey_probe(bid):
		return false
	base_resources_changed.emit(bid)
	return true


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
	var bid := _economy_base_id(base_id)
	if bid.is_empty():
		push_warning("GameSession: cannot build ColonyShip without base_id.")
		return false
	if not has_established_base(bid):
		push_warning("GameSession: cannot build ColonyShip for non-established base_id=%s." % bid)
		return false
	var prereq_key := get_colony_ship_build_prerequisite_blocked_reason_key(bid)
	if not bases.build_colony_ship(bid, prereq_key):
		return false

	base_resources_changed.emit(bid)
	return true


func get_base_storage_used(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_storage_used(base_id)


func get_base_storage_capacity(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_storage_capacity(base_id)


func get_base_storage_free(base_id: String = BaseStore.BASE_EARTH) -> int:
	return get_base_remaining_storage_capacity(base_id)


func get_base_remaining_storage_capacity(base_id: String = BaseStore.BASE_EARTH) -> int:
	return bases.get_remaining_storage_capacity(base_id)


func is_base_storage_full(base_id: String = BaseStore.BASE_EARTH) -> bool:
	return bases.is_storage_full(base_id)


func can_accept_base_resource(base_id: String, resource_id: String, amount: int) -> bool:
	return bases.can_accept_resource(base_id, resource_id, amount)


func add_base_resource_with_capacity_check(
	base_id: String,
	resource_id: String,
	amount: int,
) -> int:
	return add_base_resource(base_id, resource_id, amount)


func get_base_storage_blocked_reason_full() -> String:
	return get_gate_text(
		GateUiTextDefinition.KEY_STORAGE_FULL,
		GateUiTextDefinition.FALLBACK_STORAGE_FULL,
	)


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
	return get_buy_next_base_upgrade_gate(base_id, category).get("ok", false)


func get_buy_next_base_upgrade_gate(base_id: String, category: StringName) -> Dictionary:
	var bid := _economy_base_id(base_id)
	var reason_key := bases.get_buy_next_upgrade_blocked_reason_key(bid, category)
	if reason_key == GateUiTextDefinition.KEY_NONE or String(reason_key).is_empty():
		if not has_next_base_upgrade(bid, category):
			return {
				"ok": false,
				"blocked_reason": "",
				"blocked_reason_key": GateUiTextDefinition.KEY_NONE,
			}
		return {"ok": true, "blocked_reason": "", "blocked_reason_key": GateUiTextDefinition.KEY_NONE}
	return _gate_fail(reason_key)


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


func get_mining_ship_mining_rate_multiplier(base_id: String = BaseStore.BASE_EARTH) -> float:
	return clampf(bases.get_mining_ship_mining_rate_multiplier(base_id), 0.05, 10.0)


func get_max_base_scan_drone_count() -> int:
	return bases.get_max_scan_drone_count()


func get_max_base_mining_ship_count() -> int:
	return bases.get_max_mining_ship_count()


func can_build_base_drone(base_id: String) -> bool:
	return get_build_base_scan_drone_gate(base_id).get("ok", false)


func can_build_base_mining_ship(base_id: String) -> bool:
	return get_build_base_mining_ship_gate(base_id).get("ok", false)


func get_colony_ship_build_cost() -> Dictionary:
	var cost := get_production_cost(BaseStore.PRODUCTION_COLONY_SHIP)
	if not cost.is_empty():
		return cost
	var balance := get_game_balance()
	if balance != null:
		return balance.colony_ship_build_cost.duplicate(true)
	return {}


func get_colony_ship_build_time_seconds() -> float:
	var def := get_production_definition(BaseStore.PRODUCTION_COLONY_SHIP)
	if def != null and def.build_time_seconds > 0.0:
		return def.build_time_seconds
	var balance := get_game_balance()
	if balance != null and balance.colony_ship_build_time_seconds > 0.0:
		return balance.colony_ship_build_time_seconds
	return 0.0


## v0.1: Storage Upgrade I proxies Shipyard I until a dedicated Shipyard tech exists.
func has_colony_ship_shipyard_i_for_base(base_id: String) -> bool:
	var bid := _economy_base_id(base_id)
	var balance := get_game_balance()
	var need_lvl := 1
	if balance != null:
		need_lvl = maxi(1, balance.colony_ship_shipyard_proxy_storage_upgrade_level)
	return bases.get_upgrade_level(bid, &"storage") >= need_lvl


## v0.1: Mining Ship Upgrade I proxies Colony Protocol until dedicated tech exists.
func has_colony_ship_colony_protocol_for_base(base_id: String) -> bool:
	var bid := _economy_base_id(base_id)
	var balance := get_game_balance()
	var need_lvl := 1
	if balance != null:
		need_lvl = maxi(1, balance.colony_ship_protocol_proxy_mining_ship_upgrade_level)
	return bases.get_upgrade_level(bid, &"mining_ship") >= need_lvl


func has_colony_ship_deep_scan_module_for_base(base_id: String) -> bool:
	return bases.get_upgrade_level(_economy_base_id(base_id), &"scan_drone") >= 1


func count_fully_scanned_objects(system_id: String = "") -> int:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		sid = current_system_id.strip_edges()
	if sid.is_empty():
		return 0

	var system_states: Variant = object_scans.object_scan_states.get(sid, {})
	if not system_states is Dictionary:
		return 0

	var deep_rank := scan_state_rank(SCAN_DEEP)
	var count := 0
	for _oid: Variant in (system_states as Dictionary).keys():
		var state := str((system_states as Dictionary).get(_oid, SCAN_UNKNOWN))
		if scan_state_rank(state) >= deep_rank:
			count += 1
	return count


func get_colony_ship_min_fully_scanned_objects() -> int:
	var balance := get_game_balance()
	if balance != null:
		return maxi(1, balance.colony_ship_min_fully_scanned_objects)
	return 3


func has_discovered_ice_source(system_id: String = "") -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return _any_system_has_discovered_ice_source()
	return _system_has_discovered_ice_source(sid)


func _any_system_has_discovered_ice_source() -> bool:
	for sys_key: Variant in object_scans.object_scan_states.keys():
		if _system_has_discovered_ice_source(str(sys_key)):
			return true
	return false


func _system_has_discovered_ice_source(system_id: String) -> bool:
	var sid := system_id.strip_edges()
	if sid.is_empty():
		return false

	var system_def := get_system_definition_by_id(sid)
	if system_def == null:
		return false

	var ice_ids := _colony_ship_ice_resource_ids_normalized()

	for body_variant: Variant in system_def.bodies:
		var body_def := body_variant as SystemBodyDefinition
		if body_def == null:
			continue
		var oid := str(body_def.id).strip_edges()
		if oid.is_empty():
			continue
		if not is_object_known(sid, oid):
			continue
		var scan_state := get_object_scan_state(sid, oid)
		if scan_state_rank(scan_state) < scan_state_rank(SCAN_BASIC):
			continue
		for entry: Variant in _collect_scan_entries_for_definition(body_def, scan_state):
			if entry is ScannedResourceEntry:
				var rid := str((entry as ScannedResourceEntry).resource_id)
				if _resource_id_matches_ice_source(rid, ice_ids):
					return true
	return false


func _colony_ship_ice_resource_ids_normalized() -> PackedStringArray:
	var balance := get_game_balance()
	if balance != null and balance.colony_ship_ice_resource_ids.size() > 0:
		return balance.colony_ship_ice_resource_ids
	return PackedStringArray(["Ice", "Water"])


func _resource_id_matches_ice_source(resource_id: String, ice_ids: PackedStringArray) -> bool:
	var rid := resource_id.strip_edges().to_lower()
	if rid.is_empty():
		return false
	for ice_id: String in ice_ids:
		if rid == str(ice_id).strip_edges().to_lower():
			return true
	return false


func get_colony_ship_build_prerequisite_status(base_id: String) -> Array:
	var bid := _economy_base_id(base_id)
	return [
		_colony_prerequisite_entry(
			"deep_scan_module",
			"Deep Scan Module",
			has_colony_ship_deep_scan_module_for_base(bid),
			GateUiTextDefinition.KEY_COLONY_DEEP_SCAN_REQUIRED,
		),
		_colony_prerequisite_entry(
			"shipyard_i",
			"Shipyard I",
			has_colony_ship_shipyard_i_for_base(bid),
			GateUiTextDefinition.KEY_COLONY_SHIPYARD_REQUIRED,
		),
		_colony_prerequisite_entry(
			"colony_protocol",
			"Colony Protocol",
			has_colony_ship_colony_protocol_for_base(bid),
			GateUiTextDefinition.KEY_COLONY_PROTOCOL_REQUIRED,
		),
		_colony_prerequisite_entry(
			"ice_source",
			"Ice source discovered",
			has_discovered_ice_source(),
			GateUiTextDefinition.KEY_COLONY_ICE_SOURCE_REQUIRED,
		),
		_colony_prerequisite_entry(
			"fully_scan_three",
			"Fully scan 3 objects",
			count_fully_scanned_objects() >= get_colony_ship_min_fully_scanned_objects(),
			GateUiTextDefinition.KEY_COLONY_FULLY_SCAN_THREE,
		),
	]


func _colony_prerequisite_entry(
	id: String,
	label: String,
	met: bool,
	reason_key: StringName,
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"met": met,
		"blocked_reason_key": reason_key,
		"blocked_reason": get_gate_text(reason_key),
	}


func get_colony_ship_build_prerequisite_blocked_reason_key(base_id: String) -> StringName:
	for entry: Variant in get_colony_ship_build_prerequisite_status(base_id):
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry
		if bool(row.get("met", false)):
			continue
		var key: StringName = row.get("blocked_reason_key", GateUiTextDefinition.KEY_NONE)
		if key != GateUiTextDefinition.KEY_NONE and not String(key).is_empty():
			return key
	return GateUiTextDefinition.KEY_NONE


func get_colony_ship_build_prerequisite_blocked_reason(base_id: String) -> String:
	var key := get_colony_ship_build_prerequisite_blocked_reason_key(base_id)
	if key == GateUiTextDefinition.KEY_NONE or String(key).is_empty():
		return ""
	return get_gate_text(key)


func get_build_base_colony_ship_gate(base_id: String) -> Dictionary:
	var bid := _economy_base_id(base_id)
	if bid.is_empty() or not has_established_base(bid):
		return {
			"ok": false,
			"blocked_reason": "",
			"blocked_reason_key": GateUiTextDefinition.KEY_NONE,
			"prerequisites": [],
		}

	var prerequisites: Array = get_colony_ship_build_prerequisite_status(bid)
	var prereq_key := get_colony_ship_build_prerequisite_blocked_reason_key(bid)
	var reason_key := bases.get_build_colony_ship_blocked_reason_key(bid, prereq_key)
	if reason_key == GateUiTextDefinition.KEY_NONE or String(reason_key).is_empty():
		return {
			"ok": true,
			"blocked_reason": "",
			"blocked_reason_key": GateUiTextDefinition.KEY_NONE,
			"prerequisites": prerequisites,
		}

	var gate := _gate_fail(reason_key)
	gate["prerequisites"] = prerequisites
	return gate


func can_build_base_colony_ship(base_id: String) -> bool:
	return get_build_base_colony_ship_gate(base_id).get("ok", false)


func get_production_cost(production_id: String) -> Dictionary:
	return bases.get_production_cost(production_id)


func get_production_definition(production_id: String) -> ProductionDefinition:
	return bases.get_production_definition(production_id)


# --------------------------------------------------
# Automation API
# --------------------------------------------------

func create_scan_mission(
	base_id: String,
	target_id: String,
	target_scan_state: String = "",
	scan_is_progression: bool = true,
) -> int:
	return automation.create_scan_mission(
		base_id, target_id, target_scan_state, scan_is_progression
	)


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

	var kit: Dictionary = _resolve_v01_start_kit(true)

	bases.bases = {
		primary_base_id: bases.create_new_game_base_entry(
			int(kit.get("population", 1)),
			int(kit.get("drones", 1)),
			int(kit.get("mining_ships", 1)),
			int(kit.get("colony_ships", 0)),
			kit.get("resources", {}) as Dictionary,
			int(kit.get("storage_capacity", -1)),
			int(kit.get("survey_probes", 0)),
		),
	}

	object_scans.object_scan_states = {}
	object_scans.object_discovery_states = {}
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


## Pre-save (v0.1): cancel in-flight survey-probe missions and refund probes (no mission restore on load).
func cancel_active_survey_probe_missions_before_save() -> int:
	var controller := _find_survey_probe_mission_controller_in_tree()
	if controller == null:
		return 0
	return controller.cancel_all_active_investigations_refund()


func cancel_active_base_sensor_pulse_before_save() -> void:
	var controller := _find_base_sensor_pulse_controller_in_tree()
	if controller == null:
		return
	controller.cancel_pulse_before_save()


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


func _find_survey_probe_mission_controller_in_tree() -> SurveyProbeMissionController:
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return null
	return _find_survey_probe_mission_controller_recursive(root)


func _find_survey_probe_mission_controller_recursive(node: Node) -> SurveyProbeMissionController:
	if node is SurveyProbeMissionController:
		return node as SurveyProbeMissionController
	for child: Node in node.get_children():
		var found := _find_survey_probe_mission_controller_recursive(child)
		if found != null:
			return found
	return null


func _find_base_sensor_pulse_controller_in_tree() -> BaseSensorPulseController:
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return null
	return _find_base_sensor_pulse_controller_recursive(root)


func _find_base_sensor_pulse_controller_recursive(node: Node) -> BaseSensorPulseController:
	if node is BaseSensorPulseController:
		return node as BaseSensorPulseController
	for child: Node in node.get_children():
		var found := _find_base_sensor_pulse_controller_recursive(child)
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

	if current_system_definition != null:
		ensure_default_discovery_for_system(current_system_definition)

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
