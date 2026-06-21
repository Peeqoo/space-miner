# SharedScanJob Step 6 — UI Assign ScanDrone v0.1

**Date:** 2026-06-07  
**Status:** Done — Multi-SD assignment enabled, no speed scaling, SAVE_VERSION 1

---

## Audit Summary

| # | Question | Answer |
|---|----------|--------|
| 1 | Scan button text | `object_info_panel.tscn` default `"Scan"`; `SystemUIController` sets `"Assign ScanDrone"` when active SharedScanJob |
| 2 | `can_scan_object` + active scan | `_apply_scan_drone_info_to_dict`, `launch_scan_drone`, `_on_object_scan_requested` |
| 3 | `KEY_SCAN_ALREADY_IN_PROGRESS` | `GameSession.can_scan_object` when `target_has_active_scan=true` |
| 4 | UI states | Via `has_active_shared_scan_job_for_target` vs assign gate vs support-only (no active job) |
| 5 | Idle ScanDrones | `AutomationController.idle_drones` / `_get_idle_drone()` |
| 6 | Existing count UI | `active_scan_drone_count` in orbit labels; new `ScanDroneCountLabel` mirrors MiningShip pattern |
| 7 | `.tscn` change | Added `ScanDroneCountLabel` in `OrbitStatusSection` |

---

## Gate Decision

**Fall A — New scan:** `launch_scan_drone()` unchanged semantics; `target_has_active_scan` now means **active SharedScanJob** (not support-only assignment).

**Fall B — Assign:** `can_assign_scan_drone_to_shared_job()` + `assign_scan_drone_to_shared_job()` — separate path, no `KEY_SCAN_ALREADY_IN_PROGRESS`.

`KEY_SCAN_ALREADY_IN_PROGRESS` **retained** for new scan attempts while a SharedScanJob is active.

---

## Assign Runtime

- No new `AutomationStore` mission for assign drones (`mission_id = 0`).
- `_on_assign_scan_drone_arrived_at_target` → support orbit only (no completion).
- Primary mission drone still uses SharedScanJob completion pipeline once.

---

## Save/Restore

**No SAVE_VERSION change.** Existing `scan_missions[]` + store missions sufficient.

`_sync_shared_scan_job_assignments_from_target_map()` rebuilds multi-assign after load/galaxy.

---

## Tests

`shared_scan_job_step_6_ui_assign_scan_drone_smoke_test.gd` — A–G + regression.

**Results (2026-06-07):**

| Suite | Result |
|-------|--------|
| Step 6 smoke (A–G) | PASS WITH NOTES |
| Step 5 save/restore regression | PASS |
| Step 4 single-drone regression | PASS |
| Step 2 telemetry regression | PASS |
| ObjectInfo Multi-MS UI regression | PASS |
| SAVE_VERSION | 1 (unchanged) |
| tooltip_text | 0 |

---

## Risks

1. Support-only drones no longer block new scan layer (intended for deep scan after basic).
2. Assign drones in flight when primary completes — mapping cleared with job; support orbit preserved.
3. No speed stacking yet — `assigned_unit_count > 1` is telemetry/UI only.
