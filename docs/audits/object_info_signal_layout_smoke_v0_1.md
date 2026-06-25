# ObjectInfo Signal Layout Smoke Audit v0.1

**Date:** 2026-06-07  
**Scope:** Dedicated smoke for SIGNAL vs KNOWN `ObjectInfoPanel` layout — test + audit only.  
**Godot:** 4.6.1 (strict typing)  
**Design reference:** [`docs/design/object_info_signal_layout_refactor_plan_v0_1.md`](../design/object_info_signal_layout_refactor_plan_v0_1.md)

---

## Audit summary

`ObjectInfoPanel` uses `_apply_signal_panel_layout()`, `_fit_signal_lore_text_height()`, `_restore_known_lore_layout()`, and `_queue_panel_layout_refresh()` to compact the panel for **SIGNAL** (`is_discovery_signal == true`) while the `.tscn` is sized for **KNOWN** objects.

A new headless smoke drives the panel via **synthetic info dicts** (`show_body_info`) without changing discovery/gameplay code. This satisfies the design-spike gate: **signal-layout smoke exists before any `SignalInfoSubPanel` refactor**.

**No production code or scene layout was modified.**

---

## Assertions secured

| ID | Requirement | Smoke coverage |
|----|-------------|----------------|
| S1 | SIGNAL: resource section hidden (`DividerB`, `ResourceTitleLabel`, `ResourcePanel`) | **Test A** |
| S2 | SIGNAL: `ScanWithDroneButton`, `SendMiningShipButton` hidden | **Test A** |
| S3 | SIGNAL: `InvestigateButton` visible when gate allows | **Test A** |
| S4 | SIGNAL investigate: `InvestigateProgressLabel` visible; `SensorPulseProgressLabel` hidden | **Test B** |
| S5 | Investigate vs pulse label separation (wording) | **Test B** |
| S6 | KNOWN: resource + scan/mine sections restored | **Test C** |
| S7 | SIGNAL → KNOWN: `is_discovery_signal` false; investigate UI hidden | **Test C** |
| S8 | KNOWN: `LoreScroll` not stuck in `SCROLL_MODE_DISABLED` | **Test C** |
| S9 | SIGNAL height &lt; KNOWN height (tolerant delta ≥ 12px) | **Test D** |
| S10 | `SAVE_VERSION == 1`, `tooltip_text == 0` | **Test E** |

### Runtime layout functions exercised (read-only)

| Function | Exercised by |
|----------|----------------|
| `_apply_signal_panel_layout` | Tests A, B (signal), C (known restore) |
| `_fit_signal_lore_text_height` | Test A/B signal path |
| `_restore_known_lore_layout` | Test C |
| `_queue_panel_layout_refresh` | Implicit via `show_body_info` / layout updates |

### Node paths verified

`Margin/Root/DividerB`, `ResourceTitleLabel`, `ResourcePanel`, `DividerD`, `OrbitStatusSection`, `GridContainer/ScanWithDroneButton`, `SendMiningShipButton`, `InvestigateButton`, `InvestigateProgressLabel`, `SensorPulseProgressLabel`.

---

## Open layout risks (not in this smoke)

| Risk | Status |
|------|--------|
| Full **system_scene** anchor (`offset_bottom ≈ 380`) + live `SignalMarker` selection | Not covered — isolated panel only |
| **Signal → KNOWN** transition via investigate reveal + marker despawn | Not covered — synthetic dict switch only |
| **Saturn / wide preview texture** lore wrap | Documented optional; no screenshot/size assertion |
| **Home base** Sensor Pulse during signal selection | N/A (signal is not home base) |
| `sensor_pulse_progress_label_cleanup` overlap | Complementary — still recommended in regression suite |

---

## Tests

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/object_info_signal_layout_smoke_runner.tscn
```

### Results (2026-06-07)

| Test | Description | Status |
|------|-------------|--------|
| **A** | SIGNAL compact controls | **PASS** |
| **B** | SIGNAL investigate progress | **PASS** |
| **C** | KNOWN restore after SIGNAL | **PASS** |
| **D** | Panel height sanity (158 vs 311 px, Δ 153) | **PASS** |
| **E** | SAVE_VERSION / tooltip regression | **PASS** |

**Overall:** **PASS**

Sample metrics: signal `combined_minimum_size.y` ≈ 158; known ≈ 311; lore panel min height restored to 80 on KNOWN.

---

## Changed files

| File | Change |
|------|--------|
| `scripts/debug/smoke_tests/object_info_signal_layout_smoke_test.gd` | **New** |
| `scripts/debug/smoke_tests/object_info_signal_layout_smoke_runner.tscn` | **New** |
| `docs/audits/object_info_signal_layout_smoke_v0_1.md` | **New** |

**Unchanged:** `object_info_panel.gd`, `object_info_panel.tscn`, `system_ui_controller.gd`, `GameSession`, `SAVE_VERSION = 1`, `tooltip_text = 0`.

---

## Verdict

**PASS**

- Dedicated signal-layout smoke exists.
- SIGNAL compact layout, investigate progress separation, and SIGNAL → KNOWN restore are automated.
- Height sanity uses tolerant bounds (no pixel-perfect coupling).
- Ready for optional `SignalInfoSubPanel` implementation per design plan C1.

---

## Recommended regression bundle (before layout refactor)

1. `object_info_signal_layout_smoke_runner.tscn`
2. `sensor_pulse_progress_label_cleanup_smoke_runner.tscn`
3. `object_info_simple_action_button_labels_smoke_runner.tscn`
