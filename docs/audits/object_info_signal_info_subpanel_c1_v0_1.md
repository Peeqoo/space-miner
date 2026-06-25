# ObjectInfo SignalInfoSubPanel Phase C1 — Audit v0.1

**Date:** 2026-06-07  
**Scope:** Presentation-only extraction of SIGNAL / `DISCOVERY_SIGNAL` UI from `ObjectInfoPanel` into `SignalInfoSubPanel`.  
**Verdict:** **PASS**

---

## Kurzfassung

Phase C1 (Option C aus `docs/design/object_info_signal_layout_refactor_plan_v0_1.md`) ist umgesetzt: SIGNAL-spezifische Darstellung (Lore, Investigate-Button, Investigate-Progress, Economy-Block für Signal) lebt in einer eigenen Subscene. `ObjectInfoPanel` bleibt Host; die öffentliche API (`show_body_info`, `show_poi_info`, `show_empty`, `apply_investigate_progress`, `set_distance_text`) ist unverändert. KNOWN-Layout (Ressourcen, Orbit, Scan/Mine/Recall, SensorPulse auf Home Base) bleibt im Monolithen. Keine Gameplay-, Gate-, Save- oder Tooltip-Änderungen.

---

## Alte Struktur → Neue Struktur

| Bereich | Vorher (Monolith) | Nachher (C1) |
|--------|-------------------|--------------|
| Signal-Lore | Host `LorePanel` + `_fit_signal_lore_text_height()` | `SignalInfoSubPanel` / `LorePanel` (kompakt, kein 80px-Min) |
| Investigate UI | `GridContainer/InvestigateButton`, root `InvestigateProgressLabel` | `SignalInfoSubPanel/InvestigateButton`, `InvestigateProgressLabel` |
| Signal Economy-Text | Host `EconomyBlockLabel` | `SignalInfoSubPanel/EconomyBlockLabel` |
| KNOWN Lore / Ressourcen / Grid | Host unverändert | Host unverändert (sichtbar wenn `is_discovery_signal == false`) |
| Investigate-Signal | `ObjectInfoPanel.investigate_requested` | Subpanel `investigate_pressed` → Host re-emittiert `investigate_requested` |
| SensorPulse-Progress | Host `SensorPulseProgressLabel` | Host (nur KNOWN / Home Base) |

**Host-Toggle bei `is_discovery_signal`:** Known-Sections aus (`DividerB`–`GridContainer` via `_set_resource_section_visible` + `_set_known_presentation_visible`); `signal_info_sub_panel.visible = true` + `apply_signal_info()`. Bei KNOWN: `signal_info_sub_panel.reset()` + `visible = false`.

---

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scenes/ui/system/signal_info_sub_panel.tscn` | **Neu** — kompakte Signal-UI-Subscene |
| `scripts/ui/system/signal_info_sub_panel.gd` | **Neu** — `class_name SignalInfoSubPanel`, `apply_signal_info`, progress, `investigate_pressed` |
| `scripts/ui/system/signal_info_sub_panel.gd.uid` | **Neu** — Script-UID |
| `scenes/ui/system/object_info_panel.tscn` | Instanz `SignalInfoSubPanel`; root Investigate-Controls entfernt |
| `scripts/ui/system/object_info_panel.gd` | Host-Delegation, Layout-Mode-Vereinfachung, keine Host-Investigate-Nodes |
| `scripts/debug/smoke_tests/object_info_signal_layout_smoke_test.gd` | Node-Pfade → `SignalInfoSubPanel/...` |
| `scripts/debug/smoke_tests/sensor_pulse_progress_label_cleanup_smoke_test.gd` | Investigate-Label-Pfad → Subpanel |

**Nicht geändert:** `GameSession`, `SystemUIController`, Discovery/Survey/Sensor-Controller, Scan/Mine/Automation, `SAVE_VERSION`, `tooltip_text`.

---

## Entfernte Runtime-Layout-Workarounds

| Workaround | Status |
|------------|--------|
| `_apply_signal_panel_layout()` | Ersetzt durch `_apply_discovery_layout_mode()` + `_set_known_presentation_visible()` |
| `_fit_signal_lore_text_height()` | **Entfernt** — Lore-Shrink liegt im Subpanel-Layout (kein Host-Scroll-Min 80px) |
| `_get_lore_text_wrap_width()` | **Entfernt** |
| Host `InvestigateProgressFormatTemplate` / `_format_investigate_progress()` | **Entfernt** — Format im Subpanel |
| Signal-spezifisches Host-Lore `custom_minimum_size`-Zeroing | **Entfernt** — Host-Lore bei Signal hidden |
| Root `InvestigateButton` / `InvestigateProgressLabel` in `.tscn` | **Entfernt** |

---

## Beibehaltene Workarounds (mit Begründung)

| Workaround | Begründung |
|------------|------------|
| `_apply_discovery_layout_mode(true)` — Panel `custom_minimum_size.y = 0`, `resource_panel` min zero | VBox behält sonst KNOWN-Mindesthöhen für versteckte Resource-Section |
| `_queue_panel_layout_refresh(is_signal)` — `offset_bottom = offset_top + content_height` bei Signal | `system_scene.tscn` verankert Panel mit festem `offset_bottom`; ohne Shrink bleibt Leerraum |
| `_restore_known_lore_layout()` bei KNOWN | Stellt Lore-Scroll/Panel-Mindestgrößen nach SIGNAL→KNOWN-Wechsel wieder her |
| `_set_resource_section_visible()` | Ressourcen-Block für Signal ausblenden (wie vor C1) |

---

## Tests (Pflicht-Smokes)

| Smoke | Ergebnis | Anmerkung |
|-------|----------|-----------|
| `object_info_signal_layout_smoke_runner.tscn` | **PASS** | Signal 146px, KNOWN 311px, Δ=165px; investigate/sensor getrennt |
| `sensor_pulse_progress_label_cleanup_smoke_runner.tscn` | **PASS WITH NOTES** | Test E: zweiter Pulse-Start übersprungen (aktiver Pulse/Gate) |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | **PASS WITH NOTES** | Test F: partielle Idle-Drone-Prüfung |
| `object_info_recall_button_language_pass_smoke_runner.tscn` | **PASS** | Recall EN |
| `object_info_scan_drone_assign_ui_smoke_runner.tscn` | **PASS WITH NOTES** | Test D: partielle Idle-Drone-Prüfung |
| `object_info_multi_ms_ui_smoke_runner.tscn` | **PASS** | |

**Regressionen in Signal-Smoke:** `SAVE_VERSION = 1`, `tooltip_text_count = 0`, Scan/Mine „Scan“/„Mine“, SIGNAL→KNOWN restore, InvestigateProgress ≠ SensorPulseProgress.

---

## Risiken

1. **Subpanel-Lore ohne dynamisches Height-Fitting** — kürzer als pre-C1 (~146 vs ~158px); Smoke PASS; lange Lore könnte Panel höher machen (autowrap).
2. **Zwei Economy-Labels** — Host für KNOWN scan/mine/colony/sensor; Subpanel für Signal; Host wird bei Signal explizit hidden.
3. **`apply_investigate_progress`** nutzt `DiscoverySignalUiTextDefinition` auf dem Host (Subpanel-Template parallel); Text konsistent mit Smoke.
4. **Godot class cache** — `SignalInfoSubPanel` erfordert gültige `.uid` / `--import` für strikte Typisierung in `object_info_panel.gd`.

---

## Akzeptanz-Checkliste

| Kriterium | Status |
|-----------|--------|
| `SignalInfoSubPanel` existiert | ✓ |
| `ObjectInfoPanel` public API unverändert | ✓ |
| SIGNAL-UI aus Monolith extrahiert | ✓ |
| KNOWN-Layout unverändert | ✓ |
| Keine Gameplay/Gate/Save-Änderung | ✓ |
| Pflicht-Smokes PASS / PASS WITH NOTES | ✓ |
| `SAVE_VERSION` = 1 | ✓ |
| `tooltip_text` = 0 | ✓ |

**Gesamt:** **PASS**
