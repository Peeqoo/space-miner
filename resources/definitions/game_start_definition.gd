## Data-driven new-game start state (Phase 6.6f). Not used during Continue/Load.
class_name GameStartDefinition
extends Resource

@export var id: String = "default"

@export var start_system_id: String = "solar-system"
@export var primary_base_body_id: String = "earth"

@export var discovered_system_ids: Array[String] = []
@export var unlocked_system_ids: Array[String] = []

@export var start_resources: Dictionary = {}
@export var start_population: int = 1
@export var start_drones: int = 1
@export var start_mining_ships: int = 1
@export var start_colony_ships: int = 0

@export var preferred_colonization_source_base_id: String = "earth"
