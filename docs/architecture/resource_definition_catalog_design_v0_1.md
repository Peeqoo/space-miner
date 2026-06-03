# ResourceDefinition Catalog Design v0.1

**Status:** Design only — no implementation in this phase.  
**Engine:** Godot 4.6.1 / GDScript (strict typing in future code).  
**Related:** Full Project Cleanup Audit (Phase 3 architecture); Phase 3.2 Audio Path Table (done); Phase 3 Mining Loop Proof (PASS).

---

## Purpose

Space Miner v0.1 already uses stable **resource IDs** (`StringName` / `String` keys) across stores, `.tres` costs, deposits, and UI. Display text is duplicated or derived ad hoc (`capitalize()`, `ProductionDefinition.format_resource_title()`, raw ID strings in `ScanInfoBuilder`).

A **ResourceDefinition Catalog** centralizes **UI metadata and classification** for known resource IDs:

- `display_name`, `short_label`, `icon`, optional `color` / `category` / `description`
- `sort_order` for consistent panel ordering
- Flags: `is_storable`, `is_deposit_resource`, `is_abstract_currency`
- Visibility hints: `show_in_top_hud`, `show_in_storage_panel` (future)

The catalog is **not**:

- A source for **amounts** (base storage, deposits, costs, rewards).
- A replacement for **ObjectScanStore** / **BaseStore**.
- A replacement for **`data/planet_resources/*.tres`** (`ScannedResourceEntry` deposit definitions).
- A way to redefine **SurveyData** as a planet deposit.

Gameplay, economy math, save keys, and affordability checks stay in existing systems. The catalog only answers: *“How should this ID look and how should we classify it in UI?”*

---

## Current Resource Sources

| Bereich | Aktuelle Quelle | Beispiele | Darf geändert werden? | Bemerkung |
|--------|------------------|-----------|------------------------|-----------|
| **Base resources (amounts)** | `BaseStore.bases[base_id].resources` | `"Iron": 100`, `"SurveyData": 5` | Nein (Semantik) | Mengen + Storage-Capacity-Logik; Save serialisiert Dictionary-Keys |
| **remaining_resources** | `ObjectScanStore.remaining_resources_by_object` | `system → object → resource_id → int` | Nein (Semantik) | Initialisiert aus Body-`ScannedResourceEntry` + `ensure_object_resources_initialized` |
| **Production costs** | `ProductionDefinition.cost` in `data/production/*.tres` | `mining_ship.tres`: `Iron`, `Silicon` | Nein (Semantik) | Nur Anzeige später über Catalog |
| **Upgrade costs** | `UpgradeDefinition.cost` in `data/upgrades/**/*.tres` | `storage_1_upgrade.tres`: `Copper`, `Iron` | Nein (Semantik) | Wie Production |
| **SurveyData rewards/costs** | `GameBalanceDefinition` + `v0_1_balance.tres` | `RESOURCE_SURVEY_DATA`, `base_sensor_pulse_cost`, scan rewards, `colony_ship_build_cost` | Nein (Werte) | ID-Konstante `&"SurveyData"`; Startwert `start_survey_data` |
| **Planet resource deposits** | `ScannedResourceEntry` in `data/planet_resources/*.tres` + Body-`.tres` refs | `iron.tres` → `resource_id = &"Iron"`; Bodies referenzieren ExtResources | Nein (Semantik) | `richness_percent`, `deposit_amount`, `layer`, `extraction_difficulty` bleiben hier |
| **UI display names (storage)** | `StoragePanel` | `rid.capitalize()` + `NumberFormat.format_compact` | Ja (nur Anzeige, später) | Kein zentraler Name; `SurveyData` → awkward capitalize |
| **UI display names (object resources)** | `ScanInfoBuilder` + `ObjectInfoPanel` | `display_text` uses raw `String(resource_id)`; row title via `_format_title(id)` | Ja (nur Anzeige, später) | Gleiche Title-Case-Heuristik wie Production/Upgrade |
| **TopHUD labels** | `TopHUD` scene prefixes + counts | Storage `used/cap`, Scan Drone / Mining Ship / Colony / Survey Probe / Jobs | Teilweise (Icons später) | Zeigt **keine** einzelnen Ressourcenmengen, nur Storage gesamt + Unit-Counts |
| **Production/Upgrade cost display** | `ProductionDefinition.format_cost_lines_with_availability`, `UpgradeDefinition.format_resource_cost_lines` | `"Iron: 40 / 90"` via `format_resource_title` | Ja (nur Anzeige, später) | Affordability nutzt `Dictionary`-Keys, nicht Titel |
| **Gate / blocked text** | `GateUiTextDefinition` / `gate_ui_texts.tres` | `"Ice source not discovered"` | Nein in Catalog-Phase | Copy ist gate-spezifisch, nicht resource metadata |
| **Number formatting** | `NumberFormat.format_compact` | `1.2K`, `40` | Nein | Bleibt für alle Mengen |

### Deposit catalog vs base resources (IDs in repo today)

**`data/planet_resources/*.tres`** (16 files, `ScannedResourceEntry`):  
`Iron`, `Silicon`, `Copper`, `Carbon`, `Nickel`, `Water`, `Helium`, `Calcium`, `Aluminium`, `Sodium`, `Potassium`, `Hydrogen`, `Methane`, `Cobalt`, `Magnesium`, `Oxygen`.

**Used in costs / balance but no matching `planet_resources/*.tres` today:**

- **`Ice`** — `GameBalanceDefinition.RESOURCE_ICE`, `colony_ship` cost, `colony_ship_ice_resource_ids` includes `"Ice"` and `"Water"` (Water deposit proxies ice discovery).
- **`SurveyData`** — abstract base currency; rewards in balance; **must not** become a deposit `.tres` in v0.1.

Bodies may reference deposit IDs not yet in the v0.1 “core six” list (e.g. `Aluminium` on `moon.tres`); the catalog can grow incrementally without changing deposit math.

---

## Important Rule: Amounts stay where they are

| Concern | Owner (unchanged) |
|--------|-------------------|
| Base warehouse amounts | `BaseStore` → `bases[*].resources` |
| Per-object deposit remaining | `ObjectScanStore.remaining_resources_by_object` |
| Build/upgrade price tables | `ProductionDefinition.cost`, `UpgradeDefinition.cost` |
| Start resources, rewards, pulse cost, colony cost | `GameBalanceDefinition` / `data/balance/v0_1_balance.tres` |
| Deposit size, layer, mining tier | `ScannedResourceEntry` + body scan resource arrays |
| Affordability / can-build | `GameSession` / `BaseStore` (compares amounts to cost dict keys) |
| Mining target / depletion | `AutomationController`, `ObjectScanStore`, `GameSession` |

**ResourceDefinition Catalog** supplies only: labels, icons, sort order, and boolean classification for UI and tooling.

---

## SurveyData Rule

1. **SurveyData** remains a **base / intel currency** stored like other base resources under key `"SurveyData"` (`GameBalanceDefinition.RESOURCE_SURVEY_DATA`).
2. The catalog **may** define UI metadata for SurveyData (`display_name`, `short_label`, icon, flags).
3. **Do not** create `data/planet_resources/survey_data.tres` or any deposit entry that treats SurveyData as a mineable planet resource in v0.1.
4. If SurveyData appears in the catalog:
   - `is_abstract_currency = true`
   - `is_deposit_resource = false`
   - `is_storable = true` (it occupies base storage and pulse/build costs)
5. POI / survey-probe rewards stay numeric in **GameBalance**; the catalog does not define reward amounts.

---

## Proposed File Structure

### Option A (recommended for v0.1 — mirrors Audio Path Table)

```
resources/definitions/resource_definition.gd          # class_name ResourceDefinition
resources/definitions/resource_catalog_definition.gd # class_name ResourceCatalogDefinition
data/resources/resource_catalog.tres                # one catalog, Array[ResourceDefinition] or id→def map
```

**Pros:** Single editor asset; easy diff; one load in `GameSession` or a small autoload; matches `data/audio/audio_event_table.tres` pattern.  
**Cons:** Large `.tres` when many deposit IDs are added.

### Option B (per-resource files)

```
resources/definitions/resource_definition.gd
data/resource_definitions/iron.tres
data/resource_definitions/survey_data.tres
...
data/resources/catalog.tres   # aggregates references
```

**Pros:** Per-resource art/metadata in isolation.  
**Cons:** More files, aggregation step, easier to orphan IDs.

**Recommendation:** **Option A** for first implementation; split to Option B only if the catalog exceeds comfortable editor size (~30+ entries with icons).

**Explicitly do not create in Phase 3.3 implementation prompt:** `data/planet_resources/survey_data.tres`.

---

## ResourceDefinition Fields

Proposed type (design only):

```gdscript
class_name ResourceDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var short_label: String
@export var description: String = ""
@export var icon: Texture2D
@export var sort_order: int = 0
@export var category: StringName = &""
@export var is_storable: bool = true
@export var is_deposit_resource: bool = true
@export var is_abstract_currency: bool = false
@export var show_in_top_hud: bool = false
@export var show_in_storage_panel: bool = true
```

### Field evaluation (v0.1)

| Field | v0.1? | Notes |
|-------|-------|-------|
| `id` | **Yes** | Must match cost/deposit/save keys exactly |
| `display_name` | **Yes** | Primary UI string |
| `short_label` | **Yes** | Compact HOVER / tight rows; collision risk (see Open Questions) |
| `description` | Defer | No resource tooltip policy; use panel copy elsewhere |
| `icon` | Optional Step 5 | Ship without icons first (null icon = text only) |
| `sort_order` | **Yes** | StoragePanel currently sorts keys alphabetically |
| `category` | Defer | e.g. `&"metal"`, `&"gas"` — no filter UI in v0.1 |
| `color` | Defer | Theme-driven UI sufficient for v0.1 |
| `rarity` | Defer | Gameplay not rarity-based |
| `compact display override` | **No** | `NumberFormat` owns numeric compaction |
| `is_storable` | **Yes** | Documents intent; future hide non-storable rows |
| `is_deposit_resource` | **Yes** | Distinguishes Iron vs SurveyData vs Ice-in-base-only |
| `is_abstract_currency` | **Yes** | SurveyData |
| `show_in_top_hud` | Defer false | TopHUD does not list per-resource today |
| `show_in_storage_panel` | **Yes** | Can hide internal IDs later if needed |

---

## ResourceCatalogDefinition Fields

```gdscript
class_name ResourceCatalogDefinition
extends Resource

@export var resources: Array[ResourceDefinition] = []
```

**Future helpers (not implemented in design phase):**

- `get_resource(id: StringName) -> ResourceDefinition`
- `get_display_name(id: StringName) -> String` — fallback: `id` title-case or raw ID
- `get_short_label(id: StringName) -> String`
- `get_icon(id: StringName) -> Texture2D`
- `get_sort_order(id: StringName) -> int`
- `get_resource_ids_for_storage() -> Array[StringName]` — storable + show_in_storage_panel

**Risks:** Helpers must not load amounts, must not mutate stores, must tolerate unknown IDs (return fallback, no crash).

---

## Initial v0.1 Resource List

Core economy / UI resources referenced in balance, production, upgrades, and base storage. Deposit-only IDs from `planet_resources` can be added in a follow-up catalog pass without gameplay changes.

| id | display_name | short_label | category | is_storable | is_deposit_resource | is_abstract_currency | show_in_top_hud | show_in_storage_panel | notes |
|----|--------------|-------------|----------|-------------|---------------------|----------------------|-----------------|----------------------|-------|
| `Iron` | Iron | Fe / Iron | `&"metal"` | true | true | false | false | true | Start + most build costs; `iron.tres` deposit |
| `Silicon` | Silicon | Si | `&"metal"` | true | true | false | false | true | `silicon.tres`; mining_ship / colony costs |
| `Copper` | Copper | Cu | `&"metal"` | true | true | false | false | true | Upgrades; `copper.tres` |
| `Carbon` | Carbon | C | `&"element"` | true | true | false | false | true | `carbon.tres`; gas giant deposits |
| `Ice` | Ice | Ice | `&"volatiles"` | true | **false** | false | false | true | **No** `data/planet_resources/ice.tres` today; colony cost + balance; discovery via `Water` deposit per `colony_ship_ice_resource_ids` |
| `SurveyData` | Survey Data | Surv / SD* | `&"science"` | true | **false** | **true** | false | true | Pulse cost, scan rewards, colony cost; **never** a deposit `.tres` in v0.1 |

\*See Open Questions — `SD` may collide with Scan Drone abbreviations in HUD/scene copy.

**Suggested `sort_order` (storage panel):** SurveyData (0), Iron (10), Silicon (20), Copper (30), Carbon (40), Ice (50) — science/currency first, then metals; tune in data only.

**Not in initial six but already in deposits (catalog expansion later, same IDs):**  
`Water`, `Hydrogen`, `Helium`, `Methane`, `Oxygen`, `Nickel`, `Cobalt`, `Aluminium`, `Magnesium`, `Calcium`, `Sodium`, `Potassium` — each `is_deposit_resource = true`, `is_abstract_currency = false`, display names title-cased from ID until authored.

---

## What would use the Catalog later?

| File | Current behavior | Future behavior | Risk |
|------|------------------|-----------------|------|
| `storage_panel.gd` | `GameSession.get_base_resources`; label `"%s: %s" % [rid.capitalize(), amount]` | `get_display_name(rid)` + `NumberFormat` | **Low** — display only |
| `object_info_panel.gd` | Title from `_format_title(resource_id)`; amounts from `GameSession` / cache | Row title from catalog; amounts unchanged | **Low–Medium** — keep `resource_id` for store lookups |
| `scan_info_builder.gd` | `display_text` embeds raw `String(resource_id)` | Optional catalog name in `display_text` | **Medium** — info dict contract |
| `production_panel.gd` | `ProductionDefinition.format_cost_lines_with_availability` | Replace `format_resource_title` with catalog lookup | **Low** |
| `upgrade_panel.gd` | `UpgradeDefinition.format_resource_cost_lines` / hover builders | Same | **Low** |
| `production_definition.gd` / `upgrade_definition.gd` | Static `format_resource_title` | Deprecated or thin wrapper → catalog | **Low** if fallback kept |
| `base_sensor_pulse_controller.gd` | Cost summary `"%d %s" % [amount, str(resource_id)]` | Catalog display names | **Low** |
| `top_hud.gd` | Storage aggregate only; unit widgets unrelated to resource IDs | Optional per-resource strip later | **Medium** if layout changes |
| `top_hud_hover_panel.gd` | Unit/storage hover copy from templates | Unchanged unless new resource strip | **Low** |
| `game_session.gd` | `add_base_resource`, gates, rewards | Optional `get_resource_display_name(id)` facade | **Low** if read-only |
| `gate_ui_texts.tres` | Human gate strings | Unchanged | **None** |

**NumberFormat** remains responsible for all numeric compaction and parsing; the catalog must not duplicate it.

---

## What must NOT use the Catalog

- `remaining_resources` calculations (`ObjectScanStore.take_remaining`, depletion, init from deposits)
- `BaseStore` amount math (`add_resource`, capacity, discard)
- Production / upgrade **affordability** (compares cost dict to `resources` dict)
- Mining target selection, cargo `resource_id`, automation weights (`AutomationController`)
- Save serialization keys in `SaveManager` / `build_save_data` (resource dict keys must stay stable)
- `ObjectScanStore` initialization semantics (`ensure_object_resources_initialized`, `deposit_amount`)
- `GameBalanceDefinition` reward values and cost dictionaries
- `ScannedResourceEntry` fields (`richness_percent`, `layer`, `extraction_difficulty`)
- Changing existing resource ID strings in saves, `.tres` costs, or body deposits

---

## Migration Strategy

Small steps; each step = one testable commit; no gameplay behavior change until explicitly noted.

### Step 1 — Skeleton (data only)

- Add `ResourceDefinition`, `ResourceCatalogDefinition`, `data/resources/resource_catalog.tres` with the **core six** entries (text only, icons null).
- **No call-site changes.**
- **Test:** Project opens; no parse errors; catalog loads in editor.

### Step 2 — Read facade

- Add read-only resolver on `GameSession` (or dedicated autoload), e.g. `get_resource_display_name(id: StringName) -> String`.
- Fallback chain: catalog → `ProductionDefinition.format_resource_title` equivalent → `String(id)`.
- **No UI changes yet.**
- **Test:** Debugger/unit call returns names for `Iron`, `SurveyData`; unknown ID does not crash.

### Step 3 — Storage + Object Info labels

- `StoragePanel`: replace `rid.capitalize()` with resolver.
- `ObjectInfoPanel` / optionally `ScanInfoBuilder` `display_text`: catalog name for title portion; **amounts still from GameSession / entry dict**.
- **Test:** Storage rows and object resource rows show proper names; discard and depletion unchanged.

### Step 4 — Production + Upgrade cost display

- Wire `format_cost_lines_*` to catalog for the resource name segment only.
- **Test:** Build hover shows same numbers; blocked build still works; `not_enough_resources` SFX unchanged.

### Step 5 — Optional polish

- Icons in storage rows; `sort_order` instead of alphabetical sort; TopHUD resource strip only if designed.
- **Test:** Visual pass; save/load resource amounts identical.

---

## Risk Matrix

| Level | Topic | Mitigation |
|-------|--------|------------|
| **Low** | UI display names only | Fallback when catalog missing; never block gameplay |
| **Medium** | Icons / sort order in panels | Null icon safe; sort fallback to alphabetical |
| **High** | Renaming resource IDs or moving amounts into catalog | **Forbidden** in v0.1; IDs are save/cost contract |
| **Critical** | New `survey_data.tres` deposit or changing `SurveyData` key | Explicit rule + code review; no planet_resources entry |
| **Critical** | Catalog drives affordability or mining yields | Keep cost/deposit sources separate; document in PR template |

---

## Open Questions

1. **SurveyData in StoragePanel** — Stay visible (recommended: yes, `show_in_storage_panel = true`) so players see pulse currency?
2. **Short label collision** — `SD` for Survey Data vs Scan Drone prefixes in TopHUD (`_scan_drone_prefix` from scene). Prefer `Surv`, `Svy`, or full “Survey” in compact UI?
3. **Icons timing** — Ship text-only catalog first, or block until `assets/ui/resources/` icon set exists?
4. **TopHUD scope** — Keep aggregate storage only, or add optional resource chips for Iron/SurveyData later?
5. **Resource categories** — Needed for filter/sort in v0.2, or YAGNI until colony/trade UI exists?
6. **Deposit-only IDs** — Add all 16 `planet_resources` IDs to catalog in Step 1 or Step 3b when Object Info shows them with raw IDs?
7. **Ice deposit** — If `ice.tres` is added later, update catalog `is_deposit_resource` only; do not conflate with SurveyData rules.

---

## Do Not Touch (implementation phases 3.3+)

- `BaseStore` resource dictionaries and capacity logic
- `ObjectScanStore.remaining_resources_by_object` structure and APIs
- `GameSession` resource amount APIs and `RESOURCE_SURVEY_DATA` constant semantics
- `data/planet_resources/*.tres` semantics and body references
- `ProductionDefinition.cost` / `UpgradeDefinition.cost` dictionaries
- `GameBalanceDefinition` numeric rewards and `build_start_resources_dictionary`
- Save/Load JSON shape for `resources`
- `NumberFormat`
- Mining extraction, unload, automation mission state machines
- Gate UI text resources (`gate_ui_texts.tres`)
- `tooltip_text` (project policy: **0**)

---

## Recommended First Implementation Prompt

Use this verbatim for the next coding task (Phase 3.3 implementation — **not** part of this document PR):

> Implement Phase 3.3 skeleton only: add `resources/definitions/resource_definition.gd` (`class_name ResourceDefinition`), `resources/definitions/resource_catalog_definition.gd` (`class_name ResourceCatalogDefinition` with `resources: Array[ResourceDefinition]` and typed lookup helpers with safe fallbacks), and `data/resources/resource_catalog.tres` containing UI metadata for **Iron, Silicon, Copper, Carbon, Ice, SurveyData** exactly matching save/cost IDs. SurveyData: `is_abstract_currency = true`, `is_deposit_resource = false`. Do **not** create `data/planet_resources/survey_data.tres`. Do **not** change any call sites, gameplay, stores, save/load, or UI panels. Godot 4.6.1, strictly typed GDScript. Verify project loads in editor with no parser errors.

---

## Acceptance (this document only)

1. Only `docs/architecture/resource_definition_catalog_design_v0_1.md` was created (plus `docs/architecture/` folder if missing).
2. No code, `.tscn`, or `.tres` changes.
3. Document separates amounts, deposits, UI metadata, and SurveyData currency rules.
4. Step-by-step migration and risk matrix included.
5. Explicit: no `data/planet_resources/survey_data.tres`.
6. Exactly one small follow-up implementation prompt provided above.
