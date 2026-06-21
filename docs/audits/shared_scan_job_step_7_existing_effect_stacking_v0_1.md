# SharedScanJob Step 7 — Existing Effect Stacking v0.1

**Date:** 2026-06-07  
**Godot:** 4.6.1 / strictly typed GDScript  
**Status:** Done — linear stacking of data-driven ScanDrone support effects; no scan-speed scaling.

---

## Audit Answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Where is support bonus defined? | `UpgradeDefinition.mining_yield_bonus_per_support_drone_percent` in scan_drone `.tres` files |
| 2 | Field name | `mining_yield_bonus_per_support_drone_percent` (integer percent) |
| 3 | Applied to mining before Step 7? | Yes — `get_mining_bonus_for_target()` → mining tick `effective_rate = rate * (1 + bonus)` |
| 4 | Only 1 drone counted? | **Yes** — `get_active_scan_drone_support_count_for_target()` returned `1` max |
| 5 | Support count API? | `get_active_scan_drone_support_count_for_target` / `get_scan_drone_support_counts_by_target` |
| 6 | Capped at 1? | Mining bonus path capped at **1**; telemetry `support_drones_per_target` was already uncapped |
| 7 | Final mining rate | `automation_controller.gd` mining `_process`: `mining_rate * (1 + get_mining_bonus_for_target())` |
| 8 | Upgrade II interpretation | **Replaces** per-drone percent on active tier (`scan_drone_2_upgrade.tres` = 3%, not 2%+3%) |
| 9 | Single source of truth | Active scan_drone `UpgradeDefinition` via `GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(base_id)` |

---

## .tres Values (data-driven)

| Tier | File | `mining_yield_bonus_per_support_drone_percent` |
|------|------|-----------------------------------------------|
| 0 | `scan_drone_0_base.tres` | 2 |
| I | `scan_drone_1_upgrade.tres` | 2 |
| II | `scan_drone_2_upgrade.tres` | 3 |

No new constants added in code.

---

## Pre-Step-7 Bonus Calculation

```gdscript
# Capped: first supporting drone only
bonus = per_drone_percent / 100.0   # e.g. 0.02
effective_rate = mining_rate * (1.0 + bonus)
```

Support during **active scan mission** was inconsistently counted via `_is_scan_drone_providing_mining_support_at_target` (included `WORKING`).

---

## Step 7 Fix

1. `get_scan_drone_support_effect_count_for_target()` — delegates to uncapped `get_scan_drone_support_counts_by_target()` (support orbit only, no active scan mission).
2. `get_mining_bonus_for_target()` — `support_count * per_drone_percent / 100.0`.
3. `get_scan_drone_support_effects_by_target()` — telemetry snapshot per target.
4. UI unchanged structurally — `mining_bonus_label` already used `drone_supporting * per_drone_pct`.

**Formula:**

```
support_bonus_total = support_count × (mining_yield_bonus_per_support_drone_percent / 100)
mining_rate_multiplier = 1.0 + support_bonus_total
```

Examples at tier 0 (2% per drone): 1→1.02, 2→1.04, 3→1.06.

---

## Unchanged

- Scan duration / `work_duration` (upgrade multiplier only)
- SharedScanJob progress / completion
- SurveyData reward / ScanState
- SAVE_VERSION = 1
- No tooltips

---

## Tests

`shared_scan_job_step_7_existing_effect_stacking_smoke_test.gd` — Tests A–G + regression.

---

## Risks

1. **Support during in-flight scan** — Drones on active scan mission do not count (by design). Bonus applies after support orbit only.
2. **Mixed upgrade tiers** — All drones use session base's current scan_drone tier percent (existing upgrade model).
3. **Recall / assign edge cases** — Support count follows `get_scan_drone_support_counts_by_target` visual rules.
