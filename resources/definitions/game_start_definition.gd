## Data-driven new-game start state (Phase 6.6f). Not used during Continue/Load.
## v0.1 start counts/resources: see `GameBalanceDefinition` (`data/balance/v0_1_balance.tres`).
class_name GameStartDefinition
extends Resource

const DEFAULT_BALANCE_PATH := "res://data/balance/v0_1_balance.tres"

@export var id: String = "default"
@export var balance_profile_path: String = DEFAULT_BALANCE_PATH

@export var start_system_id: String = "solar-system"
@export var primary_base_body_id: String = "earth"

@export var discovered_system_ids: Array[String] = []
@export var unlocked_system_ids: Array[String] = []

@export var start_resources: Dictionary = {}
@export var start_population: int = 1
@export var start_drones: int = 1
@export var start_mining_ships: int = 1
@export var start_colony_ships: int = 0
@export var start_survey_probes: int = 2
@export var start_storage_capacity: int = 1000

@export var preferred_colonization_source_base_id: String = "earth"


func load_balance_profile() -> GameBalanceDefinition:
	var path := balance_profile_path.strip_edges()
	if path.is_empty():
		path = DEFAULT_BALANCE_PATH
	var res: Resource = load(path)
	if res is GameBalanceDefinition:
		return res as GameBalanceDefinition
	push_warning("GameStartDefinition: failed to load GameBalanceDefinition from %s" % path)
	return null
