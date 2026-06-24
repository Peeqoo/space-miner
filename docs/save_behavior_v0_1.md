# Space Miner Save Behavior v0.1

Reference for how **Space Mining v0.1** handles **active operations** on **disk save/load** vs **in-session scene transitions** (e.g. Galaxy Map).

**Entry points:** `SaveManager.build_save_data()` → pre-save cancel/refund hooks → `GameSession.to_save_data()` / `apply_save_data()`.

**Save file:** `user://saves/save_NNN.json` — `save_version = 1`.

---

## Scope

| Topic | v0.1 behavior |
|-------|----------------|
| Save version | `1` (`SaveManager.SAVE_VERSION`) — no bump in this doc task |
| Persisted session data | Bases, resources, units, upgrades, discovery/scan state, object `remaining_resources`, automation store + runtime, colonization ops, camera (per system) |
| Cancel + refund on **disk save** | SurveyProbe Investigate, Base Sensor Pulse |
| Persist through **disk save** | ScanDrone / MiningShip automation (incl. cargo, `WAITING_FOR_STORAGE`) |
| **Scene transition** (Galaxy ↔ System) | Runtime snapshots in memory — **not** a disk save; Investigate/Pulse **continue** |
| Out of scope | Save v2 mission persistence for Probe/Pulse; no implementation changes in v0.1 |

---

## Persisted (disk save)

Written via `GameSession.to_save_data()` after pre-save hooks:

| Domain | Source | Notes |
|--------|--------|-------|
| Base resources & storage | `BaseStore` | Iron, Silicon, SurveyData, etc. |
| Unit counts | `BaseStore` | Scan drones, mining ships, survey probes |
| Upgrades | `BaseStore` | Per-base upgrade levels |
| Discovery state | `ObjectScanStore` | HIDDEN / SIGNAL / KNOWN per object |
| Scan state | `ObjectScanStore` | unknown / basic / deep / special |
| Remaining mineable resources | `ObjectScanStore` | Per-object deposit amounts |
| Automation **store** | `AutomationStore` | Mission records, IDs |
| Automation **runtime** | `AutomationController.to_save_data()` | `scan_missions[]`, `mining_missions[]` — position, timers, **cargo**, mining `status` (incl. `WAITING_FOR_STORAGE`) |
| Colonization operations | `GameSession.colonization_operations` | Pending ops use `remaining_ms`; recomputed `arrival_at_tick` on load |
| Camera (system view) | `SystemCameraController` | Position, zoom, `system_id` |
| Galaxy progression | `GameSession` | Discovered/unlocked systems |
| Established bases | `GameSession` | Base records per system |

**Not in save JSON:** active SurveyProbe investigate mission records, active Sensor Pulse elapsed/progress (cancelled before write).

---

## Cancel + refund on disk save

Executed in `SaveManager.build_save_data()` **before** automation/camera snapshot and `to_save_data()`.

### SurveyProbe Investigate

**Path:** `GameSession.cancel_active_survey_probe_missions_before_save()` → `SurveyProbeMissionController.cancel_all_active_investigations_refund()`.

| | Behavior |
|---|----------|
| Cancelled | All active investigate missions |
| Refunded | **1 Survey Probe** per mission (`GameSession.add_survey_probe(1, base_id)`) |
| Not applied | KNOWN reveal, SurveyData investigate reward, lore refresh |
| Discovery after save | Target stays **SIGNAL** (same as before aborted run) |
| Why v0.1 | No mission serializer; avoids partial SIGNAL→KNOWN edge cases |
| Limitation | Player loses in-flight progress; must restart investigate after load |

### Base Sensor Pulse

**Path:** `GameSession.cancel_active_base_sensor_pulse_before_save()` → `BaseSensorPulseController.cancel_pulse_before_save()`.

| | Behavior |
|---|----------|
| Cancelled | Active pulse (`_pulse_active = false`) |
| Refunded | Full **`_paid_pulse_cost`** dictionary to paying base (typically 5 SurveyData) |
| Not applied | `_complete_pulse()` — no HIDDEN→SIGNAL reveals from cancelled run |
| Why v0.1 | Pulse is short, base-local; refund avoids charging without reveal |
| Limitation | Pulse progress lost; player pays again on next start (unless refunded at save) |

---

## Automation: Scan / Mining (disk save)

**Save path (after probe/pulse cancel):**

1. `GameSession.refresh_automation_snapshot_from_scene()` — live `AutomationController.to_save_data()`.
2. `automation: { store, runtime }` in session JSON.

**Load path:**

1. `GameSession.apply_save_data()` → `_automation_runtime_pending`.
2. `AutomationController.apply_automation_save_if_pending()` when system scene ready.
3. Skipped if saved `system_id` or `primary_base_id` ≠ current session.

| Mission type | On save | On load |
|--------------|---------|---------|
| ScanDrone / SharedScanJob | Unit state, target, timers, mission id, `scan_reveal_done` | Restored; rewards already granted stay in stores |
| MiningShip (mining, return, unload) | Full runtime dict incl. `cargo_resources`, `current_cargo`, `status` | Restored; cargo not zeroed by save |
| MiningShip `WAITING_FOR_STORAGE` | `status` + cargo persisted in runtime snapshot | Resumes waiting/unload when storage frees |

No duplicate scan rewards on restore: completion guarded by mission state / `scan_reveal_done`.

---

## Colonization (disk save)

- Pending ops stored in `colonization_operations` with **`remaining_ms`**.
- On load: `arrival_at_tick` recomputed from current tick + `remaining_ms`.
- `GameSession._process()` may auto-complete when `allow_auto_complete` and duration elapsed (`default_colonization.tres`).
- No colony-ship travel visuals in v0.1.

---

## Camera (disk save)

- **Save:** `GameSession.refresh_camera_snapshot_from_scene()` + `to_save_data()` camera section.
- **Load:** `SystemScene._try_restore_saved_camera_state()` when `system_id` matches.

---

## Scene transition behavior (≠ disk save)

**Galaxy Map navigation** calls `GameSession.capture_system_scene_processes_before_leave()` (`SystemScene._on_navigation_galaxy_requested`) — **no JSON write**.

Captured in `_pending_system_process_restore`:

| Process | Snapshot | On return to same system |
|---------|----------|---------------------------|
| Automation | `refresh_automation_snapshot_from_scene()` | Restored via pending runtime (same as save path) |
| Camera | `refresh_camera_snapshot_from_scene()` | Restored |
| SurveyProbe Investigate | `SurveyProbeMissionController.capture_runtime_snapshot()` | `restore_from_runtime_snapshot()` — **mission continues** |
| Sensor Pulse | `BaseSensorPulseController.capture_runtime_snapshot()` | `restore_from_runtime_snapshot()` — **pulse continues**, cost **not** re-charged (`cost_already_spent`) |

**Important differences from disk save:**

- Investigate/Pulse are **not** cancelled on Galaxy roundtrip.
- Survey Probe is **not** refunded on scene leave (probe remains consumed).
- SurveyData spent on pulse is **not** refunded on scene leave.
- Elapsed away time can be applied from `captured_at_msec` (pulse) or probe travel/investigate state.

**Regression:** `galaxy_transition_process_continuity_smoke_test`, `galaxy_transition_repeated_survey_probe_smoke_test`.

---

## Known limits (v0.1)

- Investigate and Pulse **do not** persist across **disk** save/load — cancel + refund policy.
- Save v2 could persist active Probe/Pulse with timestamps; **not implemented now**.
- Automation restore skipped on system/base mismatch — missions dropped with warning.
- Colonization timing is tick-based; load may immediately complete long-pending ops.
- Cooldown after cancelled pulse save: controller state reset on scene reload may differ from mid-session cooldown.

---

## Deliberate v0.1 decisions

- **Do not** persist active Survey Probe investigations or Sensor Pulse on disk save.
- **Do** refund consumables/costs on disk save cancel.
- **Do** persist ScanDrone/MiningShip automation (core loop).
- **Do** persist colonization as session records.
- **Do** preserve Probe/Pulse across **Galaxy ↔ System** via runtime snapshots only.

---

## Smoke-test matrix

| Scenario | Expected v0.1 | Automated test |
|----------|-----------------|----------------|
| Save during Investigate | Probe refunded; SIGNAL unchanged; no investigate reward | `save_behavior_v0_1_smoke_test.gd` Test A |
| Save during Sensor Pulse | SurveyData refunded; no reveal; pulse inactive | `save_behavior_v0_1_smoke_test.gd` Test B |
| Save during Scan (SharedScanJob) | Mission + job restored; no duplicate SD on load | `shared_scan_job_step_5_save_restore_smoke_test.gd` |
| Save during Mining / cargo | Runtime restored; cargo in snapshot | `shared_scan_job_step_5` (mining paths); manual |
| Save during `WAITING_FOR_STORAGE` | Status + `cargo_resources` in save dict | Manual / automation restore |
| Save during Colonization | Pending op in save; continues after load | Manual |
| Galaxy transition during Investigate | Mission continues; probe not refunded | `galaxy_transition_repeated_survey_probe_smoke_test.gd` |
| Galaxy transition during Pulse | Pulse continues; SD not refunded | `galaxy_transition_process_continuity_smoke_test.gd` Test E |
| Camera disk save/load | Position/zoom restored same system | Manual (see checklist below) |

### Manual checklist (after save/load changes)

1. Save during SurveyProbe Investigate — signal still SIGNAL, +1 probe vs mid-flight spend, no SurveyData reward.
2. Save during Sensor Pulse — SD refunded, no new SIGNAL from cancelled run.
3. Save mid scan/mining — mission resumes; stores consistent.
4. Save during colonization — pending op survives.
5. Pan/zoom, save, load — camera restored in same system.

---

## Code references

| Concern | Primary files |
|---------|----------------|
| Save orchestration | `scripts/autoload/save_manager.gd` |
| Session payload / scene snapshots | `scripts/autoload/game_session.gd` |
| Survey Probe cancel (disk) | `scripts/system/controller/survey_probe_mission_controller.gd` |
| Survey Probe restore (scene) | `capture_runtime_snapshot` / `restore_from_runtime_snapshot` |
| Sensor Pulse cancel (disk) | `scripts/system/controller/base_sensor_pulse_controller.gd` |
| Sensor Pulse restore (scene) | `capture_runtime_snapshot` / `restore_from_runtime_snapshot` |
| Automation snapshot | `scripts/system/controller/automation_controller.gd`, `scripts/system/automation/automation_save_service.gd` |
| Automation store | `scripts/autoload/stores/automation_store.gd` |
| Scene restore wiring | `scripts/system/system_scene.gd` |
| Camera | `scripts/system/controller/system_camera_controller.gd` |

---

## Later (save v2+)

- Persist active Sensor Pulse and Survey Probe with `started_at` / `duration` / target ids on **disk**.
- Unified operations array instead of ad-hoc pre-save hooks.
- Optional offline elapsed time for colonization and automation.
