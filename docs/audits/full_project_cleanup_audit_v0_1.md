# Space Miner Full Project Cleanup Audit

## 0. Audit Scope

| Field | Value |
|--------|--------|
| Repository | https://github.com/Peeqoo/space-miner |
| Audit date | 2026-05-20 |
| Engine target | Godot 4.6.1 |
| Branch | `main` |
| Commit | `150a9b69e8f254a84e6e04b6fc38f88f82c4155e` |
| Method | Static read-only analysis of repo workspace (no Godot Editor run, no playtest) |

### What was reviewed

- All `scripts/**/*.gd` (~70+ script files; largest files line-counted)
- `scenes/**/*.tscn`, `data/**/*.tres`, `resources/definitions/**/*.gd`
- `project.godot`, autoload wiring
- Targeted ripgrep passes: signals, NodePaths, hardcoded strings, `_process`, save/load, blocked_reason, legacy keywords

### What was NOT reviewed

- Runtime playthrough / screenshots
- Full `.import/` asset metadata
- Addons (none significant in `project.godot`)
- CI/CD, export presets, multiplayer
- Shader/visual quality beyond structural notes
- Complete line-by-line review of `automation_controller.gd` (~2190 LOC) and `game_session.gd` (~1891 LOC)

---

## 1. Executive Summary

### Gesamtzustand

**Bewertung: Solider v0.1-Prototyp mit klarer Richtung, aber hoher Konzentration in wenigen God-Dateien.**

Das Projekt folgt dem gewünschten Loop (Discover → Investigate → Scan → Mine → Upgrade → Expand) und trennt **DiscoveryState** (HIDDEN/SIGNAL/KNOWN) von **ScanState** (UNKNOWN/BASIC/DEEP/SPECIAL) in der Praxis weitgehend korrekt. Daten liegen überwiegend in `data/` und `resources/definitions/`. UI-Scenes existieren für die Hauptpanels; Runtime-Gates und State-Updates liegen zu Recht im Code.

### Größte technische Risiken

| # | Risiko | Severity |
|---|--------|----------|
| 1 | `automation_controller.gd` (~2190 Zeilen) — Mining/Scan/Spawn/Save/Audio/Orbit in einer Datei | **High** |
| 2 | `game_session.gd` (~1891 Zeilen) — Gates, Discovery bootstrap, Economy, Colonization, Save | **High** |
| 3 | `system_ui_controller.gd` (~1142 Zeilen, ~67× `has_method`/`call`) — fragile Panel-Kopplung | **High** |
| 4 | `object_info_panel.gd` (~910 Zeilen) — Runtime-Layout (`offset_bottom`, `custom_minimum_size`) | **Medium** |
| 5 | Verstreute `blocked_reason`-Strings (GameSession, BaseStore, Controller) — Lokalisierung/UX-Inkonsistenz | **Medium** |
| 6 | Scan-SurveyData-Rewards als `const` in `game_session.gd`, nicht in Balance | **Medium** |
| 7 | `apply_for_system()` baut alle SignalMarker neu (nach Pulse) — teuer, aber korrekt | **Low–Medium** |
| 8 | Save: aktive Missionen abgebrochen, nicht fortgesetzt (by design v0.1) | **Medium** (Dokumentation) |

### Größte UI/HUD-Probleme

- **ObjectInfoPanel**: Signal-Kompaktlayout per Code (`_apply_signal_panel_layout`, Zeilen ~214–330 in `object_info_panel.gd`) — funktional, wartungsintensiv.
- **Doppelte Progress-Anzeige**: `InvestigateProgressLabel` wird auch für Sensor-Pulse-Progress wiederverwendet (`_apply_sensor_pulse_controls`, ~663–707).
- **Statischer Button-Override**: `scan_button_text = "Scan"` in `system_ui_controller.gd` (~569, ~602) obwohl Scene bereits `"Scan"` hat.
- **Deutsche + englische UI-Mischung** in Scenes/Code (z. B. Recall-Buttons `"Drone zurück"` in `object_info_panel.tscn`, englische Blockgründe).

### Größte Datengetriebenheits-Probleme

- **Survey Data**: Keine `data/planet_resources/survey_data.tres` — **absichtlich OK**; Base-Ressource über String-ID `SurveyData` / `GameBalanceDefinition.RESOURCE_SURVEY_DATA`.
- **Blocked reasons / Gate-Texte**: größtenteils **Code-Konstanten**, nur Survey-Investigate teilweise in `discovery_signal_ui_texts.tres`.
- **Scan-Belohnungen** (+10/+25/+50): `game_session.gd` ~1227–1229, nicht `v0_1_balance.tres`.
- **Survey-Investigate-Belohnung** (+5): `survey_probe_mission_controller.gd` ~8.
- **`base_sensor_max_visible_signals`**: noch in Balance, Gate **entfernt** — Inspector-Feld verwirrend (Legacy).

### Größte Legacy-/Duplikat-Probleme

- `AutomationController` Fallbacks `DEFAULT_SCAN_DURATION_FALLBACK = 2.0` (~16) vs Balance `basic_scan_duration = 35` — irreführend bei fehlendem Unit-Def.
- `_merge_legacy_cargo_into_dictionary` in `automation_controller.gd` — Save-Kompatibilität.
- `DiscoverySignalUiTextDefinition` + viele `FALLBACK_*` im Code — doppelte Wahrheit.
- Gate-Dicts (`can_scan_object`, `can_mine_object`, `can_investigate_signal`, `can_start_sensor_pulse`) — gleiches Muster, vier Implementierungen.

### Top 10 Cleanup-Aufgaben (Priorität)

1. **Blocked-Reason-Texte** in `data/ui_text/` oder bestehende UI-Text-Ressource zentralisieren (Low–Medium Risiko).
2. **Scan/Investigate/Pulse-Rewards** in `v0_1_balance.tres` verschieben (Medium).
3. **`base_sensor_max_visible_signals`** aus Balance entfernen oder dokumentieren/als UI-Hinweis only (Low).
4. **ObjectInfoPanel**: Sensor-Progress eigenes Label in `.tscn` (Low).
5. **Englische Gate-Strings** für Sensor Pulse in UI-Text-Ressource (`base_sensor_pulse_controller.gd` ~8–12) (Low).
6. **ProductionPanel** `"timer TODO"` Kommentar/Text bereinigen (`production_panel.gd` ~221) (Low).
7. **Recall-Button-Texte** vereinheitlichen (DE→EN oder zentral) in `.tscn` (Low).
8. **`system_ui_controller`**: `ObjectInfoPanel` typisieren, `has_method`-Calls reduzieren (Medium, schrittweise).
9. **Hover-Details** TopHUD vs Panels auf Duplikate prüfen (Medium).
10. **Dokumentation Save-Verhalten** (Probe/Pulse cancel+refund) in `docs/` (Info).

### Was auf keinen Fall jetzt refactored werden sollte

- **`object_scan_store.gd`** / `remaining_resources_by_object` Semantik
- **`automation_controller.gd`** Mining-State-Machine / Cargo-Loop
- **Discovery bootstrap** in `game_session.ensure_default_discovery_for_system`
- **SurveyProbe-Missions-Controller** Investigate-Flow
- **Scan Rescan vs Progress** Logik in `get_scan_target_state_or_rescan_state`
- **Großes Aufspalten von `game_session.gd`** ohne Tests und Save-Matrix

---

## 2. System Map

| System | Hauptdateien | Datenquellen | Szenen | Runtime-Controller | UI | Persistenz | Risiko |
|--------|--------------|--------------|--------|-------------------|-----|------------|--------|
| GameSession / Autoloads | `game_session.gd`, `scene_flow.gd`, `save_manager.gd`, `audio_manager.gd` | `data/balance`, `data/game_start`, Stores | `main.tscn` | Self + delegates | Indirect | `to_save_data` / `apply_save_data` | **High** |
| Stores | `base_store.gd`, `object_scan_store.gd`, `automation_store.gd`, `system_entry_store.gd` | In-memory + save blobs | — | — | — | Per-store `to_save_data` | **High** |
| Discovery visibility | `system_discovery_controller.gd` | Body/POI `default_discovery_state` | `signal_marker.tscn` | `SystemDiscoveryController` | Via markers | `object_scans` discovery states | **Medium** |
| SignalMarker | `signal_marker.gd` | `SignalTypeDefinition`, UI texts | `signal_marker.tscn` | Spawn in discovery controller | ObjectInfo via `build_signal_info` | — | **Low–Medium** |
| SignalTypeDefinition | `signal_type_definition.gd` | `data/discovery_signal_types/*.tres` | — | — | Pre-reveal labels (centralized) | — | **Low** |
| Base Sensor Pulse | `base_sensor_pulse_controller.gd` | `v0_1_balance.tres`, body sensor fields | — | `BaseSensorPulseController` | ObjectInfoPanel button | Cancel+refund on save | **Medium** |
| SurveyProbe | `survey_probe_mission_controller.gd`, `survey_probe_unit.gd` | Units, balance, UI texts | `survey_probe_unit.tscn` | Mission controller | Investigate UI | Cancel+refund probes on save | **Medium** |
| ScanDrone | `automation_controller.gd`, `game_session.gd` | `data/units/scan_drone.tres`, balance | `drone.tscn` | AutomationController | Scan button gate | Automation runtime snapshot | **High** |
| MiningShip | `automation_controller.gd` | `data/units/mining_ship.tres`, balance | `mining_ship.tscn` | AutomationController | Mine button gate | Same | **High** |
| remaining_resources | `object_scan_store.gd` | `ScannedResourceEntry` / scan reveal | — | GameSession API | Resource rows | `object_scans` save | **Critical** |
| Storage | `base_store.gd` | Upgrades, balance | — | Automation unload | StoragePanel, TopHUD | `bases` save | **Medium** |
| Production / Build | `production_catalog.gd`, `base_store.gd` | `data/production/*.tres` | `production_panel.tscn` | GameSession build APIs | ProductionPanel | Base units/resources | **Medium** |
| Upgrades | `upgrade_catalog.gd`, `upgrade_definition.gd` | `data/upgrades/**` | `upgrade_panel.tscn` | BaseStore | UpgradePanel | Base upgrade levels | **Medium** |
| ColonyShip | `game_session.gd`, colonization def | `data/colonization`, balance | — | GameSession `_process` | Galaxy HUD, colonize btn | Operations array in save | **Medium** |
| Galaxy | `galaxy_map.gd`, `galaxy_system_node.gd` | `data/galaxy/**` | galaxy scenes | SceneFlow | `galaxy_map_hud.gd` | System unlock lists | **Medium** |
| HUD / TopHUD | `top_hud.gd`, `top_hud_hover_panel.gd` | Base resources live | `top_hud.tscn` | SystemUIController refresh | TopHUD | — | **Low–Medium** |
| ObjectInfoPanel | `object_info_panel.gd` | Info dict from controller | `object_info_panel.tscn` | SystemUIController builds dict | Self | — | **Medium** |
| BaseManagementPanel | `base_management_panel.gd` | — | `.tscn` | SystemUIController | Self | — | **Low** |
| Audio | `audio_manager.gd` | Hardcoded path map in script | — | All systems | — | — | **Low** |
| Save/Load | `save_manager.gd`, GameSession | Save v1 blob | — | Pre-save cancel hooks | — | Full session | **High** |

### Quellen der Wahrheit (Kurz)

| Concern | Sollte sein | Darf NICHT parallel sein |
|---------|-------------|-------------------------|
| DiscoveryState | `ObjectScanStore` via `GameSession` | UI, Marker |
| ScanState | `ObjectScanStore` | SignalMarker |
| Base resources (Iron/SD/…) | `BaseStore` | ObjectInfoPanel Berechnung |
| remaining_resources | `ObjectScanStore` | Definition deposits nach Init |
| Active Scan/Mine jobs | `AutomationController` runtime + snapshot | `AutomationStore` allein |
| Investigate missions | `SurveyProbeMissionController` | GameSession |
| Sensor Pulse runtime | `BaseSensorPulseController` | Save (v0.1) |
| Scan/Mine gates | `GameSession` | UI-eigene Regeln |

---

## 3. Findings by Category

### A — UI / Inspector vs Code

**Kurzfazit:** Scenes sind gut angelegt; Runtime-Gates und dynamische Werte gehören in Code. Problem: zu viel **Layout-Logik** und **Text-Overrides** im `object_info_panel.gd` und verstreute **blocked_reason**-Strings.

| ID | Datei (ca.) | Problem | Warum | Risiko | Empfehlung | Sofort? | Gehört in |
|----|-------------|---------|-------|--------|------------|---------|-----------|
| A1 | `object_info_panel.gd` 214–330 | Signal-Layout: `custom_minimum_size`, `offset_bottom`, `reset_size` | Scene-Layout wird zur Laufzeit überschrieben | Medium | Eigenes kompaktes Sub-Scene-Layout oder Container-Mode dokumentieren | Nein | Code (dynamic) + Scene |
| A2 | `object_info_panel.gd` 663–707 | Sensor-Pulse nutzt `InvestigateProgressLabel` | Semantische Vermischung | Low | Eigenes `SensorPulseProgressLabel` in `.tscn` | Ja | Scene |
| A3 | `system_ui_controller.gd` 569, 602 | `scan_button_text = "Scan"` hardcoded | Duplikat zu Scene-Default | Low | Nur Scene-Text nutzen | Ja | Scene |
| A4 | `object_info_panel.tscn` | Recall-Buttons DE, Rest EN | Inkonsistenz | Low | Ein Sprach-Set in `.tscn` oder UI-Text | Ja | Scene / i18n |
| A5 | `object_info_panel.gd` 479–481 | Lore fallback `"Keine Beschreibung verfügbar."` | Nicht zentralisiert | Low | `data/ui_text` | Ja | Resource |
| A6 | `system_ui_controller.gd` ~67× `has_method`/`call` | Duck typing auf Panels | Refactor-Brüche | Medium | Typed `@export` Panel refs | Nein | Code |
| A7 | `production_panel.gd` ~221 | `"instant build — timer TODO"` | Unfertig sichtbar | Low | Text entfernen oder Feature | Ja | Scene/Text |
| A8 | `upgrade_panel.gd` | Hover-Fallback aus Scene-Label | OK pattern | Info | Behalten | Nein | Scene + Code |
| A9 | `top_hud_hover_panel.gd` 44, 91 | `custom_minimum_size` im Code | Dynamische Hover-Höhe | Low | OK wenn dynamisch | Nein | Code |
| A10 | `object_info_panel.gd` 1124–1157 | `get_nodes_in_group("system_ui_controller")` Fallback | Entkoppelt | Medium | Signale nur über Scene-Tree wiring | Nein | Code (fallback OK) |

**Top 10 UI-Code → Scene/Resource (Migration)**

1. Blocked reasons → `data/ui_text/gates.tres` (neu)
2. Sensor Pulse strings → UI-Text
3. Scan button label → nur `.tscn`
4. Lore empty fallback → UI-Text
5. Investigate progress format → bereits `discovery_signal_ui_texts.tres` (erweitern)
6. Economy block labels → UI-Text
7. ProductionPanel build time line → Scene
8. Separate Sensor progress label
9. DE recall buttons → EN in `.tscn`
10. Colonization button texts → prüfen `.tscn` vs Code

**UI-Cleanup-Reihenfolge:** A3 → A2 → A4 → A5 → A7 → A1 (zuletzt, testintensiv)

---

### B — Hardcoded Texts

| ID | Text / Bereich | Fundstellen | Aktuell | Ziel | Risiko | Sofort? |
|----|----------------|-------------|---------|------|--------|---------|
| B1 | Scan gates | `game_session.gd` 1222–1225 | Code const | UI-Text oder Balance-Metadaten | Medium | Nein |
| B2 | Mine gates | `game_session.gd` 966–970 | Code const | UI-Text | Medium | Nein |
| B3 | Build/Colony blocks | `base_store.gd` 15–26 | Code const | UI-Text | Low | Ja |
| B4 | Sensor Pulse blocks | `base_sensor_pulse_controller.gd` 8–12 | Code const | UI-Text | Low | Ja |
| B5 | Discovery investigate blocks | `discovery_signal_ui_text_definition.gd` + `.tres` | **Gut** — dual fallback | Nur `.tres` | Low | Nein |
| B6 | Unknown/Signal panel | `DiscoverySignalUiTextDefinition` | Centralized | — | Info | Nein |
| B7 | `"Scan"` override | `system_ui_controller.gd` | Code | Scene | Low | Ja |
| B8 | Sensor progress format | `system_ui_controller.gd` ~625 | Code format string | UI-Text template | Low | Ja |
| B9 | Storage full | `base_store.gd` 15 | Code | UI-Text | Low | Ja |
| B10 | `"Keine Beschreibung..."` | `system_ui_controller.gd` ~479 | Code | UI-Text | Low | Ja |

**False positive:** `push_warning(...)` Log-Strings dürfen im Code bleiben.

**False positive:** Dynamische `"%d%%"`, `"%d u"` Distanz, Ressourcen-Zahlen in TopHUD.

---

### C — Magic Numbers / Hardcoded Values

| ID | Wert | Datei | Zweck | Soll-Datenquelle | Risiko |
|----|------|-------|-------|------------------|--------|
| C1 | +10/+25/+50 SD | `game_session.gd` 1227–1229 | Scan rewards | `v0_1_balance.tres` | Medium |
| C2 | +5 SD | `survey_probe_mission_controller.gd` 8 | Investigate reward | Balance | Medium |
| C3 | 12s / 3s / 5 SD | `v0_1_balance.tres` | Sensor pulse | **OK** | Info |
| C4 | `2.0` scan fallback | `automation_controller.gd` 16 | Missing unit def | Unit + balance only | Medium |
| C5 | `1000` storage fallback | `base_store.gd` 12 | Missing upgrade | Upgrade tres | Low |
| C6 | `max_visible_signals = 2` | `v0_1_balance.tres` 9 | Unused gate | Remove or document | Low |
| C7 | Panel `offset_bottom` 380 | `system_scene.tscn` instanz | Fixed panel height | Scene (Known mode) | Medium |
| C8 | Lore min 80 | `object_info_panel.tscn` | Layout | Scene | Low |

---

### D — Data-Driven Architecture

| System | Status | Problem | Empfehlung |
|--------|--------|---------|------------|
| GameBalance / v0_1 | **Gut** | Scan rewards noch in GameSession | Rewards in balance |
| GameStart | **Gut** | `default_start.tres` | — |
| SystemBody / POI | **Gut** | `signal_type`, discovery, sensor priority | — |
| SignalTypeDefinition | **Gut** | `marker_texture` optional empty | — |
| Discovery UI texts | **Teilweise** | Fallbacks im Code | Reduce fallbacks |
| Production | **Gut** | Catalog | — |
| Upgrades | **Gut** | Catalog | — |
| Units | **Gut** | `data/units/*.tres` | — |
| SurveyData resource | **String-ID only** | Kein planet_resources tres | **OK by design** |
| planet_resources | **Deposit types** | Not for SurveyData | Do not add SD there |
| Audio | **Code map** | Paths in `audio_manager.gd` | Optional `data/audio` later |
| Blocked reasons | **Schwach** | Code constants | UI text resource |

**Survey Data — technische Herkunft (Antwort auf Audit-Frage):**

- Konstante: `GameBalanceDefinition.RESOURCE_SURVEY_DATA` → `&"SurveyData"`
- Lagerung: `BaseStore` → `base["resources"]["SurveyData"]` (int)
- Keine `ResourceDefinition`-`.tres` im Projekt
- Rewards/ Costs: Dictionaries mit Key `"SurveyData"` / StringName
- **Keine neue `data/planet_resources/survey_data.tres` empfohlen**

---

### E — Duplicate Logic

| Thema | Primäre Wahrheit | Sekundär / Duplikat | Risiko | Sofort? |
|-------|------------------|---------------------|--------|---------|
| Scan gate | `GameSession.can_scan_object` | UI ruft nur auf | Low | Nein |
| Mine gate | `GameSession.can_mine_object` | UI | Low | Nein |
| Investigate gate | `SurveyProbeMissionController.can_investigate_signal` | SystemUI + ObjectInfo | Low | Nein |
| Pulse gate | `BaseSensorPulseController.can_start_sensor_pulse` | SystemUI | Low | Nein |
| Build gates | `BaseStore.get_build_*_blocked_reason` | ProductionPanel | Low | Nein |
| Info dict | `SystemUIController._build_selected_object_info` | ObjectInfoPanel applies | Medium | Nein |
| TopHUD refresh | `_update_top_hud` | Viele Caller | Low | Nein |
| Progress format | `DiscoverySignalUiTextDefinition` | ObjectInfo local template | Low | Nein |
| Resource format | `NumberFormat` | — | **Gut** | Nein |
| Scan info | `ScanInfoBuilder` | Bodies/POI | **Gut** | Nein |
| Discovery apply | `SystemDiscoveryController.apply_for_system` | Pulse complete | Low | Nein |
| Cost spend | `BaseStore.spend_cost` | Pulse controller direct | Low | Nein |

---

### F — Legacy / Compatibility

| Fundstelle | Zweck | Noch nötig? | Risiko | Cleanup-Zeitpunkt |
|------------|-------|-------------|--------|-------------------|
| `automation_controller.gd` DEFAULT 2.0 fallbacks | Missing .tres | Ja (safety) | Medium | Nach Validierung entfernen |
| `_merge_legacy_cargo` | Old saves | Vermutlich ja | Medium | Mit Save v2 |
| `DiscoverySignalUiTextDefinition` FALLBACK_* | Missing .tres | Ja | Low | Behalten |
| `base_sensor_max_visible_signals` | Old cap | **Nein** als Gate | Low | Balance cleanup |
| `scan_info_builder` old PackedStringArray | Old .tres | Kompat | Low | Nach Datenmigration |
| `SceneFlow` change_scene fallback | Missing Main slot | Ja | Low | — |
| `VISUAL_LIGHTING_EXPERIMENT` blocks | Experiment | Optional | Info | Später |

---

### G — NodePaths / Connections

**Signals — Kategorien:**

| Typ | Beispiele | Bewertung |
|-----|-----------|-----------|
| B Dynamisch | `automation_controller` unit signals, survey probe | **OK** |
| C Doppelt möglich | `pressed.connect` ohne `is_connected` in einigen UI `_ready` | Prüfen — ObjectInfo nutzt `is_connected` (**gut**) |
| A Editor-fähig | Main menu, einige Panels | Könnte migriert werden |
| C Fallback | `object_info_panel` → `system_ui_controller` group | **Medium** |

**NodePaths:**

| Pfad | Datei | Risiko | Empfehlung |
|------|-------|--------|------------|
| `$Margin/Root/...` (tief) | `object_info_panel.gd` 17–50 | Medium | Scene root exports |
| `get_node_or_null` save slots | `main_menu.gd` 24–45 | Low | OK für variierte Rows |
| `system_light_controller` legacy star names | `system_light_controller.gd` 325+ | Low | Document |

**Groups:** `system_ui_controller`, `galaxy_map_root`, `system_planets` — sinnvoll.

---

### H — Runtime-State Ownership

| State | Owner | Falsche Zugriffe | Empfehlung |
|-------|-------|------------------|------------|
| DiscoveryState | ObjectScanStore | — | — |
| ScanState | ObjectScanStore | — | — |
| remaining_resources | ObjectScanStore | Rescan soll nicht re-init | Guard in complete |
| Base resources | BaseStore | Pulse spend via bases OK | Emit signals |
| Survey probe count | BaseStore | Mission controller consumes | — |
| Active investigate | SurveyProbeMissionController only | — | — |
| Scan drone map | AutomationController | — | — |
| Mining runtime | AutomationController dict | — | — |
| Sensor pulse | BaseSensorPulseController | Not saved v0.1 | OK |
| UI selection | SystemSelectionController | — | — |

**UI verändert Stores?** Indirekt nur via Actions (Scan/Mine/Build) — **OK**.

---

### I — Save/Load

| Bereich | Save | Load | Risiko | Tests |
|---------|------|------|--------|-------|
| Discovery/Scan states | `object_scans.to_save_data` | `apply_save_data` + `ensure_default_discovery` | Medium | Hidden/signal/known matrix |
| remaining_resources | In object_scans | Restored | **High** | Depleted after load |
| Base resources | bases save | bases apply | Medium | SD after pulse refund |
| Survey probe missions | **Cancelled**, probes refunded | Not restored | Medium | Save mid-investigate |
| Sensor pulse | **Cancelled**, cost refunded | Not active | Low | Save mid-pulse |
| Automation runtime | Snapshot + store | `apply_automation_save_if_pending` | **High** | Ships mid-flight |
| Camera | Pending dict | Restore in SystemScene | Low | — |
| Colonization ops | Array in GameSession | Re-applied | Medium | — |
| Automation missions store | Saved | May desync from runtime | Medium | — |

**Idempotenz:** `ensure_default_discovery_for_system` on load — bewusst; nicht doppelt in einem Frame aufrufen ohne Grund.

---

### J — GDScript Quality

| ID | Datei | Problem | Risiko | Sofort? |
|----|-------|---------|--------|---------|
| J1 | Große untypisierte `Dictionary` in UI info | Variant inference | Medium | Nein |
| J2 | `system_ui_controller` duck typing | Runtime errors | Medium | Nein |
| J3 | `minimum_size_changed` / `get_content_height` | **Behoben** laut Kontext | — | — |
| J4 | `bool(...)` vs `== true` | Inkonsistent | Info | Nein |
| J5 | State als `String` nicht enum | Tippfehler-Risiko | Medium | Später StringName enum |
| J6 | `class_name` gut genutzt | — | **Positiv** | — |

**Keine aktiven `get_content_height`-Aufrufe gefunden** (Audit-Search).

---

### K — Performance

| ID | Datei | Verhalten | Risiko | Empfehlung |
|----|-------|-----------|--------|------------|
| K1 | `automation_controller._process` | Mining/scan/orbit | Medium | Profiling |
| K2 | `system_ui_controller._process` | Distance text every frame | Low | Nur bei selection change |
| K3 | `game_session._process` | Colonization tick | Low | OK |
| K4 | `apply_for_system` on pulse | Full marker rebuild | Low–Medium | Per-object refresh später |
| K5 | `audio_manager._process` | Cooldowns | Low | OK |
| K6 | `system_scene._process` | Orbit guides | Low | OK |

---

### L — Audio

- Zentrale API: `AudioManager` mit `play_sfx_optional`, `play_music_optional` — **gut**
- SFX IDs als `StringName` im Code (`&"scan_complete"`) — akzeptabel v0.1
- Hardcoded OGG paths in `audio_manager.gd` ~48–52 — später data-driven
- World loops für scan/mining — disconnect in automation — prüfen bei recall

---

### M — Economy / Resources

- IDs: `Iron`, `Silicon`, `Ice`, `SurveyData` — konsistent in Balance
- `planet_resources/*.tres` = ScannedResourceEntry deposits — **nicht** Base-Lager
- `deposit_amount` auf entries — Mining-Init nach Scan
- `spend_cost` / `can_afford` — **Single API** in BaseStore
- Pulse cost `{SurveyData: 5}` in balance — **gut**
- Colony ship cost in `data/production/colony_ship.tres` — **gut**

**Risiko:** Scan reward constants outside balance (siehe C1).

---

### N — Scene Layout

| Scene | Node / Thema | Problem | Empfehlung |
|-------|--------------|---------|------------|
| `object_info_panel.tscn` | Instanz in `system_scene` offset_bottom 380 | Known height fixed | OK for known; signal uses code shrink |
| `object_info_panel.tscn` | LorePanel min 80 | Clip risk on signal | Code zeros on signal |
| `object_info_panel.tscn` | GridContainer many buttons | OK | — |
| `signal_marker.tscn` | No default texture | Fallback procedural in code | OK |
| `system_scene.tscn` | Controller nodes as siblings | Clear | — |

---

### O — Tests (Smoke-Test Plan)

Siehe **Section 19** unten (vollständiger Pfad).

---

## 4. Risk Matrix (Auszug)

| Datei | System | Risiko | Warum | Safe changes | Unsafe changes |
|-------|--------|--------|-------|--------------|----------------|
| `object_scan_store.gd` | remaining_resources | **Critical** | Mining truth | Text, logs | Init semantics |
| `game_session.gd` | All gates | **High** | God object | Text centralization | Split without tests |
| `automation_controller.gd` | Mining/Scan | **High** | State machine | Audio IDs | Cargo loop |
| `system_ui_controller.gd` | UI bridge | **High** | Duck typing | Remove "Scan" override | Rewrite selection |
| `object_info_panel.gd` | Panel layout | **Medium** | Runtime layout | Progress label split | Delete layout code blindly |
| `base_sensor_pulse_controller.gd` | Pulse | **Medium** | Cost/refund | UI text move | Reveal rules |
| `survey_probe_mission_controller.gd` | Investigate | **Medium** | SIGNAL→KNOWN | Reward to balance | Mission FSM |
| `system_discovery_controller.gd` | Markers | **Medium** | Full rebuild | — | Spawn rules |
| `discovery_signal_ui_texts.tres` | Copy | **Low** | — | Add keys | — |
| `v0_1_balance.tres` | Balance | **Low** | — | Rewards, remove dead fields | Rename without migrate |

---

## 5. Cleanup Roadmap

### Phase 1: Safe Cleanup (niedriges Risiko)

- Zentrale UI-Text-Keys für Gate-Strings (Scan/Mine/Pulse/Build)
- `scan_button_text` Hardcode in SystemUI entfernen
- Separates Sensor-Pulse-Progress-Label
- `base_sensor_max_visible_signals` aus Balance entfernen oder `@export` deprecated comment only
- ProductionPanel TODO-Text
- Recall-Button Sprache vereinheitlichen in `.tscn`
- Dokument `docs/save_behavior_v0_1.md` (cancel/refund rules)
- Scan/Investigate rewards → balance tres

### Phase 2: Medium Cleanup

- `DiscoverySignalUiTextDefinition` für Sensor Pulse blocked + progress templates
- `system_ui_controller`: typed panel references, reduce `call()`
- ObjectInfoPanel: dokumentieren warum Signal-Layout im Code bleibt
- TopHUD hover vs ObjectInfo deduplicate
- Per-object discovery refresh statt full `apply_for_system` (optional)
- Audio path table → resource

### Phase 3: Architecture Cleanup (später)

- Split `game_session.gd` (DiscoveryAPI, EconomyAPI, ColonizationAPI)
- Split `automation_controller.gd` (ScanService, MiningService)
- Save v2 mit mission restore oder explicit abort UI
- StringName enums for discovery/scan states
- ResourceDefinition catalog for UI display names
- Build queue/timer (ProductionPanel TODO)

### Do Not Touch Yet

- `object_scan_store.remaining_resources` mining/depleted logic
- `get_scan_target_state_or_rescan_state` / scan completion
- Survey probe investigate FSM
- `ensure_default_discovery_for_system` seeding rules
- Automation mining tick / unload / storage full
- Signal marker `build_signal_info` pre-reveal policy (Unknown/Signal labels)

---

## 6. First 10 Cursor Tasks

### Task 1 — Gate text resource skeleton

- **Ziel:** `data/ui_text/gate_texts.tres` + loader wie Discovery texts
- **Dateien:** neue resource, minimal `game_session.gd` read wrapper (optional Phase 1 nur Pulse)
- **Risiko:** Low
- **AK:** Alle Scan-Block-Strings aus einer Quelle
- **Commit:** `Add centralized gate UI text resource for v0.1`

### Task 2 — Move scan SD rewards to balance

- **Ziel:** Rewards in `v0_1_balance.tres`
- **Dateien:** `game_balance_definition.gd`, `v0_1_balance.tres`, `game_session.gd`
- **Risiko:** Low
- **AK:** Scan completion awards match balance values
- **Commit:** `Move scan SurveyData rewards to game balance`

### Task 3 — Sensor pulse UI strings

- **Ziel:** Pulse blocked reasons + progress template in UI text
- **Dateien:** `discovery_signal_ui_texts.tres` or new resource, `base_sensor_pulse_controller.gd`
- **Risiko:** Low
- **Commit:** `Centralize sensor pulse player-facing strings`

### Task 4 — Remove Scan text override

- **Ziel:** Delete lines setting `scan_button_text` in SystemUI
- **Dateien:** `system_ui_controller.gd`
- **Risiko:** Low
- **Commit:** `Use scene default Scan button label`

### Task 5 — Sensor pulse progress label

- **Ziel:** Dedicated label in ObjectInfoPanel scene
- **Dateien:** `object_info_panel.tscn`, `object_info_panel.gd`
- **Risiko:** Low
- **Commit:** `Add dedicated sensor pulse progress label`

### Task 6 — Deprecate max_visible_signals in balance

- **Ziel:** Comment/remove unused export
- **Dateien:** `game_balance_definition.gd`, `v0_1_balance.tres`
- **Risiko:** Low
- **Commit:** `Remove unused sensor signal cap from balance`

### Task 7 — Investigate reward to balance

- **Ziel:** `survey_probe_survey_data_reward` in balance
- **Dateien:** balance, `survey_probe_mission_controller.gd`
- **Risiko:** Low
- **Commit:** `Move survey probe SurveyData reward to balance`

### Task 8 — Save behavior doc

- **Ziel:** Document cancel/refund for probe and pulse
- **Dateien:** `docs/save_behavior_v0_1.md`
- **Risiko:** Info
- **Commit:** `Document v0.1 save cancel rules for active operations`

### Task 9 — ProductionPanel TODO text

- **Ziel:** Remove or hide timer TODO
- **Dateien:** `production_panel.gd`, `.tscn`
- **Risiko:** Low
- **Commit:** `Clean production panel build time copy`

### Task 10 — Recall button language pass

- **Ziel:** EN labels in object_info_panel.tscn
- **Dateien:** `object_info_panel.tscn`
- **Risiko:** Low
- **Commit:** `Unify ObjectInfoPanel recall button labels to English`

---

## 7. Appendix

### Suchbegriffe verwendet

`connect`, `blocked_reason`, `DISCOVERY_`, `SCAN_`, `legacy`, `fallback`, `_process`, `get_node`, `custom_minimum_size`, `SurveyData`, `apply_for_system`, `to_save_data`, `has_method`, `signal_type`, `minimum_size_changed`

### Erkannte TODOs

- `production_panel.gd` — build timer TODO
- Diverse `push_warning` — operational, not TODO

### Offene Fragen

1. Soll `base_sensor_max_visible_signals` komplett entfernt oder als Soft-Warnung im UI erscheinen?
2. Soll Save v0.2 aktive Pulse/Investigate fortsetzen statt refund?
3. Einheitliche Sprache DE vs EN für v0.1 Release?
4. Soll `ObjectInfoPanel` Signal-Layout langfristig eine eigene Subscene bekommen?
5. Ist `AutomationController` DEFAULT `2.0` s scan noch bewusst oder historischer Bug-Fallback?

---

## 19. Smoke-Test Plan (Pflichtpfad)

| # | Setup | Aktion | Erwartung | Relevante Dateien | Fehleranzeichen |
|---|--------|--------|-----------|-------------------|-----------------|
| 1 | New Game | Start | Earth known, 2 signals (Mars/Venus), hidden bodies | `game_session.ensure_default_discovery`, body `.tres` | Wrong visibility |
| 2 | — | Click signal | ObjectInfo: Unknown/Signal, Investigate visible, no Scan | `signal_marker.gd`, `system_ui_controller` | Scan on signal |
| 3 | — | Investigate | Probe flies, progress, lore | `survey_probe_mission_controller.gd` | Double mission |
| 4 | — | Complete investigate | KNOWN, body visible, marker gone | `discovery_controller`, GameSession | Stays SIGNAL |
| 5 | — | Scan | Drone mission, SD +10 basic | `game_session.can_scan_object`, automation | No drone |
| 6 | — | Rescan | Second mission, no SD | rescan path in automation complete | SD farm |
| 7 | — | Mine | Ship mines, storage up | automation mining loop | No cargo |
| 8 | — | Storage full | Mine blocked, message | base_store, automation | Silent fail |
| 9 | — | Deplete | depleted UI | object_scan_store | Regenerates |
| 10 | — | Build probe | Cost spent | production, base_store | Free build |
| 11 | Earth + ≥5 SD | Sensor Pulse | -5 SD, progress, +1 hidden→signal | `base_sensor_pulse_controller` | Cap block (removed) |
| 12 | — | Pulse again | Works with SD | same | No candidates msg wrong |
| 13 | Save during investigate | Save | Refund probe, warning | `save_manager`, survey controller | Lost probe |
| 14 | Save during pulse | Save | Refund SD, warning | `cancel_active_base_sensor_pulse` | Lost SD |
| 15 | Load | Continue | States restored | `apply_save_data` | Reset discovery |
| 16 | Colony | If unlocked | Operation progresses | game_session colonization | — |

---

## 23. Abschluss — Pflichtantworten

1. **Ist der Core stabil genug für Cleanup?**  
   **Ja**, für Phase-1-Cleanup (Texte, Balance-Verschiebung, kleine UI). Nicht für große Controller-Splits ohne Testmatrix.

2. **Gefährlichste Dateien?**  
   `object_scan_store.gd`, `automation_controller.gd`, `game_session.gd`, `system_ui_controller.gd`.

3. **Sicherster erster Cleanup-Schritt?**  
   Gate-/Pulse-Strings + Scan-Rewards in Balance + `"Scan"` Hardcode entfernen.

4. **5 Dateien nicht ohne Plan anfassen?**  
   `object_scan_store.gd`, `automation_controller.gd`, `game_session.gd` (discovery/bootstrap), `survey_probe_mission_controller.gd`, `automation_unit.gd` (orbit/mining).

5. **5 Dateien für sicheren UI-Cleanup?**  
   `system_ui_controller.gd` (nur Text-Zeilen), `object_info_panel.tscn`, `discovery_signal_ui_texts.tres`, `base_sensor_pulse_controller.gd` (strings only), `production_panel.tscn`.

6. **Inspector verwirrend?**  
   `base_sensor_max_visible_signals` (unused gate), `signal_type` vs alte Docs, viele `default_discovery_state` leer (= legacy known), `discoverable_by_base_sensor` defaults.

7. **Schon gut datengetrieben?**  
   Bodies/POIs, Productions, Upgrades, Units, Signal types, Balance pulse durations/costs, Galaxy systems.

8. **Noch nicht gut datengetrieben?**  
   Blocked reasons, scan/probe rewards, audio paths, teils UI copy, ObjectInfo signal layout.

9. **Refactors später?**  
   Controller splits, save mission continuity, per-object discovery refresh, i18n, ResourceDefinition catalog.

10. **Nächste Prompts?**  
    Tasks 1–4 + 6 aus Section 6; dann Save-doc; dann ObjectInfo layout spike (design only).

---

*End of audit — no project files were modified except this document.*

---

> **Superseded for current status by** [`full_project_cleanup_audit_v0_2.md`](full_project_cleanup_audit_v0_2.md) **(2026-06-07).** This v0.1 file remains the historical baseline from commit `150a9b69`.
