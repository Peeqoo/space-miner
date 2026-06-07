# Unlimited Production + Multi-Unit Target Plan v0.1

**Date:** 2026-06-07  
**Engine:** Godot 4.6.1  
**Method:** Design / audit plan only — **no code, scene, data, balance, save, or tooltip changes**  
**References:** `docs/audits/postfix_colonyship_balance_verification_v0_1.md`, `docs/audits/expansion_loop_postfix_closure_v0_1.md`, `scripts/debug/balance_telemetry_logger.gd`

**Tooltip-Check:** No `tooltip_text` changes proposed. Existing UI uses hover sections / labels, not tooltips.

---

## Summary

| Item | Recommendation |
|------|----------------|
| **Overall recommendation** | **Approve direction, implement in small gated steps** — do not ship unlimited production + multi-target stacking in one pass |
| **Scope** | Production scaling (SD/MS/SP), multi-ScanDrone per object, confirm/extend multi-MiningShip per object, SurveyProbe rule refinement, ColonyShip unchanged |
| **What changes** | Hard fleet caps removed for SD/MS/SP; flat build costs replaced by scaling model; scan gate “already in progress” replaced by shared progress + stacking; UI shows next cost and per-target assignments; telemetry extended |
| **What must not change yet** | ColonyShip gating, save version (`SAVE_VERSION = 1`), expansion-loop structural fixes, existing upgrade `.tres` files deleted, balance numbers finalized without telemetry runs |

### Verdict

v0.1 balance is built around **control limits** (`max_scan_drones_start`, `max_mining_ships_start`, `max_active_probes_start`) and **one active scan per object**. That conflicts with the new direction. **Multi-MiningShip per target is largely already supported at runtime**; **multi-ScanDrone per target is explicitly blocked**; **production limits are enforced in `BaseStore` gates**. The safest path is: design approval → static audit sign-off → Step 1 (scaling cost helper, read-only) → remove SD/MS/SP limits → UI cost display → multi-MS hardening → multi-SD shared progress → upgrade reinterpretation → 30-min telemetry run.

---

## Current State Audit

### Fleet production limits

| System | Current hard limit | Where defined | Where enforced | UI dependency | Save dependency | Risk |
|--------|-------------------|---------------|----------------|---------------|-----------------|------|
| **ScanDrone** | **2** (`max_scan_drones_start`) | `resources/definitions/game_balance_definition.gd` (`Control Limits`), loaded via `data/balance/v0_1_balance.tres` (defaults) | `BaseStore.get_max_scan_drone_count()` → `get_build_scan_drone_blocked_reason_key()` → `KEY_BUILD_SCAN_DRONE_LIMIT`; surfaced via `GameSession.get_build_base_scan_drone_gate()` | `production_panel.gd` disables button when gate fails; hover shows flat cost from `get_production_cost("scan_drone")` | Fleet count in `bases[base_id].drones` — no separate limit field in save | **High** — core loop cap; telemetry logs `max_count: 2` |
| **MiningShip** | **2** (`max_mining_ships_start`) | Same as SD | `BaseStore.get_max_mining_ship_count()` → `KEY_BUILD_MINING_SHIP_LIMIT` | Same pattern via `get_build_base_mining_ship_gate()` | `bases[base_id].mining_ships` | **High** — MS2 pacing tied to this cap in balance audits |
| **SurveyProbe** | **No build limit**; **max 2 parallel investigates** (`max_active_probes_start`) | `GameBalanceDefinition.max_active_probes_start`; per-signal rule in `SurveyProbeMissionController` | Build: cost-only gate in `BaseStore` (`KEY_BUILD_NOT_ENOUGH_RESOURCES`). Runtime: `get_max_active_probes()` + `can_investigate_signal()` (`REASON_IN_PROGRESS` per object, global count cap) | `production_panel.gd`; investigate button via `system_ui_controller.gd` / `object_info_panel.gd` | `survey_probes` count in base save; investigate missions **not persisted** (cancelled on save) | **Medium** — production already unlimited; parallel cap is the real blocker |
| **ColonyShip** | **1 per build**; heavy prereq gating (protocol, deep scans, ice/water, resources, shipyard proxy) | `data/production/colony_ship.tres`, `GameBalanceDefinition`, `GameSession.get_colony_ship_build_prerequisite_*` | `BaseStore.get_build_colony_ship_blocked_reason_key()` + prereq keys (`KEY_COLONY_*`) | `production_panel.gd` colony section + prerequisite hover lines | `colony_ships` in base; colonization ops in session save | **Low for this plan** — intentionally out of scope |

### Per-target mission limits

| System | Current behavior | Where enforced | Risk |
|--------|------------------|----------------|------|
| **Scan per object** | **One active scan job per target** — second drone blocked | `AutomationController.launch_scan_drone()` passes `scan_active = get_active_scan_drone_count_for_target() > 0` into `GameSession.can_scan_object()` → `KEY_SCAN_ALREADY_IN_PROGRESS` | **High** — requires shared progress model |
| **Mine per object** | **Multiple ships allowed** — no “already mining” gate | `launch_mining_ship()` only checks idle ship + resource/depletion gates; `get_assigned_mining_ship_count(target_id)` already counts multiple | **Low** — verify depletion + UI clarity |
| **Investigate per signal** | **One active mission per object** (correct) + **global parallel cap 2** | `_active_missions.has(oid)` → `REASON_IN_PROGRESS`; `get_active_investigate_count() >= get_max_active_probes()` | **Medium** — remove global cap, keep per-signal rule |

### Production cost model (today)

| Source | Behavior |
|--------|----------|
| `data/production/*.tres` | Flat `cost` per unit type (SD: Iron 90, MS: Iron 240 + Si 40, SP: Iron 40, CS: gated bundle) |
| `ProductionDefinition` | No `built_count`, no multiplier fields |
| `BaseStore.get_production_cost()` | Returns catalog cost unchanged for every build |
| `GameBalanceDefinition` | Exports `scan_drone_2_cost`, `mining_ship_2_cost`, `survey_probe_unit_cost` — **not referenced in scripts** (dead/legacy candidates) |

### Scan mission model (today)

| Question | Finding |
|----------|---------|
| One scan mission per object? | **Effectively yes** — gate blocks second assignment while `scan_drone_target_by_unit_id` has any entry for target |
| `GameSession` “scan already in progress”? | **Yes** — `can_scan_object(..., target_has_active_scan)` → `KEY_SCAN_ALREADY_IN_PROGRESS` |
| Where is target stored per drone? | `AutomationController.scan_drone_target_by_unit_id: unit_instance_id → target_id` |
| AutomationStore role? | One `create_scan_mission()` per outbound drone until arrival; mission removed on `complete_automation_mission()` at arrival |
| Orbit / return | On arrival: `_complete_scan_mission()` sets scan state + reward **immediately**, then `transfer_orbit_to_base()`; drone stays in `scan_drone_target_by_unit_id` until return |
| Shared progress? | **No** — each drone has `work_duration` but completion fires on `arrived_at_target`, not shared progress bar |

### Mining extraction (today)

| Question | Finding |
|----------|---------|
| Block one MS per object? | **No runtime block** |
| Shared resource pool? | **Yes** — `ObjectScanStore.remaining_resources_by_object` |
| Atomic extraction? | **Per call** — `extract_resource_amount()` clamps to `mini(requested, remaining)` and writes back synchronously (single-threaded `_process` safe) |
| Depleted handling? | `can_mine_object()` checks `is_object_depleted` / `has_remaining_resources_among`; active ships use runtime status + return logic |
| Cargo save? | `mining_ship_runtime_by_unit_id` saved via `AutomationSaveService.build_mining_missions_array()` |

### Upgrade “Control” reinterpretation baseline

Current upgrade `.tres` files **do not increase fleet caps**. They affect scan speed, mining rate/cargo, layer unlocks, storage capacity:

| Category | Files | Current effect (not control caps) |
|----------|-------|-----------------------------------|
| ScanDrone | `scan_drone_0_base.tres`, `_1_`, `_2_` | `scan_duration_multiplier`, `unlock_scan_layer`, `mining_yield_bonus_per_support_drone_percent` |
| MiningShip | `mining_ship_0_base.tres`, `_1_`, `_2_` | `mining_rate_multiplier`, `cargo_capacity_percent`, `unlock_mining_layer` |
| Storage | `storage_0..3` | `storage_capacity_units` |

The name **“Control Limits”** in `GameBalanceDefinition` refers to **fleet caps**, not upgrade tiers. Any “Drone Control / Mining Control / Probe Control” reinterpretation is **future design**, not current upgrade titles.

### Balance telemetry (today)

`scripts/debug/balance_telemetry_logger.gd` logs:

- `units.scan_drone.max_count` / `mining_ship.max_count` from `GameSession.get_max_base_*`
- Flat `production_gates.*.cost` (no “next unit index” or scaling)
- `get_active_scan_drone_count_for_target()` exists in `AutomationController` but **not logged per target**
- Milestones like `scan_drone_2_built`, `mining_ship_2_built` assume old cap of 2

### Related audit context

| Report | Relevance |
|--------|-----------|
| `postfix_colonyship_balance_verification_v0_1.md` | **NOT TESTED** — ColonyShip timing still unknown post-fix; unlimited units will shift Iron/Storage curves |
| `expansion_loop_postfix_closure_v0_1.md` | Expansion structurally **PASS**; MS2 ~12 min and Storage-full ~42 min are open **balance** issues that scaling/multi-unit will amplify |

---

## Target Design

### ScanDrone (SD) — unlimited production + multi per object

- **Production:** No hard cap; balance via `cost = base_cost × multiplier^built_count` (see Scaling Cost Model).
- **Per object:** Multiple SD may support **one shared scan progress** per active scan layer (Basic / Deep / Special).
- **Stacking:** `effective_scan_speed = base_speed × stacking_factor(assigned_drone_count, upgrade_bonuses)` with **diminishing returns** (e.g. sqrt, soft cap, or tiered efficiency table).
- **Rewards:** **One** `set_object_scan_state`, **one** SurveyData grant, **one** resource reveal init per layer completion — never per drone.
- **Orbit:** Supporting drones travel → orbit → contribute to shared timer → return on completion or abort.
- **Idle gate:** Still require at least one idle drone to assign another (unless redesign allows redirect).

### MiningShip (MS) — unlimited production + multi per object

- **Production:** Unlimited with scaling costs.
- **Per object:** Multiple MS already supported; formalize as product rule.
- **Extraction:** All ships draw from same `remaining_resources` pool; no duplication.
- **Depletion:** When pool empty, block new launches; active ships finish cargo and return.
- **Storage full:** Existing `WAITING_FOR_STORAGE` behavior unchanged.
- **Optional:** Multi-ship coordination overhead (diminishing rate per extra ship) if economy explodes — **candidate only**, not default v0.1 implementation.

### SurveyProbe (SP) — unlimited production, constrained investigate

- **Production:** Unlimited with scaling costs (Iron base from `survey_probe.tres` / balance).
- **Per signal:** **Exactly one** active Investigate mission (`_active_missions` keyed by `object_id`) — **keep**.
- **Parallel signals:** Allow N simultaneous investigates where N = available probes (remove `max_active_probes_start` gate).
- **Reveal:** One reveal per signal completion — existing path.
- **Consume-on-use:** Keep single-use probe consumption.

### ColonyShip (CS) — unchanged special case

- Remain **strongly gated** (prereqs, build time, cost bundle).
- **Not** subject to unlimited production scaling.
- Colony timing remains primary expansion milestone; telemetry must still capture CS affordability separately.

---

## Scaling Cost Model

**Proposed formula (design only — no values committed):**

```
next_cost(resource) = base_cost(resource) × pow(multiplier, built_count)
```

Where `built_count` = current owned count for that unit type at the base (or total built-this-run for telemetry).

### Candidate multipliers (not final)

| Unit | Base cost source | Multiplier candidate | Notes |
|------|------------------|----------------------|-------|
| **ScanDrone** | `data/production/scan_drone.tres` (Iron 90) | **1.15 – 1.25** | Gentle early curve; MS2 audit band ~12 min becomes player choice not cap |
| **MiningShip** | `data/production/mining_ship.tres` (Fe 240, Si 40) | **1.18 – 1.30** | Silicon pressure intentional |
| **SurveyProbe** | `data/production/survey_probe.tres` (Iron 40) | **1.12 – 1.20** | Cheaper unit, milder curve |
| **ColonyShip** | `colony_ship.tres` + prereqs | **Excluded** or **one-shot** only | No spam path |

### Implementation shape (future)

| Layer | Suggested location |
|-------|-------------------|
| Data | New fields on `ProductionDefinition` or `GameBalanceDefinition`: `cost_multiplier`, `cost_curve_mode` |
| Helper | `GameSession.get_scaled_production_cost(production_id, base_id)` — read-only first (Step 1) |
| Spend path | `BaseStore.build_*` uses scaled cost, not flat `get_production_cost()` |

**Do not** wire multipliers into `.tres` until Step 1 helper + telemetry prove curve shape.

---

## Upgrade Reinterpretation

**Rule:** Do not delete existing upgrade `.tres` or break layer unlocks. Add or remap **meaning** onto tiers.

### Drone Control (scan_drone category)

| Option | Effect |
|--------|--------|
| A | Reduces SD **cost scaling** exponent or multiplier step per tier |
| B | Improves **scan efficiency** (existing `scan_duration_multiplier`) — already partially there |
| C | Improves **multi-drone stacking** efficiency (new field e.g. `scan_stacking_efficiency_bonus`) |

**Recommendation:** **C + B** — keep scan speed upgrades; add stacking bonus at tier I/II so multi-SD feels like an upgrade payoff.

### Mining Control (mining_ship category)

| Option | Effect |
|--------|--------|
| A | Reduces MS cost scaling |
| B | Improves coordination — reduce per-ship overhead when multiple MS on same body |
| C | Existing rate/cargo upgrades remain |

**Recommendation:** **B + C** — optional small multi-ship efficiency bonus; cost scaling handled primarily by production curve.

### Probe Control (new or survey balance group)

| Option | Effect |
|--------|--------|
| A | Raises **max parallel investigates** across different signals (replaces `max_active_probes_start`) |
| B | Reduces SP cost scaling |
| C | Faster investigate duration |

**Recommendation:** **A** as upgrade-gated parallel cap (e.g. 2 → 3 → 4) while **per-signal = 1** stays absolute.

---

## Multi ScanDrone Same Target

### Target behavior

```
Object scan job (per layer):
  target_id
  target_scan_state
  progress_seconds / progress_normalized
  assigned_drone_unit_ids[]
  base_scan_duration
  effective_speed_multiplier
```

### Design rules

1. **One scan state transition** per layer completion.
2. **One SurveyData reward** per completion.
3. **Assign another ScanDrone** increases `effective_speed`, not reward count.
4. **Diminishing returns:** e.g. `speed = base × (1 + 0.7 + 0.45 + 0.3 + …)` or `base × sqrt(n)` capped.
5. **Abort:** Removing drones reduces speed; progress preserved.

### Code touchpoints (future implementation)

| File | Change type |
|------|-------------|
| `game_session.gd` | Remove / bypass `target_has_active_scan` block; add read-only shared job API |
| `automation_controller.gd` | Shared job dict; multiple drones per job; single `_complete_scan_mission` |
| `automation_store.gd` | Possibly extend mission dict with `shared_job_id` |
| `system_ui_controller.gd` / `object_info_panel.gd` | “Assign another ScanDrone”, assigned count, ETA |
| `automation_save_service.gd` | Persist shared job + assignees |

### Open questions

- Should second drone join **in-flight** scan or only at start?
- Rescan (non-progression) scans — same stacking rules?
- ScanDrone orbit support for mining (`get_active_scan_drone_support_count_for_target` caps at **1**) — orthogonal; do not conflate with scan stacking.

---

## Multi MiningShip Same Target

### Target behavior

- **Already largely true** — document and harden.
- All ships share `remaining_resources_by_object`.
- `extract_resource_amount()` is synchronous — safe for multi-ship in single thread.
- UI should show **active MS count** and **depletion state**.

### Hardening checklist

| Item | Action |
|------|--------|
| Depletion race | Keep single-threaded extraction; add assert/log if `extracted < requested` while remaining > 0 |
| New launch on depleted body | Ensure `can_mine_object` stays false |
| Performance | Many MS on one body + many bodies — profile `_process` mining loop |
| Optional overhead | Design-only: total rate `= sum(ship_rates) × coordination_factor(n)` |

### Code touchpoints

| File | Notes |
|------|-------|
| `automation_controller.gd` | `get_assigned_mining_ship_count`, runtime dict — extend UI exposure |
| `game_session.gd` | `can_mine_object` — no per-target busy check today |
| `object_info_panel.gd` | Show assigned count, “Assign MiningShip” when idle ship available |

---

## SurveyProbe Rule

| Rule | Keep / Change |
|------|---------------|
| SP production unlimited (with scaling) | **Target** |
| One active Investigate per signal (`object_id`) | **Keep** — `SurveyProbeMissionController._active_missions` |
| Multiple different signals in parallel | **Target** — remove `max_active_probes_start` soft cap |
| Probe consumed on launch | **Keep** |
| No duplicate reveal | **Keep** — `REASON_ALREADY_KNOWN` / completion path |

### Code touchpoints

| File | Change |
|------|--------|
| `survey_probe_mission_controller.gd` | Remove or replace `get_max_active_probes()` with upgrade-driven limit |
| `game_balance_definition.gd` | Deprecate `max_active_probes_start` or repurpose as upgrade base |
| `object_info_panel.gd` | Investigating state disables second probe on same signal only |

---

## UI Changes Needed

| Area | Current | Target |
|------|---------|--------|
| **ProductionPanel** | Button disabled on `KEY_BUILD_*_LIMIT` | Never show limit for SD/MS/SP; disable only on **insufficient resources**; show **next scaled cost** in hover |
| **ProductionPanel CS** | Unchanged gated behavior | No change |
| **ObjectInfo — Scan** | Blocked when scan active (`KEY_SCAN_ALREADY_IN_PROGRESS`) | Show progress; button **“Assign ScanDrone”** if idle drone exists |
| **ObjectInfo — Scan meta** | Scan status label only | Add: `assigned_drones`, `scan_speed`, `ETA` |
| **ObjectInfo — Mine** | Mine button if idle ship | **“Assign MiningShip”**; show `active_ships_on_target` |
| **ObjectInfo — Investigate** | Blocked per signal + global cap | Investigating on signal; block duplicate on **same** signal only |
| **UpgradePanel** | Speed/cargo/layer copy | Future copy updates for stacking / parallel probes (no tooltip_text) |

**Files:** `scripts/ui/system/production_panel.gd`, `scripts/ui/system/object_info_panel.gd`, `scripts/system/controller/system_ui_controller.gd`, `resources/definitions/gate_ui_text_definition.gd` (retire or repurpose limit strings).

---

## Save/Load Impact

**Current:** `SaveManager.SAVE_VERSION = 1`

| Data | Saved today | Multi-unit impact |
|------|-------------|-------------------|
| Base fleet counts | `bases.*.drones/mining_ships/survey_probes` | Grows unbounded — OK |
| Scan missions | `automation.runtime.scan_missions[]` per drone | Shared job may need `job_id`, `assignees[]`, `progress` |
| Mining missions | `mining_missions[]` per ship with cargo | Multiple per same `target_id` already valid |
| Remaining resources | `object_scans.remaining_resources_by_object` | Shared pool — unchanged |
| Investigate | Not saved (cancelled) | No change for v0.1 |

### Compatibility recommendation

| Approach | When |
|----------|------|
| **Stay SAVE_VERSION 1** | If shared scan job can serialize as multiple drone records + implicit shared progress, or progress re-derived on load |
| **SAVE_VERSION 2 + migration** | If mission schema adds required fields old saves cannot default |

**Do not** bump save version in the same PR as unlimited production. If schema changes: separate `docs/design/save_migration_unlimited_production_v2.md` (future).

### Load edge cases

- Old save with 2 drones, new build unlimited — OK.
- Mid-scan load with multiple drones on same target — needs explicit restore tests.
- Survey probe missions lost on load — existing limitation; document for QA.

---

## Telemetry Updates

Extend `BalanceTelemetryLogger` (future code step — not in this doc PR):

| Field | Purpose |
|-------|---------|
| `units.*.count` without misleading `max_count` | Replace with `next_scaled_cost` + `built_count` |
| `production_gates.*.scaled_cost` | Per-unit next buy cost |
| `scan.assigned_drones_per_target` | Dict `target_id → count` |
| `mining.assigned_ships_per_target` | Dict `target_id → count` |
| `scan.shared_job_progress` | If shared job exists |
| `mining.depletion_events` | Time-to-deplete per body |
| `storage.storage_percent` over time | Pressure under unlimited MS |
| Milestones | Deprecate `*_2_built`; add `sd_build_5`, `ms_build_5`, `first_multi_scan`, `first_multi_mine` |
| Colony | `colony_ship_cost_gap` at 30/45 min with unlimited economy |

Enables updating `postfix_colonyship_balance_verification_v0_1.md` with real curves after Step 7.

---

## Step-by-Step Implementation Plan

| Step | Description | Files (primary) | Validation |
|------|-------------|-----------------|------------|
| **1** | Scaling production cost **helper** (read-only); no gate changes | `game_session.gd`, `production_definition.gd` or `game_balance_definition.gd`, debug print | Unit tests / debug REPL: cost at n=0,1,5,10 |
| **2** | Remove hard production limit SD/MS/SP gates; **CS unchanged** | `base_store.gd`, `gate_ui_text_definition.gd` | Build 3rd SD/MS in Editor |
| **3** | ProductionPanel shows **scaled next cost** | `production_panel.gd` | Hover reflects rising cost |
| **4** | **Multi-MS hardening** — UI assigned count, depletion QA | `automation_controller.gd`, `object_info_panel.gd`, `system_ui_controller.gd` | 3 MS same asteroid, single pool depletes |
| **5** | **Multi-SD shared progress** — remove `KEY_SCAN_ALREADY_IN_PROGRESS` block; single reward | `game_session.gd`, `automation_controller.gd`, `automation_save_service.gd` | 2 SD same body, one Basic completion |
| **6** | Rework upgrade meaning (stacking / parallel probes) | `data/upgrades/**`, `upgrade_definition.gd`, controllers | Upgrades affect stacking not caps |
| **7** | Telemetry + **30-min balance run** | `balance_telemetry_logger.gd`, audit docs | JSON shows scaled costs + multi-unit |

**Between steps:** run 5–10 min smoke test; no balance number commits until Step 7 data reviewed.

---

## Risks

| Risk | Severity | Why | Mitigation |
|------|----------|-----|------------|
| Economy explodes too fast | **High** | Removing caps + multi-MS without scaling | Scaling costs first; telemetry at 10/20/30 min; optional mining coordination overhead |
| Storage fills too early | **High** | More MS → more throughput | Storage upgrades + scaling; monitor `storage_full` milestone |
| Scan becomes trivial | **High** | Multi-SD stacking without diminishing returns | Diminishing returns; travel time still linear per drone |
| Mining depletes bodies too quickly | **Medium** | N ships × rate | Shared pool already; tune rates after telemetry |
| UI becomes unclear | **Medium** | Assign vs blocked states multiply | ObjectInfo shows counts + ETA; consistent verbs |
| Save/Load mission data breaks | **High** | Shared scan job schema | Stay v1 if possible; migration plan if not; QA mid-scan save |
| Old “Control” upgrades meaningless | **Medium** | Caps removed | Step 6 reinterpretation before public test |
| ColonyShip becomes too early | **Medium** | Faster Iron pipeline | Keep CS gates; re-verify with 30-min run |
| Performance with many units | **Medium** | More nodes in `automation_root` | Pool units; cap visual instances vs logical count (future) |
| Duplicate scan rewards | **Critical** | Multiple `_complete_scan_mission` calls | Single completion owner per shared job |
| Survey probe global cap removed too aggressively | **Low** | Many parallel investigates | Upgrade-gated parallel cap |

---

## Recommendation

**Start with design approval + static audit sign-off (this document). Do not implement all steps at once.**

**First implementation step after approval:** **Step 1 — read-only scaled cost helper** + debug output in `BalanceTelemetryLogger` (next cost at current `built_count`). No gate changes, no `.tres` edits, no save changes.

This validates the economic curve before removing caps or touching scan mission architecture.

---

## Affected Files (reference index)

| Category | Paths |
|----------|-------|
| Production data | `data/production/scan_drone.tres`, `mining_ship.tres`, `survey_probe.tres`, `colony_ship.tres` |
| Upgrades | `data/upgrades/scan_drone/*`, `mining_ship/*`, `storage/*` |
| Balance profile | `data/balance/v0_1_balance.tres`, `resources/definitions/game_balance_definition.gd` |
| Definitions | `resources/definitions/production_definition.gd`, `upgrade_definition.gd`, `gate_ui_text_definition.gd` |
| Session / stores | `scripts/autoload/game_session.gd`, `scripts/autoload/stores/base_store.gd`, `object_scan_store.gd`, `automation_store.gd` |
| Controllers | `scripts/system/controller/automation_controller.gd`, `survey_probe_mission_controller.gd` |
| Save | `scripts/system/automation/automation_save_service.gd`, `scripts/autoload/save_manager.gd` |
| UI | `scripts/ui/system/production_panel.gd`, `upgrade_panel.gd`, `object_info_panel.gd`, `system_ui_controller.gd` |
| Telemetry | `scripts/debug/balance_telemetry_logger.gd` |
| Audits | `docs/audits/postfix_colonyship_balance_verification_v0_1.md`, `expansion_loop_postfix_closure_v0_1.md` |

---

## Implementation Status (code)

| Step | Status | Notes |
|------|--------|-------|
| **Step 1** — read-only `get_scaled_production_cost_preview*` | **Done** | Refactored to `get_scaled_production_cost` single source of truth |
| **Step 1b** — `production_lifetime_counts` per base | **Done** | Stable count source for preview; increments on `build_*`; save-v1 compatible lazy migrate |
| **Step 2a** — remove SD/MS hard build limits | **Done** | Cost-only gating; telemetry `hard_limit_removed_for_build` |
| **Step 2b** — activate scaled costs for SD/MS/SP spend | **Done** | BaseStore gates + spend; ProductionPanel + telemetry show actual scaled cost; CS excluded |
| **Step 3+** | **Pending** | Multi-scan, multi-MS hardening, multiplier .tres migration |

---

## Acceptance (this document only)

1. Only `docs/design/unlimited_production_multi_unit_target_plan_v0_1.md` created.  
2. No code / scene / data files changed.  
3. Plan separates production scaling, multi-scan, multi-mining, SurveyProbe rules.  
4. Affected files named.  
5. Small implementation steps defined.  
6. No Save-v2 without separate migration plan.  
7. `tooltip_text` remains 0.
