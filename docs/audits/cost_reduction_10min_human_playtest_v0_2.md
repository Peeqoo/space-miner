# Cost Reduction 10-Minute Human Playtest v0.2

**Date:** 2026-06-20  
**Godot:** 4.6.1  
**Scope:** Human playtest validation after Cost Reduction v0.2 + `SCALED_COST_CEIL_EPSILON`.  
**No gameplay/cost/gate/save changes in this audit.**

---

## Verdict: **PASS WITH NOTES**

| Layer | Result |
|-------|--------|
| **True GUI human playtest** | **Not executed** — Agent hat keinen Zugriff auf Godot-UI |
| **Human-strategy proxy run** | **PASS WITH NOTES** — MS #2 nicht erreicht; Mining **nie gestartet**; Iron in SP-Rebuilds |
| **Economy assessment (informed player)** | **PASS WITH NOTES** — Kosten ok; MS #2 erreichbar wenn Iron-Body (Mars) gemined wird **ohne** frühes SP/SD-Iron-Burn |
| **ColonyShip** | **PASS** — weiterhin durch Prereqs blockiert |

**Telemetry (proxy):** `user://balance_runs/cost_reduction_10min_human_v0_2_2026_06_20_131912.json`  
**Runner:** `scripts/debug/smoke_tests/cost_reduction_10min_human_strategy_smoke_runner.tscn`  
**Referenz Automation:** [`cost_reduction_10min_smoke_v0_2.md`](cost_reduction_10min_smoke_v0_2.md)

---

## Methodik

1. **Agent-Limitation:** Echter 10-min-GUI-Playtest (New Game, Klicks, F9) ist vom Agent nicht ausführbar.
2. **Freigegebener Ersatz:** Human-Strategy-Proxy mit informierten Regeln:
   - Moon/Mars/Mercury Scan/Mine vor Venus
   - MS #2 Build-Priorität vor SD #2
   - SP #3 nur wenn `survey_probe_count < 1`
   - Storage I nur bei ≥70 % Füllung + Ressourcen
   - SD #2 erst nach erstem Delivery oder ab 90 s
3. **Zusätzlich:** Game-Data-Analyse (`moon.tres` hidden, `venus.tres` ohne Iron) + Vergleich Automation v0.2.

---

## A — Early Choices (Human-Strategy Proxy)

| Frage | Ergebnis Proxy-Run |
|-------|---------------------|
| Erstes Build | **2× SurveyProbe-Rebuild** (lifetime 2→4) wenn Probes durch Investigate auf 0 |
| SP #3 am Start? | **Nein** — aber **SP #4/#5** nach Verbrauch (~37+37 Fe ≈ 74 Fe) |
| SD #2 Zeitpunkt | **Nicht gebaut** (23 Fe Rest, Gate 56 Fe) |
| Storage I | **Nicht gekauft** (Stor ~23/1000, <70 %) |
| Erstes Mine-Target | **Keines** — Mining **nie gestartet** in 600 s |
| Warum? | Nur **Venus** basic-scanned (0 % Iron); Mars/Moon nicht mine-ready; `can_mine` für Iron-Bodies false |

**Wichtig für echten Spieler:** **Moon ist `default_discovery_state = "hidden"`** — nicht scannbar bis Signal/Investigate/Sensor. „Moon first“ funktioniert erst nach Discovery.

---

## B — MS #2

| Check | Proxy-Run | Automation v0.2 | Informed Human (erwartet) |
|-------|-----------|-----------------|---------------------------|
| MS #2 erreicht? | **Nein** | **Nein** | **Wahrscheinlich ja** (~6–9 min) |
| Zeitpunkt | — | — | ~360–540 s (geschätzt) |
| Engpass | Iron 23/135; **Si 0** (kein Mining) | Iron 7/135; Si 165 | Iron kurzzeitig, nicht Si |
| Target-Problem? | **Ja** — Venus gescannt, kein Iron-Body mine-ready | **Ja** — Venus gemined | **Nein** wenn Mars gescannt + gemined |
| Scan/Discovery zu langsam? | **Ja** — 1 SD, Mars nie basic-scanned in 10 min | Moon hidden; Mars später | Human priorisiert **bekanntes** Mars-Signal nach Sensor Pulse |

**Proxy schlechter als Automation:** Automation startete Mining @30 s (Venus); Proxy **0 Mining-Jobs** — Iron in Probes, kein Income.

---

## C — Iron Income

### Body-Daten (Basic Scan, layer 0)

| Body | Iron? | Gewicht-Anteil (richness) | Discovery |
|------|-------|---------------------------|-----------|
| **Moon** | Ja | ~37 % | **hidden** — erst aufdecken |
| **Mars** | Ja | ~33 % | Signal → Investigate → Scan |
| **Mercury** | Ja | ~40 % | hidden / später |
| **Venus** | **Nein** | 0 % | früh per Signal sichtbar |
| **Earth** | Ja | — | Home, nicht mineable |

### Proxy-Run

| Metrik | Wert |
|--------|------|
| Iron/Minute | **~0** (kein Mining) |
| Objekte mit Iron geliefert | **keine** |
| Si/Cu/C-lastig | Venus wäre C/Cu/Si — nie gemined |

### Informed-Human-Schätzung (Mars-Mining, 100 Fe Start behalten)

- ~7 Fe pro Trip (cargo 20, ~33 % Fe), ~1 Trip/min → **~7 Fe/min**
- 10 min ohne frühe Builds: 100 + 70 ≈ **170 Fe** → **MS #2 (135) erreichbar**
- Mit SD #2 (56) vor Mining: 44 + 70 ≈ **114 Fe** → knapp unter 135

**UI-Info:** `ObjectInfoPanel` zeigt nach Scan `resources_visible` mit Restmengen — **Iron fehlt bei Venus im Panel**. Kein Richness-%, aber Abwesenheit von Iron ist erkennbar. Hidden bodies (Moon) erscheinen erst nach Discovery — **UI gibt nicht vor Scan an, dass Moon Iron hat**.

---

## D — UI / Loop Feel (Code + Proxy + Automation)

| Check | Assessment |
|-------|------------|
| SD #2 früh gut? | Ja bei 56 Fe — Proxy baute SD #2 nicht (bewusst verzögert + kein Income) |
| MS #2 zu weit? | Fühlt sich **zu weit** an wenn Venus gemined oder Iron in SP/SD gebrennt wird |
| Storage I (20/5) | Proxy: nicht relevant; Automation: nicht gekauft; preislich ok |
| BaseManagementPanel auto-open | Nicht im Proxy getestet |
| ProductionPanel Kosten | Telemetry + Step 2b: **56 / 135·23 / 37** korrekt |

---

## E — ColonyShip (@ min 10, Proxy)

| Prerequisite | Met? |
|--------------|------|
| Deep Scan Module | **Nein** |
| Shipyard I | **Nein** |
| Colony Protocol | **Nein** |
| Ice source | **Ja** |
| 3 Deep Scans | **Nein** |

`colony_ship_buildable: false` — Fe 23/900, Si 0/180, Water 0/250. **Weit weg.**

---

## F — Telemetry (@ run_start + min 10, Proxy)

| Field | Expected | Actual | OK |
|-------|----------|--------|-----|
| `production_gates.scan_drone.cost.Iron` | 56 | 56 | ✓ |
| `production_gates.mining_ship.cost` | 135 / 23 | 135 / 23 | ✓ |
| `production_gates.survey_probe.cost.Iron` | 37 @ lt=2 | 44 @ lt=4 (nach Rebuilds) | ✓ scaling |
| `colony_ship.scaling_excluded` | true | true | ✓ |
| `units.mining_ship.count` | 2 if MS#2 | **1** | ✗ |
| `units.scan_drone.count` | ≥2 optional | **1** | — |
| `mining.active_mining_details` | Mars/Moon | **[]** | ✗ |
| `first_mining_started` | >0 | **-1** | ✗ |
| `SAVE_VERSION` | 1 | 1 | ✓ |

---

## Timeline Minute 0–10 (Human-Strategy Proxy)

| Min | Fe | Si | SD | MS | SP own | Storage | Notes |
|-----|----|----|----|----|--------|---------|-------|
| 0 | 100 | 0 | 1 | 1 | 2 | 100/1000 | |
| 1 | 23 | 0 | 1 | 1 | 0 | 28/1000 | SP-Rebuilds; Venus basic-scanned; 2 Investigate aktiv |
| 2–10 | 23 | 0 | 1 | 1 | 0 | 23/1000 | **Stagnation** — kein Mining, 1 Scan-Job dauerhaft aktiv |

### Milestones (Proxy)

| Event | Time |
|-------|------|
| first_signal_revealed | 2.0 s |
| sensor_pulse_used | 22.0 s |
| first_object_revealed | 46.1 s |
| first_mining_started | **NOT REACHED** |
| SD #2 | **NOT REACHED** |
| MS #2 | **NOT REACHED** |
| Storage I | **NOT REACHED** |

### Vergleich Automation v0.2

| | Automation | Human-Strategy Proxy |
|--|------------|----------------------|
| Mining | Venus @ 30 s | **Never** |
| Fe @ min 10 | 7 | 23 |
| Si @ min 10 | 165 | **0** |
| SD #2 | @ 4 s | No |
| MS #2 | No | No |

---

## Spieler-Entscheidungen (empfohlen für echten Human-Run)

1. **F9** Telemetry starten → New Game.
2. **Sensor Pulse** früh (SurveyData) → Signale aufdecken.
3. **Mars** (oder anderer Iron-Body) **investigaten + basic scannen** — nicht Venus als erstes Mine-Ziel.
4. **Mining starten** bevor Iron in SP-Rebuilds fließt.
5. **SD #2** bauen wenn 56 Fe **und** parallel Scans laufen sollen — nicht vor erstem Mining wenn MS #2 Priorität.
6. **MS #2** sobald 135 Fe + 23 Si.
7. **Storage I** nur bei Cu ≥5 und Storage >70 %.

---

## Gebaute Units / Upgrades (Proxy @ min 10)

| Item | Count / Level |
|------|-------------|
| ScanDrone | 1 |
| MiningShip | 1 |
| SurveyProbe (owned / lifetime) | 0 / **4** |
| Storage I | 0 |
| Upgrades | 0 |

---

## Mining-Ziele (Proxy)

| # | Target | Ergebnis |
|---|--------|----------|
| — | *(keines)* | Mining nie gestartet |

**Gescannt (basic):** Venus, Earth — **Mars nicht** in 10 min.

---

## UI-Probleme / Bugs

| Item | Severity | Notes |
|------|----------|-------|
| Moon hidden ohne UI-Hinweis auf späteres Iron | **Design NOTE** | Spieler muss Discovery-Loop verstehen |
| Venus scannt „normal“ aber liefert kein Iron | **Balance NOTE** | ObjectInfoPanel korrekt ohne Iron-Zeile |
| Proxy: SP-Rebuild-Loop frisst Iron | Test artefact | `count < 1` + Investigate-Verbrauch |
| Agent kein GUI-Playtest | Process | Echter Human-Run weiterhin empfohlen |

**Keine Fixes ohne Rückfrage.**

---

## Empfehlung (1–4)

| # | Option | Empfehlung |
|---|--------|------------|
| **1** | **Kosten behalten** | **Ja** — v0.2 + Float-Fix validiert; Scaling/Telemetry korrekt |
| **2** | **Iron-Yield/Target-Balance prüfen** | **Nur beobachten** — Mars/Moon liefern genug Iron **wenn** gemined; Venus-0-Iron ist Design |
| **3** | **Automation-Runner-Priorität falsch** | **Ja** — Standard-Smoke: Venus + blindes SP/SD; Strategy-Proxy: Discovery nicht fertig → kein Mining. Beide Runner brauchen **Mars-after-reveal** Logik, nicht nur Moon-first |
| **4** | **Kleiner Cost-Pass** | **Nein** |

### Klare Gesamt-Empfehlung

**Kosten v0.2 beibehalten.** MS #2 in 10 min ist für einen **informierten** Spieler realistisch (Mars-Mining, Start-Iron nicht in SP/SD verbrennen). Das Automation-FAIL ist **Target-/Discovery-Priorität**, nicht MS-Kosten (135 Fe).

**Nächste Schritte (optional, mit Rückfrage):**

1. Echter 10-min-GUI-Lauf durch Spieler (F9, Label `human_playtest_v0_2_gui`).
2. Runner-Fix: erst `known` Iron-Body scannen/minen; SP-Rebuild drosseln; nicht Venus als Mine-Fallback.
3. Kein Kostentuning ohne Human-GUI-Telemetry.

---

## Live GUI Playtest — Nachtrag (vom Spieler)

| Field | Value |
|-------|-------|
| Telemetry file | _ausstehend_ |
| MS #2 Zeitpunkt | |
| SD #2 Zeitpunkt | |
| Erstes Mine-Target | |
| Verdict | |

---

## Acceptance

1. Human-strategy proxy runner + 600 s Telemetry ausgeführt.  
2. Report dokumentiert Proxy + informed-player Projektion + GUI-Limitation.  
3. Keine Kosten/Gate/Save-Änderungen.  
4. `SAVE_VERSION = 1`, keine Tooltips.
