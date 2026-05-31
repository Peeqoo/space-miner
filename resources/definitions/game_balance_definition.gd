## Space Miner v0.1 — central balance profile (data-driven).
## Controllers and stores should read via `GameSession.get_game_balance()` (not magic numbers).
class_name GameBalanceDefinition
extends Resource

const VERSION_V01 := "v0.1"

## Resource ids for start resources and build costs (matches `data/planet_resources/*.tres`).
const RESOURCE_IRON := &"Iron"
const RESOURCE_SILICON := &"Silicon"
const RESOURCE_ICE := &"Ice"
const RESOURCE_SURVEY_DATA := &"SurveyData"

@export var version: String = VERSION_V01

# --- START -------------------------------------------------------------------

@export_group("Start")
@export var scan_drone_start_count: int = 1
@export var mining_ship_start_count: int = 1
@export var survey_probe_start_count: int = 2
@export var start_iron: int = 100
@export var start_silicon: int = 0
@export var start_ice: int = 0
@export var start_survey_data: int = 0
@export var start_storage_capacity: int = 1000

# --- SURVEY PROBE ------------------------------------------------------------

@export_group("Survey Probe")
@export var survey_probe_build_cost: Dictionary = {"Iron": 40}
@export var survey_probe_build_time: float = 8.0
@export var survey_probe_near_travel_time_min: float = 8.0
@export var survey_probe_near_travel_time_max: float = 15.0
@export var survey_probe_investigate_time_min: float = 15.0
@export var survey_probe_investigate_time_max: float = 25.0
@export var survey_probe_early_fail_chance: float = 0.0
@export var survey_probe_investigate_survey_data_reward: int = 5

# --- SCAN DRONE --------------------------------------------------------------

@export_group("Scan Drone")
@export var basic_scan_duration: float = 35.0
@export var deep_scan_duration: float = 85.0
@export var special_scan_duration: float = 140.0
@export var scan_drone_cooldown: float = 3.0
@export var scan_drone_near_travel_time_min: float = 10.0
@export var scan_drone_near_travel_time_max: float = 15.0
@export var scan_drone_is_consumed_on_scan: bool = false
@export var scan_basic_survey_data_reward: int = 10
@export var scan_deep_survey_data_reward: int = 25
@export var scan_special_survey_data_reward: int = 50

# --- MINING SHIP -------------------------------------------------------------

@export_group("Mining Ship")
@export var mining_ship_cargo_capacity: float = 50.0
@export var mining_ship_mining_rate: float = 1.25
@export var mining_ship_unload_rate: float = 10.0
@export var mining_ship_near_travel_time_min: float = 12.0
@export var mining_ship_near_travel_time_max: float = 18.0

# --- STORAGE -----------------------------------------------------------------

@export_group("Storage")
@export var storage_start: int = 1000
@export var storage_i: int = 1600
@export var storage_ii: int = 2600
@export var storage_iii: int = 4200

# --- UNIT BUILD COSTS (additional units) -------------------------------------

@export_group("Unit Costs")
@export var scan_drone_2_cost: Dictionary = {"Iron": 90}
@export var mining_ship_2_cost: Dictionary = {"Iron": 240, "Silicon": 40}
@export var survey_probe_unit_cost: Dictionary = {"Iron": 40}

# --- COLONY SHIP -------------------------------------------------------------

@export_group("Colony Ship")
@export var colony_ship_build_cost: Dictionary = {
	RESOURCE_IRON: 1500,
	RESOURCE_SILICON: 300,
	RESOURCE_ICE: 350,
	RESOURCE_SURVEY_DATA: 150,
}
@export var colony_ship_build_time_seconds: float = 120.0
@export var colony_ship_min_fully_scanned_objects: int = 3
## Resource ids that satisfy "ice source discovered" (includes Water deposits until Ice bodies exist).
@export var colony_ship_ice_resource_ids: PackedStringArray = ["Ice", "Water"]
## v0.1 proxies until dedicated Shipyard / Colony Protocol tech exists (see GameSession).
@export var colony_ship_shipyard_proxy_storage_upgrade_level: int = 1
@export var colony_ship_protocol_proxy_mining_ship_upgrade_level: int = 1

# --- BASE SENSOR PULSE -------------------------------------------------------

@export_group("Base Sensor Pulse")
@export var base_sensor_pulse_duration_seconds: float = 12.0
@export var base_sensor_reveal_count: int = 1
## Legacy cap; not used as a start gate in v0.1 (pulse costs Survey Data instead).
@export var base_sensor_max_visible_signals: int = 2
@export var base_sensor_reveal_tier: int = 0
@export var base_sensor_cooldown_seconds: float = 3.0
@export var base_sensor_pulse_cost: Dictionary = {RESOURCE_SURVEY_DATA: 5}

# --- CONTROL LIMITS ----------------------------------------------------------

@export_group("Control Limits")
@export var max_scan_drones_start: int = 2
@export var max_mining_ships_start: int = 2
@export var max_active_probes_start: int = 2

# --- UPGRADE EFFECTS (v0.1 reference targets) --------------------------------

@export_group("Upgrade Effects")
## Scan duration multiplier delta at tier I (e.g. -20 means 20% faster → ×0.8 duration).
@export var scan_speed_i_percent: float = -20.0
@export var mining_laser_i_percent: float = 25.0
@export var cargo_i_capacity_from: int = 50
@export var cargo_i_capacity_to: int = 75
@export var thrusters_i_percent: float = 20.0
@export var storage_i_capacity_from: int = 1000
@export var storage_i_capacity_to: int = 1600


func build_start_resources_dictionary() -> Dictionary:
	return {
		RESOURCE_IRON: start_iron,
		RESOURCE_SILICON: start_silicon,
		RESOURCE_ICE: start_ice,
		RESOURCE_SURVEY_DATA: start_survey_data,
	}


func get_storage_capacity_for_upgrade_level(level: int) -> int:
	match clampi(level, 0, 3):
		0:
			return storage_start
		1:
			return storage_i
		2:
			return storage_ii
		_:
			return storage_iii


func get_scan_duration_for_layer(layer: int) -> float:
	match layer:
		ScannedResourceEntry.Layer.DEEP:
			return deep_scan_duration
		ScannedResourceEntry.Layer.SPECIAL:
			return special_scan_duration
		_:
			return basic_scan_duration


func get_scan_survey_data_reward_for_state(scan_state: StringName) -> int:
	match String(scan_state).strip_edges():
		ObjectScanStore.SCAN_DEEP:
			return maxi(0, scan_deep_survey_data_reward)
		ObjectScanStore.SCAN_SPECIAL:
			return maxi(0, scan_special_survey_data_reward)
		ObjectScanStore.SCAN_BASIC:
			return maxi(0, scan_basic_survey_data_reward)
		_:
			return 0


func get_survey_probe_investigate_survey_data_reward() -> int:
	return maxi(0, survey_probe_investigate_survey_data_reward)


func get_unit_build_cost(cost_key: StringName) -> Dictionary:
	match cost_key:
		&"scan_drone_2":
			return scan_drone_2_cost.duplicate(true)
		&"mining_ship_2":
			return mining_ship_2_cost.duplicate(true)
		&"survey_probe":
			return survey_probe_unit_cost.duplicate(true)
		_:
			return {}


func get_scan_speed_i_duration_multiplier() -> float:
	return 1.0 + (scan_speed_i_percent / 100.0)


func get_mining_laser_i_rate_multiplier() -> float:
	return 1.0 + (mining_laser_i_percent / 100.0)


func get_thrusters_i_travel_multiplier() -> float:
	return 1.0 + (thrusters_i_percent / 100.0)
