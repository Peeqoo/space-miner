# Save-v2 Mission Continuity Design v0.1

**Status:** Design only — **not implemented**.  
**Engine:** Godot 4.6.1.  
**Related:** `docs/save_behavior_v0_1.md`, `docs/architecture/per_object_discovery_refresh_design_v0_1.md`, `docs/audits/phase_3_4_discovery_refresh_smoketest_v0_1.md`.

---

## Purpose

Save/load in v0.1 is **functional** and keeps long-term progression (discovery, scans, resources, bases, colonization) consistent. What varies is how **in-flight missions** are treated at save time: some systems are **cancelled and refunded**, others are **snapshotted and restored**, and colonization is **data-only** in `GameSession`.

**Why Save-v2 might be needed**

- Players can lose **short mission progress** (Survey Probe investigate, Sensor Pulse) even though Scan/Mine automation continues after load — inconsistent UX.
- Automation restore depends on **scene tree timing** (`apply_automation_save_if_pending`, deferred frames) and **system/base guards**; edge cases produce warnings or dropped jobs.
- Mission state is split across **stores** (`ObjectScanStore`, `BaseStore`, `AutomationStore`) and **controller runtime** (snapshots, ephemeral controllers) without a single **operations** model.
- Future features (offline elapsed time, cross-scene ops, manual colonization confirm) need a documented contract before changing JSON.

**Why v0.1 behavior is acceptable today**

- Survey Probe and Sensor Pulse use **simple refund rules** that avoid half-applied discovery (no KNOWN without completion, no SIGNAL reveals from aborted pulse).
- Scan/Mine are the **core loop**; investing in snapshot/restore there already shipped.
- Colonization is already **session-serialized** with `remaining_ms` re-base on load.
- `SaveManager.SAVE_VERSION` is **1**; strict version check rejects unknown files — safe baseline.

**Save-v2 goal (scope of this design)**

**Mission continuity** — deterministic **continue** or **clean refund** after load — **without** new gameplay rules, economy changes, or discovery/scan semantics changes. Save-v2 describes *how* to persist ops; product still chooses per mission type whether to continue or cancel.

---

## Current Save Behavior

Entry: `SaveManager.build_save_data()` → pre-save hooks → `GameSession.to_save_data()` → JSON `save_version: 1`.  
Load: `SaveManager.apply_save_data()` → `GameSession.apply_save_data()` → pending automation/camera → scene restore.

| System | Current behavior before save | Stored data | Restored behavior | Risk |
|--------|-------------------------------|-------------|-------------------|------|
| **SurveyProbe Investigate** | `cancel_active_survey_probe_missions_before_save()` → `cancel_all_active_investigations_refund()` per active mission | **None** for investigate FSM; probe spend reversed via `add_survey_probe(1)`; discovery stays **SIGNAL** | No mission; player restarts investigate | Progress loss (intended); no double KNOWN / Survey Data reward |
| **BaseSensorPulse** | `cancel_active_base_sensor_pulse_before_save()` → `cancel_pulse_before_save()` if `_pulse_active` | **None** for pulse; `_paid_pulse_cost` refunded to paying base | No pulse; cooldown/runtime cleared on cancel | Progress loss; no partial SIGNAL reveals; **cooldown not in save** (resets with scene) |
| **ScanDrone mission** | `refresh_automation_snapshot_from_scene()` → `automation.runtime.scan_missions[]` | Per job: `target_id`, `base_id`, `mission_id`, `unit_state`, timers, position, orbit fields, `scan_reveal_done`; plus `automation.store.missions` (`target_scan_state`, `scan_is_progression` when mission record exists) | `AutomationController.apply_automation_save_if_pending()` → `_restore_scan_mission` when `system_id` + `primary_base_id` match | Restore skipped on mismatch; missing nodes → warning, idle fallback; **scan reward** already in `object_scans` if granted before save |
| **MiningShip mission** | Same snapshot path → `mining_missions[]` | Sanitized **runtime** dict + unit motion fields (`cargo_resources`, `status`, `target_id`, etc.) | Same restore path as scan | Cargo duplication / loss if runtime vs `BaseStore` diverge; storage-full **WAITING_FOR_STORAGE** must restore consistently |
| **Cargo / unload** | Part of mining runtime snapshot | `cargo_resources`, `current_cargo`, mining `status` enum | Restored into `mining_ship_runtime_by_unit_id` | Double delivery if unload completes twice after load |
| **Colonization** | Serialized as-is (no cancel) | `game_session.colonization_operations[]`: pending uses **`remaining_ms`**; completed/failed records kept | `_apply_colonization_operation_from_save()` → new `arrival_at_tick`; `process_colonization_operations()` when `allow_auto_complete` | Instant complete if `remaining_ms == 0`; no ship visuals; establish uses discovery signal path on complete |
| **DiscoveryState** | Written via store (probe/pulse cancel does **not** advance KNOWN / pulse SIGNAL) | `object_scans.object_discovery_states` | `ObjectScanStore.apply_save_data`; visuals on `SystemScene` enter via `apply_for_system` | Store vs marker drift healed on system enter (Phase 3.4 per-object refresh at runtime) |
| **ScanState** | Normal play + scan missions | `object_scans.object_scan_states` | Same store apply | Progression scan vs special scan gates unchanged |
| **remaining_resources** | Depletion during mining | `object_scans.remaining_resources_by_object` | Same store apply | Must not re-grant depleted amounts on restore |
| **Base resources** | Includes refunds on probe/pulse cancel | `game_session.bases` (full `BaseStore` dict) | `bases.apply_save_data` | Refund-at-save must match player expectation |
| **Camera state** | `refresh_camera_snapshot_from_scene()` | `game_session.camera_state` (`global_position`, `zoom`, `system_id`) | `SystemScene._try_restore_saved_camera_state()` if system matches | No restore if wrong system loaded first |

**Pre-save order (v0.1, fixed):**

1. Cancel survey probe missions (refund).  
2. Cancel sensor pulse (refund).  
3. Snapshot automation from scene.  
4. Snapshot camera from scene.  
5. `GameSession.to_save_data()`.

---

## What Works Today

- **DiscoveryState** persists in `ObjectScanStore` and survives load.
- **ScanState** persists; scan layer unlocks and rewards already applied remain in store.
- **remaining_resources** persists per object.
- **Base resources** (including Survey Probes, Survey Data, colony ships) persist via `BaseStore`.
- **Colonization operations** persist with tick re-base (`remaining_ms` → `arrival_at_tick`).
- **Automation snapshot** restores ScanDrone / MiningShip when system scene loads and guards pass.
- **SurveyProbe / SensorPulse cancel+refund** prevents broken half-states (no save-time KNOWN, no save-time pulse reveals).
- **Per-object discovery refresh** (Phase 3.4) keeps runtime visuals aligned with store after load enter (`apply_for_system`) and after gameplay events (`refresh_object` / `refresh_objects`).

---

## Current Limitations

- **SurveyProbe Investigate** does not resume; probe was already consumed at mission start — save refunds one probe but player loses timer progress.
- **BaseSensorPulse** does not resume; paid cost refunded, no partial reveal list persisted.
- **In-flight mission fidelity** varies: scan jobs save motion/orbit but not a unified `elapsed`/`duration` model; mining relies on ad-hoc runtime keys; **audio** is restarted from unit state, not saved.
- **Audio loops** are not save state (by design today); restore calls `_restart_automation_audio_after_restore()` — must not duplicate loops from stale saved “audio flags” (none exist).
- **Runtime references** (`unit`, `Node`, signal connections) cannot be serialized — restore must **respawn** units and reconnect.
- **Save during mission** requires clear **ownership**: who writes store vs who owns ephemeral controller state (`SurveyProbeMissionController._active_missions`, pulse `_pulse_active`, automation dictionaries).
- **SaveManager** rejects `save_version != 1` — any v2 file needs migration path before tightening checks.
- **Cross-system save**: automation snapshot tagged with `system_id`; jobs for other systems are not restored until player enters that system (no v0.1 `active_missions` bucket).
- **Sensor pulse cooldown** is controller-local; not in save — load into system scene resets cooldown unless separately persisted.

---

## Save-v2 Goals

| Goal | Meaning |
|------|---------|
| No duplicate units | Restoring a mission must not spawn a second drone/ship/probe for the same logical mission id |
| No lost resources | Refund-on-cancel and cargo-on-continue must be mutually exclusive and auditable |
| No duplicate rewards | Survey Data scan rewards, investigate Survey Data, pulse reveals, mining delivery — each at most once per mission completion |
| No duplicate reveals | Discovery transitions (`HIDDEN→SIGNAL`, `SIGNAL→KNOWN`) idempotent per `object_id` |
| No hanging audio loops | Audio derived from restored **mission/unit state** only |
| No marker duplicates | Discovery refresh uses store + per-object refresh; no duplicate `SignalMarker` after restore |
| Deterministic continue **or** clean refund | Every mission type documents one path; no silent half-state |
| Old saves remain loadable | v1 files load with v0.1 semantics; new fields optional until restore implemented |

**Non-goals for Save-v2 design**

- Changing mission durations, costs, reveal counts, or gate rules.
- Changing save file path or slot count.
- Persisting UI panel layout, selection, or tooltips (`tooltip_text` stays **0**).

---

## Mission-by-Mission Decision

### 1. SurveyProbe Investigate

| Option | Description |
|--------|-------------|
| **A (v0.1)** | Continue **cancel + refund** before save |
| **B (Save-v2 candidate)** | Persist mission state and resume after load |

**If B — fields to persist (design)**

| Field | Source today |
|-------|----------------|
| `mission_type` | `"survey_probe_investigate"` |
| `system_id` | `_system_id` |
| `object_id` | mission key |
| `base_id` | mission `base_id` |
| `elapsed` / `duration` | `SurveyProbeUnit` investigate progress / sampled duration |
| `probe_consumed` | `true` after `consume_survey_probe` (do **not** refund on continue) |
| `reward_granted` | `false` until `_complete_mission` |
| `cost_paid` | 1 probe (implicit) |

**Risks**

| Risk | Mitigation |
|------|------------|
| Double **KNOWN** + `refresh_object` | Only complete path sets KNOWN; restore must not call complete twice |
| Double **Survey Data** reward | `reward_granted` flag; complete handler checks |
| Marker / selection | On restore: if still SIGNAL, respawn probe unit and progress UI; on complete, same as live path + selection refresh |
| Save during outbound travel | Must persist unit motion or restart from base with same timer |

**Recommendation:** **Defer B** until automation-style snapshot pattern is proven for probes. **Keep A** as default for v2.0 unless product prioritizes investigate continuity; if B ships, **do not refund** probe on save (probe already spent).

---

### 2. BaseSensorPulse

| Option | Description |
|--------|-------------|
| **A (v0.1)** | Cancel + refund `_paid_pulse_cost` |
| **B** | Persist pulse and resume |

**If B — fields to persist**

| Field | Notes |
|-------|--------|
| `system_id`, `base_id` | `_system_id`, `_paid_pulse_base_id` |
| `elapsed`, `duration` | `_pulse_elapsed`, `_pulse_duration` |
| `cost_paid` | copy of `_paid_pulse_cost` |
| `reward_granted` | `false` until `_complete_pulse` |
| `cooldown_remaining` | optional if cooldown should survive load |

**Risks**

| Risk | Mitigation |
|------|------------|
| Double **Survey Data** spend | `cost_paid` recorded; no second `_spend_pulse_cost` on resume |
| Double **SIGNAL** reveals | `_complete_pulse` runs once; store sets SIGNAL then `refresh_objects` once |
| Partial candidate list | Do **not** save candidate picks until complete — recompute from store HIDDEN set on complete |

**Recommendation:** **Keep A** for first Save-v2 slice. Pulse is short; refund matches v0.1 trust model. B is optional later with strict `reward_granted` / single completion.

---

### 3. ScanDrone

| Option | Description |
|--------|-------------|
| **A (v0.1)** | Snapshot in `automation.runtime.scan_missions` + `AutomationStore` mission record |
| **B** | Unified `active_missions` entry with explicit `reward_granted` / progression flags |

**v0.1 snapshot already includes**

- `mission_id`, `target_id`, `base_id`, `scan_reveal_done`, unit motion/state.
- Store mission: `target_scan_state`, `scan_is_progression` (when `mission_id > 0`).

**Gaps / evaluation**

| Topic | Today | Save-v2 improvement |
|-------|--------|---------------------|
| `scan_is_progression` | In store mission, not always in job dict | Copy into `active_missions` row for restore without store guess |
| `target_scan_state` | Same | Same |
| `reward_granted` | Implicit via `scan_reveal_done` + scan state in `ObjectScanStore` | Explicit flag to block double `grant_scan_survey_data_reward` |
| `elapsed` / `progress` | `work_timer`, `work_duration`, `travel_progress` | Keep; document mapping |
| Unit identity | New instance id on restore | Stable **`mission_id`** as logical key (already used) |

**Recommendation:** **Keep snapshot pattern (A)** for v2; optionally **normalize** into `active_missions` without changing gameplay. **Do not** blindly switch to full restore without migration tests. Improve **reward_granted** idempotency first.

---

### 4. MiningShip

| Option | Description |
|--------|-------------|
| **A (v0.1)** | Full runtime dict snapshot + unit visual restore |
| **B** | Unified `active_missions` + stricter cargo ledger |

**Runtime states (enum)** — `TO_TARGET`, `MINING`, `TO_BASE`, `UNLOADING`, `WAITING_FOR_STORAGE`.

**Critical persist fields**

- `cargo_resources`, `status`, `target_id`, `base_id`, timers, position.
- **Extracted but not delivered** = cargo in runtime while status `TO_BASE` / `UNLOADING` / `WAITING_FOR_STORAGE`.

**Risks**

| Risk | Mitigation |
|------|------------|
| **Cargo duplication** | On restore, cargo only in runtime OR base storage, never both; unload completion clears runtime cargo atomically |
| **Resource loss** | If restore fails, fallback idle must deposit cargo to base or log loss (v0.1: fallback helpers exist — document behavior in tests) |
| **Storage full** | `WAITING_FOR_STORAGE` must restore without auto-unload until space |

**Recommendation:** **Keep A**, harden with explicit `cargo_snapshot_checksum` or `delivered_amount` only if tests find dupes. **B** is structural cleanup, not required for continuity if snapshot tests pass.

---

### 5. Colonization

**Already v0.1-correct pattern** — `GameSession` operation records, not scene units.

| Aspect | Behavior |
|--------|----------|
| Persist | `operation_id`, `source_base_id`, `target_system_id`, `target_body_id`, `status`, `remaining_ms` / ticks, `reserved_colony_ships` |
| Complete | `establish_base_at_body` → discovery **KNOWN** in store → `established_body_discovery_visual_refresh_requested` when in system |
| Save-v2 change | **Optional:** manual confirm step if `allow_auto_complete` false; still same record shape |

**Recommendation:** **No mission-type change** for Save-v2; document as reference implementation for timer-based ops. Align Survey/Pulse **only if** product chooses continue-over-refund.

---

## Proposed Save-v2 Schema (design only)

**Do not write `save_version: 2` to disk until restore + migration are implemented.**

Top-level (compatible extension):

```json
{
  "save_version": 2,
  "saved_at_unix": 0,
  "slot_index": 1,
  "current_system_id": "sol",
  "game_session": { }
}
```

`SaveManager` would eventually accept `save_version` 1 and 2; v1 loads with empty `active_missions`.

### `game_session` sections (v2 proposal)

| Section | v1 today | v2 notes |
|---------|----------|----------|
| `object_scans` | Yes | Unchanged shape |
| `bases` | Yes | Unchanged |
| `colonization_operations` | Yes | Unchanged |
| `automation` | `{ store, runtime }` | Keep; runtime may shrink as `active_missions` grows |
| `camera_state` | Yes | Unchanged |
| `active_missions` | **Missing** | New array — see below |
| `pending_refunds` | **Missing** | Optional audit trail if cancel-at-save remains |

### `active_missions[]` record (union by `mission_type`)

Common fields:

| Field | Type | Purpose |
|-------|------|---------|
| `mission_id` | String or int | Logical id (`AutomationStore` int or `colony_*` / generated UUID for probe/pulse) |
| `mission_type` | String | `scan_drone`, `mining_ship`, `survey_probe_investigate`, `sensor_pulse`, … |
| `system_id` | String | |
| `base_id` | String | Paying / home base |
| `object_id` | String | Target body/poi/signal |
| `unit_id` | int | **Save-v2:** 0 on save (instance ids invalid); restore spawns new unit |
| `state` | String | Controller phase enum name |
| `elapsed` | float | |
| `duration` | float | |
| `progress` | float | 0–1 UI |
| `cargo_resources` | Dictionary | Mining only |
| `scan_is_progression` | bool | Scan only |
| `target_scan_state` | String | Scan only |
| `reward_granted` | bool | Idempotency |
| `cost_paid` | Dictionary | Pulse / optional probe |
| `created_at_game_time` | float | Optional; for offline elapsed (future) |

**Survey probe / pulse in v2:** only populated if product selects **continue**; otherwise omit and keep pre-save cancel hooks.

### `pending_refunds` (optional)

If save still cancels some missions:

```json
{ "base_id": "earth", "resources": { "survey_data": 5 }, "reason": "save_cancel_sensor_pulse" }
```

Used for debug/support, not required for gameplay if refund applied before serialize.

---

## Migration Strategy

| Rule | Detail |
|------|--------|
| v1 → v2 load | `active_missions` absent → behave exactly as v0.1 (cancel hooks on **save** unchanged until feature flags flip) |
| Missing fields | Safe defaults: `reward_granted: false`, empty `cargo_resources`, `progress: 0` |
| Write v2 only when | Restore implemented and covered by test matrix |
| No breaking change | v1 files must load after SaveManager teaches version `2` with fallback reader |
| Dual-write period (optional) | Serialize both `automation.runtime` and `active_missions` during transition; restore prefers `active_missions` if non-empty |

**Implementation gate:** Step 1 adds `save_version` tolerance **without** changing default write version — see Recommended Implementation Order.

---

## Ownership

| Data | Owner | Should save? | Should restore? |
|------|--------|--------------|----------------|
| `object_discovery_states` | `ObjectScanStore` / `GameSession` | Yes (in `object_scans`) | Yes → full/per-object apply on scene |
| `object_scan_states` | `ObjectScanStore` | Yes | Yes |
| `remaining_resources_by_object` | `ObjectScanStore` | Yes | Yes |
| Base resources / probes / ships | `BaseStore` | Yes | Yes |
| `AutomationStore.missions` | `AutomationStore` | Yes (`automation.store`) | Yes before unit restore |
| Scan/Mine unit runtime | `AutomationController` | Yes (`automation.runtime`) | Yes when system/base match |
| Survey probe FSM | `SurveyProbeMissionController` | **v0.1: No** | **v0.1: No** |
| Sensor pulse FSM | `BaseSensorPulseController` | **v0.1: No** | **v0.1: No** |
| Colonization ops | `GameSession` | Yes | Yes + tick re-base |
| Discovery markers | `SystemDiscoveryController` | **No** (derived) | Regenerate from store |
| Selection / ObjectInfoPanel | `SystemUIController` | **No** | Empty until user selects |
| Audio players | `AutomationController` / units | **No** | Restart from unit state |
| Camera | `SystemCameraController` | Yes | Yes if `system_id` match |
| Signal connections | Nodes | **No** | Reconnect in controller setup |

---

## What Must NOT Be Saved

- Node references (`unit`, `marker`, `NodePath` to live nodes)
- Godot signal connections
- `AudioStreamPlayer` nodes or playback position
- UI panel state (except camera already stored)
- Derived `SignalMarker` instances
- Temporary hover / blocked-reason strings
- `tooltip_text` or tooltip state (project policy: **0**)
- `GameSession.current_system_definition` resource handle (reload by id)

---

## Restore Order (proposed)

Applies when Save-v2 restore is implemented; v0.1 already follows a subset.

1. **Load `GameSession` stores** — `bases`, `object_scans`, colonization, automation store, pending flags.
2. **Resolve `current_system_id`** and load `SystemDefinition` (no scene yet).
3. **Enter / spawn system scene** — `SystemSpawner.spawn_from_definition`.
4. **Full discovery sync** — `ensure_default_discovery_for_system` + `discovery_controller.apply_for_system` (markers from store).
5. **Restore automation units** — `apply_automation_save_if_pending` / future `active_missions` restore (spawn units, mission records).
6. **Restore optional active_missions** — survey/pulse only if enabled; else pre-save cancel already ran on last save.
7. **Reconnect controllers** — `setup()` on discovery, probe, pulse, UI (existing scene wiring).
8. **Refresh UI** — selection empty; panels from user input; colonization labels from `GameSession`.
9. **Camera** — `_try_restore_saved_camera_state`.
10. **Audio** — `_restart_automation_audio_after_restore()` from **restored unit/mission state only**.

**Colonization:** `GameSession._process` may complete ops after load; establish triggers discovery refresh signal when in system (Phase 3.4).

---

## Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Duplicated scan Survey Data reward | Medium | High | `reward_granted` + store scan state checks before grant |
| Duplicated mining cargo / base storage | Medium | High | Single source of truth on restore; test unload paths |
| Resource loss on failed restore | Low | High | Fallback deposit + warning; test matrix |
| Wrong discovery reveal (double SIGNAL/KNOWN) | Low | High | Store-driven refresh only on complete; idempotent state sets |
| Duplicate automation units | Medium | High | Clear visuals before restore; mission_id dedup |
| Storage full during restore | Medium | Medium | Restore `WAITING_FOR_STORAGE`; no silent drop |
| Mission target missing after load | Low | Medium | Skip restore + refund or idle fallback (document per type) |
| Old save compatibility broken | Low | Critical | Versioned loader; v1 path unchanged |
| Marker duplicates after restore | Low | Medium | `apply_for_system` once on enter; per-object refresh on events |
| Hanging audio | Low | Low | Never save audio; restart from state |
| Survey probe refund + continue (B) | Medium | Medium | Mutually exclusive policy per option A vs B |

---

## Recommended Implementation Order (plan only)

| Step | Action | Behavior change? |
|------|--------|------------------|
| 1 | Add `save_version` read tolerance (accept 1; prepare 2) | **No** default write change |
| 2 | Document current schema → `docs/save_schema_v1.md` | None |
| 3 | Add mission serialization structs / `active_missions` **write-only** behind dev flag | None in release |
| 4 | Restore **ScanDrone** via normalized record + `reward_granted` | Dev only |
| 5 | Restore **MiningShip** cargo/unload states | Dev only |
| 6 | **Product decision:** SurveyProbe / SensorPulse continue vs refund | Feature flag |
| 7 | Migration tests v1↔v2 + test matrix automation where possible | |

---

## Test Matrix

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Save idle (no missions) | Clean load; no warnings |
| 2 | Save during scan **outbound** | One drone; progress resumed or refund policy documented |
| 3 | Save during scan **work** at target | Same; no double scan reward |
| 4 | Save **after** scan reward applied | Store has scan state; no second reward on load |
| 5 | Save mining **outbound** | Ship + target restored |
| 6 | Save mining with **cargo** | Cargo count matches; no dupe on unload |
| 7 | Save during **unload** | Completes once or waits storage correctly |
| 8 | Save **storage full** (`WAITING_FOR_STORAGE`) | Still waiting after load; no lost cargo |
| 9 | Save during **SurveyProbe** | v0.1: refunded, SIGNAL; v2 B: continued if enabled |
| 10 | Save during **SensorPulse** | v0.1: refunded, no reveals; v2 B: continued if enabled |
| 11 | Save during **Colonization** | Op pending or completes; base record correct |
| 12 | Load **old v1** save | Identical to today |
| 13 | Load with **missing target** node | Graceful skip; no crash |
| 14 | No duplicate **resources** in base | Balance unchanged except intended |
| 15 | No duplicate **units** visible | Count matches missions |
| 16 | No duplicate **rewards** | Survey Data / scan grants once |
| 17 | Re-enter system after galaxy load | Discovery visuals match store |
| 18 | `tooltip_text` grep | 0 in `*.gd` / `*.tscn` / `*.tres` |

---

## Do Not Implement Yet

- No code changes in `scripts/`, `scenes/`, `data/`, `resources/`.
- No `save_version` bump in `SaveManager.SAVE_VERSION` for players.
- No controller splits or automation refactors.
- No mission restore logic until this design is reviewed.
- No new gameplay rules (durations, costs, reveal counts).
- No `tooltip_text` introduction.

---

## Recommended Next Prompt

```
Audit the current v0.1 save JSON shape from SaveManager.build_save_data() / GameSession.to_save_data() and document it in docs/save_schema_v1.md (field list, types, owners, notes). Read-only — no code changes.
```

---

## Code references (read during design)

| Concern | File |
|---------|------|
| Save orchestration | `scripts/autoload/save_manager.gd` |
| Pre-save cancel / snapshot | `scripts/autoload/game_session.gd` |
| Object scans / discovery | `scripts/autoload/stores/object_scan_store.gd` |
| Bases | `scripts/autoload/stores/base_store.gd` |
| Automation store | `scripts/autoload/stores/automation_store.gd` |
| Snapshot / restore | `scripts/system/controller/automation_controller.gd` |
| Survey cancel | `scripts/system/controller/survey_probe_mission_controller.gd` |
| Pulse cancel | `scripts/system/controller/base_sensor_pulse_controller.gd` |
| Discovery apply | `scripts/system/controller/system_discovery_controller.gd` |
| Load order | `scripts/system/system_scene.gd` |

---

## Acceptance (this document)

1. Only `docs/architecture/save_v2_mission_continuity_design_v0_1.md` was created.  
2. No code/scene/data changes.  
3. Does not assume all missions get continue-on-load — explicit A/B per type.  
4. v0.1 cancel/refund rules match `docs/save_behavior_v0_1.md` and code.  
5. Save-v2 schema, migration, tests, and restore order included.  
6. Single small next step: `save_schema_v1.md` audit prompt.
