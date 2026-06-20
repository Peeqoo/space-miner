# Cost Reduction Pass v0.2

**Date:** 2026-06-20  
**Scope:** Early-game MS #2 / SD #2 tuning after 10-min smoke (`cost_reduction_10min_smoke_v0_1.md`).  
**No gate, feature, save, SP, or ColonyShip cost changes.**

**Prior:** `cost_reduction_pass_v0_1.md`

---

## Summary

v0.1 lowered costs globally; 10-min smoke showed **MS #2 and SD #2 still Iron-blocked** (3 Fe @ min 10, Silicon plentiful). v0.2 targets **ScanDrone + MiningShip base costs and MS scaling only**.

---

## Changes (v0.1 → v0.2)

### Production base costs

| Item | Resource | v0.1 | v0.2 |
|------|----------|------|------|
| ScanDrone | Iron | 60 | **50** |
| MiningShip | Iron | 150 | **120** |
| MiningShip | Silicon | 25 | **20** |
| SurveyProbe | Iron | 30 | *unchanged* |
| ColonyShip | all | flat | *unchanged* |

**Files:** `data/production/scan_drone.tres`, `data/production/mining_ship.tres`

### Scaled multipliers (`game_session.gd`)

| Unit | v0.1 | v0.2 |
|------|------|------|
| ScanDrone | 1.12 | **1.12** (unchanged) |
| MiningShip | 1.15 | **1.12** |
| SurveyProbe | 1.10 | **1.10** (unchanged) |

**Formula unchanged:** `ceil(base × multiplier^production_lifetime_count)`

---

## New-Game next costs (lifetime SD=1, MS=1, SP=2)

| Unit | Cost |
|------|------|
| ScanDrone #2 | **56 Iron** |
| MiningShip #2 | **135 Iron**, **23 Silicon** |
| SurveyProbe #3 | **37 Iron** (unchanged) |
| ColonyShip | **900 / 180 / 250 / 100** (unchanged) |

### After first build (lifetime +1)

| Unit | Next cost |
|------|-----------|
| ScanDrone #3 | 63 Iron |
| MiningShip #3 | 151 Iron / 26 Silicon |

---

## Unchanged

- `survey_probe.tres`, `colony_ship.tres`
- Storage I/II/III upgrade costs
- ScanDrone / MiningShip / Storage upgrade tiers (except production bases)
- Sensor Pulse (5 SurveyData)
- All gates, `KEY_SCAN_ALREADY_IN_PROGRESS`, investigate cap
- `SaveManager.SAVE_VERSION = 1`

---

## Risk

| Risk | Mitigation |
|------|------------|
| MS #2 reachable much earlier | Intended; re-run 10-min smoke when needed |
| SD #2 easier | Lower base + same multiplier |
| Mid-game MS curve flatter (1.12 vs 1.15) | Monitor telemetry `built_count` ≥ 3 |

---

## Acceptance

- Step 2b smoke: SD 56, MS 135/23, SP 37, CS flat unchanged
- `get_scaled_production_cost()` remains single source of truth
