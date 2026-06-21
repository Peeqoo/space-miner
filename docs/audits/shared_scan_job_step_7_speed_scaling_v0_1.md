# SharedScanJob Step 7 — Speed Scaling v0.1

**Date:** 2026-06-07  
**Status:** **SUPERSEDED / REVERTED** — see `docs/audits/shared_scan_job_step_7_speed_scaling_rollback_v0_1.md`

> This audit documents a **design-wrong** implementation. Multiple ScanDrones must **not** reduce scan duration. The correct Step 7 is effect stacking from existing upgrade definitions.

---

## Audit Summary

| # | Question | Answer |
|---|----------|--------|
| 1 | Scan duration | `GameSession.get_scan_duration_seconds_for_target_state()` + upgrade multiplier via `BaseStore` |
| 2 | Upgrade effect on duration | `scan_duration_multiplier` on ScanDrone upgrades reduces duration |
| 3 | SharedScanJob progress | Step 4–6: placeholder `work_required=1`, instant on arrival; Step 7: real duration |
| 4 | Completion timing (pre-Step 7) | Instant on `arrived_at_target` (approach orbit complete) |
| 5 | assigned_unit_ids | `_assign_scan_drone_to_shared_scan_job()` |
| 6 | Speed contributors | **arrived_unit_ids** only (ORBITING_BASE/WORKING at target) |
| 7 | GalaxyMap elapsed | `capture_shared_scan_jobs_runtime_snapshot()` + `restore_shared_scan_jobs_from_runtime_snapshot(away_seconds)` |
| 8 | Save/Load progress | Optional `automation.runtime.shared_scan_jobs[]` (no SAVE_VERSION bump) |

---

## Speed Formula

Central constants in `GameBalanceDefinition`:

- `shared_scan_extra_drone_sqrt_bonus = 0.6`
- `shared_scan_max_speed_multiplier = 2.5`

```gdscript
multiplier = min(max, 1.0 + sqrt(arrived_count - 1) * bonus)  # arrived_count > 1
multiplier = 1.0  # arrived_count <= 1
```

Examples: 1→1.0, 2→1.6, 3→~1.85, 4→~2.04, 5+→capped at 2.5

---

## Progress Model

- `work_required` = scan layer duration (upgrades applied) at job creation
- `progress += delta * effective_speed_multiplier` when `arrived_unit_ids.size() > 0`
- Completion via `_process_shared_scan_jobs()` → `_apply_shared_scan_job_completion()` once
- **Solo shortcut (1 assigned, 1 arrived):** instant completion on arrival (preserves Step 4–6 baseline / regressions)
- **Multi-drone:** time-based progress after arrivals

---

## UI

ObjectInfo during active SharedScanJob:

- ScanDrones assigned: N
- Scan Speed: x1.60
- Scan Progress: 47% (ETA optional)

---

## Telemetry

`get_shared_scan_job_debug_snapshot()` per job:

- `assigned_unit_count`, `arrived_unit_count`, `effective_speed_multiplier`
- `progress`, `work_required`, `progress_percent`, `estimated_remaining_seconds`
- Top-level: `shared_scan_extra_drone_sqrt_bonus`, `shared_scan_max_speed_multiplier`, `max_shared_scan_speed_multiplier`

---

## Save / GalaxyMap

- Save: `automation.runtime.shared_scan_jobs[]` (additive field, SAVE_VERSION 1)
- Load: restore after mission validate; merge progress
- Galaxy: pending `shared_scan_jobs` + `captured_at_msec` → apply away elapsed at multiplier

---

## Tests

`shared_scan_job_step_7_speed_scaling_smoke_test.gd` — A–G + regression.

**Results (2026-06-07):** PASS

| Regression | Result |
|------------|--------|
| Step 6 | PASS WITH NOTES |
| Step 5 | PASS |
| Step 4 | PASS |
| SAVE_VERSION | 1 |
| tooltip_text | 0 |

---

## Risks

1. Solo shortcut vs multi path divergence — intentional for baseline parity.
2. Progress ticks only after arrival — in-flight drones do not contribute.
3. Save restore order matters — shared jobs applied after mission validate.
4. Galaxy + automation runtime double-restore — pending snapshot authoritative for elapsed.
