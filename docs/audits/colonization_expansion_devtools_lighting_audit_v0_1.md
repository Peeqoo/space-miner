# Colonization / Expansion / Dev Tools / Lighting Audit v0.1

**Audit date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Method:** Static read-only code + data review (no Godot Editor run in this audit session)  
**Scope:** Fixed colonization targets, debug galaxy colonize button, new colony system initialization, system lighting consistency, data-driven system readiness.  
**Excluded:** Code/scene/data changes, balance tuning, save schema changes, tooltip introduction.

**References:** `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md`, `docs/audits/colony_colonization_text_audit_v0_1.md`

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Dev Button status** | **PASS WITH NOTES** — logic fixed (visible/disabled split); Editor live click-through **NOT TESTED** |
| **Colonization target status** | **PASS** — data + resolver + operation path consistent |
| **New colony system init status** | **PASS WITH NOTES** — runtime path complete; Proxima **data gap** for mineable resources |
| **Lighting consistency status** | **PASS WITH NOTES** — architecture system-wide; Proxima live visual parity **NOT TESTED** |
| **Wichtigster nächster Fix** | **Proxima Expansion SmokeTest live + `scan_resources` auf Proxima-Bodies ergänzen** |

**Tooltip-Check:** `tooltip_text` in geprüften Galaxy-HUD-Dateien → **0 Treffer**. Kein Vorschlag, Tooltips einzuführen.

---

## A) Fixed Colonization Target Audit

**Static verdict:** **PASS**

| Check | Expected | Result | Notes |
|-------|----------|--------|-------|
| `SystemDefinition.colonization_start_body_id` exists | Export on resource class | **PASS** | `resources/definitions/system_definition.gd` L29–30 |
| Resolver `get_resolved_colonization_start_body_id()` | Priority chain documented | **PASS** | L58–76: explicit → `start_body_id` → first `can_build_base` body → `""` |
| `_body_allows_colonization()` | Only `can_build_base` bodies | **PASS** | L79–89 |
| Solar `colonization_start_body_id` | `earth` | **PASS** | `data/galaxy_systems/solar_system.tres` L27 |
| Proxima `colonization_start_body_id` | `proxima_b` | **PASS** | `data/galaxy_systems/proxima_system.tres` L21 |
| `resolve_colonization_target_body_id()` | Uses resolver + warning on miss | **PASS** | `game_session.gd` L519–536 |
| `start_colonization_operation()` stores `target_body_id` | Resolver when arg empty | **PASS** | L563–607; record field `target_body_id` |
| `get_colonization_start_gate()` | Blocks empty/START/already established/pending/no ship | **PASS** | L543–560; normal gameplay unchanged |
| Save-v1 compatibility | No new save keys for target resolution | **PASS** | Ops still store `target_body_id` in existing colonization save array |
| No body list in Galaxy HUD | System name only, no body picker | **PASS** | `_colonization_system_target_text()` uses `display_name` only |
| SystemView colonize button hidden | Galaxy-only colonization v0.1 | **PASS** | `system_ui_controller.gd` L616–618: `colonization_button_visible = false` |
| Pending op intel may reference `target_body_id` | After op start only | **PASS WITH NOTES** | `galaxy_map_hud.gd` L435–436 reads pending `target_body_id` for intel label — not a body list, but reveals target body post-start (normal + dev flow) |

---

## B) Debug Galaxy Colonize Button Audit

**Static verdict:** **PASS WITH NOTES** (post visibility-fix)

### Root cause (previous invisibility)

The button was **not visible** because visibility was incorrectly coupled to full colonization eligibility:

1. `_set_dev_instant_colonize_button_visible(can_dev)` set **`visible` and `disabled` from the same boolean**.
2. `can_dev` required `access_state != LOCKED/UNREACHABLE` **and** `can_dev_instant_colonize_system()`.
3. `show_system_info()` refreshed the dev button **before** `update_colonization_preview()` set `_colonization_preview_system_def`, causing transient hide on selection.

**Fix status (static):** Visibility/disabled split implemented in `galaxy_map_hud.gd` (`_refresh_dev_instant_colonize_button`, `_apply_dev_instant_colonize_button_state`).

### Current visible/disabled rule (after fix)

| State | Rule |
|-------|------|
| **visible** | `OS.is_debug_build()` ∧ `DEV_GALAXY_INSTANT_COLONIZE_ENABLED` ∧ `selected_system_id != ""` ∧ `selected_system_id != GameSession.current_system_id` |
| **disabled** | `not GameSession.can_dev_instant_colonize_system(selected_system_id)` |
| **enabled text** | `DEV: Colonize Selected System` |
| **disabled text** | `DEV: Colonize Blocked` |

| Check | Expected | Result | Notes |
|-------|----------|--------|-------|
| `DevInstantColonizeButton` in scene | ActionSection child | **PASS** | `galaxy_map_hud.tscn` L279–286 |
| Default `visible = false` | Scene default | **PASS** | L280 |
| NodePath in script | Matches scene | **PASS** | `$GalaxyInfoPanel/Margin/Root/ActionSection/DevInstantColonizeButton`; `_ready()` warns if null |
| Debug-only visibility gate | `OS.is_debug_build()` + flag | **PASS** | `DEV_GALAXY_INSTANT_COLONIZE_ENABLED := true` |
| Foreign system → visible | Even when blocked | **PASS** (static) | No `access_state` hide; Editor **NOT TESTED** |
| Blocked → disabled not hidden | Disabled + blocked text | **PASS** (static) | |
| Signal `dev_colonize_selected_system_requested` | Typed `system_id` | **PASS** | `galaxy_map_hud.gd` L14 |
| `GalaxyMap` handler | Calls GameSession dev API | **PASS** | `galaxy_map.gd` L252–260; `push_warning` on failure |
| Real operation path | start → complete | **PASS** | `dev_instant_colonize_system()` L835–857 |
| No direct `establish_base_at_body()` bypass | Only via `complete_colonization_operation()` | **PASS** | `complete_colonization_operation()` L638 calls `establish_base_at_body()` |
| Dev ColonyShip grant | `bases.add_colony_ship` + emit | **PASS** | L848–851; comment marks DEV ONLY |
| Release gameplay unaffected | `OS.is_debug_build()` guard | **PASS** | `can_dev_*` + `dev_instant_*` return false in non-debug |
| Save schema unchanged | No dev fields persisted | **PASS** | Dev API only mutates existing runtime stores |
| Debug logging not per-frame | Once per selection when blocked | **PASS** | `_log_dev_instant_colonize_blocked_once()` + `_dev_instant_colonize_debug_logged_system_id` |
| `tooltip_text` | 0 | **PASS** | No `tooltip_text` in `galaxy_map_hud.tscn` |

---

## C) New Colony System Initialization Audit

**Static verdict:** **PASS WITH NOTES**

| Check | Expected | Result | Notes |
|-------|----------|--------|-------|
| `establish_base_at_body()` post-steps | Startkit + discovery init | **PASS** | `game_session.gd` L414–416 |
| `BaseStore.apply_start_kit_to_base()` | Replaces base with kit | **PASS** | `base_store.gd` L750–772 via `create_new_game_base_entry()` |
| Startkit source | `_resolve_v01_start_kit(false)` | **PASS** | Excludes colony ships (`colony_ships: 0`) |
| 1 ScanDrone | `start_drones = 1` | **PASS** | `default_start.tres` L15; balance fallback `scan_drone_start_count = 1` |
| 1 MiningShip | `start_mining_ships = 1` | **PASS** | `default_start.tres` L16 |
| 2 SurveyProbes | `start_survey_probes = 2` | **PASS** | `default_start.tres` L18 |
| 0 ColonyShips | Kit passes `0` | **PASS** | `_apply_colony_base_start_kit()` L1009 |
| 100 Iron | Balance `start_iron = 100` | **PASS** | `game_balance_definition.gd` L22; loaded via `build_start_resources_dictionary()` when `start_resources` empty |
| Storage 1000 | `start_storage_capacity = 1000` | **PASS** | `default_start.tres` L19 |
| Population 1 | `start_population = 1` | **PASS** | `default_start.tres` L14 |
| Upgrades Level 0 | Fresh base entry | **PASS** | `_create_empty_base()` sets all upgrade levels to 0 |
| `reset_for_new_game()` same kit source | `_resolve_v01_start_kit(true)` | **PASS** | Consistent with colony kit (colony ships only on primary start) |
| Discovery: Star KNOWN | On colony establish | **PASS** | `_initialize_colony_system_discovery()` L1030 |
| Discovery: colony body KNOWN | `proxima_b` etc. | **PASS** | L1031 |
| 2 signals SIGNAL | `COLONY_SYSTEM_START_SIGNAL_COUNT = 2` | **PASS** | L33, L1033–1060; remaining candidates → HIDDEN |
| Non-signal bodies HIDDEN | Not all KNOWN | **PASS** | Explicit `DISCOVERY_HIDDEN` when signal budget exhausted L1057 |
| Legacy KNOWN fallback avoided after init | Explicit states written | **PASS** | `_initialize_colony_system_discovery` writes all non-colony bodies |
| `SystemScene._resolve_start_body_id()` prefers established base | In current system | **PASS** | `system_scene.gd` L305–309 before `start_body_id` |
| Save/Load no startkit duplication | Kit only on establish | **PASS** | `apply_save_data()` restores bases dict; no re-call of `_apply_colony_base_start_kit` on load |
| Proxima mineable after colonization | Scan + mine on signal bodies | **FAIL (data)** | **All Proxima `.tres` bodies lack `scan_resources`** — investigate/scan may work, mining blocked |

---

## D) Lighting / Visual Consistency Audit

**Static verdict:** **PASS WITH NOTES** — architecture is system-wide; live Proxima parity unverified.

**No lighting changes made in this audit.**

### Where Solar look is defined today

| Layer | Location | Solar-specific? |
|-------|----------|-----------------|
| Default lighting profile | `data/visuals/default_system_lighting.tres` | **No** — shared default |
| Per-system override hook | `SystemDefinition.lighting_definition` | Optional; **both** `solar_system.tres` and `proxima_system.tres` leave it **null** → default |
| Runtime application | `system_scene.gd` `_apply_system_visuals()` | Loads `get_resolved_lighting_definition()` per active system |
| Controller | `SystemLightController` on `system_scene.tscn` | Generic; `star_node_path = WorldRoot/StarRoot` |
| Planet shader | `shaders/visual/planet_sprite_lit_2d.gdshader` | Applied to `system_planets` group |
| Light direction | `_update_light_directions()` | **Dynamic** from star sprite `global_position` — not hardcoded Solar coords |
| Star PointLight2D | Created at runtime on star sprite | Energy/color/radius from `SystemLightingDefinition` |

### Scene wiring notes

- `system_scene.tscn` exports **`solar_system.tres` as Inspector default** (L48) — bootstrap/fallback only; runtime uses `GameSession.consume_selected_system_definition()` / `current_system_definition` (`system_scene.gd` L259–271).
- `SystemLightController` export defaults mirror `default_system_lighting.tres` values (ambient, star light, planet tints).
- **Not** tied to Solar node names beyond generic `WorldRoot/StarRoot` + spawner `star_visual`.

| Check | Solar Result | Proxima Result | Risk | Notes |
|-------|--------------|----------------|------|-------|
| Lighting definition resolved | **PASS** (default) | **PASS** (default) | Low | Same `default_system_lighting.tres` |
| Applied on system entry | **PASS** (static) | **PASS** (static) | Med | `_apply_system_visuals()` deferred after spawn |
| Star real PointLight2D | **PASS** (static) | **PASS** (static) | Low | Star texture differs; light still attaches to spawned star |
| Planet lit shader | **PASS** (static) | **PASS** (static) | Low | All `SystemBody` join `system_planets` |
| Per-body lighting override | N/A (none set) | N/A | Low | `planet_lighting` optional on `SystemBodyDefinition` |
| Visual parity with Solar | **NOT TESTED** | **NOT TESTED** | **Med–High** | Smaller Proxima star (`star_visual_radius = 31.5` vs Solar `220`) may look dimmer/different — not a code bug, visual tuning |
| Yellow over-tint risk | **NOT TESTED** | **NOT TESTED** | Med | Default `light_tint` warm; same for all systems |
| Per-system lighting data exists | **Partial** | **Partial** | Low | `SystemLightingDefinition` + optional per-system override **exist**; only default populated |

**Lighting overall:** Not Solar-only in code — **system-wide default with optional override**. Previous report “only Solar works” is **not confirmed statically**; likely needs **live Proxima visual smoke test**.

---

## E) Data-Driven System Consistency

| System | `start_body_id` | `colonization_start_body_id` | Startkit via Base? | Discovery defaults ok? | Mineable resources ok? | Lighting ok? | Notes |
|--------|-----------------|------------------------------|--------------------|------------------------|--------------------------|--------------|-------|
| **solar-system** | `earth` | `earth` | N/A (home) | **PASS** | **PASS** | **PASS** (static) | Full body data with `scan_resources` on Earth etc. |
| **proxima** | `proxima_b` | `proxima_b` | **PASS** (runtime) | **PASS** (runtime init) | **FAIL** | **PASS** (static) | 3 bodies, **zero `scan_resources`** on all `.tres` files |

### Proxima body detail

| Body | `can_build_base` (default true) | `scan_resources` | `default_discovery_state` |
|------|--------------------------------|------------------|----------------------------|
| `proxima_b` | true | **none** | empty (runtime colony init sets KNOWN) |
| `proxima_c` | true | **none** | empty (signal candidate) |
| `proxima_d` | true | **none** | empty (signal candidate) |

### Solar-specific logic check

| Check | Result | Notes |
|-------|--------|-------|
| Only `START_SYSTEM_ID` bootstrap special-casing | **PASS** | Home enter, progression seed; no Proxima-specific code branches found |
| `preferred_colonization_source_base_id = earth` | **PASS** | `default_start.tres` L20 — data, not hardcoded logic |
| ColonyShip production cost | **PASS** (unchanged) | `colony_ship.tres`: Water 350, Iron 1500, etc. |

---

## F) Manual SmokeTest Checklist

**All items: NOT TESTED** (no Editor session in this audit).

### 1. Debug Button

- [ ] **NOT TESTED** — Galaxy Map öffnen
- [ ] **NOT TESTED** — Proxima auswählen → Dev Button sichtbar
- [ ] **NOT TESTED** — Dev Button disabled wenn blockiert (`DEV: Colonize Blocked`)
- [ ] **NOT TESTED** — Klick kolonisiert Proxima instant
- [ ] **NOT TESTED** — Kein Body-Spoiler (keine Body-Liste)

### 2. Proxima Init

- [ ] **NOT TESTED** — Proxima betreten
- [ ] **NOT TESTED** — Base auf `proxima_b`
- [ ] **NOT TESTED** — 1 ScanDrone / 1 MiningShip / 2 SurveyProbes
- [ ] **NOT TESTED** — 100 Iron / Storage 1000
- [ ] **NOT TESTED** — Star + Base sichtbar
- [ ] **NOT TESTED** — 2 Signale sichtbar
- [ ] **NOT TESTED** — Nicht alle Bodies sichtbar
- [ ] **NOT TESTED** — Investigate möglich
- [ ] **NOT TESTED** — Scan möglich
- [ ] **NOT TESTED** — Mining möglich (static data suggests **blocked** until `scan_resources` added)

### 3. Save/Load

- [ ] **NOT TESTED** — In Proxima speichern / laden
- [ ] **NOT TESTED** — Keine doppelten Units/Ressourcen
- [ ] **NOT TESTED** — Discovery-Gating bleibt

### 4. Lighting

- [ ] **NOT TESTED** — Solar-System: Stern leuchtet, Planeten Licht/Schatten
- [ ] **NOT TESTED** — Proxima: gleicher Default-Look
- [ ] **NOT TESTED** — Keine gelbe Überfärbung

---

## G) Risks

| Risk | Severity | Evidence | Suggested next step |
|------|----------|----------|-------------------|
| Dev button hidden/disabled unexpectedly | **Low** (mitigated) | Prior bug: visibility = `can_dev`; fixed statically | Editor retest Proxima selection |
| Debug path leaks into release | **Low** | `OS.is_debug_build()` on all dev entry points | Verify release export build once |
| Startkit duplicated on save/load | **Low** | Kit only in `establish_base_at_body()` | Save/load smoke test |
| **Proxima has no mineable resources** | **High** | `proxima_*.tres` — no `scan_resources` | Add basic/deep scan entries to signal bodies |
| All objects visible (discovery fallback) | **Med** | `get_object_discovery_state()` returns KNOWN if unset — mitigated by `_initialize_colony_system_discovery` | Live verify post-colony; pre-colony enter blocked |
| **Lighting only Solar-specific (perception)** | **Med** | User report; static code is system-wide default | Live Proxima lighting smoke test |
| SystemScene focus wrong body | **Low** | `_resolve_start_body_id()` prefers established base | Verify camera on `proxima_b` after colony |
| Colonization gate too strict / access_state | **Low** | Normal gate requires ship; dev grants ship | N/A for dev; normal flow unchanged |
| UI body spoilers elsewhere | **Low** | Galaxy HUD shows system name only; SystemView colonize hidden | Spot-check ObjectInfo after signal investigate |
| Pending op reveals `target_body_id` in intel | **Low** | `galaxy_map_hud.gd` colonization intel | Accept v0.1 or defer obfuscation |
| `core_loop_balance` prior FAIL on Proxima init | **Med** (historical) | Recheck doc cited post-colony init bug | Re-run live expansion after current code |

---

## H) Recommendation

**Nächster Schritt (genau einer):** **Proxima Expansion SmokeTest live dokumentieren und Proxima-Body-`scan_resources` ergänzen.**

**Begründung:** Dev-Button, fixed colonization target und New-Colony-Runtime-Pfad sind statisch **PASS**. Lighting ist architektonisch systemweit (**PASS WITH NOTES**), aber unverifiziert. Der kritischste **statische FAIL** ist fehlende Mine-Daten auf allen Proxima-Bodies — ohne diese Daten scheitert der Core Loop (Scan → Mine) in Proxima unabhängig von Dev-Tools oder Lighting.

---

## Files Reviewed (static)

- `resources/definitions/system_definition.gd`
- `resources/definitions/system_lighting_definition.gd`
- `data/galaxy_systems/solar_system.tres`
- `data/galaxy_systems/proxima_system.tres`
- `data/visuals/default_system_lighting.tres`
- `data/game_start/default_start.tres`
- `data/production/colony_ship.tres`
- `data/celestial_bodies/proxima_system/*.tres`
- `data/celestial_bodies/solar_system/earth.tres` (reference)
- `scripts/autoload/game_session.gd`
- `scripts/autoload/stores/base_store.gd`
- `scripts/system/system_scene.gd`
- `scripts/system/controller/system_discovery_controller.gd`
- `scripts/system/controller/system_ui_controller.gd`
- `scripts/galaxy/galaxy_map.gd`
- `scripts/ui/galaxy/galaxy_map_hud.gd`
- `scripts/visual/system_light_controller.gd`
- `scenes/ui/galaxy/galaxy_map_hud.tscn`
- `scenes/system/system_scene.tscn`
- `docs/audits/core_loop_balance_colony_water_recheck_v0_1.md`
