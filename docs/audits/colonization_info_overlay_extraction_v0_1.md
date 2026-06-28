# ColonizationInfoOverlay Extraction Audit v0.1

## Kurzfassung

Colonization-Overlay-Felder aus `SystemUIController._apply_colonization_info_to_dict()` in `ColonizationInfoOverlay` extrahiert. Der Controller delegiert nur noch; `_build_selected_object_info()` und `ObjectInfoPanel` unverändert. v0.1 setzt alle Colonization-Action-Flags weiterhin auf `false` (Galaxy-Map-Flow).

**Keine Smoke-Tests in diesem Schritt** — Verifikation deferred.

**Ergebnis: PASS WITH NOTES** (statische Prüfung; Smokes deferred)

## Alte Struktur → Neue Struktur

| Vorher | Nachher |
|--------|---------|
| `SystemUIController._apply_colonization_info_to_dict()` — ~10 Zeilen Inline-Logik | `ColonizationInfoOverlay.apply()` — statische Overlay-Logik |
| String-Literal-Keys | `ObjectInfoDictKeys` StringName-Keys |
| `system_id` / `object_id` im selben Methodenblock | Weiterhin im Overlay gesetzt; IDs vom Controller übergeben |

## Verschobene Keys (Overlay)

| Key | ObjectInfoDictKeys |
|-----|-------------------|
| `colonization_button_visible` | `COLONIZATION_BUTTON_VISIBLE` |
| `colonization_pending` | `COLONIZATION_PENDING` |
| `colonization_can_start` | `COLONIZATION_CAN_START` |

## Mitverschobene Identity-Keys (Teil der Methode)

| Key | ObjectInfoDictKeys | Hinweis |
|-----|-------------------|---------|
| `system_id` | `SYSTEM_ID` | War schon in `_apply_colonization_info_to_dict` gesetzt |
| `object_id` | `OBJECT_ID` | War schon in `_apply_colonization_info_to_dict` gesetzt; Panel nutzt primär `id` aus World-Info |

## Bewusst im Controller gelassene Felder

| Feld / Logik | Grund |
|--------------|-------|
| `_current_system_definition_id()` | Controller-Hilfe; Ergebnis wird an Overlay übergeben |
| `_get_object_id(selected_node)` | Node-Typ-Auflösung bleibt im Controller |
| `is_home_base` | Nicht Teil der Colonization-Methode |
| Home-Base-Zeroing | Nicht betroffen — Colonization-Flags werden nicht nachträglich gezeroed |
| System-Economy-Gate-Zeroing | Betrifft Scan/Mining/Recall, nicht Colonization-Keys |
| ColonyShip-/Colonization-Gameplay | `GameSession`, `BaseStore`, Save unverändert |

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/ui/object_info/colonization_info_overlay.gd` | **Neu** — `class_name ColonizationInfoOverlay` |
| `scripts/system/controller/system_ui_controller.gd` | `_apply_colonization_info_to_dict()` delegiert an Overlay |
| `docs/audits/colonization_info_overlay_extraction_v0_1.md` | **Neu** — dieses Audit |

**Unverändert:** `GameSession`, `BaseStore`, `ObjectInfoPanel`, Scenes, Save-Version, Tooltips, ScanDrone-/MiningShip-/SensorPulse-Overlays, alle Smoke-Dateien.

## API

```gdscript
ColonizationInfoOverlay.apply(
    info: Dictionary,
    system_id: String,
    object_id: String,
) -> void
```

## Smoke-Tests

**Nicht erstellt, nicht ausgeführt, nicht geändert in diesem Schritt.**

### Smoke deferred to overlay regression batch

Späterer Batch muss enthalten:

- `object_info_simple_action_button_labels_smoke_runner.tscn`
- `object_info_signal_layout_smoke_runner.tscn`
- `object_info_multi_ms_ui_smoke_runner.tscn`
- `object_info_scan_drone_assign_ui_smoke_runner.tscn`
- `object_info_mining_bonus_display_smoke_runner.tscn`
- `sensor_pulse_progress_label_cleanup_smoke_runner.tscn`
- `shared_scan_job_step_6_ui_assign_scan_drone_smoke_runner.tscn`
- `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn`
- `save_behavior_v0_1_smoke_runner.tscn`
- `SAVE_VERSION = 1`
- `tooltip_text = 0`

### Bestehende Colonization-Smoke-Kandidaten (nicht ausgeführt)

Kein dedizierter `colonization_info_overlay_smoke_runner`. Verwandte spätere Kandidaten:

- `galaxy_transition_process_continuity_smoke_runner.tscn` (Colonization-Survival nach Galaxy-Roundtrip)
- Phase-2-Audits mit Colony-/ColonizationNoShipBlock-Checks

Optional empfohlen für nächsten Schritt: dedizierter `colonization_info_overlay_smoke_runner.tscn` (Overlay ≡ Controller, `system_id`/`object_id`-Shape).

## Risiken

| Risiko | Bewertung |
|--------|-----------|
| Delegation-Parameter-Drift | Niedrig — 1:1-Port; nur `system_id` + `object_id` |
| `system_id` / `object_id` vs World-`id` | Niedrig — unveränderte Reihenfolge in `_build_selected_object_info` |
| v0.1 alle Flags `false` | Kein Risiko — Verhalten identisch; Galaxy-Map-Kommentar beibehalten |
| Keine Runtime-Smokes | Mittel — deferred auf Regression-Batch |

## Verdict

**PASS WITH NOTES** — Extraction behavior-preserving nach statischer Prüfung; keine Scope-Verletzungen; Smoke deferred.
