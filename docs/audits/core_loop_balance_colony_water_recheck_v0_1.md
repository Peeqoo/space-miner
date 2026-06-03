# Core Loop Balance Colony Water Recheck v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Scope:** Recheck after ColonyShip cost **Ice → Water** (`data/production/colony_ship.tres`).  
**Method:** Static repo verification + functional checklist (Editor playtest **not executed in audit environment**).  
**References:** `docs/audits/core_loop_balance_full_run_v0_1.md`, `docs/audits/phase_3_mining_loop_proof_v0_1.md`

**No code, scene, data, or balance changes in this step.**

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Water-Fix valid?** | **Yes (static)** — active production cost is **350 Water**; Water is mineable on Earth/Mars |
| **Impossible Ice blocker removed?** | **Yes (static)** — no **Ice** in active `ProductionDefinition` cost; spend path uses `can_afford` / `spend_cost` on **Water** id |
| **ColonyShip realistic in 35–45 min after fix?** | **Partially** — **Water 350** is achievable in-session; **Fe 1500 / Si 300 / SurveyData 150** still likely block **build by 45:00** (per Round 2 modeled economy; live run **NOT TESTED**) |
| **New blockers after Water-Fix** | **None for impossible resources**; remaining gates: **bulk costs**, **prereqs**, **MS2 pacing** (unchanged) |
| **Balance changes allowed after this step?** | **Yes** — only after live **45:00** confirmation; do **not** bundle MS2/Fe/Si/SD changes with this fix |

---

## Static Data Check

| Check | Expected | Result | Notes |
|-------|----------|--------|-------|
| ColonyShip cost uses **Water** | `colony_ship.tres` → `"Water": 350` | **PASS** | Verified in repo |
| No active ColonyShip **Ice** cost | No Ice key in `data/production/colony_ship.tres` | **PASS** | Only production file defines active build cost (`get_colony_ship_build_cost()` prefers production) |
| Water deposit exists | Body `scan_resources` with `Water` | **PASS** | `earth.tres` (12k deposit, 70% richness), `mars.tres` |
| Water mineable / storable | Mining → `BaseStore.add_resource`; no catalog block on spend | **PASS** | `add_resource` / `can_afford` / `spend_cost` use string id; no `is_deposit_resource` check on spend |
| Prereq accepts Water source | `colony_ship_ice_resource_ids` includes **Water** | **PASS** | `GameBalanceDefinition` default `["Ice", "Water"]`; `has_discovered_ice_source()` matches Water on scanned Earth |
| Save/Load not touched | No save schema change for this fix | **PASS** | Cost id change only affects new spends |
| No `data/planet_resources/survey_data.tres` | File absent | **PASS** | Glob: **0** files |
| `tooltip_text` = 0 | No tooltips in gd/tscn/tres | **PASS** | Repo grep: **0** |

### Static detail — active cost source

```9:14:data/production/colony_ship.tres
cost = {
"Water": 350,
"Iron": 1500,
"Silicon": 300,
"SurveyData": 150
}
```

**Fallback (inactive in normal play):** `GameBalanceDefinition.colony_ship_build_cost` still lists **350 Ice** in script defaults. Used only if `get_production_cost("colony_ship")` is empty. Production catalog is bound at runtime → **Water** is authoritative.

**Ice in catalog:** `resource_catalog.tres` still defines **Ice** with `is_deposit_resource = false` (not a deposit). Irrelevant to Colony build after fix; no solar-body Ice deposits found.

---

## Functional Check

**Status:** **NOT TESTED** in this audit (Godot Editor not available in audit shell).  
**Does not downgrade static PASS** — live confirmation required.

| Step | Expected | Result | Notes |
|------|----------|--------|-------|
| Water source scanned | Earth basic scan shows Water | **NOT TESTED** | Static: Water in `earth.tres` `scan_resources` |
| Water mined | Cargo / storage gains Water | **NOT TESTED** | Code path: finite extract → unload |
| Storage shows Water > 0 | Base storage panel | **NOT TESTED** | — |
| ColonyShip panel shows **Water** cost | Hover/cost line lists Water **350** | **NOT TESTED** | `production_panel` uses `get_colony_ship_build_cost()` |
| No **Ice** `blocked_reason` | Never “missing Ice” when Water mined | **NOT TESTED** | Block key `colony_not_enough_resources` if any cost short |
| Build succeeds when all met | `build_colony_ship` true | **NOT TESTED** | Needs Fe/Si/SD/prereqs + **350 Water** |
| Water deducted on build | Water −350 | **NOT TESTED** | `spend_cost` iterates cost dict |
| ColonyShip count +1 | `colony_ships` += 1 | **NOT TESTED** | `base_store.build_colony_ship` |

### Editor retest checklist (human)

1. New Game → investigate + basic scan **Earth**.  
2. Mine until **Water ≥ 350** (log time).  
3. Open Production → Colony Ship: cost shows **Water**, not Ice.  
4. With debug or grind: meet **1500 Fe, 300 Si, 150 SD** + all prereqs → build once.  
5. Confirm storage **Water −350**, **colony_ships +1**, no errors.

---

## Optional Full Run Timeline

**NOT TESTED** — no live 35–45 min stopwatch session after Water-Fix.

| Time | Event | Fe | Si | Water | SurveyData | Notes |
|------|--------|----|----|-------|------------|-------|
| — | — | — | — | — | — | Run in Editor and paste rows here |

**Pre-fix reference (MODELED, Round 2):** @ 45:00 Fe ~900, Si ~200, SD ~125, **Ice 0** → colony not built.  
**Post-fix expectation (MODELED, not measured):** Water **≥350** achievable by ~25–35 min with Earth water mining; colony build still blocked by **Fe / SD** unless pacing improves.

---

## Target vs Actual After Water Fix

Ratings use Round 2 **MODELED** early/mid curve + static post-fix analysis. **Live 45:00 not run.**

| Target | Actual (post Water-Fix) | Rating |
|--------|-------------------------|--------|
| MS2 **7–9 min** | **~12–14 min** (unchanged) | **Late** |
| First upgrade **10–12 min** | Storage I **~3:25** (unchanged) | **Early** |
| Deep Scan **15–18 min** | First deep **~9:55** (unchanged) | **Early** |
| Storage/Control **20–25 min** | Light pressure ~20 min (unchanged) | **On Target** |
| Colony prep **30–35 min** | Prereqs **~19–30 min** (unchanged) | **On Target** |
| ColonyShip buildable **35–45 min** | **Ice blocker removed**; **Fe/SD wall** likely remains @ 45 | **Late / Partial** — Water no longer hard-impossible |

---

## Remaining Balance Issues

Max **3** — evidence-based; **no changes in this step**.

### 1. Colony bulk cost (Fe / SurveyData) vs 45 min

| Field | Detail |
|-------|--------|
| **Evidence** | Round 2 MODELED @ 45:00: Fe **~900** / need **1500**; SD **~125** / need **150**; Water fix does not change these keys |
| **Smallest fix** | Separate data pass: e.g. Fe **1500→1100** *or* SD **150→100** (pick one after live 45:00) |
| **Risk** | Shortens endgame; validate colony loop intent |

### 2. MS2 pacing (unchanged)

| Field | Detail |
|-------|--------|
| **Evidence** | Round 1/2: **240 Fe + 40 Si**; affordable **~12 min** vs target **7–9** |
| **Smallest fix** | Si **40→28** or Fe **240→180** in `mining_ship.tres` only |
| **Risk** | Faster dual-ship snowball |

### 3. Storage Upgrade I early (unchanged)

| Field | Detail |
|-------|--------|
| **Evidence** | **~3:25** vs **10–12** target; **30 Fe + 10 Cu** |
| **Smallest fix** | **30→50 Fe** in `storage_1_upgrade.tres` |
| **Risk** | Low |

**Not listed:** Water amount **350** — obtainable from Earth deposit; no evidence it blocks 45 min once mining runs.

---

## Recommendation

**One next step:** Run a **live 45:00 New Game** after Water-Fix and fill **Functional Check** + **Optional Full Run Timeline** in this doc (or update `core_loop_balance_full_run_v0_1.md`).

**PASS WITH NOTES — if live 45:00 confirms Fe/SD gap, consider at most 1–3 data-only tweaks in a separate step (not combined with Water fix):**

1. Colony **SurveyData 150→100** *or* raise deep-scan SD reward (pick one).  
2. Colony **Iron 1500→1200** (only if build still unreachable @ 45).  
3. MS2 **Si 40→28** (only if MS2 pacing still priority).

**Do not** re-open Ice cost unless Ice deposits are added to bodies intentionally.

---

## Acceptance (this report)

1. No code, scene, or data files changed.  
2. Only `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md` created.  
3. Water-Fix statically verified.  
4. Report states: **Ice impossible-cost blocker removed** (active production path).  
5. Report states: **ColonyShip can still be blocked by Fe / Si / SurveyData / prereqs** — not by missing Ice.  
6. No MS2 or colony bulk cost changes in this step.  
7. `tooltip_text` remains **0**.
