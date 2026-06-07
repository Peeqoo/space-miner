# Base Panel Unload + Production/Orbit Limits Audit v0.1

**Date:** 2026-06-07  
**Scope:** Read-only audit — Problem A (BaseManagementPanel auto-open on MiningShip unload), Problem B (remaining production limits), Problem C (object-orbit / same-target limits).  
**Godot:** 4.6.1 / strictly typed GDScript codebase.  
**No code, scene, or data changes in this audit.**

---

## Summary

| Area | Verdict | Notes |
|------|---------|-------|
| **Overall** | **FINDINGS** | One confirmed UX bug (panel auto-open). Production **build** caps for SD/MS removed (Step 2a/2b). Runtime investigate/scan caps remain by design. Multi-MS same target already supported. |
| **BaseManagementPanel auto-open** | **FAIL** | `SystemUIController.update_base_panel()` re-opens panel on `base_resources_changed` / `automation_state_changed` when a base `SystemBody` is selected — includes MiningShip unload. |
| **Remaining production limits** | **PASS (build)** / **FINDINGS (runtime)** | SD/MS/SP **build** not capped by `max_count`. Stale limit **text keys** remain in data. SP **investigate** still has per-signal + global parallel caps. CS gated by prereqs/cost. |
| **Object / orbit limits** | **MIXED** | Multi-MS same object: **allowed**. Multi-SD same object: **blocked** (`KEY_SCAN_ALREADY_IN_PROGRESS`). SP investigate: **1 active per signal**. No hard orbit-slot cap in `AutomationUnit`. |

### Root cause candidate — BaseManagementPanel auto-open

**Primary:** `SystemUIController._on_base_resources_changed_ui_refresh()` and `_on_automation_state_changed()` both call `update_base_panel()`. That function **always** calls `BaseManagementPanel.show_for_base()` (sets `visible = true`, `_hold_open_across_selections = true`) when the current selection is a `SystemBody` with an established base — **without checking whether the panel was previously closed by the player**.

**Trigger chain for MiningShip unload:**

1. `AutomationController._unload_greedy_into_base_until_full()` → `GameSession.add_base_resource()`  
2. `GameSession.base_resources_changed.emit(base_id)`  
3. `SystemUIController._on_base_resources_changed_ui_refresh()` → `update_base_panel()` → `show_for_base()` if Earth/base body selected  

**Secondary (same symptom):** During unload, mining runtime updates schedule `automation_state_changed` via `_request_automation_state_changed()` → `_on_automation_state_changed()` → `update_base_panel()` → same open path.

**Not the cause:** `BaseManagementPanel._on_game_session_base_resources_changed()` only calls `refresh_from_game_session()` when `visible` is already true — correct refresh-only behavior.

---

## BaseManagementPanel Auto-Open Trace

| Signal / caller | Target method | Opens panel? | Should be refresh-only? | File | Risk |
|-----------------|---------------|--------------|-------------------------|------|------|
| Player selects base `SystemBody` | `SystemUIController._on_selection_changed()` → `update_base_panel()` → `show_for_base()` | **Yes** | **No** (explicit open OK) | `system_ui_controller.gd` | Low |
| `GameSession.base_resources_changed` | `SystemUIController._on_base_resources_changed_ui_refresh()` → `update_base_panel()` → `show_for_base()` if base body selected | **Yes** | **Yes** | `system_ui_controller.gd` | **High** — unload, build, any resource add |
| `AutomationController.automation_state_changed` | `SystemUIController._on_automation_state_changed()` → `update_base_panel()` | **Yes** (if base selected) | **Yes** | `system_ui_controller.gd` | **High** — mining unload ticks |
| `GameSession.base_upgrades_changed` | `_on_base_upgrades_changed_ui_refresh()` → `update_base_panel()` | **Yes** (if base selected) | **Yes** | `system_ui_controller.gd` | Medium |
| Survey probe mission events | `_on_survey_probe_mission_changed()` → `update_base_panel()` | **Yes** (if base selected) | **Yes** | `system_ui_controller.gd` | Medium |
| Investigate start (failure path) | `_on_investigate_requested` tail → `update_base_panel()` | **Yes** (if base selected) | **Yes** | `system_ui_controller.gd` | Low |
| `GameSession.base_resources_changed` | `BaseManagementPanel._on_game_session_base_resources_changed()` → `refresh_from_game_session()` | **No** (only if already visible) | **Yes** | `base_management_panel.gd` | Low — correct |
| `GameSession.base_resources_changed` | `SystemUIController._refresh_economy_panels()` → `base_management_panel.refresh_from_game_session()` if visible | **No** | **Yes** | `system_ui_controller.gd` | Low — correct |
| `show_for_base()` | Sets `visible = true`, `_hold_open_across_selections = true` | **Yes** | N/A (open API) | `base_management_panel.gd` | — |
| `refresh_from_game_session()` / `refresh_while_hold_open()` | Updates labels only; `hide_panel()` if invalid base | **No** | **Yes** | `base_management_panel.gd` | Low |
| `hide_panel()` / Close button | `visible = false`, clears hold flag | Closes | N/A | `base_management_panel.gd` | — |
| Init `update_all()` | `update_base_panel()` on scene start | **Yes** if base pre-selected | Debatable | `system_ui_controller.gd` | Low |

**Open API surface:** Only `BaseManagementPanel.show_for_base()` sets `visible = true`. No `popup()`, no separate `open_management` helper.

**Refresh-only listeners (correct):** `TopHUD._on_resources_changed`, `StoragePanel._on_game_session_base_resources_changed`, `ProductionPanel._on_resources_changed`, `UpgradePanel._on_resources_changed` — all gate on `visible` and refresh content only.

---

## MiningShip Unload Signal Flow

| Step | AutomationController / GameSession | Emitted signal | UI listener | Effect |
|------|-----------------------------------|----------------|-------------|--------|
| 1 | `UNLOADING` state tick; `_unload_greedy_into_base_until_full()` | — | — | Per-resource transfer loop |
| 2 | `GameSession.add_base_resource(base_id, rid, amount)` | `base_resources_changed(base_id)` | `SystemUIController._on_base_resources_changed_ui_refresh` | **`update_base_panel()` → may open BaseManagementPanel** |
| 2b | Same signal | `base_resources_changed` | `BaseManagementPanel._on_game_session_base_resources_changed` | Refresh labels **only if panel already visible** |
| 2c | Same signal | `base_resources_changed` | `SystemUIController._refresh_economy_panels` | Refresh Production/Upgrade/Storage/Base panel **if visible** |
| 2d | Same signal | `base_resources_changed` | `TopHUD._on_resources_changed` | Storage/unit counts update |
| 3 | Runtime state updates during unload | `automation_state_changed` (deferred) | `SystemUIController._on_automation_state_changed` | **`update_base_panel()` again** + object info + economy panels + TopHUD |
| 4 | Cargo emptied; status → `TO_TARGET` or `WAITING_FOR_STORAGE` | `automation_state_changed` | Same | Same open risk |
| 5 | Storage full path | `add_base_resource` partial accept | `base_resources_changed` | Same |

**Unload does not call any panel `show()` directly.** The bug is indirect: economy refresh handlers reuse the **selection-open** code path.

---

## Production Limit Audit

| Unit | Build cap still active? | Gate key (build) | UI text / disabled | Telemetry field | Recommendation |
|------|-------------------------|------------------|--------------------|-----------------|----------------|
| **ScanDrone** | **No** | `KEY_BUILD_NOT_ENOUGH_RESOURCES` only (`BaseStore.get_build_scan_drone_blocked_reason_key`) | `ProductionPanel` disables on gate `ok` — no limit-specific branch | `max_count` + `hard_limit_removed_for_build: true` in `balance_telemetry_logger.gd` | Remove stale limit strings from player-facing path when touched; keep `get_max_scan_drone_count()` telemetry-only or deprecate |
| **MiningShip** | **No** | Same pattern | Same | Same | Same |
| **SurveyProbe** | **No build cap** (never had `KEY_BUILD_SURVEY_PROBE_LIMIT`) | `KEY_BUILD_NOT_ENOUGH_RESOURCES` + scaled cost | Same | Scaled cost in gates/investigate | No build change needed |
| **SurveyProbe investigate** | **Yes (runtime)** | `REASON_IN_PROGRESS` (per object), `REASON_ACTIVE_PROBE_LIMIT` (global `max_active_probes_start` = 2) | `ObjectInfoPanel` investigate button via `can_investigate_signal` | `investigate` snapshot | **Intentional** per design — do not remove per-signal rule; global cap is separate product decision |
| **ColonyShip** | **No fleet cap**; gated by prereqs + flat cost | `KEY_COLONY_*` family | Colony button + prereq list in hover | `scaling_excluded: true` | Unchanged — correct special case |

### Stale limit artifacts (not emitted by gameplay gates today)

| Artifact | Location | Still reachable in gameplay? |
|----------|----------|----------------------------|
| `KEY_BUILD_SCAN_DRONE_LIMIT` | `gate_ui_text_definition.gd`, `data/ui_text/gate_ui_texts.tres` | **No** — not returned by `BaseStore` build gates after Step 2a |
| `KEY_BUILD_MINING_SHIP_LIMIT` | Same | **No** |
| `get_max_scan_drone_count()` / `get_max_mining_ship_count()` | `base_store.gd`, `game_session.gd` | **Telemetry / diagnostics only** — not used in build gates |
| `max_scan_drones_start` / `max_mining_ships_start` | `game_balance_definition.gd`, `v0_1_balance.tres` | Balance data still defines 2; **not enforced on build** |
| `max_active_probes_start` | balance + `survey_probe_mission_controller.gd` | **Yes** — investigate parallel cap |

**Scaling:** SD/MS/SP build spend uses `GameSession.get_scaled_production_cost()` (Step 2b). ColonyShip flat + excluded.

---

## ObjectOrbit / Same Target Audit

| Unit type | Multiple units same object now? | Blocking function / key | Runtime risk | Save risk | Recommendation |
|-----------|--------------------------------|-------------------------|--------------|-----------|----------------|
| **MiningShip** | **Yes** | None for “already mining”. `can_mine_object()` only checks idle ship, scan state, depletion, resources. `launch_mining_ship()` does not inspect existing assignments. | Multiple ships share `remaining_resources` via `GameSession.extract_resource_amount()` — race/depletion OK at data layer. UI may show `assigned_mining_ship_count` > 1. | `mining_ship_runtime_by_unit_id` keyed by **unit_id** (not unique per target). Save restore supports multiple runtimes per `target_id`. | **No block to remove.** Optional UX: show assigned count on ObjectInfo. |
| **ScanDrone** | **No** (active scan job) | `get_active_scan_drone_count_for_target() > 0` → `GameSession.can_scan_object(..., target_has_active_scan=true)` → `KEY_SCAN_ALREADY_IN_PROGRESS` in `launch_scan_drone()` and UI `_apply_scan_drone_info_to_dict` | Second drone would create **separate** `AutomationStore` scan mission + duplicate `set_object_scan_state` / survey reward on completion | One scan mission per drone; `scan_drone_target_by_unit_id` maps unit→target; multiple missions per target **not prevented** if gate removed | **Keep block** until shared scan progress (single job, multiple drones) is implemented |
| **ScanDrone (orbit support)** | Partial — “support” drones at target for mining bonus | `_is_scan_drone_providing_mining_support_at_target` counts orbit/travel states; separate from active scan gate | Bonus stacking only | Low | Document; not a production cap |
| **SurveyProbe investigate** | **One active per signal object** | `SurveyProbeMissionController.can_investigate_signal`: `_active_missions.has(oid)` → `REASON_IN_PROGRESS` | Correct — prevents duplicate reveal | Investigate missions **not persisted** on save | **Keep** per-signal rule |
| **SurveyProbe (parallel different signals)** | Capped at `max_active_probes_start` (2) | `REASON_ACTIVE_PROBE_LIMIT` | Blocks 3rd parallel investigate across signals | N/A | Product decision: remove or upgrade-gate later |
| **Orbit slots (visual)** | No hard “1 unit per object” slot | `AutomationUnit` random orbit radii; multiple units can `APPROACH_ORBIT` / `WORKING` on same target | Visual overlap only | N/A | No code limit found |

### Target-tracking structures

| Structure | File | Semantics |
|-----------|------|-----------|
| `scan_drone_target_by_unit_id: Dictionary` | `automation_controller.gd` | unit instance id → target_id (many units **can** point to same target; launch gate prevents second **active scan**) |
| `mining_ship_runtime_by_unit_id: Dictionary` | `automation_controller.gd` | unit instance id → runtime dict with `target_id` (**multi-MS per target supported**) |
| `AutomationStore.missions` | `automation_store.gd` | mission_id → `{target_id, type}` — no uniqueness constraint on `target_id` |
| `get_assigned_mining_ship_count(target_id)` | `automation_controller.gd` | Counts runtimes with matching `target_id` — used for UI, not blocking |

**No `target_to_unit` one-to-one map.** No `OrbitSlot` allocator.

---

## Recommended Fixes

Ordered by impact and dependency:

1. **BaseManagementPanel refresh/open split (Problem A)**  
   - Split `update_base_panel()` into **open-on-selection** vs **refresh-if-open**.  
   - On `base_resources_changed`, `automation_state_changed`, `base_upgrades_changed`: call `refresh_while_hold_open()` / `_refresh_economy_panels()` only — **do not** call `show_for_base()` unless the player just selected the base body.  
   - Keep `show_for_base()` exclusively from `_on_selection_changed()` (and explicit hub actions if any).  
   - **Acceptance:** MiningShip unload with Earth selected + panel closed → panel stays closed; TopHUD/Storage refresh still updates.

2. **Remove stale SD/MS production limit UI exposure (Problem B, cleanup)**  
   - `KEY_BUILD_*_LIMIT` strings remain in `gate_ui_texts.tres` but are dead — optional cleanup of templates + audit doc references.  
   - Confirm no UI path maps unknown gate keys to limit text (ProductionPanel uses gate `blocked_reason` string only).  
   - Telemetry `max_count` can stay as diagnostic or be renamed `balance_reference_max`.

3. **Multi-MS same target (Problem C)**  
   - **No gate change required** — already allowed.  
   - Optional: ObjectInfo shows assigned ship count; telemetry already tracks per-target mining counts.

4. **Plan Shared-ScanJob before Multi-SD same target (Problem C)**  
   - Do **not** remove `KEY_SCAN_ALREADY_IN_PROGRESS` until: single shared progress per `(system_id, object_id, target_scan_state)`, one completion reward, multiple drones attach to same job.  
   - Touch: `automation_controller.gd`, `automation_store.gd`, `automation_save_service.gd`, `game_session.gd` scan completion path.

5. **SurveyProbe parallel cap (out of scope unless requested)**  
   - Per-signal rule: keep.  
   - Global `max_active_probes_start`: separate step if unlimited parallel investigates across signals is desired.

---

## Files Reviewed

| File | Relevance |
|------|-----------|
| `scripts/system/controller/system_ui_controller.gd` | Panel open/refresh orchestration — **bug location** |
| `scripts/ui/system/base_management_panel.gd` | `show_for_base`, refresh-only resource handler |
| `scripts/system/controller/automation_controller.gd` | Unload → `add_base_resource`; scan/mine launch gates |
| `scripts/autoload/game_session.gd` | `base_resources_changed`, `can_scan_object`, `can_mine_object`, scaled costs |
| `scripts/autoload/stores/base_store.gd` | Build gates (no SD/MS limit keys) |
| `scripts/autoload/stores/automation_store.gd` | Scan missions — no per-target uniqueness |
| `scripts/system/controller/survey_probe_mission_controller.gd` | Investigate caps |
| `scripts/ui/system/production_panel.gd` | Gate-driven disable only |
| `scripts/ui/system/storage_panel.gd` | Refresh-only on resource change |
| `scripts/ui/system/top_hud.gd` | Refresh-only on resource change |
| `scripts/ui/system/object_info_panel.gd` | Scan/mine/investigate actions |
| `resources/definitions/gate_ui_text_definition.gd` | Limit keys (stale for SD/MS build) |
| `scenes/ui/system/base_management_panel.tscn` | No `tooltip_text`; editor-owned layout |

---

## Acceptance (this audit)

1. Only `docs/audits/base_panel_unload_and_limits_audit_v0_1.md` created.  
2. No code changes.  
3. No `.tscn` / `.tres` changes.  
4. `tooltip_text` remains 0 in reviewed system UI scenes.  
5. Root cause, production limit state, and object-target limits documented with file references.
