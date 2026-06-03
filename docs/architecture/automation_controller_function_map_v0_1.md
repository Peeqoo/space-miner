# AutomationController Function Map v0.1

**Status:** Read-only audit — **no code changed**.  
**Source file:** `scripts/system/controller/automation_controller.gd` (lines **1–3037** as of this audit).  
**Related:** `docs/architecture/automation_controller_split_plan_v0_1.md`, `docs/save_schema_v1.md`.

---

## Purpose

This map is **preparation for a future controller split** (`automation_controller_split_plan_v0_1.md`). It records:

- **Line ranges** and function groupings from the real file (not idealized modules).
- **Who calls** each public API.
- **State** read/written per area.
- **Extraction targets** and risks — **no implementation** in this phase.

---

## File Overview

| Item | Value |
|------|--------|
| **Path** | `scripts/system/controller/automation_controller.gd` |
| **`class_name`** | `AutomationController` |
| **`extends`** | `Node` |
| **Line count** | **3037** |
| **Scene** | Child of `SystemScene` → `$AutomationController` |

### Signals

| Signal | Line | Emit via |
|--------|------|----------|
| `automation_state_changed` | 6 | `_emit_automation_state_changed_deferred` (2876–2889) after `_request_automation_state_changed` |

### Enums / constants (public impact)

| Name | Lines | Notes |
|------|-------|--------|
| `MiningShipStatus` | 41–47 | `TO_TARGET`, `MINING`, `TO_BASE`, `UNLOADING`, `WAITING_FOR_STORAGE` (0–4). **SystemUIController** compares runtime `status` to `MINING`. |
| `DRONE_SCENE`, `MINING_SHIP_SCENE`, `SURVEY_PROBE_SCENE` | 8–10 | PackedScene preloads |
| Unit/balance fallbacks | 16–23 | Used if `UnitCatalog` missing |

### Core state (instance)

| Field | Lines | Role |
|-------|-------|------|
| `automation_root` | 25 | Parent for spawned units |
| `spawner` | 26 | `SystemSpawner` — resolve body nodes by id |
| `active_units_by_mission_id` | 28 | Scan: `mission_id` → `AutomationUnit` until arrive completes store mission |
| `idle_drones` | 29 | Available scan drones at base orbit |
| `idle_mining_ships` | 30 | Available mining ships at base orbit |
| `idle_survey_probes` | 31 | Idle `SurveyProbeUnit` visuals |
| `survey_probe_busy_unit_ids` | 34 | `instance_id → true` while probe on investigate |
| `starting_units_initialized` | 36 | `ensure_starting_units` runs once per controller lifetime |
| `_session_primary_base_body_id` | 39 | Scene primary base; save restore guard |
| `mining_ship_runtime_by_unit_id` | 49 | `instance_id` → mining FSM `Dictionary` |
| `scan_drone_target_by_unit_id` | 53 | `instance_id` → assigned `target_id` |
| `_automation_state_emit_scheduled` | 56 | Coalesce UI refresh |
| `_unit_catalog` | 58 | Lazy `UnitCatalog` |

**Not on this node:** pending save runtime lives on **`GameSession._automation_runtime_pending`** (consumed by `apply_automation_save_if_pending`).

---

## Public API Map

| Method / signal / field | External caller(s) | Purpose | Stability | Risk |
|------------------------|-------------------|---------|-----------|------|
| **`setup(root, spawner, primary_base_id)`** | `system_scene.gd` | Wire root/spawner/base; connect `base_resources_changed`; `set_process(true)` | **Frozen** | Wrong base id breaks all launches |
| **`ensure_starting_units(primary_base_id)`** | `system_scene.gd` | Once: sync idle drone/ship/probe counts with `BaseStore` | **Frozen** | Duplicate spawns if flag cleared |
| **`launch_scan_drone(target_id)`** | `system_ui_controller.gd` | Start scan mission | **Frozen** | Gate/store/reward path |
| **`launch_mining_ship(target_id)`** | `system_ui_controller.gd` | Start mining mission | **Frozen** | Cargo FSM |
| **`recall_one_drone_from_target`** | `system_ui_controller.gd` | Recall one drone assigned to target | **Frozen** | Audio + assignment cleanup |
| **`recall_one_mining_ship_from_target`** | `system_ui_controller.gd` | Recall one miner on target | **Frozen** | Cargo + `WAITING_FOR_STORAGE` |
| **`to_save_data()`** | `GameSession.refresh_automation_snapshot_from_scene()` | `automation.runtime` v1 payload | **Frozen** | Schema regression |
| **`apply_automation_save_if_pending()`** | `system_scene.gd` | Load pending runtime from `GameSession` | **Frozen** | Restore order |
| **`has_idle_drone()`** | `system_ui_controller.gd` | Scan button gate | **Frozen** | |
| **`has_available_mining_ship()`** | `system_ui_controller.gd` | Mine button gate | **Frozen** | |
| **`spawn_idle_drone_at_base`** | `system_ui_controller.gd` (production) | Build drone unit | **Frozen** | Fleet count vs visuals |
| **`spawn_idle_mining_ship_at_base`** | `system_ui_controller.gd` | Build mining ship | **Frozen** | Same |
| **`spawn_idle_survey_probe_at_base`** | `system_ui_controller.gd` | Build survey probe visual | **Frozen** | Same |
| **`take_idle_survey_probe_for_base`** | `survey_probe_mission_controller.gd` | Borrow probe for investigate | **Frozen** | Must not mix with scan launch |
| **`return_survey_probe_to_idle_orbit`** | `survey_probe_mission_controller.gd` | Return probe after abort path | **Frozen** | |
| **`release_survey_probe_unit`** | `survey_probe_mission_controller.gd` | Free probe from busy set | **Frozen** | |
| **`ensure_survey_probe_units_for_base`** | `survey_probe_mission_controller.gd` | Sync idle probes after refund/complete | **Frozen** | |
| **`automation_state_changed`** | `system_ui_controller.gd` | Refresh automation UI / object info | **Frozen** | Also triggers GameSession snapshot refresh |
| **`mining_ship_runtime_by_unit_id`** | `system_ui_controller.gd` (direct read) | Mining status label, busy counts | **Frozen** | Couples UI to internal dict |
| **`scan_drone_target_by_unit_id`** | `system_ui_controller.gd` (direct read) | Orbit/support UI, busy counts | **Frozen** | Same |
| **`AutomationController.MiningShipStatus`** | `system_ui_controller.gd` | Enum compare for “Mining” text | **Frozen** | Moving enum breaks UI |
| `get_orbiting_drone_count` | `system_ui_controller.gd` | Panel copy | High | |
| `get_orbiting_mining_ship_count` | `system_ui_controller.gd` | Panel copy | High | |
| `get_active_scan_drone_count_for_target` | `system_ui_controller.gd` | Panel / gates | High | |
| `get_assigned_mining_ship_count` | `system_ui_controller.gd` | Panel copy | High | |
| `get_mining_bonus_for_target` | `system_ui_controller.gd` | Yield bonus display | High | |
| `get_active_job_count_for_base` | `system_ui_controller.gd` | Top HUD job count | High | Session base only |
| `get_active_scan_job_count_for_session_base` | `system_ui_controller.gd` | Economy panel | High | |
| `get_active_mining_job_count_for_session_base` | `system_ui_controller.gd` | Economy panel | High | |
| `reapply_session_base_unit_upgrade_effects` | Internal + restore (2355, 2378) | Reapply upgrade multipliers to live units | Medium | Must run after load |
| `apply_save_data(runtime)` | Internal (`_restore_automation_runtime_when_ready`) | Restore jobs | Medium | Not direct external |
| `has_mining_candidates_for_target` | Internal (`launch_mining_ship`, `_process`) | Gate mining / loop target | Medium | |
| `get_idle_survey_probe_count` | Internal only | Probe pool trim | Low | |
| `has_active_scan_drone_support_for_target` | Internal (`get_mining_bonus_for_target`) | Support drone bonus | Medium | |
| `automation_root`, `spawner` | Scene wiring | References | Medium | |

**Indirect:** `GameSession._find_automation_controller_in_tree()` for save snapshot — calls `to_save_data()` if in tree.

**Not called externally:** `has_idle_mining_ship`, `get_active_mining_ship_count_for_target` (alias), `has_active_scan_drone_support_count_for_target` wrappers — grep shows UI uses listed methods only.

---

## Function Regions

Regions are **logical**; some helpers are physically distant in the file. Line ranges are **inclusive** approximations from the current file.

### 1. Setup / references / catalog

| | |
|--|--|
| **Lines** | **1–221** |
| **Functions** | `_ensure_unit_catalog`, `_get_*_base` (scan/mining durations, rates, capacity), `_get_scan_work_duration_for_base`, `_get_mining_rate_for_base`, `_get_mining_cargo_capacity_for_base`, `_apply_scan_drone_upgrade_stats_to_unit`, `_apply_mining_runtime_upgrade_stats`, `reapply_session_base_unit_upgrade_effects`, `_get_session_base_id`, `_runtime_base_id_with_session_fallback`, **`setup`** |
| **State** | `_unit_catalog`, `_session_primary_base_body_id`, unit `work_duration`, runtime upgrade fields |
| **Dependencies** | `UnitCatalog`, `GameSession` upgrade multipliers, `BaseStore.BASE_EARTH` fallback |
| **Future service** | Shared by all services; stays on **facade** initially |
| **Risk** | Low alone; wrong duration breaks scan/mining UX |

### 2. Unit spawning / idle orbit

| | |
|--|--|
| **Lines** | **223–536**, **1057–1067**, **1741–1767**, **1882–1925**, **2792–2827** |
| **Functions** | `ensure_starting_units`, `spawn_idle_*_at_base`, `_spawn_unit`, `_register_idle_drone` / `_register_idle_mining_ship`, `_get_idle_drone`, `_get_idle_mining_ship`, `_ensure_returned_to_base_connected`, `_on_automation_unit_returned_to_base`, `_on_scan_drone_return_dock_clear_assignment`, `_fallback_scan_job_to_idle`, `_fallback_mining_job_to_idle` |
| **State** | `idle_drones`, `idle_mining_ships`, `starting_units_initialized`, `scan_drone_target_by_unit_id` (clear on dock) |
| **Dependencies** | `SystemSpawner`, `GameSession` fleet counts, `AutomationUnit.start_orbiting_base` |
| **Future service** | **AutomationUnitSpawner** |
| **Risk** | Medium — duplicate idle units |

### 3. ScanDrone launch / travel / complete

| | |
|--|--|
| **Lines** | **537–607**, **744–847**, **1070–1198**, **2947–2978** |
| **Functions** | `launch_scan_drone`, `get_active_scan_drone_count_for_target`, `get_orbiting_drone_count`, `has_active_scan_drone_support_*`, `_is_scan_drone_providing_mining_support_at_target`, `_on_scan_drone_arrived_at_target`, **`_complete_scan_mission`**, `_scan_drone_start_outbound`, `_scan_drone_recall_to_base`, `_scan_drone_return_to_base_orbit` |
| **State** | `active_units_by_mission_id`, `scan_drone_target_by_unit_id`, `idle_drones` (consume/release) |
| **Dependencies** | `GameSession.can_scan_object`, `create_scan_mission`, `complete_automation_mission`, `set_object_scan_state`, `grant_scan_survey_data_reward`, `ensure_object_resources_initialized`, `AutomationStore` mission fields |
| **Future service** | **ScanDroneMissionService** |
| **Risk** | **High** — double scan reward; `scan_is_progression` false path |

### 4. MiningShip launch / FSM / cargo / unload

| | |
|--|--|
| **Lines** | **610–730**, **1028–1055**, **1107–1136**, **1208–1625**, **1627–1717**, **2941–2962**, **2981–2986** |
| **Functions** | `launch_mining_ship`, `has_mining_candidates_for_target`, `get_mining_bonus_for_target`, `get_assigned_mining_ship_count`, `_on_mining_ship_arrived_at_target`, **`_process`** (mining FSM), `_on_mining_ship_returned_to_base`, `_mining_ship_enter_waiting_for_storage`, `_mining_ship_start_outbound`, `_mining_ship_recall_to_base` |
| **State** | `mining_ship_runtime_by_unit_id` (status, `cargo_resources`, timers, …) |
| **Dependencies** | `GameSession.extract_resource_amount`, `add_base_resource`, `get_base_storage_free`, `ensure_mining_resources_for_object`, `ObjectScanStore` remaining amounts, `_list_mining_weighted_candidates` |
| **Future service** | **MiningShipMissionService** (last) |
| **Risk** | **Highest** — cargo loss/dup; `WAITING_FOR_STORAGE` |

### 5. Recall / abort / cleanup

| | |
|--|--|
| **Lines** | **872–1026**, **936–951**, **1200–1206**, **1719–1739**, **1965–1993** |
| **Functions** | `recall_one_drone_from_target`, `recall_one_mining_ship_from_target`, `_abort_scan_mission_for_unit`, `_cleanup_unit`, `_release_mining_ship_runtime`, `_disconnect_unit_signals` |
| **State** | Clears assignments, runtime dicts, stops audio (via disconnect) |
| **Dependencies** | `AutomationUnit.recall_to_base`, `return_to_base_orbit` |
| **Future service** | Split with scan/mining services; shared **disconnect** helper |
| **Risk** | High — wrong unit recalled; leaked runtime |

### 6. SurveyProbe unit pool

| | |
|--|--|
| **Lines** | **405–536**, **1769–1879** |
| **Functions** | `spawn_idle_survey_probe_at_base`, `ensure_survey_probe_units_for_base`, `get_idle_survey_probe_count`, `take_idle_survey_probe_for_base`, `return_survey_probe_to_idle_orbit`, `release_survey_probe_unit`, `_on_base_resources_changed_survey_probes`, `_spawn_survey_probe_unit`, `_prune_idle_survey_probes`, `_count_idle_survey_probes_at_home`, `_trim_excess_idle_survey_probes`, `_take_idle_survey_probe_from_list`, `_register_idle_survey_probe` |
| **State** | `idle_survey_probes`, `survey_probe_busy_unit_ids` |
| **Dependencies** | `GameSession` survey probe counts; **`SurveyProbeMissionController`** only mission caller |
| **Future service** | Optional **SurveyProbeUnitPool** (not ScanDrone/MiningShip service) |
| **Risk** | Medium — investigate vs idle desync |

### 7. Audio helpers / world loops

| | |
|--|--|
| **Lines** | **2830–3036** (plus call sites throughout scan/mining/recall) |
| **Functions** | `_restart_automation_audio_after_restore`, `_request_automation_state_changed`, `_emit_automation_state_changed_deferred`, `_play_automation_sfx`, `_play_unit_travel_sfx`, `_play_scan_drone_launch/arrive`, `_play_mining_ship_launch/arrive`, `_play_mining_resource_tick_sfx`, `_begin_scan_drone_return_travel`, `_begin_mining_ship_return_travel`, `_start_scan_orbit_audio`, `_stop_scan_orbit_audio`, `_scan_orbit_loop_id`, `_audio_source_node`, `_audio_node_for_base` |
| **State** | None persisted; loop ids keyed by unit instance |
| **Dependencies** | `AudioManager` (`play_world_sfx_*`, `play_world_loop_optional`, `stop_world_loop_optional`) |
| **Future service** | **AutomationAudioService** |
| **Risk** | Medium — hanging `scan_loop` |

### 8. Save snapshot builders

| | |
|--|--|
| **Lines** | **2301–2631** |
| **Functions** | **`to_save_data`**, `_scan_missions_to_save_array`, `_mining_missions_to_save_array`, `_build_scan_job_save_dict`, `_build_mining_job_save_dict`, `_global_position_to_save_dict`, `_sanitize_dictionary_for_save`, `_sanitize_value_for_save` |
| **State** | Reads live dicts + `instance_from_id` |
| **Dependencies** | `docs/save_schema_v1.md` field shapes |
| **Future service** | **AutomationSaveService** (write path first) |
| **Risk** | Medium — `scan_reveal_done` wrong |

### 9. Restore / pending automation

| | |
|--|--|
| **Lines** | **2310–2790** |
| **Functions** | **`apply_automation_save_if_pending`**, **`apply_save_data`**, `_restore_automation_runtime_when_ready`, `_expected_automation_job_count_in_runtime`, `_count_restored_automation_jobs`, `_clear_automation_visuals_and_mission_state`, **`_restore_scan_mission`**, **`_restore_mining_mission`**, `_restart_automation_audio_after_restore` (entry) |
| **State** | Rebuilds all mission dicts; may `GameSession.automation.restore_mission_record` |
| **Dependencies** | `GameSession.take_automation_runtime_pending`, system/base id guards |
| **Future service** | **AutomationSaveService** (read path) |
| **Risk** | **High** — restore skip; duplicate units |

### 10. UI helper getters

| | |
|--|--|
| **Lines** | **329–347**, **732–870**, **1028–1055** |
| **Functions** | `get_active_job_count_for_base`, `get_active_scan_job_count_for_session_base`, `get_active_mining_job_count_for_session_base`, `has_idle_drone`, `has_idle_mining_ship`, `has_available_mining_ship`, orbit/count/bonus getters |
| **State** | Read-only on dicts / idle arrays |
| **Dependencies** | `_session_primary_base_body_id` filter |
| **Future service** | Stay on **facade** or thin query object |
| **Risk** | Low logic; high if dict shape changes |

### 11. Internal utilities / sanitizers

| | |
|--|--|
| **Lines** | **1995–2298**, **2102–2150**, **2574–2584** |
| **Functions** | `_get_definition_from_target_node`, `_get_visible_resource_entries_for_scan_state`, `_get_resource_entries_for_tier`, `_can_unlocked_scan_layer_see_resource_tier`, `_get_object_id_from_node`, **`_get_target_node`**, `_cargo_resources_total`, **`_unload_greedy_into_base_until_full`**, `_merge_legacy_cargo_into_dictionary`, `_resource_weight_from_scanned_entry`, `_append_scanned_entries_from_method`, `_get_allowed_scanned_entries_for_object_scan`, `_filter_scanned_entries_for_mining_layer`, **`_list_mining_weighted_candidates`**, `_global_position_from_save_dict` |
| **State** | Mutates cargo via unload; read-only for scan resource lists |
| **Dependencies** | `SystemSpawner`, `ScannedResourceEntry`, `GameSession` scan/mining APIs |
| **Future service** | Mining service owns cargo/unload; scan service owns resource visibility helpers |
| **Risk** | High when moved with mining |

### Complete function index (line → name)

| Line | Function |
|------|----------|
| 61 | `_ensure_unit_catalog` |
| 68–122 | `_get_*` catalog / upgrade helpers |
| 139–167 | `_apply_*_upgrade_stats` |
| 169 | `reapply_session_base_unit_upgrade_effects` |
| 194–207 | `_get_session_base_id`, `_runtime_base_id_with_session_fallback` |
| 210 | `setup` |
| 223 | `ensure_starting_units` |
| 329–347 | `get_active_*_job_count*` |
| 349–527 | `spawn_idle_*`, survey probe public pool API |
| 537 | `launch_scan_drone` |
| 610 | `launch_mining_ship` |
| 686 | `has_mining_candidates_for_target` |
| 732–870 | idle / orbit / recall **public** getters + `recall_one_drone` |
| 810 | `_is_scan_drone_providing_mining_support_at_target` |
| 872–1026 | `recall_one_*` |
| 936 | `_abort_scan_mission_for_unit` |
| 1057 | `_spawn_unit` |
| 1070 | `_on_scan_drone_arrived_at_target` |
| 1107 | `_on_mining_ship_arrived_at_target` |
| 1138 | `_complete_scan_mission` |
| 1200 | `_cleanup_unit` |
| 1208 | `_process` |
| 1627–1719 | mining return / waiting / release runtime |
| 1741–1879 | register idle / survey probe internals |
| 1882–1963 | idle getters / signals / disconnect |
| 1995–2298 | target + scan/mining resource utilities |
| 2102–2150 | cargo total / unload greedy |
| 2301–2631 | save + restore |
| 2792–2827 | restore fallbacks to idle |
| 2830–3036 | audio + state changed |

---

## State Ownership Map

| Field | Type | Written by | Read by | Save involvement | Risk |
|-------|------|------------|---------|------------------|------|
| `scan_drone_target_by_unit_id` | `Dictionary` | `launch_scan_drone`, restore, recall, dock clear, `_clear_automation_visuals` | UI, save `_scan_missions_to_save_array`, audio restart | **`scan_missions[]`** in runtime | Wrong target; dup assignment |
| `mining_ship_runtime_by_unit_id` | `Dictionary` | `launch_mining_ship`, `_process`, recall, restore, `_release_mining_ship_runtime` | UI, `_mining_missions_to_save_array`, `_process` | **`mining_missions[]`** | Cargo dup/loss |
| `active_units_by_mission_id` | `Dictionary` | `launch_scan_drone`, arrive handler, restore, `_cleanup_unit` | Scan arrive, save `mission_id` | Indirect via job `mission_id` | Orphan mission in store |
| `idle_drones` | `Array[AutomationUnit]` | `ensure_starting_units`, spawn_idle, register, launch (remove), recall | `launch_scan_drone`, `_get_idle_drone` | Not saved (re-sync on ensure) | Dup drones |
| `idle_mining_ships` | `Array[AutomationUnit]` | Same pattern for ships | `launch_mining_ship`, `_get_idle_mining_ship` | Not saved | Dup ships |
| `idle_survey_probes` | `Array[SurveyProbeUnit]` | Survey pool helpers | `take_idle_survey_probe_for_base` | Not saved | Investigate vs idle |
| `survey_probe_busy_unit_ids` | `Dictionary` | `take_idle_*`, `release_*` | `ensure_starting_units` probe math | Not saved | Double borrow |
| `_session_primary_base_body_id` | `String` | `setup`, `ensure_starting_units`, restore may set from save | Save guards, job counts, launches | **`primary_base_id`** in runtime | Restore skip |
| `starting_units_initialized` | `bool` | `ensure_starting_units` | Blocks re-spawn | Not saved | Reload scene edge cases |
| **`GameSession._automation_runtime_pending`** | `Dictionary` | `GameSession.apply_save_data` | `apply_automation_save_if_pending` | Full **`automation.runtime`** blob | Not controller field but critical |
| `automation_root` / `spawner` | refs | `setup` | `_spawn_unit`, `_get_target_node` | N/A | Null spawn |

**`AutomationStore.missions`:** written via `GameSession.create_scan_mission` / `complete_automation_mission`; saved in `automation.store`, not in controller fields.

---

## Extraction Candidates

### AutomationAudioService

| | |
|--|--|
| **Could move** | Lines **2830–3036** + thin wrappers at scan/mining launch/recall (2947–2986, 1084, 1102, etc.) |
| **Must not move** | Any store write, `_process`, cargo |
| **First extract method** | Copy helpers to `automation_audio_service.gd`; facade delegates one-liners; **zero** logic change |
| **Test after** | Recall stops `scan_loop`; restore restarts loop; mining tick SFX |

### AutomationSaveService

| | |
|--|--|
| **Could move** | **2301–2631**, **2310–2790**, sanitizers **2570–2631**, **2587–2629** |
| **Must not move** | Gameplay decisions during `_process`; changing job dict keys |
| **First extract method** | Move `_build_*_job_save_dict` + `_sanitize_*` only; controller still calls restore |
| **Test after** | Full save matrix in split plan; compare JSON before/after |

### AutomationUnitSpawner

| | |
|--|--|
| **Could move** | `ensure_starting_units`, `spawn_idle_*`, `_spawn_unit`, `_register_idle_*`, `_get_idle_*`, fallbacks **2792–2827** |
| **Must not move** | Mission FSM, `create_scan_mission` |
| **First extract method** | `_spawn_unit` + `spawn_idle_drone_at_base` only |
| **Test after** | New game unit counts; production build spawn |

### ScanDroneMissionService

| | |
|--|--|
| **Could move** | **537–607**, **1070–1198**, **1138–1198**, recall drone **872–935**, scan travel **2947–2978**, support getters **744–847** |
| **Must not move** | Mining `_process`, survey probe pool |
| **First extract method** | Private service owned by facade; `launch_scan_drone` remains on facade |
| **Test after** | Scan complete once; rescan; recall; save during scan |

### MiningShipMissionService

| | |
|--|--|
| **Could move** | **610–684**, **1208–1625**, mining handlers **1107–1717**, utilities **2102–2298**, recall **953–1026** |
| **Must not move** | Scan complete path; save builders until stable |
| **First extract method** | **Do not extract first** — highest risk |
| **Test after** | Full mining + storage-full matrix |

### SurveyProbeUnitPool (optional)

| | |
|--|--|
| **Could move** | **405–536**, **1769–1879** |
| **Must not move** | `SurveyProbeMissionController` investigate FSM |
| **First extract method** | Optional parallel to audio; keep public method names on facade |
| **Test after** | Investigate start/abort/refund; idle probe count |

---

## Dangerous Couplings

1. **`_complete_scan_mission` + `scan_is_progression`** — non-progression scans skip store updates but may still play SFX (1153–1156).
2. **`_process` + `extract_resource_amount` + `cargo_resources` + `add_base_resource`** — must stay one transactional story per tick/unload slice.
3. **`WAITING_FOR_STORAGE` + `GameSession.base_resources_changed`** — probe resume path in `_process` (1569+).
4. **Save `mission_id` / `scan_reveal_done` + restore `restore_mission_record`** — must match `AutomationStore` (2676–2687).
5. **Audio `scan_loop` + `_stop_scan_orbit_audio`** — required on recall, disconnect, clear visuals, scan complete miss path.
6. **`SystemUIController` reads `mining_ship_runtime_by_unit_id` / `scan_drone_target_by_unit_id` directly** — facade cannot drop public fields without UI pass.
7. **Survey probe pool in same class as mining** — easy to accidentally call wrong idle getter.
8. **`_request_automation_state_changed` → `GameSession.refresh_automation_snapshot_from_scene`** — side effect on every automation UI refresh.

---

## Recommended First Code Extraction

**Recommendation: `AutomationAudioService` first** (not Save, not Mining).

| Option | Gameplay risk | Schema risk | Rationale |
|--------|---------------|-------------|-----------|
| **Audio** | **Lowest** | None | Pure `AudioManager` delegation; no dict/store mutation |
| Save helpers | Medium | **High** | Must byte-match `docs/save_schema_v1.md` |
| Mining service | **Highest** | Medium | Cargo + unload + remaining_resources |
| Scan service | Medium | Medium | Reward duplication risk |

**Do not implement** until this map is reviewed. Optional next doc-only step: add `# region` comments in `automation_controller.gd` matching sections above (comments only).

---

## Test Checklist Before Any Extraction

- [ ] Scan launch / arrive / complete — reward **once**
- [ ] Scan recall — assignment cleared, audio stopped
- [ ] Rescan / special scan (`scan_is_progression false`)
- [ ] Mining extract → `remaining_resources` decreases
- [ ] Return / unload → base storage increases
- [ ] Storage full → `WAITING_FOR_STORAGE` → space frees → continues
- [ ] Mining recall with cargo
- [ ] Save/load during scan (outbound / WORKING / return)
- [ ] Save/load during mining (all `MiningShipStatus` phases)
- [ ] SurveyProbe investigate still works (pool borrow/release)
- [ ] Audio loops stop on recall / scene change
- [ ] No duplicate units visible
- [ ] No resource loss / duplication
- [ ] `grep tooltip_text` → **0** in `*.gd` / `*.tscn` / `*.tres`

---

## Acceptance

1. Only `docs/architecture/automation_controller_function_map_v0_1.md` created.  
2. No code changes.  
3. Line ranges and groups from `automation_controller.gd` (3037 lines).  
4. Public API and external callers documented.  
5. No split implemented.  
6. First code step **recommended only** (AudioService after map review).
