# SensorPulse UI Strings Cleanup v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Scope:** Player-facing SensorPulse UI-Texte zentralisieren — kein Gameplay-/Save-/Cost-Change.

---

## Audit Answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Player-facing texts? | Block reasons (no SD, active, cooldown, no hidden, no base), progress format, cost format, button label |
| 2 | Hardcoded in code? | **Was** in `base_sensor_pulse_controller.gd` pre-Phase-1; **now** via `DiscoverySignalUiTextDefinition`. Scene defaults in `object_info_panel.tscn` remain editor fallbacks only. |
| 3 | Debug stays in code? | `push_warning` in controller (save cancel, discovery refresh) — unchanged |
| 4 | Existing resource? | **Yes** — `DiscoverySignalUiTextDefinition` + `discovery_signal_ui_texts.tres` |
| 5 | Extend vs new? | **A) Extended existing** — SensorPulse keys live alongside Investigate/Signal keys |
| 6 | Who reads DiscoverySignalUiTextDefinition? | `GameSession` (boot), `base_sensor_pulse_controller`, `survey_probe_mission_controller`, `system_ui_controller`, `object_info_panel`, `signal_marker` |
| 7 | SystemUIController path? | `_apply_sensor_pulse_info_to_dict()` → progress via `format_sensor_pulse_progress()`, blocked via gate from controller |
| 8 | Fallbacks? | `FALLBACK_SENSOR_PULSE_*` constants in definition class when `.tres` missing |

---

## Old Code → New Text Source

| Text | Old location | New source |
|------|--------------|------------|
| Block: not enough SurveyData | Hardcoded in controller (pre-cleanup) | `sensor_pulse_block_not_enough_survey_data` |
| Block: pulse active | Hardcoded | `sensor_pulse_block_active` |
| Block: cooldown | Hardcoded | `sensor_pulse_block_cooldown` |
| Block: no hidden signals | Hardcoded | `sensor_pulse_block_no_hidden` |
| Block: no base | Hardcoded | `sensor_pulse_block_base_missing` |
| Progress format | Hardcoded / scene | `sensor_pulse_progress_format` → `format_sensor_pulse_progress()` |
| Cost format | Hardcoded | `sensor_pulse_cost_format` → `format_sensor_pulse_cost()` |
| Button label | Scene `object_info_panel.tscn` | `sensor_pulse_button_label` → `get_sensor_pulse_button_label()` at panel init |

**Reason keys (internal, unchanged):** `REASON_*` in `base_sensor_pulse_controller.gd` alias `DiscoverySignalUiTextDefinition.KEY_SENSOR_PULSE_*` — resolved to visible text in `_blocked()` via `get_template()`.

---

## Visible Texts (discovery_signal_ui_texts.tres)

| Key | Text |
|-----|------|
| `sensor_pulse_button_label` | Sensor Pulse |
| `sensor_pulse_progress_format` | Scanning for signals: %d%% |
| `sensor_pulse_block_active` | Sensor pulse already active |
| `sensor_pulse_block_cooldown` | Sensor pulse cooling down |
| `sensor_pulse_block_no_hidden` | No hidden signals detected |
| `sensor_pulse_block_not_enough_survey_data` | Not enough Survey Data |
| `sensor_pulse_block_base_missing` | No established base |
| `sensor_pulse_cost_format` | Cost: %s |

---

## Changed Files

| File | Change |
|------|--------|
| `resources/definitions/discovery_signal_ui_text_definition.gd` | SensorPulse keys + fallbacks + format helpers; added `get_sensor_pulse_button_label()` |
| `data/ui_text/discovery_signal_ui_texts.tres` | SensorPulse template entries (Phase 1) |
| `scripts/system/controller/base_sensor_pulse_controller.gd` | `REASON_*` → `get_template()` in `_blocked()` (Phase 1) |
| `scripts/system/controller/system_ui_controller.gd` | Progress text from `format_sensor_pulse_progress()` (Phase 1) |
| `scripts/ui/system/object_info_panel.gd` | Button label from resource at init |
| `scripts/debug/smoke_tests/sensor_pulse_ui_strings_cleanup_smoke_test.gd` | **new** |
| `scripts/debug/smoke_tests/sensor_pulse_ui_strings_cleanup_smoke_runner.tscn` | **new** |

**Not changed:** pulse duration/cost/reveal, save refund, `GameBalanceDefinition` pulse values, ObjectInfo layout.

---

## Full Project Cleanup Audit

- **Cleanup Audit Task 3** (Sensor pulse UI strings): **done**

---

## Tests

| Test | Description | Result |
|------|-------------|--------|
| A | Resource load; all SensorPulse keys non-empty | **PASS** |
| B | Zero SurveyData → centralized block text | **PASS** |
| C | Active pulse → centralized block + progress | **PASS** |
| D | No hidden candidates → centralized block | **PASS** |
| E | Progress/cost templates from resource | **PASS** |
| Galaxy transition continuity | Regression | **PASS** |
| ObjectInfo simple labels | Regression | **PASS WITH NOTES** |

---

## Risks

| Risk | Mitigation |
|------|------------|
| Scene `.tscn` text diverges from `.tres` | Panel overwrites button label at `_ready()` from resource |
| `blocked_reason` returns text not key | Existing pattern; smoke compares to `get_template()` |
| Cooldown blocks before no-SD in edge cases | Documented gate order; tests use explicit setup |

---

## Result

**PASS** — Centralization completed in Phase 1; this task adds button-label wiring, smoke coverage, and audit closure.
