# SystemUIController Selection Polymorphism v0.1

Reference for how `system_ui_controller.gd` builds selection info from **polymorphic world nodes** (`SystemBody`, `PointOfInterest`, `SignalMarker`) while all UI panels stay fully typed.

Godot 4.6.1 — **Phase 2** typed panels; **Phase 3.1** replaced dynamic `selected_node` `has_method` / `call` with an explicit typed adapter.

---

## Purpose

`SystemUIController` (`scripts/system/controller/system_ui_controller.gd`) orchestrates system-scene UI: selection → info dictionary → panels.

**Phase 2** typed panel references (direct methods only on panels):

| Field | Type |
|-------|------|
| `object_info_panel` | `ObjectInfoPanel` |
| `base_management_panel` | `BaseManagementPanel` |
| `storage_panel` | `StoragePanel` |
| `production_panel` | `ProductionPanel` |
| `upgrade_panel` | `UpgradePanel` |
| `top_hud` | `TopHUD` |
| `top_hud_hover_panel` | `TopHUDHoverPanel` |

**Phase 3.1** replaced dynamic `selected_node` calls with a **typed selection-info adapter**.  
`system_ui_controller.gd` now has **0** `has_method` and **0** `.call(` (repo grep).

`selected_node` from `SystemSelectionController.get_selected_node()` is still polymorphic (`Node`), but info is resolved via explicit `is SystemBody` / `is PointOfInterest` branches — not runtime string dispatch.

Project rule: **`tooltip_text`** must stay at **0** repo-wide (`*.gd` / `*.tscn` / `*.tres`). This doc does not introduce tooltips.

---

## Current State

### Typed UI panels

All panel operations use `is_instance_valid(...)` and typed method calls (`show_body_info`, `hide_panel`, `refresh_from_game_session`, `set_base_id`, `clear`, etc.).

### Typed world selection (Phase 3.1)

World scan info is built through **`_build_world_object_info()`** — no `has_method` / `call` in this controller.

| Component | Role |
|-----------|------|
| `_build_world_object_info(selected_node, scan_state, unlocked_scan_layer)` | Returns scan/info dict for known world objects |
| `_build_signal_marker_info(marker)` | **Separate** early path for `SignalMarker` (discovery) |
| `_build_selected_object_info(selected_node)` | Routes SignalMarker → signal builder; else adapter + gates/lore |

### Adapter implementation (current code)

```gdscript
func _build_world_object_info(
    selected_node: Node,
    scan_state: String,
    unlocked_scan_layer: int,
) -> Dictionary:
    if selected_node is SystemBody:
        return (selected_node as SystemBody).build_scan_info(scan_state, unlocked_scan_layer)
    if selected_node is PointOfInterest:
        return (selected_node as PointOfInterest).build_scan_info(scan_state, unlocked_scan_layer)
    return {}
```

**`_build_selected_object_info()` flow:**

1. `if selected_node is SignalMarker` → `return _build_signal_marker_info(...)` (unchanged).
2. Resolve `scan_state` / `unlocked_scan_layer` from `GameSession`.
3. `var info := _build_world_object_info(selected_node, scan_state, unlocked_scan_layer)`.
4. Merge controller fields (preview, distance, scan/mine gates, lore, colonization, sensor pulse) — unchanged.

### Other selection-related code (not `has_method` in SystemUIController)

| Mechanism | Where | Role |
|-----------|--------|------|
| `selected_node is SignalMarker` | `_build_selected_object_info()` | Early exit → `_build_signal_marker_info()` |
| `selected_node is SystemBody` / `PointOfInterest` | `update_object_info()`, `_get_object_id()`, gates | Typed `is` checks |
| `object_info_panel.show_body_info` / `show_poi_info` | `update_object_info()` | Typed panel API |
| `_process()` distance | `object_info_panel.set_distance_text(...)` | Typed |

**Out of scope (still dynamic elsewhere):** `system_selection_controller.gd` may use `has_method("set_selected")` in `clear_selection()` for non-marker nodes — not part of `system_ui_controller.gd`.

---

## Why a typed adapter (not `has_method` / `call`)

1. **Multiple world types** — Selection stores `Node`; registrations are `SystemBody`, `PointOfInterest`, `SignalMarker`.
2. **No shared world interface** — Body and POI share `build_scan_info(...)` signatures but no common base class in GDScript.
3. **SignalMarker stays separate** — Uses `build_signal_info()` via `_build_signal_marker_info()`, not `_build_world_object_info()`. Discovery/reveal must preserve that split (`SystemDiscoveryController`).
4. **Explicit branches** — Compile-time types on `SystemBody` / `PointOfInterest`; easier to review than string-based `call`.
5. **Unknown types → `{}`** — Any selectable node not handled in the adapter returns an empty dict; downstream gates still run but panel data may be minimal.

### Warning: new selectable types

When adding a **new** world node type that should appear in ObjectInfoPanel:

- Add an explicit branch in **`_build_world_object_info()`** (or a dedicated builder like SignalMarker).
- Do **not** assume `has_method` fallback — there is none in `system_ui_controller.gd`.
- Without a branch, selection yields **`{}`** and may show sparse/empty info until extended.

---

## Known selected_node Types

| Type | Script | When selected | Info source in controller | Panel entry |
|------|--------|---------------|---------------------------|-------------|
| **SignalMarker** | `signal_marker.gd` | `DISCOVERY_SIGNAL` | `_build_signal_marker_info()` → `build_signal_info()` + investigate fields | `show_body_info(info)` (signal layout) |
| **SystemBody** | `system_body.gd` | Known body (incl. **Base/Earth**) | `_build_world_object_info()` → `build_scan_info(...)`; lore from `definition.description` | `show_body_info(info)` |
| **PointOfInterest** | `point_of_interest.gd` | Known POI | `_build_world_object_info()` → `build_scan_info(...)`; lore from `definition.description` | `show_poi_info(info)` |
| **Unknown / other** | — | Should not be selectable today | `{}` from adapter | Risk: empty dict if wired without adapter branch |
| *(none)* | — | `clear_selection` | — | `show_empty()`, panel hidden |

**Discovery visibility** (`system_discovery_controller.gd`): HIDDEN → SIGNAL (marker) → Known (body/POI visible).

**ID resolution:** `_get_object_id()` — typed `is` on `SignalMarker` / `SystemBody` / `PointOfInterest`.

---

## World node info APIs (reference)

| Class | `build_scan_info(scan_state, unlocked_scan_layer)` | Selection path |
|-------|-----------------------------------------------------|----------------|
| `SystemBody` | Full dict via `ScanInfoBuilder` | `_build_world_object_info()` |
| `PointOfInterest` | Full dict via `ScanInfoBuilder` | `_build_world_object_info()` |
| `SignalMarker` | N/A on this path | `_build_signal_marker_info()` → `build_signal_info()` |

`get_info()` still exists on Body/POI for other uses; **not** called from `_build_world_object_info()` (adapter uses `build_scan_info` only).

---

## Responsible Functions

All in `scripts/system/controller/system_ui_controller.gd` unless noted.

| Function | Role |
|----------|------|
| `_on_selection_changed()` | `selection_changed` → `update_object_info()` + `update_base_panel()` |
| `update_object_info()` | Selection → dict → `ObjectInfoPanel.show_*` |
| `_build_selected_object_info(selected_node)` | SignalMarker early exit; else `_build_world_object_info` + controller enrichments |
| **`_build_world_object_info(selected_node, scan_state, unlocked_scan_layer)`** | **Typed adapter** — Body / POI `build_scan_info`; else `{}` |
| `_build_signal_marker_info(marker)` | Signal/discovery dict |
| `_get_object_id(node)` | Typed IDs per node kind |
| `_apply_scan_drone_info_to_dict` / `_apply_mining_ship_info_to_dict` | Gates; skip SignalMarker |
| `_apply_colonization_info_to_dict` / `_apply_sensor_pulse_info_to_dict` | Body/POI / home base |
| `_process()` | `set_distance_text` while panel visible |

---

## Historical note (Phase 2 → 3.1)

Before Phase 3.1, `_build_selected_object_info()` used:

```gdscript
# REMOVED — do not reintroduce
if selected_node.has_method("build_scan_info"):
    info = selected_node.call("build_scan_info", scan_state, unlocked_scan_layer)
elif selected_node.has_method("get_info"):
    info = selected_node.call("get_info")
```

Replaced by `_build_world_object_info()` as shown above. The old `get_info()` fallback for unknown nodes is **not** replicated; unknown types return `{}` instead.

---

## Future Improvement (optional, larger scope)

Phase 3.1 adapter is the **minimal** fix. Larger options if many world types appear:

### Shared provider interface

- e.g. `ScanInfoProvider` with `build_panel_scan_info(scan_state, unlocked_scan_layer) -> Dictionary`
- Implemented by `SystemBody` and `PointOfInterest`; **not** `SignalMarker`

### Registry map

- `class_name` → `Callable` — only if branch list grows unwieldy

**Prerequisites:** Smoke matrix below green; keep `system_ui_controller.gd` at **0** `has_method` / `.call(` unless documented otherwise.

---

## Do Not Change Casually

- **`_build_world_object_info()`** — add new world types here explicitly
- `if selected_node is SignalMarker` + `_build_signal_marker_info()`
- `SignalMarker.build_signal_info()` / `object_id`
- `SystemDiscoveryController` marker spawn / reveal / removal
- `SystemSelectionController` selection routing
- `update_object_info()` → `show_body_info` vs `show_poi_info`
- `ObjectInfoPanel` signal vs known layout (`docs/ui/object_info_panel_signal_layout_v0_1.md`)
- `GameSession` discovery / scan / mine / investigate gates
- `ScanInfoBuilder` on bodies/POIs
- Reintroducing `has_method` / `call` on `selected_node` in this file
- Reintroducing `tooltip_text`

---

## Smoke Test

Manual regression after any selection or adapter change:

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
- [ ] `grep has_method` / `grep '\.call\('` in `system_ui_controller.gd` → **0**
- [ ] No red runtime errors when switching signal ↔ body ↔ POI ↔ empty

---

## Related Files

| Path | Relevance |
|------|-----------|
| `scripts/system/controller/system_ui_controller.gd` | `_build_world_object_info`, `_build_selected_object_info` |
| `scripts/system/controller/system_selection_controller.gd` | `selected_node` owner |
| `scripts/system/controller/system_discovery_controller.gd` | Signal vs known visibility |
| `scripts/system/signal_marker.gd` | Discovery marker info |
| `scripts/system/system_body.gd` | `build_scan_info` |
| `scripts/system/point_of_interest.gd` | `build_scan_info` |
| `scripts/system/components/scan_info_builder.gd` | Shared scan dict builder |
| `docs/ui/object_info_panel_signal_layout_v0_1.md` | Signal vs known panel layout |
