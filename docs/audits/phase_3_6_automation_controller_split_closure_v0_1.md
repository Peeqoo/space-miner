# Phase 3.6 AutomationController Split Closure v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Context:** Full Project Cleanup Audit — Phase 3 Architecture Cleanup  
**Scope of this report:** Closure documentation only. No code, scenes, resources, or save-format changes.

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS** |
| **Phase 3.6 closable?** | **Ja** — für den geplanten Scope bis einschließlich `AutomationAudioService` + `AutomationSaveService` Phase A |
| **Wichtigste erreichte Ziele** | Verantwortlichkeiten dokumentiert; Function Map; zwei Low-/Medium-Risk-Services extrahiert; Save-v1 Write-Path isoliert; Editor-Baselines + manueller Phase-A-Test PASS |
| **Wichtigste nicht gestartete Risiken** | Restore-Extraktion (Phase B); Mining-Cargo-Lifecycle; vollständiger Controller-Split; Save-v2 / `active_missions`; `AutomationController` weiterhin ~2800 Zeilen |

**Restore Phase B** bleibt bewusst offen und ist **kein** Abschlusskriterium für Phase 3.6.

---

## Scope

Phase 3.6 war **kein vollständiger `AutomationController`-Split**. Ziel war sichere Vorarbeit und **kleine, risikoarme** Extraktionen innerhalb des Architecture-Cleanup-Audits — nicht Mission-Redesign, nicht Save-v2, nicht Public-API-Umbau.

Geplantes Zielbild:

| Ziel | Erledigt in Phase 3.6? |
|------|------------------------|
| Verantwortlichkeiten und Extraktionsreihenfolge dokumentieren | **Ja** |
| Function Map für Review und spätere Splits | **Ja** |
| Ersten Low-Risk-Service extrahieren (Audio) | **Ja** |
| Save-Write-Path (Phase A) planen, baselinen, implementieren | **Ja** |
| Restore, Spawner, Scan-/Mining-Mission-Services extrahieren | **Nein** (deferred) |
| Save-v2 / `active_missions` / `SAVE_VERSION` bump | **Nein** (out of scope) |

Bewusst **nicht** angefasst: Restore-Semantik, Mining-Cargo-/Unload-Refactor, Survey-Probe-Pool-Merge mit Scan/Mining, UI-Verhalten, `.tscn` / `.tres`, Gameplay-Regeln.

---

## Completed Work

| Step | Datei(en) | Ergebnis | Risiko (bei Durchführung) | Status |
|------|-----------|----------|---------------------------|--------|
| **1. Split Plan** | `docs/architecture/automation_controller_split_plan_v0_1.md` | Verantwortlichkeiten, Datenbesitz, Non-Goals, Extraktionsreihenfolge Audio → Save → Spawn → Scan → Mining | N/A (Design) | **DONE** |
| **2. Function Map** | `docs/architecture/automation_controller_function_map_v0_1.md` | Zeilenbereiche, Public API, Call-Sites, State-Ownership | N/A (Design) | **DONE** |
| **3. AutomationAudioService** | `scripts/system/automation/automation_audio_service.gd`, `scripts/system/controller/automation_controller.gd` | World-SFX / Orbit-Loops delegiert; Controller-Facade unverändert; Audio-SmokeTest **PASS** | Low | **DONE** |
| **4. AutomationSaveService Extraction Plan** | `docs/architecture/automation_save_service_extraction_plan_v0_1.md` | Phase A (write) / Phase B (restore); Schema-Regeln; Kompatibilitätstests | N/A (Design) | **DONE** |
| **5. Baseline Capture** | `docs/audits/automation_save_service_phase_a_baseline_v0_1.md`, `docs/audits/save_baselines/*.json` (5 Dateien) | 4 Editor-Baselines **PASS**; optional WAITING_FOR_STORAGE **NOT TESTED** (Template) | Medium (Schema) | **DONE** |
| **6. AutomationSaveService Phase A** | `scripts/system/automation/automation_save_service.gd`, `scripts/system/controller/automation_controller.gd` | Write-Path 1:1 extrahiert; `to_save_data()` delegiert; Restore im Controller; User Editor-Test **PASS** | Medium (Schema) | **DONE** |

Referenz-Dokumentation Save-v1: `docs/save_schema_v1.md` (unverändert durch Phase 3.6, weiterhin Source of Truth für v1-Felder).

---

## Current AutomationController State

`AutomationController` (`scripts/system/controller/automation_controller.gd`, **~2807** Zeilen nach Audio- und Save-Phase-A-Extraktion; Plan-Stand vor Split: ~3036) bleibt die **Facade** für Automation im System-Scene.

| Aspekt | Status |
|--------|--------|
| **Public API** | Unverändert (`launch_scan_drone`, `launch_mining_ship`, Recall-APIs, `to_save_data`, `apply_save_data`, `apply_automation_save_if_pending`, öffentliche Runtime-Dicts, `automation_state_changed`, Survey-Probe-Pool-APIs, …) |
| **Call-Sites** | `GameSession` (`refresh_automation_snapshot_from_scene` → `to_save_data`), `SystemScene` (`apply_automation_save_if_pending`), `SystemUIController` (Launch/Recall + Dict-Lesen) — **keine** gezielten API-Umbauten in Phase 3.6 |
| **Scan / Mine / Recall / Restore** | Vollständig im Controller (FSM, Store-Interaktion, Spawning, Signals) |
| **Audio** | Private Controller-Wrapper delegieren an `AutomationAudioService` |
| **Save write** | `to_save_data()` → `AutomationSaveService.build_runtime_save_data(...)` mit Controller-`Callable`s für Unit-/Node-/Base-Auflösung |
| **Save restore** | `apply_automation_save_if_pending`, `apply_save_data`, `_restore_*`, `_clear_automation_visuals_and_mission_state`, Fallbacks — **im Controller**; `_restore_mining_mission` nutzt `_save_service.sanitize_dictionary_for_save` (identische Sanitizer-Logik, keine Restore-Semantik-Änderung) |

Der Controller ist **kleiner und klarer begrenzt**, aber weiterhin die zentrale Hochrisiko-Datei für Mission-Gameplay und Restore.

---

## New Services

| Service | Datei | Typ | Verantwortung | Was der Service **nicht** tut | Status |
|---------|-------|------|---------------|-------------------------------|--------|
| **AutomationAudioService** | `scripts/system/automation/automation_audio_service.gd` (~105 Zeilen) | `RefCounted`, `class_name AutomationAudioService` | `AudioManager`-Delegation: Travel-SFX, Scan-Orbit-Loop start/stop, Mining-Tick-SFX, Audio-Source-Helfer | Keine Mission-State-Mutation; kein Store/GameSession; kein Spawn/Restore | **PASS** |
| **AutomationSaveService** | `scripts/system/automation/automation_save_service.gd` (~271 Zeilen) | `RefCounted`, `class_name AutomationSaveService` | Save-v1 **Write-Path**: `build_runtime_save_data`, Scan-/Mining-Job-Dicts, `sanitize_*`, `global_position_to_save_dict` | **Kein** Restore; kein `GameSession`/`AutomationStore` direkt; kein Spawn/`queue_free`; kein Save-v2; kein `active_missions`; kein `SAVE_VERSION`-Bump | **PASS** (Phase A) |

Beide Services sind **stateless** (`RefCounted`), werden pro Controller-Instanz gehalten (`_audio_service`, `_save_service`).

---

## Save-v1 Compatibility

| Requirement | Phase 3.6 Ergebnis |
|-------------|-------------------|
| **`SAVE_VERSION`** | Bleibt **1** (`SaveManager.SAVE_VERSION`) — nicht geändert |
| **`automation.runtime` Root** | Unverändert: `system_id`, `primary_base_id`, `scan_missions`, `mining_missions` |
| **`scan_missions` Job-Keys** | 16 Felder pro Job unverändert (siehe Baseline-Audit) |
| **`mining_missions`** | Sanitizer + Unit-Overrides; zusätzliche JSON-sichere Runtime-Keys weiter erlaubt |
| **`active_missions` / Save-v2** | Nicht hinzugefügt |
| **Restore-Funktionen** | Semantik unverändert; Implementierung weiter im Controller |
| **Baselines** | 4 Pflicht-Editor-Baselines unter `docs/audits/save_baselines/`; Audit **PASS** (`docs/audits/automation_save_service_phase_a_baseline_v0_1.md`) |
| **Editor-Verifikation Phase A** | **PASS** — manuell vom User bestätigt (Shape/Kompatibilität nach Implementation) |

Hinweis: Byte-identischer JSON-Vergleich ist **nicht** automatisiert; struktureller Abgleich + manueller Editor-Test. Optional CASE 5 (`WAITING_FOR_STORAGE`) nur Template / **NOT TESTED**.

---

## Tests / Verification

| Test | Result | Notes |
|------|--------|-------|
| Audio SmokeTest | **PASS** | Nach `AutomationAudioService`-Extraktion |
| Idle Save Shape | **PASS** | Baseline + User Editor-Bestätigung Phase A |
| Scan outbound Save Shape | **PASS** | Baseline `automation_runtime_scan_outbound.json` |
| Scan at target Save Shape | **PASS** | Baseline 3b post-scan; `scan_reveal_done: true` |
| Mining with cargo Save Shape | **PASS** | Baseline; Capture war Return-Leg (`status: 2`), Cargo erhalten |
| Load generated Saves | **PASS** | **PASS by manual confirmation** (User Phase-A Editor-Test) |
| Scan reward no duplicate | **PASS** | **PASS by manual confirmation** (keine Restore-/Scan-Logik-Änderung) |
| Mining cargo no dupe/loss | **PASS** | **PASS by manual confirmation** (keine Mining-FSM-Änderung) |
| `tooltip_text` | **PASS** | **0** Treffer in `*.gd` / `*.tscn` / `*.tres` (Projekt-Policy) |
| Parser / Editor start | **PASS WITH NOTES** | Kein Godot-CLI auf Audit-Host; Linter sauber; User Editor-Test PASS |

Automatisierte CI-/Godot-Headless-Regression für Save-Bytes: **nicht** eingerichtet in Phase 3.6.

---

## Not Started / Deferred

| Item | Warum deferred | Risiko wenn früh gestartet |
|------|----------------|----------------------------|
| **AutomationSaveService Phase B** (Restore) | Spawn, Dict-Mutation, Store-`restore_mission_record`, Doppel-Restore-Retry — gleiche Fehlerklasse wie Cargo-Dupe | **High** |
| **AutomationUnitSpawner** | Abhängig von `SystemSpawner`, Idle-Pools, Scene-Instanzen | **High** |
| **ScanDroneMissionService** | Scan-Reward, `scan_is_progression`, Mission-IDs, UI-Snapshot | **High** |
| **MiningShipMissionService** | `_process` FSM, Cargo, `WAITING_FOR_STORAGE`, Unload | **High** |
| **SurveyProbeUnitPool** | Separater Caller (`SurveyProbeMissionController`); nicht mit Scan/Mining vermischen | **Medium** |
| **Save-v2 / `active_missions`** | Eigenes Design (`save_v2_mission_continuity_design_v0_1.md`); bewusst nach v1-Stabilisierung | **High** (Schema) |
| **Mission continuity restore** | Teil von Save-v2 / Phase B, nicht Phase 3.6 | **High** |
| **Mining cargo / unload refactor** | Gameplay-frozen v0.1; kein Cleanup-Ziel | **High** |

---

## Remaining Risks

| Risk | Severity | Status / Mitigation |
|------|----------|---------------------|
| Restore extraction (Phase B) still high risk | **High** | Deferred; vor Implementation **Design-only** Phase B, nicht sofort coden |
| Mining cargo lifecycle complexity | **High** | Unverändert im Controller; nur Save-**Write** isoliert |
| UI reads public runtime dicts directly | **Medium** | Documented in Split Plan; Facade beibehalten bis UI-Refactor explizit geplant |
| `AutomationController` still large (~2807 lines) | **Medium** | Erwartet; Phase 3.6 war Vorarbeit, kein Full Split |
| `WAITING_FOR_STORAGE` baseline optional / not editor-tested | **Low** | Nicht Phase-A-Blocker; optional vor Phase B |
| Save byte-identical compare not automated | **Low** | Manuelle Baselines + User PASS; optional später Headless-Diff |
| Shared `sanitize_*` used from restore via service | **Low** | Identische Logik wie vorher; kein Verhaltensziel geändert |

---

## Recommended Next Step

**Do not start AutomationSaveService Phase B implementation immediately.**

Als nächsten Architektur-Schritt **Phase 3.7: GameSession Split — Plan Only** beginnen (Dokumentation, Verantwortlichkeiten, Grenzen — analog Phase 3.6), oder Phase 3.6 hier bewusst pausieren.

Falls später **innerhalb** des Automation-Themas fortgefahren wird: zuerst **`AutomationSaveService` Phase B — Design-Dokument** (Restore-Grenzen, Callable-Inputs, Testmatrix, Rollback), **keine** Restore-Implementation ohne abgeschlossenes Design und erneute Baseline-/Load-Tests.

---

## Phase 3.6 Closure Decision

| Question | Decision |
|----------|----------|
| **Phase 3.6 closed for current scope?** | **Yes** |
| **Scope closed** | Planning (`automation_controller_split_plan_v0_1.md`); Function Map; `AutomationAudioService`; Save Plan; Phase-A Baselines; `AutomationSaveService` Phase A (write path) |
| **Scope not closed** | Full `AutomationController` split; Restore extraction (Phase B); UnitSpawner; Scan/Mining mission services; Survey probe pool extract; Save-v2; `active_missions`; Mining cargo refactor |

**Klarstellung:** Phase 3.6 **hat den `AutomationController` nicht vollständig gesplittet**. Es wurden dokumentierte Grenzen geschaffen und zwei risikoarme bzw. kontrollierte (Save Write) Services extrahiert. Save-v1 bleibt kompatibel; Restore und Mission-Gameplay bleiben im Controller.

---

## References

| Document / code | Role |
|-----------------|------|
| `docs/architecture/automation_controller_split_plan_v0_1.md` | Split order and non-goals |
| `docs/architecture/automation_controller_function_map_v0_1.md` | Function inventory |
| `docs/architecture/automation_save_service_extraction_plan_v0_1.md` | Phase A/B save extract plan |
| `docs/audits/automation_save_service_phase_a_baseline_v0_1.md` | Baseline validation |
| `docs/save_schema_v1.md` | Save-v1 field reference |
| `scripts/system/controller/automation_controller.gd` | Facade + restore + gameplay |
| `scripts/system/automation/automation_audio_service.gd` | Audio delegation |
| `scripts/system/automation/automation_save_service.gd` | Save-v1 write path |

---

## Acceptance (this closure report)

1. Only `docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md` was created.  
2. No code, scene, or data files were changed.  
3. Report states clearly what is done vs. intentionally open.  
4. Report does **not** claim a full `AutomationController` split.  
5. Report records Save-v1 compatibility preserved.  
6. `tooltip_text` remains **0**.  
7. Exactly one recommended next step (Phase 3.7 plan-only or pause; Phase B design-before-code if returning to automation).
