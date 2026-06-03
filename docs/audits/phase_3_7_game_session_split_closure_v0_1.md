# Phase 3.7 GameSession Split Closure v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Context:** Full Project Cleanup Audit — Phase 3 Architecture Cleanup  
**Scope of this report:** Closure documentation only. No code, scenes, resources, or save-format changes.

**Prerequisite:** Phase 3.6 AutomationController Split Preparation **CLOSED / PASS** (`docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md`).

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS** |
| **Phase 3.7 closable?** | **Ja** — für den geplanten Scope bis einschließlich **ResourceCatalogFacade** |
| **Wichtigste erreichte Ziele** | GameSession analysiert und dokumentiert (Split Plan + Function Map); erster read-only interner Delegate extrahiert; Public API und UI-Call-Sites unverändert; Resource-Display-Tests **PASS** |
| **Wichtigste nicht gestartete Risiken** | Save/Load-Orchestrierung (`SaveSessionService`); Colonization; Object progression; Base economy / Production / Upgrade; Scan-Mine-Gates; Galaxy/Session-State; direkte `GameSession.bases.*` / `automation.*` Leaks; GameSession weiterhin ~**2591** Zeilen |

**GameSession bleibt Autoload und öffentliche Facade.** Es wurde **nicht** vollständig gesplittet.

---

## Scope

Phase 3.7 war **kein vollständiger GameSession-Split**. Ziel war sichere Vorarbeit auf dem größten Cross-Cutting-Autoload — analog Phase 3.6 bei `AutomationController`.

| Ziel | Erledigt in Phase 3.7? |
|------|------------------------|
| Verantwortlichkeiten und Extraktionsreihenfolge dokumentieren | **Ja** (`game_session_split_plan_v0_1.md`) |
| Function Map (Zeilen, API, Signale, Store Ownership, Save-Order) | **Ja** (`game_session_function_map_v0_1.md`) |
| Ersten Low-Risk-Delegate implementieren (read-only) | **Ja** (`ResourceCatalogFacade`) |
| Save/Load-Umbau | **Nein** |
| Store-Split oder Store-Schema-Änderung | **Nein** |
| Signal-Umbenennung oder -Migration | **Nein** |
| Public-API-Migration (Call-Sites auf neue Services) | **Nein** |
| Save-v2 / `active_missions` / `SAVE_VERSION` bump | **Nein** |

Bewusst **nicht** angefasst: Economy-Mengen, Production-/Upgrade-Regeln, Mining/Scan-Gates, Colonization-Semantik, `to_save_data` / `apply_save_data` Implementierung, Resource-IDs, `.tres` / UI-Panels.

---

## Completed Work

| Step | Datei(en) | Ergebnis | Risiko (bei Durchführung) | Status |
|------|-----------|----------|---------------------------|--------|
| **1. GameSession Split Plan** | `docs/architecture/game_session_split_plan_v0_1.md` | 10 vorgeschlagene Future-Facades, Extraktionsreihenfolge, Save/Signal/Store-Constraints, Non-Goals | N/A (Design) | **DONE** |
| **2. GameSession Function Map** | `docs/architecture/game_session_function_map_v0_1.md` | 26 Function Regions (~2659 Zeilen zum Audit-Zeitpunkt), Signal/API-Tabellen, Save-Order, direkte Store-Leaks dokumentiert | N/A (Design) | **DONE** |
| **3. ResourceCatalogFacade** | `scripts/session/resource_catalog_facade.gd` (~102 Zeilen), `scripts/autoload/game_session.gd` (~2591 Zeilen nach Extract) | Catalog-Load + Display-Read-APIs 1:1 delegiert; `resource_catalog` public field synchronisiert; User Resource-Display-Tests **PASS** | Low | **DONE** |

---

## Current GameSession State

| Aspekt | Status |
|--------|--------|
| **Autoload** | `GameSession` bleibt globaler `Node`-Autoload (**kein** `class_name`) |
| **Public Facade** | Alle externen Call-Sites weiter `GameSession.*` |
| **Resource display API** | Unveränderte Signaturen; Delegation an `_resource_catalog_facade` |
| **`resource_catalog` field** | Öffentlich erhalten; nach `load_catalog()` aus Facade gesetzt (`game_session.gd` ~114–115) |
| **Save / Load** | `to_save_data`, `apply_save_data`, Pre-save-Hooks unverändert (`docs/save_schema_v1.md`) |
| **Signals** | Alle 5 Signale unverändert auf `GameSession` |
| **Stores** | `bases`, `object_scans`, `automation`, `scanner`, `system_entry` unverändert |
| **Resource IDs** | Unverändert; Catalog nur UI-Metadaten |

### Resource display delegation (public API)

| Method | Delegates to |
|--------|----------------|
| `get_resource_definition(resource_id)` | `ResourceCatalogFacade.get_resource_definition` |
| `get_resource_display_name(resource_id, fallback)` | `ResourceCatalogFacade.get_resource_display_name` |
| `get_resource_short_label(resource_id, fallback)` | `ResourceCatalogFacade.get_resource_short_label` |
| `get_resource_sort_order(resource_id, fallback)` | `ResourceCatalogFacade.get_resource_sort_order` |
| `get_storage_resource_ids_sorted(resource_ids)` | `ResourceCatalogFacade.get_storage_resource_ids_sorted` |

**Externe Caller (unverändert):** u. a. `storage_panel.gd`, `object_info_panel.gd`, `production_panel.gd`, `upgrade_panel.gd` — weiterhin `GameSession.get_resource_display_name()` usw.

---

## New Service

| Service | Datei | Typ | Verantwortung | Was der Service **nicht** tut | Status |
|---------|-------|------|---------------|-------------------------------|--------|
| **ResourceCatalogFacade** | `scripts/session/resource_catalog_facade.gd` | `RefCounted`, `class_name ResourceCatalogFacade` | Lädt `res://data/resources/resource_catalog.tres`; liefert `ResourceDefinition`, Display-Namen, Short Labels, Sort Order, sortierte Storage-ID-Listen | Keine Mengen/Costs; kein BaseStore/ObjectScanStore/AutomationStore; kein GameSession; kein Save; keine Signale; keine Resource-ID-Änderung; kein `survey_data.tres` | **PASS** |

**Warn-Log-Prefix** bei fehlendem Catalog: `ResourceCatalogFacade:` (vorher `GameSession:`) — nur Diagnose, kein Gameplay-Effekt.

---

## Save / Store / Signal Compatibility

| Requirement | Phase 3.7 Ergebnis |
|-------------|-------------------|
| **`SAVE_VERSION`** | Bleibt **1** — nicht geändert |
| **`GameSession.to_save_data` / `apply_save_data`** | Unverändert; ResourceCatalog nicht serialisiert |
| **BaseStore / ObjectScanStore / AutomationStore** | Shapes und Facade-Zugriff unverändert |
| **GameSession signals** | `object_remaining_resources_changed`, `base_resources_changed`, `base_upgrades_changed`, `galaxy_progression_changed`, `established_body_discovery_visual_refresh_requested` — unverändert |
| **UI / Controller call-sites** | Keine Migration; weiter `GameSession.*` |
| **ResourceCatalog** | Nur UI-Metadaten (`resource_catalog.tres` unverändert) |
| **`data/planet_resources/survey_data.tres`** | Nicht erstellt (Projekt-Policy) |
| **Pre-save order** | Unverändert (SurveyProbe → SensorPulse → automation snapshot → camera → `to_save_data`) |

ResourceCatalogFacade berührt **keinen** Eintrag in `game_session` JSON.

---

## Tests / Verification

| Test | Result | Notes |
|------|--------|-------|
| Editor start / parser | **PASS** | **PASS by manual confirmation**; Linter sauber nach Implementation |
| `get_resource_display_name(&"Iron")` → `"Iron"` | **PASS** | Catalog-Eintrag in `resource_catalog.tres` |
| `get_resource_display_name(&"SurveyData")` → `"Survey Data"` | **PASS** | **PASS by manual confirmation** |
| `get_resource_short_label(&"SurveyData")` → `"Surv"` | **PASS** | **PASS by manual confirmation** |
| Unknown ID (e.g. `Nickel`) readable fallback | **PASS** | `ProductionDefinition.format_resource_title` wenn nicht im Catalog |
| `get_storage_resource_ids_sorted` order | **PASS** | `sort_order` dann alphabetisch — Logik 1:1 in Facade |
| StoragePanel / ObjectInfoPanel / ProductionPanel / UpgradePanel labels | **PASS** | Call-Sites unverändert; **PASS by manual confirmation** |
| Save / load | **PASS** | Nicht angefasst; kein Regression erwartet |
| Gameplay / economy amounts | **PASS** | Keine Mengen-Logik in Facade |
| `tooltip_text` | **PASS** | **0** Treffer in `*.gd` / `*.tscn` / `*.tres` |

Automatisierte Headless-Tests für ResourceCatalog: nicht eingerichtet in Phase 3.7.

---

## Not Started / Deferred

| Item | Why deferred | Risk if started early |
|------|--------------|------------------------|
| **SaveSessionService** | `to_save_data` / `apply_save_data` + Pre-save + Pending-Buffer — **Critical** | **Critical** — Schema/load-order regression |
| **ColonizationService** | Establish base + ops + galaxy coupling | **High** — double establish / wrong geography |
| **ObjectProgressionFacade** | Discovery vs scan vs `remaining_resources` must stay separate | **High** — mixed object state |
| **BaseEconomyFacade** | Spend/build + signals; direct `GameSession.bases.*` leaks | **High** — dup spend / silent UI |
| **ProductionService** | Build gates + `BaseStore` | **High** — build without cost |
| **UpgradeService** | Buy gates + derived multipliers for automation | **High** — stats not refreshed |
| **ScanMineGateService** | Scan/mine policy APIs | **Medium–High** — wrong layer / duplicate scan |
| **GalaxyProgressionService** | Serialized discovery/unlock lists | **Medium** |
| **SessionStateService** | `current_system_id` / definition load | **High** — wrong system context |
| **Public API migration** | Hundreds of `GameSession.*` references | **Critical** — project-wide breakage |
| **Signal migration** | UI bus on GameSession | **High** — frozen panels |
| **Save-v2 / `active_missions`** | Separate design track | **Critical** (schema) |

**Recommended extraction order** (unchanged from Split Plan): Function Map ✅ → ResourceCatalog ✅ → Galaxy (design) → Production/Upgrade gates → BaseEconomy → ObjectProgression → Colonization → SaveSession **last**.

---

## Remaining Risks

| Risk | Severity | Status / Mitigation |
|------|----------|---------------------|
| `GameSession` still large (~2591 lines) | **Medium** | Expected; only catalog slice extracted |
| Save/load orchestration in one file | **Critical** | Deferred `SaveSessionService`; test matrix before any move |
| Direct `GameSession.bases.*` leaks | **Medium** | Documented in Function Map (`survey_probe`, `sensor_pulse`); migrate via wrappers later |
| Direct `GameSession.automation.*` leaks | **Medium** | `automation_controller` recall/restore; coordinate with AutomationSaveService Phase B design |
| `get_primary_base_id()` caller without definition | **Low–Medium** | Noted in Function Map; verify in editor if strict typing enforced |
| Signals as public coupling | **Medium** | Keep emits on GameSession when delegating internal services |
| ResourceCatalogFacade complete | **Low** | **Mitigated** — PASS for Phase 3.7 scope |

---

## Recommended Next Step

**Do not start `SaveSessionService`, `ColonizationService`, or `ObjectProgressionFacade` now.**

**Either:**

1. **Pause** Phase 3 Architecture Cleanup after Phase 3.7, **or**
2. Create a **Phase 3 Architecture Summary Report** (Plan Only) across Phases 3.1–3.7 — read-only consolidation of what was documented and extracted, without further code splits.

**If continuing with GameSession later:** next step should be **GalaxyProgressionService — design document only** (no implementation), per `game_session_split_plan_v0_1.md` Step 3 — not SaveSession or economy facades.

---

## Phase 3.7 Closure Decision

| Question | Decision |
|----------|----------|
| **Phase 3.7 closed for current scope?** | **Yes** |
| **Scope closed** | GameSession Split Plan; GameSession Function Map; ResourceCatalogFacade internal delegate |
| **Scope not closed** | Full GameSession split; SaveSessionService; ColonizationService; ObjectProgressionFacade; BaseEconomy/Production/Upgrade/ScanMine/Galaxy/SessionState services; public API migration; signal migration; Save-v2 |

**Klarstellung:** Phase 3.7 **hat GameSession nicht vollständig gesplittet**. Es wurden Analyse, Kartierung und ein read-only Delegate umgesetzt. Save-v1, Stores, Signale und externe API bleiben stabil.

---

## References

| Document / code | Role |
|-----------------|------|
| `docs/architecture/game_session_split_plan_v0_1.md` | Split boundaries and extraction order |
| `docs/architecture/game_session_function_map_v0_1.md` | Line regions, API, signals, leaks |
| `docs/save_schema_v1.md` | Save-v1 contract (unchanged) |
| `docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md` | Prior phase closure |
| `scripts/autoload/game_session.gd` | Autoload facade |
| `scripts/session/resource_catalog_facade.gd` | Resource UI metadata delegate |

---

## Acceptance (this closure report)

1. Only `docs/audits/phase_3_7_game_session_split_closure_v0_1.md` was created.  
2. No code, scene, or data files were changed.  
3. Report states clearly what is done vs. intentionally open.  
4. Report does **not** claim a full GameSession split.  
5. Report records Save-v1 compatibility preserved.  
6. `tooltip_text` remains **0**.  
7. Exactly one recommended next step (pause or Phase 3 summary report; no Save/Colonization code).
