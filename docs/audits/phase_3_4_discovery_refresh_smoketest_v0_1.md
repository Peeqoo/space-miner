# Phase 3.4 Discovery Refresh SmokeTest v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Scope:** Per-object discovery refresh (`refresh_object` / `refresh_objects`) after Steps 2–4.  
**Method:** Static code audit + call-site grep. **Runtime manual playtest not executed** (Godot CLI not available in audit environment).

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Phase 3.4 closable?** | **Yes, with editor manual confirmation** — wiring and invariants match design; runtime checklist below is **NOT TESTED** here. |
| **Biggest risks** | (1) Manual smoke not run in this audit. (2) `refresh_object` failure leaves store/visual drift (warn-only). (3) `reveal_object` still exists but is unused (dead path). (4) Colony `KNOWN` in store without per-object refresh until scene re-enter (pre-existing). |

---

## Static Checks

| Check | Expected | Result | Evidence |
|-------|----------|--------|----------|
| `apply_for_system` call sites | Only full-sync paths (e.g. `SystemScene` setup) | **PASS** | `system_scene.gd:41` only external caller |
| `apply_for_system` **not** in sensor pulse completion | No full refresh after pulse | **PASS** | `base_sensor_pulse_controller.gd` uses `refresh_objects` only |
| `reveal_object` call sites | Not used by Survey Probe completion | **PASS** | No callers in `scripts/` except definition in `system_discovery_controller.gd` |
| `refresh_object` call sites | Survey Probe `_complete_mission` | **PASS** | `survey_probe_mission_controller.gd:285` after `set_object_discovery_state(KNOWN)` |
| `refresh_objects` call sites | Sensor pulse `_complete_pulse` | **PASS** | `base_sensor_pulse_controller.gd:174` after SIGNAL state writes |
| Order Survey Probe | State → refresh → reward → selection | **PASS** | Lines 283–293 |
| Order Sensor Pulse | State loop → `refresh_objects` → signals | **PASS** | Lines 166–185 |
| Per-object path avoids `_clear_all_markers` | No global marker tear-down | **PASS** | `refresh_object` → `_apply_discovery_to_world_object` only; `_spawn_or_refresh_marker` calls `_remove_marker(oid)` before spawn (single marker per id) |
| `tooltip_text` | 0 in `*.gd` / `*.tscn` / `*.tres` | **PASS** | Repo grep |
| `system_ui_controller.gd` `has_method` / `.call(` | 0 | **PASS** | Repo grep |
| Selection on marker remove | `clear_selection` if selected | **PASS** | `_remove_marker` in `system_discovery_controller.gd` |
| Survey selection after reveal | `select_world_node(revealed)` if marker was selected | **PASS** | `_refresh_selection_after_reveal` unchanged |
| Save abort survey probe | No KNOWN / no `refresh_object` | **PASS** | `cancel_all_active_investigations_refund` → `_abort_mission_with_refund` (no discovery state change) |
| Save abort sensor pulse | No completion / refund cost | **PASS** | `cancel_pulse_before_save` resets pulse flags, refunds cost; does not call `_complete_pulse` |

---

## Manual Tests

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 1 | New Game | Start signals / hidden / known as before; no errors | **NOT TESTED** | Requires editor run |
| 2 | SignalMarker select | Signal ObjectInfo layout; Investigate visible | **NOT TESTED** | Static: `SignalMarker.get_info()` + UI controller unchanged |
| 3 | SurveyProbe Investigate | KNOWN, marker gone, body visible/clickable, selection refresh, reward, no duplicate marker | **NOT TESTED** | Static path matches design |
| 4 | Multiple signals | Other markers survive one investigate | **NOT TESTED** | Per-object refresh does not call `_clear_all_markers` |
| 5 | Sensor Pulse | HIDDEN→SIGNAL, new marker, others preserved, selection on other signal, no flicker | **NOT TESTED** | Full `apply_for_system` removed from completion path |
| 6 | Multiple pulses | Repeat reveals; no dupes/missing markers | **NOT TESTED** | |
| 7 | Save during SurveyProbe | Refund; stays SIGNAL; no KNOWN | **NOT TESTED** | Static: abort path does not set KNOWN |
| 8 | Save during Sensor Pulse | Cancel/refund; no reveal from aborted pulse; reload sync | **NOT TESTED** | Static: `cancel_pulse_before_save` does not set SIGNAL; enter scene runs `apply_for_system` |
| 9 | Leave/re-enter system / reload | `apply_for_system` syncs all states | **NOT TESTED** | Static: `system_scene.gd` `_ready` still calls full apply |
| 10 | POI | Same as body if POIs exist | **N/A** | No `pois` entries found in `data/` `.tres` grep; `refresh_object` supports `PointOfInterestDefinition` in code |
| 11 | Tooltips / calls | tooltip 0; UI controller clean; wiring | **PASS** (static) | See Static Checks |

---

## Code-Path Reference (audit)

### Survey Probe success (`survey_probe_mission_controller.gd`)

1. `GameSession.set_object_discovery_state(_system_id, oid, DISCOVERY_KNOWN)`
2. `discovery_controller.refresh_object(oid)` — warn if `false`, mission continues
3. `_grant_survey_data_reward`
4. `_refresh_selection_after_reveal(oid)` — transfers selection from `SignalMarker` to world node when applicable

### Sensor Pulse completion (`base_sensor_pulse_controller.gd`)

1. For each revealed candidate: `set_object_discovery_state(..., DISCOVERY_SIGNAL)` + append `revealed_ids`
2. `discovery_controller.refresh_objects(revealed_ids)` — warn if `refreshed_count < revealed_ids.size()`
3. `sensor_pulse_changed` / progress `1.0`

### Full sync (unchanged)

- `system_scene.gd` after spawn: `ensure_default_discovery_for_system` + `apply_for_system(system_definition)`

---

## Open Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| Runtime manual smoke not executed in this audit | **Medium** | Close Phase 3.4 after one editor pass through tests 1–9 |
| `reveal_object` dead code | **Low** | Safe to deprecate/remove in a later cleanup PR |
| `refresh_object` false → warn only | **Low** | By design; rare if spawn/definition match store |
| Colony establish sets KNOWN without `refresh_object` | **Low** | Pre-existing; full apply on scene enter heals visuals |
| POI gameplay untested in repo data | **Low** | No POI instances in current `data/` grep |

No blocking defects found in static review.

---

## Recommended Next Step

**If editor manual tests 1–9 pass (expected):**

- **Close Phase 3.4** (Discovery per-object refresh).
- Optional follow-up (separate scope): remove or deprecate `reveal_object`; call `refresh_object` when establishing colony base.

**If a manual test fails:**

Use a single fix prompt targeting the failed row only, e.g.:

> *Survey Probe completion: after `refresh_object` returns false, call `apply_for_system` as fallback for that `object_id` only* — **only if** marker/body desync is reproduced in editor.

Do not batch-fix without a reproduced failure.

---

## Acceptance (this audit)

1. Only `docs/audits/phase_3_4_discovery_refresh_smoketest_v0_1.md` added — **PASS**
2. No code/scene/data changes — **PASS**
3. All tests marked PASS / NOT TESTED / N/A — **PASS**
4. Phase 3.4 closable statement — **Yes with editor confirmation** (see Summary)
