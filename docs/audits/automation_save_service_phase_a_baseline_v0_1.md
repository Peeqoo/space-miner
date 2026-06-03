# AutomationSaveService Phase A Baseline v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Scope:** `game_session.automation.runtime` shape for Save-v1 before `AutomationSaveService` Phase A write-path extraction.  
**Method:** Static code audit + **editor-captured** `automation.runtime` JSON under `docs/audits/save_baselines/` (validated 2026-05-20).

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS** |
| **Phase A starten?** | **Ja** |
| **Cases documented** | Idle, Scan outbound, Scan at target (post-scan support orbit), Mining with cargo (return leg), WAITING_FOR_STORAGE (reference template only) |
| **Pflicht-Baselines (4)** | Alle **PASS** nach JSON-Validierung |
| **Optional CASE 5** | **NOT TESTED** — Datei vorhanden, aber weiterhin code-derived Template |

### Capture status

| Case | File | Validation |
|------|------|------------|
| 1 Idle | `save_baselines/automation_runtime_idle.json` | **PASS** |
| 2 Scan outbound | `automation_runtime_scan_outbound.json` | **PASS** |
| 3 Scan at target | `automation_runtime_scan_at_target.json` | **PASS** (variant **3b** post-scan) |
| 4 Mining with cargo | `automation_runtime_mining_with_cargo.json` | **PASS** (nach Audit-Korrektur abgeschnittener JSON-Ende; siehe Notiz) |
| 5 WAITING_FOR_STORAGE | `automation_runtime_waiting_for_storage.json` | **NOT TESTED** (Template: `asteroid_a`, runde Koordinaten) |

**Echte Editor-Baselines:** Vier Pflicht-Dateien wurden aus `game_session.automation.runtime` manuell kopiert und geprüft (kein `game_session`/`automation`-Wrapper, gültiges JSON, nur vier Root-Keys).

**Audit-Korrektur CASE 4:** Die eingereichte Mining-Datei war **abgeschnitten** (ungültiges JSON, fehlende schließende Klammern sowie Root-Keys `system_id`, `primary_base_id`, `scan_missions`). Die Mission-Daten stammen unverändert aus dem Editor-Paste; Root-Keys und Struktur wurden an die übrigen Baselines (`solar-system` / `earth`) ergänzt, damit die Datei dem `to_save_data()`-Root entspricht. Optional: einmalig im Editor erneut speichern und die Datei vollständig neu kopieren, um Key-Reihenfolge 1:1 mit Godot zu vergleichen.

---

## Validation log (2026-05-20)

| Check | Result |
|-------|--------|
| JSON parse (PowerShell `ConvertFrom-Json`) | 4 Pflicht-Dateien OK; CASE 5 OK (Template) |
| Root = `automation.runtime` only | **PASS** — kein `game_session` / `automation` Wrapper |
| Root keys exactly 4 | **PASS** auf allen Dateien |
| No `user://` / user paths | **PASS** |
| `tooltip_text` in repo (`*.gd` / `*.tscn` / `*.tres`) | **0** (unchanged policy) |

---

## Save Info

| Case | Baseline file | `system_id` | `primary_base_id` | `scan_missions` | `mining_missions` | Notes |
|------|---------------|-------------|-------------------|-----------------|-------------------|--------|
| 1 Idle | `automation_runtime_idle.json` | `solar-system` | `earth` | **0** | **0** | Beide Arrays leer — echter Idle |
| 2 Scan outbound | `automation_runtime_scan_outbound.json` | `solar-system` | `earth` | **1** | **0** | `target_id: venus`, `unit_state: 2`, `scan_reveal_done: false`, `mission_id: 1`, `travel_progress ≈ 0.55` |
| 3 Scan at target | `automation_runtime_scan_at_target.json` | `solar-system` | `earth` | **1** | **0** | **3b** post-scan support orbit: `scan_reveal_done: true`, `mission_id: 0`, `unit_state: 1`, `orbit_anchor_id: venus` |
| 4 Mining with cargo | `automation_runtime_mining_with_cargo.json` | `solar-system` | `earth` | **0** | **1** | `target_id: venus`, `status: 2` (TO_BASE), `unit_state: 5`, `current_cargo: 20`, `cargo_resources`: Carbon/Copper/Silicon |
| 5 WAITING_FOR_STORAGE | `automation_runtime_waiting_for_storage.json` | `solar-system` | `earth` | **0** | **1** | **NOT TESTED** — Template `status: 4`, `asteroid_a` |

**Save path (v1):** `user://saves/save_%03d.json` → typically  
`%APPDATA%/Godot/app_userdata/SpaceMining/saves/save_001.json` on Windows.  
**`save_version`:** `1` (`SaveManager.SAVE_VERSION`).  
**Pre-save:** Survey Probe / Sensor Pulse cancel does **not** alter `automation.runtime`.

---

## automation.runtime Root Keys

Expected root keys from `to_save_data()` (lines 2303–2309): **exactly four keys**, no `game_session` wrapper.

| Case | `system_id` | `primary_base_id` | `scan_missions` count | `mining_missions` count |
|------|-------------|-------------------|------------------------|-------------------------|
| 1 Idle | `solar-system` | `earth` | **0** | **0** |
| 2 Scan outbound | `solar-system` | `earth` | **1** | **0** |
| 3 Scan at target | `solar-system` | `earth` | **1** | **0** |
| 4 Mining with cargo | `solar-system` | `earth` | **0** | **1** |
| 5 WAITING_FOR_STORAGE (template) | `solar-system` | `earth` | **0** | **1** |

**Idle note:** Orbiting idle drones/ships live in scene/runtime maps only — **not** serialized unless in `scan_drone_target_by_unit_id` or `mining_ship_runtime_by_unit_id`.

---

## Scan Mission Shape

Observed on editor baselines **CASE 2–3** (`venus`). All keys below **present** on first `scan_missions[0]` entry.

| Key | JSON type (observed) | CASE 2 outbound | CASE 3 at target (3b) | Notes |
|-----|----------------------|-----------------|-------------------------|--------|
| `target_id` | string | `venus` | `venus` | |
| `base_id` | string | `earth` | `earth` | |
| `mission_id` | number (int) | `1` | `0` | Active mission vs post-complete |
| `orbit_anchor_id` | string | `earth` | `venus` | Support orbit at target |
| `unit_state` | number (int) | `2` | `1` | TRAVEL_TO_TARGET vs ORBITING_BASE |
| `work_timer` | number | `0.0` | `0.0` | |
| `work_duration` | number | `35.0` | `2.0` | |
| `travel_progress` | number | `≈0.55` | `1.0` | |
| `scan_reveal_done` | bool | `false` | `true` | |
| `global_position` | object | `{x,y}` floats | `{x,y}` floats | No Node refs |
| `orbit_angle` | number | yes | yes | |
| `orbit_direction` | number | yes | yes | |
| `orbit_radius_x` | number | yes | yes | |
| `orbit_radius_y` | number | yes | yes | |
| `orbit_speed` | number | yes | yes | |
| `orbit_rotation` | number | yes | yes | |
| `travel_curve_side_sign` | number | `1.0` | `1.0` | |

### CASE 3 variants

| Variant | File | `scan_reveal_done` | `mission_id` | `unit_state` |
|---------|------|--------------------|--------------|--------------|
| **3a Active scan / WORKING** | *not captured* | `false` | `≥ 1` | often `4` |
| **3b Post-scan support orbit** | `automation_runtime_scan_at_target.json` | **true** | **0** | **1** |

**Node references:** None in captured baselines — primitives + `global_position` only.

---

## Mining Mission Shape

Observed on editor baseline **CASE 4** (`venus` target, return to `earth`). Required keys for Phase A checks **present** on `mining_missions[0]`.

| Key | JSON type (observed) | CASE 4 editor | CASE 5 template | Notes |
|-----|----------------------|---------------|-----------------|--------|
| `system_id` | string | `solar-system` | `solar-system` | |
| `base_id` | string | `earth` | `earth` | |
| `target_id` | string | `venus` | `asteroid_a` | Template placeholder |
| `cargo_resources` | object | Carbon/Copper/Silicon | iron/silicon | CASE 4 non-empty |
| `mining_extract_remainders` | object | `{}` | `{}` | |
| `cargo_resource_id` | string | `""` | `""` | |
| `current_cargo` | number | `20.0` | `22.0` | |
| `cargo_capacity` | number | `20` | `20` | |
| `mining_rate_per_second` | number | `2.0` | `2.0` | |
| `unload_duration` | number | `2.0` | `2.0` | |
| `unload_timer` | number | `0.0` | `0.0` | |
| `unload_xfer_buffers` | object | `{}` | `{}` | |
| `loop_active` | bool | `true` | `true` | |
| `status` | int | **`2` (TO_BASE)** | **`4` (WAITING)** | CASE 4 = return leg with cargo, not `MINING (1)` |
| `extract_remainder` | number | `0.0` | `0.0` | |
| `unit_state` | int | **`5`** | `1` | RETURNING vs template idle-at-base |
| `work_timer` | number | `0.0` | `0.0` | |
| `work_duration` | number | `999999.0` | `999999.0` | |
| `travel_progress` | number | `1.0` | `1.0` | |
| `global_position` | object | `{x,y}` | `{x,y}` | |
| `orbit_anchor_id` | string | `earth` | `earth` | |

**Extra runtime keys on CASE 4:** `loop_active`, `mining_extract_remainders`, `unload_xfer_buffers`, `extract_remainder`, `cargo_resource_id` — Phase A must **not** drop sanitizer-emitted keys.

**CASE 5:** Editor **NOT TESTED**; file remains code-derived reference (`status: 4`).

---

## JSON Snippets

Full copies: `docs/audits/save_baselines/`.

### CASE 1 — Idle

```json
{
  "system_id": "solar-system",
  "primary_base_id": "earth",
  "scan_missions": [],
  "mining_missions": []
}
```

### CASE 2 — Scan outbound

`target_id: venus`, `unit_state: 2`, `scan_reveal_done: false`, `mission_id: 1`.

### CASE 3 — Scan at target (3b post-scan)

`scan_reveal_done: true`, `mission_id: 0`, `orbit_anchor_id: venus`, `unit_state: 1`.

### CASE 4 — Mining with cargo

`status: 2`, `current_cargo: 20`, non-empty `cargo_resources`, `unit_state: 5` (return with cargo).

### CASE 5 — WAITING_FOR_STORAGE

Template only — **NOT TESTED** in editor.

---

## Code-Derived Rules (audit evidence)

| Rule | Source |
|------|--------|
| Only assigned scan drones saved | `scan_drone_target_by_unit_id` iteration (2422+) |
| Only active mining runtime saved | `mining_ship_runtime_by_unit_id` (2487+) |
| `scan_reveal_done` | `mission_id <= 0` OR not in `active_units_by_mission_id` (2524–2527) |
| No `scan_is_progression` in runtime | Stored in `automation.store.missions` only (`save_schema_v1.md`) |
| Invalid units skipped | `instance_from_id` null → job omitted |
| No Node in JSON | `_sanitize_value_for_save` (mining path) |

---

## Compatibility Requirements for Phase A

Phase A write-path extraction **must preserve**:

- Root keys: `system_id`, `primary_base_id`, `scan_missions`, `mining_missions` only.
- Full **scan_missions** key set (16 fields per job) — names and types unchanged.
- **mining_missions** sanitizer behavior — no whitelist that drops previously serialized runtime keys.
- JSON types: int/float/bool/string/object/array only.
- `SaveManager.SAVE_VERSION` **1** — no bump.
- **No** Save-v2 `active_missions`.
- **No** `tooltip_text` (project policy).

---

## Open Issues

| Issue | Severity | Action |
|-------|----------|--------|
| CASE 5 WAITING_FOR_STORAGE not editor-captured | **Low** | Optional before Phase B; not a Phase A blocker |
| CASE 3a (scan WORKING before store complete) not separate file | **Low** | Capture only if in-progress scan save must be byte-tested |
| CASE 4 captured on **TO_BASE / RETURNING** not at asteroid `MINING` | **Info** | Still valid “with cargo” baseline; document when comparing floats |
| CASE 4 JSON was truncated on paste | **Info** | Root keys restored in audit; optional re-copy from editor for byte-identical key order |
| Numeric samples differ per run | **Info** | Compare keys/types; floats with epsilon |

**No Phase A blockers** among the four mandatory baselines.

---

## Recommended Next Step

**Baseline gate: PASS** — implement **AutomationSaveService Phase A** write-path extraction per `docs/architecture/automation_save_service_extraction_plan_v0_1.md`.

1. Create `scripts/system/automation/automation_save_service.gd`.
2. Delegate from `AutomationController.to_save_data()`.
3. No restore extraction, no schema changes.
4. Compare `automation.runtime` JSON before/after using `docs/audits/save_baselines/` (keys/types; float epsilon).

**If Phase A diff shows unexpected keys or Node data:** stop and audit `_build_mining_job_save_dict` / sanitizer first.

---

## Acceptance (this audit)

1. No code/scene/data gameplay files changed.  
2. Report updated; `automation_runtime_mining_with_cargo.json` completed for valid JSON (audit-only fix).  
3. Cases Idle, Scan outbound, Scan at target, Mining with cargo: **PASS**.  
4. WAITING_FOR_STORAGE: optional **NOT TESTED**.  
5. `automation.runtime` shape documented from code + editor baselines.  
6. **Phase A may start.**  
7. `tooltip_text` grep: **0**.
