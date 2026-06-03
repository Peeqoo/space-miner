# Save Behavior v0.1

Short reference for how **Space Mining v0.1** handles **active operations** when the player saves or loads. Entry point: `SaveManager.build_save_data()` → `GameSession.to_save_data()` / `apply_save_data()`.

## Summary

- **SurveyProbe Investigate** — Cancelled before save; probe unit is torn down and **one Survey Probe is refunded** to the base. Mission progress is **not** written to the save file.
- **Base Sensor Pulse** — Cancelled before save; **paid Survey Data cost is refunded** to the base that paid. Pulse progress and reveals from that run are **not** persisted.
- **ScanDrone / MiningShip automation** — Live missions are **snapshotted** from `AutomationController` and restored after load (store + runtime payload in `game_session.automation`).
- **Colonization operations** — Stored in `GameSession` (`colonization_operations`). Pending ops survive save/load; with `allow_auto_complete = true` they can finish on the next tick after load when duration has elapsed.
- **Camera (system view)** — Position and zoom are saved per `system_id` and restored when the matching system scene loads.

**v0.1 principle:** Prefer **cancel + refund** for Survey Probe and Sensor Pulse over saving half-finished missions. Automation and colonization use structured session data instead.

---

## Overview table

| Operation | On save | On load | Refund? | Reason | Risk |
|-----------|---------|---------|---------|--------|------|
| SurveyProbe Investigate | Cancel all active missions; refund probe | Not restored; signal stays **SIGNAL** (no KNOWN from aborted run) | **Yes** — 1 probe per cancelled mission (`add_survey_probe`) | No mission serializer in v0.1; avoid SIGNAL→partial KNOWN bugs | Player loses investigate progress (intended); must restart investigate |
| Base Sensor Pulse | Cancel if active; clear pulse state | Not restored | **Yes** — full `_paid_pulse_cost` dictionary refunded to paying base | Pulse is session-only UI/runtime; avoid charging without reveal | Player loses pulse progress (intended); cooldown may still apply from controller state until scene reset |
| ScanDrone mission | Snapshot in `automation.runtime` (`scan_missions`) | `AutomationController` restores drones + mission state when system/base match | No | Standard automation save path | Restore skipped if `system_id` or `primary_base_id` mismatch; missing nodes → warning, mission dropped |
| MiningShip mission | Snapshot in `automation.runtime` (`mining_missions`) | Same as ScanDrone | No | Same | Same; in-flight cargo/unload uses job fields in snapshot |
| Colonization op | Serialized in `game_session.colonization_operations` (`remaining_ms` for pending) | Rebuilt `arrival_at_tick`; pending ops continue | No (op continues) | Data-only op, no scene units | Tick-based timing can complete immediately after load if `remaining_ms` was 0; metadata uses pending count only |
| Camera (system) | `camera_state` in session (position, zoom, `system_id`) | `SystemScene._try_restore_saved_camera_state()` if system matches | N/A | QoL for same-system return | No restore if saved system ≠ loaded system |

---

## Details

### SurveyProbe Investigate

**Save path:** `SaveManager.build_save_data()` → `GameSession.cancel_active_survey_probe_missions_before_save()` → `SurveyProbeMissionController.cancel_all_active_investigations_refund()`.

- Each active mission: `_abort_mission_with_refund()` — removes mission, frees unit, **`GameSession.add_survey_probe(1, base_id)`**.
- Does **not** call `refresh_object` or set discovery to KNOWN (tear down without revealing signals).
- Survey Data reward from a **completed** investigate is never applied on save-cancel (only on normal completion).

**Normal completion (not save-cancel):** `set_object_discovery_state(KNOWN)` → `discovery_controller.refresh_object(oid)` → reward + selection refresh.

**Load:** No investigate mission records in save. Player sees the same signal as before the aborted run.

### Base Sensor Pulse

**Save path:** `GameSession.cancel_active_base_sensor_pulse_before_save()` → `BaseSensorPulseController.cancel_pulse_before_save()`.

- If `_pulse_active`: pulse stopped, **`_refund_paid_pulse_cost_if_any()`** (resources paid at start via `_spend_pulse_cost`).
- Does **not** run `_complete_pulse()` (no HIDDEN→SIGNAL reveal from a cancelled save; no `refresh_objects`).

**Normal completion (not save-cancel):** per candidate `set_object_discovery_state(SIGNAL)` → `discovery_controller.refresh_objects(revealed_ids)` (no `apply_for_system` on pulse end).

**Load:** No pulse state in save. Player must start a new pulse (pay cost again unless refunded path already ran at save).

### ScanDrone / MiningShip

**Save path (after probe/pulse cancel):**

1. `GameSession.refresh_automation_snapshot_from_scene()` — `AutomationController.to_save_data()` → `scan_missions` / `mining_missions` arrays.
2. `GameSession.to_save_data()` stores `automation: { store, runtime }` (`AutomationStore` mission records + runtime snapshot).

**Load path:**

1. `GameSession.apply_save_data()` → `_apply_automation_from_save_data()` sets `_automation_runtime_pending`.
2. When system scene is ready, `AutomationController.apply_automation_save_if_pending()` restores missions (spawns units, `restore_mission_visual_state`, etc.).
3. Guards: skip restore if saved `system_id` or `primary_base_id` does not match current session.

Scan progression / Survey Data rewards already applied during play remain in `object_scans` / base resources via normal session stores.

### Colonization

**Save path:** Pending (and other) operations included in `colonization_operations` array; pending ops store **`remaining_ms`** instead of absolute ticks.

**Load path:** `_apply_colonization_operation_from_save()` recomputes `arrival_at_tick` from `remaining_ms` and current tick.

**Runtime:** `GameSession._process()` calls `process_colonization_operations()` when `ColonizationDefinition.allow_auto_complete` is true (`data/colonization/default_colonization.tres`: **60s**, auto-complete **on**). Expired pending ops complete without a separate scene mission.

No colony ship travel visuals in v0.1; state is UI/session only.

**Establish / complete (runtime, same system):** `_apply_established_base_record` sets discovery **KNOWN** in save data and emits `established_body_discovery_visual_refresh_requested`. **SystemUIController** (when system scene is active) calls `discovery_controller.refresh_object(body_id)` if the established body is in the **current** system — **no** `apply_for_system` on establish. Save JSON shape unchanged; if player is on galaxy map when op completes, visuals sync on next system enter via `apply_for_system`.

### Camera state

**Save path:** `GameSession.refresh_camera_snapshot_from_scene()` then `to_save_data()` also captures via `SystemCameraController.to_save_state()` (`global_position`, `zoom`, `system_id`).

**Load path:** Pending camera dict applied in `SystemScene._try_restore_saved_camera_state()` after spawn if `has_camera_state_pending_for_system(current_system_id)`.

---

## Deliberate v0.1 decisions

- **Do not** persist active Survey Probe investigations or Base Sensor Pulse runs.
- **Do** refund consumables/costs for those cancels so save never soft-locks resources.
- **Do** persist ScanDrone/MiningShip via automation snapshot (accepted complexity; missions are core loop).
- **Do** persist colonization as session records (timers re-based on load).

Rationale: Investigate and Pulse are short, base-local actions with simple refund rules. Restoring them would need timestamps, partial progress, and discovery-edge-case handling — deferred to a future save format.

---

## Later (save v0.2+)

Possible extensions:

- Persist **active** Sensor Pulse and Survey Probe with `started_at` / `duration` / `target` ids.
- Optional **operation timestamps** (Unix or tick) for offline elapsed time.
- Unified **operations** array in save JSON instead of ad-hoc pre-save hooks.
- Colonization: manual confirm step if `allow_auto_complete` is false (status label already supports “Awaiting confirmation”).

---

## Smoke tests

Manual checks after code changes to save/load:

1. **Save during SurveyProbe Investigate** — Start investigate on a signal, save while probe is in flight. After load: signal still SIGNAL, probe count refunded (+1 vs spend), no KNOWN, no Survey Data reward from that run.
2. **Save during Sensor Pulse** — Start pulse on home base (Survey Data spent), save during progress bar. After load: no active pulse, Survey Data refunded (balance as before pulse), no new SIGNAL reveals from cancelled run.
3. **Save during Scan / Mining** — Launch scan or mining mission, save mid-flight. After load: mission continues or resumes visually; scan state / cargo consistent with stores; no duplicate drones if restore succeeds.
4. **Save during colonization** — Start colonization, save while pending. After load: op still pending or auto-completed if time elapsed; target base appears when completed.
5. **Camera** — Pan/zoom in system view, save, load same slot — camera roughly restored in same system.

---

## Code references (for debugging)

| Concern | Primary files |
|---------|----------------|
| Save orchestration | `scripts/autoload/save_manager.gd` (`build_save_data`, `apply_save_data`) |
| Session payload | `scripts/autoload/game_session.gd` (`to_save_data`, `apply_save_data`, cancel/refund helpers) |
| Survey Probe cancel | `scripts/system/controller/survey_probe_mission_controller.gd` |
| Sensor Pulse cancel | `scripts/system/controller/base_sensor_pulse_controller.gd` |
| Automation snapshot/restore | `scripts/system/controller/automation_controller.gd` |
| Camera restore | `scripts/system/system_scene.gd`, `scripts/system/controller/system_camera_controller.gd` |
| Colonization data | `data/colonization/default_colonization.tres`, `GameSession` colonization APIs |

Save file: `user://saves/save_NNN.json`, `save_version = 1`.
