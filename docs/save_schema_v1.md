# Save Schema v1

**Status:** Documentation only — describes the **current** on-disk format (`SaveManager.SAVE_VERSION == 1`).  
**Engine:** Godot 4.6.1.  
**Source of truth:** `SaveManager.build_save_data()` / `GameSession.to_save_data()` and store `to_save_data()` / `apply_save_data()` implementations.  
**Related:** `docs/save_behavior_v0_1.md`, `docs/architecture/save_v2_mission_continuity_design_v0_1.md`.

---

## Purpose

This document records the **exact v1 JSON shape** written to `user://saves/save_NNN.json` today, field by field, so Save-v2 design and migration can diff against facts rather than assumptions.

- **v1 is the active save format** (`save_version: 1`).
- **No implementation** — reading this doc does not change saves or loaders.
- Values are JSON-serializable only (`Dictionary` / `Array` / primitives after `JSON.stringify`).

---

## File location

| Item | Value |
|------|--------|
| Path pattern | `user://saves/save_%03d.json` (slots **1–3**) |
| Writer | `SaveManager._write_save_file()` — tab-indented JSON |
| Loader | `SaveManager.load_game()` → `apply_save_data()` |

---

## Top-level JSON

Produced by `SaveManager.build_save_data()` (wrapper around `GameSession.to_save_data()`).

| Field | Type | Owner | Required on load? | Notes |
|-------|------|--------|-------------------|--------|
| `save_version` | `int` | `SaveManager` | **Yes** | Must equal `SaveManager.SAVE_VERSION` (**1**). Any other value → load **fails** (`apply_save_data` returns `false`). |
| `saved_at_unix` | `int` | `SaveManager` | No | `Time.get_unix_time_from_system()` at save. Used by `get_save_metadata()` only; **not** read during `apply_save_data`. |
| `slot_index` | `int` | `SaveManager` | No | 1–3. Updates `SaveManager.active_save_slot` if valid. |
| `current_system_id` | `string` | `SaveManager` (copy of `GameSession.current_system_id`) | No | Metadata / UI; load uses `game_session.current_system_id`. |
| `established_base_count` | `int` | `SaveManager` (derived) | No | Metadata; recomputed from `game_session.established_base_records` if missing. |
| `colony_ship_total` | `int` | `SaveManager` (derived) | No | Sum of `bases[*].colony_ships`; metadata only. |
| `pending_colonization_count` | `int` | `SaveManager` (derived) | No | Count of ops with `status == "pending"`; metadata only. |
| `game_session` | `object` | `GameSession` | **Yes** | Must be a `Dictionary`; passed to `GameSession.apply_save_data()`. |

### Example top-level shape (abbreviated)

```json
{
  "save_version": 1,
  "saved_at_unix": 1710000000,
  "slot_index": 1,
  "current_system_id": "solar-system",
  "established_base_count": 1,
  "colony_ship_total": 0,
  "pending_colonization_count": 0,
  "game_session": { }
}
```

---

## Pre-save hooks (write path only)

Order in `SaveManager.build_save_data()` **before** `GameSession.to_save_data()`:

| Step | Call | Effect on serialized data |
|------|------|---------------------------|
| 1 | `GameSession.cancel_active_survey_probe_missions_before_save()` | Active investigate missions torn down; **+1 survey probe** per mission via `add_survey_probe`; discovery **unchanged** (stays SIGNAL). |
| 2 | `GameSession.cancel_active_base_sensor_pulse_before_save()` | Active pulse stopped; **paid pulse cost refunded** to base; no `_complete_pulse` / no SIGNAL reveals. |
| 3 | `GameSession.refresh_automation_snapshot_from_scene()` | Fills `_automation_runtime_pending` from `AutomationController.to_save_data()` if scene present. |
| 4 | `GameSession.refresh_camera_snapshot_from_scene()` | Fills `_camera_state_pending` from `SystemCameraController.to_save_state()` if present. |
| 5 | `GameSession.to_save_data()` | Writes stores + pending automation/camera snapshots. |

**Load path** does **not** re-run these hooks.

---

## GameSession section

`game_session` = return value of `GameSession.to_save_data()`.

| Field | Type | Owner | Default if missing (`apply_save_data`) | Notes |
|-------|------|--------|----------------------------------------|--------|
| `current_system_id` | `string` | `GameSession` | `START_SYSTEM_ID` (`"solar-system"`) | Empty string → fallback to start system. |
| `discovered_system_ids` | `array` of `string` | `GameSession` | `[]` (cleared, then filled) | Galaxy discovery list. |
| `unlocked_system_ids` | `array` of `string` | `GameSession` | `[]` | Systems player may enter. |
| `established_base_records` | `object` | `GameSession` | `{}` | Keys: **base_id** (e.g. `"earth"`). Values: see [Established base record](#established-base-record). |
| `colonization_operations` | `array` of `object` | `GameSession` | `[]` | See [Colonization](#colonization-section). |
| `next_colonization_operation_id` | `int` | `GameSession` | `1` | `maxi(1, …)`; used to allocate `colony_N` ids. |
| `bases` | `object` | `BaseStore` | skipped if not a Dictionary | Keys: **base_id**. Values: per-base dict. See [BaseStore](#basestore-section). |
| `object_scans` | `object` | `ObjectScanStore` | empty store if missing/empty | See [ObjectScanStore](#objectscanstore-section). |
| `automation` | `object` | `GameSession` + stores/controller | store cleared if invalid | `{ "store", "runtime" }`. See [Automation](#automation-section). |
| `camera_state` | `object` | `GameSession` (from camera snapshot) | pending cleared | Applied to `_camera_state_pending` for scene restore. See [Camera](#camera-state). |

After load: `ensure_default_discovery_for_system` if definition loaded; `_sync_basic_intel_from_all_established_bases()`; `_load_system_definition_for_id(current_system_id)`; signals `galaxy_progression_changed`, `base_resources_changed`, `base_upgrades_changed`.

---

### Established base record

Written by `_apply_established_base_record()` / `mark_base_established_at()`.

| Field | Type | Notes |
|-------|------|--------|
| `base_id` | `string` | Body id used as base key (v0.1: same as celestial body id). |
| `system_id` | `string` | Galaxy system id. |
| `body_id` | `string` | Celestial body id. |
| `established` | `bool` | `true` when active. |

---

## BaseStore section

`game_session.bases` = `BaseStore.to_save_data()` → **`bases.duplicate(true)`** (entire `bases` dictionary).

### Per-base entry (`bases[base_id]`)

Keys created/normalized by `BaseStore.get_base()` / `_create_empty_base()` / `create_new_game_base_entry()`:

| Field | Type | Default (new empty base) | Notes |
|-------|------|--------------------------|--------|
| `resources` | `object` | `{}` | Map **resource_id** (`string`) → **amount** (`int` / JSON number). e.g. `iron`, `survey_data`. |
| `population` | `int` | `0` (empty) / `1` (earth bootstrap) | |
| `drones` | `int` | scan drone **unit count** at base | |
| `mining_ships` | `int` | mining ship count | |
| `colony_ships` | `int` | `0` | Colonization fleet stock. |
| `survey_probes` | `int` | `0` | Consumable probes for investigate. |
| `survey_probes_reserved` | `int` | `0` | Normalized if missing on `get_base()`. |
| `storage_capacity` | `int` | from upgrade catalog / fallback **1000** | Total storage units. |
| `storage_upgrade_level` | `int` | `0` | |
| `scan_drone_upgrade_level` | `int` | `0` | |
| `mining_ship_upgrade_level` | `int` | `0` | |

`apply_save_data`: replaces `bases` dict wholesale; `_refresh_all_base_upgrade_derived_fields()` calls `get_base()` per key to re-sync capacity from upgrade definitions.

**Not a separate key:** `BaseStore` has no wrapper — top-level `game_session.bases` **is** the store map.

---

## ObjectScanStore section

`game_session.object_scans` = `ObjectScanStore.to_save_data()`.

| Field | Type | Structure | Notes |
|-------|------|-----------|--------|
| `object_scan_states` | `object` | `system_id` → `object_id` → `string` | Scan states: `"unknown"`, `"basic"`, `"deep"`, `"special"` (`ObjectScanStore` constants). |
| `object_discovery_states` | `object` | `system_id` → `object_id` → `string` | Discovery: `"hidden"`, `"signal"`, `"known"`. Unknown strings normalize to `"known"` on read with warning. |
| `remaining_resources_by_object` | `object` | `system_id` → `object_id` → `resource_id` → `int` | Depletion / mining remaining amounts. |

`apply_save_data`: if `data.is_empty()`, all three dicts reset to `{}`. Missing sub-keys → empty dict for that subtree.

**No other keys** are serialized by `ObjectScanStore.to_save_data()` in v1.

---

## Automation section

`game_session.automation` = `_build_automation_save_payload()`:

```json
{
  "store": { "next_mission_id": 1, "missions": { } },
  "runtime": { "system_id": "", "primary_base_id": "", "scan_missions": [], "mining_missions": [] }
}
```

### `automation.store` (`AutomationStore.to_save_data()`)

| Field | Type | Default on load | Notes |
|-------|------|-----------------|--------|
| `next_mission_id` | `int` | `1` (`maxi(1, …)`) | Next id to allocate. |
| `missions` | `object` | `{}` | Keys: **mission id as string** (`"1"`, `"2"`, …). Values: mission record. |

#### Mission record (`missions[id]`)

| Field | Type | Notes |
|-------|------|--------|
| `id` | `int` | Duplicated on save/load. |
| `type` | `int` | `0` = `MissionType.SCAN`, `1` = `MissionType.MINE`. |
| `base_id` | `string` | Home / paying base body id. |
| `target_id` | `string` | Target object id. |
| `target_scan_state` | `string` | **Scan missions only** — e.g. `"basic"`, `"deep"`, `"special"`. |
| `scan_is_progression` | `bool` | **Scan missions only** — progression vs special scan path. |

Completed missions are **removed** from store at runtime (`complete_mission`); save only contains **active** store records.

### `automation.runtime` (`AutomationController.to_save_data()`)

Captured live at save (or falls back to `_automation_runtime_pending` if controller not in tree).

| Field | Type | Notes |
|-------|------|--------|
| `system_id` | `string` | `GameSession.current_system_id` at snapshot. Restore **skipped** if ≠ loaded system. |
| `primary_base_id` | `string` | `_session_primary_base_body_id` at snapshot. Restore **skipped** if ≠ session base (when both non-empty). |
| `scan_missions` | `array` | Each element: scan job dict (below). |
| `mining_missions` | `array` | Each element: mining job dict (runtime + unit fields). |

Load: `GameSession._apply_automation_from_save_data` → `_automation_runtime_pending`; `SystemScene` deferred `AutomationController.apply_automation_save_if_pending()`.

#### Scan job (`scan_missions[]` entry)

Built by `_build_scan_job_save_dict()`.

| Field | Type | Notes |
|-------|------|--------|
| `target_id` | `string` | |
| `base_id` | `string` | Session primary base id. |
| `mission_id` | `int` | `AutomationStore` id; `0` if none. |
| `orbit_anchor_id` | `string` | Orbit node id (often base). |
| `unit_state` | `int` | `AutomationUnit.State` enum (0=IDLE … 5=RETURNING). |
| `work_timer` | `number` | |
| `work_duration` | `number` | |
| `travel_progress` | `number` | |
| `scan_reveal_done` | `bool` | `true` if scan reward path already applied / no active store mission. |
| `global_position` | `object` | `{ "x", "y" }`. |
| `orbit_angle` | `number` | |
| `orbit_direction` | `number` | |
| `orbit_radius_x` | `number` | |
| `orbit_radius_y` | `number` | |
| `orbit_speed` | `number` | |
| `orbit_rotation` | `number` | |
| `travel_curve_side_sign` | `number` | |

`scan_is_progression` / `target_scan_state` live in **`automation.store`**, not duplicated in the job dict.

#### Mining job (`mining_missions[]` entry)

Built by `_build_mining_job_save_dict()` = sanitized **runtime** dict + unit fields.

**Typical runtime keys** (from mission start; additional keys may exist if added at runtime and pass `_sanitize_value_for_save`):

| Field | Type | Notes |
|-------|------|--------|
| `system_id` | `string` | |
| `base_id` | `string` | |
| `target_id` | `string` | |
| `cargo_resources` | `object` | `resource_id` → amount (int). |
| `mining_extract_remainders` | `object` | Partial extraction bookkeeping. |
| `cargo_resource_id` | `string` | |
| `current_cargo` | `number` | |
| `cargo_capacity` | `int` | |
| `mining_rate_per_second` | `number` | |
| `unload_duration` | `number` | |
| `unload_timer` | `number` | |
| `unload_xfer_buffers` | `object` | |
| `loop_active` | `bool` | |
| `status` | `int` | `MiningShipStatus`: 0=TO_TARGET, 1=MINING, 2=TO_BASE, 3=UNLOADING, 4=WAITING_FOR_STORAGE. |
| `extract_remainder` | `number` | |
| `unit_state` | `int` | `AutomationUnit.State` (overwritten from unit at save). |
| `work_timer` | `number` | |
| `work_duration` | `number` | |
| `travel_progress` | `number` | |
| `global_position` | `object` | `{ "x", "y" }`. |
| `orbit_anchor_id` | `string` | |

**Not saved:** Godot `unit` instance id as a restore key (new units spawned on load). `Node` references stripped by sanitizer.

---

## Colonization section

`game_session.colonization_operations` = array of operation records (all statuses kept in v1).

### Operation record

Created in `start_colonization_operation()`:

| Field | Type | When present | Notes |
|-------|------|--------------|--------|
| `operation_id` | `string` | always | e.g. `"colony_1"`. |
| `source_base_id` | `string` | always | Paying established base. |
| `target_system_id` | `string` | always | |
| `target_body_id` | `string` | always | |
| `status` | `string` | always | `"pending"`, `"completed"`, `"failed"`, `"cancelled"`. |
| `reserved_colony_ships` | `int` | always | Usually `1`. |
| `duration_ms` | `int` | always | Op duration. |
| `created_at_tick` | `int` | runtime pending | **Stripped on save** for pending ops. |
| `arrival_at_tick` | `int` | runtime pending | **Stripped on save** for pending; replaced by `remaining_ms`. |
| `remaining_ms` | `int` | **save file** for pending | `max(0, arrival_at_tick - now)` at save. |
| `completed_at_tick` | `int` | completed / failed / cancelled | Set when op ends. |

**Save (`_colonization_operations_to_save_array`):** only **pending** ops convert ticks → `remaining_ms` and remove `arrival_at_tick` / `created_at_tick`. Completed/failed/cancelled records are copied as-is (may still contain `completed_at_tick`, etc.).

**Load (`_apply_colonization_operation_from_save`):** if `status == "pending"`, rebuild `arrival_at_tick = now + remaining_ms`, set `created_at_tick = now`, erase `remaining_ms`. Empty `operation_id` → record skipped.

Colonization is **not** cancelled pre-save (unlike survey probe / sensor pulse).

---

## Camera state

`game_session.camera_state` = last snapshot from `SystemCameraController.to_save_state()` (or pending fallback).

| Field | Type | Notes |
|-------|------|--------|
| `system_id` | `string` | Must match loaded system for `SystemScene._try_restore_saved_camera_state()`. |
| `global_position` | `object` | `{ "x": float, "y": float }`. |
| `zoom` | `object` | `{ "x": float, "y": float }` (camera zoom vector). |

Load: stored in `_camera_state_pending`; restored when system scene finishes initial setup.

---

## Missing / not saved

| Item | Notes |
|------|--------|
| UI selection / `ObjectInfoPanel` state | Not serialized. |
| `SignalMarker` instances | Derived from `object_discovery_states` on `apply_for_system`. |
| Audio players / loop playback state | Restarted from unit state after automation restore (`_restart_automation_audio_after_restore`). |
| SurveyProbe investigate FSM | `_active_missions` cleared pre-save; **not** in JSON. |
| Sensor pulse runtime | `_pulse_active`, `_pulse_elapsed`, cooldown — **not** in JSON; cancelled pre-save. |
| Node references / instance ids | Not valid across load; scan/mining jobs respawn units. |
| `tooltip_text` / UI tooltips | Not part of save (project policy: 0). |
| `GameSession` pending flags other than automation/camera | e.g. in-memory definitions, controllers — re-bound in scene. |
| Galaxy map UI-only state | Except data in `discovered_system_ids` / colonization ops. |

---

## v1 compatibility notes

| Topic | Behavior |
|-------|----------|
| **Version gate** | Only `save_version == 1` loads. Missing or `0` → warning + **failed load**. |
| **Optional metadata** | Top-level `saved_at_unix`, counts, duplicate `current_system_id` — safe to omit for loader; UI metadata may degrade. |
| **Partial `game_session`** | Missing arrays → treated as empty. Missing `bases` / `object_scans` → those stores not updated (bases) or cleared (scans empty dict only if key present and empty). |
| **Missing automation** | Non-dictionary `automation` → missions cleared, `next_mission_id = 1`, no runtime restore. |
| **Missing `automation.store`** | Missions cleared. |
| **Missing `automation.runtime`** | No pending runtime; no drones/ships restored from snapshot. |
| **Extra / unknown keys** | Generally ignored on load (duplicated dicts only copy known paths). |
| **Hand-edited saves** | Invalid mission ids (`< 1`) skipped in `AutomationStore.apply_save_data`. |
| **Old base keys** | `get_base()` adds missing upgrade/storage/probe fields on first access after load. |
| **Discovery defaults** | Objects without explicit discovery entry read as **known** (`get_object_discovery_state` default). |

Saves produced before features existed (e.g. without `survey_probes`) should still load if `save_version` is 1 and `game_session` is valid; normalization runs on access.

---

## Risks (v1 as implemented)

| Risk | Detail |
|------|--------|
| **Automation restore skipped** | `system_id` or `primary_base_id` mismatch → entire runtime snapshot dropped (warning). |
| **Automation restore failed** | Missing target/home nodes → job skipped, idle fallback; warning if zero jobs restored after retry frame. |
| **Cargo duplication / loss** | Mining cargo in runtime vs `bases.resources` must stay consistent; restore replays unload logic. |
| **Scan reward duplication** | Mitigated by `scan_reveal_done` + `object_scan_states`; store is source of truth for scan level. |
| **Missing mission target** | Body not spawned → restore warning, mission dropped. |
| **Survey probe save** | Progress lost; probe refunded — player-visible regression by design. |
| **Sensor pulse save** | Cost refunded; no partial reveals. |
| **Colonization instant complete** | Pending with `remaining_ms == 0` completes on next `process_colonization_operations` tick. |
| **Strict version check** | No forward/backward compatibility until SaveManager accepts new versions. |
| **Dual `current_system_id`** | Top-level vs `game_session` could diverge only if file hand-edited; loader uses **game_session** only. |

---

## Load flow (reference)

1. `SaveManager.apply_save_data` — version + `game_session` dict.  
2. `GameSession.apply_save_data` — stores, colonization, automation pending, camera pending, reload system definition.  
3. Player enters `SystemScene` — spawn, `apply_for_system`, `apply_automation_save_if_pending`, camera restore.

---

## Code references

| Area | File |
|------|------|
| Top-level save/load | `scripts/autoload/save_manager.gd` |
| Session payload | `scripts/autoload/game_session.gd` (`to_save_data`, `apply_save_data`, pre-save hooks) |
| Bases | `scripts/autoload/stores/base_store.gd` |
| Scans / discovery / deposits | `scripts/autoload/stores/object_scan_store.gd` |
| Automation missions (store) | `scripts/autoload/stores/automation_store.gd` |
| Automation snapshot (runtime) | `scripts/system/controller/automation_controller.gd` |
| Camera snapshot | `scripts/system/controller/system_camera_controller.gd` |
| Scene restore order | `scripts/system/system_scene.gd` |

---

## Acceptance (this document)

1. Only `docs/save_schema_v1.md` created.  
2. No code/scene/data changes.  
3. Fields traced to actual `to_save_data` / `apply_save_data` / snapshot builders.  
4. Suitable as baseline for Save-v2 in `save_v2_mission_continuity_design_v0_1.md`.
