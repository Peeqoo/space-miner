# DEFAULT_SCAN_DURATION_FALLBACK Audit v0.1

**Date:** 2026-06-07  
**Scope:** `DEFAULT_SCAN_DURATION_FALLBACK` in `automation_controller.gd` — usage audit; comment/docs only.  
**Godot:** 4.6.1 (strict typing)

---

## Audit summary

`DEFAULT_SCAN_DURATION_FALLBACK = 2.0` is an **emergency safety constant**, not the primary scan-duration source. In normal play it is **not reached** because `data/units/scan_drone.tres` loads successfully with `scan_duration_seconds = 2.0`.

The v0.2 cleanup audit compared this constant to `GameBalanceDefinition.basic_scan_duration` (35s). That comparison mixes **two separate code paths**:

| Path | Source | Typical value (v0.1) | Used for |
|------|--------|----------------------|----------|
| **Mission / launch** | `GameSession.get_scan_duration_seconds_for_target_state()` | 35 / 85 / 140s (balance defaults × upgrade multiplier) | `launch_scan_drone`, `assign_scan_drone_to_shared_job` → `unit.work_duration` |
| **Idle / orbit / restore fallback** | `_get_scan_duration_seconds_base()` → `scan_drone.tres` `scan_duration_seconds` | 2.0s × multiplier | `ensure_starting_units`, `reapply_session_base_unit_upgrade_effects`, save restore when `work_duration` missing |
| **Emergency** | `DEFAULT_SCAN_DURATION_FALLBACK` | 2.0 | Only when `UnitCatalog` cannot provide a valid `scan_drone` definition |

**SharedScanJob** completes on **arrival** (`_process_shared_scan_job_arrival`), not when `work_timer >= work_duration`. Scan rewards fire once per job completion. The fallback constant does not drive SharedScanJob timing.

There is **no existing smoke** that exercises the missing-`UnitDefinition` branch. Removal would be risky (silent 0-duration edge cases if catalog load fails).

---

## Audit questions (answers)

1. **When is `DEFAULT_SCAN_DURATION_FALLBACK` used?**  
   Only inside `_get_scan_duration_seconds_base()` when `UnitCatalog.get_definition("scan_drone")` is null or `scan_duration_seconds <= 0`, after `push_warning`.

2. **Is it only a missing-resource safety path?**  
   **Yes.** Normal gameplay always loads `data/units/scan_drone.tres`.

3. **What scan duration does ScanDrone use in regular play?**  
   - **Active scans:** `GameBalanceDefinition.basic_scan_duration` (35s default; not overridden in `v0_1_balance.tres`) via `get_scan_duration_seconds_for_target_state`.  
   - **Idle drone stats:** `scan_drone.tres` `scan_duration_seconds = 2.0` (legacy single field; layer fields unset).

4. **Is there a test for missing UnitDefinition?**  
   **No.** Documented as emergency-only; new audit smoke verifies catalog present so fallback branch is not taken.

5. **Would removal be dangerous?**  
   **Yes.** Would return implicit 0 or break `_get_scan_work_duration_for_base` maxf floor semantics without a defined emergency value.

6. **Would aligning to balance 35s make sense?**  
   **No** for this constant. Aligning would mismatch `scan_drone.tres` (2.0) on the idle/restore path and would not affect mission duration (separate API). Changing values would be balance/gameplay tuning.

7. **Is comment + audit sufficient?**  
   **Yes.** Keep `2.0` (matches unit tres legacy field and `AutomationUnit` default export).

---

## Decision

**Keep + document (Option: comment + audit)**

- Retain `DEFAULT_SCAN_DURATION_FALLBACK = 2.0`.
- Expanded comment on constant in `automation_controller.gd`.
- No duration value changes, no SharedScanJob / scan-speed changes.

**Not done:** align to 35s, remove constant, wire new gates, add missing-unit mock test (would require invasive catalog stub).

---

## Fallback path (reference)

```
_get_scan_work_duration_for_base(base_id)
  └─ _get_scan_duration_seconds_base()
       ├─ UnitCatalog.get_definition("scan_drone")
       │    └─ scan_duration_seconds > 0  →  use tres value (2.0)
       └─ else push_warning → DEFAULT_SCAN_DURATION_FALLBACK (2.0)

launch_scan_drone / assign_scan_drone
  └─ GameSession.get_scan_duration_seconds_for_target_state(...)
       ├─ unit layer fields if set
       └─ else GameBalanceDefinition.get_scan_duration_for_layer (35/85/140)
```

---

## Changed files

| File | Change |
|------|--------|
| `scripts/system/controller/automation_controller.gd` | Expanded `DEFAULT_SCAN_DURATION_FALLBACK` comment |
| `scripts/debug/smoke_tests/default_scan_duration_fallback_audit_smoke_test.gd` | **New** |
| `scripts/debug/smoke_tests/default_scan_duration_fallback_audit_smoke_runner.tscn` | **New** |
| `docs/audits/default_scan_duration_fallback_audit_v0_1.md` | **New** |

**Unchanged:** scan durations, SharedScanJob logic, rewards, `SAVE_VERSION`, tooltips.

---

## Tests

### New smoke

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/default_scan_duration_fallback_audit_smoke_runner.tscn
```

- **Test A:** Mission `work_duration` matches `get_scan_duration_seconds_for_target_state` (balance path), not emergency fallback; catalog loads.
- **Test B:** SharedScanJob completes; SurveyData reward granted once.
- **Test C:** Emergency fallback documented; normal play has valid unit definition.
- **Regression:** `SAVE_VERSION == 1`, `tooltip_text == 0`.

### Regression smokes

| Runner | Purpose |
|--------|---------|
| `shared_scan_job_step_4_single_drone_processing_smoke_runner.tscn` | Single-drone SharedScanJob |
| `shared_scan_job_step_5_save_restore_smoke_runner.tscn` | Save/restore |
| `shared_scan_job_step_7_existing_effect_stacking_smoke_runner.tscn` | Effect stacking unchanged |
| `shared_scan_job_step_7_speed_scaling_rollback_smoke_runner.tscn` | Speed scaling rollback |

---

## Risks

| Risk | Level | Notes |
|------|-------|-------|
| Confusion between 2.0 and 35s | Medium | Documented as separate paths; v0.2 item can close |
| Emergency path never tested live | Low | Acceptable; warning logged if hit |
| Aligning fallback to 35s later | Low | Would be wrong for idle/restore path without broader refactor |

---

## Verdict

**PASS WITH NOTES**

- Fallback evaluated and kept as emergency-only.
- Normal scans remain data-driven via `GameSession.get_scan_duration_seconds_for_target_state`.
- No gameplay, SharedScanJob, reward, or save-version changes.
- Note: `2.0` coincidentally matches `scan_drone.tres` legacy field and `AutomationUnit.work_duration` default — not balance basic scan duration (35s).
