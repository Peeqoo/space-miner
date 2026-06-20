# SharedScanJob Step 2 Telemetry v0.1

**Date:** 2026-06-20  
**Godot:** 4.6.1  
**Scope:** Telemetry / debug measurement only — **no scan gameplay unlock**.

---

## Audit Summary

| Question | Answer |
|----------|--------|
| What does `get_active_scan_drone_count_for_target` count? | **All** entries in `scan_drone_target_by_unit_id` for that `target_id` (in-flight scan + post-completion support). |
| Active scans + support together? | **Yes** — same counter drives `KEY_SCAN_ALREADY_IN_PROGRESS` via `launch_scan_drone()`. |
| Method for true active scan missions? | **Added (read-only):** `get_active_scan_mission_counts_by_target()` — counts `active_units_by_mission_id`. |
| Method for support drones? | **Added (read-only):** `get_scan_drone_support_counts_by_target()` — `ORBITING_BASE` at target, no active mission. Existing `get_active_scan_drone_support_count_for_target()` caps at **1** (mining bonus). |
| Where is `KEY_SCAN_ALREADY_IN_PROGRESS`? | `GameSession.can_scan_object()` when `target_has_active_scan == true`. |
| Was block reason in telemetry before? | **No** — now `already_in_progress_blocks` + `already_in_progress_block_targets`. |
| Data without gameplay change? | **Yes** — read-only dict walks + `can_scan_object()` (no mutation). |

### Support drones blocking future scans

**Yes, today.** Any assignment in `scan_drone_target_by_unit_id` makes `get_active_scan_drone_count_for_target > 0`, so `KEY_SCAN_ALREADY_IN_PROGRESS` blocks the next scan — including support-only orbit after completion.

`potential_support_blocks[target] == true` when assigned/support > 0 but `active_scan_missions == 0`.

---

## New Telemetry Fields (`scan` section)

| Field | Meaning | Exact? |
|-------|---------|--------|
| `assigned_drones_per_target` | Count from `scan_drone_target_by_unit_id` per target | **Exact** |
| `active_scan_missions_per_target` | Units in `active_units_by_mission_id` per target | **Exact** |
| `support_drones_per_target` | Post-mission `ORBITING_BASE` at target (incl. idle list without dict entry) | **Exact** for orbit state; excludes in-flight `TRAVEL`/`WORKING` |
| `targets_with_assigned_scan_drones` | Distinct targets with assigned count > 0 | **Exact** |
| `targets_with_active_scan_missions` | Distinct targets with active mission count > 0 | **Exact** |
| `targets_with_support_drones` | Distinct targets with support count > 0 | **Exact** |
| `already_in_progress_blocks` | Known scannable objects where `can_scan_object(..., target_has_active_scan=true)` returns `KEY_SCAN_ALREADY_IN_PROGRESS` | **Snapshot** (hypothetical idle drone = true) |
| `already_in_progress_block_targets` | Map `object_id -> true` for blocked targets | Same |
| `potential_support_blocks` | `true` when no active mission but assigned/support > 0 | **Exact** |
| `scan_target_telemetry_available` | Automation controller present | Meta |

### Approximations / limits

- `already_in_progress_blocks` assumes `has_idle_scan_drone=true` — counts **would-block** targets, not player click attempts.
- `get_active_scan_drone_support_count_for_target` (mining bonus) still caps at 1; telemetry `support_drones_per_target` does **not** cap.
- Support idle drones without `scan_drone_target_by_unit_id` entry are included in support count only (not assigned count).

---

## Changed Files

| File | Change |
|------|--------|
| `scripts/system/controller/automation_controller.gd` | Read-only scan target snapshot APIs |
| `scripts/debug/balance_telemetry_logger.gd` | `_snap_scan` extensions, `peek_scan_telemetry_section()` |
| `scripts/debug/smoke_tests/shared_scan_telemetry_step_2_smoke_test.gd` | Smoke A–D |
| `scripts/debug/smoke_tests/shared_scan_telemetry_step_2_smoke_runner.tscn` | Runner |

**Unchanged:** `can_scan_object`, `launch_scan_drone`, rewards, scan state, save, UI, `KEY_SCAN_ALREADY_IN_PROGRESS`.

---

## Tests

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/shared_scan_telemetry_step_2_smoke_runner.tscn
```

| Test | Coverage |
|------|----------|
| A | Baseline telemetry keys, zero assignments |
| B | Active scan: assigned=1, active mission=1, block key active |
| C | Support orbit + `potential_support_blocks` (time-bounded poll) |
| D | Second launch blocked, no SD/scan state duplication |

---

## Risks

- Long scan duration may cause Test C to note timeout on slow headless runs (partial PASS WITH NOTES).
- `already_in_progress_blocks` is diagnostic, not a cumulative player-action counter.
- Telemetry walks all KNOWN scannable bodies/POIs each snapshot — acceptable for debug interval.

---

## Status

- **Step 2 Telemetry:** done  
- **Multi-SD gameplay unlock:** **not** done  
- **`KEY_SCAN_ALREADY_IN_PROGRESS`:** unchanged and active  
