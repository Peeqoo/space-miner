# Galaxy Transition Repeated SurveyProbe Fix v0.1

**Date:** 2026-06-20  
**Status:** **PASS**

---

## Root Cause

1. **Idle visual gap:** `ensure_starting_units()` spawned one idle probe before restore; restore took it for the active mission; no post-restore `ensure_survey_probe_units_for_base()` → TopHUD store = 1, visible idle = 0.

2. **Second roundtrip mission loss:** Restore used `take_idle_survey_probe_for_base()`, which returns `null` when `get_available_survey_probe_count() == 0`. After second investigate (both probes deployed), restore failed silently while probes remained consumed.

No one-shot snapshot flag; capture/restore pipeline was re-entrant — unit acquisition was not.

---

## Why Previous PASS Was Incomplete

`galaxy_transition_process_continuity_smoke_test` used one target, one roundtrip, and never asserted `idle visual count == store count` or a second investigate after `store = 0`.

---

## Fix Approach

| Change | Purpose |
|--------|---------|
| `borrow_survey_probe_unit_for_restored_mission()` | Spawn busy mission unit without BaseStore check when probe already consumed |
| Restore uses `borrow_*` when `consumed_probe_already` | Missions restore even at store = 0 |
| `_reconcile_idle_survey_probe_visuals_after_restore()` | `ensure_survey_probe_units_for_base()` after all mission restores |
| `SystemScene._restore_pending_system_processes()` | Final idle reconcile after survey + sensor restore |
| `get_idle_survey_probe_count_at_home()` | Debug/smoke parity checks |

---

## Changed Files

| File | Change |
|------|--------|
| `scripts/system/controller/automation_controller.gd` | `borrow_survey_probe_unit_for_restored_mission`, idle/busy count helpers |
| `scripts/system/controller/survey_probe_mission_controller.gd` | Borrow on restore, post-restore reconcile |
| `scripts/system/system_scene.gd` | `ensure_survey_probe_units_for_base` after pending restore |
| `scripts/debug/smoke_tests/galaxy_transition_repeated_survey_probe_smoke_test.gd` | Tests A–C |
| `scripts/debug/smoke_tests/galaxy_transition_repeated_survey_probe_smoke_runner.tscn` | Runner |
| `docs/audits/galaxy_transition_repeated_survey_probe_bug_v0_1.md` | Audit |

**Unchanged:** Save version, costs, scan/mining gameplay, UI, `KEY_SCAN_ALREADY_IN_PROGRESS`.

---

## Tests

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/galaxy_transition_repeated_survey_probe_smoke_runner.tscn
```

**PASS** — idle=store after RT1; mission B survives RT2; 3× roundtrip on active mission.

Regression: `galaxy_transition_process_continuity_smoke_runner.tscn` still **PASS**.

---

## Risks

- `borrow_*` adds busy units not backed by store rows — reconciled by `ensure_*` only spawning up to store available count for idle orbit.
- Multiple simultaneous restored missions each get a borrowed unit; idle reconcile must not trim busy units (already excluded via `survey_probe_busy_unit_ids`).

---

## Known Limits

- Save-on-disk still cancels/refunds investigate (v0.1 save policy unchanged).
- Completed-during-galaxy path unchanged (background elapsed still applies).

---

## Acceptance

| # | Criterion | Result |
|---|-----------|--------|
| 1–4 | Idle visible, store parity, second probe, second RT | **PASS** |
| 5–8 | Repeatable RT, no re-consume, no silent loss, single reward | **PASS** (smoke C + B) |
| 9–10 | Automation spawn truth / mission controller separation | **PASS** |
| 11–12 | SAVE_VERSION=1, tooltip_text=0 | **PASS** |

**Overall: PASS**
