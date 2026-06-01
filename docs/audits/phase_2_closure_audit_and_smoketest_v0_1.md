# Phase 2 Closure Audit and SmokeTest v0.1

**Date:** 2026-05-20  
**Scope:** Phase 2 UI typing, text centralization cleanup, documentation — **no code/scene/data changes in this audit.**  
**Godot:** 4.6.1 (project assumption)

---

## Summary

| Item | Result |
|------|--------|
| **Overall status** | **PASS WITH NOTES** |
| **Phase 2 abschließen?** | **Ja**, nach manuellem Editor-SmokeTest (Godot CLI hier nicht verfügbar) |
| **Static audit** | Pass — panel typing complete; only intentional `selected_node` dynamism remains |
| **Runtime/parser** | **NOT VERIFIED** — Godot CLI not in PATH |
| **Manual smoke test** | **NOT TESTED** (requires human playthrough in Editor) |
| **Größte Risiken** | Ungetestete Runtime-Regressionen; ObjectInfoPanel signal/known layout bleibt code-gesteuert; prepared gate keys ungenutzt |
| **tooltip_text** | **0** Treffer in `*.gd` / `*.tscn` / `*.tres` |

---

## Git State

| Check | Status | Evidence |
|-------|--------|----------|
| Branch | **main** | `git branch --show-current` |
| Working tree | **Clean** | `git status`: nothing to commit, working tree clean |
| Ahead of origin | **25 commits** | Not a blocker for local Phase 2 closure |
| Recent commits | Typing + docs | `d51f536` Document SystemUIController selection polymorphism; `3e51b2b` Type TopHUDHoverPanel; `cce16a5` Type remaining system UI panel references; `ee55c10` Typed BaseManagementPanel refresh; `7f6dce4` Rename colony no-ship block template |

**Note:** Clean working tree — static audit assumptions are reliable for committed state.

---

## Static Audit Results

| Check | Status | Evidence | Notes |
|-------|--------|----------|-------|
| A) `class_name` on all 7 panel scripts | **PASS** | `ObjectInfoPanel`, `BaseManagementPanel`, `StoragePanel`, `ProductionPanel`, `UpgradePanel`, `TopHUD`, `TopHUDHoverPanel` in respective `scripts/ui/system/*.gd` | One definition each; no duplicate `class_name` symbols in repo |
| B) `system_ui_controller.gd` panel fields typed | **PASS** | Lines 10–20: all seven `var … : PanelType = null` | |
| B) `setup()` safe cast + warning | **PASS** | Lines 55–121: `as PanelType`, `push_warning` on mismatch, assign `null` | |
| B) No panel `has_method`/`call` | **PASS** | Grep: no `object_info_panel|base_management_panel|…|top_hud` + `has_method`/`call` | |
| C) Remaining `has_method`/`call` in controller | **PASS** | Only lines 485–488 in `_build_selected_object_info()` | `build_scan_info` / `get_info` on `selected_node` |
| C) No extra dynamic calls | **PASS** | Total 4 lines in `system_ui_controller.gd` | |
| D) `tooltip_text` repo-wide | **PASS** | 0 matches `*.gd`, `*.tscn`, `*.tres` | Also 0 for `hint_tooltip`, `set_tooltip`, `EnterTooltip`, `_enter_tooltips`, `_apply_enter_button_tooltip` |
| D) Enter tooltip remnants | **PASS** | Galaxy uses `AccessStatusLabel` / templates, not EnterTooltip API | |
| E) `ColonizationNoShipBlockTemplate` | **PASS** | Scene + `@onready` in `object_info_panel.gd`; 0× `ColonizationNoShipTooltipTemplate` in code/scenes | |
| E) Core `@onready` paths | **PASS** (sampled) | `SensorPulseProgressLabel`, `DividerB`, `ResourcePanel`, hover panel nodes referenced in scripts match `.tscn` names | Full scene parse not run in CI |
| F) `GateUiTextDefinition` + `.tres` | **PASS** (static) | `data/ui_text/gate_ui_texts.tres` exists; `GameSession.get_gate_text()`; `blocked_reason_key` pattern in `game_session.gd` / `base_store.gd` | |
| F) `KEY_COLONY_NO_SHIP` | **PASS** | `object_info_panel.gd` `_ready()` → `GameSession.get_gate_text(KEY_COLONY_NO_SHIP, template)` | |
| F) `colony_requirement_missing` | **PASS** | 0 matches in `*.gd` / `*.tscn` — only mentioned in audit docs | |
| F) Prepared keys | **NOTE** | `KEY_MINE_STORAGE_FULL`, `KEY_UPGRADE_MAX_LEVEL` in definition; audits mark as prepared/unwired | Intentional v0.1 |
| G) `DiscoverySignalUiTextDefinition` | **PASS** | `format_investigate_progress`, `format_sensor_pulse_progress`, `get_unknown_signal_lore`, `get_template` used | |
| G) Removed dead helpers | **PASS** | 0× `get_unknown_signal_type`, `get_sensor_pulse_button_label`, `GateUiTextDefinition.has_text` in code | Keys may remain in `.tres` |
| H) ObjectInfoPanel signal layout | **PASS** (static) | `_set_resource_section_visible(not is_signal)`, `_apply_signal_panel_layout`, `_apply_sensor_pulse_controls` on home base; doc `docs/ui/object_info_panel_signal_layout_v0_1.md` exists | |
| H) Scan button default | **PASS** | `object_info_panel.tscn` `ScanWithDroneButton` text = `"Scan"` | |
| I) Save doc | **PASS** (static) | `docs/save_behavior_v0_1.md` present; `GameSession.cancel_active_survey_probe_missions_before_save`, `cancel_active_base_sensor_pulse_before_save` exist | Aligns with doc claims |
| Docs: selection polymorphism | **PASS** | `docs/ui/system_ui_controller_selection_polymorphism_v0_1.md` | |
| Docs: signal layout | **PASS** | `docs/ui/object_info_panel_signal_layout_v0_1.md` | |
| Parser / headless start | **NOT TESTED** | `where godot` → not in PATH | Manual Editor run required |

---

## Panel Typing Results

| Panel | `class_name` | Typed in `SystemUIController` | Dynamic calls on panel | Status |
|-------|--------------|-------------------------------|-------------------------|--------|
| ObjectInfoPanel | Yes | `ObjectInfoPanel` | None | **PASS** |
| BaseManagementPanel | Yes | `BaseManagementPanel` | None | **PASS** |
| StoragePanel | Yes | `StoragePanel` | None | **PASS** |
| ProductionPanel | Yes | `ProductionPanel` | None | **PASS** |
| UpgradePanel | Yes | `UpgradePanel` | None | **PASS** |
| TopHUD | Yes | `TopHUD` | None | **PASS** |
| TopHUDHoverPanel | Yes | `TopHUDHoverPanel` | None | **PASS** |

**Minor note (not a failure):** `_connect_object_info_investigate_signal()` / `_connect_object_info_sensor_pulse_signal()` still use redundant `object_info_panel as ObjectInfoPanel` + mismatch warning after field is already typed — behavior unchanged.

---

## Remaining Dynamic Calls

| File | Function | Call | Intentional? | Documented? | Risk if removed blindly |
|------|----------|------|--------------|-------------|-------------------------|
| `system_ui_controller.gd` | `_build_selected_object_info` | `has_method("build_scan_info")` + `call(...)` | **Yes** | `docs/ui/system_ui_controller_selection_polymorphism_v0_1.md` | Broken scan/resource panel for Body/POI |
| `system_ui_controller.gd` | `_build_selected_object_info` | `has_method("get_info")` + `call("get_info")` | **Yes** (fallback) | Same doc | Empty/incomplete info dict |
| `system_selection_controller.gd` | `clear_selection` | `has_method("set_selected")` | **Yes** (out of Phase 2 scope) | Selection polymorphism doc (related) | Deselect on non-marker nodes |

**SignalMarker** does not use this block — routed via `_build_signal_marker_info()` + `is SignalMarker` guard.

---

## UI Text / Tooltip Results

| Item | Status | Evidence |
|------|--------|----------|
| `tooltip_text` count | **0** | Repo grep `*.gd`, `*.tscn`, `*.tres` |
| Gate UI texts | **OK** | `gate_ui_text_definition.gd` + `gate_ui_texts.tres`; runtime via `GameSession.get_gate_text` |
| Discovery signal texts | **OK** | `discovery_signal_ui_text_definition.gd` + `discovery_signal_ui_texts.tres` |
| Colony “No Colony Ship” | **OK** | `KEY_COLONY_NO_SHIP` + scene template `ColonizationNoShipBlockTemplate` |
| Colony build gates | **OK** (static) | Prerequisite keys via `get_colony_ship_build_prerequisite_blocked_reason_key`; no generic `colony_requirement_missing` in code |

---

## Parser / Runtime Start

| Check | Result |
|-------|--------|
| Godot CLI | **Not available** (not in PATH on audit machine) |
| Headless project load | **NOT RUN** |
| Recommendation | Open project in Godot 4.6.1 Editor once; confirm Output has no parser errors on load |

---

## Manual SmokeTest

All gameplay rows: **NOT TESTED** in this audit (no Godot runtime). Mark **PASS** only after you run them in Editor.

| ID | Test | Expected (short) | Result | Notes |
|----|------|------------------|--------|-------|
| 1 | New Game | Start, Earth, signals, no errors | **NOT TESTED** | |
| 2 | SignalMarker select | Compact panel, no resources, Investigate, distance | **NOT TESTED** | |
| 3 | Investigate start | Probe flies, progress label, HUD probes | **NOT TESTED** | |
| 4 | Reveal after Investigate | Marker gone, KNOWN object, resource section | **NOT TESTED** | |
| 5 | Scan | "Scan" label, basic/rescan, SurveyData once | **NOT TESTED** | |
| 6 | Mining | Gates, cargo, storage, depleted | **NOT TESTED** | |
| 7 | StoragePanel | Open from base, list, capacity, base id | **NOT TESTED** | |
| 8 | ProductionPanel | Builds + colony gates + hover | **NOT TESTED** | |
| 9 | UpgradePanel | Three upgrades + hover | **NOT TESTED** | |
| 10 | TopHUD | All counters update | **NOT TESTED** | |
| 11 | TopHUDHoverPanel | Hover details, clear on exit/subpanel | **NOT TESTED** | |
| 12 | Base Sensor Pulse | Cost, progress label, HIDDEN→SIGNAL, save refund | **NOT TESTED** | |
| 13 | Colony / Colonization | Gate texts, no-ship block, start, galaxy status | **NOT TESTED** | |
| 14 | Galaxy Enter | Button + AccessStatusLabel, no EnterTooltip | **NOT TESTED** | |
| 15 | Save during SurveyProbe | Cancel + refund, stays SIGNAL | **NOT TESTED** | |
| 16 | Save during SensorPulse | Cancel + refund | **NOT TESTED** | |
| 17 | Save during Scan/Mine | Automation restore, no dupes | **NOT TESTED** | |
| 18 | Empty selection | Panel empty/hidden, no errors | **NOT TESTED** | |
| 19 | tooltip_text final | grep → 0 | **PASS** (static grep) | Gameplay N/A |

---

## Open Issues

*None blocking Phase 2 closure from static evidence.*

| ID | Severity | Issue | Action |
|----|----------|-------|--------|
| O1 | **Medium** (process) | Manual smoke matrix not executed in this audit | Run checklist in Editor before release/tag |
| O2 | **Low** | Godot CLI not used for parser check | Optional: add Godot to PATH for CI/headless `--quit-after 1` |
| O3 | **Info** | Branch 25 commits ahead of `origin/main` | Push when ready; unrelated to Phase 2 quality |

---

## Not Problems / Intentional

- **`selected_node` `has_method`/`call`** in `_build_selected_object_info()` — documented adapter for `SystemBody` / `PointOfInterest` scan info.
- **Custom hover UI** — `TopHUDHoverPanel.show_details` / `clear`; not Godot `tooltip_text`.
- **Prepared gate keys** — e.g. `mine_storage_full`, `upgrade_max_level` in resources; limited/no runtime gate path (Phase 1 audits).
- **German strings** — e.g. TopHUD warning, lore in `data/` — out of Phase 2 English UI scope.
- **ObjectInfoPanel runtime layout** — signal shrink documented; not a Phase 2 defect.
- **Redundant `as ObjectInfoPanel` in signal connect helpers** — harmless; optional micro-cleanup later.
- **`SystemSelectionController.clear_selection` `has_method("set_selected")`** — separate from panel typing.

---

## Recommended Next Step

**Phase 2 formal abschließen:** Run the **Manual SmokeTest** table once in Godot 4.6.1 Editor (≈30–45 min). If all critical paths pass, tag or merge without further typing work.

**If smoke fails:** Use a **small, targeted fix prompt** for the failing row only (do not reopen bulk `has_method` removal or layout refactors).

**Do not start yet (out of scope):** `game_session.gd` split, automation split, Save v2, build queue, WorldObject interface, ObjectInfoPanel subscene layout refactor.

---

## Audit Commands Reference (reproducible)

```text
git status
git branch --show-current
git log --oneline -5
# has_method in system_ui_controller.gd → 4 lines, _build_selected_object_info only
# tooltip_text in *.gd *.tscn *.tres → 0
# ColonizationNoShipTooltipTemplate in *.gd *.tscn → 0
```

**Auditor:** Automated static pass + documentation review; gameplay **NOT TESTED**.
