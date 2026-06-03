# Phase 3.4 Discovery Refresh SmokeTest v0.1

**Date:** 2026-05-20 (updated after follow-ups)  
**Engine:** Godot 4.6.1  
**Scope:** Per-object discovery refresh (`refresh_object` / `refresh_objects`), removal of `reveal_object`, colony establish visual refresh.  
**Method:** Static code audit + call-site grep. **Runtime manual playtest not executed** in this audit (Godot CLI not available).

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Phase 3.4 closable?** | **Yes, with editor manual confirmation** — implementation and static wiring complete; runtime checklist 1–9 still **NOT TESTED** in this audit. |
| **Biggest risks** | (1) Manual editor smoke not run here. (2) `refresh_object` failure → `push_warning` only (store/visual drift until system re-enter). (3) Colony refresh only when `SystemUIController` is in tree and system ids match. |

---

## Static Checks

| Check | Expected | Result | Evidence |
|-------|----------|--------|----------|
| `apply_for_system` call sites | Only full-sync (SystemScene setup/enter) | **PASS** | `system_scene.gd:41` only external caller |
| `apply_for_system` **not** in sensor pulse completion | Per-object only | **PASS** | `base_sensor_pulse_controller.gd` → `refresh_objects` |
| `apply_for_system` **not** in colony establish path | Signal + `refresh_object` | **PASS** | `_apply_established_base_record` emits signal; no `apply_for_system` |
| `reveal_object` in `scripts/` | **0** (removed) | **PASS** | No definition or callers in `scripts/` |
| `refresh_object` — Survey Probe | After KNOWN | **PASS** | `survey_probe_mission_controller.gd` |
| `refresh_object` — Colony establish | Signal → SystemUIController | **PASS** | `game_session.gd` signal + `system_ui_controller.gd` listener |
| `refresh_objects` — Sensor Pulse | After SIGNAL writes | **PASS** | `base_sensor_pulse_controller.gd` |
| Order Survey Probe | State → refresh → reward → selection | **PASS** | `_complete_mission` |
| Order Sensor Pulse | State loop → `refresh_objects` → signals | **PASS** | `_complete_pulse` |
| Per-object path avoids `_clear_all_markers` | No global clear | **PASS** | `refresh_object` / `refresh_objects` only |
| `tooltip_text` | 0 | **PASS** | Repo grep `*.gd` / `*.tscn` / `*.tres` |
| Save abort survey probe | No KNOWN / no refresh | **PASS** | `_abort_mission_with_refund` |
| Save abort sensor pulse | No `_complete_pulse` / no refresh | **PASS** | `cancel_pulse_before_save` |

---

## Call-site map (current)

| Flow | Discovery state | Visual apply |
|------|-----------------|--------------|
| SystemScene `_ready` | `ensure_default_discovery_for_system` | `apply_for_system` |
| Survey Probe complete | `set_object_discovery_state(KNOWN)` | `refresh_object(oid)` |
| Sensor Pulse complete | `set_object_discovery_state(SIGNAL)` × N | `refresh_objects(revealed_ids)` |
| Colony / base establish | `_apply_established_base_record` → KNOWN | `established_body_discovery_visual_refresh_requested` → `SystemUIController._try_refresh_discovery_for_established_body` → `refresh_object(body_id)` |
| Galaxy colonization complete (other system) | Store updated | Visual on next system enter (`apply_for_system`) |

---

## Manual Tests

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 1 | New Game | Signals/hidden/known as before | **NOT TESTED** | Editor |
| 2 | SignalMarker select | SIGNAL panel layout | **NOT TESTED** | |
| 3 | SurveyProbe Investigate | KNOWN, marker gone, body visible, selection | **NOT TESTED** | Uses `refresh_object` |
| 4 | Multiple signals | Other markers survive | **NOT TESTED** | |
| 5 | Sensor Pulse | HIDDEN→SIGNAL, no full flicker | **NOT TESTED** | Uses `refresh_objects` |
| 6 | Multiple pulses | No dupes | **NOT TESTED** | |
| 7 | Save during SurveyProbe | Refund, stays SIGNAL | **NOT TESTED** | Static PASS |
| 8 | Save during Sensor Pulse | Refund, no reveal | **NOT TESTED** | Static PASS |
| 9 | Reload / re-enter system | `apply_for_system` sync | **NOT TESTED** | |
| 10 | Colony establish in current system | Body visible without re-enter | **NOT TESTED** | Signal + `refresh_object` |
| 11 | POI | Same as body if data exists | **N/A** | No POI `.tres` in data grep |

---

## Code-path reference

### Survey Probe (`survey_probe_mission_controller.gd`)

1. `GameSession.set_object_discovery_state(..., DISCOVERY_KNOWN)`
2. `discovery_controller.refresh_object(oid)` — warn if false
3. `_grant_survey_data_reward`
4. `_refresh_selection_after_reveal(oid)`

### Sensor Pulse (`base_sensor_pulse_controller.gd`)

1. Loop: `set_object_discovery_state(..., SIGNAL)` + `revealed_ids`
2. `discovery_controller.refresh_objects(revealed_ids)` — warn if partial
3. Pulse signals / cooldown

### Colony establish (`game_session.gd` + `system_ui_controller.gd`)

1. `_apply_established_base_record` → `set_object_discovery_state(KNOWN)`
2. `established_body_discovery_visual_refresh_requested.emit(sid, bod)`
3. `SystemUIController` → `refresh_object(bod)` if active system matches

### Full sync (`system_scene.gd`)

- After spawn: `ensure_default_discovery_for_system` + `apply_for_system`

---

## Open Issues

| Issue | Status |
|-------|--------|
| Remove / deprecate `reveal_object` | **DONE** — removed from `SystemDiscoveryController` |
| Colony establish visual refresh | **DONE** — signal + `SystemUIController` |
| Runtime manual smoke in editor | **OPEN** — recommended before marking audit PASS without notes |
| `refresh_object` false → warn only | **OPEN (accepted)** | By design |
| POI gameplay in data | **LOW** — no POI instances in current data grep |

No blocking static defects found.

---

## Recommended Next Step

1. **Editor pass:** Run manual tests 1–10 once; update this doc’s manual table to PASS where verified.
2. **Close Phase 3.4** after manual confirmation.
3. No further discovery-refresh code required unless a manual test fails.

---

## Acceptance (audit doc)

1. Documentation reflects implemented Phase 3.4 + follow-ups.
2. No claim that `reveal_object()` is active.
3. Colony establish path documented.
4. Manual smoke status explicit (NOT TESTED vs static PASS).
