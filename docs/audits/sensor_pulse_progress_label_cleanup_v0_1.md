# SensorPulse Progress Label Cleanup v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Scope:** Eigenes `SensorPulseProgressLabel` — semantische Trennung von Investigate-Progress.

---

## Audit Answers

| # | Question | Answer |
|---|----------|--------|
| 1 | InvestigateProgressLabel in scene? | `Margin/Root/InvestigateProgressLabel` — `visible=false`, default `"Investigating: 0%"` |
| 2 | Code references? | `object_info_panel.gd` `@onready investigate_progress_label` |
| 3 | Investigate methods? | `_show_investigate_progress_ui()`, `_hide_investigate_progress_ui()`, `apply_investigate_progress()`, `_apply_signal_discovery_controls()` |
| 4 | SensorPulse methods (old)? | **Previously** reused Investigate label; **now** `_show_sensor_pulse_progress_ui()`, `_hide_sensor_pulse_progress_ui()`, `_apply_sensor_pulse_controls()` |
| 5 | Visibility conflicts? | Resolved: signal path hides pulse label; home-base pulse hides investigate via separate code paths |
| 6 | Info dict field? | `sensor_pulse_progress_text` (+ `sensor_pulse_in_progress`) in `system_ui_controller._apply_sensor_pulse_info_to_dict()` |
| 7 | SystemUIController changes needed? | **No** — separate `investigate_progress_text` vs `sensor_pulse_progress_text` already |

---

## Old → New Label Usage

| Context | Old (pre-cleanup) | New |
|---------|-------------------|-----|
| SurveyProbe Investigate | `InvestigateProgressLabel` | `InvestigateProgressLabel` (unchanged) |
| Base Sensor Pulse | `InvestigateProgressLabel` (reuse) | **`SensorPulseProgressLabel`** |
| `show_empty()` / reset | Single label cleared | Both labels hidden independently |

---

## Scene Structure

```
Margin/Root/
  InvestigateProgressFormatTemplate  (hidden editor template)
  InvestigateProgressLabel           (investigate only)
  SensorPulseProgressLabel           (sensor pulse only)  ← added Phase 1
  GridContainer/
    SensorPulseButton
```

Both labels share `label_settings` (`ExtResource 6_oi0nm`) — same font/style, distinct nodes.

---

## Changed Files

| File | Role |
|------|------|
| `scenes/ui/system/object_info_panel.tscn` | `SensorPulseProgressLabel` node (Phase 1) |
| `scripts/ui/system/object_info_panel.gd` | Separate show/hide/apply paths; hide investigate label when leaving signal view |
| `scripts/system/controller/system_ui_controller.gd` | `sensor_pulse_progress_text` in info dict (unchanged) |
| `scripts/debug/smoke_tests/sensor_pulse_progress_label_cleanup_smoke_test.gd` | **new** verification |
| `scripts/debug/smoke_tests/sensor_pulse_progress_label_cleanup_smoke_runner.tscn` | **new** runner |

**Not changed:** `base_sensor_pulse_controller.gd`, `survey_probe_mission_controller.gd`, gameplay/save/costs.

---

## Full Project Cleanup Audit

- **Cleanup Audit Task 5** (Dedicated sensor pulse progress label): **done**

---

## Tests

| Test | Description | Result |
|------|-------------|--------|
| A | Both label nodes exist in scene | **PASS** |
| B | Investigate → `InvestigateProgressLabel` visible; pulse label hidden | **PASS** |
| C | Sensor pulse → `SensorPulseProgressLabel` visible; investigate not misused | **PASS** |
| D | `show_empty()` hides both | **PASS** |
| E | Pulse cost / no early reveal | **PASS WITH NOTES** (second pulse skipped — prior pulse active) |

Regression: sensor_pulse UI strings **PASS**, object_info simple labels **PASS WITH NOTES**, galaxy repeated SurveyProbe **PASS**.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Both labels visible simultaneously | Mutually exclusive UI contexts (signal vs home base); smoke B/C |
| Stale investigate text on hidden label | `visible=false`; optional future text clear on hide |
| Progress tick uses wrong label | `apply_investigate_progress()` only for investigate; pulse via `update_object_info()` |

---

## Result

**PASS WITH NOTES** — Implementation completed in Phase 1; minor hide-on-non-signal fix + smoke verification.
