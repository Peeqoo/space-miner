# AutomationSaveService Phase A Baseline v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Scope:** `game_session.automation.runtime` shape for Save-v1 before `AutomationSaveService` Phase A write-path extraction.  
**Method:** Static code audit + **reference JSON templates** (not editor-captured disk saves).

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Baseline ready for Phase A?** | **Conditional yes** — schema/shape documented; **byte-compare gate** still needs **manual editor capture** to replace templates |
| **Cases documented** | Idle, Scan outbound, Scan at target (post-complete orbit), Mining with cargo, WAITING_FOR_STORAGE (reference template) |
| **Missing cases** | Live `user://saves/save_*.json` files (none found on audit machine); CASE 3 variant “scan WORKING before store complete” not separate file |

### Capture status

| Case | Runtime JSON on disk | Reference template |
|------|----------------------|-------------------|
| 1 Idle | **NOT CAPTURED** (no save files) | `docs/audits/save_baselines/automation_runtime_idle.json` |
| 2 Scan outbound | **NOT CAPTURED** | `automation_runtime_scan_outbound.json` |
| 3 Scan at target | **NOT CAPTURED** | `automation_runtime_scan_at_target.json` |
| 4 Mining with cargo | **NOT CAPTURED** | `automation_runtime_mining_with_cargo.json` |
| 5 WAITING_FOR_STORAGE | **NOT TESTED** (editor) | `automation_runtime_waiting_for_storage.json` (code-derived) |

**Why NOT CAPTURED:** Godot CLI not in PATH; no `user://saves/save_*.json` under `%APPDATA%/Godot/app_userdata/` for this project on the audit host. Templates match `AutomationController.to_save_data()` / `_build_*_job_save_dict` logic in `scripts/system/controller/automation_controller.gd`.

**Before Phase A merge:** Developer should run the five manual flows, save slot 1–3, copy `game_session.automation.runtime` from `user://saves/save_NNN.json` (project: **SpaceMining**) over the templates and note slot + timestamp in this doc.

---

## Save Info

| Case | Save slot / file | `system_id` (expected) | `primary_base_id` (expected) | Notes |
|------|------------------|------------------------|------------------------------|--------|
| 1 Idle | *pending manual* | `solar-system` | `earth` | `GameSession.START_SYSTEM_ID`, `BaseStore.BASE_EARTH` |
| 2 Scan outbound | *pending manual* | `solar-system` | `earth` | Save while `unit_state == TRAVEL_TO_TARGET` (2) |
| 3 Scan at target | *pending manual* | `solar-system` | `earth` | Template = **post-scan support orbit** (`scan_reveal_done: true`); see variant note below |
| 4 Mining with cargo | *pending manual* | `solar-system` | `earth` | `status == 1` (MINING) in template |
| 5 WAITING_FOR_STORAGE | **NOT TESTED** | — | — | Template uses `status: 4`; confirm in editor |

**Save path (v1):** `user://saves/save_%03d.json` → typically  
`%APPDATA%/Godot/app_userdata/SpaceMining/saves/save_001.json` on Windows.  
**`save_version`:** `1` (`SaveManager.SAVE_VERSION`).  
**Pre-save:** Survey Probe / Sensor Pulse cancel does **not** alter `automation.runtime` (no entries for those FSMs).

---

## automation.runtime Root Keys

Expected root keys from `to_save_data()` (lines 2303–2309): **exactly four keys**, no others.

| Case | `system_id` | `primary_base_id` | `scan_missions` count | `mining_missions` count |
|------|-------------|-------------------|------------------------|-------------------------|
| 1 Idle | string | string | **0** | **0** |
| 2 Scan outbound | string | string | **≥ 1** | **0** |
| 3 Scan at target | string | string | **≥ 1** | **0** |
| 4 Mining with cargo | string | string | **0** | **≥ 1** |
| 5 WAITING_FOR_STORAGE (template) | string | string | **0** | **≥ 1** |

**Idle note:** Orbiting idle drones/ships live in `idle_drones` / `idle_mining_ships` only — **not** serialized unless listed in `scan_drone_target_by_unit_id` or `mining_ship_runtime_by_unit_id` (`_scan_missions_to_save_array` / `_mining_missions_to_save_array`).

---

## Scan Mission Shape

Applies to CASE 2–3. Keys from `_build_scan_job_save_dict` (lines 2529–2547). All keys **required** when a scan job is written.

| Key | JSON type | CASE 2 outbound | CASE 3 at target (template) | Notes |
|-----|-----------|-----------------|----------------------------|--------|
| `target_id` | string | yes | yes | e.g. body id |
| `base_id` | string | yes | yes | `_get_session_base_id()` |
| `mission_id` | number (int) | yes | yes | `> 0` while store mission active; often **0** after `complete_automation_mission` |
| `orbit_anchor_id` | string | yes | yes | home or `unit.base_node` id |
| `unit_state` | number (int) | yes | yes | `AutomationUnit.State`: 2 = TRAVEL_TO_TARGET; 1 = ORBITING_BASE; 4 = WORKING |
| `work_timer` | number | yes | yes | float |
| `work_duration` | number | yes | yes | float |
| `travel_progress` | number | yes | yes | 0..1 |
| `scan_reveal_done` | bool | yes | yes | `false` if `active_units_by_mission_id.has(mission_id)`; else true |
| `global_position` | object | yes | yes | `{ "x", "y" }` only — **no Node refs** |
| `orbit_angle` | number | yes | yes | |
| `orbit_direction` | number | yes | yes | |
| `orbit_radius_x` | number | yes | yes | |
| `orbit_radius_y` | number | yes | yes | |
| `orbit_speed` | number | yes | yes | |
| `orbit_rotation` | number | yes | yes | |
| `travel_curve_side_sign` | number | yes | yes | |

### CASE 3 variants (same key set)

| Variant | When to save | `unit_state` | `scan_reveal_done` | `mission_id` |
|---------|--------------|--------------|--------------------|--------------|
| **3a In-flight scan work** | Before `_on_scan_drone_arrived_at_target` completes store | often **4** WORKING | **false** | **≥ 1** |
| **3b Support orbit** (template file) | After scan complete, drone orbiting target | often **1** ORBITING_BASE | **true** | often **0** |

Template JSON file documents **3b**. Capture **3a** separately during manual baseline if both matter for Phase A tests.

**Node references:** Sanitizer not used on scan jobs; only primitives + `global_position` dict — **must not** contain paths/instance ids.

---

## Mining Mission Shape

Applies to CASE 4–5. Built by `_build_mining_job_save_dict`: `_sanitize_dictionary_for_save(runtime)` then unit field overwrites (lines 2552–2569).

| Key | JSON type | CASE 4 template | CASE 5 template | Notes |
|-----|-----------|-------------------|-----------------|--------|
| `system_id` | string | yes | yes | From runtime |
| `base_id` | string | yes | yes | |
| `target_id` | string | yes | yes | |
| `cargo_resources` | object | yes | yes | resource_id → int |
| `mining_extract_remainders` | object | yes | yes | may be `{}` |
| `cargo_resource_id` | string | yes | yes | often `""` |
| `current_cargo` | number | yes | yes | float |
| `cargo_capacity` | int | yes | yes | |
| `mining_rate_per_second` | number | yes | yes | |
| `unload_duration` | number | yes | yes | |
| `unload_timer` | number | yes | yes | |
| `unload_xfer_buffers` | object | yes | yes | |
| `loop_active` | bool | yes | yes | |
| `status` | int | yes | yes | `MiningShipStatus`: 0 TO_TARGET, 1 MINING, 2 TO_BASE, 3 UNLOADING, **4 WAITING_FOR_STORAGE** |
| `extract_remainder` | number | yes | yes | |
| `unit_state` | int | yes | yes | from unit at save |
| `work_timer` | number | yes | yes | |
| `work_duration` | number | yes | yes | often `999999.0` (`DEFAULT_MINING_DURATION`) |
| `travel_progress` | number | yes | yes | |
| `global_position` | object | yes | yes | `{ x, y }` |
| `orbit_anchor_id` | string | yes | yes | |

**Extra runtime keys:** Any key passing `_sanitize_value_for_save` at save time (e.g. `cargo_unload_sfx_played` bool) may appear — Phase A must **not** drop them. Templates show minimal set from mission start dict (lines 664–680).

**CASE 5:** Editor **NOT TESTED**; template `status: 4` matches `MiningShipStatus.WAITING_FOR_STORAGE`.

---

## JSON Snippets

Full reference copies live under `docs/audits/save_baselines/`. Below: same content (abbreviated comments only in this section).

### CASE 1 — Idle

```json
{
  "system_id": "solar-system",
  "primary_base_id": "earth",
  "scan_missions": [],
  "mining_missions": []
}
```

### CASE 2 — Scan outbound (template)

See `save_baselines/automation_runtime_scan_outbound.json`.  
Highlights: `unit_state: 2`, `scan_reveal_done: false`, `mission_id: 1`, `travel_progress` between 0 and 1.

### CASE 3 — Scan at target / support orbit (template)

See `save_baselines/automation_runtime_scan_at_target.json`.  
Highlights: `orbit_anchor_id` may equal target; `scan_reveal_done: true`, `mission_id: 0`.

### CASE 4 — Mining with cargo (template)

See `save_baselines/automation_runtime_mining_with_cargo.json`.  
Highlights: `status: 1` (MINING), non-empty `cargo_resources`, `unit_state: 4` (WORKING).

### CASE 5 — WAITING_FOR_STORAGE (reference only, NOT TESTED)

See `save_baselines/automation_runtime_waiting_for_storage.json`.  
Highlights: `status: 4`, `cargo_resources` preserved, ship at base orbit (`orbit_anchor_id: "earth"`).

---

## Code-Derived Rules (audit evidence)

| Rule | Source |
|------|--------|
| Only assigned scan drones saved | `scan_drone_target_by_unit_id` iteration (2422+) |
| Only active mining runtime saved | `mining_ship_runtime_by_unit_id` (2487+) |
| `scan_reveal_done` | `mission_id <= 0` OR not in `active_units_by_mission_id` (2524–2527) |
| No `scan_is_progression` in runtime | Stored in `automation.store.missions` only (`save_schema_v1.md`) |
| Invalid units skipped | `instance_from_id` null → job omitted |
| No Node in JSON | `_sanitize_value_for_save` returns null for non-JSON types (mining path) |

---

## Compatibility Requirements for Phase A

Phase A write-path extraction **must preserve**:

- Root keys: `system_id`, `primary_base_id`, `scan_missions`, `mining_missions` only.
- Full **scan_missions** key set (16 fields per job) — names and types unchanged.
- **mining_missions** sanitizer behavior — no whitelist that drops previously serialized runtime keys.
- JSON types: int/float/bool/string/object/array only in saved output.
- `SaveManager.SAVE_VERSION` **1** — no bump.
- **No** `active_missions` / Save-v2 fields.
- **No** `tooltip_text` (project policy; grep **0** in `*.gd` / `*.tscn` / `*.tres` at audit time).

---

## Open Issues

| Issue | Severity | Action |
|-------|----------|--------|
| No live save JSON on audit machine | **Medium** | Manual capture before Phase A PR merge |
| CASE 5 not playtested | **Low** | Mark NOT TESTED; optional before Phase B |
| CASE 3a vs 3b | **Low** | Capture both if scan-in-progress save matters |
| Numeric samples in templates | **Info** | Position/timer values will differ per run — compare keys/types, not exact floats |
| `target_id` placeholders (`moon`, `asteroid_a`) | **Info** | Replace with real body ids from your system scene |

**No issues found:** NodeRef in JSON schema; missing root keys in code path; Save-v1 version mismatch in code.

---

## Recommended Next Step

**Schema baseline: PASS WITH NOTES** — safe to **start Phase A implementation** of write-path-only `AutomationSaveService` **in parallel** with manual capture.

**Before merging Phase A:**

1. Run manual cases 1–4 (and 5 if possible).
2. Paste real `automation.runtime` into `docs/audits/save_baselines/` (overwrite templates) or attach slot paths to this report.
3. After Phase A code: diff normalized JSON (keys/types; floats epsilon) per `automation_save_service_extraction_plan_v0_1.md`.

**If manual capture shows unexpected keys or Node data:** stop Phase A and audit `_build_mining_job_save_dict` / sanitizer first.

**Implementation prompt (unchanged):**

```
Implement AutomationSaveService Phase A only (write-path extraction):
- Create scripts/system/automation/automation_save_service.gd
- Delegate from AutomationController.to_save_data()
- No restore extraction, no schema changes
- Compare automation.runtime JSON before/after using save_baselines/
```

---

## Acceptance (this audit)

1. No code/scene/data gameplay files changed.  
2. Report + optional baseline JSON under `docs/audits/save_baselines/` created.  
3. Cases Idle, Scan outbound, Scan at target, Mining with cargo documented.  
4. WAITING_FOR_STORAGE: reference template yes, editor **NOT TESTED**.  
5. `automation.runtime` shape documented from code + templates.  
6. Phase A may start with **manual byte-compare still required** before merge.  
7. `tooltip_text` grep: **0**.
