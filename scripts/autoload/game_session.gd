## Global game session facade.
## Keeps the public API stable and delegates state to stores.
extends Node

const DEFAULT_SYSTEM_PATH := "res://data/galaxy_systems/solar_system.tres"
const START_SYSTEM_ID: String = "solar-system"

const SCAN_UNKNOWN := ObjectScanStore.SCAN_UNKNOWN
const SCAN_BASIC := ObjectScanStore.SCAN_BASIC
const SCAN_DEEP := ObjectScanStore.SCAN_DEEP
const SCAN_SPECIAL := ObjectScanStore.SCAN_SPECIAL

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


# --------------------------------------------------
# Lifecycle
# --------------------------------------------------

func _ready() -> void:
	ensure_default_system_loaded()


# --------------------------------------------------
# Boot State
# --------------------------------------------------

func ensure_boot_state() -> void:
	ensure_default_system_loaded()

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
# Object Scan State
# --------------------------------------------------

func set_object_scan_state(system_id: String, object_id: String, scan_state: String) -> void:
	object_scans.set_object_scan_state(system_id, object_id, scan_state)


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


func add_base_resource(base_id: String, resource_id: String, amount: int) -> void:
	bases.add_resource(base_id, resource_id, amount)


func spend_base_resource(base_id: String, resource_id: String, amount: int) -> bool:
	return bases.spend_resource(base_id, resource_id, amount)


func get_base_population(base_id: String) -> int:
	return bases.get_population(base_id)


func get_base_drone_count(base_id: String) -> int:
	return bases.get_drone_count(base_id)


func get_base_mining_ship_count(base_id: String) -> int:
	return bases.get_mining_ship_count(base_id)


func build_base_drone(base_id: String) -> bool:
	return bases.build_drone(base_id)


func build_base_mining_ship(base_id: String) -> bool:
	return bases.build_mining_ship(base_id)


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
