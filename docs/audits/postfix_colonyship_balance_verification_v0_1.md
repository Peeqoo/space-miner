# Post-Fix ColonyShip Balance Verification v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Scope:** 20–30 min normal Solar → ColonyShip economy check **after** expansion-loop structural fixes  
**Purpose:** Decide whether **ColonyShip Iron** should be the first balance knob — **before** any data changes  
**References:** `docs/audits/expansion_loop_postfix_closure_v0_1.md`, `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md`, `space_miner_45min_live_run_capture_sheet_v2_kommentiert.pdf`

**No code, scene, data, balance, save, or tooltip changes in this step.**

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **NOT TESTED** — post-fix verification run **not executed** in this session |
| **Test executed?** | **No** |
| **Expansion structural blockers?** | **No** (per closure report; out of scope for this run) |
| **ColonyShip economy on track for 35–45?** | **Unknown** — needs live 30-min run |
| **Main blocker at 30 min** | **Unknown** (this run) — **historical proxy: Iron** |
| **Recommended next action** | **Execute this 30-min protocol once in Editor** — then update this report with real rows |

**Tooltip-Check:** `tooltip_text` → **0** in audited UI paths. No tooltip changes proposed.

### Verdict on “Iron first?” (pre-run, evidence-limited)

Structural post-fix changes (**startkit, discovery, Proxima data, dev tools, lighting**) do **not** alter Solar mining rates, ColonyShip costs, or Earth start economy. The last **live** Solar → ColonyShip evidence remains the **Water Recheck run** (~51:53 build; **Iron ~700 short @ 32:34**; Water OK). That supports **Iron as the leading hypothesis** for the first balance knob — but it is **not confirmed** until this post-fix verification run is performed.

---

## Run Conditions

| Field | Planned | Actual (this report) |
|-------|---------|----------------------|
| **Build / branch** | Current workspace post-fix | **NOT RUN** |
| **New Game** | Yes | — |
| **Dev colonize** | No | — |
| **Debug grants** | No | — |
| **Balance edits during test** | No | — |
| **Stop time** | 30:00 mandatory; optional to 35:00 | — |
| **Session recorder** | Stopwatch + milestone notes | — |

---

## Timeline

**Status: NOT TESTED** — fill after live run. Do not treat historical rows below as this report’s measured data.

### Measured timeline (post-fix run)

| Time | Event | Fe | Si | Cu | C | Water | Al | H | SurveyData | Storage Used/Cap | Notes |
|------|-------|----|----|----|----|-------|----|----|------------|------------------|-------|
| **0:00** | New Game | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| **10:00** | Checkpoint | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| **20:00** | Checkpoint | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| **30:00** | Primary stop | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| **35:00** | Optional extension | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| — | MS2 bought | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| — | Deep Scan 1 done | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| — | 3× Deep Scan done | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| — | Water ≥ 350 | — | — | — | — | — | — | — | — | — | **NOT TESTED** |
| — | ColonyShip buildable/built | — | — | — | — | — | — | — | — | — | **NOT TESTED** |

### Historical reference only (Water Recheck live — **not** post-fix verification)

*Source: `core_loop_balance_colony_water_recheck_v0_1.md` + capture sheet. Structural Proxima fixes do not change these Solar milestones.*

| Time | Event | Fe | Si | Water | SurveyData | Storage / notes |
|------|-------|----|----|-------|------------|-----------------|
| **19:40** | Colony prereqs met | — | — | growing | — | Only **resources** blocking |
| **32:34** | Water threshold | **~800 est.** (~700 short of 1500) | — | **354** | — | **Iron** main colony gate |
| **41:53** | Storage pressure | — | — | — | — | **Storage full**; upgrades blocked |
| **51:53** | ColonyShip built | met | met | spent | met | Build **~7 min late** vs 45:00 window |
| **~12:14** | MS2 band (sheet) | — | — | — | — | vs target **7–9 min** → **Late** |

---

## Milestone Check

| Milestone | Target time | Actual time | Rating | Notes |
|-----------|-------------|-------------|--------|-------|
| MS2 possible | 7–9 min | — | **NOT TESTED** | Historical proxy: **~12:14 band → Late** |
| MS2 bought | 7–9 min | — | **NOT TESTED** | Full-run model ~14:20 (separate audit) |
| First upgrade | 10–12 min | — | **NOT TESTED** | Prior rounds: often **Early** |
| Scan Drone Upgrade I | — | — | **NOT TESTED** | Prereq for colony protocol proxy |
| First Deep Scan | 15–18 min | — | **NOT TESTED** | Historical: met before colony grind |
| 3× Deep Scan (colony prereq) | — | — | **NOT TESTED** | Historical: prereqs @ **19:40** |
| Water ≥ 350 | — | — | **NOT TESTED** | Historical: **32:34 → On track** |
| ColonyShip prep (prereqs) | 30–35 min | — | **NOT TESTED** | Historical: **19:40** prereqs (Early) |
| ColonyShip buildable | 35–45 min | — | **NOT TESTED** | Historical: **not @ 45:00**; built **51:53 → Late** |

**Rating key:** Early / On Target / Late / Missing

---

## ColonyShip Cost Gap at 30:00

**Static costs** (unchanged): `data/production/colony_ship.tres`

| Resource | Need |
|----------|------|
| Iron | **1500** |
| Silicon | **300** |
| Water | **350** |
| SurveyData | **150** |

### At 30:00 — post-fix run

| Resource | Have | Need | Missing | Severity |
|----------|------|------|---------|----------|
| Iron | — | 1500 | — | **NOT TESTED** |
| Silicon | — | 300 | — | **NOT TESTED** |
| Water | — | 350 | — | **NOT TESTED** |
| SurveyData | — | 150 | — | **NOT TESTED** |

### Historical proxy @ ~32:34 (prior live run — reference only)

| Resource | Have | Need | Missing | Severity |
|----------|------|------|---------|----------|
| Iron | ~800 (est.) | 1500 | **~700** | **High** — dominated panel |
| Silicon | met (by 51:53) | 300 | likely OK by 30+ | Low at late check |
| Water | **354** | 350 | **0** | **None** |
| SurveyData | met (by 51:53) | 150 | likely OK by 30+ | Low at late check |

**ColonyShip `blocked_reason` @ 30:00 (this run):** **NOT TESTED**  
**Historical @ 32:34:** resource shortfall — **Iron primary**, not Water.

---

## Diagnosis

*Based on **historical live evidence** + **static cost data**. Post-fix 30-min run required to confirm.*

### 1. ColonyShip Iron too high?

| Field | Detail |
|-------|--------|
| **Evidence (this run)** | **None** — NOT TESTED |
| **Evidence (historical proxy)** | **~700 Fe short @ 32:34**; build **51:53** with **1500 Fe** cost; Water already satisfied |
| **Smallest possible fix** | Data-only: **Iron 1500 → 1200** (single knob) — **only after** post-fix run confirms Fe still dominates @ 30:00 |
| **Risk** | Shortens Earth endgame; validate with second live run |

### 2. MS2 too late?

| Field | Detail |
|-------|--------|
| **Evidence (this run)** | **None** — NOT TESTED |
| **Evidence (historical proxy)** | MS2 band **~12:14** vs **7–9** target |
| **Smallest possible fix** | **Separate** MS2 pass (e.g. `mining_ship.tres` Si cost) — **not** combined with ColonyShip Fe |
| **Risk** | Faster dual-ship economy shifts whole curve |

### 3. Storage full / capacity pressure?

| Field | Detail |
|-------|--------|
| **Evidence (this run)** | **None** — NOT TESTED |
| **Evidence (historical proxy)** | **Storage full @ 41:53** blocked upgrades |
| **Smallest possible fix** | UX/clarity + capacity path review — **not** Iron change first if storage dominates **this** run |
| **Risk** | Raising caps without design pass reduces mid-game tension |

**Max 3 problems rule satisfied.** Strongest **hypothesis** remains **#1 Iron** until measured otherwise.

---

## Recommendation

**One recommendation:** **Execute one 30-minute post-fix live run** using the protocol in this document (New Game, no dev tools, stop @ 30:00, fill Timeline + Cost Gap tables), then **update this file** with measured values.

**Do not change balance values yet.**

After the run:

| If @ 30:00… | Then next step |
|-------------|----------------|
| **Iron** missing ≫ other resources; prereqs/Water/SD OK | **Data-only pass: ColonyShip Iron only** (e.g. 1500 → 1200 candidate) |
| **MS2** still **>10 min** late and Fe gate secondary | **Separate MS2 balance check** — do not bundle with Fe |
| **Storage full** before 30:00 and blocks spending | **Storage UX/capacity check** — do not change Iron first |
| Milestones noisy / inconsistent | **Second 30-min run** before any knob |

**Not recommended now:**

- MS2 + ColonyShip + Storage combo fix  
- Save-v2, architecture splits, CargoShip, removing production limits  

---

## Run Protocol (copy for Editor session)

1. New Game → start stopwatch.  
2. Play normally in Solar only; no Dev Colonize, no debug grants.  
3. Note resources @ **10:00**, **20:00**, **30:00** (Fe, Si, Water, SurveyData, storage used/cap).  
4. Log milestones: MS2 possible/bought, first upgrade, Scan Drone I, first Deep Scan, 3× Deep Scan, Water ≥ 350.  
5. @ **30:00** open ColonyShip panel → record **`blocked_reason`** and per-resource gap.  
6. Optional: continue to **35:00** if within ~1–2 resources of build.  
7. Paste results into **Timeline** and **ColonyShip Cost Gap** sections above.

---

## Acceptance (this report)

1. No code, scene, or data files changed.  
2. Only `docs/audits/postfix_colonyship_balance_verification_v0_1.md` created.  
3. Run data **NOT TESTED** — clearly marked; historical data labeled **reference only**.  
4. ColonyShip cost gap table @ 30:00 documented (empty + static Need column).  
5. Recommendation names **at most one** next balance knob **after** a real run.  
6. No MS2 + ColonyShip + Storage combo fix proposed.  
7. `tooltip_text` remains **0**.
