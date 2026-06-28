# MiningShipInfoOverlay Extraction Audit v0.1

## Kurzfassung

Mining-Ship-Overlay-Felder aus `SystemUIController._apply_mining_ship_info_to_dict()` in `MiningShipInfoOverlay` extrahiert. Der Controller delegiert nur noch; `_build_selected_object_info()` und `ObjectInfoPanel` unverändert. Count-Felder und Home-Base-Zeroing bleiben im Controller.

**Keine Smoke-Tests in diesem Schritt** — Verifikation deferred.

**Ergebnis: PASS WITH NOTES** (statische Prüfung; Smokes deferred)

## Alte Struktur → Neue Struktur

| Vorher | Nachher |
|--------|---------|
| `SystemUIController._apply_mining_ship_info_to_dict()` — ~50 Zeilen Inline-Logik | `MiningShipInfoOverlay.apply()` — statische Overlay-Logik |
| String-Literal-Keys (`"show_mine_with_ship"`, …) | `ObjectInfoDictKeys` StringName-Keys |
| `GameSession.can_mine_object()` + `AutomationController`-Count im Controller | Gleiche Aufrufe im Overlay; Controller reicht Kontext durch |

## Verschobene Keys (Overlay)

| Key | ObjectInfoDictKeys |
|-----|-------------------|
| `show_mine_with_ship` | `SHOW_MINE_WITH_SHIP` |
| `can_mine_with_ship` | `CAN_MINE_WITH_SHIP` |
| `mine_blocked_reason` | `MINE_BLOCKED_REASON` |
| `mining_button_text` | `MINING_BUTTON_TEXT` |
| `mining_exhausted` | `MINING_EXHAUSTED` |
| `assigned_mining_ship_count` | `ASSIGNED_MINING_SHIP_COUNT` |
| `show_mining_ship_status` | `SHOW_MINING_SHIP_STATUS` |

## Bewusst im Controller gelassene Felder

| Key / Logik | Grund |
|-------------|-------|
| `active_mining_ship_count` | Gesetzt in `_build_selected_object_info()` (non-home); nicht Teil von `_apply_mining_ship_info_to_dict` |
| `mining_ship_mining_count` | Gesetzt in `_build_selected_object_info()` via `_get_mining_ship_mining_status_count()` |
| `mining_bonus` | Gesetzt in `_build_selected_object_info()` via `_get_mining_bonus_for_object()` |
| `mining_yield_upgrade_base_id` | Gesetzt vor Overlay-Aufruf in `_build_selected_object_info()` |
| `can_recall_mining_ship` | Recall-Logik in `_build_selected_object_info()` |
| Home-Base-Zeroing | Block nach Overlay: `assigned_mining_ship_count`, `show_mining_ship_status`, `mining_button_text`, `active_mining_ship_count`, … → 0 / false / `""` |
| System-Economy-Gate-Zeroing | Block am Ende von `_build_selected_object_info()` |
| `scan_state` Parameter | Signatur von `_apply_mining_ship_info_to_dict` unverändert; war bereits ungenutzt |

**Hinweis:** `_build_selected_object_info()` überschreibt für non-home `assigned_mining_ship_count`, `show_mining_ship_status` und `mining_button_text` nach dem Overlay-Aufruf — identisch zum Vorher-Zustand.

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/ui/object_info/mining_ship_info_overlay.gd` | **Neu** — `class_name MiningShipInfoOverlay` |
| `scripts/system/controller/system_ui_controller.gd` | `_apply_mining_ship_info_to_dict()` delegiert an Overlay |
| `docs/audits/mining_ship_info_overlay_extraction_v0_1.md` | **Neu** — dieses Audit |

**Unverändert:** `AutomationController`, `GameSession`, `ObjectInfoPanel`, Scenes, Save-Version, Tooltips, ScanDrone-/SensorPulse-/Colonization-Overlays, alle Smoke-Dateien.

## API

```gdscript
MiningShipInfoOverlay.apply(
    info: Dictionary,
    selected_node: Node,
    object_id: String,
    system_id: String,
    base_id: String,
    automation_controller: AutomationController,
    has_available_mining_ship: bool,
    mining_button_text: String,
    is_established_home_body: bool,
) -> void
```

Controller berechnet `is_established_home_body`, `system_id`, `has_available_mining_ship` und `MINING_BUTTON_TEXT` (`"Mine"`) wie zuvor.

## Smoke-Tests

**Nicht erstellt, nicht ausgeführt, nicht geändert in diesem Schritt.**

### Smoke deferred to overlay regression batch

Späterer Batch muss enthalten:

- `object_info_multi_ms_ui_smoke_runner.tscn`
- `object_info_simple_action_button_labels_smoke_runner.tscn`
- `object_info_mining_bonus_display_smoke_runner.tscn`
- `object_info_signal_layout_smoke_runner.tscn`
- `object_info_scan_drone_assign_ui_smoke_runner.tscn`
- `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn`
- `SAVE_VERSION = 1`
- `tooltip_text = 0`

Optional empfohlen für nächsten Schritt: dedizierter `mining_ship_info_overlay_smoke_runner.tscn` (Overlay ≡ Controller, depleted gate, home-base early return).

## Risiken

| Risiko | Bewertung |
|--------|-----------|
| Delegation-Parameter-Drift | Niedrig — 1:1-Port der bestehenden Methode |
| `mining_exhausted` / `KEY_MINE_DEPLETED` | Niedrig — unveränderte Gate-Key-Prüfung |
| Doppeltes Setzen von `assigned_mining_ship_count` / `show_mining_ship_status` | Bekannt — `_build_selected_object_info` überschreibt wie vorher |
| Home-Base-Zeroing-Reihenfolge | Niedrig — unverändert nach Overlay |
| Keine Runtime-Smokes in diesem Schritt | Mittel — deferred auf Regression-Batch |

## Verdict

**PASS WITH NOTES** — Extraction behavior-preserving nach statischer Prüfung; keine Scope-Verletzungen; Smoke deferred.
