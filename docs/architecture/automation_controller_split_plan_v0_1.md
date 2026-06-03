# AutomationController Split Plan v0.1

**Status:** Design only — **no split implemented**.  
**Engine:** Godot 4.6.1.  
**Scope file:** `scripts/system/controller/automation_controller.gd` (~**3036** lines, `class_name AutomationController`).  
**Related:** `docs/save_schema_v1.md`, `docs/architecture/save_v2_mission_continuity_design_v0_1.md`, `docs/architecture/per_object_discovery_refresh_design_v0_1.md`, `docs/save_behavior_v0_1.md`.

---

## Purpose

`AutomationController` is the **largest high-risk system controller** in v0.1. It owns visible **ScanDrone** and **MiningShip** automation, **idle unit spawning**, **mining tick simulation**, **save/runtime snapshots**, **world audio**, and **shared survey-probe unit pooling** — all in one node.

**Why split later**

- Single file mixes unrelated failure modes (cargo unload bugs vs scan reward vs audio loops vs JSON restore).
- Changes to mining storage-full logic risk regressing scan save restore (and vice versa).
- Test and review surface is too large for safe iteration.

**Why no big-bang refactor now**

- Save v1 schema (`automation.store` + `automation.runtime`) is production-shaped; split must preserve byte-level behavior.
- `SystemUIController` and `SurveyProbeMissionController` depend on **public fields and methods** on `AutomationController` today.
- Mission gameplay rules are frozen for v0.1; this plan only **separates responsibilities**, not redesigns them.

**Goal of this document**

Make responsibilities visible, define **future service boundaries**, keep a **stable public facade**, and specify a **safe extraction order** (audio → save → spawn → scan → mining).

---

## Current Responsibilities

| Responsibility | Current functions / state | External dependencies | Risk |
|----------------|---------------------------|------------------------|------|
| **ScanDrone launch / travel / scan complete** | `launch_scan_drone`, `_scan_drone_start_outbound`, `_on_scan_drone_arrived_at_target`, `_complete_scan_mission`, `_on_scan_drone_return_dock_clear_assignment` | `GameSession.can_scan_object`, `create_scan_mission`, `complete_automation_mission`, `set_object_scan_state`, `grant_scan_survey_data_reward`, `ensure_object_resources_initialized`, `AutomationStore` via mission record | Double scan reward; wrong `scan_is_progression`; mission_id / unit desync |
| **MiningShip launch / tick / cargo / unload** | `launch_mining_ship`, `_process` (mining FSM), `_on_mining_ship_arrived_at_target`, `_on_mining_ship_returned_to_base`, `_mining_ship_enter_waiting_for_storage`, `_unload_greedy_into_base_until_full` | `GameSession.extract_resource_amount`, `add_base_resource`, `ensure_mining_resources_for_object`, `ObjectScanStore` remaining resources, `BaseStore` capacity | Cargo dup/loss; storage-full hang; wrong `remaining_resources` |
| **Unit spawning / idle orbit** | `_spawn_unit`, `ensure_starting_units`, `spawn_idle_*`, `_register_idle_*`, `_get_idle_drone` / `_get_idle_mining_ship`, orbit transfer after scan | `SystemSpawner` (targets), `UnitCatalog`, scenes `drone.tscn` / `mining_ship.tscn` | Duplicate idle units; missing start units |
| **Recall / abort** | `recall_one_drone_from_target`, `recall_one_mining_ship_from_target`, `_abort_scan_mission_for_unit`, `_scan_drone_recall_to_base`, `_mining_ship_recall_to_base` | Signal disconnect, runtime dict cleanup | Wrong target recalled; mission left in `AutomationStore` |
| **Audio (SFX + loops)** | `_play_automation_sfx`, `_play_unit_travel_sfx`, `_start_scan_orbit_audio` / `_stop_scan_orbit_audio` (`scan_loop`), `_play_mining_resource_tick_sfx`, `_restart_automation_audio_after_restore` | `AudioManager.play_world_sfx_*`, `play_world_loop_optional`, `stop_world_loop_optional` | Hanging `scan_loop`; duplicate ticks after restore |
| **Save snapshot** | `to_save_data`, `_scan_missions_to_save_array`, `_mining_missions_to_save_array`, `_build_*_job_save_dict`, `_sanitize_*` | `GameSession.current_system_id`, `_session_primary_base_body_id` | Wrong `scan_reveal_done`; missing jobs |
| **Restore snapshot** | `apply_automation_save_if_pending`, `apply_save_data`, `_restore_automation_runtime_when_ready`, `_restore_scan_mission`, `_restore_mining_mission`, `_clear_automation_visuals_and_mission_state` | `GameSession.take_automation_runtime_pending`, system/base guards | Restore skipped; zero jobs after load |
| **AutomationStore mission records** | `launch_scan_drone` → `create_scan_mission`; `_on_scan_drone_arrived_at_target` → `complete_automation_mission`; restore may `restore_mission_record` | `AutomationStore` in `GameSession.automation` | Orphan store mission vs no unit |
| **UI callbacks / signals** | `signal automation_state_changed`, `_request_automation_state_changed` (also refreshes GameSession snapshot) | `SystemUIController` listens; reads public dicts | Stale panel counts; extra save snapshot churn |
| **BaseStore interaction** | Unit counts via `ensure_starting_units`; unload via `add_base_resource`; survey probe idle count vs `survey_probes` | `GameSession.bases`, `base_resources_changed` | Storage reject → `WAITING_FOR_STORAGE` |
| **ObjectScanStore interaction** | Scan completion sets scan state + seeds resources; mining uses `extract_resource_amount` / deposit lists | `GameSession` facade on `object_scans` | Scan vs discovery confusion (discovery **not** here) |
| **Survey probe unit pool** (shared infra) | `take_idle_survey_probe_for_base`, `return_survey_probe_to_idle_orbit`, `ensure_survey_probe_units_for_base`, `idle_survey_probes`, `survey_probe_busy_unit_ids` | `SurveyProbeMissionController` only caller for investigate | Must **not** merge with scan/mining mission services |

---

## Current Data Ownership

| Data | Owner | AutomationController role |
|------|--------|------------------------------|
| Logical scan/mine mission record (`mission_id`, `target_scan_state`, `scan_is_progression`) | **`AutomationStore`** via `GameSession` | Creates on launch; completes on scan arrive; may restore record on load |
| Visible `AutomationUnit` nodes | **`AutomationController`** (scene children under `AutomationRoot`) | Spawn, move, orbit, queue_free |
| Scan assignment per unit | **`scan_drone_target_by_unit_id`** (instance_id → `target_id`) | UI job counts; save scan jobs |
| Mining FSM per unit | **`mining_ship_runtime_by_unit_id`** (instance_id → runtime `Dictionary`) | `_process` driver; save mining jobs |
| Active scan unit per store mission | **`active_units_by_mission_id`** | Until `complete_automation_mission` |
| Idle pools | **`idle_drones`**, **`idle_mining_ships`**, **`idle_survey_probes`** | Launch consumes idle; return registers idle |
| Scan state per object | **`ObjectScanStore`** via `GameSession.set_object_scan_state` | Written in `_complete_scan_mission` |
| Remaining deposit amounts | **`ObjectScanStore`** via `GameSession.extract_resource_amount` | Mining tick |
| Base storage resources | **`BaseStore`** via `GameSession.add_base_resource` | Unload / greedy load |
| Session primary base for scene | **`_session_primary_base_body_id`** | Save/restore guard; launch base |
| Audio loop ids | **`AudioManager`** (keyed e.g. `scan_orbit_{instance_id}`) | Start/stop from controller |
| ObjectInfo / action buttons | **`SystemUIController`** | Calls launch/recall; **reads** runtime dicts for status text |

---

## Non-Goals

- No **Save-v2** or `active_missions` array implementation.
- No change to **mission restore semantics** (only move code).
- No new mission types (POI drone, build queue, etc.).
- No merging **SurveyProbe investigate** into ScanDrone/MiningShip code paths.
- No **build queue** or production automation expansion.
- No new resources or economy rules.
- No balance changes (durations, rates, cargo caps stay in `UnitCatalog` + `GameSession` multipliers).
- No **movement/orbit rewrite** (`AutomationUnit` API stays).
- No new audio events or loop types.
- No `tooltip_text` (project policy: **0**).

---

## Why SurveyProbe Stays Separate

| Aspect | SurveyProbe | ScanDrone / MiningShip |
|--------|-------------|-------------------------|
| Controller | **`SurveyProbeMissionController`** | **`AutomationController`** |
| Inventory | **`BaseStore.survey_probes`** consumed per launch | **Drones/ships** as unit counts + idle pool |
| Mission outcome | Discovery **KNOWN** + `refresh_object` (outside automation) | Scan state / mining cargo |
| Store mission | **Not** in `AutomationStore` | `AutomationStore` SCAN / MINE |

**Shared today:** `AutomationController` spawns **`SurveyProbeUnit`** scenes and manages **idle orbit** (`take_idle_survey_probe_for_base`, `release_survey_probe_unit`) because one spawner/root is convenient.

**Split rule:** Survey-probe pooling may remain a **small “SurveyProbeUnitPool”** helper or stay on the facade — but **investigate FSM, reveal, refund-on-save** stay in `SurveyProbeMissionController`. **Do not** move investigate logic back into scan/mining services or vice versa.

---

## Proposed Future Services (design only)

`AutomationController` remains the **facade** (`class_name` + node on `SystemScene`) until Step 7.

### 1. AutomationUnitSpawner

| Item | Detail |
|------|--------|
| **Possible files** | `scripts/system/automation/automation_unit_spawner.gd` (RefCounted or child Node) |
| **May contain** | `_spawn_unit`, `ensure_starting_units`, `spawn_idle_drone_at_base`, `spawn_idle_mining_ship_at_base`, idle registration helpers, scene preloads |
| **Must not contain** | Scan/mine mission FSM, `_process` mining tick, save/restore, `GameSession.create_scan_mission` |
| **Inputs** | `automation_root`, `spawner`, `primary_base_id`, `UnitCatalog` |
| **Outputs** | `AutomationUnit` instances in idle arrays |
| **Risk** | Low–medium (duplicate start units if called twice) |

### 2. ScanDroneMissionService

| Item | Detail |
|------|--------|
| **Possible files** | `scripts/system/automation/scan_drone_mission_service.gd` |
| **May contain** | `launch_scan_drone` logic, arrive handler, `_complete_scan_mission`, recall/abort scan, orbit-at-target after scan, `scan_drone_target_by_unit_id`, `active_units_by_mission_id` (scan only) |
| **Must not contain** | Mining `_process`, cargo unload, survey probe investigate |
| **Inputs** | Spawner helper, target nodes, `GameSession` scan gates, `AutomationStore` |
| **Outputs** | Updated scan state/resources; orbit support at target |
| **Risk** | Medium (scan reward duplication, `scan_is_progression` special scans) |

### 3. MiningShipMissionService

| Item | Detail |
|------|--------|
| **Possible files** | `scripts/system/automation/mining_ship_mission_service.gd` |
| **May contain** | `launch_mining_ship`, `_process` mining loop, `MiningShipStatus` transitions, `cargo_resources`, extract/unload, `WAITING_FOR_STORAGE`, recall mining |
| **Must not contain** | Scan completion, save JSON builders (initially), audio (until delegated) |
| **Inputs** | Spawner, runtime dict, `GameSession` extract/add resource, deposit candidates |
| **Outputs** | `mining_ship_runtime_by_unit_id` updates; base storage changes |
| **Risk** | **High** (cargo, storage full, remaining_resources) |

### 4. AutomationSaveService

| Item | Detail |
|------|--------|
| **Possible files** | `scripts/system/automation/automation_save_service.gd` |
| **May contain** | `to_save_data` / `apply_save_data` helpers, `_build_scan_job_save_dict`, `_build_mining_job_save_dict`, `_sanitize_*`, `_restore_*`, `_clear_automation_visuals_and_mission_state`, pending restore orchestration |
| **Must not contain** | Gameplay decisions during restore (only replay saved state); no changes to v1 field names |
| **Inputs** | Live dicts + units from facade/services |
| **Outputs** | `docs/save_schema_v1.md`-compatible `runtime` object |
| **Risk** | Medium–high (load regressions) |

### 5. AutomationAudioService

| Item | Detail |
|------|--------|
| **Possible files** | `scripts/system/automation/automation_audio_service.gd` |
| **May contain** | `_play_automation_sfx`, travel SFX, `scan_loop` start/stop, mining tick SFX, `_restart_automation_audio_after_restore` |
| **Must not contain** | Mission state mutations, store writes |
| **Inputs** | `AutomationUnit`, target nodes, runtime status (read-only) |
| **Outputs** | `AudioManager` calls only |
| **Risk** | Low (gameplay), medium (leaked loops) |

### 6. AutomationFacade (remaining `AutomationController`)

| Item | Detail |
|------|--------|
| **Keeps** | `setup`, public API listed below, `signal automation_state_changed`, service wiring, `MiningShipStatus` enum (or re-export for UI) |
| **Delegates** | To services; owns signal connections **at first** to avoid double-connect during migration |
| **Survey probe pool** | Stays on facade or tiny `SurveyProbeUnitPool` until a separate doc says otherwise |

---

## Public API That Must Stay Stable

External call sites **must not change** on early split steps — `automation_controller.gd` remains the entry point.

### SystemScene (`system_scene.gd`)

| API | Usage |
|-----|--------|
| `setup(automation_root, spawner, primary_base_id)` | `_ready` wiring |
| `apply_automation_save_if_pending()` | After load, before `ensure_starting_units` |
| `ensure_starting_units(primary_base_id)` | Initial idle fleet |

### SystemUIController (`system_ui_controller.gd`)

| API | Usage |
|-----|--------|
| `launch_scan_drone(object_id)` | Scan button |
| `launch_mining_ship(object_id)` | Mine button |
| `recall_one_drone_from_target` / `recall_one_mining_ship_from_target` | Recall buttons |
| `has_idle_drone`, `has_available_mining_ship` | Gate buttons |
| `get_orbiting_*`, `get_active_scan_drone_count_for_target`, `get_assigned_mining_ship_count`, `get_mining_bonus_for_target` | Panel info |
| `get_active_*_job_count_for_session_base`, `get_active_job_count_for_base` | Economy panel |
| `spawn_idle_drone_at_base`, `spawn_idle_mining_ship_at_base`, `spawn_idle_survey_probe_at_base` | Production build |
| **`automation_state_changed`** signal | Refresh object info / automation UI |
| **Direct field reads** | `mining_ship_runtime_by_unit_id`, `scan_drone_target_by_unit_id` (mining status line, busy counts) |
| **`AutomationController.MiningShipStatus`** | Compared to runtime `status` int for “Mining” label |

### SurveyProbeMissionController

| API | Usage |
|-----|--------|
| `take_idle_survey_probe_for_base` | Start investigate |
| `return_survey_probe_to_idle_orbit`, `release_survey_probe_unit` | Abort / complete cleanup |
| `ensure_survey_probe_units_for_base` | Refund / idle sync |

### GameSession (save path)

| API | Usage |
|-----|--------|
| `refresh_automation_snapshot_from_scene()` | Calls `to_save_data()` on controller in tree |
| `_find_automation_controller_in_tree()` | Pre-save snapshot |

### Facade persistence API

| API | Usage |
|-----|--------|
| `to_save_data()` | `automation.runtime` in save v1 |
| `apply_save_data(runtime)` | Internal restore |
| `apply_automation_save_if_pending()` | Scene entry |
| `reapply_session_base_unit_upgrade_effects()` | After load / upgrade changes |

**Rule:** New services are **private** to the facade until a deliberate pass updates call sites (not planned in v0.1 split).

---

## Proposed Extraction Order

| Step | Action | Behavior change? |
|------|--------|------------------|
| **1** | **Internal map only** — function region / responsibility doc (this plan + optional comment regions) | **None** |
| **2** | **AutomationAudioService** — move audio helpers; facade forwards | **None** (same AudioManager calls) |
| **3** | **AutomationSaveService** — pure serialization/restore helpers; facade delegates | **None** if byte-compatible |
| **4** | **AutomationUnitSpawner** — spawn + idle orbit setup | **None** |
| **5** | **ScanDroneMissionService** — scan path only; facade keeps `launch_scan_drone` / recall | **None** |
| **6** | **MiningShipMissionService** — last; full test matrix | **None** |
| **7** | Optional facade shrink / remove dead private methods | **None** |

**Do not** start Step 2 (audio) until Step 1 function map exists in repo (audit doc or regions).

---

## What Must Never Be Split Casually

- **`cargo_resources` lifecycle** (mine → cargo dict → unload → base → clear / loop).
- **`UNLOADING` → `WAITING_FOR_STORAGE` → resume unload** when space frees (`GameSession.base_resources_changed` path in mining wait).
- **`extract_resource_amount` then `add_base_resource`** ordering and partial accepts.
- **Scan reward path** — `set_object_scan_state` + `grant_scan_survey_data_reward` only after `complete_automation_mission` + `_complete_scan_mission`.
- **`scan_is_progression == false`** early exit (SFX only, no store progression).
- **`active_units_by_mission_id`** binding through scan arrive → complete → erase.
- **Restore `mission_id` + `scan_reveal_done`** matching store records.
- **Audio loop cleanup** on recall, `_disconnect_unit_signals`, `_clear_automation_visuals_and_mission_state`, scene exit.
- **`system_id` / `primary_base_id` restore guards** (skip entire runtime if mismatch).

---

## Save/Load Constraints

From `docs/save_schema_v1.md` and Save-v2 design:

| Constraint | Detail |
|------------|--------|
| **v1 schema frozen** | `game_session.automation.store` + `automation.runtime` shape unchanged |
| **Runtime keys** | `scan_missions[]`, `mining_missions[]` job dict fields as documented in save schema |
| **Restore order** | `SystemScene`: spawn → `apply_for_system` (discovery) → `apply_automation_save_if_pending` → `ensure_starting_units` → camera |
| **No `save_version` bump** during controller split |
| **No `active_missions`** in this effort |
| **Pre-save** | Survey probe / sensor pulse cancel still in `SaveManager` before snapshot — automation split must not break `to_save_data()` timing |
| **Tests** | Cargo duplication, scan reward duplication, restore skip warnings |

`GameSession.refresh_automation_snapshot_from_scene()` is triggered from `_request_automation_state_changed` — facade must keep this side effect or document an explicit move.

---

## Risk Matrix

| Risk | Severity | Mitigation |
|------|----------|------------|
| Duplicate units after split | High | Single spawner service; idempotent `ensure_starting_units` |
| Lost mining cargo | High | No logic change in Step 6 without full mining test matrix |
| Double base unload | High | Keep `_unload_greedy_into_base_until_full` atomic |
| Double scan Survey Data reward | High | Preserve `complete_automation_mission` → `_complete_scan_mission` order |
| Hanging `scan_loop` | Medium | Audio service must call same `stop_world_loop_optional` on all exit paths |
| Restore skipped (system/base mismatch) | Medium | Do not change guard strings/fields in save service |
| Recall clears wrong mission | Medium | Keep target_id matching rules in one service per type |
| Stuck `WAITING_FOR_STORAGE` | Medium | Keep `base_resources_changed` subscription path intact |
| Idle units vanish | Medium | Spawner + register idle unchanged |
| UI shows wrong status | Medium | Keep public dicts or add accessors only after UI migration |
| Survey probe pool regression | Medium | Do not fold probe pool into mining service |
| Split breaks save snapshot timing | Low | Run save-during-mine tests after Step 3 |

---

## Test Matrix Before Any Implementation

Manual / scripted checks (same as save + automation smoke):

- [ ] New Game — idle drones, ships, probes at primary base  
- [ ] Scan — launch → arrive → complete → orbit at target  
- [ ] Scan reward granted **once** (store + Survey Data)  
- [ ] Scan recall — unit returns, audio stops, assignment cleared  
- [ ] Rescan / progression / special scan (`scan_is_progression false`)  
- [ ] Mining — launch → arrive → MINING tick  
- [ ] Mining reduces `remaining_resources` in store  
- [ ] Return → unload → base storage increases  
- [ ] Storage full → `WAITING_FOR_STORAGE` → add space → continues  
- [ ] Mining recall with cargo  
- [ ] Save during scan (outbound / WORKING / return)  
- [ ] Save during mining (outbound / MINING / cargo / UNLOADING / WAITING)  
- [ ] Load — jobs restored; no duplicate units  
- [ ] Scene leave / re-enter — no orphan loops  
- [ ] No duplicate rewards / no resource loss  
- [ ] `grep tooltip_text` → **0** in `*.gd` / `*.tscn` / `*.tres`  

---

## Do Not Implement Yet

- No file splits, no new autoloads, no scene changes.
- No changes to `automation_controller.gd` logic (including audio extraction) until function map is done.
- No Save-v2, no mission rule changes.

---

## Recommended First Implementation Prompt

Use **after** this design is accepted — **documentation / map only**, no gameplay changes:

```
Audit scripts/system/controller/automation_controller.gd and produce docs/architecture/automation_controller_function_map_v0_1.md:
- Line ranges per responsibility (scan, mining, spawn, save, restore, audio, survey probe pool, UI helpers).
- List of public methods and which external scripts call them.
- Optional: add # region comments in automation_controller.gd matching the map (comments only, no logic changes).
Do not extract AutomationAudioService yet.
```

---

## Acceptance (this document)

1. Only `docs/architecture/automation_controller_split_plan_v0_1.md` created.  
2. No code/scene/data changes.  
3. Current responsibilities documented from real symbols.  
4. Future services + extraction order defined.  
5. Stable public API and call sites listed.  
6. Save/load constraints tied to `save_schema_v1.md`.  
7. Test matrix + single next-step prompt included.
