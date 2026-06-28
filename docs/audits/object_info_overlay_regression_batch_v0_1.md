# ObjectInfo Overlay Regression Batch v0.1

**Date:** 2026-06-07  
**Godot:** 4.6.1-stable (headless)  
**Code/Scene changes:** None (run-only batch)

## Scope

Dieser Batch sichert die folgenden Refactors gegen bestehende Regression-Smokes ab:

| Refactor | Abgesichert durch |
|----------|-------------------|
| SignalInfoSubPanel C1 | `object_info_signal_layout`, `object_info_simple_action_button_labels` |
| ObjectInfoDictKeys | Alle ObjectInfo-Smokes (Dict-Contract) |
| SignalObjectInfoBuilder | `object_info_signal_layout` |
| SensorPulseInfoOverlay | `sensor_pulse_progress_label_cleanup`, `sensor_pulse_ui_strings_cleanup` |
| ScanDroneInfoOverlay | `object_info_scan_drone_assign_ui`, `shared_scan_job_step_6`, `shared_scan_job_step_7` |
| MiningShipInfoOverlay | `object_info_multi_ms_ui`, `object_info_mining_bonus_display`, `object_info_simple_action_button_labels` |
| ColonizationInfoOverlay | `object_info_signal_layout`, `galaxy_transition_process_continuity` |
| mining_bonus display contract fix | `object_info_mining_bonus_display` |
| TopHUD storage hover catalog-name cleanup | `top_hud_hover_storage` |
| Save / SharedScanJob baseline | `save_behavior_v0_1`, `galaxy_transition_*` |

## Smoke Results

| Smoke | Result | Notes |
|-------|--------|-------|
| `object_info_signal_layout_smoke_runner.tscn` | **PASS** | `tooltip_text_count: 0` |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | **PASS WITH NOTES** | Test F: idle scan drone still available — partial check |
| `object_info_multi_ms_ui_smoke_runner.tscn` | **PASS** | |
| `object_info_scan_drone_assign_ui_smoke_runner.tscn` | **PASS WITH NOTES** | Test D: idle scan drone still available — partial check |
| `object_info_mining_bonus_display_smoke_runner.tscn` | **PASS** | |
| `sensor_pulse_progress_label_cleanup_smoke_runner.tscn` | **PASS WITH NOTES** | Test E: second pulse start skipped (active pulse or gate) |
| `sensor_pulse_ui_strings_cleanup_smoke_runner.tscn` | **PASS** | |
| `shared_scan_job_step_6_ui_assign_scan_drone_smoke_runner.tscn` | **PASS WITH NOTES** | Test C: idle drone still available after assign loop |
| `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn` | **PASS** | Support stacking + mining bonus |
| `save_behavior_v0_1_smoke_runner.tscn` | **PASS WITH NOTES** | Test C/D deferred to dedicated smokes (by design) |
| `galaxy_transition_process_continuity_smoke_runner.tscn` | **PASS** | Colonization survival |
| `galaxy_transition_repeated_survey_probe_smoke_runner.tscn` | **PASS** | |
| `top_hud_hover_storage_smoke_runner.tscn` | **PASS** | Optional — vorhanden, ausgeführt |

**Ausführung:** 13 Runner in Folge nach `object_info_signal_layout`; alle Exit-Code 0. Kein vorzeitiger Abbruch.

## Invariants

| Check | Result | Detail |
|-------|--------|--------|
| `SAVE_VERSION` | **1** | `scripts/autoload/save_manager.gd` `const SAVE_VERSION := 1`; bestätigt in mehreren Smokes |
| `tooltip_text` | **0** | `object_info_signal_layout` meldet `tooltip_text_count: 0`; kein `tooltip_text` in `*.tscn` |
| Save schema | **Unverändert** | Kein `shared_scan_jobs`-Key in `save_manager.gd` / `game_session` Save-Payload |
| SharedScanJob speed scaling | **Entfernt** | Siehe verbotene Begriffe unten |

### Verbotene Begriffe (Runtime-Code-Scan)

| Begriff | Runtime `scripts/` (excl. `debug/`) | Szenen | Bewertung |
|---------|--------------------------------------|--------|-----------|
| `effective_speed_multiplier` | Nicht gefunden | Nicht gefunden | OK — nur in `docs/` und `debug/smoke_tests/shared_scan_job_step_7_speed_scaling_rollback_smoke_test.gd` |
| `diminishing` | Nicht gefunden | Nicht gefunden | OK — nur in `docs/design/` und Audit-Dokumenten |
| `ScanSpeedLabel` | Nicht gefunden | Nicht gefunden | OK — nur Rollback-Smoke + Audit-Docs |
| `ScanProgressLabel` | Nicht gefunden | Nicht gefunden | OK — nur Rollback-Smoke + Audit-Docs |
| `shared_scan_jobs` (Save-Blob) | Nicht in Save-Autoloads | — | OK |
| `shared_scan_jobs_by_job_id` | `automation_controller.gd` (Runtime-In-Memory) | — | Erwartet — kein Save-Feld, nur Laufzeit-Modell |

`balance_telemetry_logger.gd` (debug) enthält `shared_scan_jobs` im Telemetrie-Snapshot — kein Save-Schema.

## Failures / Notes

### FAILs

Keine.

### Bekannte PASS WITH NOTES (akzeptiert)

| Quelle | Note |
|--------|------|
| `sensor_pulse_progress_label_cleanup` | Zweiter Pulse-Start skipped wegen active pulse / Gate |
| `object_info_simple_action_button_labels` | Test F: partial idle-drone check |
| `object_info_scan_drone_assign_ui` | Test D: partial idle-drone check |
| `shared_scan_job_step_6` | Test C: idle drone still available after assign loop |
| `save_behavior_v0_1` | Test C/D bewusst an dedizierte Smokes delegiert |

Keine Regressionen bei Button-Text (`Scan` / `Mine`), Scan/Mine-Labels, SharedScanJob-Rewards, Support-Stacking oder Mining-Bonus-Anzeige.

## Verdict

**PASS WITH NOTES**

Alle 14 Batch-Smokes grün (PASS oder bekannte PASS WITH NOTES). Invarianten erfüllt. Keine Code- oder Scene-Änderungen in diesem Batch.
