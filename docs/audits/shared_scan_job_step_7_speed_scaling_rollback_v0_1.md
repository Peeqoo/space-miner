# SharedScanJob Step 7 Speed Scaling Rollback v0.1

**Date:** 2026-06-07  
**Godot:** 4.6.1 / strictly typed GDScript  
**Status:** Rollback complete — wrong Step 7 speed scaling removed; Steps 4–6 preserved.

**Supersedes (design only):** `docs/audits/shared_scan_job_step_7_speed_scaling_v0_1.md`

---

## Audit Summary

Wrong Step 7 treated multiple ScanDrones as a scan-speed multiplier with sqrt diminishing returns. Correct design: multiple ScanDrones stack existing `.tres` / `UpgradeDefinition` effects (e.g. +2% mining support per drone), **not** scan duration.

---

## Removed (wrong Step 7)

| Area | Removed |
|------|---------|
| `GameBalanceDefinition` | `shared_scan_extra_drone_sqrt_bonus`, `shared_scan_max_speed_multiplier`, `get_shared_scan_speed_multiplier_for_arrived_count()` |
| `AutomationController` | `arrived_unit_ids`, `effective_speed_multiplier`, `_get_shared_scan_speed_multiplier()`, `_process_shared_scan_jobs()`, `_register_shared_scan_job_unit_arrived()`, progress tick, `_resolve_work_required_for_scan_layer()` for speed, `capture/restore_shared_scan_jobs_*`, `shared_scan_jobs` in `to_save_data()` / `apply_save_data()`, `get_shared_scan_job_status_for_target()` |
| `GameSession` / `SystemScene` | GalaxyMap `shared_scan_jobs` snapshot restore |
| UI | `ScanSpeedLabel`, `ScanProgressLabel`, `_apply_shared_scan_job_status_to_dict()` |
| Tests | `shared_scan_job_step_7_speed_scaling_smoke_test.gd` + runner |
| Docs | Step 7 speed scaling marked superseded in design plan |

---

## Preserved (Steps 3–6)

| Step | Feature |
|------|---------|
| 3 | `shared_scan_jobs_by_job_id` runtime model, debug snapshot, telemetry `shared_scan_jobs` |
| 4 | SharedScanJob completion owner; instant completion on primary arrival; `progress = work_required = 1.0` |
| 5 | Save/restore via `scan_missions[]` rebuild (`_validate_shared_scan_jobs_after_restore`) — no `SAVE_VERSION` bump |
| 6 | `assign_scan_drone_to_shared_job()`, `assigned_unit_ids` multi-assign, UI “Assign ScanDrone”, `KEY_SCAN_ALREADY_IN_PROGRESS` for new scan path |

Unchanged: `SAVE_VERSION = 1`, `tooltip_text = 0`, no balance/cost changes.

---

## Restored Behavior

- Primary scan drone arrival → `_mark_shared_scan_job_ready_for_completion` + `_apply_shared_scan_job_completion` (once).
- Additional assigned drones → support orbit only (`_on_assign_scan_drone_arrived_at_target`); no completion, no reward.
- `work_required = SHARED_SCAN_JOB_WORK_REQUIRED` (1.0), not scan-layer duration.
- No `_process` tick for shared scan progress.

---

## Tests

- **New:** `shared_scan_job_step_7_speed_scaling_rollback_smoke_test.gd`
  - A: No forbidden speed symbols in core files
  - B: Multi-assign `assigned_unit_count = 2`, no duplicate reward/ScanState
  - C: `work_required` not scan-duration-based; completion once
  - D: SAVE_VERSION, tooltip, Step 6 API, telemetry keys

**Regression (run separately):**

- Step 6 UI Assign smoke
- Step 5 Save/Restore smoke
- Step 4 Single-Drone Processing smoke
- Step 3 Runtime Model smoke
- Step 2 Telemetry smoke

---

## Known Risks

1. **Galaxy roundtrip during in-flight scan** — Step 7 had elapsed-progress capture; rollback restores Step 5 rebuild-only. Jobs survive if `scan_missions[]` restore is consistent.
2. **Save slot with legacy `shared_scan_jobs[]`** — Field ignored on load; harmless extra data in old saves.
3. **Future Step 7 (correct)** — Effect stacking per drone must not reintroduce scan-duration multipliers.

---

## Acceptance

| # | Criterion | Status |
|---|-----------|--------|
| 1 | No scan-speed formula from drone count | Done |
| 2 | No diminishing-returns constants | Done |
| 3 | No UI “Scan Speed x…” | Done |
| 4 | No telemetry implying multi-SD speed | Done |
| 5–8 | Steps 4–6 + multi-assign | Preserved |
| 9–10 | Reward + ScanState once | Preserved |
| 11–12 | SAVE_VERSION 1, tooltip_text 0 | Preserved |
