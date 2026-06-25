# TopHUD Storage Hover Resource Display Cleanup — Audit v0.1

**Date:** 2026-06-07  
**Scope:** Option B1 from `docs/design/tophud_objectinfo_dedup_plan_v0_1.md` — storage hover display names + catalog sort only.  
**Verdict:** **PASS**

---

## Kurzfassung

Der Storage-Zweig von `SystemUIController._build_hover_details("storage")` nutzt jetzt dieselbe Namens- und Sortierlogik wie StoragePanel: `GameSession.get_resource_display_name()` und `GameSession.get_storage_resource_ids_sorted()`. `SurveyData` erscheint als **Survey Data**, nicht `Surveydata`. TopHUD-Kompaktbar, ObjectInfoPanel und StoragePanel sind unverändert.

---

## Alt → Neu

| Aspekt | Vorher | Nachher |
|--------|--------|---------|
| Resource-Name | `str(res_id).capitalize()` | `GameSession.get_resource_display_name(rid_sn, rid.capitalize())` |
| Sortierung | Alphabetisch auf Roh-Keys (`keys_sorted.sort()`) | `GameSession.get_storage_resource_ids_sorted(resource_ids)` (Catalog `sort_order`) |
| Amount | `NumberFormat.format_compact` | unverändert |
| Empty-Text | `"No resources stored."` | unverändert |
| Title / Hint | `"Storage"` / `"Storage capacity."` | unverändert |
| TopHUD bar (`top_hud.gd`) | — | **keine Änderung** |

### UI-Beispiel

| Resource | Alt (Hover) | Neu (Hover) |
|----------|-------------|-------------|
| `SurveyData` | `Surveydata: 42` | `Survey Data: 42` |
| `Iron` | `Iron: 100` | `Iron: 100` (gleich, aber via Catalog) |
| Sortierung | alphabetisch (`Ice`, `Iron`, `Silicon`) | Catalog-Reihenfolge (`Iron`, `Silicon`, `Ice`) |

---

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `scripts/system/controller/system_ui_controller.gd` | Storage-Zweig in `_build_hover_details` |
| `scripts/debug/smoke_tests/top_hud_hover_storage_smoke_test.gd` | **Neu** — Tests A–D + Regression |
| `scripts/debug/smoke_tests/top_hud_hover_storage_smoke_runner.tscn` | **Neu** — Headless runner |

**Nicht geändert:** `top_hud.gd`, `top_hud_hover_panel.gd`, `object_info_panel.gd`, `storage_panel.gd`, `SAVE_VERSION`, `tooltip_text`.

---

## API-Nutzung

`GameSession.get_storage_resource_ids_sorted(resource_ids: Array[StringName])` existiert und delegiert an `ResourceCatalogFacade.get_storage_resource_ids_sorted` — keine neue API nötig.

---

## Tests

| Smoke | Prüft |
|-------|--------|
| `top_hud_hover_storage_smoke_runner.tscn` | A: Survey Data; B: Catalog-Namen + NumberFormat + Sort; C: empty text; D: title/hint; SAVE_VERSION; tooltip_text |
| `object_info_simple_action_button_labels_smoke_runner.tscn` | Regression ObjectInfo |
| `object_info_signal_layout_smoke_runner.tscn` | Regression ObjectInfo layout |

---

## Risiken

| Risiko | Mitigation |
|--------|------------|
| Sichtbare Hover-Zeilen ändern sich für Multi-Word-IDs | Smoke A/B; nur Hover, nicht Bar |
| Sortierreihenfolge weicht von alter Alphabet-Sort ab | Gewollt (Catalog); Smoke B prüft Iron → Silicon → Ice |
| Upgrade-Effekt-Block nach Resource-Zeilen | Unverändert; Smokes prüfen nur Resource-Detailzeilen |

---

## Akzeptanz

| Kriterium | Status |
|-----------|--------|
| Storage hover nutzt Catalog/GameSession display names | ✓ |
| SurveyData → Survey Data | ✓ (Smoke A) |
| Empty-Text unverändert | ✓ |
| TopHUD compact bar unverändert | ✓ |
| ObjectInfo unverändert | ✓ |
| StoragePanel unverändert | ✓ |
| SAVE_VERSION = 1 | ✓ (Smoke) |
| tooltip_text = 0 | ✓ (Smoke) |

**Gesamt:** **PASS**
