# SharedScanJob Step 5 — Save/Restore v0.1

**Date:** 2026-06-07  
**Status:** Done — **Option B**, SAVE_VERSION unchanged

---

## Decision

**Option B — Minimal runtime restore fix**

- No new save fields.
- `SAVE_VERSION = 1`.
- SharedScanJobs rebuilt from `active_units_by_mission_id` + `AutomationStore.missions` after restore.

See audit: `docs/audits/shared_scan_job_step_5_save_restore_audit_v0_1.md`

---

## Data Sources for Rebuild

| Field | Source |
|-------|--------|
| `system_id` | `GameSession.current_system_id` |
| `target_id` | `scan_drone_target_by_unit_id` |
| `target_scan_state` | `automation.store.missions[mission_id]` or `get_scan_target_state_or_rescan_state()` |
| `scan_is_progression` | Store mission record |
| `mission_id` | `active_units_by_mission_id` |
| `unit_id` | Spawned `AutomationUnit` instance |

**Not persisted:** `shared_scan_jobs_by_job_id` (runtime-only).

---

## Load / Restore Order

1. `SaveManager.load_game()` → `GameSession.apply_save_data()`
2. `_apply_automation_from_save_data()` → store missions + `_automation_runtime_pending`
3. `SystemScene._finish_initial_setup()` → `apply_automation_save_if_pending()`
4. `_clear_automation_visuals_and_mission_state()` (clears stale shared jobs)
5. `apply_save_data(runtime)` → `_restore_scan_mission()` per job
6. `_validate_shared_scan_jobs_after_restore()` → rebuild + orphan cleanup

Galaxy roundtrip: `capture_system_scene_processes_before_leave()` → same pending runtime path.

---

## New Methods

| Method | Purpose |
|--------|---------|
| `_rebuild_shared_scan_jobs_from_active_scan_missions()` | Create/assign jobs for live scan missions |
| `_validate_shared_scan_jobs_after_restore()` | Rebuild + remove stale jobs |

**Rules:** No rewards, no ScanState changes, no extra missions, no drone consumption.

---

## Completed Scan on Load

- `scan_reveal_done=true` in runtime snapshot.
- No active store mission.
- Support orbit via `scan_drone_target_by_unit_id` only.
- **No** active SharedScanJob restored.

---

## Tests

`scripts/debug/smoke_tests/shared_scan_job_step_5_save_restore_smoke_test.gd`

- A: Active scan save/load, job reconstructed, no reward on load
- B: Completion after load, reward once
- C: Completed scan save/load, no active job, no duplicate reward
- D: Galaxy + save + load + completion once
- E: Reset clears shared job dicts

---

## Risks

1. **Rebuild depends on store mission** — if mission missing but unit active, job not rebuilt (warn path in Step 4 arrival).
2. **Double validate** — called from `apply_save_data` and `_restore_automation_runtime_when_ready` (harmless idempotent).
3. **Support-orbit saves** — correctly excluded from active job rebuild.

---

## Status

- Step 5 done.
- SAVE_VERSION unchanged.
- No Multi-SD.
- `KEY_SCAN_ALREADY_IN_PROGRESS` unchanged.
