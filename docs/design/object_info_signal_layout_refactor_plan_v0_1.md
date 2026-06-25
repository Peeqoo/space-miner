# ObjectInfo Signal Layout Refactor Plan v0.1

**Date:** 2026-06-07  
**Type:** Design spike (analysis + recommendation only)  
**Godot:** 4.6.1 (strict typing)  
**Status:** No code or scene changes in this pass

**Related (existing behavior doc):** [`docs/ui/object_info_panel_signal_layout_v0_1.md`](../ui/object_info_panel_signal_layout_v0_1.md)  
**Audit trigger:** [`docs/audits/full_project_cleanup_audit_v0_2.md`](../audits/full_project_cleanup_audit_v0_2.md) — A1 *ObjectInfo signal runtime layout* **PENDING**

---

## Executive summary

`ObjectInfoPanel` is a **single scene** sized for **KNOWN** objects (resources, orbit block, scan/mine grid, tall lore scroll). **SIGNAL** selection (`SignalMarker`, `is_discovery_signal == true`) reuses the same tree and compensates with **runtime layout surgery**: `custom_minimum_size`, `offset_bottom`, `reset_size()`, and lore height fitting.

This works but is **maintenance-heavy**: every new root child or editor minimum size can reintroduce empty gaps on compact signal view, and signal ↔ known transitions must restore captured editor sizes.

**Recommendation:** **Option A now** (contract documentation — partially done); **Option C later** when implementing layout refactor (phased `SignalInfoSubPanel`). **Do not** start with Option B unless a specific redundant manipulation is proven safe by smoke.

**Verdict:** **PASS WITH NOTES** — spike complete; implementation deferred; product decision not required for Option A.

---

## Ist-Zustand

### Selection modes (panel perspective)

| Mode | Trigger | `is_discovery_signal` | Typical `scan_state` | Entry API |
|------|---------|----------------------|----------------------|-----------|
| **Empty** | No selection | `false` | — | `show_empty()`; panel hidden by `SystemUIController` |
| **SIGNAL** | `SignalMarker` selected | `true` | `SCAN_UNKNOWN` | `show_body_info()` ← `build_signal_info()` |
| **KNOWN body/POI** | `SystemBody` / `PointOfInterest` | `false` | `unknown` … `special` | `show_body_info()` / `show_poi_info()` |
| **Home base** | Established base body | `false` | varies | KNOWN + `is_home_base` → Sensor Pulse |

**Terminology note:** `SCAN_UNKNOWN` on a **revealed** body is not the same as **SIGNAL**. A known-discovered Mars can show `Scan Status: Unknown` and still display **Scan** / **Mine** — that is KNOWN layout. **SIGNAL** means `DISCOVERY_SIGNAL` world state + `SignalMarker` placeholder.

### Node visibility matrix

#### SIGNAL (`is_discovery_signal == true`)

| Node / section | Visible? | Mechanism |
|----------------|----------|-----------|
| Header, Close, DividerA | Yes | Always |
| MainRow (preview, name, type, scan status, distance) | Yes | `_apply_info()` |
| DividerB, ResourceTitleLabel, ResourcePanel | **No** | `_set_resource_section_visible(false)` |
| DividerC, LoreTitleLabel, LorePanel, LoreTextLabel | Yes | Signal lore (unknown / investigate-active text) |
| DividerD, OrbitStatusSection | **No** | `_apply_signal_panel_layout(true)` |
| EconomyBlockLabel | Conditional | Investigate block / complete message |
| InvestigateButton | Yes (hidden during progress) | `_apply_signal_discovery_controls()` |
| InvestigateProgressLabel | During investigate | `_show_investigate_progress_ui()` |
| SensorPulseButton / SensorPulseProgressLabel | **No** | Not home base; pulse is base-only |
| Scan / Mine / Recall / Colonization buttons | **No** | `_set_action_buttons(false, …)` in signal branch |

#### KNOWN (`is_discovery_signal == false`)

| Node / section | Visible? | Mechanism |
|----------------|----------|-----------|
| Resource section | Yes (if data) | `_set_resource_section_visible(true)` |
| LorePanel | Yes | Body/POI `description`; scroll + editor min heights |
| OrbitStatusSection | Yes | `_apply_automation_status()`; lines toggled by counts |
| Scan / Mine / Recall | Per gate dict | `_apply_live_action_controls()` |
| Colonization | Per dict flags | `_apply_colonization_controls()` |
| Sensor Pulse | Home base only | `_apply_sensor_pulse_controls()` |
| Investigate | **No** | Hidden when not signal |

### Scene anchor (KNOWN-oriented)

`scenes/system/system_scene.tscn` — `ObjectInfoPanel`:

- `offset_left = -186`, `offset_top = 30`, `offset_bottom = 380` (fixed ~350px tall box)
- Panel `custom_minimum_size = Vector2(200, 0)` in `.tscn`

SIGNAL mode **shrinks** content via `_queue_panel_layout_refresh(true)` setting `offset_bottom = offset_top + content_height`. KNOWN mode restores `_known_offset_bottom` from `_ready()` capture.

### Runtime layout manipulation inventory

| Function / site | What it mutates | Mode | Necessary? |
|-----------------|-----------------|------|------------|
| `_capture_known_layout_sizes()` | Snapshots panel, lore, resource min sizes, `offset_bottom` | `_ready()` | **Yes** — restore baseline for KNOWN |
| `_apply_signal_panel_layout(true)` | Panel `custom_minimum_size.y = 0`; resource panel min zero; hide DividerD + OrbitStatusSection; calls `_fit_signal_lore_text_height()` | SIGNAL | **Yes** — without zeroing, VBox keeps 50px+80px gaps |
| `_fit_signal_lore_text_height()` | Lore label/scroll/panel `custom_minimum_size`; disables lore scroll | SIGNAL | **Yes** — avoids fixed 80px lore box + clipping |
| `_restore_known_lore_layout()` | Restores lore scroll mode + editor min sizes | KNOWN | **Yes** — signal branch must not leak |
| `_queue_panel_layout_refresh(is_signal)` | `root_vbox.queue_sort()`, `reset_size()`, `update_minimum_size()`; SIGNAL sets `offset_bottom` from measured height | Both | **Yes for SIGNAL**; pulse progress on KNOWN also calls with `false` |
| `_apply_signal_discovery_controls()` | Resource visibility + layout + redundant orbit label hides | SIGNAL | Visibility **yes**; duplicate orbit hides **optional** |
| `_show_sensor_pulse_progress_ui()` | `_queue_panel_layout_refresh(false)` | KNOWN (base) | **Yes** — pulse label changes panel height |

**Root cause:** Godot `VBoxContainer` still accounts for children’s `custom_minimum_size` even when `visible = false`. The monolithic scene bakes KNOWN minimums into the same tree SIGNAL uses.

### Upstream data flow (unchanged by layout)

```
SystemSelectionController → SystemUIController.update_object_info()
  ├─ SignalMarker → _build_signal_marker_info() → is_discovery_signal, investigate fields
  └─ SystemBody/POI → _build_selected_object_info() → scan/mine/resources/lore
ObjectInfoPanel._apply_info() → _apply_signal_discovery_controls() → _apply_live_action_controls()
```

Gates stay in `GameSession`, `SurveyProbeMissionController`, `BaseSensorPulseController` — panel is presentation only.

### Existing tests (ObjectInfo-related)

| Smoke | Covers signal layout? | Notes |
|-------|----------------------|-------|
| `object_info_simple_action_button_labels_smoke_test` | Partial (KNOWN Mars) | Scan/Mine labels, multi-assign |
| `object_info_scan_drone_assign_ui_smoke_test` | KNOWN only | Assign count label |
| `object_info_multi_ms_ui_smoke_test` | KNOWN only | Multi mining ship |
| `object_info_recall_button_language_pass_smoke_test` | KNOWN only | Recall EN |
| `sensor_pulse_progress_label_cleanup_smoke_test` | **Yes** | Signal investigate vs base pulse labels |
| `sensor_pulse_ui_strings_cleanup_smoke_test` | Base pulse | Progress text source |
| `shared_scan_job_step_6/7_*` | KNOWN scan assign | Uses ObjectInfo labels |

**Gap:** No automated smoke for **SIGNAL compact height** (no resource/orbit chrome), **signal ↔ known transition** layout restore, or **wide preview texture** (Saturn rings) vs lore wrap.

---

## Problemstellen

1. **Dual-purpose scene** — KNOWN editor mins fight SIGNAL compact layout.
2. **`offset_bottom` runtime** — couples panel to `system_scene` anchor; fragile if parent layout changes.
3. **`_fit_signal_lore_text_height()`** — manual wrap-width math (`_get_lore_text_wrap_width()`); theme/resize can clip long lore.
4. **Order sensitivity** — `_apply_automation_status()` may show orbit labels before signal path hides them again.
5. **Deep `@onready` paths** — 30+ node refs under `Margin/Root`; renames break silently.
6. **No dedicated signal-layout smoke** — regressions possible when adding root children (e.g. new progress row).

### Risks if layout code removed without replacement

| Removed behavior | Likely regression |
|------------------|-------------------|
| Resource panel `custom_minimum_size = ZERO` on signal | Empty ~50px gap above lore |
| `_fit_signal_lore_text_height()` | Fixed 80px lore or clipped text |
| `offset_bottom` shrink on signal | Tall empty panel (380px anchor) |
| `_restore_known_lore_layout()` after signal | Stuck short lore / disabled scroll on KNOWN |
| `_queue_panel_layout_refresh` after pulse | Pulse label overlaps buttons |

---

## Design options

### Option A — Status quo + contract documentation

**Description:** Keep runtime layout code. Strengthen documentation and in-code contract comments only (no structural refactor).

| | |
|--|--|
| **Advantages** | Zero regression risk; audit item closable as “documented”; builds on existing `docs/ui/object_info_panel_signal_layout_v0_1.md` |
| **Disadvantages** | Maintenance cost remains; new features still touch layout helpers |
| **Files changed** | `docs/ui/object_info_panel_signal_layout_v0_1.md` (optional sync), `object_info_panel.gd` header comment block only |
| **Smokes required** | Existing ObjectInfo smokes + manual checklist in ui doc |
| **Risk** | **Low** |
| **Recommendation** | **Do now** — satisfies v0.2 “documented contract” path without implementation |

---

### Option B — Small layout cleanup (same scene)

**Description:** Remove provably redundant manipulations; keep monolithic scene. Examples: drop duplicate orbit label hides in `_apply_signal_discovery_controls()` (section already hidden); avoid double `_apply_signal_discovery_controls()` call from signal branch of `_apply_live_action_controls()` if order can be simplified.

| | |
|--|--|
| **Advantages** | Slightly smaller `.gd`; less duplicate visibility |
| **Disadvantages** | Easy to break signal/known transition; limited benefit without scene split; still need `offset_bottom` + lore fit |
| **Files changed** | `object_info_panel.gd` only (surgical) |
| **Smokes required** | All ObjectInfo smokes + **new** `object_info_signal_layout_smoke_test` (visibility + height bounds) |
| **Risk** | **Medium** |
| **Recommendation** | **Defer** — only after dedicated signal-layout smoke exists; not first refactor step |

---

### Option C — `SignalInfoSubPanel` subscene

**Description:** Extract SIGNAL stack into `scenes/ui/system/signal_info_sub_panel.tscn` (+ thin `signal_info_sub_panel.gd`). Host `ObjectInfoPanel` toggles:

- `signal_section.visible = is_discovery_signal`
- `known_section.visible = not is_discovery_signal`

KNOWN section keeps current resource/orbit/grid tree (optionally second subscene later: `KnownObjectInfoSection`).

| | |
|--|--|
| **Advantages** | Editor-owned compact layout; removes most `custom_minimum_size` / `offset_bottom` surgery for signals; clearer ownership |
| **Disadvantages** | Higher initial cost; must wire investigate/progress/economy block; signal ↔ known transition testing; two scenes to keep in sync for shared chrome (header, MainRow) |
| **Files changed** | New `signal_info_sub_panel.tscn/.gd`; `object_info_panel.tscn/.gd` (host toggle + delegate); possibly `system_ui_controller.gd` only if API changes (prefer no API change) |
| **Smokes required** | Full matrix below + signal ↔ known transition test |
| **Risk** | **Medium–High** (visual/layout); **Low** for gameplay if gates untouched |
| **Recommendation** | **Preferred implementation path** when A1 is scheduled — phased: **C1** signal subscene only, keep KNOWN monolith; **C2** optional known subscene |

---

## Comparison

| Criterion | A — Document | B — Cleanup | C — Subscene |
|-----------|--------------|-------------|--------------|
| Regression risk | Low | Medium | Medium–High (one-time) |
| Maintenance | Unchanged | Slightly better | Much better |
| Effort | Hours | 0.5–1 day | 2–4 days |
| Closes A1 audit | With notes | Partially | Fully |
| Gameplay impact | None | None if careful | None if presentation-only |

---

## Empfehlung

1. **Immediate (this sprint):** **Option A** — treat [`docs/ui/object_info_panel_signal_layout_v0_1.md`](../ui/object_info_panel_signal_layout_v0_1.md) + this plan as the contract; mark v0.2 A1 as *documented, implementation deferred*.
2. **Before any Option B/C code:** Add **`object_info_signal_layout_smoke_test`** (see matrix).
3. **Implementation sprint:** **Option C1** (`SignalInfoSubPanel`) — do **not** big-bang split KNOWN section in same PR.
4. **Do not** remove `_fit_signal_lore_text_height()` or `offset_bottom` logic until SIGNAL content lives in a separately sized container or host uses `SIZE_SHRINK_END` layout without fixed parent `offset_bottom`.

---

## Nicht anfassen (any option)

- `GameSession` discovery states (`DISCOVERY_HIDDEN`, `DISCOVERY_SIGNAL`, KNOWN)
- `SurveyProbeMissionController` investigate flow
- `SystemDiscoveryController.refresh_object()` / marker lifecycle
- Scan/mine gates (`can_scan_object`, `can_mine_object`, gate text keys)
- `SensorPulseProgressLabel` / `InvestigateProgressLabel` separation (recently fixed)
- `tooltip_text` (project policy: 0)
- `SAVE_VERSION` (remain 1)
- `system_ui_controller` info-dict field semantics (unless purely additive)

---

## Smoke matrix (required before implementation)

| ID | Assertion | Existing smoke? | Priority |
|----|-----------|-----------------|----------|
| S1 | SIGNAL selection: `ResourcePanel` + `ResourceTitleLabel` + `DividerB` not visible | Partial (manual) | **P0** |
| S2 | SIGNAL: `ScanWithDroneButton` + `SendMiningShipButton` not visible | No | **P0** |
| S3 | SIGNAL: `InvestigateButton` visible (when gate allows) | Partial (`sensor_pulse` uses investigate path) | **P0** |
| S4 | SIGNAL during investigate: `InvestigateProgressLabel` visible; `SensorPulseProgressLabel` hidden | **Yes** (`sensor_pulse_progress_label_cleanup`) | P0 |
| S5 | Home base pulse: `SensorPulseProgressLabel` visible; investigate label not showing pulse text | **Yes** | P0 |
| S6 | KNOWN Mars: resource section visible when scanned resources exist | No | P1 |
| S7 | Signal → KNOWN transition (after investigate reveal): resource + scan/mine restored | No | **P0** |
| S8 | Panel height on SIGNAL &lt; KNOWN height (no large empty gap) | No | P1 |
| S9 | Saturn (or wide preview): lore text does not overflow panel width absurdly | No | P1 |
| S10 | `object_info_simple_action_button_labels` regression | **Yes** | P0 |
| S11 | `SAVE_VERSION == 1`, `tooltip_text == 0` | Various smokes | P0 |

**Proposed new runner:** `scripts/debug/smoke_tests/object_info_signal_layout_smoke_runner.tscn` covering S1–S3, S7–S8 minimum.

---

## Nächster Implementierungs-Prompt (wenn freigegeben)

Use only after smoke S1–S5, S7, S10 exist or pass manually.

```
TASK: ObjectInfo SignalInfoSubPanel — Phase C1 (layout only).

Constraints:
- Godot 4.6.1, strict typing.
- Presentation only: no GameSession gate changes, no SAVE_VERSION change, tooltip_text = 0.
- Keep ObjectInfoPanel public API (show_body_info, show_poi_info, show_empty, apply_investigate_progress, set_distance_text).

Steps:
1. Create scenes/ui/system/signal_info_sub_panel.tscn + scripts/ui/system/signal_info_sub_panel.gd
   - Contains: Lore block (compact), EconomyBlockLabel, InvestigateButton, InvestigateProgressLabel
   - Optional: move MainRow meta here OR keep shared in host (document choice).
2. ObjectInfoPanel: toggle signal vs known sections; delete _apply_signal_panel_layout,
   _fit_signal_lore_text_height, _restore_known_lore_layout, offset_bottom manipulation for signal branch
   ONLY after subscene reproduces compact layout in editor.
3. Run smokes: object_info_signal_layout, sensor_pulse_progress_label_cleanup,
   object_info_simple_action_button_labels, SAVE/tooltip regression.
4. Update docs/ui/object_info_panel_signal_layout_v0_1.md with new tree.

Out of scope: KnownObjectInfoSection split (C2), SystemUIController refactor, TopHUD dedup.
```

---

## Changed files (this spike only)

| File | Change |
|------|--------|
| `docs/design/object_info_signal_layout_refactor_plan_v0_1.md` | **New** — this document |

**Unchanged:** all `.gd`, `.tscn`, gameplay, `SAVE_VERSION`, `tooltip_text`.

---

## Verdict

**PASS WITH NOTES**

- Ist-Zustand and runtime layout inventory documented.
- Three options evaluated with recommendation (A now, C for implementation).
- Smoke requirements defined; gaps identified (signal height, transition, Saturn preview).
- No code or scene changes.
- Full Project Cleanup A1 remains **open for implementation** but **unblocked for “design spike first”** closure.
