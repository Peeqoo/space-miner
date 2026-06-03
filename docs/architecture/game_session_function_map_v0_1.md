# GameSession Function Map v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Status:** Read-only audit — **no code changes**.  
**Source:** `scripts/autoload/game_session.gd` (line count verified: **2659**).  
**Related:** `docs/architecture/game_session_split_plan_v0_1.md`, `docs/save_schema_v1.md`, `docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md`.

---

## Purpose

This document maps `GameSession.gd` **before any split**: responsibility regions (line ranges), public API and signals, store ownership, save/load order, and **direct store access leaks** from outside the autoload.

Use it to review extraction boundaries from `game_session_split_plan_v0_1.md` without opening the full file.

---

## File Overview

| Item | Value |
|------|--------|
| **Path** | `scripts/autoload/game_session.gd` |
| **Line count** | **2659** |
| **Autoload** | Yes (`GameSession` node name in project autoloads) |
| **`class_name`** | **None** — global autoload `GameSession` only |
| **`extends`** | `Node` |

### Public store / catalog fields (lines 37–64)

| Field | Type | Role |
|-------|------|------|
| `current_system_definition` | `SystemDefinition` | Active system resource (scene) |
| `current_system_id` | `String` | Active system id (save + gates) |
| `object_scans` | `ObjectScanStore` | Discovery, scan state, remaining resources |
| `system_entry` | `SystemEntryStore` | Staged galaxy → system travel |
| `bases` | `BaseStore` | Per-base economy, units, upgrades, production |
| `automation` | `AutomationStore` | Logical scan/mine mission records |
| `scanner` | `ScannerStore` | Scanner tier helper (legacy/display) |
| `upgrade_catalog` | `UpgradeCatalog` | Loaded in `_ready` |
| `production_catalog` | `ProductionCatalog` | Loaded in `_ready` |
| `colonization_definition` | `ColonizationDefinition` | Colonization balance/UI |
| `game_start_definition` | `GameStartDefinition` | New-game seed (not applied on load) |
| `game_balance` | `GameBalanceDefinition` | v0.1 balance profile |
| `resource_catalog` | `ResourceCatalogDefinition` | UI metadata for resource ids |

### Session-only private state (lines 46–82)

| Field | Role |
|-------|------|
| `_automation_runtime_pending` | Save/load buffer for `automation.runtime` |
| `_camera_state_pending` | Save/load buffer for camera |
| `discovered_system_ids` / `unlocked_system_ids` | Galaxy progression (serialized) |
| `_galaxy_progression_seeded` | Boot guard |
| `_system_definition_by_id` | Cached `SystemDefinition` catalog |
| `_established_base_ids` / `_established_base_records` | True “base exists” geography |
| `_colonization_operations` / `_next_colonization_operation_id` | In-flight colony ops |

### Constants (lines 5–35)

Aliases for scan/discovery (`SCAN_*`, `DISCOVERY_*`), `START_SYSTEM_ID`, `PROXIMA_SYSTEM_ID`, `SYSTEM_STAR_OBJECT_ID`, default `.tres` paths, `SCANNER_*` tiers.

### Signals (lines 84–90)

See [Signal Map](#signal-map).

---

## Signal Map

| Signal | Emitted from (function / area, approx. lines) | Known listeners | Purpose | Risk if missing |
|--------|--------------------------------------------------|-----------------|--------|-----------------|
| `object_remaining_resources_changed(system_id, object_id)` | `extract_resource_amount` (~1083) | `object_info_panel.gd`, `system_ui_controller.gd` | Deposit UI refresh after mining extract | Stale remaining-resource display |
| `base_resources_changed(base_id)` | Base add/spend/remove/build/colonization/survey paths; `apply_save_data` loop (~2524); `reset_for_new_game` (~2286) | `top_hud`, `storage_panel`, `production_panel`, `upgrade_panel`, `base_management_panel`, `galaxy_map`, `automation_controller`, `system_ui_controller` | Storage/units/probes changed | Frozen HUD/panels |
| `base_upgrades_changed(base_id)` | `buy_next_base_upgrade` (~1850); `apply_save_data` (~2525) | `upgrade_panel`, `production_panel`, `system_ui_controller` | Upgrade tier changed | Wrong upgrade UI / derived stats display |
| `galaxy_progression_changed()` | `discover_system`, `unlock_system`, `reset_for_new_game`, `apply_save_data` | `galaxy_map.gd` | Discovered/unlocked systems changed | Galaxy map stale |
| `established_body_discovery_visual_refresh_requested(system_id, body_id)` | `_apply_established_base_record` (~909) | `system_ui_controller.gd` | Colony establish → discovery visual refresh | Body stays wrong visibility after establish |

### External signal emits (facade leak)

These call sites **emit `GameSession` signals without going through GameSession methods**:

| Location | Signal | Notes |
|----------|--------|-------|
| `survey_probe_mission_controller.gd` ~203 | `base_resources_changed` | After direct `GameSession.bases.consume_survey_probe` |
| `base_sensor_pulse_controller.gd` ~328 | `base_resources_changed` | After direct `GameSession.bases.spend_cost` |

**Risk:** Future extractions that move spend logic must preserve these emits or route through `GameSession` wrappers.

---

## Public API Map

**Stable?** = must not change without migration plan. **Backing** = authoritative data owner.

### Session identity & travel

| Method / state | External callers | Purpose | Backing | Stable? | Risk |
|----------------|------------------|---------|---------|---------|------|
| `current_system_id` | `automation_controller`, `system_scene`, `system_ui_controller`, `galaxy_map`, save metadata | Active system key | GameSession | **Yes** | Wrong system for all gates |
| `current_system_definition` | `system_scene`, `system_discovery_controller`, `galaxy_map` | Loaded definition | GameSession + `.tres` | **Yes** | Null mid-load |
| `set_current_system` | `system_scene`, `galaxy_map` | Bind definition | GameSession | **Yes** | |
| `ensure_default_system_loaded` | `system_scene`, boot | Load default/solar | GameSession | **Yes** | |
| `ensure_boot_state` | `main.gd` | Boot catalogs + earth establish | GameSession | **Yes** | |
| `stage_system_entry` / `consume_selected_system_definition` / `consume_travel_entry_flag` | `galaxy_map`, `system_scene` | Travel staging | `system_entry` | **Yes** | |
| `get_system_definition_by_id` / `get_system_display_name` | `galaxy_map`, `main_menu` | Galaxy UI | GameSession catalog | **Yes** | |
| `START_SYSTEM_ID`, `PROXIMA_SYSTEM_ID`, … consts | Widespread | Stable ids | const | **Yes** | |

### Galaxy progression

| Method / state | External callers | Purpose | Backing | Stable? | Risk |
|----------------|------------------|---------|---------|---------|------|
| `discovered_system_ids` / `unlocked_system_ids` | Save (via `to_save_data`) | Serialized lists | GameSession | **Yes** | |
| `discover_system` / `unlock_system` | Gameplay (map) | Mutate lists | GameSession | **Yes** | |
| `is_system_discovered` / `can_enter_system` | `galaxy_map` | Access rules | GameSession | **Yes** | |
| `ensure_galaxy_progression_boot` | `galaxy_map` | Seed from game start | GameSession | **Yes** | |

### Established bases & colonization

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `has_established_base` / `has_established_base_in_system` | Automation, UI, sensor pulse, survey | Membership | `_established_base_*` | **Yes** | Placeholder base in BaseStore ≠ established |
| `get_established_base_*` / `get_established_base_record` | UI, galaxy HUD, automation | Geography | `_established_base_records` | **Yes** | |
| `mark_base_established_at` / `establish_base_at_body` | Colonization, new game | Create base | Session + BaseStore | **Yes** | Double establish |
| `start_colonization_operation` / `complete_*` / `cancel_*` | `galaxy_map`, `system_ui_controller`, `galaxy_map_hud` | Colony ship ops | `_colonization_operations` | **Yes** | |
| `process_colonization_operations` | `galaxy_map_hud`, `system_ui_controller`, `_process` | Auto-complete pending | GameSession | **Yes** | |
| `get_colonization_*` (status, pending, source) | Galaxy HUD/UI | Display | GameSession | **Yes** | |
| `colonization_definition` (field) | `galaxy_map_hud` | UI duration text | `.tres` | **Yes** | |

### Base economy

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `get_base_resource_amount` / `get_base_resources` | UI, automation | Read | **BaseStore** | **Yes** | |
| `add_base_resource` / `spend_base_resource` / `remove_base_resource` | Automation, survey, sensor refund, UI | Mutate + signal | **BaseStore** | **Yes** | Dup spend if bypassed |
| `get_base_storage_*` / `get_base_storage_blocked_reason_full` | Automation, UI | Capacity | **BaseStore** | **Yes** | |
| `get_base_drone_count` / `mining_ship` / `colony_ship` | Automation, UI | Units | **BaseStore** | **Yes** | |
| `get_available_survey_probe_count` / `can_consume_survey_probe` / `add_survey_probe` | Automation, survey controller | Probes | **BaseStore** | **Yes** | |
| `reserve_or_consume_survey_probe` | Survey flow | Probe consume | **BaseStore** | **Yes** | |

### Production & upgrade

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `get_build_base_*_gate` / `build_base_*` | `production_panel` | Build units | **BaseStore** + catalogs | **Yes** | Build without gate |
| `get_buy_next_base_upgrade_gate` / `buy_next_base_upgrade` | `upgrade_panel` | Upgrades | **BaseStore** + **UpgradeCatalog** | **Yes** | Stats not refreshed |
| `get_*_upgrade_definition` / `has_next_base_upgrade` | `upgrade_panel`, `system_ui_controller` | UI | Catalog + BaseStore | **Yes** | |
| `get_unlocked_scan_layer_for_base` / `get_unlocked_mining_layer_for_base` | Automation, UI | Layer gates | **BaseStore** | **Yes** | |
| `get_scan_drone_*_multiplier` / `get_mining_ship_*_multiplier` | `automation_controller` | Derived stats | **BaseStore** | **Yes** | |
| `get_colony_ship_build_*` / prerequisite status | `production_panel` | Colony gates | GameSession + stores | **Yes** | |
| `get_production_cost` / `get_production_definition` | `production_panel` | Costs | **BaseStore** / catalog | **Yes** | |

### Discovery, scan, mine gates

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `get/set_object_discovery_state` | Discovery, survey, sensor pulse | Discovery FSM | **ObjectScanStore** | **Yes** | Mix with scan |
| `is_object_known` / `is_object_hidden` / … | Automation, gates | Queries | **ObjectScanStore** | **Yes** | |
| `ensure_default_discovery_for_system` | `system_scene` | Seed on enter | **ObjectScanStore** + defs | **Yes** | |
| `get/set_object_scan_state` | Automation, UI, galaxy | Scan tier | **ObjectScanStore** | **Yes** | |
| `can_scan_object` | `automation_controller`, `system_ui_controller` | Scan gate | GameSession policy | **Yes** | |
| `can_mine_object` | `system_ui_controller` | Mine gate | GameSession policy | **Yes** | |
| `get_scan_target_state_or_rescan_state` / `get_scan_duration_seconds_for_target_state` | Automation | Mission params | GameSession | **Yes** | |
| `grant_scan_survey_data_reward` | Automation scan complete | SurveyData reward | **BaseStore** | **Yes** | Dup reward |
| `extract_resource_amount` / `get_remaining_resource_amount` | Automation mining | Depletion | **ObjectScanStore** | **Yes** | Dup/lost ore |
| `ensure_object_resources_initialized` / `ensure_mining_resources_for_object` | Automation | Init deposits | **ObjectScanStore** | **Yes** | |
| `scan_state_rank` / `SCAN_*` consts | UI, automation, `scan_info_builder` | Tier compare | const / helpers | **Yes** | |

### Automation records

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `create_scan_mission` / `create_mining_mission` | `automation_controller` | Store records | **AutomationStore** | **Yes** | |
| `complete_automation_mission` / `get_automation_mission` | `automation_controller` | Complete/restore | **AutomationStore** | **Yes** | |
| `automation` (field) | `automation_controller` restore | Direct store | **AutomationStore** | **Yes** | Leak — see below |

### Save / load / snapshots

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `reset_for_new_game` | `main_menu` | New game | All stores + session | **Yes** | |
| `to_save_data` | `SaveManager` | Serialize session | Stores + session | **Yes** | Schema break |
| `apply_save_data` | `SaveManager` | Restore session | Stores + session | **Yes** | Order regression |
| `refresh_automation_snapshot_from_scene` | `SaveManager`, `automation_controller` | Pre-save runtime | Controller → pending | **Yes** | |
| `refresh_camera_snapshot_from_scene` | `SaveManager` | Pre-save camera | Camera → pending | **Yes** | |
| `take_automation_runtime_pending` / `has_automation_runtime_pending` | `system_scene`, `AutomationController` | Load handoff | `_automation_runtime_pending` | **Yes** | |
| `take_camera_state_pending` / `has_camera_state_pending_for_system` | `system_scene` | Camera restore | `_camera_state_pending` | **Yes** | |
| `cancel_active_survey_probe_missions_before_save` | `SaveManager` | Pre-save step 1 | Scene → controller | **Yes** | |
| `cancel_active_base_sensor_pulse_before_save` | `SaveManager` | Pre-save step 2 | Scene → controller | **Yes** | |

### Resource catalog & balance (read-mostly)

| Method | External callers | Purpose | Backing | Stable? | Risk |
|--------|------------------|---------|---------|---------|------|
| `get_resource_display_name` / `get_resource_short_label` / `get_resource_sort_order` | UI panels, `scan_info_builder` | UI labels | **resource_catalog.tres** | **Yes** | Wrong label only |
| `get_gate_text` / `get_gate_ui_texts` | UI | Block reasons | gate `.tres` | **Yes** | |
| `get_game_balance` | Controllers | Balance | **game_balance.tres** | **Yes** | |

### API note (caller vs definition)

`automation_controller.gd` calls `GameSession.get_primary_base_id()` (~118), but **no such method exists** in `game_session.gd` at audit time. Treat as **pre-existing coupling risk** if strict typing is enforced; not introduced by this map.

---

## Function Regions

Line ranges are **inclusive** of section headers where noted. Small gaps between regions are blank lines or one-off helpers.

| # | Region | Lines (approx.) | Key functions | State touched | Store touched | External deps | Future extraction | Risk |
|---|--------|-----------------|-----------------|---------------|---------------|---------------|-------------------|------|
| 1 | Constants / store init / public fields | **1–96** | consts, `var` stores, signals | All public `var` | Constructs stores | `.tres` paths | Stay on GameSession | Low |
| 2 | `_ready` / catalog loading | **97–119** | `_ready` | Catalog refs, `mark_base_established(earth)` | `bases.set_*_catalog` | UpgradeCatalog, ProductionCatalog loaders | Session boot only | Medium (dev boot side effects) |
| 3 | `_process` / boot state | **121–146** | `_process`, `ensure_boot_state` | Colonization auto-complete tick | — | — | ColonizationService (late) | Low |
| 4 | Current system | **148–169** | `ensure_default_system_loaded`, `set_current_system` | `current_system_*` | — | SystemDefinition `.tres` | SessionStateService | High |
| 5 | Galaxy progression boot & API | **174–300** | `ensure_galaxy_progression_boot`, `discover_system`, `unlock_system`, `can_enter_system`, loaders | `discovered_*`, `unlocked_*` | — | GameStartDefinition | GalaxyProgressionService | Medium |
| 6 | System entry (travel) | **302–320** | `stage_system_entry`, `consume_*`, `can_leave_current_system` | `system_entry` | **SystemEntryStore** | Galaxy map | SessionStateService | Medium |
| 7 | Established bases (core) | **322–412** | `mark_base_established_*`, `establish_base_at_body` | `_established_base_*` | BaseStore row | Colonization | ColonizationService | High |
| 8 | Definition loaders & resource catalog | **414–561** | `_load_*`, `get_resource_*`, `get_storage_resource_ids_sorted` | `resource_catalog`, UI defs | — | `.tres` | **ResourceCatalogFacade** | Low |
| 9 | Gate helper | **564–573** | `_gate_fail` | — | — | GateUiTextDefinition | Utility (stay) | Low |
| 10 | Colonization operations | **575–850** | `start/complete/cancel_colonization_*`, `process_colonization_operations`, `get_colonization_*` | `_colonization_operations` | BaseStore ships/resources | ColonizationDefinition | ColonizationService | High |
| 11 | Established queries & intel sync | **857–1046** | `has_established_base*`, `_apply_established_base_record`, `_sync_basic_intel_*`, body loaders | Records, discovery side effects | **ObjectScanStore** | SystemDefinition bodies | Colonization + ObjectProgression | High |
| 12 | Mining / remaining_resources (ObjectScan API) | **1048–1111** | `extract_resource_amount`, `ensure_*_resources`, `has_object_resources` | remaining_resources | **ObjectScanStore** | — | ObjectProgressionFacade | High |
| 13 | Mine gate | **1113–1230** | `can_mine_object`, `_mine_blocked`, definition loaders | — | ObjectScanStore (read) | ScannedResourceEntry | ScanMineGateService | Medium |
| 14 | Discovery facade | **1232–1336** | `get/set_object_discovery_state`, `is_object_*`, `ensure_default_discovery_for_system`, `_seed_discovery_*` | discovery states | **ObjectScanStore** | SystemDefinition | ObjectProgressionFacade | High |
| 15 | Scan state / progression / gates | **1339–1574** | `scan_state_rank`, `get_next_scan_target_state`, `can_scan_object`, `grant_scan_survey_data_reward` | scan states (indirect) | ObjectScanStore, BaseStore | UnitDefinition, balance | ScanMineGateService + ObjectProgression | High |
| 16 | Scanner API | **1577–1593** | `get_active_scanner_tier`, `get_scanner_tier_for_base` | — | **ScannerStore** | — | Low priority | Low |
| 17 | Base economy facade | **1596–1761** | `get/add/spend/remove_base_resource`, storage, units, survey probes | — | **BaseStore** | — | BaseEconomyFacade | High |
| 18 | Production build | **1682–1761**, **1925–2173** | `get_build_*_gate`, `build_base_*`, colony prerequisites, `get_production_*` | units, resources | **BaseStore** | ProductionCatalog | ProductionService | High |
| 19 | Upgrade buy & multipliers | **1803–1914** | `get_buy_next_base_upgrade_gate`, `buy_next_base_upgrade`, `get_*_multiplier` | upgrade levels | **BaseStore** | UpgradeCatalog | UpgradeService | High |
| 20 | AutomationStore facade | **2175–2199** | `create_*_mission`, `complete_automation_mission` | missions | **AutomationStore** | — | Thin facade (stay) | Medium |
| 21 | New game / reset | **2207–2287** | `reset_for_new_game` | Full session reset | All stores cleared/seeded | GameStartDefinition | SaveSessionService (orchestration) | High |
| 22 | Pre-save hooks | **2295–2306** | `cancel_active_survey_probe_*`, `cancel_active_base_sensor_pulse_*` | Scene missions | — | SurveyProbe / SensorPulse controllers | SaveSessionService | Medium |
| 23 | Automation & camera snapshots | **2290–2441** | `refresh_*_snapshot`, `take_*_pending`, `_capture_*`, tree finders | pending dicts | — | AutomationController, SystemCameraController | SaveSessionService | Medium |
| 24 | Save `to_save_data` | **2444–2456**, **2352–2356**, **2570–2587** | `to_save_data`, `_build_automation_save_payload`, `_colonization_operations_to_save_array` | All serialized fields | All stores | Live scene capture | SaveSessionService | **Critical** |
| 25 | Load `apply_save_data` | **2459–2527**, **2530–2616** | `apply_save_data`, `_apply_automation_from_save_data`, `_apply_camera_state_from_save_data`, `_load_system_definition_for_id` | Full restore | All stores | — | SaveSessionService | **Critical** |
| 26 | System definition catalog | **2605–2659** | `get_system_definition_by_id`, `_build_system_definition_catalog` | `_system_definition_by_id` | — | `data/galaxy_systems/*.tres` | SessionStateService | Medium |

---

## Store Ownership Map

### BaseStore (`GameSession.bases`)

| Data | Owner | GameSession access |
|------|--------|-------------------|
| `bases[base_id].resources` | **BaseStore** | Facade get/add/spend; signals on change |
| Unit counts (drones, ships, colony, survey probes) | **BaseStore** | Facade getters; build methods |
| Upgrade levels per category | **BaseStore** | Facade + `upgrade_catalog` |
| Production build affordability | **BaseStore** | `get_build_*_gate` → store reason keys |
| Storage capacity / used | **BaseStore** | Facade storage APIs |

**Serialize:** `bases.to_save_data()` / `apply_save_data()` via `to_save_data` / `apply_save_data` (~2452–2504).

### ObjectScanStore (`GameSession.object_scans`)

| Data | Owner | GameSession access |
|------|--------|-------------------|
| `object_discovery_states` | **ObjectScanStore** | get/set + seeding |
| `object_scan_states` | **ObjectScanStore** | get/set + rank helpers |
| `remaining_resources_by_object` | **ObjectScanStore** | extract/init/deplete APIs |

**Serialize:** `object_scans.to_save_data()` / `apply_save_data()`.

**Internal direct read:** `count_fully_scanned_objects` / ice-source helpers read `object_scans.object_scan_states` directly (~1984–2012) — acceptable inside GameSession; external callers should use facade methods.

### AutomationStore (`GameSession.automation`)

| Data | Owner | GameSession access |
|------|--------|-------------------|
| `missions`, `next_mission_id` | **AutomationStore** | `create_*` / `complete_*` wrappers |
| Runtime unit snapshot | **AutomationController** + `_automation_runtime_pending` | Not in AutomationStore |

**Serialize:** `automation` block `{ store, runtime }` in `to_save_data`.

### ScannerStore (`GameSession.scanner`)

| Data | Owner | Notes |
|------|--------|-------|
| Active scanner tier | **ScannerStore** | Thin wrapper; low split priority |

### SystemEntryStore (`GameSession.system_entry`)

| Data | Owner | Notes |
|------|--------|-------|
| Staged system definition / travel flag | **SystemEntryStore** | Galaxy → system transition |

### GameSession-only state (not in sub-stores)

| Data | Serialized? | Notes |
|------|-------------|-------|
| `current_system_id` | Yes | Reload definition after apply |
| `discovered_system_ids` / `unlocked_system_ids` | Yes | |
| `_established_base_records` | Yes | Truth for established bases |
| `_colonization_operations` | Yes | Tick fields converted on save |
| `_automation_runtime_pending` | Via `automation.runtime` | Consumed on scene load |
| `_camera_state_pending` | Via `camera_state` | Consumed on scene load |
| `current_system_definition` | No (reloaded) | Cleared during `apply_save_data` |

---

## Direct Store Access Leaks

Places **outside** `game_session.gd` that bypass facade methods and touch store fields on the autoload.

### `GameSession.bases.*`

| File | Line(s) | Call | Risk |
|------|---------|------|------|
| `scripts/system/controller/survey_probe_mission_controller.gd` | ~196 | `GameSession.bases.consume_survey_probe(bid)` | Must keep probe count + **manual** `base_resources_changed.emit` |
| `scripts/system/controller/base_sensor_pulse_controller.gd` | ~318, ~326 | `GameSession.bases.can_afford`, `GameSession.bases.spend_cost` | Must keep spend + **manual** signal emit |

**Preferred future path:** `GameSession.spend_cost` / `consume_survey_probe` wrappers that always emit signals (no behavior change in first extract).

### `GameSession.automation.*`

| File | Line(s) | Call | Risk |
|------|---------|------|------|
| `scripts/system/controller/automation_controller.gd` | ~950–951 | `GameSession.automation.missions.has/erase` | Store consistency on recall |
| `scripts/system/controller/automation_controller.gd` | ~2493 | `GameSession.automation.restore_mission_record` | Load restore path |

**Note:** Restore should stay coordinated with `AutomationController` until AutomationSaveService Phase B is designed.

### `GameSession.object_scans.*`

| Result | |
|--------|--|
| **No external leaks found** | All external access goes through `GameSession.get/set_*` and gate APIs |

---

## Save/Load Order Diagram

### Pre-save (write) — `SaveManager.build_save_data()` (`save_manager.gd` ~81–104)

Per `docs/save_schema_v1.md`:

```text
SaveManager.build_save_data()
  │
  ├─1─► GameSession.cancel_active_survey_probe_missions_before_save()
  │         └─► SurveyProbeMissionController.cancel_all_active_investigations_refund()
  │
  ├─2─► GameSession.cancel_active_base_sensor_pulse_before_save()
  │         └─► BaseSensorPulseController.cancel_pulse_before_save()
  │
  ├─3─► GameSession.refresh_automation_snapshot_from_scene()
  │         └─► AutomationController.to_save_data() → _automation_runtime_pending
  │
  ├─4─► GameSession.refresh_camera_snapshot_from_scene()
  │         └─► SystemCameraController.to_save_state() → _camera_state_pending
  │
  └─5─► GameSession.to_save_data()
            ├─ session fields (system id, galaxy, established, colonization, …)
            ├─ bases.to_save_data()
            ├─ object_scans.to_save_data()
            ├─ automation { store, runtime snapshot }
            └─ camera_state (live capture again in to_save_data)
```

**Wrapper fields:** `save_version: 1`, metadata (`current_system_id`, counts), `game_session: <dict>`.

### Load — `SaveManager.load_game()` → `GameSession.apply_save_data()` (~2459–2527)

```text
GameSession.apply_save_data(data)
  │
  ├─► current_system_id (fallback START_SYSTEM_ID)
  ├─► discovered_system_ids / unlocked_system_ids
  ├─► established_base_records + _established_base_ids
  ├─► colonization_operations (+ rehydrate pending ticks)
  ├─► bases.apply_save_data → _refresh_all_base_upgrade_derived_fields()
  ├─► object_scans.apply_save_data
  ├─► _sync_basic_intel_from_all_established_bases()
  ├─► ensure_default_discovery_for_system (if definition already loaded)
  ├─► _apply_automation_from_save_data → automation store + _automation_runtime_pending
  ├─► _apply_camera_state_from_save_data → _camera_state_pending
  ├─► current_system_definition = null
  ├─► _load_system_definition_for_id(current_system_id)
  └─► galaxy_progression_changed.emit()
        └─► for each base_id in bases.bases:
              base_resources_changed.emit(bid)
              base_upgrades_changed.emit(bid)
```

**Scene consumption (after load, not in `apply_save_data`):**

- `system_scene` → `take_camera_state_pending()` when system matches
- `AutomationController.apply_automation_save_if_pending()` → `take_automation_runtime_pending()`

### New game — `reset_for_new_game()` (~2207–2287)

Clears colonization, established records, reseeds `bases`, clears `object_scans` and `automation`, seeds galaxy from `GameStartDefinition`, `mark_base_established_at`, sets `current_system_id`, `ensure_default_system_loaded`, emits `base_resources_changed` + `galaxy_progression_changed`.

**Not** used on Continue/Load.

---

## Dangerous Couplings

| Coupling | Why it matters |
|----------|----------------|
| **Pre-save order (1→5)** | Changing order changes what is serialized (active missions vs refunds) |
| **`apply_save_data` order** | Stores before pending buffers; intel sync before discovery seed; system def reloaded last |
| **Post-load signal burst** | UI relies on mass `base_*_changed` after load — omitting breaks panels |
| **Signals vs direct store access** | External `bases.spend_cost` + manual emit must stay paired |
| **Base spend/build** | All production/upgrade paths must go through BaseStore affordability |
| **Discovery vs scan** | Different ObjectScanStore maps; `ensure_default_discovery` vs `set_object_scan_state` |
| **`remaining_resources`** | Initialized from body defs; mining uses `extract_resource_amount` — must not reset on load incorrectly |
| **Colonization establish** | `establish_base_at_body` → records + BaseStore + `established_body_discovery_visual_refresh_requested` |
| **Automation pending** | Store missions applied separately from runtime restore in scene |
| **Resource IDs** | Dictionary keys in saves and `.tres` — catalog display must not alter ids |
| **`has_established_base` vs `bases.get_base`** | Placeholder base rows ≠ established geography |
| **Live scene capture in `to_save_data`** | Camera captured again inside `to_save_data` after refresh step |
| **`get_primary_base_id` missing** | Automation caller may depend on undefined API — verify in editor |

---

## Risk Areas (summary)

| Area | Severity | Lines (anchor) |
|------|----------|----------------|
| `apply_save_data` / `to_save_data` | **Critical** | 2444–2527, 2570–2616 |
| Colonization + establish | **High** | 393–412, 575–686, 894–909 |
| Mining extract + signals | **High** | 1075–1083 |
| Scan gate + reward | **High** | 1423–1477, 1551–1565 |
| Base economy signals | **High** | 1608–1620, 2521–2525 |
| Discovery seed on system enter | **High** | 1261–1301 |
| Direct `GameSession.bases.*` leaks | **Medium** | External files only |
| Resource catalog | **Low** | 474–561 |

---

## Recommended First Code Extraction

**After this map is reviewed** (no code in Phase 3.7):

Extract **`ResourceCatalogFacade`** as an **internal `RefCounted` delegate** on `GameSession` — same pattern as Phase 3.6 `AutomationAudioService` / `AutomationSaveService` on `AutomationController`.

| Why first | Detail |
|-----------|--------|
| Read-only | Display names, short labels, sort order — no amounts or spend |
| Low risk | No save fields, no signals, no store mutation |
| Clear boundary | Lines **474–561** (+ `_load_resource_catalog`) |
| Public API unchanged | `get_resource_display_name` etc. remain on `GameSession |

**Do not** start `ResourceCatalogFacade` implementation until this function map is reviewed and agreed.

**Do not** start `SaveSessionService`, `ColonizationService`, or `ObjectProgressionFacade` before lower-risk steps in `game_session_split_plan_v0_1.md`.

---

## Acceptance (this document)

1. Only `docs/architecture/game_session_function_map_v0_1.md` was created.  
2. No code, scene, or data files were changed.  
3. Line ranges reflect the current **2659-line** `game_session.gd`.  
4. Public APIs, signals, and store ownership are documented.  
5. Direct store leaks (`bases.*`, `automation.*`) are listed.  
6. Save/load and pre-save order match `docs/save_schema_v1.md`.  
7. Exactly one next recommendation: **ResourceCatalogFacade** after review.  
8. `tooltip_text`: **0** in project policy (unchanged).
