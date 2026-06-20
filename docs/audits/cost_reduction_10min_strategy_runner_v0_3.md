# Cost Reduction 10-Minute Strategy Runner v0.3

**Date:** 2026-06-20  
**Godot:** 4.6.1 (headless debug build)  
**Scope:** Improved informed early-game strategy in `cost_reduction_10min_smoke_test.gd` — validates Cost Reduction v0.2 + float-precision fix without gameplay changes.  
**No gameplay/cost/gate/save/UI changes in this audit.**

**Telemetry:** `user://balance_runs/cost_reduction_10min_strategy_v0_3_2026_06_20_140210.json`  
**Runner:** `scripts/debug/smoke_tests/cost_reduction_10min_smoke_runner.tscn`

---

## Verdict: **PASS**

| Area | Result |
|------|--------|
| Iron-target priority | **PASS** — Mars mined from 28 s; no Venus mining |
| MS #2 in 10 min | **PASS** — built @ **296.9 s (~4.9 min)** |
| SP rebuild discipline | **PASS** — 2 rebuilds (late), no early Iron burn |
| SD #2 | **PASS** — @ 2–4 s, MS #2 not blocked |
| Storage I | **PASS** — not bought (usage <70 %) |
| ColonyShip pressure | **PASS** — prereqs block |
| Telemetry baseline costs | **PASS** — 56 / 135·23 / 37 |

**Smoke overall:** **PASS** (0 failures).

---

## Strategy Changes (v0.3 Runner Only)

Compared to pre-v0.3 automation:

| Behavior | Old | v0.3 |
|----------|-----|------|
| Mining target | Venus (0 % Iron) | **Mars** (Iron body), Venus fallback only |
| Build tick order | SP/SD before mine | Sensor → Investigate (Mars signal) → Scan iron → **Mine** → **MS #2** → SD → SP |
| SP rebuild | Immediate @ tick 1 | Only if `owned==0`, not MS2-imminent, Fe after build ≥80 |
| SD #2 | Immediate @ tick 1 | Allowed in Si-gather phase; blocked if would drop Fe below MS2 need when Si≥23 |
| Storage I | Early @ ~42 s | Only if usage >70 % and won't block MS #2 |
| Upgrades | Attempted each tick | **Removed** from tick (saves early Iron) |

**Deleted duplicate:** `cost_reduction_10min_human_strategy_smoke_test.gd` — both runners now use `cost_reduction_10min_smoke_test.gd`.

---

## Timeline (minute 0–10)

| Minute | Iron | Silicon | SD | MS | SP own | Storage | Notes |
|--------|------|---------|----|----|--------|---------|-------|
| 0 | 100 | 0 | 1 | 1 | 2 | 100/1000 | New game |
| 1 | 50 | 5 | 2 | 1 | 0 | 69/1000 | SD #2; Mars mining started @28 s |
| 2 | 74 | 25 | 2 | 1 | 0 | 144/1000 | Iron rising from Mars |
| 3 | 98 | 45 | 2 | 1 | 0 | 224/1000 | Si ≥23 approaching |
| 4 | 118 | 62 | 2 | 1 | 0 | 291/1000 | |
| 5 | 5 | 57 | 2 | **2** | 0 | 206/1000 | **MS #2 built @297 s** |
| 6 | 31 | 79 | 2 | 2 | 0 | 293/1000 | |
| 7 | 65 | 107 | 2 | 2 | 0 | 406/1000 | |
| 8 | 101 | 137 | 2 | 2 | 0 | 526/1000 | |
| 9 | 100 | 167 | 2 | 2 | 0 | 609/1000 | SP rebuild #1 @518 s |
| 10 | 96 | 197 | 2 | 2 | 0 | 694/1000 | Water 132 from Mars cargo |

### Milestones

| Event | Time (s) |
|-------|----------|
| first_signal_revealed | 2.0 |
| **scan_drone_2_built** | **2.0** (smoke tracker @4.0) |
| sensor_pulse_used | 24.1 |
| **first_mining_started (Mars)** | **28.1** |
| first_delivery | 46.1 |
| first_object_revealed | 48.1 |
| **mining_ship_2_built** | **296.9** |
| survey_probe_rebuild #1 | 517.6 |
| survey_probe_rebuild #2 | ~579.8 |
| storage_upgrade_bought | **NOT REACHED** |

---

## A — Early Choices

| Question | Result |
|----------|--------|
| First production spend | SD #2 @ ~2–4 s (Si still <23 — allowed) |
| SP #3 at start? | **No** — probes consumed by investigate; rebuilds deferred |
| SD #2 | **~4 s** ✓ |
| Storage I | **Not bought** |
| First mine target | **Mars** ✓ |
| Why Mars? | Mars signal investigated → known → basic scanned → **has Iron**; runner prioritizes `mars` > `moon` > `mercury` > Venus fallback |

---

## B — MS #2

| Check | Result |
|-------|--------|
| MS #2 reached? | **Yes** @ **296.9 s** |
| Bottleneck at build | None — gate opened with Fe≥135, Si≥23 |
| Target selection | **Mars Iron mining** — not Venus |
| Scan/Discovery | Mars revealed ~48 s; mining started before full reveal pipeline completed |

**At MS #2 build (min 5 snap):** Fe dropped to 5 after spend; Si 57.

---

## C — Iron Income

| Source | Used? |
|--------|-------|
| **Mars** | **Yes** — sole mining target (telemetry `target_id: mars` throughout) |
| Venus | **No** |
| Moon/Mercury | Not needed (Mars sufficient) |

**Iron rate (approx.):** ~15–25 Fe/min net during active Mars loop (min 1–4), sufficient to reach 135 Fe by min 5.

---

## D — Runner vs Prior Runs

| Metric | Automation v0.2 | Human-Proxy v0.2 | **Strategy v0.3** |
|--------|-----------------|------------------|-------------------|
| First mine | Venus | None | **Mars** |
| MS #2 | No | No | **Yes @297 s** |
| Fe @ min 10 | 7 | 23 | **96** |
| Si @ min 10 | 165 | 0 | **197** |
| SP rebuilds early | Yes (tick 1) | Yes (lifetime 4) | **No** (2 late) |
| SD #2 | @4 s | No | @4 s |

---

## E — SP Rebuilds

| # | Time (s) | Context |
|---|----------|---------|
| 1 | 517.6 | After MS #2; Fe ~100; probes depleted |
| 2 | ~579.8 | Late run; MS #2 safe |

**Early Iron preserved:** 100 Fe at start → mining from 28 s without SP production spend.

---

## F — Storage I

**Not purchased.** Usage peaked ~69 % @ min 10 (694/1000) — below 70 % threshold.

---

## G — ColonyShip (@ min 10)

| Prerequisite | Met? |
|--------------|------|
| Deep Scan Module | No |
| Shipyard I | No |
| Colony Protocol | No |
| Ice source | Yes |
| 3 Deep Scans | No |

| Resource | Have | Need |
|----------|------|------|
| Iron | 96 | 900 |
| Silicon | 197 | 180 ✓ (over) |
| Water | 132 | 250 |
| SurveyData | 5 | 100 |

ColonyShip **not trivial** — prereqs + resources block.

---

## H — Iron-Target Priority Verification

| Check | Result |
|-------|--------|
| Mars prioritized over Venus | **Yes** |
| Venus mined? | **No** |
| Moon required? | No — Mars available after investigate |
| `first_iron_mining_mars` milestone | **28.1 s** |

---

## Telemetry Field Check (@ run_start)

| Field | Expected | OK |
|-------|----------|-----|
| `production_gates.scan_drone.cost.Iron` | 56 | ✓ |
| `production_gates.mining_ship.cost` | 135 / 23 | ✓ |
| `production_gates.survey_probe.cost.Iron` | 37 | ✓ |
| `colony_ship.scaling_excluded` | true | ✓ |
| `units.*.build_hard_limit_active` | false | ✓ |
| `SAVE_VERSION` | 1 | ✓ |

---

## Bugs / Warnings

| Item | Severity |
|------|----------|
| Mars investigate spam warnings | Low — automation retries while in progress |
| SD #2 still @4 s (early) | Note — allowed in Si-gather phase; did not block MS #2 |
| ObjectDB leak @ quit | Low — headless teardown |
| `first_basic_scan_done` milestone | Not reached — telemetry quirk |

---

## Recommendation

### **1. Kosten v0.2 behalten** ✓

Strategy runner proves **MS #2 in ~5 min** with Mars Iron mining and disciplined SP spending. Prior runner failures were **strategy artifacts**, not cost tuning gaps.

| Option | Action |
|--------|--------|
| Iron-Yield prüfen | **Not needed** — Mars yield sufficient |
| Echter GUI-Test | **Optional** — confirms UI target selection; economy validated |
| Weiterer Cost-Pass | **No** |
| Automation v0.2 smoke superseded | Use **v0.3 runner** for future 10-min economy checks |

---

## Acceptance

1. Only debug smoke runner changed — no gameplay `.tres`/gates/save/UI.  
2. No cost changes.  
3. Iron-target priority (Mars) implemented.  
4. No early SP Iron burn.  
5. `SAVE_VERSION = 1`, `KEY_SCAN_ALREADY_IN_PROGRESS` intact, `tooltip_text = 0`.  
6. 600 s run **PASS** — MS #2 @ 297 s.
