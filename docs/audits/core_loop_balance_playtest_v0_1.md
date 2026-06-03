# Core Loop Balance Playtest v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Scope:** v0.1 **Early Loop** — Round 1 only (stop at **12:00**).  
**Method:** Playtest analysis report — **no code, scene, or balance data changes.**

---

## Test method and limitations

| Item | Detail |
|------|--------|
| **Intended procedure** | New Game → first signal → Investigate → Basic Scan → Mine → first delivery → check affordances → **stop at 12:00** |
| **Data source for this report** | Primary: manual session recorded in `docs/audits/phase_3_mining_loop_proof_v0_1.md` (same build, solar-system / earth, representative orbit). Milestones **0:00–~2:30** are **measured**; **2:30–12:00** are **projected** from repeated mining cadence and resource table in that doc. |
| **Fresh 12:00 stopwatch run** | **Not executed in this audit environment** (Godot Editor playtest required on developer machine). Times below should be **re-validated** with a dedicated 12-minute capture. |
| **Reference curve** | User target pacing (0–45 min design intent) vs measured/projected actual |

**Start state (data):** `default_start.tres` + `GameBalanceDefinition` — **100 Iron**, **2 Survey Probes**, **1 Scan Drone**, **1 Mining Ship**, storage **1000**, **2 signals** visible (design intent at 0 min).

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Early loop (12 min) playable?** | **Yes** — core chain Investigate → Scan → Mine → Storage works; next actions understandable |
| **Biggest blocker** | **None** for completing first loop; **no hard soft-lock** observed in reference session |
| **Biggest balance deviation vs target curve** | **MS2 (2nd mining ship) at 7–9 min** — data cost **240 Iron + 40 Silicon**; first body cargo is mostly **Si/C/Cu**, start **Iron stays 100** until many runs or iron-heavy targets → **MS2 likely after 12 min**, not 7–9 min |
| **35–45 min full run recommended?** | **Yes**, with notes — validate MS2/Deep Scan/ColonyShip pacing on a timed full run |

---

## Timeline

Measured segment (from mining loop proof session) + projected continuation to 12:00. Resources = **base storage** unless noted.

| Time | Event | Resources (base storage) | UI / state | Problem / note |
|------|--------|---------------------------|------------|----------------|
| **0:00** | New Game | Iron **100**; Survey Data **0**; 2 probes, 1 drone, 1 ship | Star + earth base visible; 2 signals on map | Matches target 0 min |
| **0:10** | First signal selected | — | ObjectInfo: SIGNAL panel | Player-dependent; **~10 s** assumed |
| **0:12** | Investigate started | — | Investigate button → probe outbound | — |
| **0:30** | Object **KNOWN** (reveal) | Survey Data **+5** → **5**; probes **1** left | Marker gone; body visible; TopHUD updates | **Ahead** of 1 min target; orbit-dependent |
| **0:32** | Basic Scan started | — | Scan enabled; button **"Scan"** | — |
| **0:36** | Basic Scan **complete** (session marker) | Survey Data **+10** → **15** | Drone returns; resources visible on object | Proof lists **36 s** from start; **ahead** of 2–3 min scan milestone |
| **0:38** | Mining started | — | Mine enabled after known + basic scan | — |
| **0:53** | **First mining delivery** | SD **15**, Si **5**, C **10**, Cu **5**, Iron **100** | Storage panel refresh; cargo cleared | **Ahead** of 2–3 min delivery target; cargo **Si/C/Cu** not Iron |
| **0:53** | Afford: **Survey Probe** build (40 Iron) | Iron **100** | Production: probe buildable | **PASS** — target “SD2/probe” by 4–5 min easily met for probe |
| **0:53** | Afford: **Scan Drone #2** (90 Iron) | Iron **100** | Production: second drone buildable | **Ahead** of needing second drone for parallel scans |
| **~2:30** | **Projected** 2nd mining delivery | Si **~12**, C **~24**, Cu **~12** (interp.) | Repeat mine same body | Extrapolated from proof “after 2nd run” table |
| **~3:30** | **Projected** **Storage Upgrade I** affordable | Cu **≥10**, Iron **≥30** | Upgrade panel: 30 Iron + 10 Copper | **Ahead** of 10–12 min first-upgrade target |
| **~4:00** | **Projected** 3rd mining delivery | Si **~17**, C **~34**, Cu **~17** | Per proof table after 3rd run | — |
| **~4–5 min** | Target: SD2 / extra probe | SD **15** (3× pulse at 5 SD) | Sensor pulse / probe production | **Survey Data** threshold met; probe rebuild optional |
| **~7–9 min** | Target: **MS2** | Iron **100** still; Si **~17–25** projected | MS2 gate: **240 Iron + 40 Si** | **Behind target** — **40 Si** not reached by 12 min in proof trajectory |
| **7–9 min** | Target: MS2 (actual) | — | MS2 **blocked** (not enough Si; Iron sufficient) | **Balance** — not UI bug |
| **~10–12 min** | Target: first upgrade | — | **Storage I** likely **already bought ~3:30** | Upgrade pacing **faster** than 10–12 min target |
| **12:00** | **Round 1 stop** | Iron **100**; SD **15**; Si/Cu/C **growing**; MS2 **not** bought | Player can mine, scan, build probe/drone; **MS2 / Deep Scan** next goals | Loop **motivating**; next step clear: **more mining** or **other body** |

---

## Target vs actual

| Target time | Intended milestone | Actual (measured / projected) | Δ | Rating |
|-------------|-------------------|------------------------------|---|--------|
| **0 min** | Star + base, 2 signals, 1D/1MS/2 probes, 100 Iron | **0:00** — matches data | **0** | **On target** |
| **1 min** | First signal investigated / object visible | **0:30** KNOWN | **−30 s** | **Ahead** (good) |
| **2–3 min** | Basic Scan + first mining delivery | Scan **0:36**, delivery **0:53** | **−1.5 to −2 min** | **Ahead** (good) |
| **4–5 min** | SD2 or extra probe | SD **15** @ 0:53; probe **40 Iron** anytime | **Early** | **On/ahead** |
| **7–9 min** | MS2 possible | **Not projected** by 12 min (Si shortfall) | **+many min** | **Behind** (balance) |
| **10–12 min** | First upgrade | **Storage I ~3:30** projected | **−6 to −8 min** | **Ahead** (good) |
| **15–18 min** | Deep Scan or MS3 | *Not in Round 1 scope* | — | **Deferred** |
| **20–25 min** | Storage/control relevant | Storage **1000** — low pressure early | — | **Deferred** |
| **30–35 min** | ColonyShip prep | *Not in Round 1 scope* | — | **Deferred** |
| **35–45 min** | ColonyShip buildable | *Not in Round 1 scope* | — | **Deferred** |

---

## Friction log

| Moment | Problem | Category | Severity | Smallest fix |
|--------|---------|----------|----------|--------------|
| **0:30–0:53** | Travel times vary strongly with orbit | **Balance** | Low | Document in tutorial; optional balance on travel bands |
| **After first mine** | `remaining_amount` at **12.00k** does not visibly drop on small trips | **UI** | Low | Finer format under 20k or show delta on unload (no tooltip) |
| **~7–9 min (target)** | MS2 feels “late” vs design curve | **Balance** | Medium | Lower `mining_ship_2` Si cost **or** earlier iron-bearing body / higher Si yield — **data only**, separate change |
| **MS2 blocked** | Gate needs **240 Iron + 40 Si**; early cargo is Si-light on test body | **Balance** | Medium | Same as above; verify intentional for 12 min pacing |
| **Scan button** | Always **"Scan"** (not “Basic Scan”) | **UI** | Info | Acceptable; rescan rules in gate text |
| **Investigate vs Scan order** | New player must learn SIGNAL → KNOWN → Scan | **UI** | Low | One-line objective hint in ObjectInfo (copy only) |
| **None observed** | Soft-lock, lost resources, save break in 12 min window | **Bug** | — | — |

---

## Economy notes (through 12:00)

### Iron income (minute 0–12)

| Source | Amount | When |
|--------|--------|------|
| Start | **+100** | 0:00 |
| Mining (test body, 3 projected runs) | **~0** to base Iron | Cargo was **Si/C/Cu** on recorded body |
| **Total Iron ~100** at 12 min | Unless player mines iron-rich deposit or sells/trades N/A | MS2 **240 Iron** affordable on paper; **Si** is gate |

### Survey Data income (minute 0–12)

| Source | Amount | When |
|--------|--------|------|
| Investigate reward | **+5** | ~0:30 |
| Basic Scan (progression) | **+10** | ~0:36 |
| **Total ~15** by 0:53 | Pulse cost **5** each → **3 pulses** possible | Matches “SD2” interpretation (≥2 SD) by 4–5 min |

### Affordance timing (actual / projected)

| Item | Cost (data) | When reachable | vs target |
|------|-------------|----------------|-----------|
| **Survey Probe** (build) | 40 Iron | **~0:30+** | Before 4–5 min ✓ |
| **Scan Drone #2** | 90 Iron | **~0:53** | Early ✓ |
| **MS2** | 240 Iron + 40 Si | **Not by 12:00** (projected) | **Behind** 7–9 min target |
| **Storage Upgrade I** | 30 Iron + 10 Cu | **~3:30** projected | **Before** 10–12 min target ✓ |
| **Mining Ship Upgrade I** | 40 Iron + 20 Si + 10 Cu | **~8–10 min** projected (Si) | Near first-upgrade window |

### Storage relevance

| Item | Assessment |
|------|------------|
| Capacity **1000** at start | **Not relevant** in first 12 min (used **~4%**) |
| Storage full | Not reached in reference session |
| **Conclusion** | Storage pressure correctly **deferred** past Round 1 |

---

## UI / feedback notes

| Check | Result | Notes |
|-------|--------|-------|
| Block reasons understandable? | **PASS** | Gate keys → English via `gate_ui_texts` / panel blocked_reason |
| No Godot `tooltip_text`? | **PASS** | Repo grep **0** (`*.gd` / `*.tscn` / `*.tres`) |
| Action buttons clear? | **PASS WITH NOTES** | Investigate / Scan / Mine enabled in sequence; Scan label generic |
| Storage visible? | **PASS** | TopHUD + Storage panel after delivery |
| Mining/Scan status visible? | **PASS** | Unit motion + ObjectInfo scan state / resources |
| Depleted / storage full | **Not reached** in 12 min window | Prior proof: behavior **PASS** when forced |

**Clarity — “what next?”**

| Minute | Player likely next step | Clear? |
|--------|-------------------------|--------|
| 0:00 | Select a signal | **Yes** |
| 0:30 | Scan the revealed body | **Yes** |
| 0:53 | Mine, or build probe/drone, or pulse | **Yes** (many valid) |
| 12:00 | Keep mining for Si / try another body / upgrade storage | **Yes** |

---

## Recommendation

**Proceed with a 35–45 minute full-loop playtest** (Round 2), using a **stopwatch and written log**.

**PASS WITH NOTES — at most 1–3 balance hypotheses for a future data-only pass (do not apply in this step):**

1. **MS2 timing:** Consider **lowering `mining_ship_2` Silicon from 40 → 25–30** *or* ensuring first mineable body has meaningful **Iron** in `remaining_resources` if MS2 by ~8 min is a hard design goal.  
2. **Remaining UI:** Consider sub-**10k** numeric format on ObjectInfo remaining row so first trips show extraction feedback.  
3. **Optional:** If Scan should read **“Basic Scan”** on first progression scan only — copy/UI label only, not mechanics.

**Do not start** ColonyShip/colony balance changes until Round 2 confirms 30–45 min curve.

---

## Round 2 checklist (for human tester)

When running the dedicated 12:00 + 45:00 sessions, log:

- [ ] Exact wall-clock per milestone (table in this doc)  
- [ ] `blocked_reason` text when Mine/Scan/Build disabled  
- [ ] Base storage screenshot at 0:53, 6:00, 12:00  
- [ ] Whether MS2 affordable before 12:00  
- [ ] Whether Deep Scan affordable by 18:00  
- [ ] ColonyShip prerequisites status at 35:00  

---

## Acceptance (this report)

1. No code, scene, or data files were changed.  
2. Only `docs/audits/core_loop_balance_playtest_v0_1.md` was created.  
3. Timeline filled with times (measured + projected; re-validation requested).  
4. Issues classified as Bug / UI / Balance.  
5. No balance values changed in this step.  
6. Exactly one next step: **35–45 min full-loop playtest**.  
7. `tooltip_text` remains **0**.
