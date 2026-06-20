# SharedScanJob Step 3 — Runtime Model v0.1

**Date:** 2026-06-07  
**Godot:** 4.6.1 / strictly typed GDScript  
**Scope:** Internal runtime model only — **no Multi-SD unlock, no gameplay change, SAVE_VERSION unchanged.**

---

## Audit Summary

| # | Question | Location |
|---|----------|----------|
| 1 | ScanDrone launch | `AutomationController.launch_scan_drone()` |
| 2 | `mission_id` creation | `GameSession.create_scan_mission()` |
| 3 | `unit_id → target_id` | `scan_drone_target_by_unit_id` in `launch_scan_drone()` |
| 4 | `target_scan_state` storage | `AutomationStore.missions[mission_id]` via `create_scan_mission()` |
| 5 | `_complete_scan_mission()` | Called from `_on_scan_drone_arrived_at_target()` (now via guard wrapper) |
| 6 | SurveyData reward | `GameSession.grant_scan_survey_data_reward()` inside `_complete_scan_mission()` |
| 7 | ScanState set | `GameSession.set_object_scan_state()` inside `_complete_scan_mission()` |
| 8 | Support orbit after completion | `_on_scan_drone_arrived_at_target()` → `unit.transfer_orbit_to_base(target_node)` |
| 9 | GalaxyMap scan restore | `_restore_scan_mission()` from pending automation snapshot |
| 10 | Clear / reconstruct | `_clear_automation_visuals_and_mission_state()` clears jobs; `_restore_scan_mission()` reconstructs active jobs |

---

## Runtime Data Model

**Dictionaries on `AutomationController`:**

- `shared_scan_jobs_by_job_id: Dictionary`
- `shared_scan_job_id_by_unit_id: Dictionary`

**Job ID:** `{system_id}:{target_id}:{target_scan_state}`

**Job dict fields:** `job_id`, `system_id`, `target_id`, `base_id`, `target_scan_state`, `scan_layer`, `scan_is_progression`, `assigned_unit_ids`, `active_mission_ids`, `progress`, `work_required`, `completed`, `completion_applied`, `reward_given`, `created_at_msec`, `completed_at_msec`.

Step 3: `progress` / `work_required` are placeholders only; scan still completes on arrival/WORKING entry.

---

## Helper / Debug APIs

| Method | Visibility | Purpose |
|--------|------------|---------|
| `_make_shared_scan_job_id` | private | Build job key |
| `_create_shared_scan_job_for_scan_mission` | private | Create job dict |
| `_assign_scan_drone_to_shared_scan_job` | private | Link unit + mission |
| `_get_shared_scan_job_for_unit` | private | Lookup by unit |
| `_mark_shared_scan_job_completed` | private | Guard flags + remove active job |
| `_clear_shared_scan_job_for_unit` | private | Abort / cleanup |
| `_clear_all_shared_scan_jobs` | private | Scene reset |
| `_try_complete_scan_mission_with_shared_job_guard` | private | Duplicate-completion guard |
| `_reconstruct_shared_scan_job_for_restored_mission` | private | Galaxy restore |
| `get_shared_scan_job_debug_snapshot` | read-only | Telemetry / debug |
| `get_active_shared_scan_job_count` | read-only | Active job count |
| `get_shared_scan_job_count_for_target` | read-only | Per-target count |

---

## Launch Integration

After existing gate + `create_scan_mission()` in `launch_scan_drone()`:

1. Create SharedScanJob with `work_duration` as `work_required` placeholder.
2. Assign unit + mission to job.
3. Set `shared_scan_job_id_by_unit_id[unit_id]`.

`KEY_SCAN_ALREADY_IN_PROGRESS` gate unchanged — second drone on same target still blocked.

---

## Completion Guard

`_on_scan_drone_arrived_at_target()` calls `_try_complete_scan_mission_with_shared_job_guard()`:

- If `completion_applied` already true → warning, skip `_complete_scan_mission()`.
- Else run existing `_complete_scan_mission()` unchanged.
- Mark job `completion_applied`, `reward_given = scan_is_progression`, remove from active maps.

No ScanReward, ScanState, or timing changes.

---

## Restore / Reset

| Event | Behavior |
|-------|----------|
| Galaxy restore (active scan) | `_restore_scan_mission()` reconstructs job from mission/gate data; no reward |
| `_clear_automation_visuals_and_mission_state()` | `_clear_all_shared_scan_jobs()` |
| Abort / empty mission | `_clear_shared_scan_job_for_unit()` |
| New game / scene reload | Fresh controller — empty dicts |

**SAVE_VERSION:** remains `1`. SharedScanJobs are runtime-only (not persisted).

---

## Telemetry

`BalanceTelemetryLogger._snap_scan_target_telemetry()` adds:

```json
"shared_scan_jobs": {
  "enabled": true,
  "active_count": N,
  "jobs": { "solar-system:mars:basic": { ... } }
}
```

Step 2 fields (`assigned_drones_per_target`, etc.) unchanged.

---

## Tests

- `scripts/debug/smoke_tests/shared_scan_job_step_3_runtime_model_smoke_test.gd`
- Regression: `shared_scan_telemetry_step_2_smoke`, `galaxy_transition_process_continuity_smoke`

---

## Risks

1. **Runtime-only jobs** — save/load mid-scan relies on existing `scan_missions[]` restore + reconstruction (same as pre-Step-3 mission restore).
2. **Completed job removal** — only one completion path — debug snapshot shows active jobs only.
3. **Multi-SD later** — gate + job uniqueness by `(system, target, scan_state)` must be updated together in Step 4+.

---

## Status

**Step 3 Runtime Model done.**

- No Multi-SD unlock.
- No UI Assign.
- No progress-speed stacking.
- `KEY_SCAN_ALREADY_IN_PROGRESS` unchanged.
- Save version unchanged.
