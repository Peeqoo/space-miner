# Unused UI Text Keys and Helpers Audit v0.1

**Audit date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Method:** Static ripgrep + targeted reads across listed definitions, scripts, scenes, and data (no Godot run, no deletions)

**Scope:** Post Phase-1/2 text cleanup — prove what is unused vs fallback-only vs intentional scene default.

---

## Summary

| Metric | Count |
|--------|------:|
| **GateUiTextDefinition** keys (excl. `KEY_NONE`) | 23 |
| **DiscoverySignalUiTextDefinition** keys | 22 |
| **upgrade_effect_texts.tres** template keys | 10 |
| **Eindeutig ungenutzt im Runtime-Code** (Gate keys) | **3** |
| **FALLBACK_ONLY / PREPARED** (Gate) | 3 |
| **Discovery keys ohne externen Caller** | **1** (`unknown_signal_type`) |
| **Dead helper candidates** | **4** (scan label pair + 2 Discovery wrappers) |
| **tooltip_text** in `*.gd` / `*.tscn` / `*.tres` | **0** |

- **Status:** **PASS WITH NOTES**
- **Darf Cleanup folgen?** **Ja** — nur kleine, nachgewiesene Kandidaten; nichts blind löschen.

---

## tooltip_text

| Pattern | Treffer |
|---------|--------|
| `tooltip_text` | **0** |
| `hint_tooltip` | **0** |
| `set_tooltip` | **0** |
| `EnterTooltip` / `_enter_tooltips` / `_apply_enter_button_tooltip` | **0** |

**Naming only:** `ColonizationNoShipTooltipTemplate` + `_colonization_no_ship_tooltip` — visible `EconomyBlockLabel` text, not Godot tooltip.

---

## GateUiTextDefinition Key Table

| Key | .tres value | Code references | Runtime use | Status | Recommendation | Risk |
|-----|-------------|-----------------|-------------|--------|----------------|------|
| `none` | *(not in .tres)* | `KEY_NONE` in gates / stores | Meta “no block” | **USED** | Behalten | Low |
| `scan_not_discovered` | Object not discovered | `can_scan_object` | Scan gate | **USED** | Behalten | Low |
| `scan_already_in_progress` | Scan already in progress | `can_scan_object` | Scan gate | **USED** | Behalten | Low |
| `scan_no_drone` | No scan drone available | `can_scan_object` | Scan gate | **USED** | Behalten | Low |
| `scan_no_layer` | No scan layer available | `_scan_blocked` → `KEY_SCAN_NO_LAYER` | Scan gate | **USED** | Behalten | Low |
| `mine_not_discovered` | Object not discovered | `can_mine_object` | Mine gate | **USED** | Behalten | Low |
| `mine_not_scanned` | Scan required | `can_mine_object` | Mine gate | **USED** | Behalten | Low |
| `mine_no_resources` | No resources available | `can_mine_object` | Mine gate | **USED** | Behalten | Low |
| `mine_depleted` | Resource depleted | `can_mine_object`, `system_ui_controller`, `object_info_panel` | Mine gate + exhausted UI | **USED** | Behalten | Low |
| `mine_no_ship` | No mining ship available | `can_mine_object` | Mine gate | **USED** | Behalten | Low |
| `mine_storage_full` | Storage full | Definition + `.tres` + `_fallback_for_key` only | — | **PREPARED** | Behalten oder an Mining-unload-Gate anbinden; heute `storage_full` via `get_base_storage_blocked_reason_full()` | Low |
| `build_not_enough_resources` | Not enough resources | `base_store` build gates, survey probe build, colony cost | Build gates | **USED** | Behalten | Low |
| `build_scan_drone_limit` | Scan drone limit reached | `base_store` | Build gate | **USED** | Behalten | Low |
| `build_mining_ship_limit` | Mining ship limit reached | `base_store` | Build gate | **USED** | Behalten | Low |
| `upgrade_not_enough_resources` | Not enough resources | `base_store.get_buy_next_upgrade_blocked_reason_key` | Upgrade gate | **USED** | Behalten | Low |
| `upgrade_max_level` | Maximum level reached | Definition + `.tres` only | — | **PREPARED** | Behalten für spätere Upgrade-Hover-Max-Texte; Max-Level nutzt Scene-Captions in `upgrade_panel.tscn` | Low |
| `storage_full` | Storage full | `get_base_storage_blocked_reason_full()` → automation + storage panel | Storage block | **USED** | Behalten | Low |
| `colony_no_ship` | No Colony Ship available | Definition + `.tres` only | ObjectInfo nutzt **Scene** template, nicht Key | **PREPARED** | Scene an Key anbinden **oder** Key aus `.tres` entfernen nach Abgleich | Low |
| `colony_not_enough_resources` | Not enough resources | `base_store` colony build | Colony build gate | **USED** | Behalten | Low |
| `colony_shipyard_required` | Shipyard I required | `game_session` prerequisite rows | Colony build gate | **USED** | Behalten | Low |
| `colony_protocol_required` | Colony Protocol required | prerequisite rows | Colony build gate | **USED** | Behalten | Low |
| `colony_deep_scan_required` | Deep Scan Module required | prerequisite rows | Colony build gate | **USED** | Behalten | Low |
| `colony_ice_source_required` | Ice source not discovered | prerequisite rows | Colony build gate | **USED** | Behalten | Low |
| `colony_fully_scan_three` | Fully scan 3 objects | prerequisite rows | Colony build gate | **USED** | Behalten | Low |

**Removed since earlier audits:** `colony_requirement_missing` — no longer in definition or `.tres` (correct).

---

## DiscoverySignalUiTextDefinition Key Table

| Key | .tres | Code / runtime | Status | Recommendation | Risk |
|-----|-------|----------------|--------|----------------|------|
| `investigate_progress` | Yes | `format_investigate_progress`, controllers, panel (fallback if scene format empty) | **USED** | Behalten | Low |
| `investigate_lore_active` | Yes | `system_ui_controller` lore | **USED** | Behalten | Low |
| `signal_lore_fallback` | Yes | `signal_marker.gd` | **USED** | Behalten | Low |
| `marker_label_fallback` | Yes | `signal_marker.gd` | **USED** | Behalten | Low |
| `signal_object_type_label` | Yes | `get_signal_object_type_label()` → marker | **USED** | Behalten | Low |
| `unknown_signal_name` | Yes | `get_unknown_signal_name()` → marker | **USED** | Behalten | Low |
| `unknown_signal_type` | Yes | Only `get_unknown_signal_type()` in definition; **no external caller** | **PREPARED** | Behalten für Signal-Type-UI oder Helper entfernen wenn dauerhaft ungenutzt | Low |
| `unknown_signal_lore` | Yes | `get_unknown_signal_lore()` → marker | **USED** | Behalten | Low |
| `blocked_no_probe` | Yes | `survey_probe_mission_controller` | **USED** | Behalten | Low |
| `blocked_not_signal` | Yes | survey probe | **USED** | Behalten | Low |
| `blocked_in_progress` | Yes | survey probe + system UI | **USED** | Behalten | Low |
| `blocked_target_missing` | Yes | survey probe | **USED** | Behalten | Low |
| `blocked_base_missing` | Yes | survey probe | **USED** | Behalten | Low |
| `blocked_already_known` | Yes | survey probe | **USED** | Behalten | Low |
| `blocked_active_probe_limit` | Yes | survey probe | **USED** | Behalten | Low |
| `sensor_pulse_button_label` | Yes | `get_sensor_pulse_button_label()` only in definition; button = Scene `"Sensor Pulse"` | **FALLBACK_ONLY / DEAD API** | Behalten Key+FALLBACK; Helper optional entfernen | Low |
| `sensor_pulse_progress_format` | Yes | pulse controller, system UI, panel | **USED** | Behalten | Low |
| `sensor_pulse_block_active` | Yes | `base_sensor_pulse_controller` | **USED** | Behalten | Low |
| `sensor_pulse_block_cooldown` | Yes | pulse controller | **USED** | Behalten | Low |
| `sensor_pulse_block_no_hidden` | Yes | pulse controller | **USED** | Behalten | Low |
| `sensor_pulse_block_not_enough_survey_data` | Yes | pulse controller | **USED** | Behalten | Low |
| `sensor_pulse_block_base_missing` | Yes | pulse controller | **USED** | Behalten | Low |
| `sensor_pulse_cost_format` | Yes | `format_sensor_pulse_cost` | **USED** | Behalten | Low |

All Discovery keys exist in `.tres` and have matching `FALLBACK_*` in the definition script.

---

## Other UI Text Resources

### `upgrade_effect_texts.tres`

| Key | Used via |
|-----|----------|
| `cargo_delta` / `cargo_final` | `UpgradeDefinition` + upgrade hover |
| `mining_rate_*` | Same |
| `scan_duration_*` / `scan_speed_*` / `scan_support_*` | Same |
| `storage_capacity_*` | Same |

**Status:** **USED** (indirect through `UpgradeDefinition.set_effect_texts` in `GameSession._load_upgrade_effect_texts`).  
**Recommendation:** Behalten.

### `data/production/*.tres`

Player-facing: `short_description`, `effect_lines`, button captions in scenes (`ColonyShip`, etc.). **Not** GateUiText — correct separation.

### `data/colonization/default_colonization.tres`

Operation status strings (`Running %ds`, etc.) — **USED** via `ColonizationDefinition.format_operation_status_view` in `galaxy_map_hud.gd`.  
`completed_status_label` / `cancelled_status_label` empty → Galaxy falls back to `ColonizationPendingFallbackTemplate` (“Running”) when format returns empty — **intentional v0.1**, not dead data.

---

## Helper Function Table

| Function | File | Callers | Status | Recommendation | Risk |
|----------|------|---------|--------|----------------|------|
| `get_scan_button_label_for_target_state()` | `game_session.gd` | Only calls `get_rescan_button_label_for_target_state` | **DEAD** (no UI) | Später verdrahten **oder** entfernen mit Rescan-Helper | Medium if removed without product sign-off |
| `get_rescan_button_label_for_target_state()` | `game_session.gd` | Only from scan label helper above | **DEAD** | Same | Medium |
| `_scan_button_text_default` / `scan_button_text` in info dict | `object_info_panel.gd` | Internal; **no** `system_ui_controller` sets `info["scan_button_text"]` | **USED** (Scene → panel) | Behalten — bewusst Scene-Default `"Scan"` | Low |
| `_blocked_reason_for_button()` | `production_panel.gd` | Hover build | **USED** | Behalten | Low |
| `_blocked_reason_for_category()` | `upgrade_panel.gd` | Hover upgrade | **USED** | Behalten | Low |
| `_colonization_no_ship_tooltip` | `object_info_panel.gd` | `_apply_colonization_controls` | **USED** | Behalten; optional später `get_gate_text(KEY_COLONY_NO_SHIP)` | Low |
| `_scan_blocked_no_layer()` | `game_session.gd` | `can_scan_object` | **USED** | Behalten | Low |
| `get_gate_text()` | `game_session.gd` | Gates, prerequisites, storage | **USED** | Behalten | Low |
| `get_gate_ui_texts()` | `game_session.gd` | Thin wrapper → `GateUiTextDefinition.get_global()` | **API only** | Behalten (public facade) | Low |
| `GateUiTextDefinition.set_global()` | `game_session.gd` `_load_gate_ui_texts` | Boot | **USED** | Behalten | Low |
| `GateUiTextDefinition.get_global()` | via `get_gate_ui_texts` only | No other callers | **API only** | Behalten | Low |
| `GateUiTextDefinition.has_text()` | — | **No callers** | **DEAD API** | Optional entfernen oder für Editor-Tools behalten | Low |
| `DiscoverySignalUiTextDefinition.set_global()` | `game_session.gd` | Boot | **USED** | Behalten | Low |
| `DiscoverySignalUiTextDefinition.get_global()` | — | **Does not exist** | — | — | — |
| `get_unknown_signal_type()` | `discovery_signal_ui_text_definition.gd` | **None** | **DEAD** | Remove helper or wire signal UI | Low |
| `get_sensor_pulse_button_label()` | `discovery_signal_ui_text_definition.gd` | **None** | **DEAD** | Remove helper or set button from resource | Low |
| `_apply_enter_button_tooltip` / `_enter_tooltips` | — | **Absent** | — | — | — |

---

## Template Node Table

| Node | Scene | Used by code? | Status | Recommendation |
|------|-------|---------------|--------|----------------|
| `InvestigateProgressFormatTemplate` | `object_info_panel.tscn` | Yes — `_investigate_progress_format` | **USED** | Behalten; duplicates Discovery `.tres` as editor preview (**DUPLICATE** source, runtime prefers scene then Discovery fallback) |
| `SensorPulseProgressLabel` | `object_info_panel.tscn` | Yes | **USED** | Behalten |
| `InvestigateProgressLabel` | `object_info_panel.tscn` | Yes | **USED** | Behalten |
| `ColonizationNoShipTooltipTemplate` | `object_info_panel.tscn` | Yes → `_colonization_no_ship_tooltip` | **USED** | **Naming cleanup optional** (not Godot tooltip) |
| `ColonizationRunningTemplate` | `object_info_panel.tscn` | Yes | **USED** | Behalten |
| `MiningButtonDepletedTemplate` | `object_info_panel.tscn` | Yes — `_mining_button_text_depleted` | **USED** | Behalten (mine button text when exhausted) |
| `ScanState*Template` / lore templates | `object_info_panel.tscn` | Yes | **USED** | Behalten |
| `AccessStatus*Template` | `galaxy_map_hud.tscn` | Yes | **USED** | Behalten (Enter status, no tooltip) |
| `Colonization*Template` / `Intel*Template` | `galaxy_map_hud.tscn` | Yes | **USED** | Behalten |
| `HoverInfoSection` | production / upgrade panels | Yes | **USED** | Custom hover — bewusst |
| `DetailLabelTemplate` / `EffectsSectionLabelTemplate` | `top_hud_hover_panel.tscn` | Yes | **USED** | Behalten |

**No dead template nodes found** in the scoped scenes without `@onready` wiring.

---

## Scene-Default vs Code-Text

| Control | Scene default | Code sets same static text? | Verdict |
|---------|---------------|------------------------------|---------|
| `ScanWithDroneButton` | `"Scan"` | No — `system_ui_controller` does **not** set `scan_button_text` | **OK** (panel reads scene via `_scan_button_text_default`) |
| `SensorPulseButton` | `"Sensor Pulse"` | No — matches Discovery `.tres` but scene wins | **OK**; Discovery `get_sensor_pulse_button_label()` unused |
| `InvestigateButton` | `"Investigate"` | No duplicate | **OK** |
| `ColonizationButton` | `"Start Colonization"` | No duplicate | **OK** |
| Recall buttons | EN labels | No duplicate | **OK** |
| `BuildColonyShipButton` | `"ColonyShip"` | No duplicate | **OK** |

**DUPLICATE (intentional layering):** Investigate progress format exists in both `InvestigateProgressFormatTemplate` (scene) and `discovery_signal_ui_texts.tres` — runtime uses scene first.

---

## Dead Code Candidates

*(Candidates only — do not delete without follow-up task.)*

1. **`get_scan_button_label_for_target_state()` / `get_rescan_button_label_for_target_state()`** — ~25 lines in `game_session.gd`.
2. **`DiscoverySignalUiTextDefinition.get_unknown_signal_type()`** — no callers.
3. **`DiscoverySignalUiTextDefinition.get_sensor_pulse_button_label()`** — no callers.
4. **`GateUiTextDefinition.has_text()`** — no callers.
5. **Gate keys without runtime key reference:** `mine_storage_full`, `upgrade_max_level`, `colony_no_ship` (`.tres` + fallbacks only).

---

## Do Not Remove

- **`FALLBACK_*` constants** in `gate_ui_text_definition.gd` and `discovery_signal_ui_text_definition.gd` — required when `.tres` fails to load.
- **`KEY_NONE`** — gate plumbing, not a player string.
- **`set_global()` loaders** in `GameSession._ready`.
- **Hidden scene templates** — copied at runtime; not editor-only decoration.
- **`_scan_button_text_default` pipeline** — intentional Scene-`"Scan"` policy.
- **`get_scan_button_label_*`** — product may wire later; treat as **reserved API** until explicitly removed.
- **`upgrade_max_level` / `mine_storage_full` keys** — reasonable v0.2 hooks unless product confirms never.

---

## Safe Cleanup Candidates (max 5)

### 1. Align ObjectInfo “No Colony Ship” with `KEY_COLONY_NO_SHIP`

- **Ziel:** Single source for copy; use `GameSession.get_gate_text(GateUiTextDefinition.KEY_COLONY_NO_SHIP)` in `_ready` or keep scene text synced.
- **Dateien:** `object_info_panel.gd` and/or `object_info_panel.tscn`
- **Risiko:** Low
- **AK:** Visible text unchanged; `colony_no_ship` key **USED** in code
- **Commit:** `Wire colony no-ship block text to GateUiTextDefinition`

### 2. Mark or remove dead scan button label helpers

- **Ziel:** Reduce confusion; add `@deprecated` comment or delete both functions if design confirms permanent `"Scan"` label.
- **Dateien:** `game_session.gd`
- **Risiko:** Medium (API removal) — prefer **comment + keep** unless user approves delete
- **AK:** No references; project parses
- **Commit:** `Document unused scan button label helpers` or `Remove unused scan button label helpers`

### 3. Remove unused Discovery wrapper methods

- **Ziel:** `get_unknown_signal_type()`, `get_sensor_pulse_button_label()` if keys stay for `get_template()` only.
- **Dateien:** `discovery_signal_ui_text_definition.gd`
- **Risiko:** Low
- **AK:** Keys remain in `.tres`; no behavior change
- **Commit:** `Remove unused DiscoverySignalUiTextDefinition accessors`

### 4. Resolve prepared Gate keys (`mine_storage_full`, `upgrade_max_level`)

- **Ziel:** Either wire (mining storage gate / upgrade max hover) or document in definition comment as v0.2.
- **Dateien:** `gate_ui_text_definition.gd`, consumers
- **Risiko:** Low if only comments; Medium if wiring gates
- **AK:** Key status clear in docs
- **Commit:** `Document prepared gate UI text keys` or wire specific gate

### 5. Optional: `GateUiTextDefinition.has_text()` removal

- **Ziel:** Drop unused public API.
- **Dateien:** `gate_ui_text_definition.gd`
- **Risiko:** Low
- **AK:** No callers
- **Commit:** `Remove unused GateUiTextDefinition.has_text`

---

## Recommended Next Prompt

> Read-only bestätigt: Welche der 3 PREPARED Gate-Keys (`colony_no_ship`, `mine_storage_full`, `upgrade_max_level`) sollen in v0.1 noch angeschlossen werden? Implementiere nur die vom User gewählten 1–2 Anbindungen (z. B. ObjectInfo `get_gate_text(KEY_COLONY_NO_SHIP)`), ohne `get_scan_button_label_*` zu verdrahten und ohne etwas zu löschen, das nicht explizit freigegeben ist.

---

## Akzeptanz (this audit)

1. Only `docs/audits/unused_ui_text_keys_and_helpers_audit_v0_1.md` created — **yes**
2. No code/scene/data changes — **yes**
3. `tooltip_text` = 0 — **yes**
4. Distinction unused / fallback-only / prepared / scene-default / dead — **yes**
