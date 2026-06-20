# Cost Reduction 10-Minute Smoke v0.2

**Date:** 2026-06-20  
**Godot:** 4.6.1 (headless debug build)  
**Scope:** Post Cost Reduction Pass v0.2 + Float-Precision-Fix (`SCALED_COST_CEIL_EPSILON`) — 600 s automated economy run with `BalanceTelemetryLogger`.  
**No gameplay/cost/gate/save changes in this audit.**

**Telemetry file:** `user://balance_runs/cost_reduction_10min_v0_1_2026_06_20_124134.json`  
*(Runner label still `cost_reduction_10min_v0_1` in script constant — data reflects v0.2 economy.)*  
**Runner:** `scripts/debug/smoke_tests/cost_reduction_10min_smoke_runner.tscn`

**Baseline under test:**

| Unit | Base | Multiplier | Next cost (new game) |
|------|------|------------|----------------------|
| ScanDrone #2 | 50 Fe | 1.12 | **56 Iron** |
| MiningShip #2 | 120 Fe / 20 Si | 1.12 | **135 Iron / 23 Silicon** |
| SurveyProbe #3 | 30 Fe | 1.10² | **37 Iron** |
| ColonyShip | flat | excluded | **900 / 180 / 250 / 100** |

---

## Verdict: **PASS WITH NOTES**

| Area | Result |
|------|--------|
| A — Early production | **PASS WITH NOTES** — SD #2 @ ~4 s ✓; SP #3 early ✓; **MS #2 not reached** (Iron); Storage I **not bought** |
| B — Scaling / telemetry gates | **PASS** — runtime costs correct; `build_hard_limit_active` false |
| C — Mining loop | **PASS WITH NOTES** — mining + delivery observed; UI/panel not exercised |
| D — ColonyShip pressure | **PASS** — prereqs block; not trivial |
| E — Storage | **PASS WITH NOTES** — Storage I skipped (Iron sunk into production); storage never full |
| F — Telemetry fields | **PASS** — baseline costs 56 / 135·23 / 37; `scaling_excluded` true |

**Smoke script overall:** **PASS** (0 failures; baseline assertions at t≈0).

---

## Test Setup

- `GameSession.reset_for_new_game()` → load `system_scene.tscn`
- `BalanceTelemetryLogger.start_run("cost_reduction_10min_v0_1")`
- Automated economy tick every 2 s: upgrades → SP → SD → MS → sensor → investigate → scan → mine
- Duration: **600.0 s** wall clock
- Float-precision fix active (`ceili(amount - 0.0001)`)

**Limitations (NOTES):**

- Headless **scripted** player — not manual UI play; `ProductionPanel` hover not visually checked (costs verified via `get_scaled_production_cost` + telemetry JSON).
- `BaseManagementPanel` auto-open on unload **not re-tested** (separate smoke: `base_panel_unload_smoke_test.gd`).
- **Multi-MS same target** not exercised — fleet stayed at **1 MS**.
- No `first_basic_scan_done` telemetry milestone — automation did not complete a basic scan in 10 min.
- Repeated `SurveyProbe investigate blocked` warnings (investigation in progress / no probe available) — automation noise, not a cost bug.

---

## Timeline (minute 0–10)

| Minute | Iron | Silicon | SD | MS | SP (owned) | Storage used/cap | Notes |
|--------|------|---------|----|----|------------|------------------|-------|
| 0 | 100 | 0 | 1 | 1 | 2 | 100/1000 | New game baseline |
| 1 | 7 | 8 | 2 | 1 | 0 | 60/1000 | SP #3 + SD #2 spent Iron in first ticks |
| 2 | 7 | 30 | 2 | 1 | 0 | 132/1000 | Mining active; Si rising |
| 3 | 7 | 50 | 2 | 1 | 0 | 212/1000 | |
| 4 | 7 | 65 | 2 | 1 | 0 | 272/1000 | |
| 5 | 7 | 84 | 2 | 1 | 0 | 348/1000 | |
| 6 | 7 | 98 | 2 | 1 | 0 | 404/1000 | |
| 7 | 7 | 112 | 2 | 1 | 0 | 460/1000 | |
| 8 | 7 | 130 | 2 | 1 | 0 | 532/1000 | |
| 9 | 7 | 145 | 2 | 1 | 0 | 592/1000 | |
| 10 | 7 | 165 | 2 | 1 | 0 | 672/1000 | 1 MS returning from Venus; Iron-starved |

### Milestone times (telemetry + smoke tracker)

| Event | Time (s) |
|-------|----------|
| Run start | 0.1 |
| First signal revealed | 2.0 |
| **ScanDrone #2 built** | **2.0** (telemetry) / **4.0** (smoke unit tracker) |
| **SurveyProbe #3 built** | **≤2.0** (inferred: lifetime=3 before first economy tick completes; SP build precedes SD in tick order) |
| Sensor pulse affordable | 26.1 |
| Sensor pulse used | 28.1 |
| First mining started | 30.1 |
| First delivery (unload) | 46.1 |
| First object revealed (investigate) | 50.1 |
| Run end | 600.0 |

### Not reached in 10 min

| Target | Status |
|--------|--------|
| **MS #2** (135 Fe / 23 Si) | **Not built** — **blocked by Iron** (7 Fe, 128 missing); Silicon **not** the bottleneck (165 Si) |
| **SD #3** (63 Fe) | Not built — 56 Fe missing @ min 10 |
| **Storage Upgrade I** (20 Fe / 5 Cu) | **Not bought** — Iron at 7 after early production spend |
| ScanDrone Upgrade I | Not bought (Iron + Copper) |
| MiningShip Upgrade I | Not bought (Iron + Silicon + Copper) |
| ColonyShip affordable / built | Not reached |
| `storage_full` | Not reached (67% @ min 10) |

---

## A — Early Production

| Check | Result |
|-------|--------|
| SD #2 timing | **~2–4 s** — major improvement vs v0.1 (not reached in 10 min) |
| MS #2 timing | **Not reached** — need 135 Fe, have 7 Fe @ min 10 |
| MS #2 bottleneck | **Iron** (`cost_gap.Iron.missing=128`, `cost_gap.Silicon.missing=0`) |
| SP #3 timing | **≤2 s** (37 Fe spend in opening ticks) |
| Storage I timing | **Not purchased** — early Iron went to SP #3 (37) + SD #2 (56) → 7 Fe remainder |
| ProductionPanel / telemetry costs | **Match** — `production_gates.*.cost` = runtime scaled values (see §F) |

**Early Iron budget (first tick, inferred):** 100 − 37 (SP #3) − 56 (SD #2) = **7 Iron** — stable for minutes 1–10.

---

## B — Scaling

| Check | Result |
|-------|--------|
| SD next cost after #2 | **63 Iron** (`lifetime_count=2`, mult 1.12) ✓ |
| MS next cost | **135 / 23** (`lifetime_count=1`) ✓ |
| SP next cost after #3 | **40 Iron** (`lifetime_count=3`, mult 1.10) ✓ |
| `production_lifetime_count` | SD=2, MS=1, SP=3 @ min 10 ✓ |
| Telemetry `cost` fields | Runtime scaled values (not flat base) ✓ |
| `build_hard_limit_active` | **false** for SD and MS @ run_start and min 10 ✓ |

---

## C — Mining Loop

| Check | Result |
|-------|--------|
| Mining started | **Yes** @ 30.1 s (Venus target) |
| Unload / delivery | **Yes** @ 46.1 s |
| Storage refresh | Used capacity rises 100 → 672 (no full block) |
| `waiting_for_storage` | 0 throughout |
| BaseManagementPanel auto-open | **Not tested** (headless automation) |
| Multi-MS same target | **N/A** — only 1 MS |

@ min 10: MS status `to_base`, cargo Venus mix (Carbon/Copper/Silicon — **low Iron yield**), explaining slow Fe recovery.

---

## D — ColonyShip Pressure

| Prerequisite | Met @ min 10 |
|--------------|--------------|
| Deep Scan Module | **No** |
| Shipyard I | **No** |
| Colony Protocol | **No** |
| Ice source discovered | **Yes** |
| Fully scan 3 objects | **No** (0 deep scans) |

| Resource | Have | Need | Missing |
|----------|------|------|---------|
| Iron | 7 | 900 | 893 |
| Silicon | 165 | 180 | 15 |
| Water | 0 | 250 | 250 |
| SurveyData | 5 | 100 | 95 |

`colony_ship_buildable: false`, `scaling_excluded: true`, blocked reason: **Deep Scan Module required**. ColonyShip remains non-trivial.

---

## E — Storage

| Check | Result |
|-------|--------|
| Storage I bought | **No** |
| Storage full | **No** (672/1000 @ min 10, 67%) |
| Early Iron drain | **Production spend** (SP+SD), not Storage I — opposite of v0.1 where Storage I @ 42 s consumed 20 Fe |

Storage I did **not** destroy early Iron flow in this run; instead **successful early SD #2** consumed the Iron that v0.1 had reserved for Storage I.

---

## F — Telemetry Field Validation (@ run_start)

| Field | Expected | Actual | OK |
|-------|----------|--------|-----|
| `production_gates.scan_drone.cost.Iron` | 56 | 56 | ✓ |
| `production_gates.mining_ship.cost.Iron` | 135 | 135 | ✓ |
| `production_gates.mining_ship.cost.Silicon` | 23 | 23 | ✓ |
| `production_gates.survey_probe.cost.Iron` | 37 | 37 | ✓ |
| `production_gates.colony_ship.scaling_excluded` | true | true | ✓ |
| `production_gates.colony_ship.cost` | 900/180/250/100 | 900/180/250/100 | ✓ |
| `units.scan_drone.build_hard_limit_active` | false | false | ✓ |
| `units.mining_ship.build_hard_limit_active` | false | false | ✓ |
| `SaveManager.SAVE_VERSION` | 1 | 1 (smoke assertion) | ✓ |
| `KEY_SCAN_ALREADY_IN_PROGRESS` | present | present in codebase | ✓ |
| `tooltip_text` in `.gd`/`.tscn` | 0 | 0 | ✓ |

Float-precision fix confirmed: SD #2 = **56** (not 57).

---

## Built Units & Upgrades (@ min 10)

**Units:** SD ×2, MS ×1, SP owned 0 (lifetime built 3, all consumed/deployed)  
**Upgrades:** Storage 0, ScanDrone 0, MiningShip 0  
**Active jobs:** 2 scan jobs, 1 MS `to_base` from Venus

**Resource snapshot @ min 10:** Fe 7, Si 165, Cu 165, C 330, SurveyData 5, Water 0

---

## v0.1 → v0.2 Comparison

| Metric | v0.1 smoke | v0.2 smoke | Delta |
|--------|------------|------------|-------|
| SD #2 in 10 min | Not reached | **Yes @ ~4 s** | **Improved** |
| MS #2 in 10 min | Not reached (173 Fe) | Not reached (135 Fe, 128 missing) | Closer, still blocked |
| MS bottleneck | Iron | Iron | Same |
| SP #3 | ~4–6 s | ~≤2 s | Similar |
| Storage I | ~42 s | **Not bought** | Trade-off: Iron → SD #2 |
| Iron @ min 10 | 3 | 7 | Slightly better |
| Silicon @ min 10 | 170 | 165 | Similar |
| Storage cap | 1600 | 1000 | Lower (no upgrade) |

---

## Bugs / Warnings

| Item | Severity | Notes |
|------|----------|-------|
| ObjectDB leak @ quit | Low | Headless scene teardown (known pattern) |
| Iron starvation after early SP + SD | **Balance NOTE** | MS #2 still Iron-gated; Venus cargo Si-heavy |
| SurveyProbe investigate spam | Low | Automation retries while job active |
| Telemetry label `v0_1` | Cosmetic | Script constant not renamed; data is v0.2 |
| No basic scan milestone | Low | Automation/targeting |

**No gameplay bugs filed — no fixes without approval.**

---

## Recommendation

### **Kosten v0.2 grundsätzlich beibehalten**

Cost Reduction v0.2 + Float-Precision-Fix erfüllt das Hauptziel **SD #2 früh erreichbar** und liefert korrekte Runtime-Kosten in Telemetry/Production path. ColonyShip bleibt korrekt blockiert. Scaling und `build_hard_limit_active` verhalten sich wie erwartet.

### Optionaler nächster kleiner Tuning-Pass (nur wenn MS #2 in 10 min Human-Playtest ebenfalls fehlt)

Priorität **nicht** Produktionskosten senken (bereits v0.2), sondern **Iron-Income-Rate** im Early-Loop:

1. **Human 10-min playtest** — prüfen ob Spieler MS #2 natürlicher erreicht (z. B. Moon/Mars Iron statt Venus).
2. Falls weiterhin Iron-starved: kleine **Yield-/Target-Balance** oder **MS cargo mix** evaluieren — nicht erneut SD/MS base costs ohne Daten.
3. Storage I (20 Fe) ist in v0.2 kein Early-Iron-Killer mehr; Trade-off SP+SD vs Storage bleibt beobachten.

**Nicht empfohlen ohne Playtest:** weitere Kostensenkung — SD #2-Ziel ist erreicht; MS #2 ist näher (128 vs 170 Fe missing) aber noch nicht in Reichweite bei 1 MS auf Si-lastigem Target.

---

## Acceptance

1. Only audit doc created; no gameplay/cost/gate/save changes.  
2. 600 s telemetry run completed — smoke **PASS**.  
3. Report documents timeline, bottlenecks, telemetry validation, v0.1 comparison.  
4. `SAVE_VERSION = 1`, `KEY_SCAN_ALREADY_IN_PROGRESS` intact, `tooltip_text = 0`.
