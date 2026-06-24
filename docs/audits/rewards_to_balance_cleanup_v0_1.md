# Rewards To Balance Cleanup v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Scope:** Datengetriebenheits-Cleanup — Scan- und Investigate-SurveyData-Rewards aus Balance, keine Wertänderung.

---

## Audit Answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Where are scan rewards defined? | `GameBalanceDefinition`: `scan_basic_survey_data_reward` (10), `scan_deep_survey_data_reward` (25), `scan_special_survey_data_reward` (50). Values in `data/balance/v0_1_balance.tres`. |
| 2 | Which method grants SurveyData on scan complete? | `GameSession.grant_scan_survey_data_reward()` → `balance.get_scan_survey_data_reward_for_state()`. Called from `AutomationController._complete_scan_mission()` when `scan_is_progression == true`. |
| 3 | Which ScanState values differ? | `basic` (+10), `deep` (+25), `special` (+50). Unknown / invalid → 0. |
| 4 | Where is investigate reward defined? | `GameBalanceDefinition.survey_probe_investigate_survey_data_reward` (5) in `.tres`; granted via `SurveyProbeMissionController._grant_survey_data_reward()`. |
| 5 | Balance fields already exist? | **Yes** — added in Phase 1 cleanup. |
| 6 | How does GameSession load balance? | `DEFAULT_GAME_BALANCE_PATH` → `res://data/balance/v0_1_balance.tres` via `get_game_balance()` / `_load_game_balance_definition()`. |
| 7 | How does SurveyProbeMissionController access balance? | `GameSession.get_game_balance()` with `GameBalanceDefinition.new()` fallback. |
| 8 | Smoke tests expecting reward values? | Step 4/6/7 smokes assert `sd_after > sd_before` (not hardcoded 10). New dedicated smoke asserts exact balance deltas. |

---

## Old Code Source → New Balance Source

| Reward | Old (pre-cleanup) | New |
|--------|-------------------|-----|
| Basic scan | Hardcoded `+10` in `game_session.gd` | `scan_basic_survey_data_reward` |
| Deep scan | Hardcoded `+25` | `scan_deep_survey_data_reward` |
| Special scan | Hardcoded `+50` | `scan_special_survey_data_reward` |
| Investigate | Hardcoded `+5` in `survey_probe_mission_controller.gd` | `survey_probe_investigate_survey_data_reward` |

**Naming note:** Fields use existing style `scan_*_survey_data_reward` (not `basic_scan_*`) to match `basic_scan_duration` / `scan_drone_*` grouping in `GameBalanceDefinition`.

---

## Values (unchanged)

| Field | Value |
|-------|-------|
| `scan_basic_survey_data_reward` | 10 |
| `scan_deep_survey_data_reward` | 25 |
| `scan_special_survey_data_reward` | 50 |
| `survey_probe_investigate_survey_data_reward` | 5 |

---

## Changed / Verified Files

| File | Role |
|------|------|
| `resources/definitions/game_balance_definition.gd` | Export fields + `get_scan_survey_data_reward_for_state()` + `get_survey_probe_investigate_survey_data_reward()` |
| `data/balance/v0_1_balance.tres` | Explicit 10 / 25 / 50 / 5 |
| `scripts/autoload/game_session.gd` | `grant_scan_survey_data_reward()` — no hardcoded amounts |
| `scripts/system/controller/survey_probe_mission_controller.gd` | `_grant_survey_data_reward()` — no hardcoded `5` |
| `scripts/system/controller/automation_controller.gd` | Unchanged caller of `grant_scan_survey_data_reward()` |
| `scripts/debug/smoke_tests/rewards_to_balance_cleanup_smoke_test.gd` | New A–E coverage |
| `scripts/debug/smoke_tests/rewards_to_balance_cleanup_smoke_runner.tscn` | New runner |

**Not changed:** ScanState logic, SharedScanJob, rescan guard (`scan_is_progression`), save schema, UI, costs, durations.

---

## Tests

| Test | Description |
|------|-------------|
| A | Balance fields exist; `.tres` == 10/25/50/5 |
| B | Basic scan completion → SD +`scan_basic_survey_data_reward` exactly once |
| C | `get_scan_survey_data_reward_for_state()` for BASIC/DEEP/SPECIAL/UNKNOWN (Deep/Special not full runtime sim) |
| D | Rescan after basic → SD unchanged |
| E | Investigate Venus signal → SD +`survey_probe_investigate_survey_data_reward` once |

**Regression smokes:** Step 4, Step 6, Step 7 effect stacking, galaxy repeated SurveyProbe, ObjectInfo simple labels.

---

## Full Project Cleanup Audit Cross-Reference

- **Cleanup Audit Task 2** (Move scan SD rewards to balance): **done**
- **Cleanup Audit Task 7** (Investigate reward to balance): **done**

---

## Risks

| Risk | Mitigation |
|------|------------|
| Balance `.tres` out of sync with GDScript defaults | Test A loads both; defaults match v0.1 values |
| Double reward on SharedScanJob | Unchanged `scan_is_progression` + completion guards; Step 4/6 regressions |
| Rescan farming | `_complete_scan_mission` early-return when `not scan_is_progression`; Test D |
| Investigate double grant | Unchanged mission lifecycle; Test E |

---

## Result

**PASS WITH NOTES** — Implementation was completed in Phase 1; this audit confirms no remaining hardcoded reward constants in target controllers. Deep/Special runtime scans validated via balance lookup (Test C note).
