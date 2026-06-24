# Full Project Cleanup Audit v0.2 — Update Log

**Date:** 2026-06-07  
**Base document:** `docs/audits/full_project_cleanup_audit_v0_1.md`  
**Branch:** `main`  
**Commit:** `05bf39aaf2ba4c3e6ea981cc09e4284a6eeb38c3`  
**Method:** Static read-only — ripgrep, glob, targeted file reads, closure-report cross-check. **No Godot Editor run.**

---

## v0.1 sections reviewed

| v0.1 Section | Reviewed |
|--------------|----------|
| 0. Audit Scope | Yes — compared to current repo layout |
| 1. Executive Summary (risks, UI, data-driven, legacy, Top 10) | Yes — each bullet verified |
| 2. System Map | Yes — line counts + new systems (SharedScanJob, services) |
| 3. Findings A–O (all IDs) | Yes — category summaries + representative IDs |
| 4. Risk Matrix | Yes — file sizes + ownership |
| 5. Cleanup Roadmap (Phases 1–3, Do Not Touch) | Yes |
| 6. First 10 Cursor Tasks | Yes — each task individually |
| 7. Appendix / TODOs / Open Questions | Yes |
| 19. Smoke-Test Plan | Yes — mapped to existing smokes |
| 23. Abschlussantworten | Yes — rewritten in v0.2 §10 |

---

## Search terms used (derived from v0.1)

`TODO`, `timer TODO`, `instant build`, `build_time_seconds`, `blocked_reason`, `GateUiTextDefinition`, `gate_ui_texts`, `discovery_signal_ui_texts`, `base_sensor_max_visible_signals`, `scan_basic_survey_data_reward`, `survey_probe_investigate_survey_data_reward`, `SCAN_BUTTON_TEXT`, `scan_button_text`, `Recall Drone`, `zurück`, `Keine Beschreibung`, `SensorPulseProgressLabel`, `InvestigateProgressLabel`, `has_method`, `DEFAULT_SCAN_DURATION_FALLBACK`, `tooltip_text`, `SharedScanJob`, `shared_scan_jobs`, `refresh_object`, `apply_for_system`, `AutomationAudioService`, `AutomationSaveService`, `ResourceCatalogFacade`, `audio_event_table`, `get_scan_button_label`, `SAVE_VERSION`, `custom_minimum_size`, `_apply_signal_panel_layout`, `get_nodes_in_group("system_ui_controller")`

---

## Evidence files read

### Core scripts / scenes
- `scripts/autoload/game_session.gd` (grep + sections: gates, balance load)
- `scripts/autoload/save_manager.gd`
- `scripts/autoload/stores/base_store.gd` (grep)
- `scripts/system/controller/automation_controller.gd` (line count, SharedScanJob grep)
- `scripts/system/controller/system_ui_controller.gd` (grep, typed init)
- `scripts/system/controller/base_sensor_pulse_controller.gd`
- `scripts/system/controller/system_discovery_controller.gd`
- `scripts/system/controller/survey_probe_mission_controller.gd` (grep reward)
- `scripts/ui/system/object_info_panel.gd` / `.tscn`
- `scripts/ui/system/production_panel.gd` / `.tscn`
- `resources/definitions/game_balance_definition.gd`
- `resources/definitions/gate_ui_text_definition.gd`
- `data/balance/v0_1_balance.tres`
- `data/ui_text/gate_ui_texts.tres`
- `data/ui_text/discovery_signal_ui_texts.tres`
- `data/production/*.tres`
- `data/celestial_bodies/**/*.tres` (umlaut sample)
- `scripts/autoload/audio_manager.gd` (audio table)

### Services / architecture (post–v0.1)
- `scripts/system/automation/automation_audio_service.gd`
- `scripts/system/automation/automation_save_service.gd`
- `scripts/session/resource_catalog_facade.gd`

### Closure / task audits (cross-check only — not sole evidence)
- `docs/audits/phase_1_cleanup_closure_report.md`
- `docs/audits/phase_3_architecture_summary_v0_1.md`
- `docs/audits/phase_3_6_automation_controller_split_closure_v0_1.md`
- `docs/audits/phase_3_7_game_session_split_closure_v0_1.md`
- `docs/audits/production_panel_todo_text_cleanup_v0_1.md`
- `docs/audits/object_info_recall_button_language_pass_v0_1.md`
- `docs/audits/rewards_to_balance_cleanup_v0_1.md`
- `docs/audits/save_behavior_documentation_v0_1.md`
- `docs/save_behavior_v0_1.md`

### Smoke inventory
- `scripts/debug/smoke_tests/*` — 24 `*_smoke_test.gd`, 24 `*_runner.tscn`

---

## Status counts (First 10 Cursor Tasks)

| Status | Count |
|--------|-------|
| DONE | 6 |
| DONE WITH NOTES | 4 |
| PARTIAL | 0 |
| PENDING | 0 |
| SUPERSEDED | 0 |
| NEEDS RECHECK | 0 |
| NOT FOUND | 0 |

---

## Status counts (Executive Summary Top 10 cleanup items)

| Status | Count |
|--------|-------|
| DONE | 7 |
| DONE WITH NOTES | 2 |
| PARTIAL | 1 |

---

## Status counts (Phase 1 roadmap — 8 bullets)

| Status | Count |
|--------|-------|
| DONE | 8 |
| DONE WITH NOTES | 0 |

---

## Key corrections vs older closure reports

| Topic | Older report said | v0.2 static check |
|-------|-------------------|-------------------|
| `SCAN_BLOCK_NO_LAYER` hardcoded | OPEN in `phase_1_cleanup_closure_report.md` | **Resolved** — `GateUiTextDefinition.KEY_SCAN_NO_LAYER` + `gate_ui_texts.tres` `"scan_no_layer"`; `game_session.gd` `_scan_blocked_no_layer()` |
| `get_scan_button_label_for_target_state()` | Dead API in `game_session.gd` | **NOT FOUND** in current `game_session.gd` — removed or never on this commit |
| Recall button text | `"Recall Mining Ship"` in phase_1_closure | **Updated** — `object_info_panel.tscn` now `"Recall Ship"` |
| `has_method` in SystemUI | ~67× in v0.1 | **0 matches** — Phase 3.1 typed adapter |
| File sizes | automation ~2190, game_session ~1891 | **Grew** — automation ~2711, game_session ~2440 (new features, not shrink) |

---

## NEEDS RECHECK / uncertainties

| Item | Why |
|------|-----|
| Full manual Smoke-Test Plan §19 rows 1–16 | No single automated suite; partial headless coverage only |
| `object_info_panel` signal layout at all resolutions | Runtime layout code present; no Editor playtest |
| `DEFAULT_SCAN_DURATION_FALLBACK = 2.0` runtime path | Code exists; headless path not exercised without missing unit def |
| Galaxy transition / colonization end-to-end | Dedicated smokes exist; not re-run in this audit session |

---

## Points marked DONE only with code evidence (not report-only)

- Scan/investigate rewards in balance — `v0_1_balance.tres` + `game_balance_definition.gd` + `grant_scan_survey_data_reward` usage
- ProductionPanel no visible TODO — `production_panel.tscn` + `production_panel.gd` hover path
- Recall EN labels — `object_info_panel.tscn` `text = "Recall Drone"` / `"Recall Ship"`
- `base_sensor_max_visible_signals` removed — absent from `game_balance_definition.gd` / `v0_1_balance.tres`
- SensorPulseProgressLabel split — `object_info_panel.tscn` nodes + `.gd` `@onready`
- `SAVE_VERSION = 1` — `save_manager.gd`
- `tooltip_text` in scenes — 0 gameplay assignments (only smoke test counters)

---

*End of update log.*
