# GameSession Split Plan v0.1

**Status:** Design only — **no split implemented**.  
**Engine:** Godot 4.6.1.  
**Scope file:** `scripts/autoload/game_session.gd` (~**2659** lines, Autoload `Node`, **no** `class_name`).  
**Prerequisite:** Phase 3.6 AutomationController Split Preparation **CLOSED / PASS** (`docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md`).  
**Related:** `docs/save_schema_v1.md`, `docs/architecture/save_v2_mission_continuity_design_v0_1.md`, `docs/architecture/automation_controller_split_plan_v0_1.md`, `docs/architecture/resource_definition_catalog_design_v0_1.md`, `docs/architecture/per_object_discovery_refresh_design_v0_1.md`.

---

## Purpose

`GameSession` is the **largest cross-cutting Autoload** in v0.1. It is not a single domain module — it is a **session facade** that owns or coordinates:

- Multiple **stores** (`BaseStore`, `ObjectScanStore`, `AutomationStore`, …)
- **Save/load orchestration** and pre-save hooks
- **Galaxy progression** and **colonization** session state
- **Gate APIs** for scan, mine, production, and upgrades
- **UI-facing signals** and resource display helpers
- **Scene snapshot buffers** (automation runtime, camera)

**Why split later**

- One file mixes unrelated failure modes (save order vs colonization vs mining extraction vs upgrade multipliers).
- Controllers and UI panels depend on **dozens** of `GameSession.*` entry points; accidental API drift breaks the whole game.
- Future Save-v2 and mission continuity need a **clear owner** per data domain — today that ownership is implicit inside the facade.

**Why no big-bang refactor now**

- `GameSession` is an **Autoload**; renaming, moving, or splitting it touches **every** system scene, galaxy map, and UI panel.
- Save v1 (`SaveManager.SAVE_VERSION == 1`) is production-shaped; `game_session` JSON shape and `apply_save_data` order are contractual.
- Phase 3.6 proved the safe pattern: **plan → function map → low-risk extract → baselines → small implementation**. GameSession must follow the same discipline.

**Goal of this document**

Make responsibilities visible, map **public API and signals**, clarify **true data owners** (stores vs session-only state), propose **future internal services/facades**, and define a **safe extraction order** — without changing code, autoloads, signals, or save schema in Phase 3.7.

---

## Current Role of GameSession

`GameSession` (`extends Node`, registered as Autoload) is the **central session facade** for the running game:

| Facade area | Role today |
|-------------|------------|
| **Stores** | Public instances: `bases`, `object_scans`, `automation`, `scanner`, `system_entry` |
| **Save / load** | `to_save_data()`, `apply_save_data()`, `reset_for_new_game()`; pending `_automation_runtime_pending`, `_camera_state_pending` |
| **Galaxy progression** | `discovered_system_ids`, `unlocked_system_ids`, enter/leave rules |
| **Established bases** | `_established_base_records`, `mark_base_established*`, `establish_base_at_body` |
| **Base economy** | Resource get/add/spend, storage, units, survey probes — mostly delegate to `BaseStore` + emit `base_resources_changed` |
| **Production** | Build gates + `build_base_*` — delegate to `BaseStore` + `production_catalog` |
| **Upgrades** | Buy gates + `buy_next_base_upgrade` — delegate to `BaseStore` + `upgrade_catalog` |
| **Discovery / scan facade** | Thin wrappers over `ObjectScanStore` + seeding from `SystemDefinition` |
| **Mining extraction** | `extract_resource_amount`, `remaining_resources`, depletion signals |
| **Scan / mine gates** | `can_scan_object`, `can_mine_object` — **policy only**, no unit motion |
| **Automation records** | `create_scan_mission`, `complete_automation_mission` → `AutomationStore` |
| **Colonization** | In-session operation dict, timers, complete/cancel, galaxy HUD integration |
| **Resource catalog read** | `get_resource_display_name`, sort order — **UI metadata only** |
| **Definitions** | Load/cache `SystemDefinition`, `GameStartDefinition`, `GameBalanceDefinition`, colonization, gate texts |
| **Pre-save hooks** | Survey probe cancel/refund; sensor pulse cancel/refund; automation/camera snapshot |
| **Signals** | UI/controllers subscribe for resources, upgrades, galaxy, discovery refresh, remaining resources |

**Not owned by GameSession (but coordinated):**

- Visible automation units → `AutomationController` (runtime); logical missions → `AutomationStore`
- Survey probe investigate FSM → `SurveyProbeMissionController`
- Sensor pulse FSM → `BaseSensorPulseController`
- On-disk save wrapper → `SaveManager`

---

## Current Responsibilities

| # | Responsibility | Functions / state (representative) | Backing store / owner | External callers | Risk |
|---|----------------|-----------------------------------|------------------------|------------------|------|
| 1 | **Session identity / current system** | `current_system_id`, `current_system_definition`, `set_current_system`, `ensure_default_system_loaded`, `get_system_definition_by_id`, `stage_system_entry`, `consume_selected_system_definition` | **GameSession** + `res://data/galaxy_systems/*.tres` catalog | `system_scene.gd`, galaxy travel | **High** — wrong system → all gates/scans wrong |
| 2 | **Galaxy discovered / unlocked** | `discovered_system_ids`, `unlocked_system_ids`, `discover_system`, `unlock_system`, `can_enter_system`, `is_system_discovered` | **GameSession** (serialized in save) | `galaxy_map.gd`, galaxy HUD | **Medium** — map access wrong |
| 3 | **Established bases** | `_established_base_ids`, `_established_base_records`, `mark_base_established_at`, `has_established_base`, `get_established_base_*` | **GameSession** records; **BaseStore** holds economy row | Colonization, `system_ui_controller`, automation | **High** — fake “base” vs established mismatch |
| 4 | **Base resources / units / storage** | `get_base_resource_amount`, `add_base_resource`, `spend_base_resource`, unit counts, storage used/cap/free, survey probe inventory | **BaseStore** | UI panels, automation mining unload, sensor pulse | **High** — dup spend / lost cargo |
| 5 | **Production gates / build** | `get_build_base_*_gate`, `build_base_*`, `get_production_cost`, `get_survey_probe_build_*` | **BaseStore** + `production_catalog` / balance | `production_panel.gd` | **High** — build without cost |
| 6 | **Upgrade gates / purchase** | `get_buy_next_base_upgrade_gate`, `buy_next_base_upgrade`, `get_*_upgrade_definition`, derived multipliers (`get_scan_drone_*_multiplier`, …) | **BaseStore** + `upgrade_catalog` | `upgrade_panel.gd`, `automation_controller` | **High** — stats not refreshed |
| 7 | **Object discovery facade** | `set/get_object_discovery_state`, `is_object_*`, `ensure_default_discovery_for_system`, `_seed_discovery_from_system_definition` | **ObjectScanStore** | `system_discovery_controller`, sensor pulse, survey probe | **High** — discovery/scan confusion |
| 8 | **Object scan state facade** | `set/get_object_scan_state`, `get_next_scan_target_state`, `scan_state_rank`, layer helpers | **ObjectScanStore** | Scan gates, automation scan complete, object info | **High** — double scan / wrong layer |
| 9 | **remaining_resources / mining extraction** | `ensure_object_resources_initialized`, `extract_resource_amount`, `get_remaining_resource_amount`, `object_remaining_resources_changed` | **ObjectScanStore** | `automation_controller` mining tick, object info UI | **High** — dup depletion / regen |
| 10 | **AutomationStore facade** | `create_scan_mission`, `create_mining_mission`, `complete_automation_mission`, `get_automation_mission`; `automation` store reference | **AutomationStore** | `automation_controller` | **Medium** — orphan mission records |
| 11 | **Colonization operations** | `_colonization_operations`, `start/complete/cancel_colonization_operation`, `process_colonization_operations`, `establish_base_at_body` | **GameSession** | `galaxy_map_hud.gd`, galaxy map | **High** — double establish / lost ships |
| 12 | **Save/load serialization** | `to_save_data`, `apply_save_data`, `reset_for_new_game`, `_apply_automation_from_save_data`, `_apply_camera_state_from_save_data` | **GameSession** orchestrates stores | `SaveManager`, main menu | **Critical** |
| 13 | **Camera snapshot buffer** | `_camera_state_pending`, `refresh_camera_snapshot_from_scene`, `take_camera_state_pending`, `has_camera_state_pending_for_system` | **GameSession** buffer; live from `SystemCameraController` | `system_scene.gd` | **Medium** — wrong camera after load |
| 14 | **Automation runtime pending** | `_automation_runtime_pending`, `refresh_automation_snapshot_from_scene`, `take_automation_runtime_pending` | **GameSession** buffer; live from `AutomationController.to_save_data()` | `SaveManager` pre-save, `system_scene` load | **Medium** — empty runtime on load |
| 15 | **Resource catalog read facade** | `_load_resource_catalog`, `get_resource_display_name`, `get_resource_short_label`, `get_storage_resource_ids_sorted` | **ResourceCatalogDefinition** `.tres` | Storage/upgrade/object info panels | **Low** — display only |
| 16 | **UI signals / event bus** | `base_resources_changed`, `base_upgrades_changed`, `galaxy_progression_changed`, `object_remaining_resources_changed`, `established_body_discovery_visual_refresh_requested` | Emitted from GameSession after store ops | Many UI/controllers | **High** — silent UI if not emitted |
| 17 | **Pre-save cancel/refund** | `cancel_active_survey_probe_missions_before_save`, `cancel_active_base_sensor_pulse_before_save` | Scene tree lookup → controllers | `SaveManager.build_save_data` | **Medium** — wrong save state |

**Direct store access (facade leak):** Some callers use `GameSession.bases.*` directly (e.g. `survey_probe_mission_controller`, `base_sensor_pulse_controller` → `bases.consume_survey_probe`, `bases.spend_cost`). Any split must **not** break these paths until an explicit migration.

---

## Current Data Ownership

| Data | True owner today | GameSession role | Should move later? | Risk |
|------|------------------|------------------|-------------------|------|
| Base resources, units, upgrades, production build state | **BaseStore** (`bases.bases`) | Delegate + signal emit | Facade only; **never duplicate** | High |
| Object discovery states | **ObjectScanStore** | Pass-through + system seeding | Internal **ObjectProgressionFacade** | High |
| Object scan states | **ObjectScanStore** | Pass-through + scan progression helpers | Same facade | High |
| `remaining_resources_by_object` | **ObjectScanStore** | Init/extract/deplete APIs | Same facade | High |
| Automation mission records | **AutomationStore** (`automation.missions`) | Create/complete wrappers | Stay store; optional thin facade | Medium |
| Automation runtime snapshot | **AutomationController** live; **pending dict** on GameSession | Buffer + pre-save capture | Pending buffer may move to **SaveSessionService** | Medium |
| `current_system_id` / loaded definition | **GameSession** | Session identity | **SessionStateService** (internal) | High |
| `discovered_system_ids` / `unlocked_system_ids` | **GameSession** (saved) | Galaxy progression | **GalaxyProgressionService** (internal) | Medium |
| `established_base_records` | **GameSession** (saved) | Geography + membership | Stay session until colonization service design | High |
| Colonization operations | **GameSession** (saved) | Ops + timers | **ColonizationService** (later) | High |
| Camera pending state | **GameSession** buffer | Save/load handoff | **SaveSessionService** (later) | Medium |
| Resource catalog metadata | **`resource_catalog.tres`** | Read facade | **ResourceCatalogFacade** | Low |
| Upgrade/production definitions | **Catalog `.tres`** + loaders on GameSession | Cached refs | Stay loaded once on session boot | Low |
| Scanner tier (legacy helper) | **ScannerStore** | `scanner` reference | Low priority | Low |

---

## Public API / External Callers

**Stability rule:** Anything called from outside `game_session.gd` is **public API** until a documented migration removes it. Signals are **public API** (same as methods).

### Session / galaxy / travel

| API / state | Called by (examples) | Purpose | Must remain stable? | Notes |
|-------------|----------------------|---------|----------------------|-------|
| `current_system_id` | Automation, system scene, UI, save metadata | Active system key | **Yes** | Copied to top-level save metadata |
| `current_system_definition` | `system_discovery_controller`, `system_scene` | Loaded `SystemDefinition` | **Yes** | Cleared during `apply_save_data` then reloaded |
| `set_current_system` / `ensure_default_system_loaded` | `system_scene.gd` | Bind scene to definition | **Yes** | |
| `stage_system_entry` / `consume_selected_system_definition` / `consume_travel_entry_flag` | Galaxy → system travel | Staged entry | **Yes** | |
| `discover_system` / `unlock_system` / `can_enter_system` | `galaxy_map.gd` | Progression | **Yes** | |
| `reset_for_new_game()` | Main menu / new game flow | Fresh session | **Yes** | Not named `new_game` in code |
| `get_system_definition_by_id` / `get_system_display_name` | Galaxy UI | Display | **Yes** | |

### Save / load

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `to_save_data()` | `SaveManager.build_save_data` | `game_session` JSON section | **Yes** | Shape in `save_schema_v1.md` |
| `apply_save_data()` | `SaveManager.load_game` | Restore session | **Yes** | Fixed order inside function |
| `refresh_automation_snapshot_from_scene()` | `SaveManager` pre-save | Fill pending runtime | **Yes** | |
| `refresh_camera_snapshot_from_scene()` | `SaveManager` pre-save | Fill pending camera | **Yes** | |
| `take_automation_runtime_pending()` / `has_automation_runtime_pending()` | `system_scene`, `AutomationController` | Load handoff | **Yes** | |
| `take_camera_state_pending()` / `has_camera_state_pending_for_system()` | `system_scene` | Camera restore | **Yes** | |
| `cancel_active_survey_probe_missions_before_save()` | `SaveManager` | Pre-save step 1 | **Yes** | |
| `cancel_active_base_sensor_pulse_before_save()` | `SaveManager` | Pre-save step 2 | **Yes** | |

### Base economy

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `get_base_resource_amount` / `get_base_resources` | UI, automation | Read storage | **Yes** | |
| `add_base_resource` | Automation unload, scan reward, sensor refund | Add with signal | **Yes** | |
| `spend_base_resource` | Various | Spend with signal | **Yes** | |
| `get_base_storage_*` / `get_base_storage_blocked_reason_full` | Automation, UI | Capacity gates | **Yes** | |
| `get_base_drone_count` / `mining_ship` / `colony_ship` / survey probes | Automation, UI | Unit inventory | **Yes** | |
| `GameSession.bases.spend_cost` / `can_afford` | `base_sensor_pulse_controller` | Direct store | **Yes** (leak) | Prefer facade later, not now |

### Production / upgrade

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `get_build_base_*_gate` / `build_base_*` | `production_panel.gd` | Build units | **Yes** | |
| `get_buy_next_base_upgrade_gate` / `buy_next_base_upgrade` | `upgrade_panel.gd` | Upgrades | **Yes** | |
| `get_*_upgrade_definition` / `has_next_base_upgrade` | Upgrade UI | Display | **Yes** | |
| Derived multipliers (`get_scan_drone_*`, `get_mining_ship_*`, …) | `automation_controller` | Gameplay stats | **Yes** | |

### Discovery / scan / mine

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `set_object_discovery_state` / `get_object_discovery_state` | Discovery, survey, sensor pulse | Discovery FSM | **Yes** | |
| `set_object_scan_state` / `get_object_scan_state` | Automation scan complete | Scan tier | **Yes** | |
| `ensure_default_discovery_for_system` | `system_scene` | Seed on enter | **Yes** | |
| `can_scan_object` | `automation_controller`, UI | Scan gate | **Yes** | Does not launch drone |
| `can_mine_object` | UI, automation | Mine gate | **Yes** | |
| `get_scan_target_state_or_rescan_state` / `get_scan_duration_seconds_for_target_state` | Automation | Scan mission params | **Yes** | |
| `grant_scan_survey_data_reward` | Automation on scan complete | Reward | **Yes** | SurveyData currency |
| `extract_resource_amount` / `get_remaining_resource_amount` / `ensure_mining_resources_for_object` | Automation mining | Depletion | **Yes** | |
| `SCAN_*` / `DISCOVERY_*` const aliases | Widespread | Store constants | **Yes** | |

### Automation records

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `create_scan_mission` / `complete_automation_mission` | `automation_controller` | Store records | **Yes** | Runtime still on controller |
| `automation` (store ref) | Controller restore | Direct store access | **Yes** | Tight coupling |

### Colonization / establish base

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `start_colonization_operation` / `complete_*` / `cancel_*` | Galaxy HUD / map | Colony ship ops | **Yes** | |
| `process_colonization_operations` | Galaxy HUD tick | Auto-complete | **Yes** | |
| `establish_base_at_body` / `mark_base_established_at` | Colonization complete | New base | **Yes** | Triggers discovery sync |
| `has_established_base_in_system` / `get_established_base_id_for_system` | Galaxy UI, sensor pulse | Status | **Yes** | |

### Resource catalog / balance / gates text

| API | Called by | Purpose | Stable? | Notes |
|-----|-----------|---------|---------|-------|
| `get_resource_display_name` / `get_resource_short_label` | UI panels, `scan_info_builder` | UI labels only | **Yes** | Not amounts |
| `get_gate_text` / `get_gate_ui_texts` | UI | Block reasons | **Yes** | |
| `get_game_balance()` | Controllers | Balance profile | **Yes** | |

### Signals

| Signal | Listeners (examples) | Purpose | Stable? | Notes |
|--------|----------------------|---------|---------|-------|
| `base_resources_changed(base_id)` | `top_hud`, `storage_panel`, `production_panel`, `upgrade_panel`, `base_management_panel`, automation | Storage/units changed | **Yes** | Must fire after spend/add |
| `base_upgrades_changed(base_id)` | `upgrade_panel` | Upgrade level changed | **Yes** | |
| `galaxy_progression_changed()` | `galaxy_map.gd` | Discovered/unlocked lists | **Yes** | Also after load |
| `object_remaining_resources_changed(system_id, object_id)` | `object_info_panel`, `system_ui_controller` | Deposit depletion UI | **Yes** | |
| `established_body_discovery_visual_refresh_requested(system_id, body_id)` | `system_ui_controller` | Colony establish visual | **Yes** | Runtime-only refresh hook |

**Approximate call volume:** `automation_controller.gd` (~90+ references), `system_ui_controller.gd` (~48), `galaxy_map.gd` (~48), UI panels (~11–31 each) — facade stability is **project-critical**.

---

## Non-Goals

- **No code split in Phase 3.7** — this document only.
- **No Save-v2** or `active_missions` implementation.
- **No store schema changes** (`BaseStore`, `ObjectScanStore`, `AutomationStore` on-disk shapes).
- **No resource ID changes** (including SurveyData; no `survey_data.tres` planet resource).
- **No production / upgrade / colonization rule changes**.
- **No automation restore changes** (remains `AutomationController` + pending buffer).
- **No signal renames or Autoload registration changes**.
- **No UI panel refactors** or NodePath changes.
- **No `tooltip_text`** (project policy: **0** in `*.gd` / `*.tscn` / `*.tres`).

---

## Proposed Future Facades / Services

All services below are **design targets**. They would be **`RefCounted` or private helpers** owned by `GameSession` until a deliberate **public API migration** exists. **GameSession remains the Autoload name and entry point.**

### 1. SessionStateService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/session_state_service.gd` |
| **May contain** | `current_system_id`, `current_system_definition` load/cache, `set_current_system`, `ensure_default_system_loaded`, `get_system_definition_by_id`, staged entry consumption |
| **Must not contain** | Base resources, scan gates, save serialization, colonization |
| **Inputs** | `res://data/galaxy_systems/*.tres` catalog |
| **Outputs** | Active `SystemDefinition` for scenes |
| **Risk** | **High** if system load order changes |

### 2. GalaxyProgressionService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/galaxy_progression_service.gd` |
| **May contain** | `discovered_system_ids`, `unlocked_system_ids`, discover/unlock/enter rules, save slice for galaxy fields |
| **Must not contain** | Colonization ops, base establish side effects |
| **Inputs** | `GameStartDefinition` seed data |
| **Outputs** | Progression lists; emits via GameSession → `galaxy_progression_changed` |
| **Risk** | **Medium** — map access / save list mismatch |

### 3. BaseEconomyFacade

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/base_economy_facade.gd` |
| **May contain** | Wrap `BaseStore` get/add/spend/remove, storage queries, unit counts, survey probe inventory helpers |
| **Must not contain** | Scan/mine gates, colonization, automation missions |
| **Inputs** | `BaseStore` reference |
| **Outputs** | Amounts; triggers `base_resources_changed` on GameSession |
| **Risk** | **High** — duplicated spend or missing signals |

### 4. ProductionService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/production_service.gd` |
| **May contain** | `get_build_base_*_gate`, `build_base_*`, production cost resolution from `production_catalog` / balance |
| **Must not contain** | Upgrade purchase, mining extraction |
| **Inputs** | `BaseStore`, `ProductionCatalog`, gate texts |
| **Outputs** | Gate dicts; bool build success |
| **Risk** | **Medium** — build without affordability |

### 5. UpgradeService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/upgrade_service.gd` |
| **May contain** | `get_buy_next_base_upgrade_gate`, `buy_next_base_upgrade`, definition lookups, derived stat multipliers exposed to automation |
| **Must not contain** | Production build, object scan writes |
| **Inputs** | `BaseStore`, `UpgradeCatalog` |
| **Outputs** | Gate dicts; `base_upgrades_changed` via facade |
| **Risk** | **Medium–high** — stats not applied to units |

### 6. ScanMineGateService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/scan_mine_gate_service.gd` |
| **May contain** | `can_scan_object`, `can_mine_object`, scan target state helpers, blocked reason keys |
| **Must not contain** | Launching drones/ships, `AutomationStore` mutation, reward grant |
| **Inputs** | Object scan/discovery state, base layers, idle unit flags from caller |
| **Outputs** | Gate dictionaries for UI/automation |
| **Risk** | **Medium** — wrong layer / duplicate scan |

### 7. ObjectProgressionFacade

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/object_progression_facade.gd` |
| **May contain** | Discovery/scan getters/setters, `ensure_default_discovery_for_system`, resource init, `extract_resource_amount`, depletion checks |
| **Must not contain** | Automation unit motion, colonization establish |
| **Inputs** | `ObjectScanStore`, `SystemDefinition` bodies/POIs |
| **Outputs** | Store mutations; `object_remaining_resources_changed` via GameSession |
| **Risk** | **High** — discovery vs scan vs `remaining_resources` mixed |

### 8. ColonizationService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/colonization_service.gd` |
| **May contain** | Operation CRUD, timer tick conversion save/load, `establish_base_at_body` orchestration |
| **Must not contain** | Generic base economy (delegate to BaseEconomyFacade) |
| **Inputs** | `ColonizationDefinition`, established base records, colony ships on bases |
| **Outputs** | Ops dict; calls establish + discovery refresh signal |
| **Risk** | **High** — double complete, wrong base geography |

### 9. SaveSessionService

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/save_session_service.gd` |
| **May contain** | `to_save_data` / `apply_save_data` **orchestration** (not store logic), pending automation/camera buffers, colonization save array conversion |
| **Must not contain** | Gameplay policy changes, Save-v2 fields |
| **Inputs** | All stores + session slices + scene snapshot callables |
| **Outputs** | `game_session` dict per `save_schema_v1.md` |
| **Risk** | **Critical** — load order regression |

### 10. ResourceCatalogFacade

| Item | Detail |
|------|--------|
| **Possible file** | `scripts/session/resource_catalog_facade.gd` |
| **May contain** | `get_resource_display_name`, short label, sort order, definition lookup |
| **Must not contain** | Amounts, costs, affordability, store mutation |
| **Inputs** | `resource_catalog.tres` |
| **Outputs** | Display strings only |
| **Risk** | **Low** |

---

## What Must Stay on GameSession Initially

Until a written **API migration plan** exists:

| Must stay | Reason |
|-----------|--------|
| **Autoload name `GameSession`** | Hundreds of call sites |
| **Public method signatures** | UI + controllers compile against them |
| **Public store references** (`bases`, `object_scans`, `automation`, …) | Direct access in places |
| **All signals on GameSession** | UI connections |
| **`to_save_data` / `apply_save_data` entry points** | `SaveManager` contract |
| **Pre-save hook method names** | `SaveManager.build_save_data` order |
| **Const aliases** (`SCAN_*`, `DISCOVERY_*`, `START_SYSTEM_ID`) | Widespread |

Internal services (when implemented) should be **`var _foo_service` + thin delegates** — same pattern as Phase 3.6 `AutomationAudioService` / `AutomationSaveService` on `AutomationController`.

---

## Dangerous Couplings

| Coupling | Why dangerous |
|----------|----------------|
| **SaveManager pre-save order → snapshots → `to_save_data`** | Skipping or reordering steps changes on-disk semantics |
| **`apply_save_data` internal order** | Stores → discovery sync → automation pending → reload system def → mass signal emit |
| **BaseStore upgrade levels → derived fields** | `_refresh_all_base_upgrade_derived_fields` after load; automation reapply |
| **ObjectScanStore: discovery vs scan vs `remaining_resources`** | Wrong helper order → hidden objects with deposits or vice versa |
| **AutomationStore records vs Controller runtime** | Pending buffer must match store mission ids on load |
| **Colonization complete → `establish_base_at_body` → discovery KNOWN + visual signal** | Double emit / wrong body id breaks map and object info |
| **ResourceCatalog vs economy IDs** | Display-only; must never become spend authority |
| **Signals as UI bus** | Forgetting emit after internal delegate = frozen UI |
| **Scene tree search for pre-save** | `SurveyProbeMissionController` / `BaseSensorPulseController` must exist in tree at save time |
| **`current_system_definition` null during load** | `apply_save_data` clears then reloads; scenes must not assume def mid-apply |
| **Established base vs `BaseStore.get_base` placeholder** | `_established_base_ids` is truth for “real base”; store auto-insert ≠ established |

**Do not spontaneously move:** colonization establish, `apply_save_data`, mining extraction, or automation pending without a test matrix and save baselines.

---

## Suggested Extraction Order

**Phase 3.7 = this plan only.** Implementation follows Phase 3.6 pattern.

| Step | Deliverable | Risk | Notes |
|------|-------------|------|-------|
| **1** | **GameSession Function Map** (`game_session_function_map_v0_1.md`) | None | Line ranges, API table, signal map, store ownership — **no code** |
| **2** | **ResourceCatalogFacade** (internal delegate) | **Low** | Read-only; aligns with `resource_definition_catalog_design_v0_1.md` |
| **3** | **GalaxyProgressionService** (design + optional internal helper) | **Low–medium** | No save schema change |
| **4** | **ProductionService / UpgradeService** — **gate calculation only** first | **Medium** | No spend/build move until gates proven identical |
| **5** | **BaseEconomyFacade** | **Medium–high** | Preserve signals; migrate `GameSession.bases.*` leaks slowly |
| **6** | **ObjectProgressionFacade** | **High** | Requires discovery/scan/mining regression suite |
| **7** | **ColonizationService** | **High** | Depends on established-base model |
| **8** | **SaveSessionService** | **Critical** | Only after `save_schema_v1` stable and Save-v2 design reviewed; coordinate with AutomationSaveService Phase B **design**, not rushed merge |

### Do not extract first

- **SaveSessionService** (orchestration too early)
- **ColonizationService**
- **ObjectProgressionFacade**
- **BaseEconomyFacade** spend/build paths before gates

### Parallel / related work (not Phase 3.7)

- **AutomationSaveService Phase B** — restore extraction; separate plan, **design before code** (`automation_save_service_extraction_plan_v0_1.md`)
- **AutomationController** further splits — per `automation_controller_split_plan_v0_1.md`, independent track

---

## Save/Load Constraints

From `docs/save_schema_v1.md` (v1 active, frozen for Phase 3.7):

| Constraint | Detail |
|------------|--------|
| **`SAVE_VERSION`** | Stays **1** — no bump |
| **`game_session` shape** | Fields: `current_system_id`, `discovered_system_ids`, `unlocked_system_ids`, `established_base_records`, `colonization_operations`, `next_colonization_operation_id`, `bases`, `object_scans`, `automation`, `camera_state` |
| **No Save-v2** | No `active_missions` in v1 |
| **Pre-save order** (fixed) | 1) `cancel_active_survey_probe_missions_before_save` → 2) `cancel_active_base_sensor_pulse_before_save` → 3) `refresh_automation_snapshot_from_scene` → 4) `refresh_camera_snapshot_from_scene` → 5) `GameSession.to_save_data()` |
| **`apply_save_data` order** | Session fields → colonization → `bases.apply_save_data` → `object_scans.apply_save_data` → discovery sync → automation pending → camera pending → reload system definition → signals |
| **`current_system_id` loader** | Empty → `START_SYSTEM_ID` (`solar-system`) |
| **Automation block** | `{ "store": AutomationStore, "runtime": pending snapshot }` — runtime write path now via `AutomationSaveService` on controller; **shape unchanged** |

Any GameSession split must preserve **byte-/schema-compatible** `game_session` objects for existing saves.

---

## Signal Constraints

| Rule | Detail |
|------|--------|
| **Signals = public API** | Same stability as methods |
| **No renames** without migration window and repo-wide search |
| **Internal services must not own UI signals** initially | `GameSession` re-emits after delegate |
| **Load must re-fire** | `apply_save_data` ends with `galaxy_progression_changed` + per-base resource/upgrade signals |
| **Per-object signals** | `object_remaining_resources_changed`, `established_body_discovery_visual_refresh_requested` stay on GameSession |

---

## Store Constraints

| Store | Role | GameSession rule |
|-------|------|------------------|
| **BaseStore** | Base resources, units, upgrades, production builds | Facade may wrap; **do not duplicate** `bases` dict elsewhere |
| **ObjectScanStore** | Discovery, scan state, remaining resources | Facade only; seeding stays coordinated with `SystemDefinition` |
| **AutomationStore** | Logical scan/mine mission records | Facade wrappers today; runtime separate |
| **ScannerStore** | Legacy scanner tier helper | Low priority; keep reference stable |
| **SystemEntryStore** | Travel entry staging | Small; likely stays near session state |

**Forbidden:** Copying store dictionaries into parallel session fields “for convenience” — causes desync on load.

---

## Resource ID Constraints

| Rule | Detail |
|------|--------|
| **IDs frozen** | `Iron`, `Copper`, `SurveyData`, etc. — used in saves and `.tres` costs |
| **ResourceCatalog** | UI metadata only (`resource_catalog.tres`) |
| **SurveyData** | Base/info currency via `GameBalanceDefinition` — **not** a planet deposit resource |
| **No new `data/planet_resources/survey_data.tres`** | Per project policy |
| **Display helpers** | `get_resource_display_name` must not change ID strings used as keys |

---

## Risk Matrix

| Risk | Severity | Mitigation |
|------|----------|------------|
| Save schema broken | **Critical** | No field renames; SaveSessionService last; diff against `save_schema_v1.md` |
| Signals not emitted | **High** | Delegate pattern: service returns change set → GameSession emits |
| UI stale after load | **High** | Keep post-load signal burst in `apply_save_data` |
| Resource spend duplicated | **High** | Single path through BaseStore; tests for sensor pulse refund |
| Production build bypasses gate | **High** | Gate-only extract before moving `build_*` |
| Upgrade stats not refreshed | **High** | Call `_refresh_all_base_upgrade_derived_fields` / controller reapply unchanged |
| Discovery and scan mixed | **High** | ObjectProgressionFacade with explicit sub-APIs |
| `remaining_resources` reinitialized wrong | **High** | Never split `ensure_object_resources_initialized` without mining tests |
| Colonization completes twice | **High** | Idempotent complete; save op status |
| Automation mission orphaned | **Medium** | Store + pending buffer applied together |
| `current_system_definition` null/mismatch | **High** | Reload after apply; system scene guards |
| Old saves fail load | **Critical** | Load golden saves each milestone |
| Facade leak (`GameSession.bases.*`) | **Medium** | Document in function map; migrate deliberately |

---

## Test Matrix Before Any Implementation

Manual / editor checklist for any future GameSession extraction step:

| Test | Validates |
|------|-----------|
| New Game (`reset_for_new_game`) | Start resources, earth base, progression seed |
| Save/load idle | Empty runtime, camera, stores |
| Save/load after base established | Established records + discovery sync |
| Resource add/spend/build | Signals + storage |
| Production build (survey probe, scan drone, mining ship, colony ship gates) | Gates + costs |
| Upgrade purchase + derived stats | Automation reapply |
| Scan gate + scan mission + survey reward | No duplicate SurveyData |
| Mine gate + mining + storage full | Cargo unload / WAITING_FOR_STORAGE |
| Sensor Pulse | Cost, refund on pre-save cancel |
| SurveyProbe Investigate | Consume/refund probe, KNOWN state |
| Colonization start/complete | Establish base, galaxy state |
| Galaxy enter/access | unlocked/discovered |
| ResourceCatalog labels | Display only, IDs unchanged |
| Automation save/load | Store + runtime pending (Phase 3.6 baselines) |
| Camera save/load | Position/zoom |
| `tooltip_text` grep | **0** |

---

## Do Not Touch (without explicit phase)

- `SaveManager.SAVE_VERSION` and top-level save wrapper
- `game_session` JSON field names and types
- Store internal shapes (`BaseStore`, `ObjectScanStore`, `AutomationStore`)
- Resource IDs and deposit `.tres` semantics
- Signal names and Autoload registration
- External `GameSession.*` call sites (until migration doc)
- Scene NodePaths and UI panel scripts
- `AutomationController` restore path
- `data/planet_resources/survey_data.tres` (do not create)

---

## Recommended First Implementation Prompt

**Create the GameSession Function Map document only** — no code changes.

```
Create docs/architecture/game_session_function_map_v0_1.md:
- Read-only audit of scripts/autoload/game_session.gd (~2659 lines).
- Sections: line-range responsibility map, public API table (method → callers),
  signal table (signal → listeners), store ownership map, pre-save/save/load
  order diagram, direct GameSession.bases.* leak list.
- Reference docs/save_schema_v1.md for serialized fields.
- No implementation. No ResourceCatalogFacade extraction yet.
```

This mirrors Phase 3.6 Step 2 (AutomationController function map) and is the **only** recommended next step for Phase 3.7.

**Do not** start `ResourceCatalogFacade` code extraction until the function map is reviewed.

---

## Acceptance (this document)

1. Only `docs/architecture/game_session_split_plan_v0_1.md` was created.  
2. No code, scene, or data files were changed.  
3. Current GameSession responsibilities are described.  
4. Future facades/services are proposed with boundaries.  
5. GameSession remains the public Autoload facade.  
6. Save, signal, store, and resource-ID constraints are documented.  
7. Risk matrix and test matrix are included.  
8. Exactly one small next step: **GameSession Function Map** (read-only).
