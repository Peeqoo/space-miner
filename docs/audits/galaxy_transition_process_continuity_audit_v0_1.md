# Galaxy Transition Process Continuity Audit v0.1

**Date:** 2026-06-20  
**Godot:** 4.6.1  
**Scope:** SystemScene ↔ GalaxyMap scene transitions — gameplay process survival.  
**No gameplay/balance changes in this audit.**

---

## A — Scene Lifecycle

| # | Question | Finding |
|---|----------|---------|
| 1 | What happens on GalaxyMap open? | `NavigationHUD.galaxy_requested` → `SystemScene._on_navigation_galaxy_requested()` → `SceneFlow.goto_galaxy()` |
| 2 | Is `system_scene.tscn` freed? | **Yes** — `SceneFlow.goto_scene()` `queue_free()` on all children of `CurrentSceneSlot` |
| 3 | Are controller nodes destroyed? | **Yes** — entire `SystemScene` subtree including `AutomationController`, `SurveyProbeMissionController`, `BaseSensorPulseController` |
| 4 | `_exit_tree` / cleanup? | **No mission teardown** on controllers (only `SystemUIController` disconnects one signal). Save path calls explicit cancel/refund — **galaxy path did not** |
| 5 | Is `GameSession` reset? | **No** — autoload + stores survive. `current_system_id` updated before leave |

**Re-enter:** `GalaxyMap._on_enter_pressed()` → `SceneFlow.goto_system()` → fresh `SystemScene` → `apply_automation_save_if_pending()` only if `_automation_runtime_pending` populated.

---

## B — Process Lifecycle Table

| Process | Runtime Owner | Visual Owner | Persisted? | Survived Galaxy (pre-fix)? | Failure Mode |
|---------|---------------|--------------|------------|----------------------------|--------------|
| **SurveyProbe Investigate** | `SurveyProbeMissionController._active_missions` | `SurveyProbeUnit` | Probe count in `BaseStore` only | **No** | Probe consumed @ start; mission dict destroyed; target stays `SIGNAL` |
| **ScanDrone Mission** | `AutomationController` + `AutomationStore` | `AutomationUnit` | `_automation_runtime_pending` if snapshotted | **Partial** | Lost if snapshot race / no refresh before free |
| **ScanDrone Support-Orbit** | `AutomationController.scan_drone_target_by_unit_id` | Drone node | Same snapshot | **Partial** | Same as scan |
| **MiningShip Mission** | `AutomationController.mining_ship_runtime_by_unit_id` | `AutomationUnit` | Runtime snapshot | **Partial** | Cargo/progress lost without snapshot |
| **MiningShip Cargo** | Mining runtime dict | — | In mining snapshot | **Partial** | Zeroed if no snapshot |
| **SensorPulse** | `BaseSensorPulseController` | UI labels only | SurveyData spent immediately | **No** | Mid-pulse: cost spent, no reveal, no refund |
| **ColonizationOperation** | `GameSession._colonization_operations` | Galaxy HUD | Full save array | **Yes** | Timer continues on map |
| **Production build timer** | — | — | Instant builds | **N/A** | No active timer |
| **Upgrade timer** | — | — | Instant buys | **N/A** | No active timer |

---

## C — Verbrauch / Rewards

| Process | Spend @ Start | Reward @ Complete | If process lost (pre-fix) |
|---------|---------------|-------------------|---------------------------|
| SurveyProbe Investigate | 1 probe (`consume_survey_probe`) | `DISCOVERY_KNOWN`, SurveyData | **Probe lost**, no reveal |
| ScanDrone Scan | — (drone fleet) | Scan state + SurveyData | Orphan store mission / idle drone |
| MiningShip | — | Resources to base storage | **Cargo lost** |
| SensorPulse | SurveyData from `BaseStore` | HIDDEN→SIGNAL reveals | **Cost lost**, no reveal |
| Colonization | ColonyShip count | Established base | Safe (session-owned) |

---

## D — Save / Runtime

| Data | Location | Restore path |
|------|----------|--------------|
| Base inventory, fleet counts | `BaseStore` / `GameSession` | Always |
| Discovery / scan / deposits | `object_scans` | Always |
| Colonization ops | `GameSession._colonization_operations` | Save + session |
| Automation scan/mining visuals | `_automation_runtime_pending` | `AutomationController.apply_automation_save_if_pending()` |
| Camera | `_camera_state_pending` | `SystemScene._try_restore_saved_camera_state()` |
| Investigate missions | Scene controller only | **None (pre-fix)** |
| Sensor pulse progress | Scene controller only | **None (pre-fix)** |

---

## E — Root Cause

1. **Scene-owned gameplay state** — `SurveyProbeMissionController._active_missions` and `BaseSensorPulseController` pulse fields are not mirrored to `GameSession` on galaxy leave.
2. **`SceneFlow.goto_galaxy()`** frees `SystemScene` without pre-capture (unlike `SaveManager.build_save_data()` which cancels/refunds or snapshots).
3. **Probe consume is session-persistent** at mission start, but mission completion is scene-local → asymmetric loss.
4. **Automation** has snapshot infrastructure but `refresh_automation_snapshot_from_scene()` was **not** called on galaxy navigation (only on save / deferred emit).
5. **Visual vs gameplay** — automation restore path exists; investigate/sensor pulse do not.

**Observed bug sequence:** Investigate starts → probe −1 → galaxy → scene freed → return → probe still −1, no active mission, signal unrevealed.

---

## Target Architecture (v0.1 fix)

- `GameSession.capture_system_scene_processes_before_leave()` before `SceneFlow.goto_galaxy()`
- Snapshot: automation (existing), camera (existing), survey-probe ops, sensor-pulse state
- `SystemScene._finish_initial_setup()` restores survey-probe + sensor-pulse after automation pending apply
- **Time strategy:** Pause for investigate travel; **background progress** for investigate WORKING phase and sensor pulse (elapsed += away time)
