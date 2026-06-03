# AutomationSaveService Extraction Plan v0.1

**Status:** Design only — **not implemented**.  
**Engine:** Godot 4.6.1.  
**Prerequisite:** `AutomationAudioService` extracted (Phase 3.6 Step 2, smoke test PASS).  
**Related:** `docs/save_schema_v1.md`, `docs/architecture/automation_controller_split_plan_v0_1.md`, `docs/architecture/automation_controller_function_map_v0_1.md`, `docs/architecture/save_v2_mission_continuity_design_v0_1.md`.

---

## Purpose

`AutomationController` still owns **save snapshot** and **restore** (~lines **2303–2792**, plus fallbacks **2794–2827**) in a single node alongside mission gameplay. Extracting an **`AutomationSaveService`** later would:

- Isolate **JSON shape risk** from scan/mining FSM edits.
- Make **v1 schema regression** visible in one module.
- Prepare for Save-v2 **without** implementing Save-v2 now.

**Why not split save code immediately**

- Restore **spawns units**, mutates `active_units_by_mission_id`, `scan_drone_target_by_unit_id`, `mining_ship_runtime_by_unit_id`, and may call `GameSession.automation.restore_mission_record` — same failure class as cargo duplication and duplicate units.
- **Audio** extraction was low risk; save is **medium–high** (schema + behavior).
- **Byte-/schema-compatible** extraction requires a **write-path-first** rollout and explicit before/after JSON comparison.

**Goal of this plan**

- Define **exact v1 `automation.runtime` fields** that must not change.
- Split extraction into **Phase A (write only)** and **Phase B (restore later)**.
- Specify inputs/outputs, tests, and compatibility checks.
- **Save-v1 stays active** (`SaveManager.SAVE_VERSION == 1`). **No Save-v2 `active_missions`**. **No `save_version` bump.**

---

## Current Save/Restore Ownership

Source: `scripts/system/controller/automation_controller.gd` (line ranges from audit; file may shift slightly after audio extract).

| Function | Owner | Lines (approx) | Reads state | Writes state | Save schema impact | Risk |
|----------|--------|----------------|-------------|--------------|-------------------|------|
| **`to_save_data()`** | `AutomationController` | 2303–2309 | `GameSession.current_system_id`, `_session_primary_base_body_id`, live units via helpers | None (returns dict) | **`automation.runtime` root** | High — top-level shape |
| **`_scan_missions_to_save_array()`** | Controller | 2422–2484 | `scan_drone_target_by_unit_id`, `active_units_by_mission_id`, `instance_from_id` | None | **`scan_missions[]`** | High — job list completeness |
| **`_mining_missions_to_save_array()`** | Controller | 2487–2507 | `mining_ship_runtime_by_unit_id`, `instance_from_id` | None | **`mining_missions[]`** | High — cargo in jobs |
| **`_build_scan_job_save_dict()`** | Controller | 2510–2549 | Unit motion, `mission_id`, `scan_reveal_done` logic | None | **Per scan job keys** | **Critical** — `scan_reveal_done` |
| **`_build_mining_job_save_dict()`** | Controller | 2552–2569 | Runtime dict + unit fields | None | **Per mining job keys** | **Critical** — sanitizer output |
| **`_sanitize_dictionary_for_save()`** | Controller | 2589–2600 | Any dict | None | Mining job subset | High — drops non-JSON types |
| **`_sanitize_value_for_save()`** | Controller | 2603–2632 | Variant tree | None | Nested values | High — `null` drops keys |
| **`_global_position_to_save_dict()`** | Controller | 2572–2573 | `Vector2` | None | `global_position` | Low |
| **`_global_position_from_save_dict()`** | Controller | 2576–2586 | Job dict | None | (restore read) | Medium — restore only |
| **`apply_automation_save_if_pending()`** | Controller | 2312–2318 | `GameSession` pending | Consumes pending; awaits restore | None directly | High — load entry |
| **`apply_save_data(runtime)`** | Controller | 2321–2358 | Saved dict, guards | All mission dicts, units, signals | Restore applies v1 jobs | **Highest** |
| **`_restore_automation_runtime_when_ready()`** | Controller | 2361–2380 | Pending runtime | Clear + double retry restore | None | **Highest** — duplicate restore |
| **`_expected_automation_job_count_in_runtime()`** | Controller | 2383–2395 | Runtime arrays | None | None | Medium |
| **`_count_restored_automation_jobs()`** | Controller | 2398–2399 | Dict sizes | None | None | Medium |
| **`_clear_automation_visuals_and_mission_state()`** | Controller | 2402–2419 | `automation_root` children | Clears dicts, frees units, stops audio | N/A | High — teardown order |
| **`_restore_scan_mission()`** | Controller | 2635–2707 | Job dict, spawner | Spawns drone, dicts, store, signals | Rebuilds live state from job | **Highest** |
| **`_restore_mining_mission()`** | Controller | 2710–2791 | Job dict, spawner | Spawns ship, runtime dict | Cargo + status | **Highest** |
| **`_fallback_scan_job_to_idle()`** | Controller | 2794–2810 | spawner | `idle_drones` | None | Medium |
| **`_fallback_mining_job_to_idle()`** | Controller | 2813–2827 | spawner | `idle_mining_ships` | None | Medium |

**Upstream / downstream (not moved in Phase A)**

| Piece | Owner | Role |
|-------|--------|------|
| `GameSession.refresh_automation_snapshot_from_scene()` | `game_session.gd` | Calls `AutomationController.to_save_data()` |
| `GameSession._build_automation_save_payload()` | `game_session.gd` | `{ store, runtime }` |
| `GameSession._apply_automation_from_save_data()` | `game_session.gd` | Sets `_automation_runtime_pending` |
| `SaveManager.build_save_data()` | `save_manager.gd` | Pre-save hooks, then session save |
| `SystemScene._finish_initial_setup()` | `system_scene.gd` | `apply_automation_save_if_pending()` |

---

## Save-v1 Schema That Must Stay Identical

Authoritative reference: **`docs/save_schema_v1.md`**.  
On disk: `game_session.automation.runtime` = return value of `AutomationController.to_save_data()`.

### `automation.runtime` (root)

| Field | JSON type | Source in code | Must not change |
|-------|-----------|----------------|-----------------|
| `system_id` | string | `GameSession.current_system_id` | Name, type |
| `primary_base_id` | string | `_session_primary_base_body_id` | Name, type |
| `scan_missions` | array | `_scan_missions_to_save_array()` | Name, type, element shape |
| `mining_missions` | array | `_mining_missions_to_save_array()` | Name, type, element shape |

**Out of scope for this extract:** `automation.store` (`AutomationStore.to_save_data()`), `bases`, `object_scans`, colonization, camera — unchanged.

### `scan_missions[]` entry (exact keys from `_build_scan_job_save_dict`)

| Field | JSON type | Notes |
|-------|-----------|--------|
| `target_id` | string | |
| `base_id` | string | `_get_session_base_id()` at save time |
| `mission_id` | number (int) | `0` if no store mission |
| `orbit_anchor_id` | string | Base or orbit body id |
| `unit_state` | number (int) | `AutomationUnit.State` |
| `work_timer` | number | float serialized |
| `work_duration` | number | |
| `travel_progress` | number | |
| `scan_reveal_done` | bool | `mission_id <= 0` OR not in `active_units_by_mission_id` |
| `global_position` | object | `{ "x": number, "y": number }` |
| `orbit_angle` | number | |
| `orbit_direction` | number | |
| `orbit_radius_x` | number | |
| `orbit_radius_y` | number | |
| `orbit_speed` | number | |
| `orbit_rotation` | number | |
| `travel_curve_side_sign` | number | |

**Not in job dict (unchanged):** `target_scan_state`, `scan_is_progression` — remain in **`automation.store.missions`** only.

### `mining_missions[]` entry

Built by `_build_mining_job_save_dict`: **`_sanitize_dictionary_for_save(runtime)`** then overwrites/adds:

| Field | JSON type | Source |
|-------|-----------|--------|
| `system_id` | string | runtime (if present after sanitize) |
| `base_id` | string | `_runtime_base_id_with_session_fallback(runtime)` |
| `target_id` | string | runtime, overwritten |
| `cargo_resources` | object | string → int |
| `mining_extract_remainders` | object | optional |
| `cargo_resource_id` | string | optional / legacy |
| `current_cargo` | number | |
| `cargo_capacity` | int | |
| `mining_rate_per_second` | number | |
| `unload_duration` | number | |
| `unload_timer` | number | |
| `unload_xfer_buffers` | object | |
| `loop_active` | bool | |
| `status` | int | `MiningShipStatus` 0–4 |
| `extract_remainder` | number | |
| `unit_state` | int | from **unit** at save (overwrites sanitized) |
| `work_timer` | number | from unit |
| `work_duration` | number | from unit |
| `travel_progress` | number | from unit |
| `global_position` | object | `{ x, y }` from unit |
| `orbit_anchor_id` | string | session base or `unit.base_node` id |

**Additional keys:** Any other runtime key that passes `_sanitize_value_for_save` (e.g. `cargo_unload_sfx_played` if bool) **must still be preserved** if present today — do not filter to a whitelist in Phase A.

**Hard rules**

- No field renames. No type coercion changes (e.g. bool → int).
- Do not remove optional/legacy keys the sanitizer currently keeps.
- Do not add `active_missions` or Save-v2 fields.
- **`SAVE_VERSION` remains 1** in `SaveManager`.

---

## Proposed AutomationSaveService Boundary

Design sketch — **not implemented**:

```gdscript
class_name AutomationSaveService
extends RefCounted
```

### Possible responsibilities

| Method (proposed) | Pure serialize? | Mutates scene/state? |
|-------------------|-----------------|----------------------|
| `build_runtime_save_data(...)` | Yes (output dict) | No |
| `build_scan_missions_array(...)` | Yes | No |
| `build_mining_missions_array(...)` | Yes | No |
| `build_scan_job_save_dict(...)` | Yes | No |
| `build_mining_job_save_dict(...)` | Yes | No |
| `sanitize_dictionary_for_save(...)` | Yes | No |
| `sanitize_value_for_save(...)` | Yes | No |
| `global_position_to_save_dict` / `from_save_dict` | Yes | No |
| `restore_automation_runtime_when_ready(...)` | No | **Yes** |
| `restore_scan_mission(...)` | No | **Yes** |
| `restore_mining_mission(...)` | No | **Yes** |

### Evaluation

| Category | Functions | Phase |
|----------|-----------|--------|
| **Pure serialize helpers** | `_global_position_*`, `_sanitize_*`, `_build_*_job_save_dict`, `_*_missions_to_save_array`, `to_save_data` body | **A** |
| **Read live state via parameters** | Arrays builders need snapshots of dicts + `instance_from_id` results passed in, or a **snapshot DTO** struct | **A** |
| **Mutate controller/scene** | `apply_save_data`, `_restore_*`, `_clear_automation_visuals_*`, fallbacks | **B only** |
| **Orchestration + await** | `apply_automation_save_if_pending`, `_restore_automation_runtime_when_ready` | Stay on **facade** in B; service may receive callbacks |

**Service must NOT** (Phase A): call `GameSession` (except passed-in `system_id` string), spawn units, touch `AutomationStore`, emit signals, or read `automation_root` directly.

---

## Split Into Two Phases

### Phase A — Write-path extraction only

**Move (delegate from controller):**

- `_global_position_to_save_dict`
- `_global_position_from_save_dict` (optional in A — restore-only; can stay on controller until B)
- `_sanitize_value_for_save` / `_sanitize_dictionary_for_save`
- `_build_scan_job_save_dict`
- `_build_mining_job_save_dict`
- `_scan_missions_to_save_array`
- `_mining_missions_to_save_array`
- Body of `to_save_data()` → `build_runtime_save_data(...)`

**Do not move in Phase A:**

- `apply_automation_save_if_pending`
- `apply_save_data`
- `_restore_automation_runtime_when_ready`
- `_restore_scan_mission` / `_restore_mining_mission`
- `_clear_automation_visuals_and_mission_state`
- `_fallback_*`
- `_restart_automation_audio_after_restore`

**Success criterion:** For the same in-game situation, `game_session.automation.runtime` is **semantically identical** to pre-extract baseline (see compatibility test). `AutomationController.to_save_data()` remains public and returns the same key set.

### Phase B — Restore-path extraction later

**Only after Phase A PASS** (manual JSON compare + test matrix).

**Move or delegate:**

- Restore loops and mission rebuilders (possibly with **injected callbacks** for spawn, connect signals, `_get_target_node`).
- Optionally `_clear_automation_visuals_and_mission_state` with audio stop via passed `stop_scan_orbit` callback.

**Keep on facade initially:**

- `apply_automation_save_if_pending` (await + tree)
- System/base **guards** in `apply_save_data` (may call service.restore_runtime(context))

**Risk drivers:** unit spawn, `mission_id` + `restore_mission_record`, double `apply_save_data` retry, `reapply_session_base_unit_upgrade_effects`, `_restart_automation_audio_after_restore`.

---

## Inputs / Outputs for Phase A

### Inputs (controller gathers, passes to service)

| Input | Purpose |
|-------|---------|
| `system_id: String` | `GameSession.current_system_id` |
| `primary_base_id: String` | `_session_primary_base_body_id` |
| `session_base_id: String` | `_get_session_base_id()` result |
| `scan_drone_target_by_unit_id: Dictionary` | Copy or read-only iteration |
| `active_units_by_mission_id: Dictionary` | For `mission_id` / `scan_reveal_done` |
| `mining_ship_runtime_by_unit_id: Dictionary` | Per-ship runtime |
| `resolve_unit_from_id: Callable` | `instance_from_id` wrapper → `AutomationUnit` |
| `get_object_id_from_node: Callable` | `_get_object_id_from_node` for orbit anchor |
| `runtime_base_id_fallback: Callable` | `_runtime_base_id_with_session_fallback` |

**Not required for Phase A:** `idle_drones`, `idle_mining_ships`, `idle_survey_probes` (not scanned by save arrays today).

### Per-unit inputs (inside builders)

| Field source | Used in |
|--------------|---------|
| `AutomationUnit.state`, `work_timer`, `work_duration`, `travel_progress` | Both job types |
| `AutomationUnit.global_position` | `global_position` |
| Orbit fields on unit | Scan job only |
| `unit.base_node` | `orbit_anchor_id` |

### Output

```gdscript
{
  "system_id": String,
  "primary_base_id": String,
  "scan_missions": Array,  # of Dictionary
  "mining_missions": Array,
}
```

**Identical** to current `to_save_data()` return value for v1.

---

## Inputs / Outputs for Phase B (later)

| Input | Purpose |
|-------|---------|
| `runtime: Dictionary` | Pending v1 blob |
| `saved_system_id`, `saved_base_id` | Guards |
| `spawner`, `automation_root` | Nodes |
| `GameSession` / `automation` store | `restore_mission_record`, `get_automation_mission` |
| **Callbacks** | `_spawn_unit`, `_disconnect_unit_signals`, `_ensure_returned_to_base_connected`, signal connects, `_apply_*_upgrade_stats`, `_stop_scan_orbit_audio`, `_restart_automation_audio_after_restore`, `_request_automation_state_changed` |

| Output / effect |
|-----------------|
| Mutated `scan_drone_target_by_unit_id`, `mining_ship_runtime_by_unit_id`, `active_units_by_mission_id` |
| Spawned `AutomationUnit` children under `automation_root` |
| Warnings on skip/fallback |

---

## Byte-/Schema-Compatibility Test

**Goal:** Prove Phase A did not change serialized shape.

### Procedure

1. **Baseline (before Phase A code)**  
   - Branch or tag current `main`.  
   - New Game → establish play state.  
   - **Case set (minimum):** idle; scan outbound; scan at target (orbit); mining outbound; mining with cargo; mining `WAITING_FOR_STORAGE` if reproducible.  
   - Save slot → open `user://saves/save_NNN.json`.  
   - Extract `game_session.automation.runtime` to `baseline_runtime_<case>.json`.

2. **After Phase A**  
   - Same steps, same case labels.  
   - Extract `automation.runtime` to `after_runtime_<case>.json`.

3. **Compare**  
   - **Required:** Same keys on root and on each job dict (per index).  
   - **Required:** Same JSON types per key (`typeof` equivalent).  
   - **Values:** Equal for ints/bools/strings; floats within epsilon for `work_timer`, `travel_progress`, orbit fields, position **or** document case as non-deterministic if timing differs.  
   - **Arrays:** Same length; order may matter if builders iterate dict keys — compare **sorted** job lists by `(target_id, mission_id, status)` if order differs but content same.

4. **Stricter (optional later, not in Phase A PR)**  
   - Editor tool or script: normalize JSON (sort keys, round floats) → diff.  
   - **Not required** for first implementation if manual checklist passes.

### Legitimate differences (document, do not “fix”)

- `global_position`, `work_timer`, `travel_progress` — frame timing.  
- Float string formatting in JSON file — Godot `JSON.stringify` tab indent unchanged in `SaveManager`.

### Failure = block Phase B

- Missing key (e.g. `scan_reveal_done`).  
- Type change (`cargo_resources` stringified wrong).  
- Extra Node/Reference serialized (should never happen — sanitizer returns `null` and drops).

---

## Functions Safe to Extract First (Phase A only)

| Function | Notes |
|----------|--------|
| `_global_position_to_save_dict` | Pure |
| `_sanitize_value_for_save` | Pure |
| `_sanitize_dictionary_for_save` | Pure |
| `_build_scan_job_save_dict` | Pure if all inputs passed as parameters |
| `_build_mining_job_save_dict` | Pure if runtime + unit passed in |
| `_scan_missions_to_save_array` | Pure if dicts + callables passed |
| `_mining_missions_to_save_array` | Pure if dict + callable passed |
| `to_save_data` | Facade: gather inputs → `service.build_runtime_save_data(...)` |

**Conditions**

- `AutomationController.to_save_data()` **stays public** with same signature.  
- Service **does not** read controller fields globally — controller passes snapshots.  
- **No** `GameSession` inside service in Phase A (only strings/numbers passed in).

---

## Functions NOT Safe to Extract First

| Function | Why |
|----------|-----|
| `apply_automation_save_if_pending` | `await`, `GameSession.take_automation_runtime_pending` |
| `apply_save_data` | Guards + mutates world + audio + upgrades + signal |
| `_restore_automation_runtime_when_ready` | Double clear/restore retry |
| `_restore_scan_mission` | Spawn, store, signals, dict writes |
| `_restore_mining_mission` | Runtime rebuild, cargo, status branches |
| `_clear_automation_visuals_and_mission_state` | `queue_free`, audio stop, dict clear |
| `_restart_automation_audio_after_restore` | Reads dicts + unit state (stay controller; uses audio service) |
| `_fallback_scan_job_to_idle` / `_fallback_mining_job_to_idle` | Spawn + idle arrays |

---

## Public API Stability

| API | Caller | Phase A change |
|-----|--------|----------------|
| `to_save_data()` | `GameSession.refresh_automation_snapshot_from_scene` | Implementation delegates; **signature/keys unchanged** |
| `apply_automation_save_if_pending()` | `system_scene.gd` | **Unchanged** (no move) |
| `apply_save_data(runtime)` | Internal restore | **Unchanged** (no move in A) |
| Public dicts for UI | `system_ui_controller.gd` | **Unchanged** |

External call sites: **zero** edits in Phase A.

---

## Save-v2 Relation

| Topic | This extract |
|-------|----------------|
| Save-v2 `active_missions` | **Not introduced** |
| Mission continuity on save | **Unchanged** (still snapshot runtime; probe/pulse cancel pre-save) |
| `save_version` | **Stays 1** |
| `save_v2_mission_continuity_design_v0_1.md` | Future work; optional normalized compare tooling may reuse Phase A test |

This effort is **refactor-only** for maintainability, not a player-facing save upgrade.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| JSON field missing after Phase A | High | Key checklist vs `save_schema_v1.md`; per-case baseline files |
| Type change (int/float/bool) | High | Typed GDScript in service; compare `typeof` in JSON |
| `scan_reveal_done` logic drift | High | Unit-test or copy logic verbatim; same `active_units_by_mission_id.has(mission_id)` |
| Sanitizer drops runtime keys | High | Do not whitelist; same `_sanitize_value_for_save` behavior |
| Node reference in JSON | Critical | Keep sanitizer returning `null` for non-JSON types |
| `mission_id` wrong in scan job | High | Same `mission_id_by_unit` iteration order |
| Phase B restore dup units | High | Defer B; keep double-retry semantics documented |
| Save during mining loses cargo | High | Mining case in compatibility test |
| Save during scan double reward | Medium | Rewards in store/scans, not runtime — still run scan complete save case |
| Dictionary key order in JSON file | Low | Compare normalized structure, not raw string, if needed |
| Accidental `GameSession` in service | Medium | Code review; Phase A API review |

---

## Test Matrix Before Implementation

Run **before Phase A** (baseline) and **after Phase A** (regression).

- [ ] Save idle — empty `scan_missions` / `mining_missions` or only idle orbit jobs as today  
- [ ] Save during scan outbound  
- [ ] Save during scan at target (WORKING / orbit)  
- [ ] Save after scan complete (support orbit, `scan_reveal_done` true)  
- [ ] Save during mining outbound  
- [ ] Save during mining with cargo in `cargo_resources`  
- [ ] Save during unload / `UNLOADING`  
- [ ] Save `WAITING_FOR_STORAGE`  
- [ ] Load each save above (Phase A: load must still pass — **no restore code change**)  
- [ ] No duplicate units after load  
- [ ] No duplicate scan rewards  
- [ ] No resource loss / cargo duplication  
- [ ] `grep tooltip_text` → **0** in `*.gd` / `*.tscn` / `*.tres`  

Phase B adds full matrix rerun with focus on restore failures.

---

## Recommended First Implementation Prompt

Use **only after** this plan is accepted and Phase A baseline JSON is captured on a reference build:

```
Implement AutomationSaveService Phase A only (write-path extraction):

- Create scripts/system/automation/automation_save_service.gd (RefCounted).
- Move pure serialize helpers: global_position_to_save_dict, sanitize_*, build_scan_job_save_dict, build_mining_job_save_dict, build_scan_missions_array, build_mining_missions_array, build_runtime_save_data.
- AutomationController.to_save_data() remains public; gathers state and delegates to the service.
- Do NOT move apply_save_data, apply_automation_save_if_pending, _restore_*, or _clear_automation_visuals_*.
- No save_version change, no new JSON keys, no Save-v2 active_missions.
- Manually compare game_session.automation.runtime JSON before/after for: idle, scan outbound, scan at target, mining with cargo.
```

**Do not implement Phase B** in the same change.

---

## Acceptance (this document)

1. Only `docs/architecture/automation_save_service_extraction_plan_v0_1.md` created.  
2. No code/scene/data changes.  
3. Write-path (Phase A) and restore-path (Phase B) separated.  
4. Save-v1 `automation.runtime` fields documented explicitly.  
5. Risk and test matrices included.  
6. Single Phase A implementation prompt at end.
