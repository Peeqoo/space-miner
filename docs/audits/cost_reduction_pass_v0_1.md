# Cost Reduction Pass v0.1

**Date:** 2026-06-07  
**Scope:** Lower production base costs, scaling multipliers, Storage I upgrade, and ColonyShip flat cost.  
**No gameplay gates, features, save version, or UI changes.**

**Baseline:** `docs/audits/cost_inventory_v0_1.md` (pre-reduction values)

---

## Summary

Early-game production and expansion costs reduced ~25–40% at base and via gentler scaling curves. ColonyShip remains flat / `scaling_excluded`. SD/MS/SP still use `get_scaled_production_cost()` with `production_lifetime_counts`.

---

## Production Base Costs

| Item | Resource | Old | New |
|------|----------|-----|-----|
| ScanDrone | Iron | 90 | **60** |
| MiningShip | Iron | 240 | **150** |
| MiningShip | Silicon | 40 | **25** |
| SurveyProbe | Iron | 40 | **30** |
| ColonyShip | Iron | 1500 | **900** |
| ColonyShip | Silicon | 300 | **180** |
| ColonyShip | Water | 350 | **250** |
| ColonyShip | SurveyData | 150 | **100** |

**Files:** `data/production/*.tres`

---

## Scaled Production Multipliers

| Unit | Old | New | Source |
|------|-----|-----|--------|
| ScanDrone | 1.20 | **1.12** | `GameSession.SCALED_PRODUCTION_MULT_SCAN_DRONE` |
| MiningShip | 1.25 | **1.15** | `GameSession.SCALED_PRODUCTION_MULT_MINING_SHIP` |
| SurveyProbe | 1.15 | **1.10** | `GameSession.SCALED_PRODUCTION_MULT_SURVEY_PROBE` |

**Formula unchanged:** `ceil(base_cost × multiplier^production_lifetime_count)`

---

## Storage Upgrade I

| Resource | Old | New |
|----------|-----|-----|
| Iron | 30 | **20** |
| Copper | 10 | **5** |

**File:** `data/upgrades/storage/storage_1_upgrade.tres`  
**Unchanged:** Storage II/III costs and all capacity values.

---

## New-Game Next Costs (lifetime SD=1, MS=1, SP=2)

| Unit | Cost |
|------|------|
| ScanDrone #2 | **68 Iron** |
| MiningShip #2 | **173 Iron**, **29 Silicon** |
| SurveyProbe #3 | **37 Iron** |
| ColonyShip | **900 Fe / 180 Si / 250 Water / 100 SurveyData** |
| Storage I | **20 Iron / 5 Copper** |

### After first build (lifetime +1)

| Unit | Next cost |
|------|-----------|
| ScanDrone #3 | 76 Iron |
| MiningShip #3 | 199 Iron / 34 Silicon |
| SurveyProbe #4 | 40 Iron |

---

## Unchanged Systems

- ColonyShip `build_time_seconds`, prereqs, gates
- ScanDrone / MiningShip / Storage II–III upgrades
- Sensor Pulse (5 SurveyData)
- SurveyProbe investigate cap and reward
- Scan rewards, mining rates, cargo
- `KEY_SCAN_ALREADY_IN_PROGRESS`
- `SaveManager.SAVE_VERSION = 1`
- `production_lifetime_counts` semantics

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Economy too fast | Medium | 10-min telemetry run; scaling still applies |
| ColonyShip too early | Medium | Prereqs unchanged; only resource bundle lowered |
| Legacy balance docs stale | Low | `cost_inventory_v0_1.md` superseded by this pass for values |
| `GameBalanceDefinition` dead costs still show old numbers | Low | Dead fields not used at runtime; `.tres` is source |

---

## Acceptance

1. New costs active via `get_scaled_production_cost()` and `.tres` flat reads.  
2. Telemetry `production_gates.*.cost` reflects new values.  
3. `step_2b_production_scaled_cost_smoke_test.gd` updated for new expectations.  
4. No save version bump.
