# Phase 3 Architecture Cleanup Summary v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Context:** Full Project Cleanup Audit — Phase 3 Architecture Cleanup (Phases 3.1–3.7)  
**Method:** Read-only consolidation of architecture docs, closure reports, and implemented code paths. **No code changes in this report.**

**Related closure reports:** `phase_3_6_automation_controller_split_closure_v0_1.md`, `phase_3_7_game_session_split_closure_v0_1.md`, `phase_3_4_discovery_refresh_smoketest_v0_1.md`, `phase_3_mining_loop_proof_v0_1.md`.

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS** |
| **Phase 3 Architecture Cleanup status** | **Pausable / closed for current scope** — keine direkte Fortsetzung mit High-Risk-Refactors empfohlen |
| **Wichtigste erreichte Ziele** | Architektur dokumentiert; Discovery-Refresh stabilisiert; Resource-UI-Metadaten zentralisiert; Audio- und Automation-Save-Write-Pfade extrahiert; GameSession/AutomationController kartiert; Save-v1 und Save-v2 klar getrennt |
| **Wichtigste bewusst offene Risiken** | AutomationSaveService Phase B (Restore); Mining-Cargo-/WAITING_FOR_STORAGE; Save-v2 / `active_missions`; GameSession SaveSessionService; Colonization/ObjectProgression/BaseEconomy-Splits; direkte Store-Leaks; fehlende automatisierte Headless-Regression |

**Erwartung erfüllt:** Phase 3 hat **nicht** `AutomationController` oder `GameSession` vollständig gesplittet. Es wurden **gezielte, dokumentierte Verbesserungen** und **kleine Low-/Medium-Risk-Delegates** umgesetzt.

---

## Phase Overview

| Phase | Thema | Ergebnis | Implementiert? | Closure status | Notes |
|-------|--------|----------|--------------|----------------|-------|
| **3.1** | Selection info adapter / `system_ui_controller` dynamic calls | Typed `_build_world_object_info()`; **0** `has_method` / `.call(` in controller | **Yes** | **Closed** (doc: `system_ui_controller_selection_polymorphism_v0_1.md`) | Polymorphic world nodes via explicit `SystemBody` / `POI` / `SignalMarker` branches |
| **3.2** | Audio path table resource | `AudioEventTableDefinition` + `data/audio/audio_event_table.tres`; `AudioManager` loads table | **Yes** | **Closed** (referenced as done in Phase 3.3 design) | SFX/music paths data-driven; no gameplay change |
| **3.3** | ResourceDefinition catalog | `ResourceDefinition`, `ResourceCatalogDefinition`, `resource_catalog.tres`; UI labels via `GameSession` (later `ResourceCatalogFacade`) | **Yes** | **Closed** (design + implementation) | No `survey_data.tres`; amounts still in stores |
| **3.4** | Per-object discovery refresh | `refresh_object` / `refresh_objects`; `reveal_object` removed; colony establish signal path | **Yes** | **PASS WITH NOTES** (`phase_3_4_discovery_refresh_smoketest_v0_1.md`) | Static wiring PASS; full manual checklist **NOT TESTED** in audit doc |
| **3.5** | Save-v2 mission continuity **design** + Save Schema v1 | `save_v2_mission_continuity_design_v0_1.md`, `save_schema_v1.md` | **Partial** | **Design closed** | **Docs only** for schema; **no Save-v2 code** |
| **3.6** | AutomationController split preparation | Split plan, function map, `AutomationAudioService`, `AutomationSaveService` Phase A, baselines | **Partial** | **CLOSED / PASS** (`phase_3_6_automation_controller_split_closure_v0_1.md`) | Controller ~**2807** lines; Restore still in controller |
| **3.7** | GameSession split preparation | Split plan, function map, `ResourceCatalogFacade` | **Partial** | **CLOSED / PASS** (`phase_3_7_game_session_split_closure_v0_1.md`) | GameSession ~**2591** lines; Save/Load untouched |

**Cross-cutting (pre–3.1 context):** Phase 1 delivered gate/UI text centralization, balance-backed SurveyData rewards, `save_behavior_v0_1.md`, tooltip removal — foundation for Phase 3 stability.

**Mining loop proof:** `phase_3_mining_loop_proof_v0_1.md` — **PASS** (manual core loop); supports pausing architecture work for gameplay/balance.

---

## What Was Implemented

Concrete code/data outcomes (verified in repo at summary date):

### UI / controller architecture
- **Phase 3.1:** Typed selection-info adapter in `system_ui_controller.gd` — no dynamic `has_method` / `call` on `selected_node` for world scan info.
- **Gate/UI text (Phase 1 carryover, supports Phase 3):** `gate_ui_texts.tres`, `discovery_signal_ui_texts.tres`; centralized blocked-reason keys for scan/mine/build paths.

### Resource catalog (Phase 3.3 + 3.7)
- `resources/definitions/resource_definition.gd` (`ResourceDefinition`)
- `resources/definitions/resource_catalog_definition.gd` (`ResourceCatalogDefinition`)
- `data/resources/resource_catalog.tres` (Iron, Silicon, Copper, Carbon, Ice, SurveyData — UI metadata only)
- `GameSession` read APIs: `get_resource_display_name`, `get_resource_short_label`, `get_resource_sort_order`, `get_storage_resource_ids_sorted`, `get_resource_definition`
- **Phase 3.7:** `scripts/session/resource_catalog_facade.gd` (`ResourceCatalogFacade`); `GameSession` delegates; public `resource_catalog` field synced after load
- **UI usage:** `storage_panel.gd`, `object_info_panel.gd`, `production_panel.gd`, `upgrade_panel.gd` call `GameSession.get_resource_display_name()` (call-sites unchanged)

### Discovery refresh (Phase 3.4)
- `SystemDiscoveryController.refresh_object` / `refresh_objects`
- `SystemDiscoveryController.apply_for_system` — **only** full sync (e.g. `system_scene.gd` setup/enter)
- **SurveyProbe:** `set_object_discovery_state(KNOWN)` → `refresh_object`
- **SensorPulse:** `set_object_discovery_state(SIGNAL)` → `refresh_objects`
- **Colony/base establish:** `GameSession.established_body_discovery_visual_refresh_requested` → `SystemUIController` → `refresh_object`
- **`reveal_object` removed** (no callers in `scripts/`)

### Audio (Phase 3.2 + 3.6)
- `resources/definitions/audio_event_table_definition.gd`
- `data/audio/audio_event_table.tres`
- `AudioManager` loads and resolves SFX/music via table
- **`AutomationAudioService`** (`scripts/system/automation/automation_audio_service.gd`) — world SFX / scan orbit loops; `AutomationController` delegates

### Automation save write path (Phase 3.6)
- **`AutomationSaveService` Phase A** (`scripts/system/automation/automation_save_service.gd`) — `build_runtime_save_data`, scan/mining job dicts, `sanitize_*`
- `AutomationController.to_save_data()` delegates; **Restore remains in controller**
- Editor baselines: `docs/audits/save_baselines/automation_runtime_*.json`; audit **PASS**; user Phase-A editor test **PASS**

### Documentation (implemented as docs, not gameplay)
- `docs/save_schema_v1.md` — current Save-v1 field reference
- Multiple architecture/audit markdown files (see References)

**Not implemented in Phase 3:** Save-v2, `active_missions`, full controller/session splits, UnitSpawner, Scan/Mining mission services.

---

## What Was Design Only

| Topic | Document(s) | Notes |
|-------|-------------|-------|
| **Save-v2 mission continuity** | `save_v2_mission_continuity_design_v0_1.md` | Schema proposal; migration risks; **no implementation** |
| **AutomationController full split** | `automation_controller_split_plan_v0_1.md`, `automation_controller_function_map_v0_1.md` | Extraction order: Audio ✅ → Save A ✅ → Spawn → Scan → Mining |
| **AutomationSaveService Phase B** | `automation_save_service_extraction_plan_v0_1.md` | Restore extraction; **not started** |
| **GameSession full split** | `game_session_split_plan_v0_1.md`, `game_session_function_map_v0_1.md` | 10 future facades; extraction order documented |
| **Future services (all design-only)** | Split plans | `SaveSessionService`, `ColonizationService`, `ObjectProgressionFacade`, `BaseEconomyFacade`, `ProductionService`, `UpgradeService`, `ScanMineGateService`, `GalaxyProgressionService`, `SessionStateService` |
| **Automation mission/spawn splits** | Automation split plan | `AutomationUnitSpawner`, `ScanDroneMissionService`, `MiningShipMissionService`, `SurveyProbeUnitPool` (investigate stays separate) |
| **Resource catalog Step 5+** | `resource_definition_catalog_design_v0_1.md` | Icons, TopHUD chips — optional polish, not required for Phase 3 close |

---

## Architecture Improvements

| Area | Before | After | Benefit | Risk reduced |
|------|--------|-------|---------|--------------|
| **Discovery refresh** | Global `apply_for_system` / `reveal_object` shortcuts | Per-object `refresh_object(s)`; full sync only on system enter | No marker flicker on pulse; store/visual alignment | Medium — runtime drift if refresh fails |
| **Resource labels / catalog** | `capitalize()` / ad hoc titles | `resource_catalog.tres` + `GameSession` / `ResourceCatalogFacade` | Consistent UI names; SurveyData vs deposits clear | Low — display only |
| **Audio paths / services** | Hardcoded paths in `AudioManager` map + inline automation audio | `audio_event_table.tres` + `AutomationAudioService` | Data-driven audio; smaller automation surface for SFX | Low–medium (loop leaks if misused) |
| **Automation save write** | Save builders inside ~3000-line controller | `AutomationSaveService` Phase A | Isolated JSON-shape risk; baselines for regression | Medium — restore still monolithic |
| **GameSession resource catalog** | Catalog load + reads inline in ~2659-line autoload | `ResourceCatalogFacade` delegate | Read-only boundary for first GameSession extract | Low |
| **system_ui_controller selection** | `has_method` / `call` on selected nodes | Typed adapter branches | Compile-time clarity; fewer silent failures | Medium — panel still large |
| **Save documentation** | Implicit save behavior | `save_schema_v1.md` + `save_behavior_v0_1.md` | Save-v2 design can diff against facts | Medium — doc drift if code changes without update |
| **AutomationController documentation** | Single opaque file | Function map + split plan + baselines | Safer future extractions | High areas still in one file |
| **GameSession documentation** | Single opaque autoload | Function map + split plan + store-leak list | Safer future extractions | Save/colonization still in one file |

---

## Save/Load Status

| Item | Status |
|------|--------|
| **Save-v1 active** | Yes — `SaveManager.SAVE_VERSION == 1` |
| **`save_schema_v1.md`** | Documents current `game_session` and store shapes |
| **Save-v2** | **Design only** — no `active_missions`, no version bump |
| **AutomationSaveService** | **Phase A write path only** — `automation.runtime` shape unchanged |
| **Restore** | **`AutomationController`** — `apply_save_data`, `_restore_*`, pending buffers via `GameSession` |
| **Pre-save order** | Unchanged: SurveyProbe cancel → SensorPulse cancel → automation snapshot → camera → `GameSession.to_save_data()` |
| **Phase 3.6 baselines** | Four editor `automation.runtime` JSON files; optional WAITING_FOR_STORAGE template **NOT TESTED** |

---

## Discovery Status

| Item | Status |
|------|--------|
| **DiscoveryState vs ScanState** | Remain separate (`ObjectScanStore`) |
| **`apply_for_system`** | Full sync for system setup / enter / load enter |
| **`refresh_object` / `refresh_objects`** | Runtime changes (probe, pulse, establish) |
| **`reveal_object`** | **Removed** |
| **Marker duplicates** | Static audit PASS; manual smoke **PASS WITH NOTES** (3.4 checklist not all run in audit environment) |
| **Save abort probe/pulse** | No KNOWN/SIGNAL refresh on cancel+refund (by design v0.1) |

---

## AutomationController Status

| Item | Status |
|------|--------|
| **Role** | Remains **facade** for scan/mine/spawn/save-restore/survey-probe pool |
| **`AutomationAudioService`** | Extracted — **PASS** |
| **`AutomationSaveService` Phase A** | Write path extracted — **PASS** |
| **Still in controller** | Restore, scan/mine FSM, cargo/unload, `WAITING_FOR_STORAGE`, idle spawn, recall, store integration |
| **Phase 3.6** | **Closed** for planned scope |
| **Phase B** | **Do not start** without separate design + baseline/load tests |

Approximate size: **~2807** lines (`automation_controller.gd`).

---

## GameSession Status

| Item | Status |
|------|--------|
| **Role** | Remains **Autoload facade** |
| **`ResourceCatalogFacade`** | Extracted read-only delegate — **PASS** |
| **Unchanged** | `to_save_data` / `apply_save_data`, all **5 signals**, store fields and schemas |
| **Documented leaks** | `GameSession.bases.*` (survey probe, sensor pulse); `GameSession.automation.*` (controller recall/restore) |
| **`get_primary_base_id()`** | Called from `automation_controller`; **not defined** on `GameSession` at audit — verify in editor if strict |
| **Phase 3.7** | **Closed** for planned scope |
| **Do not start without plan** | `SaveSessionService`, `ObjectProgressionFacade`, `ColonizationService` |

Approximate size: **~2591** lines (`game_session.gd`).

---

## Remaining High-Risk Areas

| Risk | Severity | Current mitigation | Recommended handling |
|------|----------|-------------------|----------------------|
| **AutomationSaveService Phase B (Restore)** | **Critical** | Stays in controller; extraction plan exists | Design doc + load matrix before any code |
| **Mining cargo lifecycle** | **High** | Unchanged FSM in controller | No refactor without mining loop proof re-run |
| **WAITING_FOR_STORAGE full coverage** | **Medium** | Optional baseline template only | Editor capture before Phase B if needed |
| **Save-v2 / `active_missions`** | **Critical** (schema) | Design only | Separate product phase; not Phase 3 continuation |
| **GameSession SaveSessionService** | **Critical** | Documented order in function map | Last in GameSession extraction order |
| **ColonizationService** | **High** | Ops + establish in GameSession | Plan-only until economy stable |
| **ObjectProgressionFacade** | **High** | Discovery/scan/remaining_resources documented as separate | No code without per-object tests |
| **BaseEconomy spend/build path** | **High** | Facade methods + store leaks | Wrapper methods before moving logic |
| **Direct `GameSession.bases.*` leaks** | **Medium** | Documented in function map | Migrate to `GameSession` wrappers with signals |
| **UI reads automation runtime dicts** | **Medium** | Documented in split plan | Keep public facade until UI refactor scoped |
| **`get_primary_base_id` missing API** | **Low–Medium** | Noted in 3.7 closure | Confirm parser/runtime; add or remove caller |
| **No automated headless regression** | **Medium** | Manual smoke (mining loop, automation save Phase A, resource labels) | Add only when gameplay loop stable |

---

## What Must Not Be Done Next

Without a **new plan + smoke/save matrix**:

- **No** `SaveSessionService` implementation code  
- **No** `AutomationSaveService` Phase B (Restore) implementation code  
- **No** `MiningShipMissionService`, `ScanDroneMissionService`, or `AutomationUnitSpawner` code  
- **No** `ObjectProgressionFacade` or `ColonizationService` code  
- **No** Save-v2 or `active_missions`  
- **No** `SAVE_VERSION` bump  
- **No** resource ID changes  
- **No** `data/planet_resources/survey_data.tres`  
- **No** further architecture splits without closure-style docs and tests  
- **No** signal rename or public `GameSession` API migration  

---

## Recommended Next Step

**Pause Phase 3 Architecture Cleanup** and **return to gameplay validation / core-loop balance**.

**Begründung:**

- Architecture is **sufficiently stabilized** for v0.1: discovery refresh, resource labels, audio table, automation save **write** path, and extensive **documentation** for high-risk areas.  
- Remaining split work is **documented but not required** for the next meaningful playtest.  
- **Mining loop proof** already **PASS** manually; the productive next step is iterating **loop feel**: Scan → Mine → Return → Storage → Build → Upgrade → ColonyShip preview — not another refactor wave.

**Do not recommend now:**

- Starting a new architecture phase (3.8) with code  
- Save-v2 implementation  
- Full `AutomationController` or `GameSession` split  

**If architecture resumes later:** `AutomationSaveService Phase B — design only` or `GalaxyProgressionService — plan only` (per closure reports), never SaveSession/Colonization/ObjectProgression code first.

---

## Closure Decision

| Question | Decision |
|----------|----------|
| **Phase 3.1–3.7 summarized?** | **Yes** — see Phase Overview and sections above |
| **Current Phase 3 scope closable / pausable?** | **Yes** — closed/paused for architecture cleanup scope |
| **Any blocker before gameplay testing?** | **No** — no mandatory high-risk refactor required |
| **Any high-risk implementation recommended now?** | **No** |

**Conclusion:** Phase 3 Architecture Cleanup is **pausable / closed for current scope**. Continue with **gameplay loop validation and balance**, not immediate high-risk architecture code.

---

## References (key artifacts)

| Phase | Primary artifacts |
|-------|-------------------|
| 3.1 | `docs/ui/system_ui_controller_selection_polymorphism_v0_1.md` |
| 3.2 | `data/audio/audio_event_table.tres`, `scripts/autoload/audio_manager.gd` |
| 3.3 | `docs/architecture/resource_definition_catalog_design_v0_1.md`, `data/resources/resource_catalog.tres` |
| 3.4 | `docs/architecture/per_object_discovery_refresh_design_v0_1.md`, `docs/audits/phase_3_4_discovery_refresh_smoketest_v0_1.md` |
| 3.5 | `docs/architecture/save_v2_mission_continuity_design_v0_1.md`, `docs/save_schema_v1.md` |
| 3.6 | `docs/architecture/automation_controller_split_plan_v0_1.md`, `docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md`, `scripts/system/automation/automation_audio_service.gd`, `scripts/system/automation/automation_save_service.gd` |
| 3.7 | `docs/architecture/game_session_split_plan_v0_1.md`, `docs/audits/phase_3_7_game_session_split_closure_v0_1.md`, `scripts/session/resource_catalog_facade.gd` |
| Loop proof | `docs/audits/phase_3_mining_loop_proof_v0_1.md` |
| Audit origin | `docs/audits/full_project_cleanup_audit_v0_1.md` |

---

## Acceptance (this report)

1. Only `docs/audits/phase_3_architecture_summary_v0_1.md` was created.  
2. No code, scene, or data files were changed.  
3. Report summarizes Phases 3.1–3.7.  
4. Report distinguishes **implemented** vs **design-only**.  
5. Report does **not** claim full split of `AutomationController` or `GameSession`.  
6. Save-v1 compatibility is stated.  
7. Remaining risks are listed.  
8. Exactly one next step: **pause architecture; gameplay/balance validation**.  
9. `tooltip_text` remains **0** (project policy).
