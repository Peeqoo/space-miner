# SensorPulseInfoOverlay Extraction — Audit v0.1

**Date:** 2026-06-07  
**Scope:** Plan Step 3 partial — extract `_apply_sensor_pulse_info_to_dict` only; no gameplay/UI scene changes.  
**Verdict:** **PASS**

---

## Kurzfassung

Die Sensor-Pulse-Felder für das ObjectInfo-Dictionary leben jetzt in `SensorPulseInfoOverlay.apply()`. `SystemUIController._apply_sensor_pulse_info_to_dict()` delegiert nur noch. Output-Dict bleibt identisch; `ObjectInfoPanel`, `BaseSensorPulseController` und Pulse-Gameplay unverändert.

---

## Alte Struktur → Neue Struktur

| Vorher | Nachher |
|--------|---------|
| ~30 Zeilen in `SystemUIController._apply_sensor_pulse_info_to_dict` | `SensorPulseInfoOverlay.apply()` |
| String-Literal-Keys | `ObjectInfoDictKeys` für alle 6 Pulse-Keys |
| Home-base gate + pulse state inline | Gleiche Logik, ausgelagert |

```text
_build_selected_object_info
  → _apply_sensor_pulse_info_to_dict(info)
      → SensorPulseInfoOverlay.apply(info, pulse_ctrl, base_id, is_home_base)
          → ObjectInfoPanel (unverändert)
```

---

## Verschobene Keys

Alle via `ObjectInfoDictKeys`:

| Key | Non-home | Home (idle) | Home (pulse active) |
|-----|----------|-------------|---------------------|
| `SHOW_SENSOR_PULSE` | `false` | `true` | `true` |
| `CAN_SENSOR_PULSE` | `false` | gate `ok` | unchanged early return |
| `SENSOR_PULSE_BLOCKED_REASON` | `""` | gate text | `""` (early return) |
| `SENSOR_PULSE_IN_PROGRESS` | `false` | `false` | `true` |
| `SENSOR_PULSE_PROGRESS_TEXT` | `""` | `""` | formatted progress |
| `SENSOR_PULSE_COST_TEXT` | `""` | cost display | `""` (early return) |

`OVERLAY_KEYS` auf dem Overlay dokumentiert die Smoke-Contract-Liste.

---

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/ui/object_info/sensor_pulse_info_overlay.gd` | **Neu** |
| `scripts/system/controller/system_ui_controller.gd` | Delegate (−27 Zeilen Logik) |
| `scripts/debug/smoke_tests/sensor_pulse_info_overlay_smoke_test.gd` | **Neu** |
| `scripts/debug/smoke_tests/sensor_pulse_info_overlay_smoke_runner.tscn` | **Neu** |

**Nicht geändert:** `object_info_panel.gd`, `base_sensor_pulse_controller.gd`, Scenes, `GameSession`, `SAVE_VERSION`, `tooltip_text`, Scan/Mine/Recall/Colonization-Overlays.

---

## Tests

| Smoke | Ergebnis |
|-------|----------|
| `sensor_pulse_info_overlay_smoke_runner.tscn` | **PASS** (A–D: keys, delegation equality, active pulse, non-home) |
| `sensor_pulse_progress_label_cleanup_smoke_runner.tscn` | **PASS WITH NOTES** |
| `sensor_pulse_ui_strings_cleanup_smoke_runner.tscn` | **PASS** |
| `object_info_signal_layout_smoke_runner.tscn` | **PASS** |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | **PASS WITH NOTES** |
| `object_info_mining_bonus_display_smoke_runner.tscn` | **PASS** |

`SAVE_VERSION = 1`, `tooltip_text = 0` — bestätigt.

---

## Risiken

| Risiko | Mitigation |
|--------|------------|
| Overlay/Controller drift | Smoke B full field equality |
| `is_home_base` param vs `info` dict | Controller übergibt `bool(info.get("is_home_base"))` wie zuvor |
| Active pulse Test C gate | NOTE wenn Pulse nicht startbar; kein FAIL |

---

## Akzeptanz

| Kriterium | Status |
|-----------|--------|
| `SensorPulseInfoOverlay` existiert | ✓ |
| Controller delegiert | ✓ |
| Output-Dict kompatibel | ✓ (Smoke B) |
| `SensorPulseProgressLabel` unverändert | ✓ (regression smoke) |
| `InvestigateProgressLabel` getrennt | ✓ |
| Keine Gameplay/Scene/Save-Änderung | ✓ |
| `SAVE_VERSION` = 1 | ✓ |
| `tooltip_text` = 0 | ✓ |

**Gesamt:** **PASS**

---

## Nächster Step (nicht in diesem PR)

Plan: `ScanDroneInfoOverlay` / `MiningShipInfoOverlay` — separat, nicht kombinieren.
