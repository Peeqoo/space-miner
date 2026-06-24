# ProductionPanel TODO Text Cleanup v0.1 — Audit

**Date:** 2026-06-07  
**Task:** Full Project Cleanup Audit **Task 9** — remove unfinished TODO/timer player copy from ProductionPanel.

---

## Audit summary

ProductionPanel shows **no unfinished TODO or timer planning text**. Phase 1 already removed visible strings such as `"instant build — timer TODO"`. Builds remain **instant**; `build_time_seconds` exists only in data/API for future queue UI. This task adds audit closure and smoke verification — **no gameplay, cost, gate, or save changes**.

---

## Audit answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Player-facing texts? | Header (`Production`), build buttons, hover title/description/cost, colony prerequisite lines, gate `blocked_reason` strings |
| 2 | TODOs only in code? | **Yes** — see table below; none rendered in UI |
| 3 | What does player see? | Build buttons + hover (description, scaled costs, block reasons) — **no build-time row** |
| 4 | Scene labels for build time? | **No** dedicated build-time label in `production_panel.tscn` |
| 5 | Production instant? | **Yes** — `GameSession.build_base_*` completes immediately |
| 6 | Planned timers? | `build_time_seconds` on `colony_ship.tres`, balance fields, `get_*_build_time_seconds()` — **not wired to UI** |

---

## Found TODO / timer references

| Location | Text / symbol | Player-visible? | Decision |
|----------|---------------|-----------------|----------|
| `production_panel.tscn` | *(none)* | — | No change |
| `production_panel.gd` ~205 | Code comment: instant builds, `build_time_seconds` data-only | **No** | Keep comment |
| `production_definition.gd` ~8 | Code comment: `build_time_seconds`, GameSession TODO | **No** | Keep comment |
| `colony_ship.tres` | `build_time_seconds = 120.0` | **No** (data only) | No change |
| `game_session.gd` | `get_colony_ship_build_time_seconds()` etc. | **No** (not called from panel) | No change |
| `base_store.gd` | *(none)* | — | No change |
| `data/production/*.tres` | Normal `short_description` / `effect_lines` | **Yes** (hover) | Already clean — no TODO copy |
| Pre-cleanup hover (audit) | `"instant build — timer TODO"` | Was **yes** | **Removed** in Phase 1 |

**Build-time UI strategy:** Row **hidden** (not rendered). No `"Instant"` line needed — absence is neutral for v0.1.

---

## Old → new (visible UI)

| Location | Old (pre-cleanup) | Current |
|----------|-------------------|---------|
| Hover placeholder | `"instant build — timer TODO"` (or similar) | `"Hover an production to see details."` |
| Hover on colony ship | Timer TODO copy | Description + prerequisites + costs |
| Build buttons | unchanged | `ScanDrone`, `MiningShip`, `Survey Probe`, `ColonyShip` |

---

## Changed files

| File | Change |
|------|--------|
| `docs/audits/production_panel_todo_text_cleanup_v0_1.md` | This audit |
| `scripts/debug/smoke_tests/production_panel_todo_text_cleanup_smoke_test.gd` | New smoke A/B + regression |
| `scripts/debug/smoke_tests/production_panel_todo_text_cleanup_smoke_runner.tscn` | New runner |

**Verified unchanged (no edits required):**

- `scenes/ui/system/production_panel.tscn`
- `scripts/ui/system/production_panel.gd`
- `scripts/autoload/stores/base_store.gd`
- `scripts/autoload/game_session.gd`
- `data/production/*.tres`
- `SAVE_VERSION` (= 1)

---

## Tests

| Test | Result |
|------|--------|
| **A** — no `TODO` / `timer TODO` / `instant build` in visible labels/hover | **PASS** |
| **B** — `build_base_drone` instant (+1 drone, iron consumed) | **PASS** |
| `object_info_simple_action_button_labels_smoke_test` | **PASS WITH NOTES** |
| `save_behavior_v0_1_smoke_test` | **PASS WITH NOTES** |
| `SAVE_VERSION = 1`, `tooltip_text = 0` | **PASS** |

Run:

```bash
godot --headless --path . --scene res://scripts/debug/smoke_tests/production_panel_todo_text_cleanup_smoke_runner.tscn
```

---

## Risks

| Risk | Mitigation |
|------|------------|
| Re-introducing timer copy in `_build_hover_description()` | Smoke A scans panel + hover on all build buttons |
| Future queue UI shows `build_time_seconds` without design pass | Documented as data-only in v0.1; API exists but unused in panel |
| Colony ship `build_time_seconds = 120` misread as active timer | Not displayed; instant build behavior unchanged |

---

## Cleanup Audit

- **Task 9** (ProductionPanel TODO text): **done**

---

## Result

**PASS** — No visible TODO/timer debug text; production behavior, costs, gates, and save version unchanged.
