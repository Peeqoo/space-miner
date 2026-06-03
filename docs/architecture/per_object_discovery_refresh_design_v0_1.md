# Per-object Discovery Refresh Design v0.1

**Status:** Implemented (Phase 3.4 Steps 2–5 + follow-ups). This document remains the architecture reference.  
**Engine:** Godot 4.6.1 / GDScript (strict typing).  
**Related:** `docs/audits/phase_3_4_discovery_refresh_smoketest_v0_1.md`; `docs/ui/object_info_panel_signal_layout_v0_1.md`; `docs/save_behavior_v0_1.md`.

---

## Purpose

`SystemDiscoveryController.apply_for_system()` is the **correct** way to sync **all** spawned bodies/POIs with `ObjectScanStore` discovery state for the active system. It:

1. Clears every `SignalMarker` in `_markers_by_object_id`.
2. Iterates `SystemDefinition.bodies` and `.pois`.
3. For each spawned instance, calls `_apply_discovery_to_world_object()`.

That is appropriate for **system enter**, **initial spawn**, and **bulk state reconciliation** after load.

It is **broader than necessary** when only one or a few `object_id` values change at runtime, for example:

- **Base Sensor Pulse:** `HIDDEN` → `SIGNAL` for 1–N candidates.
- **Survey Probe investigate complete:** `SIGNAL` → `KNOWN` for one `object_id`.
- Future single-object discovery events (POI reveal, scripted reveals).

**Per-object refresh** (`refresh_object` / `refresh_objects`) is implemented for runtime visibility. Goals achieved:

- **Performance / robustness:** avoid tearing down every marker on small state changes (sensor pulse, survey probe, colony establish).
- **No new discovery rules:** store semantics stay in `GameSession` / `ObjectScanStore`; controllers only apply visibility.
- **No mixing concerns:** `discovery_state` (`hidden` / `signal` / `known`) remains independent of `scan_state` (`unknown` / `basic` / `deep` / `special`).

**Store-driven apply pattern (v0.1):**

1. Caller sets `GameSession.set_object_discovery_state(system_id, object_id, state)` (or establish path sets KNOWN via `_apply_established_base_record`).
2. Caller or listener invokes `SystemDiscoveryController.refresh_object(object_id)` or `refresh_objects(ids)`.
3. Controller reads `GameSession.get_object_discovery_state` and runs `_apply_discovery_to_world_object()` — **no** `_clear_all_markers()` in this path.

**Removed:** `reveal_object()` — legacy parallel path that forced visibility without reading store; **no** callers in `scripts/`.

---

## Current Discovery Flow

### 1. Source of truth (data)

| Layer | Responsibility |
|-------|----------------|
| `ObjectScanStore.object_discovery_states` | `system_id → object_id → "hidden" \| "signal" \| "known"` |
| `GameSession` | Facade: `set_object_discovery_state`, `get_object_discovery_state`, `DISCOVERY_*` constants |
| `SystemDefinition` + body/POI `.tres` | Default discovery for **new** objects via `_seed_discovery_from_system_definition` (only if no explicit saved state) |

`object_scan_states` and `remaining_resources_by_object` are **separate** dictionaries in the same store; discovery refresh must not touch them.

### 2. Runtime application (`SystemDiscoveryController`)

```
apply_for_system(system_definition)
  → _clear_all_markers()          # every marker queue_free; may clear_selection if selected
  → for each body/poi in definition:
        spawned = spawner.get_spawned_object(id)
        _apply_discovery_to_world_object(system_id, object_id, node, definition)
```

`_apply_discovery_to_world_object()` reads **`GameSession.get_object_discovery_state(system_id, object_id)`** and:

| State | World object (`SystemBody` / `PointOfInterest`) | Marker |
|-------|---------------------------------------------------|--------|
| `DISCOVERY_HIDDEN` | `set_discovery_surface_visible(false)`, `set_discovery_interactable(false)` | `_remove_marker(object_id)` |
| `DISCOVERY_SIGNAL` | hidden + not interactable | `_spawn_or_refresh_marker(...)` |
| `DISCOVERY_KNOWN` (default branch) | visible + interactable | `_remove_marker(object_id)` |

### 3. `SignalMarker` (presentation only)

- Spawned as **child of** the hidden world object (`world_object.add_child(marker)`).
- `configure()` sets stable `object_id`, signal type copy, texture, `target_object`.
- `get_info()` / `build_signal_info()` feeds **ObjectInfoPanel** SIGNAL layout (`is_discovery_signal`, lore, investigate UI).
- Registered with `SystemSelectionController.register_signal_marker()`.

### 4. Selection / UI (downstream)

- **SIGNAL:** user selects `SignalMarker` → `SystemUIController._build_signal_marker_info()`.
- **KNOWN:** user selects `SystemBody` / `PointOfInterest` → `_build_world_object_info()` with **scan** state from `GameSession.get_object_scan_state()` (not discovery).

See `docs/ui/object_info_panel_signal_layout_v0_1.md` for panel layout rules.

### 5. Runtime per-object paths (implemented)

| Flow | State write | Visual apply | Notes |
|------|-------------|--------------|-------|
| **Survey Probe** complete | `set_object_discovery_state(..., KNOWN)` | `discovery_controller.refresh_object(oid)` | Then reward + `_refresh_selection_after_reveal()` (may `select_world_node` if marker was selected) |
| **Sensor Pulse** complete | Per candidate: `set_object_discovery_state(..., SIGNAL)` | `discovery_controller.refresh_objects(revealed_ids)` | No `apply_for_system` on completion |
| **Colony / base establish** | `_apply_established_base_record` → KNOWN | `established_body_discovery_visual_refresh_requested` → `SystemUIController` → `refresh_object(body_id)` if `system_id` matches active system | No `apply_for_system`; signal avoids `GameSession` touching scene nodes |
| **System enter / load** | `ensure_default_discovery_for_system` (data) | `system_scene.gd` → `apply_for_system(system_definition)` | Full reconciliation only here |

---

## Full vs per-object call sites (current)

| Call site | Trigger | Mechanism |
|-----------|---------|-----------|
| `system_scene.gd` `_ready()` | After spawn + `ensure_default_discovery_for_system` | **`apply_for_system`** — keep |
| `base_sensor_pulse_controller.gd` `_complete_pulse()` | HIDDEN → SIGNAL for 1–N ids | **`refresh_objects(revealed_ids)`** |
| `survey_probe_mission_controller.gd` `_complete_mission()` | SIGNAL → KNOWN | **`refresh_object(oid)`** |
| `game_session.gd` `_apply_established_base_record()` | Colony/base KNOWN | **Signal** → `SystemUIController.refresh_object` when in same system |
| `game_session.gd` `apply_save_data()` | Data only | **`ensure_default_discovery_for_system`**; visual sync on next `SystemScene` enter via **`apply_for_system`** |

**`apply_for_system` external callers in `scripts/`:** `system_scene.gd` only.  
**`reveal_object`:** removed — **0** references in `scripts/`.

---

## Ownership / Source of Truth

| Concern | Owner | Per-object refresh may change? |
|---------|--------|--------------------------------|
| Discovery state values | `ObjectScanStore` via `GameSession` | **No** — callers set state **before** refresh |
| Default / seed discovery | `GameSession.ensure_default_discovery_for_system` | **No** |
| Object visibility & pickability | `SystemBody` / `PointOfInterest` `set_discovery_*` | **Yes** — apply store state to nodes |
| Marker lifecycle | `SystemDiscoveryController._markers_by_object_id` | **Yes** — spawn / remove / refresh one id |
| Signal info dict content | `SignalMarker` + definitions | **Yes** only via marker re-`configure` on SIGNAL |
| Selection | `SystemSelectionController` | **Indirect** — via `_remove_marker` → `clear_selection` if needed |
| ObjectInfoPanel content | `SystemUIController` from selection | **No** — panel reacts to selection signals |
| Scan state | `ObjectScanStore.object_scan_states` | **No** — out of scope |
| remaining_resources | `ObjectScanStore` | **No** |
| Survey probe FSM | `SurveyProbeMissionController` | **No** |
| Sensor pulse cost / refund | `BaseSensorPulseController` | **No** |
| Save JSON shape | `object_scans` blob in save | **No** |

---

## API (`SystemDiscoveryController` — implemented)

Implemented on **`SystemDiscoveryController`**:

```gdscript
## Re-applies discovery visibility for one object from GameSession store. Returns false if object not spawned.
func refresh_object(object_id: String) -> bool

## Re-applies discovery for many ids. Returns count successfully refreshed.
func refresh_objects(object_ids: Array[StringName]) -> int
```

### Internal helpers (private)

```gdscript
func _find_world_object_and_definition(object_id: String) -> Dictionary
  # Returns { "world_object": Node2D, "definition": Resource } or empty

func _refresh_object_from_store(object_id: String) -> bool
  # Uses GameSession.current_system_id + get_object_discovery_state
  # Calls existing _apply_discovery_to_world_object(system_id, object_id, node, definition)
```

**Do not** call `_clear_all_markers()` in per-object paths.

### Return values & errors

| API | Success | Failure (no crash) |
|-----|---------|-------------------|
| `refresh_object(id)` | `true` if spawned node found and apply ran | `false` if empty id, no spawner, no spawn, or no definition entry |
| `refresh_objects(ids)` | number of `true` results | skip empty / invalid ids |

### Fallback policy

- **Primary:** read state from store, apply via `_apply_discovery_to_world_object`.
- **If spawn missing:** log once (`push_warning`), return `false`; **do not** auto-call `apply_for_system`.
- **Optional dev-only recovery:** documented manual `apply_for_system` when `_markers_by_object_id` size ≠ expected SIGNAL count (debug menu) — not v0.1 gameplay.

### `reveal_object()` (removed)

Former shortcut removed in Phase 3.4 follow-up. All gameplay paths use store state + `refresh_object` / `refresh_objects` / `_apply_discovery_to_world_object`.

---

## State Transition Behavior

Per-object refresh must implement the same semantics as `_apply_discovery_to_world_object` for the **new** store state (caller updates store first).

| Old → New | World object | Marker | Selection (typical) |
|-----------|--------------|--------|---------------------|
| **HIDDEN → SIGNAL** | Stay hidden, not interactable | `_spawn_or_refresh_marker` (replace if exists) | Unchanged unless user had nothing selected |
| **SIGNAL → KNOWN** | Visible + interactable | `_remove_marker` (clears selection if marker was selected) | Survey probe: optional `select_world_node` in mission controller — **not** in discovery controller by default |
| **HIDDEN → KNOWN** | Visible + interactable | Remove if any | Rare (debug/save/direct); same as KNOWN branch |
| **SIGNAL → HIDDEN** | Hidden | Remove marker | Clear selection if marker selected |
| **KNOWN → SIGNAL** | Hide surface | Spawn marker | Clear world selection if body selected (edge / debug) |
| **KNOWN → HIDDEN** | Hide | Remove marker | Clear selection |

**v0.1 gameplay paths:** mainly **HIDDEN → SIGNAL** (sensor pulse) and **SIGNAL → KNOWN** (investigate complete).

**ScanState:** unchanged on all transitions. ObjectInfoPanel scan/mine gates use `get_object_scan_state` only for **known** world nodes.

---

## Marker Lifecycle Rules

1. **At most one** `SignalMarker` per `object_id` in `_markers_by_object_id`.
2. `_spawn_or_refresh_marker` already calls `_remove_marker(oid)` before instantiate — per-object refresh must **reuse** this, never add a second marker without remove.
3. `_remove_marker`:
   - Erases dict entry.
   - If `selection.get_selected_node() == marker` → `selection.clear_selection(true)`.
   - `marker.queue_free()`.
4. **KNOWN** transition must leave **no** marker for that id (no orphans).
5. Marker parent remains the **world object** node (current scene tree: child of `SystemBody` / `PointOfInterest` under `SystemBodiesRoot` / `PointOfInterestRoot`).
6. `SignalMarker.object_id` must match store / spawner id (body_id / poi id).
7. **`apply_for_system` difference:** starts with `_clear_all_markers()` — per-object path must **not** do global clear (avoids mass selection loss and flicker).

---

## Selection Rules

| Scenario | Required behavior |
|----------|-------------------|
| Selected **SignalMarker** revealed to KNOWN | `_remove_marker` clears selection (`clear_selection(true)`); panel goes empty until user clicks again |
| Survey probe complete (current) | Mission controller may **`select_world_node(revealed)`** after **`refresh_object`** — keep this **outside** `refresh_object` unless product asks to centralize |
| Selected **known body** hidden (debug) | `clear_selection` if pickable removed |
| Per-object refresh during pulse | Other objects’ markers must **not** be destroyed — selection on another signal preserved |
| ObjectInfoPanel | Must never hold reference to freed marker; `SystemUIController` listens to selection cleared / changed |

**Design default for `refresh_object`:** do **not** auto-select the revealed body (matches “no automatic Umspringen” except existing survey probe hook).

---

## Interaction / Clickability Rules

| State | World surface | World click (`Area2D`) | Marker click |
|-------|---------------|------------------------|--------------|
| HIDDEN | invisible | not pickable | none |
| SIGNAL | invisible | not pickable | pickable (`SignalMarker` Area2D) |
| KNOWN | visible (incl. orbit unit layers on body) | pickable | none |

`SystemBody.set_discovery_surface_visible` also toggles `back_orbit_units` / `front_orbit_units` visibility — per-object refresh must continue using body/POI helpers, not ad-hoc sprite toggles.

---

## When Full `apply_for_system()` Should Remain

- `SystemScene` initial setup after spawn (first frame discovery sync).
- Entering a system scene after load (save applied → spawn → full apply).
- Large reconciliation: many discovery states changed at once.
- Debug / recovery: marker dict inconsistent with store (count mismatch).
- After changing `SystemDefinition` membership (add/remove bodies) — rare in v0.1.

---

## When Per-object Refresh Is Better

- Base sensor pulse: **1–N** `HIDDEN` → `SIGNAL` (N = `base_sensor_reveal_count`, typically small).
- Survey probe: **1** `SIGNAL` → `KNOWN` — **`refresh_object`** (done).
- Colony / establish base: **`refresh_object`** via signal when player is in target system (done).
- Future scripted POI / anomaly reveals.
- Editor/debug “reveal this object” tools.

---

## Save/Load Considerations

- Save stores `object_discovery_states` inside `object_scans` (`ObjectScanStore.build_save_data` / `apply_save_data`).
- Per-object refresh is **runtime presentation only**; no migration, no new keys.
- `GameSession.apply_save_data` calls `ensure_default_discovery_for_system` but **not** `apply_for_system` — visual sync happens when player opens `SystemScene` (`_ready` full apply). **Keep this.**
- After load, individual reveals during play should use per-object refresh; entering system still uses full apply once.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Duplicate markers for same `object_id` | **High** | Always `_remove_marker` before spawn; single dict key |
| Marker remains after KNOWN | **High** | KNOWN branch must `_remove_marker`; verify in tests |
| Body stays hidden after reveal | **High** | Use `_apply_discovery_to_world_object`, not partial visibility hacks |
| Selection / panel points at freed marker | **High** | Keep `_remove_marker` selection guard; no deferred panel access to marker |
| Wrong id (POI vs body) | **Medium** | Resolve via `spawner.get_spawned_object` + definition lookup by id |
| Confuse discovery with scan | **Medium** | Code review: refresh file must not call scan APIs |
| Sensor pulse only updates subset visually | **Medium** | `refresh_objects` only for ids whose store state changed |
| `reveal_object` vs store drift | ~~Medium~~ | **Resolved** — `reveal_object` removed; single store-driven path |
| Full apply during pulse clears unrelated selection | ~~Medium~~ | **Resolved** — pulse uses `refresh_objects` only |
| Colony KNOWN without visual refresh | ~~Low~~ | **Resolved** — `established_body_discovery_visual_refresh_requested` + `SystemUIController` |
| `refresh_object` returns false | **Low** | `push_warning` only; store state still correct; full apply on system enter heals edge cases |
| Orbit/automation visibility side effects | **Low** | Only use existing `set_discovery_surface_visible` |
| Save/load inconsistency | **Low** | Full apply on scene enter unchanged |

---

## Implementation status (Phase 3.4)

| Step | Status |
|------|--------|
| 1 — Design / audit | **Done** (this doc) |
| 2 — `refresh_object` / `refresh_objects` internal | **Done** |
| 3 — Survey Probe → `refresh_object` | **Done** |
| 4 — Sensor Pulse → `refresh_objects` | **Done** |
| 5 — Full `apply_for_system` on setup/enter only | **Done** (`system_scene.gd`) |
| Follow-up — Remove `reveal_object` | **Done** |
| Follow-up — Colony establish visual refresh | **Done** (GameSession signal + `SystemUIController`) |

Manual runtime smoke: see `docs/audits/phase_3_4_discovery_refresh_smoketest_v0_1.md` (static PASS; editor playtest recommended).

---

## Tests Required Before / After Implementation

- [ ] New game: default HIDDEN bodies show no surface; SIGNAL markers at signal-default bodies (if any).
- [ ] Select `SignalMarker` → ObjectInfoPanel SIGNAL layout (investigate visible, no resources).
- [ ] Investigate complete → KNOWN, marker gone, body selectable, panel valid (survey selection transfer if applicable).
- [ ] Sensor pulse: only targeted HIDDEN → SIGNAL; no duplicate markers; other signals remain.
- [ ] Multiple pulses in a row.
- [ ] Save after reveal / after pulse → reload → states and visuals match (full apply on enter).
- [ ] POI with discovery defaults (if present in system).
- [ ] Empty selection after marker removed while selected (no crash).
- [ ] `grep tooltip_text` → 0 in `*.gd` / `*.tscn` / `*.tres`.

---

## Do Not Touch (implementation phases)

- `ObjectScanStore` save schema and discovery normalization
- Scan state transitions and scan rewards
- `remaining_resources` init/depletion
- `SurveyProbeMissionController` mission timing, costs, refunds (except discovery **apply** call in Step 3)
- `BaseSensorPulseController` cost/refund/reveal count rules (except discovery **apply** call in Step 4)
- `ObjectInfoPanel` signal layout contract / scene structure
- `SystemUIController` gate and info dict builders (except via selection changes)
- `AutomationController`
- `SaveManager` format
- Resource catalog
- `data/planet_resources`, production/upgrade `.tres`

---

## Recommended next step

Phase 3.4 implementation is complete. Optional:

- Run editor manual smoke (checklist in audit doc) and mark manual rows PASS.
- Future save v0.2: persist in-flight probe/pulse if product requires (see `docs/save_behavior_v0_1.md`).
