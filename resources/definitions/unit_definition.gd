## Data-driven automation unit balancing (Phase 6.6e).
## v0.1 canonical numbers live in `GameBalanceDefinition` (`data/balance/v0_1_balance.tres`).
class_name UnitDefinition
extends Resource

@export var id: String = ""
@export var unit_key: String = ""

## Legacy single duration; prefer layer durations + `GameSession.get_game_balance()` when wired.
@export var scan_duration_seconds: float = 0.0
@export var basic_scan_duration_seconds: float = 0.0
@export var deep_scan_duration_seconds: float = 0.0
@export var special_scan_duration_seconds: float = 0.0
@export var scan_cooldown_seconds: float = 0.0
@export var near_travel_time_min: float = 0.0
@export var near_travel_time_max: float = 0.0
@export var is_consumed_on_scan: bool = false

@export var mining_cargo_capacity: int = 0
@export var mining_rate_per_second: float = 0.0
@export var mining_unload_duration_seconds: float = 0.0
@export var mining_unload_rate: float = 0.0
