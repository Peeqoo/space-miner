# Colony / Colonization Text Audit v0.1

**Audit date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Method:** Static read-only search + targeted file reads (no Godot run, no edits outside this report)

**Scope:** Visible colony/colonization player strings, gate/block reasons, scene defaults, data resources, naming leftovers. **Excluded:** gameplay/logic refactors, automation units, save format changes, timer implementation.

---

## Summary

- **Gesamtstatus:** **PASS WITH NOTES**
- **Größte Text-/Key-Probleme:**
  1. **`GateUiTextDefinition` `colony_*` keys sind vorbereitet, aber nirgends angebunden** — echte Gates nutzen `BaseStore.COLONY_BLOCK_*` und `get_build_base_colony_ship_gate()` ohne `blocked_reason_key`.
  2. **Doppelte / leicht abweichende Texte** für „No Colony Ship“ (Gate-Fallback ohne Punkt vs. ObjectInfo-Template mit Punkt) und „Not enough resources“ (shared mit Build-Gates).
  3. **Prerequisite-Labels vs. Blockgründe** — fünf spezifische `blocked_reason`-Strings + fünf kürzere `label`-Strings in `game_session.gd`; passt nicht in ein einziges generisches `colony_requirement_missing`.
  4. **`ColonizationDefinition` Script-Defaults noch Deutsch** (`Läuft %ds`, `Bereit zur Ankunft`), während `default_colonization.tres` Englisch liefert.
  5. **`ColonizationNoShipTooltipTemplate`** — irreführender Node-Name; kein Godot-`tooltip_text`.
- **Darf ein kleiner Cleanup folgen?** **Ja** — rein Text/Keys (keine Logik), risikoarm wenn `COLONY_BLOCK_*` 1:1 auf Gate-Keys gemappt werden und Scene-Templates synchronisiert werden.

**Tooltip-Check:** `tooltip_text` in `*.gd` / `*.tscn` / `*.tres` → **0 Treffer**. Kein Vorschlag, `tooltip_text` wieder zu setzen.

---

## Text Source Map

| Bereich | Aktuelle Textquelle | Sollte Zielquelle sein | Bewertung |
|---------|---------------------|------------------------|-----------|
| ColonyShip Build Button | `production_panel.tscn` → `"ColonyShip"` | Scene (Button-Caption) | OK |
| ColonyShip Production Hover (title/desc/cost) | `colony_ship.tres` + `ProductionDefinition` helpers + `production_panel.gd` Hover | Production `.tres` + Scene Hover placeholders | OK |
| ColonyShip Build Gate / Prerequisites | `BaseStore.COLONY_BLOCK_*`, `game_session.get_colony_ship_build_prerequisite_*`, Gate-Dict `blocked_reason` | **GateUiTextDefinition** für `blocked_reason`; Labels optional Colonization/Production data | OPEN — Keys exist, nicht wired |
| ObjectInfo Colonization Button | `object_info_panel.tscn` → `"Start Colonization"` / `"In progress..."` | Scene templates | OK |
| ObjectInfo Colonization Block (no ship) | `ColonizationNoShipTooltipTemplate` → `EconomyBlockLabel` | Scene template oder `KEY_COLONY_NO_SHIP` | RISK — Duplikat + Punkt |
| Galaxy Enter Status | `galaxy_map_hud.tscn` hidden templates → `galaxy_map_hud.gd` | Scene templates | OK (kein Tooltip) |
| Galaxy Colonization Preview | Scene section labels + templates + `ColonizationDefinition.format_operation_status_view` | Scene für Captions; **ColonizationDefinition** für Timer-Status | OK |
| Colonization Operation Status | `default_colonization.tres` + `ColonizationDefinition` | **ColonizationDefinition** | OK (EN in `.tres`) |
| Colonization Save/Load Status | Keine eigenen Save-UI-Strings; Status aus Ops + Preview refresh | Unverändert dokumentiert (`docs/save_behavior_v0_1.md`) | OK |
| GateUiText `colony_*` keys | `gate_ui_texts.tres` + Fallbacks in `gate_ui_text_definition.gd` | Nutzen oder entfernen | OPEN — **ungenutzt** |

---

## Gate Texts

### `COLONY_BLOCK_*` (`base_store.gd`)

| Konstante | Text | Verwendung |
|-----------|------|------------|
| `COLONY_BLOCK_NOT_ENOUGH_RESOURCES` | Not enough resources | `get_build_colony_ship_blocked_reason` (cost) |
| `COLONY_BLOCK_SHIPYARD_I` | Shipyard I required | Prerequisite row + gate |
| `COLONY_BLOCK_COLONY_PROTOCOL` | Colony Protocol required | Prerequisite row + gate |
| `COLONY_BLOCK_DEEP_SCAN_MODULE` | Deep Scan Module required | Prerequisite row + gate |
| `COLONY_BLOCK_ICE_SOURCE` | Ice source not discovered | Prerequisite row + gate |
| `COLONY_BLOCK_FULLY_SCAN_THREE` | Fully scan 3 objects | Prerequisite row + gate |

`get_build_colony_ship_blocked_reason()` gibt bei gesetztem `prerequisite_reason` diesen String **unverändert** zurück (keine Übersetzung).

### `get_build_base_colony_ship_gate()` (`game_session.gd`)

- Liefert: `ok`, `blocked_reason` (String), `prerequisites` (Array mit `label`, `met`, `blocked_reason`).
- **Kein** `blocked_reason_key` (im Gegensatz zu Scan/Mine/Build-Gates).
- Nicht migriert — bewusst in Phase 1 ausgelassen.

### `gate_ui_texts.tres` — `colony_*` keys

| Key | Text in `.tres` | Verwendung in Code |
|-----|-----------------|-------------------|
| `colony_no_ship` | No Colony Ship available | **Keine** `.gd`-Referenz außer `GateUiTextDefinition` |
| `colony_not_enough_resources` | Not enough resources | **Ungenutzt** (dupliziert `build_not_enough_resources` / `COLONY_BLOCK_*`) |
| `colony_requirement_missing` | Requirement missing | **Ungenutzt** — zu generisch für 4 spezifische Prereq-Meldungen |

**Fazit Keys:** Nicht löschbar ohne Entscheidung — entweder **anbinden** (mit zusätzlichen Keys pro Prereq) oder **aus `.tres` entfernen** nach Migration. Ein kleiner Migration-Prompt ist **sinnvoll**, aber nur mit **6+ spezifischen Keys** oder Mapping-Tabelle; ein einzelnes `colony_requirement_missing` reicht nicht.

---

## Findings

| ID | Datei | Text/Key | Art | Problem | Empfehlung | Risiko |
|----|-------|----------|-----|---------|------------|--------|
| C01 | `base_store.gd` | `COLONY_BLOCK_*` (6 strings) | Gate-/blocked_reason | Hardcoded; nicht in `GateUiTextDefinition` | In GateUiTextDefinition migrieren (1 Key pro Block-String) | Low |
| C02 | `game_session.gd` | `get_build_base_colony_ship_gate` → `blocked_reason` | Gate | Kein `blocked_reason_key` | Keys setzen wie andere Gates; Logik unverändert | Low |
| C03 | `gate_ui_texts.tres` | `colony_*` (3 keys) | UI-Text-Resource | Vorbereitet, ungenutzt | Anbinden oder nach Migration entfernen | Low |
| C04 | `gate_ui_text_definition.gd` | `KEY_COLONY_*` + Fallbacks | UI-Text-Resource | Nur Definition, keine Caller | Mit C01/C03 zusammen migrieren | Low |
| C05 | `gate_ui_texts.tres` vs `object_info_panel.tscn` | „No Colony Ship available“ vs „…available.**“** | Duplikat | Punkt-Inkonsistenz | Scene-Template an Gate-Text angleichen | Low |
| C06 | `object_info_panel.tscn` | `ColonizationNoShipTooltipTemplate` | Scene-Default | Name suggeriert Tooltip | Nur umbenennen (optional) | Low |
| C07 | `object_info_panel.gd` | `_colonization_no_ship_tooltip` | sichtbarer Spielertext | Nutzt Template, nicht Gate | Nach Migration `get_gate_text(KEY_COLONY_NO_SHIP)` oder Template beibehalten | Low |
| C08 | `object_info_panel.tscn` | `Start Colonization`, `In progress...` | Scene-Default | — | In Scene lassen | Low |
| C09 | `system_ui_controller.gd` | `_apply_colonization_info_to_dict` | Logik/Flags | Kein `colonization_blocked_reason` im Info-Dict | bleibt; Block über Economy-Label | Low |
| C10 | `production_panel.tscn` | `BuildColonyShipButton` → `ColonyShip` | Scene-Default | — | In Scene lassen | Low |
| C11 | `colony_ship.tres` | `short_description`, `effect_lines` | Production-Daten | — | In Production `.tres` lassen | Low |
| C12 | `production_panel.gd` | `"Prerequisites:"` | sichtbarer Spielertext (Hover) | Hardcoded in Code | Scene oder ColonizationDefinition | Low |
| C13 | `game_session.gd` | Prerequisite `label` fields | UI-Listen-Text | Hardcoded (5 labels) | ColonizationDefinition oder `.tres` | Medium |
| C14 | `production_panel.gd` | `_blocked_reason_for_button` Colony path | Gate-Anzeige | Liest `COLONY_BLOCK_*` via gate | Nach C01 zentral | Low |
| C15 | `default_colonization.tres` | `Running %ds`, `Ready for arrival`, `Awaiting confirmation` | Colonization-Daten | — | In ColonizationDefinition lassen | Low |
| C16 | `colonization_definition.gd` | `@export` defaults DE | Colonization-Daten | Script-Fallback DE wenn `.tres` fehlt | Script-Defaults auf EN (nur Text) | Low |
| C17 | `colonization_definition.gd` | `completed_status_label`, `cancelled_status_label` leer | Colonization-Daten | Leer → `format_operation_status_view` gibt `""` | Galaxy nutzt Fallback „Running“; optional Labels ergänzen | Low |
| C18 | `galaxy_map_hud.tscn` | AccessStatus* / Colonization* templates | Scene-Default | — | In Scene lassen | Low |
| C19 | `galaxy_map_hud.gd` | `_access_status_texts`, `_colonization_state_texts` | Runtime aus Scene | — | bleibt | Low |
| C20 | `galaxy_map_hud.tscn` | `ColonizationBlockedTemplate` = `Locked` | Scene-Default | Gleiches Wort wie Access „Locked“ | bleibt (Kontext unterschiedlich) | Low |
| C21 | `galaxy_map_hud.tscn` | `Enter System`, `Cancel Colonization` | Scene-Default | — | In Scene lassen | Low |
| C22 | `galaxy_top_bar.tscn` | Galaxy Map / Current System | Scene-Default | Kein Colony-Text | — | Low |
| C23 | `system_ui_controller.gd` | TopHUD `"ColonyShips"` | sichtbarer Spielertext | Hardcoded in Controller | Scene/Resource später | Low |
| C24 | `game_balance_definition.gd` | `colony_ship_*` | Balance (Zahlen) | Kein Spielertext | Nicht in Gate-Text ziehen | Low |
| C25 | `game_session.gd` | `get_scan_button_label_*` | Code | Nicht Colony; ungenutzt | Nicht anfassen (separates Thema) | — |

---

## Scene Texts (sollen bleiben)

### `object_info_panel.tscn`

| Node / text | Rolle |
|-------------|--------|
| `ColonizationButton` → `Start Colonization` | Button-Caption |
| `ColonizationRunningTemplate` → `In progress...` | Pending-Button-Text |
| `ColonizationNoShipTooltipTemplate` → `No Colony Ship available.` | Economy block when cannot start |
| Scan/Mine/Investigate/Pulse | Nicht Colony — unverändert |

### `production_panel.tscn`

| Node / text | Rolle |
|-------------|--------|
| `BuildColonyShipButton` → `ColonyShip` | Build button |
| `HoverInfoSection` / placeholders | Custom hover (kein Godot tooltip) |

### `galaxy_map_hud.tscn`

| Bereich | Beispiele |
|---------|-----------|
| Section chrome | `Colonization`, `Colony Status:`, `Colony Target:`, `ColonyShips:` |
| Actions | `Enter System`, `Cancel Colonization`, `DEV: Simulate Arrival` |
| Hidden templates | Access: Current/Ready/Locked/Unreachable; Colony: Established/Home/Uncolonized/Locked/Running; Intel Known/Unknown |

### `galaxy_top_bar.tscn`

Nur Navigation (`Galaxy Map`, `Current System:`) — kein Colony-Gate-Text.

---

## Data Texts (sollen dort bleiben)

### `data/production/colony_ship.tres`

- `short_description`: „Establishes new bases in other systems.“
- `effect_lines`: „Consumed during colonization“
- `build_time_seconds = 120.0` — **nicht sichtbar** in v0.1 (instant build; Kommentar in `production_panel.gd`)

### `data/colonization/default_colonization.tres`

- `pending_status_format = "Running %ds"`
- `ready_status_label = "Ready for arrival"`
- `awaiting_confirmation_status_label = "Awaiting confirmation"`
- `operation_duration_ms` — Balance/Timing, kein Label

### `resources/definitions/colonization_definition.gd`

- `format_operation_status_view()` — zentrale Formatierung für Galaxy-Preview-Status
- Script-`@export`-Defaults noch DE — **nur relevant wenn `.tres` fehlt**

### `game_balance_definition.gd` / `v0_1_balance.tres`

- Kosten, Dauer, Prereq-Schwellen (`colony_ship_min_fully_scanned_objects`, ice ids) — **Gameplay-Daten**, keine UI-Copy

---

## Tooltip / Dead Naming

| Fund | Bewertung |
|------|-----------|
| `ColonizationNoShipTooltipTemplate` (`object_info_panel.tscn`) | **Naming cleanup optional** — hidden Label, copied to `economy_block_label.text` in `_apply_colonization_controls()`. **Kein** `tooltip_text`. |
| `PROJECT_OVERVIEW.md` erwähnt „Tooltips“ für Production Hover | Doku veraltet; Implementierung = `HoverInfoSection` |
| Repo `tooltip_text` | **0** in Code/Scenes/Data |

**Fehler wäre:** jeder Code, der `Control.tooltip_text` setzt — **nicht gefunden**.

---

## Safe Cleanup Candidates

### 1. Colony build gates → `GateUiTextDefinition`

- **Ziel:** `COLONY_BLOCK_*` durch Keys ersetzen; `get_build_base_colony_ship_gate` liefert `blocked_reason_key` + `blocked_reason` via `get_gate_text()`.
- **Dateien:** `gate_ui_text_definition.gd`, `gate_ui_texts.tres`, `base_store.gd`, `game_session.gd` (nur Text-Pfade).
- **Neue Keys (Vorschlag):** `colony_not_enough_resources`, `colony_shipyard_required`, `colony_protocol_required`, `colony_deep_scan_required`, `colony_ice_source_required`, `colony_fully_scan_three` — **oder** 1:1-Mapping der bestehenden Konstanten-Strings.
- **Risiko:** Low — gleiche Strings, gleiche `ok`/Prereq-Reihenfolge.
- **AK:** Production Hover + disabled Build zeigen identische Blockgründe; `grep COLONY_BLOCK` nur noch als Key-Alias oder weg.
- **Commit:** `Centralize colony ship build gate strings in GateUiTextDefinition`

### 2. `KEY_COLONY_NO_SHIP` + ObjectInfo-Template

- **Ziel:** Ein Text für „No Colony Ship“; Punkt vereinheitlichen.
- **Dateien:** `object_info_panel.tscn`, optional `object_info_panel.gd` (read from gate or keep template synced).
- **Risiko:** Low
- **AK:** Economy block matches gate text exactly.
- **Commit:** `Align colony ship unavailable copy with gate UI text`

### 3. Ungenutztes `colony_requirement_missing` klären

- **Ziel:** Entweder entfernen oder durch spezifische Keys ersetzen (siehe Candidate 1).
- **Risiko:** Low (kein Caller)
- **Commit:** `Remove unused generic colony gate key` oder Teil von Candidate 1

### 4. `ColonizationDefinition` script defaults EN

- **Ziel:** `@export` defaults in `.gd` auf Englisch (`.tres` bleibt Source of Truth).
- **Dateien:** `colonization_definition.gd` only
- **Risiko:** Low
- **Commit:** `Use English defaults in ColonizationDefinition script`

### 5. Optional: Rename `ColonizationNoShipTooltipTemplate`

- **Ziel:** z. B. `ColonizationNoShipBlockTemplate`
- **Dateien:** `.tscn` + `@onready` path in `.gd`
- **Risiko:** Low (Editor-only rename)
- **Commit:** `Rename colony no-ship label template node`

**Nicht in diesem Cleanup:** Prerequisite-`label`-Zeilen in Hover-Liste (C13) — eigener, optionaler Daten-Schritt.

---

## Do Not Touch

- `start_colonization_operation` / `complete_colonization_operation` / `cancel_colonization_operation`
- `establish_base_at_body`
- Colonization save/load shape and cancel+refund rules
- `can_enter_system` / galaxy access state machine (`galaxy_map.gd` `ACCESS_*`)
- Production cost spending / `build_colony_ship` inventory
- Prerequisite **logic** (`has_colony_ship_*`, ice scan count, upgrade proxies)
- `colony_ships` count / `consume_colony_ships` / `add_colony_ship`
- `automation_controller`
- Survey Probe / Sensor Pulse text systems
- Build timer / queue UI

---

## Recommended Next Prompt

> Migriere nur die ColonyShip-Build-`blocked_reason`-Texte von `BaseStore.COLONY_BLOCK_*` nach `GateUiTextDefinition`: ergänze spezifische `colony_*` Keys in `gate_ui_texts.tres`, setze `blocked_reason_key` in `get_build_base_colony_ship_gate()`, lasse Prerequisite-**Logik** und `get_colony_ship_build_prerequisite_status()` unverändert, verdrahte `production_panel` weiter nur über `blocked_reason`, und gleiche `ColonizationNoShipTooltipTemplate` mit `KEY_COLONY_NO_SHIP` ab. Keine Änderung an `start_colonization_operation`, Galaxy Enter, ObjectInfo Scan-Button, oder `tooltip_text`.

---

## Akzeptanz (dieses Audits)

1. Nur `docs/audits/colony_colonization_text_audit_v0_1.md` erstellt/geändert — **erfüllt**
2. Keine Code-/Scene-/Data-Änderungen — **erfüllt**
3. `colony_*` Gate-Keys: **ungenutzt**, nicht löschbar ohne Entscheidung — **dokumentiert**
4. Colony-Texte: Gates → künftig GateUiText; Timer/Status → ColonizationDefinition; Buttons/Captions → Scene — **dokumentiert**
5. Riskante Bereiche (Prereq-Labels, can_start vs. block message, generic `colony_requirement_missing`) — **markiert**
