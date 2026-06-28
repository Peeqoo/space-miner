# ObjectInfo mining_bonus Display Drift Fix — Audit v0.1

**Date:** 2026-06-07  
**Scope:** UI contract fix — panel reads `info.mining_bonus` for display; no yield/gameplay changes.  
**Verdict:** **PASS**

---

## Kurzfassung

`ObjectInfoPanel._apply_automation_status()` leitet die Mining-Bonus-Anzeige (`MiningBonusLabel`) jetzt aus `info.mining_bonus` ab — dem vom `SystemUIController` / `AutomationController.get_mining_bonus_for_target()` gelieferten Bruchteil. Die Panel-seitige Neuberechnung `scan_drone_supporting_count * per_drone_pct` entfällt. Support-Drone-Counts und Orbit-Zeilen bleiben unverändert.

---

## Format-Vertrag `mining_bonus`

| Feld | Typ | Bedeutung | Anzeige |
|------|-----|-----------|---------|
| `mining_bonus` | `float` | Additiver Yield-Anteil (nicht Multiplikator) | `int(round(mining_bonus * 100))` → `"+{n}%"` |

**Beispiele (wie `AutomationController.get_mining_bonus_for_target`):**

- `0.02` → `+2%` (1 Support-Drone × 2 % / 100)
- `0.06` → `+6%`
- `0.0` → `+0%` (wenn Orbit-Zeile sichtbar)

Mining-Tick: `effective_rate = rate * (1 + mining_bonus)` — **unverändert**.

---

## Alte Quelle → Neue Quelle

| Aspekt | Vorher | Nachher |
|--------|--------|---------|
| Bonus-% Anzeige | `drone_supporting * GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent(base)` | `round(info.mining_bonus * 100)` |
| Key-Zugriff | String-Literal `"mining_bonus"` implizit ignoriert | `ObjectInfoDictKeys.MINING_BONUS` |
| `scan_drone_supporting_count` | Count + Bonus | Nur Count / Orbit-Text |
| `mining_yield_upgrade_base_id` | Panel las Upgrade für Bonus | Im Dict weiter gesetzt; Panel nutzt es für Bonus **nicht** mehr |

**Controller / Automation:** keine Änderung.

---

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/ui/system/object_info_panel.gd` | `_apply_automation_status` — Bonus aus `mining_bonus` |
| `scripts/debug/smoke_tests/object_info_mining_bonus_display_smoke_test.gd` | **Neu** |
| `scripts/debug/smoke_tests/object_info_mining_bonus_display_smoke_runner.tscn` | **Neu** |

**Nicht geändert:** `system_ui_controller.gd`, `automation_controller.gd`, Scenes, Upgrades, `SAVE_VERSION`, `tooltip_text`.

---

## Tests

| Smoke | Ergebnis |
|-------|----------|
| `object_info_mining_bonus_display_smoke_runner.tscn` | **PASS** (A: 999 support + 0.04 → +4%; B: 2%/6%/0%) |
| `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn` | **PASS** |
| `object_info_multi_ms_ui_smoke_runner.tscn` | **PASS** |
| `object_info_scan_drone_assign_ui_smoke_runner.tscn` | **PASS WITH NOTES** |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | **PASS WITH NOTES** |
| `object_info_signal_layout_smoke_runner.tscn` | **PASS** |

`SAVE_VERSION = 1`, `tooltip_text = 0` — bestätigt.

---

## Risiken

| Risiko | Mitigation |
|--------|------------|
| `mining_yield_upgrade_base_id` ≠ Session-Base für Bonus | Panel folgt jetzt Controller-Wert; einheitliche Quelle |
| Rundung `round(* 100)` vs. int truncation | Gleich wie bisherige Integer-%; Smoke B |
| Synthetischer Dict ohne `mining_bonus` | Default `0.0` → `+0%` |

---

## Akzeptanz

| Kriterium | Status |
|-----------|--------|
| Panel zeigt Bonus aus `info.mining_bonus` | ✓ |
| Normale Fälle gleich sichtbar | ✓ (Step 7 + Smoke B) |
| Support-Count-Anzeige unverändert | ✓ |
| Mining-Yield-Berechnung unverändert | ✓ |
| Step 7 stacking PASS | ✓ |
| Keine Scene/Gameplay/Save-Änderung | ✓ |
| `SAVE_VERSION` = 1 | ✓ |
| `tooltip_text` = 0 | ✓ |

**Gesamt:** **PASS**
