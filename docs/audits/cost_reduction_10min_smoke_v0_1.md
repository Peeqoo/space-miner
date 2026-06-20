# Cost Reduction 10-Minute Smoke v0.1

**Date:** 2026-06-20  
**Godot:** 4.6.1 (headless debug build)  
**Scope:** Post Cost Reduction Pass v0.1 — 600 s automated economy run with `BalanceTelemetryLogger`.  
**No gameplay/cost/gate changes in this audit.**

**Telemetry file:** `user://balance_runs/cost_reduction_10min_v0_1_2026_06_20_120820.json`  
**Runner:** `scripts/debug/smoke_tests/cost_reduction_10min_smoke_runner.tscn` (debug-only headless automation)

---

## Verdict: **PASS WITH NOTES**

| Area | Result |
|------|--------|
| A — Early production / scaled costs in telemetry | **PASS** — costs match v0.1 reduction; SP #3 early; SD/MS #2 **not reached** in 10 min |
| B — Scaling / telemetry gates | **PASS** |
| C — Mining loop | **PASS WITH NOTES** — mining + delivery observed; UI/panel not exercised here |
| D — ColonyShip pressure | **PASS** — prereqs block; not trivial |
| E — Storage I | **PASS WITH NOTES** — bought ~42 s; very affordable |
| F — Telemetry fields | **PASS** |

---

## Test Setup

- `GameSession.reset_for_new_game()` → load `system_scene.tscn`
- `BalanceTelemetryLogger.start_run("cost_reduction_10min_v0_1")`
- Automated economy tick every 2 s: builds, upgrades, sensor pulse, investigate, scan, mine (priority order)
- Duration: **600.0 s** wall clock
- Smoke overall: **PASS** (0 failures; baseline cost assertions at t≈0)

**Limitations (NOTES):**

- Headless **scripted** player — not manual UI play; `ProductionPanel` hover not visually checked (costs verified via `get_scaled_production_cost` + telemetry JSON).
- `BaseManagementPanel` auto-open on unload **not re-tested** in this run (separate smoke: `base_panel_unload_smoke_test.gd` — prior **PASS**).
- **Multi-MS same target** not exercised — fleet stayed at **1 MS** (MS #2 never affordable on Iron).
- No `first_basic_scan_done` milestone — automation did not complete a basic scan in 10 min (SD busy / gate / target selection).

---

## Timeline (minute 0–10)

| Minute | Iron | Silicon | SD | MS | SP (owned) | Storage used/cap | Notes |
|--------|------|---------|----|----|------------|------------------|-------|
| 0 | 100 | 0 | 1 | 1 | 2 | 100/1000 | New game baseline |
| 1 | 3 | 10 | 1 | 1 | 0 | 43/1600 | Storage I purchased (~42 s); probes consumed |
| 2 | 3 | 30 | 1 | 1 | 0 | 118/1600 | Mining active; Si rising |
| 3 | 3 | 50 | 1 | 1 | 0 | 198/1600 | |
| 4 | 3 | 70 | 1 | 1 | 0 | 278/1600 | |
| 5 | 3 | 85 | 1 | 1 | 0 | 338/1600 | |
| 6 | 3 | 100 | 1 | 1 | 0 | 398/1600 | |
| 7 | 3 | 115 | 1 | 1 | 0 | 458/1600 | |
| 8 | 3 | 130 | 1 | 1 | 0 | 518/1600 | |
| 9 | 3 | 145 | 1 | 1 | 0 | 579/1600 | |
| 10 | 3 | 170 | 1 | 1 | 0 | 678/1600 | 1 MS mining Venus; Iron-starved |

### Milestone times (telemetry + smoke tracker)

| Event | Time (s) |
|-------|----------|
| First signal revealed | 2.0 |
| SurveyProbe built (lifetime → 3) | 4.0 |
| SurveyProbe count 3 (smoke) | 6.0 |
| Sensor pulse used | 24.1 |
| First mining started | 26.1 |
| Storage Upgrade I bought | 42.1 |
| First delivery (unload) | 44.1 |
| First object revealed (investigate) | 44.1 |
| Run end | 600.0 |

### Not reached in 10 min

| Target | Status |
|--------|--------|
| **SD #2** (68 Iron) | **Not built** — Iron ≈3; gate shows 65 missing |
| **MS #2** (173 Fe / 29 Si) | **Not built** — **blocked by Iron**, not Silicon (170 Si @ min 10) |
| **SP #3 build** (37 Iron at start) | **Built ~4–6 s** (then more probes to lifetime 4) |
| ScanDrone Upgrade I | Not bought (Iron) |
| MiningShip Upgrade I | Not bought (Iron) |
| ColonyShip build | Blocked by prereqs + resources |
| Storage full | No |
| Multi-MS same target | N/A (1 MS only) |

---

## A — Early Production

### New scaled costs (telemetry @ minute 10)

| Unit | `production_gates.*.cost` | Expected | Match |
|------|---------------------------|----------|-------|
| ScanDrone | Iron **68** | 68 | ✓ |
| MiningShip | Iron **173**, Silicon **29** | 173 / 29 | ✓ |
| SurveyProbe | Iron **44** (lifetime 4) | 37 @ n=2; 44 @ n=4 | ✓ (scaling) |
| ColonyShip | 900 / 180 / 250 / 100 | flat | ✓ |

### SD #2 / MS #2 / SP #3

- **SP #3:** Reachable **very early** (~4–6 s) — automation built 3rd probe quickly after start.
- **SD #2:** **Not reachable** in this 10 min run — Iron spent on probes + Storage I + mining lag; only **3 Iron** left at end while next SD costs **68**.
- **MS #2:** **Blocked by Iron** (173 needed, 3 have); **Silicon not the bottleneck** (170 available). Confirms reduced Si cost (29) is affordable once Iron flows.

### ProductionPanel

Not visually inspected. Runtime source unchanged: `GameSession.get_scaled_production_cost()` via `production_panel.gd` — telemetry `used_for_gameplay: true` and gate `cost` fields match.

---

## B — Scaling

| Check | Result |
|-------|--------|
| `production_lifetime_counts` increment on build | ✓ SP lifetime 2→4 over run |
| SD lifetime | 1 (no second build) |
| MS lifetime | 1 |
| `production_gates.*.scaled_preview.multiplier` | SD 1.12, MS 1.15, SP 1.10 |
| `build_hard_limit_active` (SD/MS) | **false** throughout JSON |
| `balance_reference_max_count` | Present (diagnostic only) |
| `colony_ship.scaling_excluded` | **true** |
| `SAVE_VERSION` | **1** (smoke baseline check) |

---

## C — Mining Loop

| Check | Result |
|-------|--------|
| Mining started | ✓ 26.1 s |
| First unload/delivery | ✓ 44.1 s |
| Active mining @ min 10 | 1 ship on **venus**, status `mining` |
| Storage waiting | 0 |
| BaseManagementPanel auto-open | **Not tested** (see separate smoke) |
| Multi-MS same target | **Not tested** (1 MS fleet) |

---

## D — ColonyShip Pressure

@ minute 10 (`colony_ship` gate):

| Prereq | Met |
|--------|-----|
| Deep Scan Module | **No** |
| Shipyard I (Storage I proxy) | **Yes** (after ~42 s) |
| Colony Protocol (MS I proxy) | **No** |
| Ice/Water source | **Yes** |
| 3 deep-scanned objects | **No** |

**Blocked reason key:** `colony_deep_scan_required` (not resource-only).

**Affordability:** Iron 3/900, Si 170/180, Water 0/250, SurveyData 0/100 — **not affordable**, but prereqs would block even with cheats.

**Conclusion:** ColonyShip is **cheaper on paper** (900 Fe vs 1500) but **not trivial** — upgrade + scan progression gates intact.

---

## E — Storage

| Item | Result |
|------|--------|
| Storage I (20 Fe / 5 Cu) | Bought **~42 s** — affordable after initial mining/investigate |
| Capacity | 1000 → **1600** |
| Too cheap? | **NOTE:** Early buy may compete with SD/MS #2 Iron in aggressive probe-heavy play |
| Storage full @ 10 min | **No** (678/1600) |

---

## F — Telemetry Field Check (@ minute 10)

| Field | Value / status |
|-------|----------------|
| `production_gates.scan_drone.cost` | `{Iron: 68}` |
| `production_gates.mining_ship.cost` | `{Iron: 173, Silicon: 29}` |
| `production_gates.survey_probe.cost` | `{Iron: 44}` |
| `production_gates.colony_ship.scaling_excluded` | `true` |
| `units.scan_drone.build_hard_limit_active` | `false` |
| `units.mining_ship.build_hard_limit_active` | `false` |
| `units.*.balance_reference_max_count` | `2` (diagnostic) |
| Schema | `balance_telemetry_v1` |

---

## Bugs / Warnings

| Item | Severity | Notes |
|------|----------|-------|
| ObjectDB leak @ quit | Low | Headless scene teardown (known pattern) |
| Iron starvation after SP + Storage I | **Balance NOTE** | MS #2 still gated on Iron in 10 min automated run |
| No basic scan milestone | Low | Automation/targeting; not necessarily player-facing bug |
| `iron_1500_reached` milestone | N/A | Threshold still 1500 in logger; CS now 900 Fe |

**No gameplay bugs filed — no fixes without approval.**

---

## Assessment vs Goals

| Goal | Assessment |
|------|------------|
| Economy less grindy | **Partial** — SP #3 + Storage I much faster; MS/SD #2 still Iron-gated in 10 min |
| Not completely trivial | **Yes** — Colony prereqs + Iron pipeline delay second fleet |
| Scaling correct | **Yes** |
| Gates unchanged | **Yes** |

### Recommended follow-up (observation only)

1. **10 min human playtest** — confirm ProductionPanel costs + MS #2 feel.
2. Consider whether **probe + Storage I** still consume too much early Iron relative to MS #2 (173) — data-only tuning candidate, not applied here.
3. Update telemetry milestone `iron_1500_reached` → `iron_900_reached` when touching logger (out of scope).

---

## Acceptance

1. Only audit docs + debug smoke runner added for test execution.  
2. No cost/gate/save changes.  
3. 600 s telemetry run completed.  
4. Report documents timeline, bottlenecks, telemetry validation.  
5. `tooltip_text` remains 0.
