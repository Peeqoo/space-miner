# SystemUIController Selection Polymorphism v0.1

Documentation-only reference for **why** `system_ui_controller.gd` still uses `has_method` / `call` on `selected_node`, while all major UI panels are typed. Prevents accidental “cleanup” that breaks discovery selection or scan info building.

Godot 4.6.1 — reflects repo state after Phase 2 panel typing.

---

## Purpose

`SystemUIController` (`scripts/system/controller/system_ui_controller.gd`) orchestrates system-scene UI: selection → info dictionary → panels.

**Phase 2** typed these panel references (direct methods, no `has_method` / `call` on them):

| Field | Type |
|-------|------|
| `object_info_panel` | `ObjectInfoPanel` |
| `base_management_panel` | `BaseManagementPanel` |
| `storage_panel` | `StoragePanel` |
| `production_panel` | `ProductionPanel` |
| `upgrade_panel` | `UpgradePanel` |
| `top_hud` | `TopHUD` |
| `top_hud_hover_panel` | `TopHUDHoverPanel` |

**Remaining dynamic calls** apply only to **`selected_node`**: the world object (or discovery marker) returned by `SystemSelectionController.get_selected_node()`. That value is **not** a single UI class; it is polymorphic runtime `Node` content.

Replacing those calls with a blind cast (e.g. always `SystemBody`) would break **SignalMarker**, **PointOfInterest**, or future world nodes. The current `has_method` / `call` pair is an **intentional adapter**, not leftover panel legacy.

Project rule: **`tooltip_text`** must stay at **0** repo-wide (`*.gd` / `*.tscn` / `*.tres`). This doc does not introduce tooltips.

---

## Current State

### Typed UI (no dynamic panel calls in controller)

All panel operations listed above use `is_instance_valid(...)` and typed method calls (`show_body_info`, `hide_panel`, `refresh_from_game_session`, `set_base_id`, `clear`, etc.).

### Remaining dynamic calls (world selection only)

As of this document, **`system_ui_controller.gd` contains exactly four lines** using `has_method` / `call`:

| Lines (approx.) | Location |
|-----------------|----------|
| 485–488 | `_build_selected_object_info()` |

```gdscript
if selected_node.has_method("build_scan_info"):
    info = selected_node.call("build_scan_info", scan_state, unlocked_scan_layer)
elif selected_node.has_method("get_info"):
    info = selected_node.call("get_info")
```

No other `has_method` / `call` remain in this file (verified by repo grep).

### Related code that is **not** dynamic (for clarity)

| Mechanism | Where | Role |
|-----------|--------|------|
| `selected_node is SignalMarker` | `_build_selected_object_info()` | Early exit → `_build_signal_marker_info()` (no `build_scan_info` on marker path) |
| `selected_node is SystemBody` / `PointOfInterest` | `update_object_info()`, `_get_object_id()`, gates | Typed `is` checks for routing and IDs |
| `object_info_panel.show_body_info` / `show_poi_info` | `update_object_info()` | Typed panel API after dict is built |
| `_process()` distance | `object_info_panel.set_distance_text(...)` | Typed; uses `selection.get_selected_node()` as `Node2D` only for position |

---

## Why selected_node remains dynamic

1. **Multiple world types** — `SystemSelectionController.selected_node` is typed as `Node`. Registrations: `SystemBody`, `PointOfInterest`, `SignalMarker` (`system_selection_controller.gd`).
2. **No shared world interface yet** — Bodies and POIs both implement `build_scan_info(scan_state, unlocked_scan_layer)` and `get_info()`, but there is no common `class_name` base or GDScript interface enforced at compile time on `Node`.
3. **SignalMarker is a separate path** — Uses `SignalMarker.build_signal_info()` via `_build_signal_marker_info()`, not the `build_scan_info` branch. Discovery/reveal must keep that split (`SystemDiscoveryController`).
4. **Adapter pattern** — `has_method` chooses the richest info producer available on the node. `get_info()` is a thinner fallback if `build_scan_info` were ever missing on a new type.
5. **Gates stay in the controller** — After the dict is built, `_apply_scan_drone_info_to_dict`, `_apply_mining_ship_info_to_dict`, colonization, sensor pulse, etc. add gameplay fields. The panel only displays; world nodes supply scan/resource-shaped data.

---

## Known selected_node Types

Only types that exist in the project today.

| Type | Script | When selected | Info source in controller | Panel entry |
|------|--------|---------------|---------------------------|-------------|
| **SignalMarker** | `signal_marker.gd` | `DISCOVERY_SIGNAL`: hidden body/POI, marker clickable | `_build_signal_marker_info()` → `marker.build_signal_info()` + investigate fields from `SurveyProbeMissionController` | `show_body_info(info)` (signal layout in `ObjectInfoPanel`) |
| **SystemBody** | `system_body.gd` | Known body visible; includes **Base/Earth** when established | `build_scan_info(scan_state, unlocked_scan_layer)` via dynamic call; lore merged from `body.definition.description` | `show_body_info(info)` |
| **PointOfInterest** | `point_of_interest.gd` | Known POI visible | Same dynamic `build_scan_info` / `get_info` as body | `show_poi_info(info)` → same `_apply_info()` |
| *(none)* | — | Empty space / `clear_selection` | — | `show_empty()`, panel hidden |

**Discovery visibility** (`system_discovery_controller.gd`):

- `DISCOVERY_HIDDEN` — world object hidden, no marker.
- `DISCOVERY_SIGNAL` — world object hidden + `SignalMarker` spawned at target.
- **Known** — marker removed, `SystemBody` / `PointOfInterest` visible and selectable.

**ID resolution** (typed, not dynamic): `_get_object_id()` uses `SignalMarker.object_id`, `SystemBody.body_id`, `PointOfInterest.poi_id`.

---

## World node info APIs (reference)

| Class | `get_info()` | `build_scan_info(scan_state, unlocked_scan_layer)` |
|-------|----------------|-----------------------------------------------------|
| `SystemBody` | Basic meta (`id`, `display_name`, `body_type`, orbit fields) | Full scan dict via `ScanInfoBuilder.build_scan_info(...)` |
| `PointOfInterest` | Basic meta (`id`, `display_name`, `poi_type`, orbit fields) | Same builder pattern for POI definitions |
| `SignalMarker` | Minimal marker meta (`get_info()`) | **Not used** on selection path; use `build_signal_info()` instead |

---

## Responsible Functions

All in `scripts/system/controller/system_ui_controller.gd` unless noted.

| Function | Role |
|----------|------|
| `_on_selection_changed()` | Wired to `SystemSelectionController.selection_changed`; calls `update_object_info()` + `update_base_panel()` |
| `update_object_info()` | Reads `selection.get_selected_node()`; builds dict; routes to `ObjectInfoPanel.show_*` |
| `_build_selected_object_info(selected_node)` | **Contains the only remaining `has_method` / `call`** for world info |
| `_build_signal_marker_info(marker)` | Signal-specific dict; investigate gates; no `build_scan_info` dynamic call |
| `_get_object_id(node)` | Typed `is SignalMarker` / `SystemBody` / `PointOfInterest` |
| `_apply_scan_drone_info_to_dict` | Skips `SignalMarker`; uses `GameSession.can_scan_object` |
| `_apply_mining_ship_info_to_dict` | Skips `SignalMarker`; uses `GameSession.can_mine_object` |
| `_apply_colonization_info_to_dict` | Body/POI only |
| `_apply_sensor_pulse_info_to_dict` | Home base (`SystemBody` + established base) only |
| `_process()` | Live distance: `object_info_panel.set_distance_text` while panel visible |

**Related (not in SystemUIController):**

| File | Note |
|------|------|
| `system_selection_controller.gd` | Owns `selected_node`; emits `selection_changed`; still uses `has_method("set_selected")` in `clear_selection()` for non-marker nodes — separate from UI controller doc scope |
| `system_discovery_controller.gd` | Spawn/remove markers; `reveal_object()` |

---

## Remaining Dynamic Calls

| File | Function | Call | Why dynamic? | Risk if replaced naively | When to refactor |
|------|----------|------|--------------|-------------------------|------------------|
| `system_ui_controller.gd` | `_build_selected_object_info` | `has_method("build_scan_info")` + `call(..., scan_state, unlocked_scan_layer)` | Body/POI share method name but selection type is `Node` | Wrong cast → missing resources/scan fields or runtime error | After shared interface or single adapter helper with typed branches |
| `system_ui_controller.gd` | `_build_selected_object_info` | `has_method("get_info")` + `call("get_info")` | Fallback for nodes without scan builder | Empty or incomplete panel if `build_scan_info` skipped incorrectly | Same as above; prefer explicit `is SystemBody` / `is PointOfInterest` before dropping dynamic |

**Count:** 2 `has_method` checks + 2 `call` invocations (one branch taken per selection).

---

## Why not replace now

1. **Scope** — Panel typing was bounded (known scene scripts). World selection needs a **cross-cutting contract** on gameplay nodes.
2. **Discovery safety** — Signal path already bypasses this block; a refactor must preserve `_build_signal_marker_info()` and `SystemDiscoveryController` marker lifecycle.
3. **ScanInfoBuilder** — `build_scan_info` delegates to `ScanInfoBuilder` with different definition types (`SystemBodyDefinition` vs `PointOfInterestDefinition`). A shared interface must still feed that builder correctly.
4. **Acceptable debt** — Four lines, one function, easy to grep. Cost of a bad replacement (broken scan UI, wrong POI panel, broken reveal) exceeds benefit of removing `call` today.
5. **No `tooltip_text`** — Any future work must not reintroduce Godot tooltips.

---

## Future Improvement

Preferred direction (design only — **not implemented**):

### Option A: Explicit adapter in `SystemUIController`

```gdscript
func _build_world_object_info(node: Node, scan_state: String, layer: int) -> Dictionary:
    if node is SystemBody:
        return (node as SystemBody).build_scan_info(scan_state, layer)
    if node is PointOfInterest:
        return (node as PointOfInterest).build_scan_info(scan_state, layer)
    return {}
```

Removes `has_method` / `call` while staying explicit. New world types add a new `is` branch and tests.

### Option B: Shared provider interface

Example names only:

- `SelectableWorldObject` or `ScanInfoProvider`
- `func build_panel_scan_info(scan_state: String, unlocked_scan_layer: int) -> Dictionary`
- `func get_stable_object_id() -> String`

Implemented by `SystemBody` and `PointOfInterest`; **not** by `SignalMarker` (keeps discovery separate).

### Option C: Registry map

`Dictionary` from `class_name` → `Callable` for info build. Flexible but more indirect; use only if many types appear.

**Prerequisites before any change:**

- Smoke test matrix below green
- Grep `has_method` / `call` in `system_ui_controller.gd` stays at zero **or** only in one documented adapter
- No change to `GameSession` gate semantics or `ObjectScanStore`

---

## Do Not Change Casually

- `_build_selected_object_info()` — `has_method` / `call` block (lines ~485–488) without full type matrix
- `if selected_node is SignalMarker` early return and `_build_signal_marker_info()`
- `SignalMarker.build_signal_info()` / `object_id`
- `SystemDiscoveryController` — `_apply_discovery_to_world_object`, `_spawn_or_refresh_marker`, `reveal_object`, marker removal on reveal
- `SystemSelectionController` — `selection_changed`, `register_*`, `clear_selection` when marker was selected
- `update_object_info()` routing: `SignalMarker` / `SystemBody` → `show_body_info`; `PointOfInterest` → `show_poi_info`
- `ObjectInfoPanel` signal vs known layout (`docs/ui/object_info_panel_signal_layout_v0_1.md`)
- `GameSession` discovery states (`DISCOVERY_HIDDEN`, `DISCOVERY_SIGNAL`, known), scan/mine/investigate gates
- `ScanInfoBuilder.build_scan_info` usage on bodies/POIs
- Reintroducing `tooltip_text`

---

## Smoke Test

Manual regression before/after any selection refactor:

- [ ] Select **SignalMarker** → compact ObjectInfoPanel, no resource section, Investigate as designed
- [ ] Start **Investigate** → progress; still signal layout
- [ ] **Reveal** → marker gone; select real **SystemBody** or **POI** → full panel
- [ ] **Known body** with resources → resource rows, scan/mine buttons per gates
- [ ] **Depleted** mine state → correct button/block text
- [ ] **Base/Earth** (established `SystemBody`) → BaseManagementPanel, Sensor Pulse, no mine on home
- [ ] **PointOfInterest** → POI type label, scan/mine if applicable
- [ ] **Empty selection** → panel hidden / empty state
- [ ] **Distance** updates while selection and panel visible
- [ ] Scan / Mine / Investigate / Sensor Pulse / Colony unchanged
- [ ] `grep tooltip_text` → **0** hits in `*.gd` / `*.tscn` / `*.tres`
- [ ] No red runtime errors when switching signal ↔ body ↔ POI ↔ empty

---

## Related Files

| Path | Relevance |
|------|-----------|
| `scripts/system/controller/system_ui_controller.gd` | Selection → UI orchestration; only remaining dynamic calls |
| `scripts/system/controller/system_selection_controller.gd` | `selected_node` owner |
| `scripts/system/controller/system_discovery_controller.gd` | Signal vs known visibility |
| `scripts/system/signal_marker.gd` | Discovery marker info |
| `scripts/system/system_body.gd` | `build_scan_info` / `get_info` |
| `scripts/system/point_of_interest.gd` | `build_scan_info` / `get_info` |
| `scripts/system/components/scan_info_builder.gd` | Shared scan dict builder |
| `docs/ui/object_info_panel_signal_layout_v0_1.md` | Signal vs known **panel** layout (separate concern) |
