# Phase 1 Cleanup Closure Report

**Audit date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Method:** Static read-only ripgrep + targeted file reads (no Godot Editor run, no playtest, no code changes)

---

## Summary

- **Phase 1 status:** **PASS WITH NOTES**
- **Größte offene Punkte:**
  - Scan-Gate **`SCAN_BLOCK_NO_LAYER`** (`"No scan layer available"`) noch hardcoded in `game_session.gd` (kein `GateUiTextDefinition`-Key).
  - **Colonization-/Colony-Build-**Blockgründe weiterhin als `COLONY_BLOCK_*`-Strings in `base_store.gd` / `game_session.gd` (bewusst nicht migriert).
  - **`get_scan_button_label_for_target_state()`** existiert, wird von UI aber nicht aufgerufen — Scan-Button bleibt Scene-Default `"Scan"` (kein „Basic Scan“ / „Deep Rescan“ am Button).
  - **Deutsche Lore** in `data/celestial_bodies/**` und `data/galaxy_systems/*.tres` (ausdrücklich kein Phase-1-UI-Ziel).
  - Vorbereitete, aber **ungenutzte** Keys in `gate_ui_texts.tres` (`mine_storage_full`, `upgrade_max_level`, `colony_*`).
- **Darf Phase 2 beginnen?** **Ja** — Kernziele von Phase 1 (Balance-Rewards, Tooltips entfernt, Pulse/Gate-Text-Zentralisierung, Save-Doku, UI-EN für Standard-Panels) sind erfüllt. Offene Punkte sind kleine Restmigrationen oder Phase-2-Themen.

---

## Checklist

| Item | Status | Evidence / file | Notes |
|------|--------|-----------------|-------|
| Zentrale UI-Text-Keys für Gate-Strings (Scan/Mine/Build/Storage/Upgrade) | **PASS** | `resources/definitions/gate_ui_text_definition.gd`, `data/ui_text/gate_ui_texts.tres`, `game_session.gd` (`_gate_fail`, `blocked_reason_key`) | Scan/Mine/Build/Upgrade-not-enough/Storage-full migriert. Ausnahme: `SCAN_BLOCK_NO_LAYER`. |
| Sensor Pulse UI-Texte zentralisiert | **PASS** | `discovery_signal_ui_text_definition.gd`, `discovery_signal_ui_texts.tres`, `base_sensor_pulse_controller.gd`, `system_ui_controller.gd` | Bewusst **nicht** in `GateUiTextDefinition` (Discovery-Resource). |
| `scan_button_text`-Hardcode in SystemUI entfernt | **PASS** | `scripts/system/controller/system_ui_controller.gd` — kein `scan_button_text` / kein `"Scan"`-Override | Label aus `object_info_panel.tscn` (`text = "Scan"`) via `_scan_button_text_default`. |
| Separates `SensorPulseProgressLabel` | **PASS** | `scenes/ui/system/object_info_panel.tscn` (node), `object_info_panel.gd` (`sensor_pulse_progress_label` vs `investigate_progress_label`) | Investigate und Pulse nutzen getrennte Labels. |
| `base_sensor_max_visible_signals` entfernt | **PASS** | `game_balance_definition.gd`, `v0_1_balance.tres` — Feld fehlt; Treffer nur noch in `full_project_cleanup_audit_v0_1.md` | Kein aktiver Code-/Balance-Export mehr. |
| ProductionPanel TODO-Spielertext entfernt | **PASS** | `scenes/ui/system/production_panel.tscn` — kein „timer TODO“; `production_panel.gd` nur Kommentar „instant“ (nicht sichtbar) | Sichtbarer TODO-String weg. |
| Recall-Button-Sprache vereinheitlicht (EN) | **PASS** | `object_info_panel.tscn`: `"Recall Drone"`, `"Recall Mining Ship"` | Kein „zurück“ mehr in UI-Scenes. |
| `docs/save_behavior_v0_1.md` vorhanden | **PASS** | `docs/save_behavior_v0_1.md` | Investigate/Pulse cancel+refund dokumentiert. |
| Scan/Investigate SurveyData rewards in Balance | **PASS** | `v0_1_balance.tres` (5/10/25/50), `game_balance_definition.gd`, `game_session.gd` `grant_scan_survey_data_reward`, `survey_probe_mission_controller.gd` `_grant_survey_data_reward` | Keine Magic-`+10/+25/+50/+5` mehr in diesen Controllern. |
| Standard-`tooltip_text` entfernt | **PASS** | Repo-weit `tooltip_text` → **0 Treffer** | — |
| Galaxy Enter-Tooltip-Dead-Code entfernt | **PASS** | Kein `EnterTooltip`, `_enter_tooltips`, `_apply_enter_button_tooltip` | `AccessStatus*Template` + `AccessStatusLabel` bleiben (sichtbarer Status, kein Godot-Tooltip). |
| Custom HoverPanels bewusst behalten | **PASS (by design)** | `production_panel.tscn`, `upgrade_panel.tscn`, `top_hud_hover_panel.tscn` + zugehörige `.gd` | Kein `tooltip_text`; Hover-Sections für Build/Upgrade/TopHUD. |
| UI-English Standard-Pfade | **PASS WITH NOTES** | `scenes/ui/**` — keine Umlaute in `text =` | Lore DE in `data/celestial_bodies/**`, `data/galaxy_systems/*.tres` (siehe Open Items). |
| Galaxy Top Bar / Enter-Status | **PASS** | `galaxy_map_hud.gd`, `galaxy_top_bar.tscn` — EN-Labels | — |

---

## 1. Phase-1-Liste (Original-Audit)

| Punkt | Status | Fundstellen |
|-------|--------|-------------|
| Zentrale UI-Text-Keys für Gate-Strings | **PASS** | `gate_ui_text_definition.gd`, `gate_ui_texts.tres`, `game_session.gd`, `base_store.gd` (`*_blocked_reason_key`) |
| `scan_button_text`-Hardcode entfernt | **PASS** | Kein Setter in `system_ui_controller.gd`; Panel nutzt Scene-Default |
| Separates SensorPulseProgressLabel | **PASS** | `object_info_panel.tscn` + `.gd` |
| `base_sensor_max_visible_signals` entfernt | **PASS** | Nicht in Balance-Definition/`.tres` |
| ProductionPanel TODO-Text entfernt | **PASS** | Kein sichtbarer TODO-String |
| Recall-Button EN | **PASS** | `object_info_panel.tscn` |
| `docs/save_behavior_v0_1.md` | **PASS** | Datei vorhanden, Inhalt vollständig für v0.1 |
| Scan/Investigate rewards in Balance | **PASS** | `v0_1_balance.tres`, API in `GameBalanceDefinition` |

**RISK (Teilmigration, kein Blocker für Phase-2-Start):**

| Punkt | Status | Fundstellen |
|-------|--------|-------------|
| Alle Scan-Block-Strings zentral | **RISK** | `game_session.gd`: `SCAN_BLOCK_NO_LAYER` + `_scan_blocked_no_layer()` ohne `GateUiTextDefinition` |
| Phase-1-Roadmap „Pulse in Gate-Texts“ | **RISK (Doc drift)** | Pulse liegt korrekt in `DiscoverySignalUiTextDefinition` — besser als ursprüngliche Roadmap, kein Fehler |

---

## 2. Tooltip-Reste

| Pattern | Treffer | Erwartung |
|---------|---------|----------|
| `tooltip_text` | **0** | OK |
| `hint_tooltip` | **0** | OK |
| `set_tooltip` | **0** | OK |
| `EnterTooltip` | **0** | OK |
| `_enter_tooltips` | **0** | OK |
| `_apply_enter_button_tooltip` | **0** | OK |

**Bewusst behalten (kein Godot-Tooltip):**

- `HoverInfoSection` in Production/Upgrade-Panels (`production_panel.gd`, `upgrade_panel.gd`)
- `TopHudHoverPanel` (`top_hud_hover_panel.tscn`, `top_hud.gd`)
- `ColonizationNoShipTooltipTemplate` in `object_info_panel.tscn` — **Node-Name** enthält „Tooltip“, ist aber ein **verstecktes Label-Template** für `EconomyBlockLabel.text` (`object_info_panel.gd` ~210, ~742), **kein** `Control.tooltip_text`

---

## 3. Hardcoded Phase-1-Texte (Scripts)

| Suchbegriff | Befund | Bewertung |
|-------------|--------|-----------|
| `"Scan"` | Nur in `object_info_panel.tscn` Scene-Default; `get_scan_button_label_for_target_state()` in `game_session.gd` ungenutzt | **OK** Scene-Default; **RISK** Progressions-Labels (Basic/Deep) nicht an UI gebunden |
| `"Not enough"` | `COLONY_BLOCK_NOT_ENOUGH_RESOURCES` in `base_store.gd`; Gate-Texte über `GateUiTextDefinition` | **OK** Colony; Gates zentral |
| `"No scan drone"` / `"Scan already"` / `"Resource depleted"` / `"Storage full"` | Nur in `gate_ui_text_definition.gd` Fallbacks + `.tres` | **OK** zentraler Fallback |
| `"Scanning for signals"` / `"Cost:"` | `discovery_signal_ui_text_definition.gd` + `.tres`; Scene-Placeholder `object_info_panel.tscn` Zeile ~199 | **OK** Runtime überschreibt via Controller |
| `timer TODO` / `instant build` (sichtbar) | **0** in UI; Kommentar in `production_panel.gd` ~204, `production_definition.gd` ~8 | **OK** |
| `Drone zurück` / `Mining Ship zurück` / `Keine Beschreibung` / `Pausiert` / `Kolonisierung` | **0** in `scripts/ui`, `scripts/system/controller` | **OK** |
| `SCAN_BLOCK_NO_LAYER` | `game_session.gd` ~1254, ~1428 | **OPEN** (Phase-1-Teilmigration) |

---

## 4. Balance / Reward Magic Numbers

| Prüfpunkt | Status | Evidence |
|-----------|--------|----------|
| +10/+25/+50 nicht in `game_session.gd` | **PASS** | `grant_scan_survey_data_reward` → `balance.get_scan_survey_data_reward_for_state()` |
| +5 Investigate nicht hardcoded im Controller | **PASS** | `survey_probe_mission_controller.gd` → `get_survey_probe_investigate_survey_data_reward()` |
| Werte in `v0_1_balance.tres` | **PASS** | `survey_probe_investigate_survey_data_reward = 5`, `scan_*_survey_data_reward = 10/25/50` |
| `base_sensor_pulse_cost` in Balance | **PASS** | `game_balance_definition.gd` @export, `v0_1_balance.tres` `SurveyData: 5` |
| `base_sensor_max_visible_signals` aktiv | **PASS (removed)** | Nicht in Balance-Dateien |
| Pulse cost fallback `5` im Controller | **RISK** | `base_sensor_pulse_controller.gd` `FALLBACK_PULSE_COST_SURVEY_DATA := 5` nur wenn Balance fehlt — akzeptabel als Safety-Fallback |

---

## 5. UI-English-Pass

| Bereich | Umlaute / DE sichtbar | Status |
|---------|----------------------|--------|
| `scenes/ui/**/*.tscn` | Keine Treffer mit `[äöüÄÖÜß]` | **PASS** |
| `data/ui_text/**/*.tres` | Keine Umlaute | **PASS** |
| `data/production/*.tres` | Keine Umlaute | **PASS** |
| `data/upgrades/**/*.tres` | Keine Umlaute | **PASS** |
| `scripts/ui/**/*.gd` | Keine DE-Spielertexte | **PASS** |
| `system_ui_controller.gd` | Keine Umlaute | **PASS** |
| `data/celestial_bodies/**` descriptions | Deutsch (z. B. `moon.tres`, `mars.tres`) | **Not Phase 1** (Lore) |
| `data/galaxy_systems/*.tres` descriptions | Deutsch (`solar_system.tres`, `proxima_system.tres`) | **Not Phase 1** (Lore) |

---

## 6. ObjectInfoPanel

| Prüfpunkt | Status | Evidence |
|-----------|--------|----------|
| `SensorPulseProgressLabel` existiert | **PASS** | `object_info_panel.tscn`, `@onready` in `.gd` |
| `InvestigateProgressLabel` nur Investigate | **PASS** | `_show_investigate_progress_ui` vs `_show_sensor_pulse_progress_ui` |
| Sensor Pulse eigenes Label | **PASS** | `_apply_sensor_pulse_controls` → `_show_sensor_pulse_progress_ui` |
| ScanButton-Text aus Scene-Default | **PASS** | `ScanWithDroneButton` `text = "Scan"`; `_scan_button_text_default` in `_ready` |
| Keine `tooltip_text`-Nutzung | **PASS** | 0 repo-weit |
| Signal-Panel-Layout konzeptionell | **PASS (static)** | `_apply_signal_panel_layout` etc. unverändert vorhanden; kein Layout-Refactor in Phase 1 |
| `tooltip_text` / Godot-Tooltips | **PASS** | Keine |

**RISK:** `mining_exhausted` in `object_info_panel.gd` vergleicht `mine_blocked` mit `GateUiTextDefinition.get_text(KEY_MINE_DEPLETED)` (String-Gleichheit) statt `blocked_reason_key` — funktional OK solange Text aus derselben Quelle kommt.

---

## 7. GateUiTextDefinition

| Prüfpunkt | Status | Evidence |
|-----------|--------|----------|
| Definition existiert | **PASS** | `resources/definitions/gate_ui_text_definition.gd` |
| Daten-Resource existiert | **PASS** | `data/ui_text/gate_ui_texts.tres` |
| Scan/Mine/Build/Storage nutzen Key + zentralen Text | **PASS** | `can_scan_object` (3 Keys), `can_mine_object`, `_build_gate_from_key`, `get_base_storage_blocked_reason_full`, Upgrade-not-enough |
| Sensor Pulse bei Discovery | **PASS** | `base_sensor_pulse_controller.gd`, `DiscoverySignalUiTextDefinition` |
| SurveyProbe Investigate bei Discovery | **PASS** | `survey_probe_mission_controller.gd`, `system_ui_controller.gd` Investigate-Pfade |
| Colonization nicht migriert | **PASS (by design)** | `COLONY_BLOCK_*` in `base_store.gd`, `get_build_base_colony_ship_gate` in `game_session.gd` |

**Ungenutzte Keys in `.tres` (Vorbereitung, kein Gate-Pfad):** `mine_storage_full`, `upgrade_max_level`, `colony_no_ship`, `colony_not_enough_resources`, `colony_requirement_missing`.

---

## 8. Dead Code / Phase-1-Reste (nur gemeldet)

| Fund | Datei | Einschätzung |
|------|-------|--------------|
| `get_scan_button_label_for_target_state()` / `get_rescan_button_label_for_target_state()` ohne Caller | `game_session.gd` | Tot oder für späteres UI-Wiring; Button zeigt nur „Scan“ |
| `SCAN_BLOCK_NO_LAYER` Konstante | `game_session.gd` | Legacy-String neben Gate-System |
| `ColonizationNoShipTooltipTemplate` Node-Name | `object_info_panel.tscn` | Irreführender Name; funktional Label-Template |
| `KEY_UPGRADE_MAX_LEVEL` in Gate-Resource, Gate liefert bei Max-Level leeren `blocked_reason` | `gate_ui_texts.tres`, `upgrade_panel.gd` | Key ungenutzt; Max-Level über Scene-Captions |
| `KEY_MINE_STORAGE_FULL` | `gate_ui_texts.tres` | Kein `can_mine_object`-Pfad (Storage block nur Automation/Storage-UI) |
| Colony-Keys in `gate_ui_texts.tres` | — | Nicht an `COLONY_BLOCK_*` angebunden |
| `PROJECT_OVERVIEW.md` erwähnt noch „Tooltips“ für Hover | Doku veraltet | Kein Code-Problem |
| `full_project_cleanup_audit_v0_1.md` | — | Historischer Stand; nicht aktualisiert |

Keine alten `EnterTooltip`-Nodes oder `_enter_tooltips`-Variablen gefunden.

---

## Open Items

Nur echte Phase-1-Reste oder kleine Nachzieh-Arbeiten:

1. **`SCAN_BLOCK_NO_LAYER`** — letzter Scan-Gate-String außerhalb `GateUiTextDefinition` (`game_session.gd`).
2. **Scan-Button-Progressions-Labels** — API `get_scan_button_label_for_target_state()` existiert, UI nutzt nur Scene-`"Scan"` (war schon vor Cleanup ein UX-Gap; Hardcode-Entfernung erfüllt, dynamische Labels optional).
3. **Colonization-Blockgründe** — bewusst nicht auf `GateUiTextDefinition` (Keys in `.tres` bereits vorbereitet).
4. **Ungenutzte Gate-Keys** — `mine_storage_full`, `upgrade_max_level`, `colony_*` (Aufräumen oder in Phase 2 anbinden).
5. **Deutsche Planet-/System-Lore** — kein Phase-1-UI-Scope; separater Content-Pass.

---

## Not Phase 1 / Move to Phase 2

- `system_ui_controller` typisieren, `has_method`/`call` reduzieren
- ObjectInfoPanel Layout-Subscene / Signal-Layout dokumentieren oder extrahieren
- TopHUD-Hover vs Panel-Hover deduplizieren
- Per-object discovery refresh statt full `apply_for_system`
- Audio path table → Resource
- Controller-Splits (`game_session`, `automation_controller`)
- **Discovery Pulse blocked strings** — laut Original-Roadmap Phase 2; faktisch bereits in Phase 1 über `DiscoverySignalUiTextDefinition` erledigt
- Deutsche **Lore** in celestial/galaxy `.tres`
- Build queue / Production-Timer-UI (`production_definition.gd` Kommentar ColonyShip timer)
- `mine_blocked` → `blocked_reason_key` in ObjectInfoPanel (Robustheit)

---

## 9. Smoke-Test-Checkliste

Manuell in Godot 4.6.1 (nicht im Rahmen dieses Audits ausgeführt):

- [ ] **New Game** — startet ohne Parser-/Runtime-Fehler
- [ ] **Signal Investigate** — Progress auf `InvestigateProgressLabel`; Blockgründe aus Discovery-Texts
- [ ] **Sensor Pulse** — Progress auf `SensorPulseProgressLabel` (nicht Investigate-Label); Kosten/Block EN
- [ ] **Scan** — Hidden/Signal nicht scannbar; Known ohne Drone → „No scan drone available“
- [ ] **Rescan** — Button sichtbar/verhalten wie vorher (Label ggf. weiterhin „Scan“)
- [ ] **Mine** — ohne Scan → „Scan required“; depleted → „Resource depleted“
- [ ] **Build** — ohne Ressourcen / Drone-Limit / Ship-Limit — korrekte Meldungen
- [ ] **Storage full** — Storage-Panel-Zeile + Automation-Recall-Verhalten
- [ ] **Save during Investigate** — cancel + refund laut `save_behavior_v0_1.md`
- [ ] **Save during Sensor Pulse** — cancel + refund Survey Data
- [ ] **Galaxy Enter Status** — `AccessStatusLabel` sichtbar, keine Enter-Tooltips

---

## Recommended Next Step

**Phase 2, Task 1 (klein):** `SCAN_BLOCK_NO_LAYER` in `GateUiTextDefinition` + `gate_ui_texts.tres` nachziehen und `get_scan_button_label_for_target_state()` in `system_ui_controller` → `info["scan_button_text"]` verdrahten (nur wenn Progressions-Labels gewünscht).

Alternativ **Phase 2 laut Audit:** `system_ui_controller` — typisierte `ObjectInfoPanel`-Referenz und Reduktion der `has_method`-Calls, ohne Gameplay-Änderung.

---

*Generated by static closure audit. Re-run after gameplay changes or before release tagging.*
