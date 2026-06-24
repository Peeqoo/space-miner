# Audio Event Table Verification Audit v0.1

**Date:** 2026-06-07  
**Scope:** `data/audio/audio_event_table.tres` + `AudioManager` integration — verification only.  
**Godot:** 4.6.1 (strict typing)

---

## Audit summary

`AudioEventTableDefinition` loads from `data/audio/audio_event_table.tres` in `AudioManager._ready()`. All **v0.1 gameplay-wired** SFX IDs resolve to embedded streams in the table. `AutomationAudioService` delegates world SFX to `AudioManager.play_world_sfx_*_optional`.

**Findings:**

- **16 code-used SFX IDs** — all present in `sfx_streams` / `world_loop_streams` with valid `.ogg` assets.
- **3 registered-but-unwired IDs** — `scan_start`, `mining_start`, `ship_return` (optional / future).
- **1 music path fallback** — `music_system_default` registered but `.ogg` file absent on disk (fallback when system track unknown; primary systems use embedded tracks).
- **No sensor_pulse / survey_probe / colony SFX** — those features have no audio event IDs in v0.1 (UI uses generic `build_success` / `not_enough_resources`).
- **No audio architecture or ID changes** in this pass.

---

## SFX-ID matrix

| SFX ID | Used in code? | Exists in table? | Optional? | Result |
|--------|---------------|------------------|-----------|--------|
| `ui_click` | Yes (`AudioManager.bind_ui_button`) | Yes (embedded) | No | **PASS** |
| `ui_hover` | Yes (bind) | Yes | No | **PASS** |
| `ui_blocked` | Yes (bind) | Yes | No | **PASS** |
| `not_enough_resources` | Yes (production/upgrade/system UI) | Yes | No | **PASS** |
| `build_success` | Yes (production/upgrade/system UI) | Yes | No | **PASS** |
| `object_selected` | Yes (`system_selection_controller`) | Yes | No | **PASS** |
| `scan_complete` | Yes (`automation_controller`) | Yes | No | **PASS** |
| `resource_revealed` | Yes (`automation_controller`) | Yes | No | **PASS** |
| `scan_drone_launch` | Yes (`AutomationAudioService`) | Yes | No | **PASS** |
| `scan_drone_arrive` | Yes (`AutomationAudioService`) | Yes | No | **PASS** |
| `scan_loop` | Yes (world loop) | Yes (`world_loop_streams`) | No | **PASS** |
| `mining_ship_launch` | Yes (`AutomationAudioService`) | Yes | No | **PASS** |
| `mining_ship_arrive` | Yes (`AutomationAudioService`) | Yes | No | **PASS** |
| `mining_resource_tick` | Yes (`AutomationAudioService`) | Yes | No | **PASS** |
| `mining_complete` | Yes (`automation_controller`) | Yes | No | **PASS** |
| `cargo_unload` | Yes (`automation_controller`) | Yes | No | **PASS** |
| `scan_start` | No (only `GAME_EVENT_IDS`) | Yes (embedded) | **Yes** — not wired | **PASS WITH NOTES** |
| `mining_start` | No | Path only (`sfx_paths`) | **Yes** — asset missing | **PASS WITH NOTES** |
| `ship_return` | No | Path only (`sfx_paths`) | **Yes** — asset missing | **PASS WITH NOTES** |
| `sensor_pulse` | No | No | N/A — no v0.1 audio | **N/A** |
| `survey_probe` | No | No | N/A — no v0.1 audio | **N/A** |
| `colony` | No | No | N/A — no v0.1 audio | **N/A** |

### Music tracks

| Track ID | Used in code? | In table? | Resolvable file? | Result |
|----------|---------------|-----------|------------------|--------|
| `music_main_menu` | Yes (`main_menu.gd`) | Embedded | Yes | **PASS** |
| `music_galaxy_map` | Yes (`galaxy_map.gd`) | Embedded | Yes | **PASS** |
| `music_solar_system` | Yes (`system_scene`) | Embedded | Yes | **PASS** |
| `music_proxima_system` | Yes (system defs) | Embedded | Yes | **PASS** |
| `music_system_default` | Yes (fallback) | Path only | **No** (file missing) | **PASS WITH NOTES** |
| `menu_theme` / `galaxy_ambient` | Legacy aliases | Embedded (alias) | Yes | **PASS** |

---

## Missing / optional IDs

| ID | Status |
|----|--------|
| `mining_start` | Registered in `GAME_EVENT_IDS` + `sfx_paths`; **not called** from code; **`.ogg` missing** |
| `ship_return` | Same as `mining_start` |
| `scan_start` | In table + cooldown map; **not called** from code; asset exists |
| `music_system_default` | Path fallback; **`.ogg` missing**; `play_music` warns and skips |

No typo corrections required (IDs match between code and table).

---

## Changed files

| File | Change |
|------|--------|
| `scripts/debug/smoke_tests/audio_event_table_verification_smoke_test.gd` | **New** |
| `scripts/debug/smoke_tests/audio_event_table_verification_smoke_runner.tscn` | **New** |
| `docs/audits/audio_event_table_verification_v0_1.md` | **New** |

**Unchanged:** `audio_manager.gd`, `audio_event_table.tres`, gameplay, `SAVE_VERSION`.

---

## Tests

```text
godot --headless --path . --scene res://scripts/debug/smoke_tests/audio_event_table_verification_smoke_runner.tscn
```

- **Test A:** Table loads; `AudioManager.audio_event_table` set; all code-used SFX resolvable.
- **Test B:** Code-used IDs in table registry; optional IDs documented; music file gaps noted.
- **Test C:** ScanDrone / MiningShip launch-arrive + scan/mining complete IDs resolvable; `scan_loop` in world loops.
- **Test D:** `play_sfx_optional` / `play_world_sfx_optional` do not replace table reference.
- **Regression:** `SAVE_VERSION == 1`, `tooltip_text == 0`.

---

## Risks

| Risk | Level | Notes |
|------|-------|-------|
| Silent missing SFX for unwired IDs | Low | `play_*_optional` warns on missing stream |
| `music_system_default` missing file | Medium | Unknown system music fails silently after warning |
| Path-only IDs without assets | Low | `mining_start`, `ship_return` not wired |
| Future wiring typo | Medium | Smoke guards code-used ID set |

---

## Verdict

**PASS WITH NOTES**

- Dedicated audio table verification smoke added.
- All gameplay-wired SFX IDs verified.
- Optional/unwired IDs and missing path assets documented.
- No gameplay or audio architecture changes.
