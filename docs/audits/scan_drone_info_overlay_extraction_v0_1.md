# ScanDroneInfoOverlay Extraction Audit v0.1

## Kurzfassung

Scan-Drone-Overlay-Felder aus `SystemUIController._apply_scan_drone_info_to_dict()` in `ScanDroneInfoOverlay` extrahiert. Der Controller delegiert nur noch; `_build_selected_object_info()` und `ObjectInfoPanel` unverändert. `active_scan_drone_count` und `scan_drone_supporting_count` bleiben im Controller (Home-Base-Zeroing / Orbiting-Count).

**Ergebnis: PASS**

## Alte Struktur → Neue Struktur

| Vorher | Nachher |
|--------|---------|
| `SystemUIController._apply_scan_drone_info_to_dict()` — ~55 Zeilen Inline-Logik | `ScanDroneInfoOverlay.apply()` — statische Overlay-Logik |
| String-Literal-Keys (`"show_scan_with_drone"`, …) | `ObjectInfoDictKeys` StringName-Keys |
| Direkte `GameSession` / `AutomationController`-Aufrufe im Controller | Gleiche Aufrufe im Overlay; Controller reicht Kontext durch |

## Verschobene Keys (nur Overlay)

| Key | ObjectInfoDictKeys |
|-----|-------------------|
| `show_scan_with_drone` | `SHOW_SCAN_WITH_DRONE` |
| `can_scan_with_drone` | `CAN_SCAN_WITH_DRONE` |
| `scan_blocked_reason` | `SCAN_BLOCKED_REASON` |
| `scan_button_text` | `SCAN_BUTTON_TEXT` |
| `assigned_scan_drone_count` | `ASSIGNED_SCAN_DRONE_COUNT` |
| `show_scan_drone_status` | `SHOW_SCAN_DRONE_STATUS` |
| `has_active_shared_scan_job` | `HAS_ACTIVE_SHARED_SCAN_JOB` |

**Nicht verschoben** (bleiben in `_build_selected_object_info`):

- `active_scan_drone_count`
- `scan_drone_supporting_count`

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/ui/object_info/scan_drone_info_overlay.gd` | **Neu** — `class_name ScanDroneInfoOverlay` |
| `scripts/system/controller/system_ui_controller.gd` | `_apply_scan_drone_info_to_dict()` delegiert an Overlay |
| `scripts/debug/smoke_tests/scan_drone_info_overlay_smoke_test.gd` | **Neu** — Tests A–D |
| `scripts/debug/smoke_tests/scan_drone_info_overlay_smoke_runner.tscn` | **Neu** — Runner |
| `docs/audits/scan_drone_info_overlay_extraction_v0_1.md` | **Neu** — dieses Audit |

**Unverändert:** `AutomationController`, `GameSession`, `ObjectInfoPanel`, Scenes, Save-Version, Tooltips, SharedScanJob-Logik.

## API

```gdscript
ScanDroneInfoOverlay.apply(
    info: Dictionary,
    selected_node: Node,
    object_id: String,
    system_id: String,
    base_id: String,
    automation_controller: AutomationController,
    has_available_drone: bool,
    scan_button_text: String,
    is_established_home_body: bool,
) -> void
```

Controller berechnet `is_established_home_body`, `system_id`, `has_available_drone` und `SCAN_BUTTON_TEXT` wie zuvor und übergibt sie.

## Tests

### Neuer Smoke (`scan_drone_info_overlay_smoke_runner.tscn`)

| Test | Prüfung |
|------|---------|
| A | Alle `OVERLAY_KEYS` gesetzt; null-Node → Defaults |
| B | Overlay ≡ Controller für KNOWN Mars, kein aktiver Job; Button-Text `"Scan"` |
| C | Nach Support-Test: neuer Drone gebaut, dann aktiver SharedScanJob — assign count, show/can flags, Button `"Scan"` |
| D | Vor Test C: Support-Drone am Mars; `scan_drone_supporting_count` via `_build_selected_object_info` ≡ `get_orbiting_drone_count` |

### Regression-Smokes

| Runner | Status |
|--------|--------|
| `object_info_scan_drone_assign_ui_smoke_runner.tscn` | PASS WITH NOTES |
| `shared_scan_job_step_6_ui_assign_scan_drone_smoke_runner.tscn` | PASS WITH NOTES |
| `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn` | PASS |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | PASS WITH NOTES |
| `object_info_signal_layout_smoke_runner.tscn` | PASS |
| `object_info_mining_bonus_display_smoke_runner.tscn` | PASS |

### Invarianten

- `SAVE_VERSION = 1`
- `tooltip_text = 0`

## Risiken

| Risiko | Bewertung |
|--------|-----------|
| Delegation-Parameter-Drift (Controller vs Overlay) | Niedrig — Smoke B/C vergleichen Byte-für-Byte auf OVERLAY_KEYS |
| `system_definition` null bei leerem `system_id` | Behoben: Overlay prüft `system_id.strip_edges()` wie zuvor; Controller übergibt `""` wenn null |
| Assign-Pfad bei aktivem Job | Niedrig — Smoke C + assign-UI-Regression |
| Support count außerhalb Overlay | Bewusst — Test D prüft Host-Pfad unverändert |

## Verdict

**PASS** — Extraction behavior-preserving; alle Pflicht-Smokes grün; keine Scope-Verletzungen.
