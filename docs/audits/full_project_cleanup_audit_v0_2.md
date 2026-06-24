# Space Miner Full Project Cleanup Audit v0.2

**Based on:** `docs/audits/full_project_cleanup_audit_v0_1.md` (historical source, 2026-05-20)  
**Update log:** `docs/audits/full_project_cleanup_audit_v0_2_update_log.md`

---

## 0. Audit Scope v0.2

| Field | Value |
|--------|--------|
| Repository | `space-mining` (local workspace; origin per v0.1: Peeqoo/space-miner) |
| Audit date | 2026-06-07 |
| Engine target | Godot 4.6.1 |
| Branch | `main` |
| Commit | `05bf39aaf2ba4c3e6ea981cc09e4284a6eeb38c3` |
| Method | Static read-only analysis — ripgrep, glob, targeted `.gd` / `.tscn` / `.tres` / `.md` reads. **No Godot Editor run, no playtest in this session.** |

### What was reviewed

- `scripts/**/*.gd` — line counts on god files; grep on audit keywords
- `scenes/ui/system/*.tscn` — ObjectInfo, Production, panels
- `data/balance/`, `data/ui_text/`, `data/production/`, sample `data/celestial_bodies/`
- `resources/definitions/` — balance, gate UI, production
- `docs/audits/` — closure reports cross-checked against code
- `scripts/debug/smoke_tests/` — inventory (24 test scripts + 24 runners)
- `project.godot` autoload wiring (implicit via script paths)

### What was NOT reviewed

- Runtime playthrough / screenshots / full manual §19 matrix
- Complete line-by-line re-read of `automation_controller.gd` (~2711 LOC) or `game_session.gd` (~2440 LOC)
- All `.import/` metadata, CI/export, shaders
- Re-execution of every headless smoke in this audit session (prior PASS reports + spot-check only)

---

## 1. Executive Summary v0.2

### Gesamtzustand heute

**Bewertung: Stabiler v0.1-Prototyp mit deutlich mehr Test- und Doku-Abdeckung als beim Ursprungsaudit — aber weiterhin hohe Konzentration in wenigen God-Dateien, die seit v0.1 gewachsen sind.**

Phase-1-Cleanup-Ziele (UI-Texte, Balance-Rewards, Save-Doku, EN-Standard-UI, Tooltips entfernt) sind **überwiegend erledigt**. Phase-3 hat **kleine, dokumentierte Delegates** (Audio, Save-Write, Resource-Catalog, Discovery-Refresh) geliefert — **kein** vollständiger Controller-Split.

**Neu seit v0.1 (nicht im Ursprungsaudit):** `SharedScanJob`-Modell in `automation_controller.gd`, umfangreiche SharedScanJob-Smokes (Steps 3–7), weitere UI-Cleanup-Audits (ProductionPanel, Recall, SensorPulse).

### Was seit v0.1 besser wurde

| Area | Improvement |
|------|-------------|
| Gate / block UI text | `gate_ui_texts.tres` + `GateUiTextDefinition`; scan/mine/build/colony keys wired in `game_session.gd` / `base_store.gd` |
| SurveyData rewards | `scan_*_survey_data_reward` + `survey_probe_investigate_survey_data_reward` in `v0_1_balance.tres` |
| Sensor Pulse copy | `discovery_signal_ui_texts.tres`; `base_sensor_pulse_controller.gd` uses `DiscoverySignalUiTextDefinition` keys |
| ObjectInfo progress | Separate `SensorPulseProgressLabel` in `object_info_panel.tscn` |
| ProductionPanel | No visible TODO/timer copy |
| Recall buttons | English: `"Recall Drone"`, `"Recall Ship"` |
| Save behavior | `docs/save_behavior_v0_1.md` + `save_behavior_v0_1_smoke_test.gd` |
| SystemUI typing | Typed panel init; **0** `has_method` in `system_ui_controller.gd` (was ~67×) |
| Audio paths | `data/audio/audio_event_table.tres` loaded by `audio_manager.gd` |
| Resource display | `resource_catalog.tres` + `ResourceCatalogFacade` |
| Discovery refresh | `SystemDiscoveryController.refresh_object` / `refresh_objects` |
| Automation | `AutomationAudioService`, `AutomationSaveService` (write path) |
| Smoke coverage | 24 headless smoke tests vs ad-hoc plan in v0.1 |
| Tooltips | No `tooltip_text` on gameplay UI (smoke-regression enforced) |

### Was weiterhin riskant ist

| # | Risiko | Severity (unchanged) |
|---|--------|----------------------|
| 1 | `automation_controller.gd` **~2711** Zeilen (+ SharedScanJob, Mining, Restore) | **High** |
| 2 | `game_session.gd` **~2440** Zeilen (Gates, Economy, Colonization, Save hooks) | **High** |
| 3 | `object_scan_store.gd` — `remaining_resources` Semantik | **Critical** |
| 4 | `system_ui_controller.gd` **~1244** Zeilen — large info-dict bridge | **High** |
| 5 | `object_info_panel.gd` — runtime signal layout (`_apply_signal_panel_layout`) | **Medium** |
| 6 | Save v0.1 — active Investigate/Pulse cancel+refund; automation restore in controller | **Medium** |
| 7 | `DEFAULT_SCAN_DURATION_FALLBACK = 2.0` in `automation_controller.gd` | **Medium** (edge path) |
| 8 | Deutsche Lore in `data/celestial_bodies/**` (player-facing when revealed) | **Low–Medium** (i18n) |

### Was weiterhin nicht angefasst werden sollte

Unverändert gültig aus v0.1 §5 „Do Not Touch Yet“:

- `object_scan_store` mining/depleted semantics
- Automation mining tick / cargo / unload loop
- `get_scan_target_state_or_rescan_state` / scan completion
- Survey probe investigate FSM
- `ensure_default_discovery_for_system` seeding
- Großes Aufspalten von `game_session` / `automation_controller` **ohne** Save-Matrix + Smokes

### Wichtigste offene Punkte

1. **Architecture / Later** — AutomationSaveService Phase B (restore), GameSession SaveSessionService, vollständige Controller-Splits  
2. **UI** — ObjectInfo signal compact layout still code-driven (A1)  
3. **i18n** — German body lore in data vs English UI chrome  
4. **TopHUD vs ObjectInfo** — hover/detail deduplication not done  
5. **Manual regression** — v0.1 §19 smoke matrix not fully automated  

---

## 2. Original Audit Status Matrix

| Area | Original Issue / Task (v0.1) | Current Status | Evidence | Remaining Work |
|------|------------------------------|----------------|----------|----------------|
| God files | `automation_controller` ~2190 LOC monolith | **PENDING** | `automation_controller.gd` **~2711** lines; `AutomationAudioService` + `AutomationSaveService` exist but core FSM unchanged | Restore extract; scan/mining service split |
| God files | `game_session` ~1891 LOC | **PENDING** | **~2440** lines; only `ResourceCatalogFacade` extracted | SaveSessionService, economy/discovery splits |
| God files | `system_ui_controller` ~67× `has_method` | **DONE** | **0** `has_method` matches; typed `ObjectInfoPanel` / `ProductionPanel` init in `_ready` wiring | Reduce file size / info-dict typing |
| UI | ObjectInfo signal runtime layout | **PENDING** | `object_info_panel.gd` `_apply_signal_panel_layout`, `custom_minimum_size` / `offset_bottom` | Subscene or documented contract |
| UI | InvestigateProgress reused for Pulse | **DONE** | `object_info_panel.tscn`: `SensorPulseProgressLabel` + separate `@onready` in `.gd` | — |
| UI | `scan_button_text = "Scan"` hardcoded duplicate | **DONE WITH NOTES** | `system_ui_controller.gd` `SCAN_BUTTON_TEXT` / `MINING_BUTTON_TEXT` always passed when buttons shown; scene default also `"Scan"` | Product choice: always simple labels (by design) |
| UI | Recall buttons DE | **DONE** | `object_info_panel.tscn`: `"Recall Drone"`, `"Recall Ship"`; no `zurück` in UI scenes | — |
| UI | ProductionPanel timer TODO visible | **DONE** | `production_panel.tscn` clean; `production_panel.gd` comment only ~205; smoke PASS | — |
| Data | Scan rewards in GameSession const | **DONE** | `v0_1_balance.tres` `scan_*_survey_data_reward`; `game_balance_definition.gd` getters | — |
| Data | Investigate +5 hardcoded | **DONE** | `survey_probe_mission_controller.gd` → `balance.get_survey_probe_investigate_survey_data_reward()` | — |
| Data | `base_sensor_max_visible_signals` legacy | **DONE** | Field absent from balance definition/`.tres`; smoke `base_sensor_max_visible_signals_cleanup_smoke_test` | — |
| Data | Blocked reasons in code only | **DONE WITH NOTES** | `gate_ui_texts.tres`, `GateUiTextDefinition`; `game_session._gate_fail()` | Some `FALLBACK_*` in definition; unused prepared keys |
| Data | Audio paths hardcoded | **DONE WITH NOTES** | `audio_manager.gd` loads `data/audio/audio_event_table.tres` | Fallback if table missing |
| Legacy | `DEFAULT_SCAN_DURATION_FALLBACK 2.0` | **PENDING** | `automation_controller.gd` line 16, used line 84 | Validate or align with balance |
| Legacy | `_merge_legacy_cargo` | **PENDING** | Still in automation (save compat) | Save v2 |
| Save | Probe/Pulse cancel on save undocumented | **DONE** | `docs/save_behavior_v0_1.md`; `save_behavior_v0_1_smoke_test.gd` | Extend automated scan/mining save matrix |
| Perf | `apply_for_system` full marker rebuild | **PARTIAL** | `refresh_object`/`refresh_objects` added; `apply_for_system` still exists | Optional per-object path after pulse |
| i18n | DE+EN UI mix | **DONE WITH NOTES** | `scenes/ui/**` English; **German lore** in `data/celestial_bodies/*.tres` | Lore translation or i18n system |
| Tests | Ad-hoc smoke plan | **PARTIAL** | 24 automated smokes; not 1:1 §19 coverage | Map gaps in §8 |
| Architecture | Controller splits | **PARTIAL** | Phase 3.6/3.7 closure docs; 2 services + 1 facade | Phase B restore, further splits |
| Scan model | Per-drone scan missions only (v0.1) | **SUPERSEDED** | `SharedScanJob` in `automation_controller.gd`; smokes step 3–7 | Document in architecture; maintain smokes |

---

## 3. First 10 Cursor Tasks — Current Status

| # | Original Task (v0.1 §6) | Status | Evidence | Remaining Work | Recommended Next Action |
|---|-------------------------|--------|----------|----------------|-------------------------|
| 1 | Gate text resource skeleton | **DONE WITH NOTES** | `data/ui_text/gate_ui_texts.tres`, `gate_ui_text_definition.gd`, `game_session.gd` loads via `DEFAULT_GATE_UI_TEXTS_PATH` | v0.1 suggested `gate_texts.tres` name; unused keys (`upgrade_max_level`, etc.) | Wire unused keys **or** document as reserved |
| 2 | Move scan SD rewards to balance | **DONE** | `v0_1_balance.tres` 10/25/50; `grant_scan_survey_data_reward` uses balance | — | — |
| 3 | Sensor pulse UI strings | **DONE** | `discovery_signal_ui_texts.tres`; `base_sensor_pulse_controller.gd` `KEY_SENSOR_PULSE_*` | — | — |
| 4 | Remove Scan text override in SystemUI | **DONE WITH NOTES** | No duplicate scene override problem; `SCAN_BUTTON_TEXT`/`MINING_BUTTON_TEXT` **intentionally** set in `system_ui_controller.gd` for simple labels | Original goal was scene-only; superseded by simple-label design | Keep; document in UI style guide |
| 5 | Sensor pulse progress label | **DONE** | `object_info_panel.tscn` `SensorPulseProgressLabel`; smoke PASS | — | — |
| 6 | Deprecate `max_visible_signals` | **DONE** | Removed from balance; smoke PASS | — | — |
| 7 | Investigate reward to balance | **DONE** | `survey_probe_investigate_survey_data_reward = 5` in `.tres`; controller uses getter | — | — |
| 8 | Save behavior doc | **DONE** | `docs/save_behavior_v0_1.md`; audit `save_behavior_documentation_v0_1.md`; smoke | Automated scan/mining save cases in other smokes | — |
| 9 | ProductionPanel TODO text | **DONE** | No visible TODO; `production_panel_todo_text_cleanup_v0_1.md`; smoke PASS | Code comment only in `.gd` / `production_definition.gd` | — |
| 10 | Recall button language EN | **DONE** | `object_info_panel.tscn` EN labels; `object_info_recall_button_language_pass` smoke PASS | — | — |

---

## 4. Findings A–O — Updated

### A — UI / Inspector vs Code

| ID | v0.1 issue | Status | Evidence | Notes |
|----|------------|--------|----------|-------|
| A1 | Signal layout in code | **PENDING** | `_apply_signal_panel_layout` still in `object_info_panel.gd` | SHOULD NOT DO NOW without layout tests |
| A2 | Pulse reuses Investigate label | **DONE** | Separate `SensorPulseProgressLabel` node | — |
| A3 | Scan `"Scan"` override | **DONE WITH NOTES** | `SCAN_BUTTON_TEXT` in `system_ui_controller.gd` | Intentional simple labels |
| A4 | Recall DE buttons | **DONE** | `.tscn` EN text | — |
| A5 | Lore fallback DE | **DONE** | `system_ui_controller.gd` `"No description available."`; `.tscn` same | — |
| A6 | `has_method` duck typing | **DONE** | 0 matches in `system_ui_controller.gd` | File still large |
| A7 | ProductionPanel timer TODO | **DONE** | Scene + hover clean | — |
| A8 | Upgrade hover fallback | **DONE WITH NOTES** | Pattern unchanged — still valid | Info |
| A9 | TopHUD `custom_minimum_size` | **PENDING** | `top_hud_hover_panel.gd` — not re-audited line-by-line | Low risk; dynamic OK |
| A10 | Group fallback for signals | **PARTIAL** | `_forward_investigate_if_unconnected` still uses `get_nodes_in_group(&"system_ui_controller")` | Primary path is scene wiring |

**Category summary:** 6 DONE/DONE WITH NOTES, 2 PENDING, 1 PARTIAL.

---

### B — Hardcoded Texts

| ID | Status | Evidence |
|----|--------|----------|
| B1 Scan gates | **DONE WITH NOTES** | `GateUiTextDefinition` keys in `game_session.can_scan_object` path |
| B2 Mine gates | **DONE WITH NOTES** | Same pattern |
| B3 Build/Colony blocks | **DONE WITH NOTES** | `base_store.gd` → `GateUiTextDefinition.KEY_*` |
| B4 Sensor Pulse blocks | **DONE** | `DiscoverySignalUiTextDefinition` keys |
| B5–B6 Discovery investigate | **DONE** | `.tres` + definition |
| B7 `"Scan"` override | **DONE WITH NOTES** | See A3 |
| B8 Sensor progress format | **DONE** | UI text templates |
| B9 Storage full | **DONE** | `KEY_STORAGE_FULL` |
| B10 Lore empty | **DONE** | EN string in controller |

**Remaining:** Prepared but unwired gate keys (`unused_ui_text_keys_and_helpers_audit_v0_1.md`).

---

### C — Magic Numbers

| ID | Status | Evidence |
|----|--------|----------|
| C1 Scan rewards | **DONE** | Balance fields |
| C2 Investigate +5 | **DONE** | Balance field |
| C3 Pulse timing/cost | **DONE** | `v0_1_balance.tres` |
| C4 `2.0` scan fallback | **PENDING** | `automation_controller.gd` const |
| C5 Storage 1000 fallback | **NEEDS RECHECK** | Not re-verified line-by-line in `base_store.gd` |
| C6 max_visible_signals | **DONE** | Removed |
| C7–C8 Layout numbers | **PENDING** | Scene/layout unchanged |

---

### D — Data-Driven Architecture

| System | v0.1 | v0.2 |
|--------|------|------|
| Balance / rewards | Partial | **DONE** for scan/investigate/pulse cost |
| Blocked reasons | Weak | **DONE WITH NOTES** — `gate_ui_texts.tres` |
| Production / Upgrades / Units | Good | **Good** — unchanged |
| SurveyData | String-ID OK | **OK** — unchanged |
| Audio | Code map | **DONE WITH NOTES** — `audio_event_table.tres` |
| Resource catalog | N/A in v0.1 | **DONE** — `resource_catalog.tres` + facade |

---

### E — Duplicate Logic

**Unchanged assessment:** Gates correctly centralized in GameSession/controllers; UI reads gate dicts. **SharedScanJob** adds new scan orchestration layer — document, don’t duplicate gate logic in UI.

Status: **DONE WITH NOTES** (acceptable duplication pattern; SharedScanJob is new).

---

### F — Legacy / Compatibility

| Item | Status | Evidence |
|------|--------|----------|
| DEFAULT 2.0 fallback | **PENDING** | Still present |
| `_merge_legacy_cargo` | **PENDING** | Save compat |
| FALLBACK_* in UI defs | **DONE WITH NOTES** | Safety if `.tres` missing |
| max_visible_signals | **DONE** | Removed |
| SceneFlow fallback | **PENDING** | Not re-verified — assume still needed |

---

### G — NodePaths / Connections

| Item | Status | Evidence |
|------|--------|----------|
| Deep `$Margin/Root/...` in ObjectInfo | **PENDING** | Still used |
| `is_connected` guards in ObjectInfo | **DONE** | Pattern retained |
| Group `system_ui_controller` | **PARTIAL** | Fallback investigate/pulse forward remains |

---

### H — Runtime-State Ownership

**No change to v0.1 ownership table.** **Addition:** `SharedScanJob` state in `automation_controller.shared_scan_jobs_by_job_id` — owner remains AutomationController.

Status: **DONE WITH NOTES** (ownership clear; complexity increased).

---

### I — Save/Load

| Area | Status | Evidence |
|------|--------|----------|
| Probe cancel+refund | **DONE** | `save_behavior_v0_1.md` + smoke |
| Pulse cancel+refund | **DONE** | Same |
| Automation snapshot | **PENDING** | Restore still in controller; Phase B open |
| SharedScanJob save | **PARTIAL** | `shared_scan_job_step_5_save_restore_smoke_test.gd` exists | NEEDS RECHECK for full matrix |

---

### J — GDScript Quality

| ID | Status | Notes |
|----|--------|-------|
| J1 Dictionary info dicts | **PENDING** | Still untyped dicts in UI bridge |
| J2 Duck typing SystemUI | **DONE** | Typed panels |
| J3 `get_content_height` | **DONE** | Still no active calls (grep) |
| J5 String states | **PENDING** | Still string constants |
| J6 class_name usage | **DONE** | Good |

---

### K — Performance

All v0.1 items **PENDING** or **NEEDS RECHECK** — no profiling in this audit. `system_ui_controller._process` still updates distance every frame (line 237).

---

### L — Audio

**DONE WITH NOTES** — `AudioEventTableDefinition` + tres; `AudioManager` delegates. World loops still managed from automation.

---

### M — Economy / Resources

C1 resolved → **DONE**. Colony/production costs in `.tres` — **DONE**.

---

### N — Scene Layout

**PENDING** — `object_info_panel` signal shrink logic unchanged; `system_scene` offset_bottom not re-measured.

---

### O — Tests

See **§8**. **PARTIAL** vs v0.1 §19 — many new smokes, not full manual matrix.

---

## 5. Updated System Map

Changes from v0.1 (evidence-based only):

| System | Change since v0.1 |
|--------|-------------------|
| ScanDrone | **SharedScanJob** model + multi-drone assign UI; still `AutomationController` |
| GameSession | **ResourceCatalogFacade** for display metadata |
| Automation | **AutomationAudioService**, **AutomationSaveService** (write) |
| Audio | **AudioEventTableDefinition** resource |
| UI text | **GateUiTextDefinition** + `gate_ui_texts.tres` (Phase 1) |
| Discovery | **refresh_object(s)** in addition to `apply_for_system` |
| ProductionPanel | Build-time UI removed; instant builds |
| ObjectInfo | Separate pulse progress label; EN recall |

**Line counts (2026-06-07):**

| File | v0.1 (~) | v0.2 |
|------|----------|------|
| `automation_controller.gd` | 2190 | **2711** |
| `game_session.gd` | 1891 | **2440** |
| `system_ui_controller.gd` | 1142 | **1244** |
| `object_info_panel.gd` | 910 | **957** |

---

## 6. Updated Risk Matrix

| Datei | Risiko | Warum (aktuell) | Safe changes | Unsafe changes |
|-------|--------|-----------------|--------------|----------------|
| `object_scan_store.gd` | **Critical** | Mining truth | Logs, docs | Init/depleted semantics |
| `automation_controller.gd` | **High** | SharedScanJob + mining FSM + restore | Strings, telemetry | Cargo loop, restore |
| `game_session.gd` | **High** | Gates, colonization, save hooks | Text keys, docs | Bootstrap, gate logic |
| `system_ui_controller.gd` | **High** | Large info dict | Text constants | Selection rewrite |
| `object_info_panel.gd` | **Medium** | Runtime layout | Label text, visibility | Delete layout code |
| `base_sensor_pulse_controller.gd` | **Medium** | Cost/refund/reveal | UI text | Reveal rules |
| `survey_probe_mission_controller.gd` | **Medium** | Investigate FSM | Reward from balance only | Mission state |
| `gate_ui_texts.tres` | **Low** | Copy source | Add keys | Rename without migrate |
| `v0_1_balance.tres` | **Low** | Balance | Tune numbers | Rename fields |

---

## 7. Updated Cleanup Roadmap

### Done (verified in repo)

- Gate UI text resource (`gate_ui_texts.tres`) — Low risk — smokes: gate-related object info tests
- Scan/investigate rewards in balance — Medium — `rewards_to_balance_cleanup_smoke_test`
- Sensor pulse UI strings — Low — `sensor_pulse_ui_strings_cleanup_smoke_test`
- SensorPulseProgressLabel — Low — `sensor_pulse_progress_label_cleanup_smoke_test`
- `base_sensor_max_visible_signals` removed — Low — dedicated smoke
- ProductionPanel TODO text — Low — `production_panel_todo_text_cleanup_smoke_test`
- Recall EN — Low — `object_info_recall_button_language_pass_smoke_test`
- Save behavior doc — Info — `save_behavior_v0_1_smoke_test`
- Tooltip removal — Low — regression in many smokes
- Simple Scan/Mine labels — Low — `object_info_simple_action_button_labels_smoke_test`
- Audio event table — Low — **NEEDS RECHECK** dedicated smoke
- Resource catalog + facade — Low — Phase 3.7 manual PASS
- Discovery `refresh_object` — Medium — `phase_3_4` smoke **PASS WITH NOTES**
- Automation audio/save write services — Medium — Phase 3.6 closure

### Remaining Low-Risk Cleanup

| Item | Why | Risk | Files | Smoke required | Do now? |
|------|-----|------|-------|----------------|---------|
| Wire unused gate keys (`colony_no_ship`, `upgrade_max_level`) | Prepared copy not shown | Low | `gate_ui_texts.tres`, ObjectInfo | ObjectInfo smokes | **Optional** |
| German lore → EN or i18n table | UI EN but lore DE | Low–Med | `data/celestial_bodies/**` | Manual read | **Yes** if targeting EN release |
| Document SharedScanJob in architecture doc | New vs v0.1 audit | Info | `docs/architecture/` | SharedScan smokes | **Yes** |
| `DEFAULT_SCAN_DURATION_FALLBACK` comment/align | Misleading vs balance 35s | Low | `automation_controller.gd` | Scan smokes | **Optional** |

### Medium Cleanup

| Item | Why | Risk | Files | Smoke required | Do now? |
|------|-----|------|-------|----------------|---------|
| ObjectInfo signal layout → subscene | A1 maintenance | Medium | `object_info_panel.*` | ObjectInfo + signal view | **No** — design spike first |
| TopHUD hover vs ObjectInfo dedup | Duplicate detail | Medium | `top_hud_hover_panel.gd` | HUD smoke | **No** |
| AutomationSaveService Phase B (restore) | Save risk | Medium | automation services | step_5 + galaxy smokes | **No** without plan |
| Typed info dict / slimmer SystemUI | J1/J2 follow-up | Medium | `system_ui_controller.gd` | All ObjectInfo smokes | **No** |
| Per-object discovery after pulse only | K4 perf | Medium | `system_discovery_controller.gd` | pulse + discovery smokes | **Optional** |

### Architecture / Later

- Full `game_session.gd` split (SaveSessionService, EconomyAPI, …)
- Full `automation_controller.gd` split (ScanService, MiningService, Restore)
- Save v2 mission continuity (`save_v2_mission_continuity_design_v0_1.md`)
- Build queue / production timers
- StringName enums for discovery/scan states
- i18n system

**Do now?** **No** for all architecture items.

---

## 8. Updated Smoke-Test Plan

### v0.1 §19 mapping

| # | v0.1 scenario | Automated coverage | Status |
|---|---------------|-------------------|--------|
| 1 | New game discovery bootstrap | Partial | **NEEDS RECHECK** — no dedicated single smoke |
| 2 | Click signal — no Scan | Partial | investigate/signal UI smokes |
| 3 | Investigate flow | Partial | `save_behavior_v0_1`, survey tests |
| 4 | Complete → KNOWN | Partial | **NEEDS RECHECK** |
| 5 | Scan + SD reward | **DONE** | `rewards_to_balance_cleanup_smoke_test` |
| 6 | Rescan no SD | Partial | automation scan path — **NEEDS RECHECK** |
| 7 | Mine | Partial | `object_info_multi_ms_ui`, mining smokes |
| 8 | Storage full | Partial | `cost_reduction_10min`, base_panel |
| 9 | Deplete | **NEEDS RECHECK** | |
| 10 | Build probe | Partial | `step_2b_production_scaled_cost` |
| 11–12 | Sensor pulse | **DONE** | `sensor_pulse_*`, `save_behavior_v0_1` |
| 13–14 | Save mid investigate/pulse | **DONE** | `save_behavior_v0_1_smoke_test` |
| 15 | Load restore | Partial | `shared_scan_job_step_5_save_restore` |
| 16 | Colony | **NEEDS RECHECK** | colony audits exist |

### New smokes since v0.1 (add to CI checklist)

| Smoke | Topic |
|-------|--------|
| `shared_scan_job_step_3` … `step_7` | SharedScanJob runtime, UI assign, save, speed, stacking |
| `object_info_simple_action_button_labels` | Scan/Mine simple labels |
| `object_info_scan_drone_assign_ui` | ScanDrone assign UI |
| `object_info_multi_ms_ui` | Multi mining ship UI |
| `object_info_recall_button_language_pass` | Recall EN + function |
| `production_panel_todo_text_cleanup` | Production UI text |
| `base_sensor_max_visible_signals_cleanup` | Legacy balance field |
| `galaxy_transition_process_continuity` | Galaxy transition |
| `galaxy_transition_repeated_survey_probe` | Survey probe edge case |
| `cost_reduction_10min` | Balance smoke |
| `base_panel_unload` | Base panel |

### Regression bundle (recommended before cleanup)

1. `rewards_to_balance_cleanup_smoke_runner.tscn`
2. `save_behavior_v0_1_smoke_runner.tscn`
3. `shared_scan_job_step_5_save_restore_smoke_runner.tscn`
4. `object_info_simple_action_button_labels_smoke_runner.tscn`
5. `production_panel_todo_text_cleanup_smoke_runner.tscn`

---

## 9. Open Questions v0.2

1. **Release language:** Is German lore in `data/celestial_bodies/**` acceptable for v0.1, or must lore match EN UI?
2. **Save v2:** Continue cancel+refund policy or design mission restore? (Design doc exists; no code.)
3. **ObjectInfo signal layout:** Subscene vs documented code-layout — product decision pending.
4. **Unused gate keys:** Wire `KEY_COLONY_NO_SHIP`, `KEY_UPGRADE_MAX_LEVEL`, etc., or remove from `.tres`?
5. **Build timers:** `build_time_seconds` on `colony_ship.tres` — when to expose in UI?

*Removed from open list:* `base_sensor_max_visible_signals` (removed). `SCAN_BLOCK_NO_LAYER` hardcode (migrated to gate texts).

---

## 10. Final Answers v0.2

1. **Ist der Core stabil genug für weiteren Cleanup?**  
   **Ja** — für Low-Risk-Text/Doku/Balance-Tweaks und weitere Smokes. **Nein** für große Splits ohne Save-Matrix.

2. **Welche Dateien sind aktuell am riskantesten?**  
   `object_scan_store.gd`, `automation_controller.gd`, `game_session.gd`, `system_ui_controller.gd`.

3. **Welche v0.1 Tasks sind DONE?**  
   Tasks **2, 3, 5, 6, 7, 8, 9, 10** fully done. Tasks **1, 4** done with notes.

4. **Welche v0.1 Tasks sind noch offen?**  
   None of the First 10 remain **PENDING**. Follow-ups are **roadmap** items (architecture), not the original task list.

5. **Welche v0.1 Findings sind superseded?**  
   Single-drone-only scan model → **SharedScanJob**. Scan button progression labels API → **removed/unused**; simple `"Scan"`/`"Mine"` policy.

6. **Was ist der nächste sichere Cleanup-Block?**  
   German lore pass **or** wire unused gate keys **or** architecture docs for SharedScanJob — all Low risk with smokes.

7. **Was darf nicht ohne Plan angefasst werden?**  
   `object_scan_store` semantics, automation mining/cargo/restore, discovery bootstrap, investigate FSM, save format, controller splits.

8. **Welche SmokeTests sind Pflicht?**  
   §8 regression bundle (5 runners) + any smoke touching changed subsystem.

9. **Welche Dokumente sind Quelle der Wahrheit?**  
   | Topic | Document |
   |-------|----------|
   | Save v0.1 behavior | `docs/save_behavior_v0_1.md` |
   | Save v1 schema | `docs/save_schema_v1.md` |
   | Phase 1 closure | `docs/audits/phase_1_cleanup_closure_report.md` |
   | Phase 3 architecture | `docs/audits/phase_3_architecture_summary_v0_1.md` |
   | This audit (current) | **`docs/audits/full_project_cleanup_audit_v0_2.md`** |
   | Historical baseline | `docs/audits/full_project_cleanup_audit_v0_1.md` |

10. **Nächste 3 Cursor-Prompts (Reihenfolge):**  
    1. **German lore audit + EN pass** for `data/celestial_bodies/**` (player-facing descriptions only).  
    2. **SharedScanJob architecture doc** — update system map, ownership, save fields (docs only).  
    3. **Unused gate UI keys** — wire `KEY_COLONY_NO_SHIP` / storage-full mine message to UI or mark deprecated in `.tres`.

---

## Cleanup Audit cross-reference

| v0.1 roadmap item | v0.2 status |
|-------------------|-------------|
| Phase 1 Safe Cleanup (8 bullets) | **8/8 DONE** (see §7 Done) |
| Phase 2 Medium Cleanup | **PARTIAL** — SystemUI typing done; TopHUD dedup, ObjectInfo layout open |
| Phase 3 Architecture | **PARTIAL** — delegates only; god files larger |
| Task 9 ProductionPanel | **DONE** |
| Task 10 Recall language | **DONE** |

---

## Result

**PASS WITH NOTES**

- All First 10 Cursor Tasks verified **DONE** or **DONE WITH NOTES** with code evidence.
- God-file and layout risks **remain open** (not falsely marked done).
- Manual §19 smoke matrix **partially** automated.
- No gameplay/scene/resource files modified in this audit.

---

*End of audit v0.2 — documentation only.*
