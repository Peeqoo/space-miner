# Gate UI Text Unused Keys Cleanup Audit v0.1

**Date:** 2026-06-07  
**Scope:** `GateUiTextDefinition` / `gate_ui_texts.tres` — evaluate prepared/unused keys; no gameplay gate changes.  
**Repo:** `main` (local workspace)  
**Godot:** 4.6.1 (strict typing)

---

## Audit summary

All 23 `KEY_*` constants in `gate_ui_text_definition.gd` were checked against `gate_ui_texts.tres`, runtime gate emitters (`game_session.gd`, `base_store.gd`, `automation_controller.gd`), and UI consumers (`object_info_panel.gd`, `system_ui_controller.gd`).

**Findings:**

- **19 keys** are actively used at runtime (gate emission or wired player-facing UI).
- **2 keys** are **reserved** (template + fallback present; not emitted by current gates).
- **2 keys** are **deprecated** (identity constants for Step 2a unlimited-production smoke only).
- **0 keys** removed — all have documented purpose or active use.
- **`KEY_COLONY_NO_SHIP`** was already wired in a prior pass (`object_info_panel.gd` → `GameSession.get_gate_text`).

No gameplay gates, costs, `SAVE_VERSION`, or `tooltip_text` were changed.

---

## Key matrix

| Key | Text in `.tres` | Used in code? | Player-facing? | Decision |
|-----|-----------------|---------------|----------------|----------|
| `none` | — | Meta (`KEY_NONE`) | No | **Keep** (sentinel) |
| `scan_not_discovered` | Object not discovered | `game_session` scan gate | Yes | **Used** |
| `scan_already_in_progress` | Scan already in progress | `game_session`, automation assign | Yes | **Used** |
| `scan_no_drone` | No scan drone available | `game_session`, automation assign | Yes | **Used** |
| `scan_no_layer` | No scan layer available | `game_session._scan_blocked_no_layer` | Yes | **Used** |
| `mine_not_discovered` | Object not discovered | `game_session.can_mine_object` | Yes | **Used** |
| `mine_not_scanned` | Scan required | `game_session.can_mine_object` | Yes | **Used** |
| `mine_no_resources` | No resources available | `game_session.can_mine_object` | Yes | **Used** |
| `mine_depleted` | Resource depleted | `game_session`, `system_ui_controller` | Yes | **Used** |
| `mine_no_ship` | No mining ship available | `game_session.can_mine_object` | Yes | **Used** |
| `mine_storage_full` | Storage full | Not emitted (`KEY_STORAGE_FULL` used for unload) | No (reserved copy) | **Reserved** |
| `build_not_enough_resources` | Not enough resources | `base_store` build gates | Yes | **Used** |
| `build_scan_drone_limit` | — (not in `.tres`) | `step_2a_production_limit_smoke_test` identity only | No | **Deprecated / reserved** |
| `build_mining_ship_limit` | — (not in `.tres`) | `step_2a_production_limit_smoke_test` identity only | No | **Deprecated / reserved** |
| `upgrade_not_enough_resources` | Not enough resources | `base_store.get_buy_next_upgrade_blocked_reason_key` | Yes | **Used** |
| `upgrade_max_level` | Maximum level reached | Not emitted (max → `KEY_NONE`; scene captions) | No (reserved copy) | **Reserved** |
| `storage_full` | Storage full | `game_session.get_base_storage_blocked_reason_full` | Yes | **Used** |
| `colony_no_ship` | No Colony Ship available | `object_info_panel._ready` → `get_gate_text` | Yes | **Wired (used)** |
| `colony_not_enough_resources` | Not enough resources | `base_store` colony ship gate | Yes | **Used** |
| `colony_shipyard_required` | Shipyard I required | `game_session` colony prerequisites | Yes | **Used** |
| `colony_protocol_required` | Colony Protocol required | `game_session` colony prerequisites | Yes | **Used** |
| `colony_deep_scan_required` | Deep Scan Module required | `game_session` colony prerequisites | Yes | **Used** |
| `colony_ice_source_required` | Ice source not discovered | `game_session` colony prerequisites | Yes | **Used** |
| `colony_fully_scan_three` | Fully scan 3 objects | `game_session` colony prerequisites | Yes | **Used** |

---

## Decisions (wired / reserved / removed)

### Wired (prior pass — confirmed)

| Key | Action |
|-----|--------|
| `colony_no_ship` | Already wired: `object_info_panel.gd` loads copy via `GameSession.get_gate_text(KEY_COLONY_NO_SHIP, scene template)`. No further change. |

### Reserved (Option B)

| Key | Rationale |
|-----|-----------|
| `mine_storage_full` | Mining unload/storage blocks use `KEY_STORAGE_FULL` via `get_base_storage_blocked_reason_full()`. Separate mine-specific copy kept in `.tres` + fallback for future differentiation without gate reorder changes. |
| `upgrade_max_level` | Max-level upgrades return `KEY_NONE` from `base_store`; UI uses `upgrade_panel.tscn` captions. Template retained for future hover/block messaging. |
| `build_scan_drone_limit` | Deprecated after unlimited production (Step 2a). Constant retained for smoke identity checks that limits are **not** emitted. |
| `build_mining_ship_limit` | Same as scan drone limit — deprecated identity only. |

### Removed (Option C)

None. Every unused key has a documented reserved/deprecated purpose or active smoke reference.

---

## Changed files

| File | Change |
|------|--------|
| `resources/definitions/gate_ui_text_definition.gd` | `## Reserved` / `## Deprecated` comments on `KEY_MINE_STORAGE_FULL`, `KEY_UPGRADE_MAX_LEVEL` |
| `scripts/debug/smoke_tests/gate_ui_text_unused_keys_cleanup_smoke_test.gd` | **New** — Tests A/B/C + SAVE_VERSION / tooltip regression |
| `scripts/debug/smoke_tests/gate_ui_text_unused_keys_cleanup_smoke_runner.tscn` | **New** — headless runner |
| `docs/audits/gate_ui_text_unused_keys_cleanup_v0_1.md` | **New** — this audit |

**Not changed:** `game_session.gd`, `base_store.gd`, `gate_ui_texts.tres` (already complete), gameplay gates, costs, `SAVE_VERSION`.

---

## Tests

### New smoke

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/gate_ui_text_unused_keys_cleanup_smoke_runner.tscn
```

- **Test A:** `GateUiTextDefinition` loads; all runtime gate keys have non-empty text.
- **Test B:** Runtime + reserved keys (except deprecated identity-only) have `.tres` entry or built-in fallback.
- **Test C:** No `.tres` or definition key without runtime use or `RESERVED_KEYS` registry entry.
- **Regression:** `SAVE_VERSION == 1`, `tooltip_text == 0` in scene tree.

### Regression smokes (recommended)

| Smoke | Purpose |
|-------|---------|
| `object_info_simple_action_button_labels_smoke_runner.tscn` | ObjectInfo simple labels |
| `production_panel_todo_text_cleanup_smoke_runner.tscn` | ProductionPanel TODO cleanup |
| `save_behavior_v0_1_smoke_runner.tscn` | Save behavior |

---

## Risks

| Risk | Level | Mitigation |
|------|-------|------------|
| Reserved keys mistaken for active gates | Low | Comments in definition + smoke `RESERVED_KEYS` registry |
| `mine_storage_full` vs `storage_full` duplication | Low | Documented; mining intentionally uses `storage_full` |
| Removing deprecated limit keys breaks Step 2a smoke | Medium | Keys kept; not removed |
| Future wiring changes gate semantics | Medium | Out of scope — explicit non-goal |

---

## Verdict

**PASS WITH NOTES**

- All gate keys audited and documented.
- No undocumented unused player-facing keys.
- No gameplay gate / cost / save-version changes.
- Reserved and deprecated keys explicitly documented.
- Notes: `mine_storage_full` and `upgrade_max_level` remain prepared copy only; deprecated build-limit keys are smoke identity constants only.
