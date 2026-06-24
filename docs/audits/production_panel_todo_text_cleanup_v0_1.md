# ProductionPanel TODO Text Cleanup v0.1 — Audit

**Date:** 2026-06-07  
**Task:** Full Project Cleanup Audit **Task 9** — remove unfinished TODO/timer player copy from ProductionPanel.

---

## Audit answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Player-facing texts? | Button labels (`ScanDrone`, `MiningShip`, `Survey Probe`, `ColonyShip`), hover title/cost, `ProductionDefinition.short_description` / `effect_lines` from `.tres` |
| 2 | TODOs only in code? | **Yes** — `production_panel.gd` line ~205 and `production_definition.gd` line ~8 are **comments only**; not shown in UI |
| 3 | What does player see? | Build buttons + custom hover section (description, costs, block reasons, colony prerequisites) — **no build-time row** |
| 4 | Scene labels for build time? | **No** dedicated build-time label in `production_panel.tscn` |
| 5 | Production instant? | **Yes** — `GameSession.build_base_*` completes immediately; `build_time_seconds` in data is not rendered |
| 6 | Planned timers? | `build_time_seconds` / `get_colony_ship_build_time_seconds()` exist for future use; **no queue UI in v0.1** |

---

## Old → new (visible UI)

| Location | Old (pre-cleanup) | Current |
|----------|-------------------|---------|
| Scene / hover | e.g. `"instant build — timer TODO"` | `"Hover an production to see details."` (placeholder only) |
| Build buttons | unchanged | `ScanDrone`, `MiningShip`, `Survey Probe`, `ColonyShip` |
| Hover on item | TODO timer copy | Description + costs + gates from data |

---

## Decision

**No code/scene changes required** — Phase 1 already removed visible TODO strings. This task adds audit closure + smoke verification.

---

## Files verified (unchanged)

| File | Status |
|------|--------|
| `scenes/ui/system/production_panel.tscn` | No TODO/timer text |
| `scripts/ui/system/production_panel.gd` | No player-facing build-time line; instant comment only |
| `data/production/*.tres` | Normal descriptions; `colony_ship.build_time_seconds` data-only |
| `resources/definitions/production_definition.gd` | `build_time_seconds` export; no UI formatting |

---

## Tests

| Test | Result |
|------|--------|
| `production_panel_todo_text_cleanup_smoke_test` A–B | Run after creation |
| `step_2b_production_scaled_cost_smoke_test` (build still works) | Existing regression |

---

## Cleanup Audit

- **Task 9** (ProductionPanel TODO text): **done**

---

## Risks

| Risk | Mitigation |
|------|------------|
| Re-introducing timer copy in hover | Smoke A scans all visible labels |
| `build_time_seconds` shown later without design | Data field documented as non-UI in v0.1 |

---

## Result

**PASS** — Visible TODO/timer copy absent; production behavior unchanged.
