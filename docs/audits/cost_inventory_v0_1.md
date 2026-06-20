# Cost Inventory v0.1

**Date:** 2026-06-07  
**Godot:** 4.6.1 / strictly typed GDScript  
**Scope:** Read-only audit — all resource costs and spends in the current codebase.

> **Updated:** Values reflect **Cost Reduction Pass v0.2** (`docs/audits/cost_reduction_pass_v0_2.md`). v0.1 in `cost_reduction_pass_v0_1.md`.

**Related docs:** `cost_reduction_pass_v0_2.md`, `cost_reduction_pass_v0_1.md`, `unlimited_production_multi_unit_target_plan_v0_1.md`, `stale_production_limit_cleanup_v0_1.md`

---

## Summary

### Systems that cost resources

| System | Spend type | Active? |
|--------|------------|---------|
| **Production build** — ScanDrone, MiningShip, SurveyProbe | Scaled resource spend | **Yes** |
| **Production build** — ColonyShip | Flat resource spend | **Yes** |
| **Upgrades** — storage, scan_drone, mining_ship tiers | Flat per-tier `.tres` cost | **Yes** |
| **Base Sensor Pulse** | SurveyData spend | **Yes** |
| **SurveyProbe Investigate** | Consumes 1 probe **unit** (no extra iron at launch) | **Yes** |
| **Colonization operation** | Consumes 1 ColonyShip **unit** (built separately) | **Yes** |
| **ScanDrone scan** (basic/deep) | Time + unit only | **No resource spend** |
| **MiningShip mining** | Time + unit only | **No resource spend** |
| **Galaxy travel / system unlock** | Progression flags only | **No resource spend** |
| **Establish base (colonization complete)** | Start kit applied to new body | **Not a player spend** |

### Flat vs scaled

| Category | Flat | Scaled |
|----------|------|--------|
| ScanDrone build | Base cost in `.tres` | **Runtime:** `ceil(base × 1.12^lifetime_count)` |
| MiningShip build | Base cost in `.tres` | **Runtime:** `ceil(base × 1.12^lifetime_count)` |
| SurveyProbe build | Base cost via `.tres` / balance fallback | **Runtime:** `ceil(base × 1.10^lifetime_count)` |
| ColonyShip build | Flat from `.tres` (primary) | **Excluded** (`scaling_excluded: true`) |
| All upgrades | Flat from `data/upgrades/**/*.tres` | No |
| Sensor Pulse | Flat from `v0_1_balance.tres` | No |

**Scaling index:** `production_lifetime_counts[production_id]` on each base — incremented on successful `build_*`, initialized from fleet counts on new game / lazy migrate. **Investigate consume does not change lifetime count** (only owned `survey_probes` count).

**Multipliers:** Hardcoded in `GameSession`: SD `1.12`, MS `1.12`, SP `1.10`.

### Legacy / dead costs

| Artifact | Status |
|----------|--------|
| `GameBalanceDefinition.scan_drone_2_cost` / `mining_ship_2_cost` / `survey_probe_unit_cost` | **Dead** — `get_unit_build_cost()` has no script callers |
| `max_scan_drones_start` / `max_mining_ships_start` | **Legacy reference** — telemetry `balance_reference_max_count` only |
| `KEY_BUILD_SCAN_DRONE_LIMIT` / `KEY_BUILD_MINING_SHIP_LIMIT` | **Deprecated** — not emitted by build gates |
| `GameBalanceDefinition.storage_i/ii/iii` numeric exports | **Capacity reference** — upgrade **prices** live in upgrade `.tres` |

### Prereqs / gates without spend

| Gate | Blocks | Spend? |
|------|--------|--------|
| ColonyShip build | Deep Scan Module, Shipyard I (Storage I proxy), Colony Protocol (MS I proxy), ice source, 3× deep-scanned objects | Resources only after prereqs met |
| Scan launch | Discovery, layer, idle drone, `KEY_SCAN_ALREADY_IN_PROGRESS` | No |
| Mine launch | Scan state, depletion, idle ship, storage | No |
| Investigate | Signal state, per-object in progress, global probe cap (2), owned probe | Probe unit only |
| SD/MS build | Resources only (no hard cap) | Yes when built |

---

## Production Costs

### Master table

| Item | Cost Source | Base Cost | Actual Runtime Cost | Scaling? | Formula | Used By | Notes |
|------|-------------|-----------|---------------------|----------|---------|---------|-------|
| **ScanDrone** | `data/production/scan_drone.tres` | Iron: 50 | `get_scaled_production_cost("scan_drone")` | **Yes** | `ceil(50 × 1.12^n)` | `BaseStore.build_drone`, gates, `ProductionPanel`, telemetry | `n` = `production_lifetime_counts.scan_drone` |
| **MiningShip** | `data/production/mining_ship.tres` | Iron: 120, Silicon: 20 | `get_scaled_production_cost("mining_ship")` | **Yes** | per-resource `ceil(base × 1.12^n)` | `BaseStore.build_mining_ship`, gates, UI, telemetry | |
| **SurveyProbe** | `.tres` + `get_survey_probe_build_cost()` | Iron: 30 | `get_scaled_production_cost("survey_probe")` | **Yes** | `ceil(30 × 1.10^n)` | `BaseStore.build_survey_probe`, gates, UI, telemetry | Base read: `.tres` first, then `balance.survey_probe_build_cost` |
| **ColonyShip** | `data/production/colony_ship.tres` | Water: 250, Iron: 900, Silicon: 180, SurveyData: 100 | Same (flat) | **No** | flat | `BaseStore.build_colony_ship`, `get_colony_ship_build_cost()`, telemetry | `build_time_seconds`: 120; not scaled |

**Spend path:** `BaseStore._get_scaled_automation_build_cost()` → `GameSession.get_scaled_production_cost()` → `spend_cost()` on build (SD/MS/SP). ColonyShip uses `get_production_cost()` directly (flat).

### New Game starting state (`default_start.tres` + balance)

| Field | Value |
|-------|-------|
| Start resources | Iron: **100**, Silicon: 0, Ice: 0, SurveyData: 0 (`build_start_resources_dictionary`) |
| Fleet | 1 ScanDrone, 1 MiningShip, **2** SurveyProbes, 0 ColonyShip |
| `production_lifetime_counts` (derived) | SD: 1, MS: 1, SP: **2**, CS: 0 |
| Storage capacity | 1000 |

**First purchasable unit costs after New Game** (code formula; confirmed by `step_2b_production_scaled_cost_smoke_test.gd`):

| Unit | Next build cost |
|------|-----------------|
| ScanDrone #2 | **56 Iron** |
| MiningShip #2 | **135 Iron**, **23 Silicon** |
| SurveyProbe #3 | **37 Iron** |

### Scaled cost examples (`lifetime_count` = n)

Formula: `ceil(base_amount × multiplier^n)` per resource key.

#### ScanDrone (base Iron 50, ×1.12)

| n | Iron |
|---|------|
| 0 | 50 |
| 1 | **56** |
| 2 | 63 |
| 3 | 70 |
| 4 | 79 |
| 5 | 88 |

#### MiningShip (base Iron 120 / Silicon 20, ×1.12)

| n | Iron | Silicon |
|---|------|---------|
| 0 | 120 | 20 |
| 1 | **135** | **23** |
| 2 | 151 | 26 |
| 3 | 169 | 29 |
| 4 | 189 | 33 |
| 5 | 212 | 37 |

#### SurveyProbe (base Iron 30, ×1.10)

| n | Iron |
|---|------|
| 0 | 30 |
| 1 | 34 |
| 2 | **37** |
| 3 | 40 |
| 4 | 44 |
| 5 | 49 |

#### ColonyShip (flat, n ignored)

| | Water | Iron | Silicon | SurveyData |
|---|-------|------|---------|------------|
| Any n | 250 | 900 | 180 | 100 |

---

## Upgrade Costs

**Source:** `data/upgrades/**/*.tres` via `UpgradeCatalog` → `BaseStore.buy_next_upgrade()` → `spend_cost(upgrade_definition.cost)`.

**Not in balance `.tres`:** Upgrade prices are **only** in upgrade `.tres` files. `GameBalanceDefinition.storage_i/ii/iii` define **capacity targets**, not upgrade prices.

### ScanDrone upgrades

| Upgrade ID | Category | Level | Cost | Unlock / Effect | Source File |
|------------|----------|-------|------|-----------------|-------------|
| `scan_drone_0_base` | scan_drone | 0 | *(none — not purchasable)* | Basic scan, +2% mining support/drone | `scan_drone_0_base.tres` |
| `scan_drone_1_upgrade` | scan_drone | 1 | Copper: 15, Iron: 20 | Deep scan layer, scan ×0.8 duration | `scan_drone_1_upgrade.tres` |
| `scan_drone_2_upgrade` | scan_drone | 2 | Aluminium: 15, Copper: 25, Iron: 35 | Scan ×0.5 duration, +3% support bonus | `scan_drone_2_upgrade.tres` |

### MiningShip upgrades

| Upgrade ID | Category | Level | Cost | Unlock / Effect | Source File |
|------------|----------|-------|------|-----------------|-------------|
| `mining_ship_0_base` | mining_ship | 0 | *(none)* | Basic mining | `mining_ship_0_base.tres` |
| `mining_ship_1_upgrade` | mining_ship | 1 | Copper: 10, Iron: 40, Silicon: 20 | Deep mining, rate ×1.25, cargo 150% | `mining_ship_1_upgrade.tres` |
| `mining_ship_2_upgrade` | mining_ship | 2 | Aluminium: 35, Copper: 15, Hydrogen: 10, Iron: 60 | Cargo 150%, deep layer (no extra rate in data) | `mining_ship_2_upgrade.tres` |

### Storage upgrades

| Upgrade ID | Category | Level | Cost | Capacity | Source File |
|------------|----------|-------|------|----------|-------------|
| `storage_0_base` | storage | 0 | *(none)* | 1000 units | `storage_0_base.tres` |
| `storage_1_upgrade` | storage | 1 | Copper: 5, Iron: 20 | 1600 | `storage_1_upgrade.tres` |
| `storage_2_upgrade` | storage | 2 | Copper: 25, Iron: 50 | 2600 | `storage_2_upgrade.tres` |
| `storage_3_upgrade` | storage | 3 | Copper: 50, Iron: 100 | 4200 | `storage_3_upgrade.tres` |

### Other upgrade categories

**None** in `data/upgrades/` beyond scan_drone, mining_ship, storage (10 `.tres` files total).

### Upgrade cost totals (purchasable tiers only)

| Category | Total Iron | Other resources |
|----------|------------|-----------------|
| ScanDrone I+II | 55 | Copper 40, Aluminium 15 |
| MiningShip I+II | 100 | Silicon 20, Copper 25, Aluminium 35, Hydrogen 10 |
| Storage I–III | 170 | Copper 80 |

---

## ColonyShip / Expansion Costs

| System | Cost / Requirement | Resource Cost | Prereq? | Spend? | Source |
|--------|--------------------|---------------|---------|--------|--------|
| **ColonyShip build** | Flat production cost | Water 250, Iron 900, Silicon 180, SurveyData 100 | **Yes** (5 gates) | **Yes** — `spend_cost` on build | `colony_ship.tres`, `BaseStore.build_colony_ship` |
| **Deep Scan Module** | ScanDrone upgrade level ≥ 1 | — | Gate only | No (upgrade paid separately) | `GameSession.has_colony_ship_deep_scan_module_for_base` |
| **Shipyard I** | Storage upgrade level ≥ 1 | — | Gate proxy | No | `colony_ship_shipyard_proxy_storage_upgrade_level` |
| **Colony Protocol** | MiningShip upgrade level ≥ 1 | — | Gate proxy | No | `colony_ship_protocol_proxy_mining_ship_upgrade_level` |
| **Ice source discovered** | Known object with Ice/Water in scan | — | Gate | No | `has_discovered_ice_source` |
| **Fully scan 3 objects** | ≥3 objects at Deep scan state | — | Gate | No | `colony_ship_min_fully_scanned_objects` (= 3) |
| **Colonization operation** | 1 ColonyShip in fleet | — | Must own ship | **Consumes** 1 colony ship unit (no extra resources) | `start_colonization_operation` → `consume_colony_ships` |
| **New colony base** | Start kit on establish | Grants population/units/resources | — | **Not a spend** — `apply_start_kit_to_base` | `GameSession.establish_base_at_body` |
| **Galaxy system unlock / travel** | `unlocked_system_ids` | — | Progression | No resource spend | `GameSession.unlock_system` |
| **Establish Earth (new game)** | Start kit | 100 Iron, 1 SD, 1 MS, 2 SP | — | N/A | `reset_for_new_game` |

**ColonyShip gate order:** First unmet prereq key wins (`get_colony_ship_build_prerequisite_blocked_reason_key`), then resource check (`KEY_COLONY_NOT_ENOUGH_RESOURCES`).

---

## SensorPulse / Scan / Investigate Costs

| Action | Cost | Consumes Unit? | Resource Spend? | Source | Notes |
|--------|------|----------------|-----------------|--------|-------|
| **Base Sensor Pulse** | SurveyData: **5** | No | **Yes** — `spend_cost` at pulse start | `v0_1_balance.tres` → `base_sensor_pulse_cost`; `base_sensor_pulse_controller.gd` | Refund on cancel path exists |
| **SurveyProbe Investigate** | None at launch | **Yes** — 1 SurveyProbe | Indirect (probe was built with scaled Iron) | `survey_probe_mission_controller.gd` → `consume_survey_probe` | Reward: +5 SurveyData (`survey_probe_investigate_survey_data_reward`) |
| **SurveyProbe build** | Scaled Iron | Adds unit | **Yes** | `build_survey_probe` | Separate from investigate |
| **ScanDrone Basic/Deep scan** | None | No (drone returns to support orbit) | **No** | `launch_scan_drone` | Time: 35s / 85s base durations × upgrade multiplier |
| **Scan completion reward** | — | — | **Income** +10 / +25 / +50 SurveyData | `grant_scan_survey_data_reward` | Not a cost |
| **MiningShip launch / mine** | None | No | **No** | `launch_mining_ship` | Cargo → base storage on unload |
| **Scan probe / sensor item** | — | — | — | — | **Not implemented** as separate spend |

---

## Storage / Capacity Costs

| Item | Cost | Effect | Source |
|------|------|--------|--------|
| Storage Upgrade I | Copper 10, Iron 30 | 1000 → 1600 capacity | `storage_1_upgrade.tres` |
| Storage Upgrade II | Copper 25, Iron 50 | 1600 → 2600 | `storage_2_upgrade.tres` |
| Storage Upgrade III | Copper 50, Iron 100 | 2600 → 4200 | `storage_3_upgrade.tres` |
| New game base storage | — | 1000 (level 0) | `storage_0_base.tres` / `start_storage_capacity` |

**No hidden storage expansion costs** beyond upgrade tiers. Storage-full blocks mining unload (`KEY_MINE_STORAGE_FULL`) but does not auto-charge resources.

---

## Resource Spend Functions

| File | Function | What it spends | Used for |
|------|----------|----------------|----------|
| `base_store.gd` | `spend_cost(base_id, cost)` | Multi-resource dict | **Central spend** — production, upgrades |
| `base_store.gd` | `spend_resource(base_id, resource_id, amount)` | Single resource | Called by `spend_cost` |
| `base_store.gd` | `remove_resource(base_id, resource_id, amount)` | Single resource (partial ok) | `GameSession.remove_base_resource` / discard |
| `base_store.gd` | `build_drone` | Scaled SD cost | Production |
| `base_store.gd` | `build_mining_ship` | Scaled MS cost | Production |
| `base_store.gd` | `build_survey_probe` | Scaled SP cost | Production |
| `base_store.gd` | `build_colony_ship` | Flat CS cost | Production |
| `base_store.gd` | `buy_next_upgrade` | `upgrade_definition.cost` | Upgrade panel |
| `base_store.gd` | `consume_survey_probe` | −1 `survey_probes` count | Investigate (unit, not iron) |
| `base_store.gd` | `consume_colony_ships` | −1 `colony_ships` count | Colonization launch |
| `game_session.gd` | `spend_base_resource` | Single resource | Generic API |
| `game_session.gd` | `remove_base_resource` / `discard_base_resource` | Single resource | Dev / discard flows |
| `base_sensor_pulse_controller.gd` | `_spend_pulse_cost` | SurveyData (5) | Sensor pulse |
| `game_session.gd` | `start_colonization_operation` | 1 colony ship unit | Via `consume_colony_ships` |

**Not spends:** `add_base_resource`, `grant_scan_survey_data_reward`, mining extraction → storage, colonization start kit grant.

---

## Legacy / Dead Costs

| Artifact | Location | Current Status | Recommendation |
|----------|----------|----------------|----------------|
| `scan_drone_2_cost` | `game_balance_definition.gd` | Duplicate of `.tres` base; **no callers** | Mark legacy; remove only with `get_unit_build_cost` audit |
| `mining_ship_2_cost` | Same | **Dead** | Same |
| `survey_probe_unit_cost` | Same | **Dead** | Same |
| `survey_probe_build_cost` | `game_balance_definition.gd` | **Fallback** if `.tres` missing; `.tres` wins today | Keep as fallback |
| `colony_ship_build_cost` | `game_balance_definition.gd` | **Fallback** if `.tres` missing; `.tres` wins today | Keep |
| `get_unit_build_cost()` | `game_balance_definition.gd` | **Zero script references** | Dead API |
| `max_scan_drones_start` / `max_mining_ships_start` | Balance + `get_max_*_count()` | Telemetry reference only | Keep for balance archaeology |
| `KEY_BUILD_SCAN_DRONE_LIMIT` / `KEY_BUILD_MINING_SHIP_LIMIT` | `gate_ui_text_definition.gd` | Deprecated; smoke tests only | Keep for tests |
| `build_scan_drone_limit` / `build_mining_ship_limit` strings | Removed from `gate_ui_texts.tres` | **Not UI-facing** | OK |
| `GameBalanceDefinition` `storage_i/ii/iii` | Balance exports | Capacity numbers; **not** upgrade prices | Do not confuse with upgrade costs |
| `SCALED_PRODUCTION_MULT_*` in `game_session.gd` | Code constants | **Active** but not data-driven | Future: move to `.tres` when balancing |

---

## Cost Pressure Notes

*Assessment only — no value changes in this audit.*

### Likely bottlenecks

| Phase | Pressure |
|-------|----------|
| **Early game** | 100 Iron start vs MS #2 (**173 Iron + 29 Silicon**) and SD #2 (**68 Iron**); Silicon gated until mining |
| **Mid game** | Upgrade tiers require **Copper / Aluminium / Hydrogen** (mined resources) stacked on top of scaled production |
| **MS3+** | Iron **469+** and Silicon **79+** at `n=3`; exponential curve |
| **ColonyShip** | **900 Iron + 180 Silicon + 250 Water + 100 SurveyData** flat — largest single bundle |
| **Storage** | Iron **180** total across 3 tiers + Copper **85** — competes with fleet scaling |

### Priority for future reduction (recommendation only)

| Priority | Targets | Why |
|----------|---------|-----|
| **A — reduce first** | Further MS/SD scaling tuning if still slow; ColonyShip bundle already reduced v0.1 | Post 10-min telemetry |
| **B — observe in 10-min telemetry** | SurveyProbe scaling; ScanDrone II upgrade; Sensor Pulse SurveyData (5); MiningShip II upgrade | Secondary curves; reward loops may offset |
| **C — keep for now** | ColonyShip prereqs (non-monetary); investigate probe cap; scan/mine time costs; `max_active_probes_start` | Gameplay structure, not direct resource sinks |

---

## Reference Search Notes

Repo search (2026-06-07) for production-limit and cost terms:

- `KEY_BUILD_SCAN_DRONE_LIMIT` / `KEY_BUILD_MINING_SHIP_LIMIT`: definition + smoke tests only; **not** in `BaseStore` gates.
- `max_count` in scripts: **removed** from telemetry; replaced by `balance_reference_max_count`.
- `get_scaled_production_cost`: active for SD/MS/SP build spend and telemetry `production_gates.*.cost`.
- `production_lifetime_counts`: save-v1 field on base; source of scaling exponent.

---

## Acceptance

1. Only `docs/audits/cost_inventory_v0_1.md` created.  
2. No code changes.  
3. No `.tres` changes.  
4. All production costs listed with flat/scaled distinction.  
5. All upgrade costs listed from `data/upgrades/**`.  
6. SensorPulse, Investigate, ColonyShip, Storage audited.  
7. Legacy/dead costs marked.  
8. Scaled SD/MS/SP example tables included; New Game next-cost values match code/smoke tests.  
9. ColonyShip marked flat / `scaling_excluded`.  
10. `tooltip_text` remains 0 in project.
