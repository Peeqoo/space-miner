# Galaxy Transition Repeated SurveyProbe Bug Audit v0.1

**Date:** 2026-06-20  
**Godot:** 4.6.1

---

## Root Cause

### Problem 1 — Idle visual missing after first roundtrip

**Ordering:** `ensure_starting_units()` runs **before** survey-probe restore.

1. After galaxy return, `ensure_starting_units` spawns **1** idle probe (store available = 1).
2. `restore_from_runtime_snapshot` calls `take_idle_survey_probe_for_base()` for active mission A → steals that idle unit, marks it busy.
3. **No post-restore reconcile** → store still shows 1 available, but **0** idle visuals at base.

TopHUD reads **BaseStore** count; world shows **AutomationController** idle units → divergence.

### Problem 2 — Second roundtrip loses mission B

When all probes are consumed (store available = 0), restore still used `take_idle_survey_probe_for_base()`:

```gdscript
if GameSession.get_available_survey_probe_count(bid) <= 0:
    return null
```

Restore fails silently (warning only). Probe was already spent at investigate start; mission snapshot is dropped on return → **silent probe + mission loss**.

Second capture/restore path itself was fine (`take_pending` clears after consume; next leave overwrites snapshot). Failure was restore unit acquisition, not one-shot flags.

---

## Why Previous SmokeTest PASS Was Incomplete

Original `galaxy_transition_process_continuity_smoke_test` Test A:

- Single investigate on one target
- Only **one** galaxy roundtrip
- Asserts probe count and mission active — **not** idle visual count at home
- Does not start a **second** investigate after first roundtrip with store = 0

---

## Runtime Lost

| Case | Lost |
|------|------|
| First return | Idle survey-probe **visual** (store count preserved) |
| Second return | Entire **active mission** when store available = 0 |

---

## Fix Plan

1. `borrow_survey_probe_unit_for_restored_mission()` — spawn busy mission unit without store check when `consumed_probe_already`.
2. `ensure_survey_probe_units_for_base()` after restore + in `SystemScene._restore_pending_system_processes()`.
3. `_reconcile_idle_survey_probe_visuals_after_restore()` at end of `restore_from_runtime_snapshot()`.
4. Smoke tests for repeated roundtrips + idle visual vs store parity.

---

## Audit Answers (summary)

| Area | Finding |
|------|---------|
| A — Idle visual sync | Post-restore reconcile was missing; `ensure_survey_probe_units_for_base` uses store count correctly |
| B — Mission restore | Missions re-enter `_active_missions`; re-capture works if unit restore succeeds |
| C — Multiple roundtrips | Capture overwrites pending each leave; no one-shot flag |
| D — Probe consumption | Restore must never call `consume_survey_probe`; failed restore caused silent loss |
