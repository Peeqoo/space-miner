# Expansion Loop Post-Fix Closure v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Method:** Documentation closure — historical baseline review + post-fix status synthesis (read-only; no code/scene/data edits in this step)  
**Supersedes:** Nothing — this report **does not** replace earlier audits.  
**Historical baseline:** `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md` + `space_miner_45min_live_run_capture_sheet_v2_kommentiert.pdf`  
**Post-fix references:** `docs/audits/colonization_expansion_devtools_lighting_audit_v0_1.md`, user-confirmed Editor smoke tests (2026-06-07)

**No code, scene, data, balance, save, or tooltip changes in this step.**

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Expansion Loop structural status** | **PASS** |
| **Water-Fix status** | **PASS** (unchanged since baseline) |
| **ColonyShip build status** | **PASS (functional)** — live baseline **~51:53**; **35–45 min target not met** |
| **Proxima / New-System status** | **PASS** (post-fix; user-confirmed smoke test) |
| **Lighting status** | **PASS** (user-confirmed live check) |
| **Remaining balance status** | **NOT CLOSED** |
| **Wichtigster nächster Schritt** | **Kurzer post-fix Balance-Verifikationslauf (20–30 min Solar → ColonyShip)** — oder kleiner Balance Design Report **bevor** Werte geändert werden; bei Daten-Fix nur **ColonyShip Iron** prüfen |

**Tooltip-Check:** `tooltip_text` in geprüften Audit-/HUD-Pfaden → **0**. Kein Vorschlag, Tooltips einzuführen.

---

## Historical Baseline

The **Water Recheck live run** (`core_loop_balance_colony_water_recheck_v0_1.md`, capture sheet PDF) documents the game **before** the structural expansion fixes listed below.

| Finding (baseline era) | Status then | Current relevance |
|------------------------|-------------|-------------------|
| **Water-Fix (Ice → Water)** | **PASS** — Water mined (**354 @ 32:34**), spent on build; no Ice blocker | Still **PASS**; `colony_ship.tres` unchanged (`Water: 350`) |
| **ColonyShip built** | **PASS (late)** @ **~51:53** | Functional build path works; **timing still a balance issue** |
| **ColonyShip 35–45 min target** | **FAIL** — not buildable @ 45:00 | **Still open** — Iron was primary gate (~700 short @ 32:34) |
| **Proxima after colonization** | **FAIL / BLOCKER** — all objects visible, no start resources, no actions | **Historically true** — **not current** after post-fix init + data |
| **MS2 pacing** | **~12:14 band** vs **7–9 min** target | **Still open** (balance) |
| **Storage full @ ~41:53** | Pressure blocked upgrades | **Still open** (balance/UX) |

**Important:** Statements like *“Proxima broken / all bodies visible / no start kit”* in the Water Recheck and capture sheet describe the **pre-fix** state. They are **archived evidence**, not the current product status.

---

## Fixes Applied After Baseline

| # | Fix | Primary files / areas | Zweck | Status | Notes |
|---|-----|----------------------|-------|--------|-------|
| 1 | **ColonyShip Ice → Water** | `data/production/colony_ship.tres` | Remove impossible Ice cost; Water mineable on Earth | **PASS** | Baseline live-verified; cost still `Water 350`, `Iron 1500`, `Si 300`, `SD 150` |
| 2 | **New Colony Startkit** | `game_session.gd` (`establish_base_at_body`, `_apply_colony_base_start_kit`), `base_store.gd` (`apply_start_kit_to_base`) | Playable new base after colonization | **PASS** | 1 drone, 1 MS, 2 probes, 100 Fe, storage 1000, 0 colony ships |
| 3 | **New System Discovery-Gating** | `game_session.gd` (`_initialize_colony_system_discovery`), `system_discovery_controller.gd` | Star + colony body KNOWN; 2 signals; rest hidden | **PASS** | User-confirmed: not all bodies visible |
| 4 | **Fixed `colonization_start_body_id`** | `system_definition.gd`, `solar_system.tres`, `proxima_system.tres`, `game_session.gd` resolver | Player picks system only; body resolved in data | **PASS** | Solar `earth`, Proxima `proxima_b` |
| 5 | **Dev Instant Colonize Button** | `galaxy_map_hud.tscn`, `galaxy_map_hud.gd`, `galaxy_map.gd`, `game_session.gd` (`dev_instant_colonize_system`) | Debug-only fast path through real colonization ops | **PASS** | `OS.is_debug_build()` gated; no save schema change |
| 6 | **Dev Button Visibility Fix** | `galaxy_map_hud.gd` | Visible on foreign system; disabled when blocked | **PASS** | Decoupled from `access_state` / full `can_dev` gate |
| 7 | **Proxima `scan_resources`** | `proxima_b.tres`, `proxima_c.tres`, `proxima_d.tres` | Scan/Mine loop in Proxima | **PASS** | Data-only; see resource table below |
| 8 | **Lighting / Visual consistency** | `system_definition.gd`, `default_system_lighting.tres`, `system_scene.gd`, `system_light_controller.gd` | System-wide default lighting + per-system override hook | **PASS** | User-confirmed live Solar + Proxima |

### Proxima resource data (post-fix)

| Body | Basic scan | Deep scan |
|------|------------|-----------|
| **proxima_b** | Iron, Water | Carbon |
| **proxima_c** | Silicon, Copper | Carbon |
| **proxima_d** | Copper, Aluminium | Hydrogen |

---

## Current Confirmed Status

Evidence = user-confirmed Editor smoke test (2026-06-07) unless noted as static/historical.

| Area | Result | Evidence | Remaining notes |
|------|--------|----------|-----------------|
| **ColonyShip build** | **PASS (functional)** | Baseline live @ ~51:53 | **Balance NOT CLOSED** — late vs 35–45 min |
| **Water cost** | **PASS** | `colony_ship.tres`; baseline live | Water not colony blocker |
| **Dev Button** | **PASS** | Instant colonize via real op path | Release/export hidden |
| **Fixed target body** | **PASS** | `proxima_b` resolved; no body picker | Galaxy shows system name only |
| **Base on proxima_b** | **PASS** | User smoke test | `base_id == body_id` v0.1 |
| **Startkit** | **PASS** | User smoke test | Matches v0.1 new-game kit minus colony ships |
| **Discovery-Gating** | **PASS** | User smoke test | Star + base + 2 signals; not all bodies |
| **Proxima scan_resources** | **PASS** | Data + user smoke test | Replaces pre-fix FAIL in colonization audit |
| **Investigate → Scan → Mine** | **PASS** | User Proxima Expansion SmokeTest | Structural loop complete |
| **Lighting** | **PASS** | User live check | Default profile applies cross-system |
| **Save/Load in Proxima** | **NOT TESTED** | Not re-run post-fix in this closure | Not a FAIL — follow-up smoke item |

---

## Expansion Loop Result

The **structural expansion loop** is **PASS** post-fix:

```
ColonyShip bauen (Solar)
  → Zielsystem wählen (Galaxy)
  → fixed target body resolve (colonization_start_body_id)
  → Colonization operation (start → complete)
  → establish_base_at_body()
  → Startkit (_apply_colony_base_start_kit)
  → Discovery-Gating (_initialize_colony_system_discovery)
  → Proxima betreten (SystemScene; focus established base)
  → 2 Signale sichtbar
  → Investigate (SurveyProbe)
  → Scan (ScanDrone)
  → Mine (MiningShip + scan_resources deposits)
```

| Step | Pre-fix baseline | Post-fix |
|------|-------------------|----------|
| ColonyShip → Proxima travel | Worked | Works |
| New base playable | **BLOCKER** | **PASS** |
| Scan/Mine in Proxima | **BLOCKER** (no deposits) | **PASS** |
| Dev fast-path to test expansion | N/A / slow | **PASS** (debug only) |

**Save/Load after Proxima colonization:** **NOT TESTED** in post-fix closure — treat as open verification, not regression.

---

## Remaining Balance Issues

These items come from the **historical live run** and remain **open**. They are **not** structural expansion blockers.

### 1. ColonyShip timing

| Field | Detail |
|-------|--------|
| **Baseline evidence** | Built **~51:53** vs design **35–45 min**; **Iron ~700 short** @ 32:34 while Water OK |
| **Current status** | **NOT CLOSED** — no post-fix timing re-run documented |
| **Note** | Water is **no longer** the blocker |

### 2. MS2 timing

| Field | Detail |
|-------|--------|
| **Baseline evidence** | **~12:14 band** vs **7–9 min** target (capture sheet / full-run audit) |
| **Current status** | **NOT CLOSED** — not validated as fixed |
| **Note** | Do **not** bundle with ColonyShip Fe tuning in one pass |

### 3. Storage full @ ~41:53

| Field | Detail |
|-------|--------|
| **Baseline evidence** | Full storage blocked upgrades mid-run |
| **Current status** | **NOT CLOSED** — intentional capacity; UX/clarity issue |
| **Note** | Not a structural expansion blocker |

### 4. UI friction (from baseline friction log)

| Issue | Category | Status |
|-------|----------|--------|
| SensorPulse cost not visible before pulse | UI | Open |
| “Scan already in progress” during orbit-only phase | UI / state | Open |
| ObjectInfo / panels stale while open | UI | Open |
| Storage delete UX awkward | UI | Open |
| Label “Earth Base” → “Earth” | UI copy | Open |

**No balance changes recommended in this closure report** except as a **later, separate small pass** (ideally after a short verification run).

---

## What Is No Longer A Blocker

| Former blocker | Resolution |
|----------------|------------|
| **Ice impossible ColonyShip cost** | Water cost + live baseline PASS |
| **Proxima no startkit** | `_apply_colony_base_start_kit` on establish |
| **Proxima all bodies visible** | `_initialize_colony_system_discovery` + discovery controller |
| **Proxima no meaningful actions** | Startkit + units + gating |
| **Proxima no `scan_resources`** | `proxima_*.tres` data fix |
| **Dev travel to Proxima too slow for iteration** | Dev Instant Colonize (debug only) |
| **Lighting unknown / Solar-only fear** | System-wide default + user live PASS |
| **Wrong colony body ambiguity** | `colonization_start_body_id` per system |

---

## What Is Still Not Solved

| Item | Type |
|------|------|
| ColonyShip timing / **Iron 1500** cost vs session length | Balance |
| MS2 pacing (~12 min vs 7–9) | Balance |
| Storage full UX / capacity relief path | Balance + UX |
| SensorPulse cost visibility | UI |
| Scan busy / orbit state messaging | UI |
| Body **main resource identity** on Solar (design clarity) | Design / data pass |
| **Save/Load in Proxima** after post-fix colonization | Verification gap |
| Second **full normal-play** live run post-fix (no dev colonize) | Verification gap |

**Explicitly not recommended here:**

- Save-v2
- Further architecture splits
- CargoShip scope
- Removing all production limits

---

## Recommended Next Step

**One recommendation:** Run **one short post-fix balance verification** (20–30 min focused **Solar → ColonyShip** economy check, normal play, no dev colonize) **or** write a **small Balance Design Report** before changing any values.

If a data fix is needed after that run:

- Adjust **only ColonyShip Iron** first (`colony_ship.tres` **1500 → lower candidate**)
- Do **not** simultaneously change MS2, SurveyData, Storage caps, or production limits

**Do not** treat structural expansion as incomplete — expansion loop closure is **PASS**; remaining work is **balance + UX + optional Save/Load verification**.

---

## Acceptance (this report)

1. Only `docs/audits/expansion_loop_postfix_closure_v0_1.md` created.  
2. No code, scene, or data files changed.  
3. Water Recheck documented as **historical pre-fix baseline**.  
4. Post-fix state documented with user-confirmed PASS items.  
5. Structural fixes separated from balance/UI open items.  
6. Balance **not** claimed closed.  
7. Exactly **one** next recommendation.  
8. `tooltip_text` remains **0**.

---

## Files reviewed (read-only)

- `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md`
- `docs/audits/colonization_expansion_devtools_lighting_audit_v0_1.md`
- `docs/audits/core_loop_balance_full_run_v0_1.md`
- `data/production/colony_ship.tres`
- `data/celestial_bodies/proxima_system/*.tres`
- `data/galaxy_systems/proxima_system.tres`
- `data/galaxy_systems/solar_system.tres`
- `resources/definitions/system_definition.gd`
- `scripts/autoload/game_session.gd`
- `scripts/autoload/stores/base_store.gd`
- `scripts/system/system_scene.gd`
- `scripts/galaxy/galaxy_map.gd`
- `scripts/ui/galaxy/galaxy_map_hud.gd`
- `scenes/ui/galaxy/galaxy_map_hud.tscn`
