# ObjectInfoDictKeys + SignalObjectInfoBuilder — Audit v0.1

**Date:** 2026-06-07  
**Scope:** Plan Steps 1–2 from `docs/design/system_ui_info_dict_typing_plan_v0_1.md` — key constants + SIGNAL builder extraction only.  
**Verdict:** **PASS**

---

## Kurzfassung

`ObjectInfoDictKeys` zentralisiert alle ObjectInfo-Dictionary-Keys als `StringName`-Constants (contract v0.1 §4). `SignalObjectInfoBuilder` übernimmt die bisherige Logik aus `SystemUIController._build_signal_marker_info()`. Der Controller delegiert nur noch; OUTPUT-Dict bleibt byte-identisch zum Vorher-Zustand. KNOWN-Pfad, ObjectInfoPanel, Scenes und Gameplay unverändert.

---

## Alte Struktur → Neue Struktur

| Vorher | Nachher |
|--------|---------|
| `_build_signal_marker_info()` ~44 Zeilen inline | `SignalObjectInfoBuilder.build()` |
| String-Literal-Keys im Controller-Overlay | Overlay-Keys via `ObjectInfoDictKeys` im Builder |
| Keine zentrale Key-Liste | `ObjectInfoDictKeys` + `SIGNAL_KEYS` / `SIGNAL_BUILDER_REQUIRED_KEYS` |
| `SignalMarker.build_signal_info()` unverändert | Unverändert (Welt-Quelle) |

```text
SignalMarker.build_signal_info()
        ↓
SignalObjectInfoBuilder.build(marker, survey_ctrl, base_id)
        ↓
SystemUIController._build_signal_marker_info()  [delegate]
        ↓
ObjectInfoPanel.show_body_info(info)
```

---

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/ui/object_info/object_info_dict_keys.gd` | **Neu** — alle §4-Keys, `SIGNAL_KEYS`, Duplikat-Check |
| `scripts/ui/object_info/signal_object_info_builder.gd` | **Neu** — investigate overlay |
| `scripts/system/controller/system_ui_controller.gd` | `_build_signal_marker_info` → 4-Zeilen-Delegate (−40 Zeilen Logik) |
| `scripts/debug/smoke_tests/object_info_signal_builder_smoke_test.gd` | **Neu** — Tests A–C |
| `scripts/debug/smoke_tests/object_info_signal_builder_smoke_runner.tscn` | **Neu** |

**Nicht geändert:** `object_info_panel.gd`, `signal_info_sub_panel.gd`, `signal_marker.gd`, Scenes, `SAVE_VERSION`, `tooltip_text`, KNOWN-Builder-Pfade.

---

## Zentralisierte Keys

Alle Keys aus Plan §4.1–§4.8 als `const …: StringName` in `ObjectInfoDictKeys`.

**Im Builder aktiv genutzt (Overlay):**

- `CAN_INVESTIGATE_SIGNAL`, `INVESTIGATE_BLOCKED_REASON`, `INVESTIGATE_IN_PROGRESS`
- `LORE_TEXT`, `SCAN_STATE` (nur bei `in_progress`)
- `IS_INVESTIGATE_ACTIVE`, `INVESTIGATE_PROGRESS`, `INVESTIGATE_PROGRESS_TEXT`

**Noch nicht migriert (bewusst):**

- `ObjectInfoPanel`, `ScanInfoBuilder`, `SignalMarker.build_signal_info()` — weiterhin String-Literale
- `discovery_complete_message` — nicht gesetzt (wie vorher)
- `system_economy_blocked_reason`, `mining_bonus` — unberührt

---

## Aus SystemUIController entfernte Logik

Verschoben nach `SignalObjectInfoBuilder.build()`:

1. `survey_probe_mission_controller.is_investigate_active` / `can_investigate_signal`
2. Fallback `REASON_BASE_MISSING` wenn Controller null
3. `REASON_IN_PROGRESS` wenn in_progress ohne can_investigate
4. Investigate-Felder setzen
5. Active-lore + `SCAN_UNKNOWN` bei in_progress
6. Progress + `format_investigate_progress`

---

## Verhalten / Gleichheit

Smoke **Test C** vergleicht `SignalObjectInfoBuilder.build()` mit `SystemUIController._build_signal_marker_info()` — **vollständige Dict-Gleichheit** (Größe + alle Key/Value-Paare) im System-Szenen-Kontext.

Pflicht-SIGNAL-Keys aus `build_signal_info()` + Overlay bleiben erhalten; `can_scan_with_drone` / `can_mine_with_ship` / recall flags bleiben `false`.

---

## Tests

| Smoke | Ergebnis |
|-------|----------|
| `object_info_signal_builder_smoke_runner.tscn` | **PASS** (A: keys; B: shape; C: delegation equality) |
| `object_info_signal_layout_smoke_runner.tscn` | **PASS** |
| `sensor_pulse_progress_label_cleanup_smoke_runner.tscn` | **PASS WITH NOTES** |
| `galaxy_transition_repeated_survey_probe_smoke_runner.tscn` | **PASS** (exit 0) |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | **PASS WITH NOTES** |

`SAVE_VERSION = 1`, `tooltip_text = 0` — bestätigt in Builder-Smoke.

---

## Risiken

| Risiko | Mitigation |
|--------|------------|
| Key-Constant-Typo | `SIGNAL_KEYS` Duplikat-Check + Smoke A |
| Builder/Controller drift | Smoke C full dict equality |
| Global class cache | Godot `--import` nach neuen Scripts |
| Frühe Constants-Nutzung nur im Builder | Panel-Migration bewusst Step 4 |

---

## Akzeptanz

| Kriterium | Status |
|-----------|--------|
| `ObjectInfoDictKeys` existiert | ✓ |
| `SignalObjectInfoBuilder` existiert | ✓ |
| Controller delegiert SIGNAL-Pfad | ✓ |
| OUTPUT-Dict kompatibel | ✓ (Smoke C) |
| KNOWN-Pfad unverändert | ✓ |
| Keine UI/Scene/Gameplay/Save-Änderung | ✓ |
| Pflicht-Smokes PASS / PASS WITH NOTES | ✓ |
| `SAVE_VERSION` = 1 | ✓ |
| `tooltip_text` = 0 | ✓ |

**Gesamt:** **PASS**

---

## Nächster Step (nicht in diesem PR)

Plan Step 3: `KnownObjectInfoBuilder` + Overlays — **nicht** beginnen, bis Step 2 stabil im Mainline ist.
