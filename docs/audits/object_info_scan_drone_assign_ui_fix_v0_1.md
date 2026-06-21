# ObjectInfo ScanDrone Assign UI Fix v0.1

**Date:** 2026-06-07  
**Scope:** UI/UX only — no SharedScanJob runtime, rewards, or save changes.

---

## Root Cause

ScanDrone ObjectInfo did not mirror the MiningShip assign pattern:

| Issue | MiningShip | ScanDrone (before) |
|-------|------------|-------------------|
| Count visibility | `show_mining_ship_status = show_mine \| assigned > 0` | `show_scan_drone_status = assigned > 0 \| active_job` only — hidden at 0 when scannable |
| Button visibility | `mine_visible = show_mine \| can_mine` | `scan_visible = show_scan` only — hidden when gate blocked but layer exists |
| Button label (new scan) | Default `"Mine"` from scene | Empty `scan_button_text` → scene fallback `"Scan"` |
| Button label (assign) | `mining_button_text` always set when assigned | Set only on active-job branch (OK) but visibility could hide button |
| Live cache | `assigned_mining_ship_count` cached | `assigned_scan_drone_count` **not** cached — stale reads on partial refresh |

No typo `"Assigned ScanDrone"` in codebase.

---

## Fix (minimal)

### `system_ui_controller.gd`

- Unified `_apply_scan_drone_info_to_dict()` flow (single `can_scan_object` call).
- Active SharedScanJob → `scan_button_text = "Assign ScanDrone"`, button always shown.
- No active job → `scan_button_text = "{Layer} Scan"` (e.g. Basic Scan) from `target_scan_state`.
- `show_scan_drone_status = show_scan_with_drone or assigned_count > 0` (mining parity).

### `object_info_panel.gd`

- Cache `assigned_scan_drone_count`, `show_scan_drone_status`, `has_active_shared_scan_job`.
- `scan_visible = show_scan or can_scan` (mining parity).
- Block reason uses `scan_visible` when disabled.

---

## UI Before → After

| State | Before | After |
|-------|--------|-------|
| Scannable, 0 drones | Button `"Scan"`, count often hidden | Button `"Basic Scan"`, count visible |
| Active job, idle SD | Assign text (if visible) | `"Assign ScanDrone"`, count N, enabled |
| Active job, no idle SD | Assign sometimes hidden | `"Assign ScanDrone"`, count N, **disabled** |
| Support-only post-scan | Risk of Assign label | Layer scan button (e.g. Deep Scan), no Assign |

---

## Tests

- `object_info_scan_drone_assign_ui_smoke_test.gd` — Tests A–F
- Updated `shared_scan_job_step_6_ui_assign_scan_drone_smoke_test.gd` — Basic Scan baseline

---

## Risks

1. **Layer button copy** — Derived from `target_scan_state` title case + `" Scan"`; not from separate `.tres` button strings.
2. **Deep/Special rescan** — Same label pattern as progression scans.

---

## Files Changed

- `scripts/system/controller/system_ui_controller.gd`
- `scripts/ui/system/object_info_panel.gd`
- `scripts/debug/smoke_tests/object_info_scan_drone_assign_ui_smoke_test.gd` (+ runner)
- `scripts/debug/smoke_tests/shared_scan_job_step_6_ui_assign_scan_drone_smoke_test.gd`
