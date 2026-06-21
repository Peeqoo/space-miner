# SharedScanJob Step 5 — Save/Restore Audit v0.1

**Date:** 2026-06-07  
**Godot:** 4.6.1 / strictly typed GDScript

---

## Audit Questions

| # | Question | Finding |
|---|----------|---------|
| 1 | Active ScanMissions in Save v1? | **Yes** — `automation.runtime.scan_missions[]` |
| 2 | Saved fields | `mission_id`, `target_id`, `base_id`, `unit_state`, `work_timer`, `work_duration`, `travel_progress`, `scan_reveal_done`, orbit/position fields. `system_id` on runtime root. `target_scan_state` + `scan_is_progression` in `automation.store.missions` |
| 3 | Full SharedScanJob reconstruct? | **Yes** — from store mission + runtime scan job via `_restore_scan_mission()` → `_reconstruct_shared_scan_job_for_restored_mission()` |
| 4 | Load vs Galaxy restore | **Same path** — both use `_automation_runtime_pending` → `apply_automation_save_if_pending()` → `apply_save_data()` |
| 5 | Stale jobs after Load/NewGame? | Cleared in `_clear_automation_visuals_and_mission_state()` before restore; fresh controller on new scene |
| 6 | Completion after Load once? | Yes — Step 4 pipeline; mission store + `completion_applied` guard |
| 7 | Reward already applied before save? | ScanState in `object_scans`; completed scans save with `scan_reveal_done=true`, no store mission → no re-completion |
| 8 | Persist SharedScanJob? | **Not required** — reconstruct from store + runtime |

---

## Decision: **Option B**

Existing Save v1 data is sufficient. Step 5 adds a **runtime rebuild/validate safety net** without new save fields.

**SAVE_VERSION:** remains `1`.

---

## Gaps Addressed

- `_restore_scan_mission` already reconstructs per job; rebuild covers ordering gaps or partial restore.
- `_validate_shared_scan_jobs_after_restore()` removes orphaned jobs without live store missions.
- Called after `apply_save_data()` and `_restore_automation_runtime_when_ready()`.

---

## Not Option C

No missing save fields identified. `target_scan_state` is in `AutomationStore.missions`; runtime carries mission linkage and visual state.
