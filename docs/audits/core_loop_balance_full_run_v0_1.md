# Core Loop Balance Full Run v0.1

**Date:** 2026-05-20  
**Engine:** Godot 4.6.1  
**Scope:** Round 2 — **35–45 min** full loop (New Game → ColonyShip preview / buildability).  
**Method:** Playtest analysis — **no code, scene, or balance data changes.**

---

## Test method and data sources

| Item | Detail |
|------|--------|
| **Intended procedure** | New Game → stopwatch 0:00 → normal play → log milestones → stop at **45:00** (or earlier if ColonyShip clearly reachable) |
| **Executed in this audit** | **No interactive Godot session** (Godot binary not available in audit shell). |
| **Measured segment (stopwatch)** | `docs/audits/phase_3_mining_loop_proof_v0_1.md` — same representative run (solar-system, earth orbit; first body cargo **Si/C/Cu** consistent with **Moon**-style deposits). Times **0:00–0:53** are **verified manual stopwatch** from that session. |
| **Extended segment (3:00–45:00)** | **MODELED** — single-body + second-signal pacing model using measured cargo deltas, production/upgrade costs from `data/production/*.tres` and `data/upgrades/**/*.tres`, colony rules from `GameSession` / `GameBalanceDefinition`. **Replace with live Round 2 stopwatch when run in Editor.** |
| **Round 1 cross-check** | `docs/audits/core_loop_balance_playtest_v0_1.md` (PASS WITH NOTES; MS2 late hypothesis). |

**Legend:** **M** = measured stopwatch · **~** = modeled estimate · **P** = pending live confirmation

---

## Summary

| Item | Result |
|------|--------|
| **Overall** | **PASS WITH NOTES** |
| **Full loop playable to 45 min?** | **Yes** — discover → investigate → scan → mine → build → upgrade remains coherent; no soft-lock observed in static + early measured path |
| **ColonyShip reachable / buildable by 45:00?** | **No (MODELED)** — prerequisites can complete mid-run; **build cost not affordable** and **350 Ice not obtainable** from deposits (`Ice.is_deposit_resource = false`, no `Ice` on solar bodies) |
| **Biggest blocker** | **ColonyShip Ice cost (350)** with no deposit source — build stays blocked on resources even if prereqs met |
| **Biggest balance deviation** | **ColonyShip 35–45 min target** vs **~45+ min** resource wall (1500 Fe, 300 Si, 150 SD, 350 Ice) + **MS2 ~14–16 min (MODELED)** vs **7–9 min** design target |
| **Biggest UI clarity issue** | **Remaining resources** at **12.00k** format hides small extraction steps (carried from Round 1); colony prereq list is clear, **Ice vs Water** distinction is not |
| **Balance changes allowed after this step?** | **Yes** — with notes; recommend **one** data pass after a **live** 45:00 confirmation run |

---

## Timeline

Resources = **Earth base storage** unless noted. Purchases = player actions in modeled optimal-ish path (earth → moon iron/si, upgrades before MS2).

| Zeit | Event | Ressourcen (Auszug) | Gekauft / gebaut | Aktuelles Ziel | Problem / Notiz |
|------|--------|---------------------|------------------|----------------|-----------------|
| **0:00** **M** | New Game | Fe **100**, SD **0**, 2 probes, 1 drone, 1 MS | — | Signal wählen | Matches design 0 min |
| **0:10** **~** | First signal selected | — | — | Investigate | Player-dependent |
| **0:12** **~** | Investigate started | — | — | Wait reveal | Orbit-dependent travel |
| **0:30** **M** | Object **KNOWN** | SD **5**, probes **1** | — | Basic Scan | **Early** vs 1 min target |
| **0:32** **~** | Basic Scan started | SD **5** | — | — | — |
| **0:36** **M** | Basic Scan **complete** | SD **15** | — | Mine | **Early** vs 2–3 min |
| **0:38** **~** | Mining started | SD **15** | — | First delivery | — |
| **0:53** **M** | **First mining delivery** | SD **15**, Si **5**, C **10**, Cu **5**, Fe **100** | — | Build or re-mine | Cargo **no Fe** this trip |
| **1:05** **~** | Scan Drone #2 **affordable** | Fe **100** | — | Optional SD2/drone | 90 Fe OK |
| **2:10** **~** | 2nd delivery (same body) | Si **12**, C **24**, Cu **12** | — | Storage I or mine | From proof table |
| **3:25** **~** | **Storage Upgrade I** purchased | Fe **70**, Cu **2** | Storage I | More capacity | **Early** vs 10–12 min target |
| **3:50** **~** | **Scan Drone #2** purchased | Fe **0** → need re-mine | Drone #2 | Parallel scans | Fe temporarily low |
| **4:05** **~** | Survey pulse / probe window | SD **15** | — | 2nd signal | SD2/probe target **met** |
| **5:30** **~** | 2nd signal investigated (moon) | SD **20**, probes **0→build** | Probe rebuild **40 Fe** | Moon scan | Second loop starts |
| **6:45** **~** | Moon basic scan complete | SD **30** | — | Mine moon for Fe/Si | Higher Fe richness |
| **7:15** **~** | **Scan Drone Upgrade I** affordable | Cu **≥15**, Fe **≥20** | — | Deep Scan unlock | Deep Scan **gate** cleared |
| **8:00** **~** | **Scan Drone Upgrade I** purchased | — | Scan Up I | Deep Scan earth | 20 Fe + 15 Cu |
| **8:10** **~** | Deep Scan **started** (earth) | SD **30** | — | Wait deep | Needs scan layer 1 |
| **9:55** **~** | Deep Scan **complete** (earth) | SD **55** (+25) | — | Deep mine / next body | ~85s scan + travel **MODELED** |
| **10:30** **~** | **Mining Ship Upgrade I** affordable | Si **≥20**, Cu **≥10** | — | Deep mining | Unlocks deep layer mining |
| **11:15** **~** | **Mining Ship Upgrade I** purchased | — | MS Up I | Colony Protocol proxy ✓ | Prereq for colony |
| **12:00** **~** | **MS2 affordable** (MODELED) | Fe **≥240**, Si **≥40** | — | Buy MS2 | **Late** vs 7–9 min; Fe/Si from moon runs |
| **14:20** **~** | **MS2 purchased** | Fe **0**, Si **0** | Mining Ship #2 | Two-ship economy | Blocked earlier: **Fe 240** + **Si 40** |
| **15:00** **~** | Deep Scan #2 started (moon) | SD **55** | — | 3× deep for colony | 15–18 min deep target **~on edge** |
| **17:10** **~** | Deep Scan #2 **complete** | SD **80** | — | Third body | — |
| **19:30** **~** | 3rd body deep scanned | SD **105** | — | Colony prereqs | **Fully scan 3** prereq **met** |
| **20:00** **~** | Storage **~45%** used (~720/1600) | Mixed stock | — | Hoard for colony | **Low pressure** — Storage I already bought |
| **22:00** **~** | Colony prereqs panel **all green except cost** | Ice source ✓ (Water seen), modules ✓ | — | Farm Fe/Si/SD | **Ice 0/350** in storage |
| **30:00** **~** | ColonyShip **preview** visible | Fe **~550**, Si **~140**, SD **~110**, Ice **0** | — | Colony build | Costs far from 1500/300/150 |
| **38:00** **~** | Control limits felt (2 MS / 2 drones) | — | — | Optimize fleet | **Relevant** but not blocking |
| **45:00** **~** | **Stop** | Fe **~900**, Si **~200**, SD **~125**, Ice **0**, used **~55%** | Colony **not** built | Endgame grind | **Missing** 35–45 colony target |

---

## Target vs Actual

| Zielzeit | Soll-Event | Ist-Zeit | Abweichung | Bewertung |
|----------|------------|----------|------------|-----------|
| 0 min | Start kit | **0:00** **M** | 0 | **On Target** |
| 1 min | First investigated / visible | **0:30** **M** | −30 s | **Early** |
| 2–3 min | Basic Scan + first delivery | **0:36** / **0:53** **M** | −1.5 to −2 min | **Early** |
| 4–5 min | SD2 / extra probe | **~4:05** **~** | ~0 | **On Target** |
| 7–9 min | MS2 möglich | **~12:00** affordable **~** | **+3–5 min** | **Late** |
| 10–12 min | First upgrade | **~3:25** Storage I **~** | −7 min | **Early** |
| 15–18 min | Deep Scan or MS3 | Deep **~9:55** first **~**; MS Up II N/A | Deep **Early**; MS2 **Late** | **Mixed** |
| 20–25 min | Storage/Control relevant | **~20:00** ~45% fill **~** | Slight **Early** pressure | **On Target** (light) |
| 30–35 min | ColonyShip prep | **~30:00** prereqs mostly **~** | On prep timing | **On Target** (prep only) |
| 35–45 min | ColonyShip buildable | **Not at 45:00** **~** | **+∞ / Missing** | **Missing** |

---

## Economy Progression

| Zeitpunkt | Iron | Silicon | Copper | Carbon | Ice | SurveyData | Storage Used / Cap | Notes |
|-----------|------|---------|--------|--------|-----|------------|-------------------|-------|
| 0:00 **M** | 100 | 0 | 0 | 0 | 0 | 0 | 0 / 1000 | Start |
| 0:53 **M** | 100 | 5 | 5 | 10 | 0 | 15 | ~30 / 1000 | No Fe from trip 1 |
| 2:10 **~** | 100 | 12 | 12 | 24 | 0 | 15 | ~50 / 1000 | Proof deltas |
| 3:25 **~** | 70 | 12 | 2 | 24 | 0 | 15 | ~50 / 1600 | Storage I bought |
| 9:55 **~** | 180 | 35 | 25 | 80 | 0 | 55 | ~200 / 1600 | Post deep scan |
| 14:20 **~** | 20 | 8 | 20 | 120 | 0 | 80 | ~350 / 1600 | Post MS2 spend |
| 30:00 **~** | 550 | 140 | 45 | 200 | **0** | 110 | ~650 / 1600 | Colony cost gap |
| 45:00 **~** | 900 | 200 | 60 | 280 | **0** | 125 | ~880 / 1600 | **150 SD** need 150; **Ice blocked** |

---

## Build / Upgrade Milestones

| Item | Cost (data) | Erreichbar um | Gekauft um | Blockgrund (falls nicht) | Bewertung |
|------|-------------|---------------|------------|--------------------------|-----------|
| Survey Probe | 40 Fe | **0:30** **M** | **~5:30** **~** (rebuild) | — | **Early** |
| Scan Drone #2 | 90 Fe | **0:53** **M** | **~3:50** **~** | — | **Early** |
| Mining Ship #2 | 240 Fe + 40 Si | **~12:00** **~** | **~14:20** **~** | Before 12: **Fe/Si** | **Late** vs 7–9 |
| Storage Upgrade I | 30 Fe + 10 Cu | **~0:53** **M** | **~3:25** **~** | — | **Early** |
| Mining Upgrade I | 40 Fe + 20 Si + 10 Cu | **~10:30** **~** | **~11:15** **~** | Si/Cu | **On Target** |
| Scan Drone Upgrade I (Deep) | 20 Fe + 15 Cu | **~7:15** **~** | **~8:00** **~** | — | Enables Deep Scan |
| Scan Drone Upgrade II | 35 Fe + 25 Cu + 15 Al | **~22:00** **~** | **Not bought** **~** | Priorities elsewhere | Optional |
| Mining Upgrade II | 60 Fe + 15 Cu + 35 Al + 10 H | **~28:00** **~** | **Not bought** **~** | Al/H from deep bodies | Mid-late |
| ColonyShip prereqs | See GameSession | **~19:30** **~** all met | — | Ice **discovery** OK via Water | Prep **OK** |
| ColonyShip | 1500 Fe, 300 Si, 350 Ice, 150 SD | **Not by 45:00** **~** | **Not built** | **Ice 0**; Fe/SD short | **Missing** |

---

## Scan / Discovery Progression

| Object | Reveal | Basic Scan | Deep Scan | Special/Full | Notes |
|--------|--------|------------|-------------|--------------|-------|
| Signal 1 → body (earth) | **0:30** **M** | **0:36** **M** | **~9:55** **~** | — | Water = ice-source discovery |
| Signal 2 → moon | **~5:30** **~** | **~6:45** **~** | **~17:10** **~** | — | Fe/Si/Cu mining hub |
| Signal 3 (pulse) | **~12:00** **~** | **~13:30** **~** | **~19:30** **~** | — | 3rd deep → colony scan count |
| Additional | **~25:00+** **~** | ongoing | — | — | SD income too low for 150 SD by 45 |

---

## Mining Progression

| Object | Mining start | Deliveries (45 min) | Key resources | Depleted? | Storage full? | Notes |
|--------|--------------|---------------------|---------------|-----------|---------------|-------|
| Earth (first) | **0:38** **~** | **~4** **~** | Si, C, Cu | No | No | Fe yield low in early mix |
| Moon | **~7:00** **~** | **~12** **~** | Fe, Si, Cu | No | No | Unlocks MS2 iron |
| Mars (optional) | **~25:00** **~** | **~6** **~** | Fe, C | No | No | Faster Fe if visited |
| — | — | — | — | — | — | **No Ice** deliveries possible |

---

## Friction Log

| Zeit | Problem | Kategorie | Schwere | Kleinster Fix |
|------|---------|-----------|---------|----------------|
| 0:53+ | `remaining_amount` 12.00k — no visible drop | UI | Low | Finer format &lt;20k |
| 7–14 | MS2 later than design; **240 Fe** + **40 Si** | Balance | Medium | Lower Si **or** Fe; richer first Fe body |
| 3:25 | Storage I very early vs 10–12 target | Balance | Low | Raise Storage I cost slightly **or** accept as QoL |
| 22:00+ | Colony needs **350 Ice** — **no deposit Ice** | Bug/Balance | **Blocker** | Cost → Water **or** mineable Ice deposits |
| 30:00+ | **150 SurveyData** for colony — only **~125** by 45 | Balance | High | Lower SD cost **or** raise SD rewards |
| 30:00+ | **1500 Fe** colony cost vs **~900** at 45 | Balance | High | Reduce Fe **or** extend session target &gt;60 min |
| 14:00+ | Next goal clear until colony wall | UI | Medium | Show colony **resource progress** % on panel |
| — | `tooltip_text` | — | — | **0** (verified grep) |

---

## Specific checks from Round 1

| # | Question | Result | Evidence |
|---|----------|--------|----------|
| 1 | Kommt MS2 wirklich zu spät? | **Ja** | Affordable **~12:00**, bought **~14:20** vs target **7–9** |
| 2 | Ist 40 Silicon für MS2 zu hoch? | **Teils** — Si gate real, but **240 Fe** equally important until moon Fe | Moon mining required |
| 3 | Storage Upgrade I zu früh? | **Ja (leicht)** | **~3:25** vs 10–12 min target |
| 4 | Deep Scan 15–18 min realistisch? | **Ja (früher)** | First deep complete **~9:55** after Scan Up I **~8:00** |
| 5 | Storage/Control 20–25 relevant? | **Teils** | ~45% at 20 min; **not** a hard blocker with Storage I |
| 6 | ColonyShip 35–45 realistisch? | **Nein** | Prereqs ~19–30 min; **build blocked** Ice + bulk costs |
| 7 | Nächstes Ziel immer klar? | **Ja bis ~25 min**; **Nein ~30+** (colony grind opaque) |

---

## UI / Feedback Notes

| Check | Result | Notes |
|-------|--------|-------|
| `tooltip_text` | **PASS** | **0** matches in `*.gd` / `*.tscn` / `*.tres` |
| Blockgründe | **PASS** | Gate keys + panel `blocked_reason` |
| Storage / resources | **PASS** | TopHUD + storage panel update on unload |
| Remaining progress | **FAIL (minor)** | 12.00k compact hides early deltas |
| Scan/Mine/Investigate | **PASS** | State progression clear |
| Colony prerequisites | **PASS WITH NOTES** | List clear; **Ice vs Water** confusing for **cost** |
| Disabled buttons | **PASS** | Audio + reason text on build fail |

---

## Balance Diagnosis

Max **5** issues — recommendations only, **no data changes in this step**.

### 1. ColonyShip Ice cost unreachable

| Field | Detail |
|-------|--------|
| **Symptom** | Cannot accumulate **350 Ice**; build gate shows not enough resources |
| **Evidence** | `resource_catalog.tres`: Ice `is_deposit_resource = false`; colony cost `data/production/colony_ship.tres`; timeline **Ice 0 @ 45:00** |
| **Likely cause** | Prereq accepts **Water** discovery; **spend** still requires **Ice** id |
| **Smallest change** | Colony build cost: **350 Ice → 350 Water** (or split) |
| **Risk** | Low if Water economy already exists |

### 2. ColonyShip bulk cost vs 45 min session

| Field | Detail |
|-------|--------|
| **Symptom** | ~900 Fe / ~125 SD at 45 vs **1500 Fe / 150 SD** |
| **Evidence** | Economy table @ 45:00; modeled mining throughput |
| **Likely cause** | v0.1 costs tuned for longer or multi-session grind |
| **Smallest change** | Reduce colony Fe **1500→900** and SD **150→100** for v0.1 curve |
| **Risk** | May trivialize late game if not re-tuned after colony loop ships |

### 3. MS2 pacing (7–9 min target)

| Field | Detail |
|-------|--------|
| **Symptom** | MS2 **~12–14 min** not **7–9** |
| **Evidence** | **240 Fe + 40 Si**; first body low Fe; measured Fe **100** @ 0:53 |
| **Likely cause** | Second ship cost + need moon/Fe route |
| **Smallest change** | `mining_ship_2`: **Si 40→28** and/or **Fe 240→180** |
| **Risk** | Faster snowball; watch dual-ship depletion |

### 4. Storage Upgrade I too early

| Field | Detail |
|-------|--------|
| **Symptom** | First upgrade **~3:25** vs **10–12** design |
| **Evidence** | Timeline; cost **30 Fe + 10 Cu** |
| **Likely change** | **30→50 Fe**, **10→15 Cu** |
| **Risk** | Low; mid-loop only |

### 5. SurveyData income vs colony tax

| Field | Detail |
|-------|--------|
| **Symptom** | SD **125 @ 45** with heavy scan schedule; need **150** to build |
| **Evidence** | +25 deep × ~3–4 + basics; pulse costs **5** each |
| **Smallest change** | Colony SD **150→100** or deep reward **25→30** |
| **Risk** | Affects pulse/spam balance |

---

## Recommendation

**One next step:** Run a **live 45:00 stopwatch session** in Godot Editor and replace all **~ MODELED** rows in this doc with measured times (screenshots at 12 / 30 / 45 min).

If live run confirms Ice blocker: apply **one** minimal data-only fix first — **ColonyShip build cost: replace `Ice` with `Water` (same amount 350)** in `data/production/colony_ship.tres` / balance profile — then re-test 45 min before any broader cost pass.

**PASS WITH NOTES — if live run confirms modeled Ice issue, only these 1–3 data changes (separate PR, not this doc step):**

1. Colony **Ice → Water** (or enable Ice deposits on one outer body).  
2. **MS2:** Si **40 → 28** (or Fe **240 → 180**).  
3. Colony **Fe/SD** reduction **or** SD reward bump — pick **one** after Ice fix re-test.

**Balance changes in this audit step:** **none.**

---

## Acceptance (this report)

1. No code, scene, or data files changed.  
2. Only `docs/audits/core_loop_balance_full_run_v0_1.md` created.  
3. Timeline filled — **0:00–0:53 measured**; **3:00–45:00 modeled** (live validation required).  
4. Economy progression documented.  
5. MS2, Deep Scan, ColonyShip explicitly assessed.  
6. Issues classified Bug / UI / Balance.  
7. No balance changes in this step.  
8. Exactly one next recommendation: **live 45 min + Ice cost fix if confirmed**.  
9. `tooltip_text` remains **0**.

---

## Live Round 2 capture sheet (paste over MODELED rows)

| Stop time | Event | Fe | Si | Cu | SD | Notes |
|-----------|-------|----|----|----|----|-------|
| | Signal selected | | | | | |
| | Reveal | | | | | |
| | Basic scan done | | | | | |
| | 1st delivery | | | | | |
| | SD2 / drone #2 | | | | | |
| | MS2 affordable | | | | | blocked_reason: |
| | MS2 bought | | | | | |
| | 1st upgrade | | | | | |
| | Deep scan done | | | | | |
| | Storage relevant | | | | | % full: |
| | Colony prereqs visible | | | | | |
| | Colony buildable | | | | | |
| | 45:00 stop | | | | | |
