## Data-driven UI strings for economy gates (scan, mine, build, upgrade, storage).
## Loaded from `data/ui_text/gate_ui_texts.tres` in GameSession.
class_name GateUiTextDefinition
extends Resource

const KEY_NONE := &"none"

const KEY_SCAN_NOT_DISCOVERED := &"scan_not_discovered"
const KEY_SCAN_ALREADY_IN_PROGRESS := &"scan_already_in_progress"
const KEY_SCAN_NO_DRONE := &"scan_no_drone"
const KEY_SCAN_NO_LAYER := &"scan_no_layer"

const KEY_MINE_NOT_DISCOVERED := &"mine_not_discovered"
const KEY_MINE_NOT_SCANNED := &"mine_not_scanned"
const KEY_MINE_NO_RESOURCES := &"mine_no_resources"
const KEY_MINE_DEPLETED := &"mine_depleted"
const KEY_MINE_NO_SHIP := &"mine_no_ship"
const KEY_MINE_STORAGE_FULL := &"mine_storage_full"

const KEY_BUILD_NOT_ENOUGH_RESOURCES := &"build_not_enough_resources"
## Deprecated (Step 2a): SD/MS build gates no longer emit this key. Kept as string id for tests only.
const KEY_BUILD_SCAN_DRONE_LIMIT := &"build_scan_drone_limit"
## Deprecated (Step 2a): MS build gates no longer emit this key. Kept as string id for tests only.
const KEY_BUILD_MINING_SHIP_LIMIT := &"build_mining_ship_limit"

const KEY_UPGRADE_NOT_ENOUGH_RESOURCES := &"upgrade_not_enough_resources"
const KEY_UPGRADE_MAX_LEVEL := &"upgrade_max_level"

const KEY_STORAGE_FULL := &"storage_full"

const KEY_COLONY_NO_SHIP := &"colony_no_ship"
const KEY_COLONY_NOT_ENOUGH_RESOURCES := &"colony_not_enough_resources"
const KEY_COLONY_SHIPYARD_REQUIRED := &"colony_shipyard_required"
const KEY_COLONY_PROTOCOL_REQUIRED := &"colony_protocol_required"
const KEY_COLONY_DEEP_SCAN_REQUIRED := &"colony_deep_scan_required"
const KEY_COLONY_ICE_SOURCE_REQUIRED := &"colony_ice_source_required"
const KEY_COLONY_FULLY_SCAN_THREE := &"colony_fully_scan_three"

const FALLBACK_SCAN_NOT_DISCOVERED := "Object not discovered"
const FALLBACK_SCAN_ALREADY_IN_PROGRESS := "Scan already in progress"
const FALLBACK_SCAN_NO_DRONE := "No scan drone available"
const FALLBACK_SCAN_NO_LAYER := "No scan layer available"

const FALLBACK_MINE_NOT_DISCOVERED := "Object not discovered"
const FALLBACK_MINE_NOT_SCANNED := "Scan required"
const FALLBACK_MINE_NO_RESOURCES := "No resources available"
const FALLBACK_MINE_DEPLETED := "Resource depleted"
const FALLBACK_MINE_NO_SHIP := "No mining ship available"
const FALLBACK_MINE_STORAGE_FULL := "Storage full"

const FALLBACK_BUILD_NOT_ENOUGH_RESOURCES := "Not enough resources"

const FALLBACK_UPGRADE_NOT_ENOUGH_RESOURCES := "Not enough resources"
const FALLBACK_UPGRADE_MAX_LEVEL := "Maximum level reached"

const FALLBACK_STORAGE_FULL := "Storage full"

const FALLBACK_COLONY_NO_SHIP := "No Colony Ship available"
const FALLBACK_COLONY_NOT_ENOUGH_RESOURCES := "Not enough resources"
const FALLBACK_COLONY_SHIPYARD_REQUIRED := "Shipyard I required"
const FALLBACK_COLONY_PROTOCOL_REQUIRED := "Colony Protocol required"
const FALLBACK_COLONY_DEEP_SCAN_REQUIRED := "Deep Scan Module required"
const FALLBACK_COLONY_ICE_SOURCE_REQUIRED := "Ice source not discovered"
const FALLBACK_COLONY_FULLY_SCAN_THREE := "Fully scan 3 objects"

@export var templates: Dictionary = {}

static var _global: GateUiTextDefinition


static func set_global(definition: GateUiTextDefinition) -> void:
	_global = definition


static func get_global() -> GateUiTextDefinition:
	return _global


static func get_text(key: StringName, fallback: String = "") -> String:
	if key == KEY_NONE or String(key).is_empty():
		return fallback
	if _global != null:
		var from_data := str(_global.templates.get(key, "")).strip_edges()
		if not from_data.is_empty():
			return from_data
	var from_fallback := _fallback_for_key(key)
	if not from_fallback.is_empty():
		return from_fallback
	return fallback


static func _fallback_for_key(key: StringName) -> String:
	match key:
		KEY_SCAN_NOT_DISCOVERED:
			return FALLBACK_SCAN_NOT_DISCOVERED
		KEY_SCAN_ALREADY_IN_PROGRESS:
			return FALLBACK_SCAN_ALREADY_IN_PROGRESS
		KEY_SCAN_NO_DRONE:
			return FALLBACK_SCAN_NO_DRONE
		KEY_SCAN_NO_LAYER:
			return FALLBACK_SCAN_NO_LAYER
		KEY_MINE_NOT_DISCOVERED:
			return FALLBACK_MINE_NOT_DISCOVERED
		KEY_MINE_NOT_SCANNED:
			return FALLBACK_MINE_NOT_SCANNED
		KEY_MINE_NO_RESOURCES:
			return FALLBACK_MINE_NO_RESOURCES
		KEY_MINE_DEPLETED:
			return FALLBACK_MINE_DEPLETED
		KEY_MINE_NO_SHIP:
			return FALLBACK_MINE_NO_SHIP
		KEY_MINE_STORAGE_FULL:
			return FALLBACK_MINE_STORAGE_FULL
		KEY_BUILD_NOT_ENOUGH_RESOURCES:
			return FALLBACK_BUILD_NOT_ENOUGH_RESOURCES
		KEY_UPGRADE_NOT_ENOUGH_RESOURCES:
			return FALLBACK_UPGRADE_NOT_ENOUGH_RESOURCES
		KEY_UPGRADE_MAX_LEVEL:
			return FALLBACK_UPGRADE_MAX_LEVEL
		KEY_STORAGE_FULL:
			return FALLBACK_STORAGE_FULL
		KEY_COLONY_NO_SHIP:
			return FALLBACK_COLONY_NO_SHIP
		KEY_COLONY_NOT_ENOUGH_RESOURCES:
			return FALLBACK_COLONY_NOT_ENOUGH_RESOURCES
		KEY_COLONY_SHIPYARD_REQUIRED:
			return FALLBACK_COLONY_SHIPYARD_REQUIRED
		KEY_COLONY_PROTOCOL_REQUIRED:
			return FALLBACK_COLONY_PROTOCOL_REQUIRED
		KEY_COLONY_DEEP_SCAN_REQUIRED:
			return FALLBACK_COLONY_DEEP_SCAN_REQUIRED
		KEY_COLONY_ICE_SOURCE_REQUIRED:
			return FALLBACK_COLONY_ICE_SOURCE_REQUIRED
		KEY_COLONY_FULLY_SCAN_THREE:
			return FALLBACK_COLONY_FULLY_SCAN_THREE
		_:
			return ""
