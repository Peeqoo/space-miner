# ObjectInfo Recall Button Language Pass v0.1 — Audit

**Date:** 2026-06-07  
**Task:** Full Project Cleanup Audit **Task 10** — unify recall button language to English.

---

## Audit answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Which recall buttons exist? | `RecallDroneButton`, `RecallMiningShipButton` in `object_info_panel.tscn` |
| 2 | Scene default texts? | `"Recall Drone"`, `"Recall Ship"` (was `"Recall Mining Ship"`) |
| 3 | Code overrides? | **No** — `object_info_panel.gd` only toggles visibility/disabled via `_set_recall_buttons()` |
| 4 | ScanDrone / MiningShip / SurveyProbe? | ScanDrone + MiningShip only; **no SurveyProbe recall button** |
| 5 | Player-facing? | **Yes** — button labels when `can_recall_*` is true |
| 6 | Central UI text resource? | **No** — scene defaults only (same pattern as Scan/Mine) |
| 7 | Scene-only fix sufficient? | **Yes** — no runtime text assignment in GDScript |

---

## Old → new (visible UI)

| Button | Pre-Phase-1 (audit) | Current |
|--------|---------------------|---------|
| `RecallDroneButton` | `"Drone zurück"` | `"Recall Drone"` |
| `RecallMiningShipButton` | `"Mining Ship zurück"` (or similar DE) | `"Recall Ship"` |

---

## Files changed

| File | Change |
|------|--------|
| `scenes/ui/system/object_info_panel.tscn` | `"Recall Mining Ship"` → `"Recall Ship"` |
| `docs/audits/object_info_recall_button_language_pass_v0_1.md` | This audit |
| `scripts/debug/smoke_tests/object_info_recall_button_language_pass_smoke_test.gd` | New smoke |
| `scripts/debug/smoke_tests/object_info_recall_button_language_pass_smoke_runner.tscn` | New runner |

**Unchanged:** `object_info_panel.gd`, `system_ui_controller.gd`, recall callbacks, automation runtime.

---

## Tests

| Test | Result |
|------|--------|
| `object_info_recall_button_language_pass_smoke_test` A–C | **PASS** |
| `object_info_simple_action_button_labels_smoke_test` | **PASS WITH NOTES** |
| `shared_scan_job_step_6_ui_assign_scan_drone_smoke_test` | **PASS WITH NOTES** |
| `object_info_multi_ms_ui_smoke_test` | **PASS** |

---

## Cleanup Audit

- **Task 10** (Recall button language): **done**

---

## Result

**PASS** — No German recall labels; English unified; recall behavior unchanged.
