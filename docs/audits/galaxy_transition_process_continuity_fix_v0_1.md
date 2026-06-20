# Galaxy Transition Process Continuity Fix v0.1

**Date:** 2026-06-20  
**Godot:** 4.6.1  
**Status:** Implemented — minimal snapshot/restore fix.

---

## Root Cause

`SceneFlow.goto_galaxy()` frees the entire `SystemScene`, destroying scene-owned controllers. Survey-probe investigate missions and sensor-pulse progress lived only in `SurveyProbeMissionController._active_missions` and `BaseSensorPulseController` fields. Probe/SurveyData spend is session-persistent at start, so resources were lost without completion.

Automation already had `_automation_runtime_pending` + restore, but `refresh_automation_snapshot_from_scene()` was not called on galaxy leave.

---

## Processes at Risk (pre-fix)

| Process | Pre-fix | Post-fix |
|---------|---------|----------|
| SurveyProbe Investigate | **Lost** | Restored via snapshot |
| ScanDrone / MiningShip | Partial (no snapshot on leave) | Snapshot on leave + existing restore |
| SensorPulse | **Lost** | Restored via snapshot |
| ColonizationOperation | Safe (GameSession) | Unchanged |
| Production / Upgrade timers | Instant (N/A) | N/A |

---

## Fix Approach

**`GameSession.capture_system_scene_processes_before_leave()`** called from `SystemScene._on_navigation_galaxy_requested()` before `SceneFlow.goto_galaxy()`:

1. `refresh_automation_snapshot_from_scene()` (scan/mining/support-orbit)
2. `refresh_camera_snapshot_from_scene()` (existing)
3. Survey-probe mission snapshot from controller
4. Sensor-pulse snapshot from controller

**`SystemScene._restore_pending_system_processes()`** after `ensure_starting_units()` on re-enter:

- Restores survey-probe missions (no re-consume; background elapsed applied)
- Restores sensor-pulse (no re-spend; completes if duration exceeded away)

**Time strategy:** **Background progress (Option B)** — `captured_at_msec` + away-time added to work/pulse elapsed on restore.

---

## Changed Files

| File | Change |
|------|--------|
| `scripts/autoload/game_session.gd` | Pending restore dict, capture/take APIs, clear on new game/load |
| `scripts/system/system_scene.gd` | Capture before galaxy; restore after setup |
| `scripts/system/controller/survey_probe_mission_controller.gd` | `capture_runtime_snapshot`, `restore_from_runtime_snapshot`, duration in mission dict |
| `scripts/system/controller/base_sensor_pulse_controller.gd` | `capture_runtime_snapshot`, `restore_from_runtime_snapshot` |
| `scripts/debug/smoke_tests/galaxy_transition_process_continuity_smoke_test.gd` | Smoke tests A/B/C/E/F |
| `scripts/debug/smoke_tests/galaxy_transition_process_continuity_smoke_runner.tscn` | Runner scene |
| `docs/audits/galaxy_transition_process_continuity_audit_v0_1.md` | Audit (pre-fix) |

**Not changed:** `SAVE_VERSION`, balance, costs, UI, multi-scan rules.

---

## Tests

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/galaxy_transition_process_continuity_smoke_runner.tscn
```

| Test | Coverage |
|------|----------|
| A | SurveyProbe investigate survives; no double probe spend |
| B | ScanDrone mission survives |
| C | MiningShip mission + cargo survives |
| D | WAITING_FOR_STORAGE / UNLOADING | Not automated (setup heavy) |
| E | SensorPulse spend not refunded incorrectly |
| F | ColonizationOperation pending survives |

Regression: `SAVE_VERSION = 1`, `KEY_SCAN_ALREADY_IN_PROGRESS` present.

---

## Risks

- Restore requires spawned nodes (base, target, idle probe unit). Failure logs warning; mission not silently refunded.
- Very long galaxy visits may complete missions immediately on restore (intended background progress).
- Test D (storage-wait) not covered by smoke; automation snapshot path should cover mining phases but needs manual QA.

---

## Known Limits

- UI panels do not persist (by design).
- Camera restore unchanged (separate concern).
- Save-on-disk still cancels/refunds investigate + sensor pulse (v0.1 save policy unchanged).

---

## Acceptance

| # | Criterion | Result |
|---|-----------|--------|
| 1–4 | Missions survive galaxy roundtrip | Fixed |
| 5–9 | No double spend/reward/completion | Restore paths idempotent |
| 10 | Colonization stable | Already session-owned |
| 11 | SensorPulse no false refund | Fixed |
| 12 | SAVE_VERSION = 1 | Unchanged |
| 13 | tooltip_text = 0 | Unchanged |
| 14 | No multi-SD unlock | Unchanged |

**Overall:** **PASS** (smoke run 2026-06-20)

Smoke output highlights:
- Test A: probe 2→1, stays 1 after galaxy; investigate still active
- Test B/C: scan + mining jobs survive (1→1)
- Test E: SurveyData 10→5, stays 5; pulse active after restore
- Test F: colonization op `colony_1` still pending
