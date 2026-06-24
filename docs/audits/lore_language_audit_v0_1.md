# Lore Language Audit v0.1

**Date:** 2026-06-07  
**Scope:** Player-facing lore / description language inventory — audit and documentation only.  
**Godot:** 4.6.1  
**Repo:** local workspace (post Phase-1 EN UI cleanup)

---

## Audit summary

v0.1 is **intentionally mixed**:

| Layer | Language | Player-facing? |
|-------|----------|----------------|
| **UI scenes + `data/ui_text`** | **English** | Yes |
| **Celestial body + galaxy system lore** (`description`) | **German** | Yes (ObjectInfo, Galaxy Map) |
| **Discovery signal types + signal UI lore** | **English** | Yes (pre-reveal signals, investigate) |
| **Production / upgrade hover copy** | **English** | Yes |
| **Resource display names** | **English** | Yes |

This is a **content / release-language decision**, not a technical bug. Phase-1 removed German from UI chrome (buttons, fallbacks like `"No description available."`); **planet and system flavor text in `.tres` remains German**.

`data/points_of_interest/` — **not present** in repo (no POI `.tres` files).

---

## Language per data area

| Data area | Files checked | Primary language | Player-facing fields | Notes |
|-----------|---------------|------------------|----------------------|-------|
| `data/celestial_bodies/**` | 12 | **DE** lore, **EN** names | `description`, `display_name` | All bodies have German `description`; names English (`Merkury` typo on Mercury) |
| `data/galaxy_systems/**` | 2 | **DE** lore, **EN**/mixed names | `description`, `display_name` | `Proxima Centauri-System` display name is German compound |
| `data/discovery_signal_types/**` | 7 | **EN** | `display_name`, `description` | Used for signal typing / investigate copy |
| `data/production/**` | 4 | **EN** | `short_description` | Hover text in ProductionPanel |
| `data/upgrades/**` | 10 | **EN** | `title`, `short_description`, `effect_lines` | Hover text in UpgradePanel |
| `data/ui_text/**` | 3 | **EN** | all template keys | Gates, discovery signals, upgrade effect labels |
| `data/resources/resource_catalog.tres` | 1 | **EN** | `display_name` | No lore descriptions set |
| `scenes/ui/**` | all `.tscn` | **EN** | labels, buttons, lore fallbacks | No German umlauts in scene text (grep) |

---

## SFX-ID-style matrix (lore / description fields)

| File | Field | Language | Player-facing? | Recommendation |
|------|-------|----------|----------------|----------------|
| `data/celestial_bodies/solar_system/earth.tres` | `display_name` | EN | Yes | Keep (proper noun) |
| `data/celestial_bodies/solar_system/earth.tres` | `description` | **DE** | Yes | Product decision: translate for EN release **or** keep DE flavor |
| `data/celestial_bodies/solar_system/mars.tres` | `description` | **DE** | Yes | Same as Earth |
| `data/celestial_bodies/solar_system/mercury.tres` | `display_name` | EN (typo: *Merkury*) | Yes | Optional name fix separate from language policy |
| `data/celestial_bodies/solar_system/mercury.tres` | `description` | **DE** | Yes | Same as Earth |
| `data/celestial_bodies/solar_system/venus.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/solar_system/moon.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/solar_system/jupiter.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/solar_system/saturn.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/solar_system/uranus.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/solar_system/neptune.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/proxima_system/proxima_b.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/proxima_system/proxima_c.tres` | `description` | **DE** | Yes | Same |
| `data/celestial_bodies/proxima_system/proxima_d.tres` | `description` | **DE** | Yes | Same |
| `data/galaxy_systems/solar_system.tres` | `description` | **DE** | Yes (Galaxy Map) | Same |
| `data/galaxy_systems/proxima_system.tres` | `display_name` | **DE**/mixed | Yes | `Proxima Centauri-System` |
| `data/galaxy_systems/proxima_system.tres` | `description` | **DE** | Yes | Same |
| `data/discovery_signal_types/*.tres` (×7) | `description` | EN | Yes (signals) | Aligned with EN UI |
| `data/ui_text/discovery_signal_ui_texts.tres` | `*_lore*` templates | EN | Yes | Aligned with EN UI |
| `data/ui_text/gate_ui_texts.tres` | all templates | EN | Yes | Aligned with EN UI |
| `data/ui_text/upgrade_effect_texts.tres` | all templates | EN | Yes (hover) | Aligned with EN UI |
| `data/production/*.tres` (×4) | `short_description` | EN | Yes (hover) | Aligned with EN UI |
| `data/upgrades/**/*.tres` (×10) | `short_description` | EN | Yes (hover) | Aligned with EN UI |
| `scenes/ui/system/object_info_panel.tscn` | `NoDescriptionLoreTemplate` | EN | Yes (fallback) | OK for EN UI |
| `scenes/ui/galaxy/galaxy_map_hud.tscn` | `NoDescriptionTemplate` | EN | Yes (fallback) | OK for EN UI |
| `scenes/ui/system/object_info_panel.tscn` | `LoreTextLabel` (editor placeholder) | EN | No at runtime | Replaced by body `description` |
| `scripts/system/controller/system_ui_controller.gd` | `lore_text` fallback string | EN | Yes | Hardcoded; matches scene template |
| `scripts/ui/system/top_hud.gd` | `push_warning` text | **DE** | **No** | Dev log only — out of lore scope |

**Summary counts**

- German player-facing lore fields: **14** (`description` on 12 bodies + 2 galaxy systems)
- English player-facing lore/description fields: **discovery (7)**, **ui_text (3 files)**, **production (4)**, **upgrades (10)**, **UI fallbacks**
- No `signal_lore` overrides on individual bodies (field unused in `.tres`; signals use `discovery_signal_ui_texts.tres`)

---

## Examples

### German lore (shown in ObjectInfo → Info panel)

**Mars** (`data/celestial_bodies/solar_system/mars.tres`):

> *Trockener roter Wüstenplanet mit tiefen Canyons und gewaltigen Staubstürmen…*

**Solar System** (`data/galaxy_systems/solar_system.tres`):

> *Heimatregion der Menschheit mit vielfältigen Planeten, Monden und Asteroidenfeldern…*

### English UI + signal lore

**Unknown signal** (`discovery_signal_ui_texts.tres`):

> *Unknown signal detected by the base sensors.*

**ObjectInfo fallback** (`object_info_panel.tscn`):

> *No description available.*

### Mixed playtest experience

1. Player selects **Mars** → English chrome (*Scan*, *Mine*, *Info*) + **German** lore paragraph.
2. Player opens **Galaxy Map** → English labels + **German** system blurb when a system is selected.
3. Player investigates **signal** → English lore templates throughout.

---

## Playtest risk

| Risk | Severity | Notes |
|------|----------|-------|
| EN UI + DE planet lore feels inconsistent | **Medium** | Most visible in ObjectInfo and Galaxy Map |
| Stream/recording audience assumes full EN | **Low–Medium** | Lore is the main DE holdout |
| DE-speaking playtesters | **Low** | UI is EN; lore is comfortable |
| Future i18n cost | **Medium** | Lore split across `.tres` bodies vs centralized `ui_text` |
| `Merkury` display name | **Low** | Orthography, not language policy |

---

## Recommendation options (no action taken)

| Option | Description | Fit for v0.1 |
|--------|-------------|--------------|
| **A — UI EN + Lore EN** | Translate 14 German `description` fields (+ Proxima display name) | Clean international demo; content work |
| **B — UI DE + Lore DE** | Revert/localize UI to German | Conflicts with completed Phase-1 EN UI |
| **C — i18n later** | `tr()` + locale resources for lore and UI | Best long-term; higher setup cost |
| **D — v0.1 mixed on purpose** | Keep EN UI + DE flavor lore | **Current state**; document in release notes |

**Audit recommendation:** Treat as **needs product decision**. Technically stable; no blocker. If targeting English-first playtests/streaming, **Option A** or **C**; if flavor-first internal build, **Option D** is acceptable with release-note disclaimer.

---

## Decision status

**OPEN — needs product / release-language decision**

No translation, `.tres` edits, i18n scaffolding, UI, gameplay, or save changes in this audit pass.

---

## Changed files

| File | Change |
|------|--------|
| `docs/audits/lore_language_audit_v0_1.md` | **New** — this audit |

**Unchanged:** all `data/**`, `scenes/**`, `scripts/**`, `SAVE_VERSION = 1`, `tooltip_text = 0`.

---

## Verdict

**PASS WITH NOTES**

1. Lore/description language documented per data area.
2. No content files modified.
3. Release-language decision explicitly marked open.
4. No save/gameplay/UI changes.
5. Mixed EN UI + DE celestial/galaxy lore is the dominant finding.
