# base_sensor_max_visible_signals Cleanup v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Scope:** Legacy Balance-Feld entfernen / verifizieren — kein SensorPulse-Gameplay-Change.

---

## Audit Answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Active code references? | **None** in `scripts/` — field absent from runtime GDScript |
| 2 | Used for gate/block? | **No** — `can_start_sensor_pulse()` checks base, in-progress, cooldown, hidden candidates, SurveyData only |
| 3 | Only in balance files? | **Was** in balance; **now removed** from `game_balance_definition.gd` and `v0_1_balance.tres` (Phase 1) |
| 4 | Save compatibility if removed? | **Low risk** — field was never in `SaveManager` schema; balance loaded from `.tres` at boot |
| 5 | Godot `.tres` compat if removed? | **Safe** — Godot ignores unknown keys in `.tres` when property removed from script |
| 6 | Remove vs deprecated? | **Option A — Remove** (already done) |

---

## Old Meaning vs Current Status

| Aspect | Old (pre-removal) | Current |
|--------|-------------------|---------|
| `base_sensor_max_visible_signals` | Inspector cap suggesting max visible signals | **Removed** |
| SensorPulse gate | Possibly blocked when too many signals visible | **Removed** — cap never reintroduced |
| Reveal limit | N/A | `base_sensor_reveal_count` per pulse (unchanged) |
| Block when no targets | — | `sensor_pulse_block_no_hidden` (centralized UI text) |

SensorPulse starts when: base exists, SurveyData affordable, no active pulse/cooldown, **≥1 hidden candidate**.  
Does **not** block on count of visible `SIGNAL` markers.

---

## Decision

**Option A — Remove** (completed in Phase 1 cleanup; verified in this audit).

No deprecated no-op field retained — no save/load dependency found.

---

## Changed / Verified Files

| File | Status |
|------|--------|
| `resources/definitions/game_balance_definition.gd` | Field absent |
| `data/balance/v0_1_balance.tres` | Field absent |
| `scripts/system/controller/base_sensor_pulse_controller.gd` | No cap logic |
| `scripts/debug/smoke_tests/base_sensor_max_visible_signals_cleanup_smoke_test.gd` | **new** verification |

**Not changed:** gameplay, costs, UI layout, `SAVE_VERSION`.

---

## Full Project Cleanup Audit

- **Cleanup Audit Task 6** (Deprecate/remove `max_visible_signals` in balance): **done**

---

## Tests

| Test | Description | Result |
|------|-------------|--------|
| A | No export in definition/.tres; no runtime `.gd` references | **PASS** |
| B | ≥2 visible SIGNAL + hidden candidate → gate ok | **PASS** |
| C | Normal pulse start; cost unchanged (5 SD) | **PASS** |
| D | No hidden → `no_hidden` block text, not cap text | **PASS** |

Regression: sensor_pulse UI strings **PASS**, progress label **PASS WITH NOTES**, galaxy continuity **PASS**, object_info labels **PASS WITH NOTES**.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Old `.tres` copies with stale key | Godot ignores unknown properties |
| Designer re-adds cap field | Smoke B/C; audit documents removal |
| Confusion with `base_sensor_reveal_count` | Different concept (per-pulse reveal budget) — documented above |

---

## Result

**PASS** — Field already removed; smoke tests confirm no cap behavior.
