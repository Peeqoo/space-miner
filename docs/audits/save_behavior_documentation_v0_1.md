# Save Behavior Documentation v0.1 — Audit

**Date:** 2026-06-07  
**Task:** Full Project Cleanup Audit **Task 8** — document v0.1 save behavior.  
**Deliverable:** `docs/save_behavior_v0_1.md` (updated/verified).

---

## Audit answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Save during SurveyProbe Investigate? | `SaveManager.build_save_data()` → `cancel_all_active_investigations_refund()` — mission torn down |
| 2 | Probe refunded or mission saved? | **Refunded** — 1 probe per cancelled mission; mission **not** in save JSON |
| 3 | Save during SensorPulse? | `cancel_pulse_before_save()` — pulse stopped |
| 4 | SurveyData refunded or pulse saved? | **Refunded** — full `_paid_pulse_cost`; pulse **not** in save JSON |
| 5 | Save during ScanDrone? | Automation runtime snapshot (`scan_missions`); restored on load |
| 6 | Save during MiningShip? | `mining_missions` in runtime snapshot; restored on load |
| 7 | Save during MiningShip with cargo? | `cargo_resources`, `current_cargo`, `status` sanitized into job dict — **persisted** |
| 8 | `WAITING_FOR_STORAGE`? | Mining `status` enum value saved in runtime; resumes after load |
| 9 | ColonyOperation? | `colonization_operations` in session; `remaining_ms` for pending |
| 10 | Camera state? | Saved per `system_id`; restored in `SystemScene` when system matches |
| 11 | GalaxyMap vs disk save? | **Different** — `capture_system_scene_processes_before_leave()` keeps Probe/Pulse alive; **no** cancel/refund |

---

## Decision

**Documentation only** — no save/runtime logic changed. Existing `docs/save_behavior_v0_1.md` expanded to match audit template (scope, scene transition, smoke matrix).

---

## Files

| File | Action |
|------|--------|
| `docs/save_behavior_v0_1.md` | Updated structure + scene-transition section |
| `docs/audits/save_behavior_documentation_v0_1.md` | This audit |
| `scripts/debug/smoke_tests/save_behavior_v0_1_smoke_test.gd` | New — disk save Investigate/Pulse policy |
| `scripts/debug/smoke_tests/save_behavior_v0_1_smoke_runner.tscn` | New runner |

**Unchanged:** `save_manager.gd`, controllers, `SAVE_VERSION = 1`.

---

## Tests

| Test | Result |
|------|--------|
| `save_behavior_v0_1_smoke_test` A (investigate cancel/refund) | **PASS** |
| `save_behavior_v0_1_smoke_test` B (pulse cancel/refund) | **PASS** |
| `shared_scan_job_step_5_save_restore` (scan) | Existing regression |
| `galaxy_transition_process_continuity` (pulse scene) | Existing regression |
| `galaxy_transition_repeated_survey_probe` (investigate scene) | Existing regression |

---

## Risks

| Risk | Mitigation |
|------|------------|
| Doc drift from code | Code references table; smoke A/B |
| Confusion Galaxy vs save | Dedicated section + matrix |
| Players expect Probe/Pulse to survive save | Documented as known v0.1 limit |

---

## Cleanup Audit

- **Task 8** (`docs/save_behavior_v0_1.md`): **done**

---

## Result

**PASS** — Documentation complete; optional smoke verifies disk-save cancel/refund policy.
