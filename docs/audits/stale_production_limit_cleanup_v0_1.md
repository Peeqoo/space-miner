# Stale Production-Limit Cleanup v0.1

**Date:** 2026-06-07  
**Scope:** Post Step 2b cleanup — remove misleading SD/MS hard-limit artifacts.  
**No gameplay gate, cost, scaling, save, or automation changes.**

---

## Summary

| Area | Action |
|------|--------|
| `KEY_BUILD_SCAN_DRONE_LIMIT` / `KEY_BUILD_MINING_SHIP_LIMIT` | Constants **kept**, deprecated in `gate_ui_text_definition.gd`; **not emitted** by `BaseStore` build gates |
| `gate_ui_texts.tres` | Limit strings **already removed** (Step 2a) |
| Telemetry `units.scan_drone` / `mining_ship` | `max_count` → `balance_reference_max_count`; `build_hard_limit_active: false`; `hard_limit_removed_for_build: true` |
| `get_max_*_count()` APIs | **Kept** for telemetry reference; doc comments = deprecated build cap |
| `max_scan_drones_start` / `max_mining_ships_start` | **Kept** in `GameBalanceDefinition`; legacy reference comments added |

## Unchanged (by design)

- `KEY_SCAN_ALREADY_IN_PROGRESS` — runtime scan gate
- `max_active_probes_start` — SurveyProbe investigate parallel cap
- ColonyShip gates / flat cost / `scaling_excluded`
- Scaled production costs (Step 2b)
- `SaveManager.SAVE_VERSION = 1`

## Reference audit (post-cleanup)

| Reference | Gameplay | UI-facing | Telemetry/Diag only |
|-----------|----------|-----------|---------------------|
| `KEY_BUILD_SCAN_DRONE_LIMIT` | No | No (not in `.tres`) | Tests (`step_2a_production_limit_smoke_test.gd`) |
| `KEY_BUILD_MINING_SHIP_LIMIT` | No | No | Tests |
| `get_max_scan_drone_count()` | No | No | Yes → `balance_reference_max_count` |
| `get_max_mining_ship_count()` | No | No | Yes |
| `max_scan_drones_start` | No | No | Indirect via get_max_* |
| `max_mining_ships_start` | No | No | Indirect via get_max_* |

## UI check

- `production_panel.gd` — gate `ok` only; no limit-specific branch
- `object_info_panel.gd` — scan block via `KEY_SCAN_ALREADY_IN_PROGRESS` unchanged
- `tooltip_text` — 0 in project
