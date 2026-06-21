# ObjectInfo Simple Action Button Labels v0.1

## Root Cause

`SystemUIController` set `mining_button_text` and `scan_button_text` in the info dict based on internal action mode:

- Mining: `"Assign MiningShip"` when `assigned_mining_ship_count > 0`, otherwise empty (panel fell back to scene default `"Mine"`).
- Scan: `"Assign ScanDrone"` when an active `SharedScanJob` existed; `"Scan"` (or previously layer labels like `"Basic Scan"`) when starting a new scan.

`ObjectInfoPanel._set_action_buttons()` faithfully rendered those dict values, including when buttons were disabled. Action routing (`_on_object_mining_requested` / `_on_object_scan_requested`) was already separate from label text.

## Old Labels → New Labels

| Context | Old visible label | New visible label |
|---------|-------------------|-------------------|
| Mining, no ship on target | `Mine` (scene default) | `Mine` |
| Mining, ship(s) assigned | `Assign MiningShip` | `Mine` |
| Mining, disabled | `Assign MiningShip` or `Mine` | `Mine` |
| Scan, no active job | `Scan` / `Basic Scan` / layer text | `Scan` |
| Scan, active SharedScanJob | `Assign ScanDrone` | `Scan` |
| Scan, disabled | `Assign ScanDrone` | `Scan` |

Removed constants: `MINING_BUTTON_TEXT_ASSIGN`, `SCAN_BUTTON_TEXT_ASSIGN`.

Retained constants: `MINING_BUTTON_TEXT = "Mine"`, `SCAN_BUTTON_TEXT = "Scan"`.

## Audit Answers

1. **Where is `mining_button_text` set?** `_apply_mining_ship_info_to_dict()` and `_build_selected_object_info()` else branch in `system_ui_controller.gd`.
2. **Where is `scan_button_text` set?** `_apply_scan_drone_info_to_dict()` in `system_ui_controller.gd`.
3. **Constants?** `MINING_BUTTON_TEXT`, `SCAN_BUTTON_TEXT`. Assign/layer helpers removed from button-text path.
4. **Does ObjectInfoPanel override?** No — it uses `info["mining_button_text"]` / `info["scan_button_text"]` via `_set_action_buttons()`, with scene defaults only when dict value is empty.
5. **Disabled state?** Yes — same label path; disabled only affects `button.disabled`.
6. **Action routing separate?** Yes — unchanged in `_on_object_mining_requested` / `_on_object_scan_requested`.

## Changed Files

- `scripts/system/controller/system_ui_controller.gd` — always `"Mine"` / `"Scan"` when button shown
- `scripts/debug/smoke_tests/object_info_multi_ms_ui_smoke_test.gd` — expect `"Mine"` always
- `scripts/debug/smoke_tests/object_info_scan_drone_assign_ui_smoke_test.gd` — expect `"Scan"` always
- `scripts/debug/smoke_tests/shared_scan_job_step_6_ui_assign_scan_drone_smoke_test.gd` — expect `"Scan"` always
- `scripts/debug/smoke_tests/object_info_simple_action_button_labels_smoke_test.gd` — new A–G coverage
- `scripts/debug/smoke_tests/object_info_simple_action_button_labels_smoke_runner.tscn` — new runner

**Not changed:** `object_info_panel.gd` (already correct), runtime assign/scan logic, SharedScanJob, rewards, `SAVE_VERSION`.

## Tests

| Test | Result |
|------|--------|
| Simple labels A–G | **PASS WITH NOTES** |
| Multi-MS UI regression | **PASS** |
| ScanDrone assign UI | **PASS WITH NOTES** |
| Step 6 UI assign | **PASS WITH NOTES** |
| Step 7 effect stacking | **PASS** |
| Speed-scaling rollback | **PASS** |

Regression: `SAVE_VERSION = 1`, `tooltip_text = 0`, no scan-speed UI.

| Test | Command |
|------|---------|
| Simple labels A–G | `object_info_simple_action_button_labels_smoke_runner.tscn` |
| Multi-MS UI regression | `object_info_multi_ms_ui_smoke_runner.tscn` |
| ScanDrone assign UI | `object_info_scan_drone_assign_ui_smoke_runner.tscn` |
| Step 6 UI assign | `shared_scan_job_step_6_ui_assign_scan_drone_smoke_runner.tscn` |
| Step 7 effect stacking | `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn` |
| Speed-scaling rollback | `shared_scan_job_step_7_speed_scaling_rollback_smoke_runner.tscn` |
