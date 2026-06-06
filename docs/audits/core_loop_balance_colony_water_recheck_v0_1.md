# Core Loop Balance Colony Water Recheck v0.1

**Date:** 2026-05-20  
**Last updated:** 2026-05-20 (live run from capture sheet)  
**Engine:** Godot 4.6.1  
**Scope:** Recheck after ColonyShip cost **Ice → Water** (`data/production/colony_ship.tres`).  
**Live source:** `space_miner_45min_live_run_capture_sheet_v2_kommentiert.pdf` (commented capture sheet)  
**References:** `docs/audits/core_loop_balance_full_run_v0_1.md`, `docs/audits/phase_3_mining_loop_proof_v0_1.md`

**No code, scene, data, or balance changes in this step.**

---

## Live run — execution status

| Item | Status |
|------|--------|
| **Procedure** | New Game → stopwatch → normal play (no debug cheats) → ColonyShip build → colonize Proxima |
| **Executed** | **YES** — live Editor session documented in capture sheet PDF |
| **Session length** | **~51:53** to ColonyShip build (continued past 45:00 target window) |
| **Water-Fix build** | Post **Ice → Water** (`350 Water` cost) |

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Water-Fix valid?** | **PASS** — Water mined, stored, spent on build; no Ice `blocked_reason` |
| **Impossible Ice blocker removed?** | **PASS** — functional confirmation; build used **Water**, not Ice |
| **Functional Check** | **PASS** — Water path + ColonyShip build verified live |
| **ColonyShip built?** | **PASS (late)** — built **~51:53** vs design target **35–45 min** |
| **ColonyShip realistic in 35–45 min?** | **No** — reachable only after **~52 min** in this run |
| **Expansion after ColonyShip** | **FAIL / BLOCKER** — Proxima / new system incorrectly initialized after colonization |
| **New blockers after Water-Fix** | **(1)** Post-colony **new-system init** (bug). **(2)** **Iron** still dominant colony cost gate until ~52 min (balance). **(3)** **Storage full @ ~42 min** stalled upgrades (balance/state) |
| **Most important next fix** | **New colony system initialization** (start package + playable state on Proxima) |
| **Balance changes allowed after this step?** | **No** — fix colonization init first; defer Fe/SD/MS2 cost tuning |

---

## Static Data Check

| Check | Expected | Result | Notes |
|-------|----------|--------|-------|
| ColonyShip cost uses **Water** | `"Water": 350` | **PASS** | `data/production/colony_ship.tres` |
| No active ColonyShip **Ice** cost | No Ice in production cost | **PASS** | Live: no Ice block observed |
| Water deposit exists | Earth / Mars bodies | **PASS** | Mined in session |
| Water mineable / storable | Mining → BaseStorage | **PASS** | **354 Water @ 32:34** |
| Prereq accepts Water source | Ice-source prereq + Water discovery | **PASS** | Prereqs met before build |
| Save/Load not touched (this audit) | — | **PASS** | Doc-only update |
| No `survey_data.tres` in planet_resources | Absent | **PASS** | — |
| `tooltip_text` = 0 | Grep 0 | **PASS** | Verified 2026-05-20 |

---

## Functional Check

**Live status:** **PASS** (capture sheet).

| Step | Expected | Result | Notes |
|------|----------|--------|-------|
| Water source scanned | Earth basic scan shows Water | **PASS** | — |
| Water mined | Storage gains Water | **PASS** | ≥350 by **32:34** |
| Storage shows Water > 0 | Base storage panel | **PASS** | **354** @ 32:34 |
| ColonyShip panel shows **Water** cost | **350 Water** in cost | **PASS** | No Ice in cost display |
| No **Ice** `blocked_reason` | Never missing Ice | **PASS** | Water-Fix confirmed |
| Build succeeds when all met | ColonyShip built | **PASS** | **~51:53** |
| Water deducted on build | Water −350 | **PASS** | Implied by successful build after 354 stored |
| ColonyShip count +1 | Inventory +1 | **PASS** | Ship consumed on colonization |

### ColonyShip end state (live)

| Field | Value |
|-------|--------|
| **ColonyShip built?** | **Yes** @ **~51:53** |
| **ColonyShip buildable @ 45:00?** | **No** — still grinding **Iron**; build **~7 min late** |
| **`blocked_reason` before build** | Resource shortfall (**Iron** primary); not Ice/Water |
| **Missing resources @ 32:34** | **Water OK (354)**; **Iron ~700 short** of colony need (1500 total) |
| **Prereqs all met before build?** | **Yes** (player note @ 19:40: only resources missing) |
| **New base established?** | **Yes** — **Proxima** after colonization |
| **Proxima playable after switch?** | **No** — see Expansion blocker |

---

## Mandatory milestones (live)

| Time | Event | Fe | Si | Water | SD | Notes |
|------|--------|----|----|-------|-----|-------|
| | Early loop (prior proof ref.) | 100 | — | 0 | 15 | Reveal ~0:30, delivery ~0:53 (other session) |
| **12:14** | Checkpoint / MS2 area | *(sheet)* | *(sheet)* | *(sheet)* | *(sheet)* | Resource stand; **MS2 band** per capture comments |
| **19:40** | Colony prep | — | — | — | — | Player: **„brauche nur noch genug Ressourcen“** — prereqs done, bulk costs remain |
| **32:34** | Water threshold | low vs 1500 | — | **354** | — | **Water ≥ 350**; **Iron still ~700 short** |
| **41:53** | Storage pressure | — | — | — | — | **Storage full**; **no further upgrades** possible |
| **51:53** | ColonyShip + colonize | — | — | spent | — | **ColonyShip built**; **new base in Proxima** |
| After **51:53** | Proxima session | **0 / none** | — | — | — | **All objects visible**; **no start resources**; **cannot act** |

*(Exact Fe/Si/SD at 12:14 from PDF capture — fill from sheet screenshots if transcribing later.)*

---

## Full Run Timeline (post–Water-Fix, live)

| Time | Event | Fe | Si | Water | SurveyData | Notes |
|------|--------|----|----|-------|------------|-------|
| **12:14** | Mid-run checkpoint | — | — | — | — | MS2 / economy band; see capture sheet |
| **19:40** | Colony resource grind | — | — | growing | — | Only **resources** blocking colony |
| **32:34** | Water target met | **~800** (est. ~700 short) | — | **354** | — | **Iron** main colony gate |
| **41:53** | Storage ceiling | — | — | — | — | **Storage full**; upgrades blocked |
| **45:00** | Design target window | — | — | ≥350 | — | **Colony not yet built** |
| **51:53** | ColonyShip built | met | met | **−350** | met | **Proxima base established** |
| **Post-51:53** | Proxima broken state | **0** | — | — | — | Visible bodies, **no start kit**, **no actions** |

---

## Target vs Actual After Water Fix

| Target | Actual (live) | Rating |
|--------|---------------|--------|
| MS2 **7–9 min** | **~12:14 band** (MS2 area per sheet) | **Late** |
| First upgrade **10–12 min** | Earlier than target (prior rounds) | **Early** |
| Deep Scan **15–18 min** | Met before colony grind | **On Target / Early** |
| Storage/Control **20–25 min** | **41:53 storage full** — relevant | **On Target** (pressure real) |
| Colony prep **30–35 min** | **19:40** prereqs done; resources lag | **On Target** (prep) |
| ColonyShip buildable **35–45 min** | **Not @ 45:00**; built **51:53** | **Late** |

---

## Friction Log

| Zeit | Problem | Kategorie | Schwere | Kleinster Fix |
|------|---------|-----------|---------|---------------|
| Post-**51:53** | Proxima: all objects visible, **no start resources**, player **cannot act** | **Bug / Blocker** | **Blocker** | **New colony system initialization** — start package + gating on new base |
| **51:53** | ColonyShip only after **~52 min** vs **35–45** design | **Balance** | Medium | Defer cost tuning until Proxima init fixed; then consider **Fe** only |
| — | SensorPulse **cost not visible** before pulse | **UI** | Low | Show SD cost on pulse control |
| — | **„Scan already in progress“** while drone only **orbiting** | **UI / State** | Medium | Align scan-busy state with actual scan phase |
| — | Resources feel **random**; bodies lack clear **main resource** identity | **Design / Balance** | Medium | Deposit plan / richness review (separate pass) |
| — | **Remaining resources** / live panel values stale while panel open | **UI** | Low | Refresh open ObjectInfo on resource signals |
| — | Storage **delete** button awkward | **UI** | Low | UX pass on discard control |
| — | Label **„Earth Base“** should read **„Earth“** | **UI Copy** | Low | Copy-only rename |
| **41:53** | **Storage full** blocks upgrades mid-run | **Balance / State** | Medium | Intentional capacity; clarify limits + upgrade path — **not** remove all control limits |

### Control limits (v0.1 design note)

- **Control limits** (max drones / mining ships / probes) are **intentional in v0.1**.
- The problem is **not** “remove all production limits.”
- Issues are: **unclear or over-blocking limits**, **storage full without clear relief**, and **missing new-base start package** after colonization.
- **Do not** remove all limits without a separate balance design pass.

---

## Remaining Balance Issues

Max **3** — live evidence from capture sheet. **No cost changes in this step.**

### 1. Colony Iron cost vs session length

| Field | Detail |
|-------|--------|
| **Evidence** | **32:34**: Water **354**, Iron still **~700 short**; build **51:53** |
| **Smallest fix** | After Proxima fix: consider **Fe 1500→1200** only — **one** knob |
| **Risk** | Shortens Earth endgame; validate with second live run |

### 2. MS2 pacing

| Field | Detail |
|-------|--------|
| **Evidence** | MS2 band **~12:14** vs target **7–9 min** |
| **Smallest fix** | Defer until post-Proxima; optional **Si 40→28** in `mining_ship.tres` |
| **Risk** | Faster dual-ship economy |

### 3. Storage full @ 41:53

| Field | Detail |
|-------|--------|
| **Evidence** | **41:53** full storage → **no upgrades**; intentional capacity met |
| **Smallest fix** | UX: clearer **storage full** + upgrade affordance; not blanket limit removal |
| **Risk** | Raising caps without design pass blunts mid-game tension |

**Water 350:** **PASS** — reached **32:34**; **not** the colony blocker after Water-Fix.

---

## Recommendation

**One next step:** **Fix new colony system initialization** — after colonization, Proxima (or any new base) must receive a **v0.1 start package** (resources, units, signals/gating) and a **playable loop** (not all bodies visible with zero actions).

Do **not** tune Colony **Fe / Si / SurveyData** or MS2 costs until Proxima is verified playable in a second live run.

---

## Acceptance (this report update)

1. No code, scene, or data files changed.  
2. Only `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md` updated.  
3. Live-run results from capture sheet PDF incorporated.  
4. Issues classified **Bug / UI / Balance / Design**.  
5. Exactly **one** next recommendation: **new colony system initialization**.  
6. `tooltip_text` remains **0**.
