# Space Miner Projektübersicht

Stand: 2026-05-20

---

## 1. Kurzfazit

### Aktueller technischer Aufbau
Space Miner ist ein Godot-4.6.1-Spiel (Forward Plus). Der Einstiegspunkt ist `scenes/core/main.tscn` → `scripts/core/main.gd`. Von dort wird über `SceneFlow` entweder die Galaxy Map, das Main Menu oder die System Scene geladen.

Der gesamte Spielzustand wird durch den Autoload `GameSession` verwaltet, der als dünne Fassade über mehrere Store-Objekte (BaseStore, AutomationStore, ObjectScanStore, ScannerStore, SystemEntryStore) agiert. Store-Instanzen sind Plain-GDScript-`RefCounted`-Objekte in `GameSession`, keine separaten Autoloads.

Persistenz: `SaveManager` (Autoload) serialisiert `GameSession` in JSON-Slots (`user://saves/save_NNN.json`); Automation-Runtime wird beim Speichern aus der aktiven `SystemScene` eingesammelt.

### Hauptsysteme
- **Galaxy Map**: Übersicht aller Sternensysteme, Auswahl und Einstieg in ein System (`GalaxyMapHUD` + `GalaxyTopBar`)
- **System Scene**: Darstellung eines Sternensystems mit Planeten und POIs
- **Automation System**: Automatisierte Drohnen (Scan) und Mining Ships (Mining)
- **System-HUD (`system_scene.tscn` / `UI`)**: `TopHUD`, `TopHudHoverPanel`, `BaseManagementPanel`, `ProductionPanel`, `UpgradePanel`, `StoragePanel`, `ObjectInfoPanel`, `PauseMenuOverlay`
- **ObjectInfoPanel**: Scan-Infos und Aktionen am selektierten Body/POI; `close_requested` → `SystemUIController` cleared die Selection
- **Scan System**: Mehrstufiges Scansystem mit Layern (basic / deep / special) über `ScannedResourceEntry.layer`

### UI-Layout-Regeln (System-HUD)
- **Feste Panels** (`BaseManagementPanel`, `ObjectInfoPanel`, `ProductionPanel`, `UpgradePanel`, `StoragePanel`, `TopHUD`): Größe und Position sind **editor-owned** (`.tscn`). Scripts setzen Inhalt und `visible`, **kein** runtime `_fit_height_to_content` / keine `custom_minimum_size`- oder `global_position`-Anpassung in diesen Panels.
- **Ausnahme Floating UI**: `TopHudHoverPanel` positioniert sich am Hover-Anker und passt die **Höhe** content-driven an (`_fit_height_after_layout` / `_fit_height_to_content`) — bewusste Ausnahme, kein Vorbild für feste Panels.
- **ProductionPanel / UpgradePanel Hover**: Sichtbarkeit über `HoverInfoSection.visible`; `HoverInfoPanel` bleibt innerer Container (`visible = true` in `_ready`). Button-Hover nutzt eine schlanke `Control`-HoverFläche, damit auch `disabled` Buttons Tooltips/Infos zeigen (Kauf weiter über `GameSession`-Guards).
- **StoragePanel**: Feste Panelbreite (`custom_minimum_size.x = 170` in `.tscn`); Liste unter `ResourcePanel/ResourceScroll/ResourceList`; nur **-10** Discard pro Zeile (`Discard10ButtonTemplate`); kein „Discard All“. `refresh()` → deferred `_apply_refresh()`, damit Zeilen nicht während `pressed` per `free()` entfernt werden.
- **GalaxyMapHUD**: Kein `InfoPopupPanel` / `InfoButton`. Systembeschreibung dauerhaft in `InfoTextLabel` (`InfoSection/InfoTextScroll`); Text aus `SystemDefinition.description` via `galaxy_map.gd` → `show_system_info(..., info_text, ...)`.

### Aktiv wirkende Systeme
- GameSession + alle Stores + `SaveManager`
- AutomationController (Mining, Scanning, Unit-Spawning; Save/Restore der Runtime-Missions)
- SystemUIController (Panel-Orchestrierung, Signal-Routing)
- TopHUD / TopHudHoverPanel (Status + Hoverdetails)
- BaseManagementPanel (Base-Hub: Navigation zu Production / Upgrades / Storage)
- ProductionPanel / UpgradePanel / StoragePanel
- ObjectInfoPanel (`resource_info_row.tscn`)
- ScanInfoBuilder, CelestialPresentationCalculator
- Main Menu (Slots), Pause Menu (Save/Continue)

### Legacy / Hinweise (noch im Code, nicht separate UI-Systeme)
- `scan_info_builder.gd`: Kompatibilitäts-Fallback für alte String-Einträge in Scan-Arrays (keine POI-`PackedStringArray`-Daten mehr)
- `automation_controller.gd`: `cargo_resources` + optional `cargo_resource_id` / `current_cargo` als interner Mining-Puffer (kein Ship-Cargo-Entity)
- `data/planet_resources/*.tres`: Authoring-Vorlagen; Bodies nutzen inline `SubResource` in `celestial_bodies` (nicht per Pfad geladen)
- Entfernt und **nicht** mehr im Repo: `storage_row.gd`, `cargo_row.*`, `InfoPopupPanel`, `InfoButton`, Discard-All in StoragePanel

---

## 2. Autoloads / Singletons

### GameSession
- **Pfad:** `res://scripts/autoload/game_session.gd`
- **Aufgabe:** Globale Fassade für den gesamten Spielzustand. Delegiert an interne Store-Instanzen. Stabilisiert die öffentliche API.
- **Wichtige Variablen:**
  - `current_system_definition: SystemDefinition`
  - `current_system_id: String`
  - `object_scans: ObjectScanStore`
  - `system_entry: SystemEntryStore`
  - `bases: BaseStore`
  - `automation: AutomationStore`
  - `scanner: ScannerStore`
  - Konstanten: `SCAN_UNKNOWN`, `SCAN_BASIC`, `SCAN_DEEP`, `SCAN_SPECIAL`, `SCANNER_BASIC`, `SCANNER_DEEP`, `SCANNER_SPECIAL`
- **Wichtige Funktionen:**
  - `ensure_default_system_loaded()` — lädt Default-System falls kein System gesetzt
  - `get_system_definition_by_id(system_id)` / `get_system_display_name(system_id)` — Katalog über `data/galaxy_systems/*.tres` (Match auf `SystemDefinition.id`, kein Dateiname-Raten)
  - `to_save_data()` / `apply_save_data()` — Session-Persistenz inkl. `automation`-Block
  - `set_current_system(system_definition)` — setzt das aktive System
  - `get_base_resource_amount(base_id, resource_id) -> int`
  - `get_base_resources(base_id) -> Dictionary`
  - `add_base_resource(base_id, resource_id, amount)`
  - `spend_base_resource(base_id, resource_id, amount) -> bool`
  - `get_base_drone_count(base_id) -> int`
  - `get_base_mining_ship_count(base_id) -> int`
  - `build_base_drone(base_id) -> bool`
  - `build_base_mining_ship(base_id) -> bool`
  - `get_object_scan_state(system_id, object_id) -> String`
  - `set_object_scan_state(system_id, object_id, scan_state)`
  - `get_active_scanner_tier() -> String`
  - `create_scan_mission(base_id, target_id) -> int`
  - `create_mining_mission(base_id, target_id) -> int`
  - `complete_automation_mission(mission_id) -> Dictionary`
  - Earth-Aliase: `get_earth_resource_amount`, `add_earth_resource`, etc.
- **Zugreifende Scripts:** automation_controller.gd, system_ui_controller.gd, base_management_panel.gd, object_info_panel.gd, production_panel.gd, upgrade_panel.gd, storage_panel.gd, top_hud.gd, galaxy_map.gd, system_scene.gd, scan_info_builder.gd, main.gd, main_menu.gd, pause_menu_overlay.gd, save_manager.gd
- **Definierte Signale:** u. a. `base_resources_changed`, `base_upgrades_changed`, `galaxy_progression_changed`
- **Emittierte Signale:** Store-Events über Facade
- **Verbundene Signale:** diverse UI-Panels

### SaveManager
- **Pfad:** `res://scripts/autoload/save_manager.gd`
- **Aufgabe:** Multi-Slot Save/Load (`SAVE_VERSION = 1`, Slots 1–3). `build_save_data()` ruft `GameSession.refresh_automation_snapshot_from_scene()` vor `to_save_data()` auf.
- **Wichtige Funktionen:** `save_game()`, `load_game()`, `has_save()`, `get_save_metadata()`, `delete_save()`
- **Zugreifende Scripts:** `main_menu.gd`, `pause_menu_overlay.gd`

### SceneFlow
- **Pfad:** `res://scripts/autoload/scene_flow.gd`
- **Aufgabe:** Verwaltet Szenenwechsel via einem `CurrentSceneSlot`-Node unter `Main`. Fallback auf `change_scene_to_packed()` wenn kein Root registriert.
- **Wichtige Variablen:**
  - `DEFAULT_SLOT_PATH: NodePath = "SceneRoot/CurrentSceneSlot"`
  - `_main_root: Node`
  - `_current_scene: Node`
- **Wichtige Funktionen:**
  - `register_main_root(root)` — wird von `main.gd` aufgerufen
  - `goto_galaxy()` → lädt `galaxy_map.tscn`
  - `goto_system()` → lädt `system_scene.tscn`
  - `goto_scene(scene_path)` — generische Szenenladung
- **Zugreifende Scripts:** main.gd (register), galaxy_map.gd (goto_system)
- **Definierte Signale:** keine
- **Emittierte Signale:** keine

---

## 3. Szenenübersicht

### `res://scenes/core/main.tscn`
- **Root-Node:** Node (kein Typ-Override)
- **Script:** `res://scripts/core/main.gd`
- **Wichtige Child-Nodes:** `SceneRoot/CurrentSceneSlot` (Slot für geladene Szenen)
- **Instanziierte Szenen:** keine (lädt dynamisch via SceneFlow)

### `res://scenes/galaxy/galaxy_map.tscn`
- **Root-Node:** Node2D
- **Script:** `res://scripts/galaxy/galaxy_map.gd`
- **Wichtige Child-Nodes:** `CameraRoot/GalaxyCamera2D`, `SystemsRoot`, `UI/GalaxyMapHUD`
- **Instanziierte Szenen:** GalaxyMapHUD, GalaxySystemNode-Instanzen unter SystemsRoot

### `res://scenes/ui/galaxy/galaxy_map_hud.tscn`
- **Root-Node:** Control (`GalaxyMapHUD`)
- **Script:** `res://scripts/ui/galaxy/galaxy_map_hud.gd`
- **Wichtige Child-Nodes:** `GalaxyInfoPanel/.../SystemNameLabel`, `AccessStatusLabel`, Scan-Intel-Labels, `InfoSection/InfoTextScroll/InfoTextLabel` (permanente Beschreibung), `ColonizationSection`, `EnterButton`
- **Hinweis:** `CurrentSystemValueLabel` liegt in sibling `GalaxyTopBar` (`galaxy_top_bar.tscn`), per `get_node_or_null("../GalaxyTopBar/...")`. Kein `InfoPopupPanel` / `InfoButton`.
- **DEV:** `ColonizationDevButton` (nur Entwicklungshilfe)

### `res://scenes/ui/galaxy/galaxy_top_bar.tscn`
- **Script:** `res://scripts/ui/galaxy/galaxy_top_bar.gd`
- **Rolle:** Aktuelles System in der Galaxy-Map-Topbar

### `res://scenes/ui/main_menu/main_menu.tscn`
- **Script:** `res://scripts/ui/main_menu/main_menu.gd`
- **Rolle:** New Game / Continue mit Save-Slots; Systemname via `GameSession.get_system_display_name()`

### `res://scenes/system/system_scene.tscn`
- **Root-Node:** Node2D
- **Script:** `res://scripts/system/system_scene.gd`
- **Wichtige Child-Nodes:**
  - `CameraRoot/SystemCamera2D` (SystemCameraController)
  - `SystemSpawner`
  - `SystemOrbitGuidesController`
  - `SystemSelectionController`
  - `SystemUIController`
  - `AutomationController`
  - `WorldRoot/StarRoot`, `WorldRoot/SystemBodiesRoot`, `WorldRoot/PointOfInterestRoot`, `WorldRoot/AutomationRoot`
  - `BackgroundRoot/OrbitGuidesLayer`
  - `UI/TopHUD`, `UI/TopHudHoverPanel`, `UI/BaseManagementPanel`, `UI/ObjectInfoPanel`, `UI/ProductionPanel`, `UI/UpgradePanel`, `UI/StoragePanel`, `UI/PauseMenuOverlay`
- **Instanziierte Szenen:** TopHUD, TopHudHoverPanel, ObjectInfoPanel, BaseManagementPanel, ProductionPanel, UpgradePanel, StoragePanel, PauseMenuOverlay; SystemBody / PointOfInterest / AutomationUnit (dynamisch)

### `res://scenes/system/objects/system_body.tscn`
- **Root-Node:** Node2D
- **Script:** `res://scripts/system/system_body.gd` (class SystemBody)
- **Wichtige Child-Nodes:** `OrbitPivot/BodyVisual` (Sprite2D), `OrbitPivot/SelectionRing`, `OrbitPivot/ClickArea`, `OrbitPivot/BackOrbitUnits`, `OrbitPivot/FrontOrbitUnits`
- **Instanziierte Szenen:** keine

### `res://scenes/system/objects/point_of_interest.tscn`
- **Root-Node:** Node2D
- **Script:** `res://scripts/system/point_of_interest.gd` (class PointOfInterest)
- **Wichtige Child-Nodes:** `OrbitPivot/POIVisual`, `OrbitPivot/SelectionRing`, `OrbitPivot/ClickArea`
- **Instanziierte Szenen:** keine

### `res://scenes/ui/system/base_management_panel.tscn`
- **Root-Node:** PanelContainer (`BaseManagementPanel`)
- **Script:** `res://scripts/ui/system/base_management_panel.gd`
- **Rolle:** Base-Hub — Vorschau, Basisname, Status, Population/Food/Growth-Labels, Navigation
- **Wichtige Child-Nodes:**
  - `Margin/Root/HeaderRow/HeaderLabel`, `Margin/Root/HeaderRow/CloseBasePanelButton`
  - `Margin/Root/MainRow/PreviewPanel/.../PreviewTexture`
  - `Margin/Root/MainRow/MetaColumn/BaseNameLabel`, `StatusLabel`, `PopulationLabel`, `FoodLabel`, `PopulationGrowthLabel`
  - `Margin/Root/ManagementButtonSection/OpenProductionButton`, `OpenUpgradeButton`, `OpenStorageButton`
  - `Margin/Root/StatusTextLabel` (Hinweiszeile)
- **Signale (Script):** `open_production_requested`, `open_upgrades_requested`, `open_storage_requested`, `close_requested`
- **Layout:** Editor-owned; kein `_fit_height_to_content` im Script

### `res://scenes/ui/system/top_hud.tscn`
- **Root-Node:** PanelContainer (`TopHUD`)
- **Script:** `res://scripts/ui/system/top_hud.gd`
- **Rolle:** Globale Kurzinfos — Storage, ScanDrones, MiningShips, ColonyShips, Jobs (je `*Widget` mit Label)
- **Signale:** `hover_requested(kind, screen_position)`, `hover_cleared`

### `res://scenes/ui/system/top_hud_hover_panel.tscn`
- **Root-Node:** PanelContainer (`TopHudHoverPanel`)
- **Script:** `res://scripts/ui/system/top_hud_hover_panel.gd`
- **Rolle:** Detail-Popup für TopHUD-Hover; Höhe content-driven (`size.y` nach Layout)

### `res://scenes/ui/system/production_panel.tscn`
- **Root-Node:** PanelContainer (`ProductionPanel`)
- **Script:** `res://scripts/ui/system/production_panel.gd`
- **Rolle:** Build ScanDrone / MiningShip / ColonyShip (`disabled` wenn `GameSession.can_build_*` false; Kauf in Handlern erneut geprüft)
- **Hover:** `Margin/Root/HoverInfoSection` (Sichtbarkeit) → `HoverInfoPanel` → Beschreibung/Kosten-Labels
- **Wichtige Child-Nodes:** `ProductionList/*Button`, `HeaderRow/CloseButton`, `HoverInfoSection/...`

### `res://scenes/ui/system/upgrade_panel.tscn`
- **Root-Node:** PanelContainer (`UpgradePanel`)
- **Script:** `res://scripts/ui/system/upgrade_panel.gd`
- **Rolle:** Upgrades Storage / ScanDrone / MiningShip; Hover-Texte aus `UpgradeDefinition.build_panel_hover_lines` mit Section-Labels aus `.tscn`
- **Daten:** Section-Überschriften u. a. aus Editor; Effektzeilen-Templates via `UpgradeEffectTextDefinition` (`data/ui_text/upgrade_effect_texts.tres`, geladen in `GameSession._load_upgrade_effect_texts()`)
- **Hover:** wie ProductionPanel (`hover_info_section.visible`)

### `res://scenes/ui/system/storage_panel.tscn`
- **Root-Node:** PanelContainer (`StoragePanel`), `custom_minimum_size.x = 170`
- **Script:** `res://scripts/ui/system/storage_panel.gd`
- **Rolle:** Basis-Lager anzeigen; manuelles Discard **-10** pro Ressource (`discard_resource_requested`)
- **Struktur:** `ResourcePanel/ResourceMargin/ResourceScroll/ResourceList` (dynamische Zeilen), verstecktes `Discard10ButtonTemplate`
- **Refresh:** `refresh()` → `_queue_refresh()` → deferred `_apply_refresh()` (kein `free()` während Button-Signal)

### `res://scenes/ui/system/object_info_panel.tscn`
- **Root-Node:** PanelContainer
- **Script:** `res://scripts/ui/system/object_info_panel.gd`
- **Wichtige Child-Nodes:**
  - `Margin/Root/HBoxContainer/HeaderLabel` (Titel aus Editor, z. B. „Object-Info“), `Margin/Root/HBoxContainer/CloseBasePanelButton`
  - `Margin/Root/MainRow/PreviewPanel/.../PreviewTexture`
  - `Margin/Root/MainRow/MetaColumn/NameLabel`, `TypeLabel`, `ScanStatusLabel`, `DistanceLabel`
  - `Margin/Root/ResourcePanel/.../ResourceList` (VBoxContainer — dynamisch)
  - `Margin/Root/OrbitStatusSection/DroneOrbitLabel`, `MineOrbitLabel`, `MiningBonusLabel`
  - `Margin/Root/GridContainer/ScanWithDroneButton`, `SendMiningShipButton`, `RecallDroneButton`, `RecallMiningShipButton`
- **Instanziierte Szenen:** `resource_info_row.tscn` (dynamisch)
- **Hinweis:** Keine `ActionBlockerBox`

### `res://scenes/ui/system/storage_info_row.tscn`
- **Root-Node:** HBoxContainer (`StorageInfoRow`)
- **Script:** KEIN Script
- **Wichtige Child-Nodes:** `ResourceNameLabel` (Label), `ResourceValueLabel` (Label)
- **Nutzung:** Wird von `base_management_panel.gd` dynamisch instanziiert und über `get_node_or_null` befüllt

### `res://scenes/ui/system/resource_info_row.tscn`
- **Root-Node:** HBoxContainer (`ResourceInfoRow`)
- **Script:** `res://scripts/ui/system/resource_info_row.gd` (class ResourceInfoRow)
- **Wichtige Child-Nodes:** `ResourceNameLabel` (Label), `ResourceValueLabel` (Label)
- **Nutzung:** Wird von `object_info_panel.gd` für Scanressourcen-Anzeige dynamisch instanziiert

### `res://scenes/automation/drone.tscn`
- **Root-Node:** Node2D
- **Script:** `res://scripts/automation/automation_unit.gd` (class AutomationUnit, UnitType.DRONE)
- **Wichtige Child-Nodes:** `VisualRoot`

### `res://scenes/automation/mining_ship.tscn`
- **Root-Node:** Node2D
- **Script:** `res://scripts/automation/automation_unit.gd` (class AutomationUnit, UnitType.MINING_SHIP)
- **Wichtige Child-Nodes:** `VisualRoot`

---

## 4. Script-Übersicht

### `res://scripts/core/main.gd`
- **class_name:** (keine)
- **extends:** Node
- **Aufgabe:** Einstiegspunkt; registriert SceneFlow-Root, bootet GameSession, lädt Startup-Szene
- **export-Variablen:** `startup_scene_path: String = "res://scenes/galaxy/galaxy_map.tscn"`
- **Wichtige Funktionen:** `_ready()`
- **Genutzte Autoloads:** SceneFlow, GameSession

### `res://scripts/autoload/game_session.gd`
- **class_name:** (keine — Autoload Node)
- **extends:** Node
- **Aufgabe:** Globale Spielzustand-Fassade
- *→ vollständig in Abschnitt 2 beschrieben*

### `res://scripts/autoload/scene_flow.gd`
- **class_name:** (keine — Autoload Node)
- **extends:** Node
- **Aufgabe:** Szenenwechsel-Management
- *→ vollständig in Abschnitt 2 beschrieben*

### `res://scripts/autoload/stores/base_store.gd`
- **class_name:** BaseStore
- **extends:** RefCounted
- **Aufgabe:** Verwaltet alle Basen (Ressourcen, Population, Drohnen, Mining Ships)
- **Wichtige Variablen:**
  - `BASE_EARTH = "earth"`, Production-IDs: `PRODUCTION_SCAN_DRONE`, `PRODUCTION_MINING_SHIP`, `PRODUCTION_COLONY_SHIP`
  - Production-Kosten aus `data/production/*.tres` via `ProductionCatalog` / `get_production_cost()`
  - `bases: Dictionary` — Key: base_id, Value: `{resources, population, drones, mining_ships, colony_ships, ...}`
  - New-Game-Start über `GameStartDefinition` (`data/game_start/default_start.tres`)
- **Wichtige Funktionen:** `get_resources()`, `get_resource_amount()`, `add_resource()`, `spend_resource()`, `build_drone()`, `build_mining_ship()`, `add_mining_ship()`, `add_drone()`
- **Definierte Signale:** keine
- **Persistenz:** `to_save_data()` / `apply_save_data()` über `SaveManager`

### `res://scripts/autoload/stores/automation_store.gd`
- **class_name:** AutomationStore
- **extends:** RefCounted
- **Aufgabe:** Verwaltet Mission-IDs und Missions-Dictionaries (Scan/Mine)
- **Wichtige Variablen:** `next_mission_id: int`, `missions: Dictionary`
- **Wichtige Funktionen:** `create_scan_mission()`, `create_mining_mission()`, `get_mission()`, `complete_mission()`, `to_save_data()` / `apply_save_data()`
- **Definierte Signale:** keine

### `res://scripts/autoload/stores/object_scan_store.gd`
- **class_name:** ObjectScanStore
- **extends:** RefCounted
- **Aufgabe:** Persistiert Scan-Zustände je System und Objekt
- **Wichtige Variablen:** `object_scan_states: Dictionary` (key: system_id → {object_id: scan_state})
- **Wichtige Funktionen:** `get_object_scan_state()`, `set_object_scan_state()`

### `res://scripts/autoload/stores/scanner_store.gd`
- **class_name:** ScannerStore
- **extends:** RefCounted
- **Aufgabe:** Hält den aktiven Scanner-Tier des Spielers
- **Wichtige Variablen:** `active_tier: String = SCANNER_BASIC`
- **Wichtige Funktionen:** `get_active_tier()`, `set_active_tier()`

### `res://scripts/autoload/stores/system_entry_store.gd`
- **class_name:** SystemEntryStore
- **extends:** RefCounted
- **Aufgabe:** Temporäre Zwischenablage für das aktuell gewählte System beim Szenenwechsel
- **Wichtige Variablen:** `selected_system_definition`, `entering_system_from_travel`
- **Wichtige Funktionen:** `stage_system_entry()`, `consume_selected_system_definition()`, `consume_travel_entry_flag()`

### `res://scripts/system/system_scene.gd`
- **class_name:** (keine)
- **extends:** Node2D
- **Aufgabe:** Haupt-Orchestrator der System-Szene; verdrahtet alle Controller
- **export-Variablen:** `system_definition: SystemDefinition`, `start_body_id: String = "earth"`
- **onready-NodePaths:**
  - `$CameraRoot/SystemCamera2D` → camera
  - `$SystemSpawner` → spawner
  - `$SystemOrbitGuidesController` → orbit_guides
  - `$SystemSelectionController` → selection
  - `$SystemUIController` → system_ui
  - `$AutomationController` → automation_controller
- **Wichtige Funktionen:** `_ready()`, `_finish_initial_setup()`, `_setup_controllers()`, `_resolve_active_system_definition()`
- **Genutzte Autoloads:** GameSession
- **Risiko NodePaths:** Alle @onready-Pfade müssen exakt mit der Szenen-Hierarchie übereinstimmen; Umbenennen von Nodes bricht das Script

### `res://scripts/system/system_body.gd`
- **class_name:** SystemBody
- **extends:** Node2D
- **Aufgabe:** Runtime-Node für Planeten; delegiert Orbit, Selektion und Scaninfo an Komponenten
- **onready-NodePaths:**
  - `$OrbitPivot/BodyVisual`, `$OrbitPivot/BackOrbitUnits`, `$OrbitPivot/FrontOrbitUnits`
  - `$OrbitPivot/SelectionRing`, `$OrbitPivot/ClickArea`, `$OrbitPivot/ClickArea/CollisionShape2D`
- **Definierte Signale:** `selected(body: SystemBody)`
- **Wichtige Funktionen:** `set_definition()`, `build_scan_info()`, `get_back_orbit_units()`, `get_front_orbit_units()`
- **Risiko NodePaths:** Alle `$OrbitPivot/...`-Pfade kritisch

### `res://scripts/system/point_of_interest.gd`
- **class_name:** PointOfInterest
- **extends:** Node2D
- **Aufgabe:** Runtime-Node für POIs (Asteroidenfelder etc.)
- **onready-NodePaths:** `$OrbitPivot/POIVisual`, `$OrbitPivot/SelectionRing`, `$OrbitPivot/ClickArea`, `$OrbitPivot/ClickArea/CollisionShape2D`
- **Definierte Signale:** `selected(poi: PointOfInterest)`
- **Wichtige Funktionen:** `set_definition()`, `build_scan_info()`
- **Risiko:** Kein Fallback wenn `definition == null` und kein Texture definiert (erzeugt Fallback-Texture programmatisch)

### `res://scripts/system/controller/automation_controller.gd`
- **class_name:** AutomationController
- **extends:** Node
- **Aufgabe:** Spawnt und steuert Drohnen und Mining Ships; verwaltet Mining-Loop; schreibt direkt in BaseStore über GameSession
- **Wichtige Variablen:**
  - `DRONE_SCENE`, `MINING_SHIP_SCENE` (preloads)
  - Basiswerte aus `data/units/*.tres` via `UnitCatalog`; Fallbacks `DEFAULT_*_FALLBACK`
  - Mining-Yield-Bonus über `GameSession.get_scan_drone_mining_yield_bonus_per_support_drone_percent()` / `UpgradeDefinition`
  - `active_units_by_mission_id`, `idle_drones`, `idle_mining_ships`
  - `mining_ship_runtime_by_unit_id: Dictionary` — enthält internen Cargo-Puffer pro Ship
- **Definierte Signale:** `automation_state_changed`
- **Emittierte Signale:** `automation_state_changed` (sehr häufig — bei jedem State-Wechsel)
- **Wichtige Funktionen:**
  - `setup()`, `ensure_starting_units()` — spawnt 1 Mining Ship zu Spielbeginn
  - `launch_scan_drone()`, `launch_mining_ship()`
  - `recall_one_drone_from_target()`, `recall_one_mining_ship_from_target()`
  - `_on_mining_ship_returned_to_base()` → ruft `GameSession.add_base_resource()` auf — **das ist der Mining-zu-Base-Datenfluss**
  - `_process()` — Mining-Loop tick
- **Genutzte Autoloads:** GameSession (für add_base_resource, scan-state, mission-management)
- **Preloads:** `drone.tscn`, `mining_ship.tscn`
- **Hinweis zu Cargo:** `current_cargo`, `cargo_capacity`, `cargo_resource_id` sind interne Dictionary-Keys des `mining_ship_runtime_by_unit_id`-Puffers — kein eigenständiges Ship-Cargo-Objekt

### `res://scripts/system/controller/system_ui_controller.gd`
- **class_name:** SystemUIController
- **extends:** Node
- **Aufgabe:** Orchestriert System-UI: Selektion → ObjectInfo/Base; routet Scan/Mine/Recall, Production/Upgrade-Builds, TopHUD-Hover-Position
- **Wichtige Variablen:** system_definition, selection, spawner, object_info_panel, base_management_panel, production_panel, upgrade_panel, storage_panel, top_hud, top_hud_hover_panel, automation_controller
- **Verbundene Signale (Auszug):**
  - `selection.selection_changed` → `_on_selection_changed`
  - `automation_controller.automation_state_changed` → `_on_automation_state_changed`
  - `object_info_panel.scan_requested` / `mining_requested` / `recall_*` → Automation-Launcher
  - `object_info_panel.close_requested` → `_on_object_info_close_requested` → `selection.clear_selection(true)`
  - `base_management_panel.open_production_requested` / `open_upgrades_requested` → öffnet/schließt Production/Upgrade; leert TopHUD-Hover
  - `production_panel.build_scan_drone_requested` / `build_mining_ship_requested` → `_on_build_*`
  - `production_panel.close_requested` / `upgrade_panel.close_requested`
  - `top_hud.hover_requested` / `hover_cleared` → TopHudHoverPanel
- **Genutzte Autoloads:** GameSession
- **Wichtige Funktionen:** `update_all()`, `update_object_info()`, `update_base_panel()`, `_get_top_hud_hover_position()`, `_get_visible_hover_anchor_panels()` (nur Base + ObjectInfo als Hover-Anker)

### `res://scripts/system/controller/system_camera_controller.gd`
- **class_name:** SystemCameraController
- **extends:** Camera2D
- **Aufgabe:** Kamerasteuerung mit WASD + Maus-Drag + Mausrad-Zoom
- **export-Variablen:** `keyboard_pan_speed`, `mouse_drag_pan_speed`, `zoom_min/max/step/smooth_speed`, `start_frame_mode`, etc.
- **Definierte Signale:** keine

### `res://scripts/system/controller/system_selection_controller.gd`
- **class_name:** SystemSelectionController
- **extends:** Node
- **Aufgabe:** Verwaltet die aktuell selektierte Einheit im System; emittiert `selection_changed`
- **Definierte Signale:** `selection_changed(selected_node: Node)`
- **Emittierte Signale:** `selection_changed`
- **Verbundene Signale:** `body.selected`, `poi.selected`

### `res://scripts/system/controller/system_spawner.gd`
- **class_name:** SystemSpawner
- **extends:** Node
- **Aufgabe:** Instantiiert SystemBodies und POIs aus einer SystemDefinition; pflegt Lookup-Dictionary
- **Preloads:** `system_body.tscn`, `point_of_interest.tscn`
- **Definierte Signale:** `body_spawned(body: SystemBody)`, `poi_spawned(poi: PointOfInterest)`
- **Wichtige Funktionen:** `spawn_from_definition()`, `get_spawned_object(object_id) -> Node`

### `res://scripts/system/controller/system_orbit_guides_controller.gd`
- **class_name:** SystemOrbitGuidesController
- **extends:** Node
- **Aufgabe:** Sammelt Orbit-Daten aus SystemBodies und POIs; leitet an OrbitGuidesRenderer weiter

### `res://scripts/system/components/scan_info_builder.gd`
- **class_name:** ScanInfoBuilder
- **extends:** RefCounted
- **Aufgabe:** Baut Scan-Info-Dictionaries für Objekte basierend auf Scan-Zustand und Scanner-Tier
- **Wichtige static Funktionen:** `build_scan_info()`, `_filter_resources_for_scanner()`, `_entry_to_scan_resource()`, `_get_scan_hidden_slots_after_special()`
- **Genutzte Autoloads:** GameSession (Konstanten SCANNER_BASIC etc.)
- **Hinweis:** Kompatibilitäts-Fallback in `_entry_to_scan_resource()` für alte String-Einträge (POI/Body nutzen `scan_resources: Array[ScannedResourceEntry]`)

### `res://scripts/system/components/orbiting_object_component.gd`
- **class_name:** OrbitingObjectComponent
- **extends:** RefCounted
- **Aufgabe:** Wiederverwendbare Orbit-Logik (Winkelberechnung, Position)

### `res://scripts/system/components/selectable_object_component.gd`
- **class_name:** SelectableObjectComponent
- **extends:** RefCounted
- **Aufgabe:** Wiederverwendbare Selektion-Logik (Selection Ring, ClickArea-Shape)

### `res://scripts/system/celestial_presentation_calculator.gd`
- **class_name:** CelestialPresentationCalculator
- **extends:** RefCounted
- **Aufgabe:** Berechnet visuelle Darstellungsparameter (Größe, Orbit-Radius, Geschwindigkeit) aus Referenzdaten

### `res://scripts/system/orbit_guides_renderer.gd`
- **class_name:** (keine — extends Node2D)
- **Aufgabe:** Zeichnet Orbit-Kreise mit `draw_arc()`
- **Wichtige Funktionen:** `set_orbits(entries)`

### `res://scripts/system/selection_ring.gd`
- **class_name:** (keine — extends Node2D)
- **Aufgabe:** Zeichnet Selektionsring mit `draw_arc()`
- **export-Variablen:** `radius`, `color`, `width`, `segments`

### `res://scripts/ui/system/base_management_panel.gd`
- **class_name:** (keine — extends PanelContainer)
- **Aufgabe:** Base-Hub — Anzeige Basis-Metadaten; Navigation zu Production/Upgrade; kein Build mehr auf diesem Panel
- **Definierte Signale:** `open_production_requested`, `open_upgrades_requested`, `open_storage_requested`, `close_requested`
- **Wichtige Funktionen:** `show_for_base()`, `hide_panel()`, `refresh_from_game_session()`, `set_economy_actions_enabled()`
- **Layout:** Kein runtime Height-Fit; Panelgröße aus Editor
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/system/object_info_panel.gd`
- **class_name:** (keine — extends PanelContainer)
- **Aufgabe:** Zeigt Scan-Info für das selektierte Objekt; Aktions-Buttons Scan/Mine/Recall
- **Definierte Signale:** `scan_requested`, `mining_requested`, `recall_drone_requested`, `recall_mining_ship_requested`, `close_requested`
- **Preloads:** `RESOURCE_INFO_ROW_SCENE = preload("res://scenes/ui/system/resource_info_row.tscn")`
- **Genutzte Autoloads:** GameSession
- **Wichtige Funktionen:** `show_empty()`, `show_body_info(info)`, `show_poi_info(info)`, `_apply_resources()`, `set_distance_text()`
- **Layout:** Editor-owned; kein `_fit_height_to_content`
- **Hinweis:** `_apply_resource_dict_to_row` akzeptiert ältere Dict-Keys (`resource_id`, `name`) zusätzlich zu `id`

### `res://scripts/ui/system/top_hud.gd`
- **extends:** PanelContainer
- **Aufgabe:** Globale Kennzahlen (Storage, SD, MS, CS, Jobs); emittiert Hover-Anchor (`hover_requested` mit Widget-Mitte, TopHUD-Unterkante + 8 px)
- **Genutzte Autoloads:** GameSession (`base_resources_changed`)

### `res://scripts/ui/system/top_hud_hover_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** Floating Detail-Popup für TopHUD; `_fit_height_after_layout()` → `_fit_height_to_content()` (einzige HUD-Ausnahme für dynamische Höhe)

### `res://scripts/ui/system/production_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** Build über `GameSession.build_base_*`; Hover via `HoverInfoSection`; `_setup_action_button_hover` für disabled-taugliche Tooltips
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/system/upgrade_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** `buy_next_base_upgrade`; Hover-Body via `UpgradeDefinition.build_panel_hover_lines` + `UpgradeEffectTextDefinition` (global in `GameSession` geladen)
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/system/storage_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** Lagerliste + Discard -10; deferred refresh; Signale `close_requested`, `discard_resource_requested`
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/galaxy/galaxy_map_hud.gd`
- **class_name:** GalaxyMapHUD
- **Aufgabe:** System-Intel, permanente `InfoTextLabel`-Beschreibung, Colonization-UI, Enter-Button
- **Signale:** `enter_requested`, `colonization_cancel_requested`, `close_requested`, …

### `res://scripts/ui/system/resource_info_row.gd`
- **class_name:** ResourceInfoRow
- **extends:** HBoxContainer
- **Aufgabe:** Zeigt eine Ressourcen-Zeile mit Name + Prozentwert in ObjectInfoPanel
- **onready-NodePaths:** `$ResourceNameLabel`, `$ResourceValueLabel`
- **Wichtige Funktionen:** `set_row_data(resource_name, percent_text)`

### `res://scripts/galaxy/galaxy_map.gd`
- **class_name:** (keine — extends Node2D)
- **Aufgabe:** Orchestriert die Galaxy Map; verwaltet System-Auswahl, HUD, Kamera-Init
- **Definierte Signale:** keine
- **Genutzte Autoloads:** GameSession, SceneFlow
- **Wichtige Funktionen:** `select_system()`, `clear_selection()`, `_on_enter_pressed()`, `_count_known_bodies()`, `_build_known_resources_summary()`
- **Verbundene Signale:** `hud.enter_requested` → `_on_enter_pressed`

### `res://scripts/galaxy/galaxy_system_node.gd`
- **class_name:** (keine — extends Node2D)
- **Aufgabe:** Click-Handler für einzelne Systemnodes auf der Galaxy Map
- **Wichtige Funktionen:** `set_selected()`, `_select_system()` (sucht galaxy_map_root-Gruppe)

### `res://scripts/ui/galaxy/galaxy_map_hud.gd`
- **class_name:** GalaxyMapHUD
- **extends:** Control
- **Aufgabe:** HUD der Galaxy Map — zeigt aktuelles System, Scan-Daten, Info-Text, Enter-Button
- **Definierte Signale:** `enter_requested`
- **Wichtige Funktionen:** `show_system_info()`, `show_no_selection_state()`, `set_current_system_name()`

### `res://scripts/automation/automation_unit.gd`
- **class_name:** AutomationUnit
- **extends:** Node2D
- **Aufgabe:** Visuelle Einheit für Drohnen und Mining Ships; State Machine (IDLE, ORBITING_BASE, TRAVEL, APPROACH, WORKING, RETURNING)
- **Definierte Signale:** `arrived_at_target(unit)`, `returned_to_base(unit)`
- **export-Variablen:** `unit_type`, `travel_speed`, `return_speed`, `work_duration`, `orbit_*`, `approach_*`, `visual_rotation_offset_degrees`
- **Wichtige Funktionen:** `start_orbiting_base()`, `start_mission_to_node()`, `recall_to_base()`, `transfer_orbit_to_base()`, `is_available()`, `is_busy()`

---

## 5. Resource-/Daten-Dateien

### `res://resources/definitions/system_definition.gd`
- **Typ:** Script (Resource-Definition)
- **class_name:** SystemDefinition
- **Properties:** id, display_name, description, star_texture, star_scale, star_modulate, star_visual_radius, entry_spawn_*, earth_target_*, size_curve_exponent, orbit_curve_exponent, speed_curve_exponent, bodies (Array[SystemBodyDefinition]), pois (Array[PointOfInterestDefinition])
- **Nutzende Scripts:** system_scene.gd, galaxy_map.gd, system_spawner.gd, system_entry_store.gd, game_session.gd

### `res://resources/definitions/system_body_definition.gd`
- **Typ:** Script (Resource-Definition)
- **class_name:** SystemBodyDefinition
- **Properties:** id, display_name, description, body_type, orbit_center_id, orbit_radius/orbit_speed/body_scale (legacy, noch in `.tres`), texture, can_build_base, reference_*, size_authoring_mode, gameplay_*_bias, `scan_resources: Array[ScannedResourceEntry]` (Layer über `ScannedResourceEntry.layer`), `scan_hidden_slots_after_special`
- **API:** `get_basic_scan_resources()`, `get_deep_scan_resources()`, `get_special_scan_resources()` filtern nach Layer
- **Nutzende Scripts:** system_body.gd, system_spawner.gd, scan_info_builder.gd, celestial_presentation_calculator.gd, galaxy_map.gd

### `res://resources/definitions/point_of_interest_definition.gd`
- **Typ:** Script (Resource-Definition)
- **class_name:** PointOfInterestDefinition
- **Properties:** wie Body: `scan_resources: Array[ScannedResourceEntry]`, `scan_hidden_slots_after_special`, gleiche `get_*_scan_resources()`-Helfer

### `res://resources/definitions/scanned_resource_entry.gd`
- **Typ:** Script (Resource-Definition)
- **class_name:** ScannedResourceEntry
- **Properties:** `resource_id: StringName`, `richness_percent: int`, `layer` (BASIC/DEEP/SPECIAL), optional `deposit_amount`
- **Nutzende Scripts:** system_body_definition.gd (als Typ), scan_info_builder.gd (als Instanz-Check)

### `res://data/galaxy_systems/solar_system.tres`
- **Typ:** SystemDefinition Resource
- **Properties:** id="solar-system", 9 Körper (venus, earth, moon, mars, saturn, uranus, jupiter, mercury, neptune), keine POIs, Sonne-Textur, angepasste Darstellungsparameter
- **Nutzende Scripts:** game_session.gd (DEFAULT_SYSTEM_PATH)

### `res://data/galaxy_systems/proxima_system.tres`
- **Typ:** SystemDefinition Resource
- **Properties:** 3 Körper (proxima_b, proxima_c, proxima_d)

### `res://data/celestial_bodies/solar_system/earth.tres`
- **Typ:** SystemBodyDefinition
- **Properties:** id="earth", inline `SubResource`-Einträge in `scan_resources` (Basic + Deep per `layer`), inkl. `deposit_amount` wo gesetzt

### `res://data/celestial_bodies/solar_system/*.tres` (mercury, venus, mars, moon, jupiter, saturn, uranus, neptune)
- **Typ:** SystemBodyDefinition Resources
- **Kategorie:** Planetendaten des Sonnensystems

### `res://data/celestial_bodies/proxima_system/*.tres`
- **Typ:** SystemBodyDefinition Resources (proxima_b, proxima_c, proxima_d)

### `res://data/planet_resources/*.tres`
- **Typ:** ScannedResourceEntry-Vorlagen (Authoring-Bibliothek)
- **Runtime:** Werden **nicht** per `load("res://data/planet_resources/...")` gebunden; Bodies duplizieren Werte als inline `SubResource` in `data/celestial_bodies/**`
- **Aktive IDs in Bodies:** Basic — Silicon, Iron, Copper, Carbon, Hydrogen, Water; Deep — Oxygen, Aluminium, Calcium, Sodium, Potassium, Magnesium, Nickel, Cobalt, Helium, Methane (je eine Authoring-`.tres` unter `planet_resources/`, 16 Dateien)
- **Hinweis:** Einige Outer/Proxima-Bodies haben leeres `scan_resources` (z. B. Uranus, Neptune, Proxima b/c/d)

### `res://data/ui_text/upgrade_effect_texts.tres`
- **Typ:** `UpgradeEffectTextDefinition` — globale Platzhalter für Upgrade-Hover-Effektzeilen (`GameSession` lädt beim Boot)

### `res://scenes/ui/*.tres` (m5x7_, manaspace_, pixeloperator8_, pixeloperator_hbsc_, pixeloperator_ label_settings.tres)
- **Typ:** LabelSettings Resources
- **Kategorie:** Font-/Styling-Einstellungen für Labels in UI-Szenen

---

## 6. Datenfluss: Mining

**Schrittweise Beschreibung:**

1. **Spieler wählt POI/Planet** → `SystemSelectionController.selection_changed` emittiert
2. **SystemUIController** zeigt `ObjectInfoPanel`, prüft `_can_mine_selected_object()` (Scan-Zustand muss != unknown, Mining Ship muss idle sein)
3. **Spieler klickt "Send Mining Ship"** → `ObjectInfoPanel.mining_requested` emittiert
4. **SystemUIController._on_object_mining_requested()** → ruft `AutomationController.launch_mining_ship(target_id)` auf
5. **AutomationController.launch_mining_ship():**
   - Erstellt Runtime-Dictionary in `mining_ship_runtime_by_unit_id` mit `cargo_resources: {}`, `cargo_capacity`, `mining_rate_per_second`, `status: TO_TARGET`, …
6. **AutomationUnit** fliegt zum Ziel → MINING an Zielorbit
7. **`_process()` bei MINING:** extrahiert pro `resource_id` aus `GameSession.extract_resource_amount`; füllt `cargo_resources` bis `cargo_capacity`
8. **Voll oder keine Kandidaten:** Status → TO_BASE, `recall_to_base`
9. **`_on_mining_ship_returned_to_base()`:** Snapshot → UNLOADING mit `unload_cargo_snapshot` / `unload_xfer_buffers`
10. **UNLOADING:** `GameSession.add_base_resource` pro RID (rate-limited über `unload_timer`); bei vollem Lager → WAITING_FOR_STORAGE
11. **Loop / Release:** bei `loop_active` erneuter Flug; sonst `_release_mining_ship_runtime`
12. **Save/Load:** Runtime-Missions in `game_session.automation` + `AutomationController.apply_automation_save_if_pending()` nach Scene-Load
13. **UI:** `automation_state_changed` → `SystemUIController` refresht TopHUD / Panels

**Cargo:** Kein separates Ship-Cargo-Entity. `cargo_resources` ist die kanonische Quelle; `cargo_resource_id` / `current_cargo` nur Legacy-Fallback in `_merge_legacy_cargo_into_dictionary`.

---

## 7. Datenfluss: Scanning

1. **Spieler wählt Planet/POI** → `selection_changed` → `SystemUIController.update_object_info()`
2. **SystemUIController._build_selected_object_info():**
   - `scan_state = GameSession.get_object_scan_state(system_id, object_id)`
   - `scanner_tier = GameSession.get_active_scanner_tier()` (derzeit immer "basic")
   - Ruft `selected_node.build_scan_info(scan_state, scanner_tier)` auf
3. **SystemBody/PointOfInterest.build_scan_info()** delegiert an **ScanInfoBuilder.build_scan_info()**
4. **ScanInfoBuilder:**
   - Wenn `scan_state == SCAN_UNKNOWN`: gibt leeres Info-Dict zurück (kein Name, kein Typ, keine Ressourcen)
   - Wenn gescannt: filtert Ressourcen nach Scanner-Tier via `_filter_resources_for_scanner()`
   - Für `SystemBodyDefinition`: liest `Array[ScannedResourceEntry]` → erzeugt `{id, richness_percent, display_text}`
   - POI/Body: `get_basic_scan_resources()` etc. über `scan_resources` + Layer
   - Zählt `resources_hidden_count` via `_count_hidden_resource_slots()`
5. **ObjectInfoPanel._apply_resources()** erzeugt `ResourceInfoRow`-Instanzen mit Name + Prozentwert
6. **Scan-Mission:** Spieler klickt "Scan with Drone" → `scan_requested` → `AutomationController.launch_scan_drone()` → Drohne fliegt → `_on_scan_drone_arrived_at_target()` → `_complete_scan_mission()` → `GameSession.set_object_scan_state(system_id, target_id, SCAN_BASIC)` → `automation_state_changed` → UI-Update

---

## 8. Datenfluss: BaseManagementPanel (Base-Hub)

**Schrittweise Beschreibung:**

1. **Spieler wählt Earth (Body mit Basis)** → `selection_changed(earth_body)`
2. **SystemUIController.update_base_panel():** prüft `_selected_body_has_base(body)` → ruft `base_management_panel.show_for_base(system_id, body_id, "…", true)` auf
3. **BaseManagementPanel.show_for_base():** setzt `current_body_id`, `visible = true`, `refresh_from_game_session()`
4. **BaseManagementPanel.refresh_from_game_session():** setzt Basis-Metadaten-Labels (Population etc.)
5. **Spieler öffnet Production / Upgrades / Storage:** jeweilige Signale → `SystemUIController` zeigt `ProductionPanel`, `UpgradePanel` oder `StoragePanel`
6. **StoragePanel:** `refresh(base_id)` listet Ressourcen; Discard -10 über `discard_resource_requested` → `GameSession.spend_base_resource`
7. **Nach Mining-Unload:** `automation_state_changed` → UI-Refresh

**Hinweis:** Globale Lager-/Flotten-Kurzinfos im **TopHUD**; detailliertes Discard im **StoragePanel**.

---

## 9. UI Row Scenes

### `resource_info_row.tscn` — AKTIV
- **Script:** `resource_info_row.gd` (`ResourceInfoRow`)
- **Nutzung:** `ObjectInfoPanel` — Scan-Ressourcenzeilen

### `storage_info_row.tscn` — ungenutzt
- **Status:** Szene existiert ohne Script; wird aktuell **nicht** instanziiert (StoragePanel baut Zeilen in Code)

### `storage_row.gd` — entfernt
- **Status:** Datei existiert **nicht** mehr im Repo (nicht dokumentieren als vorhanden)

### `cargo_row.*` — entfernt
- **Status:** Nicht im Projekt vorhanden

---

## 10. Alte / verwaiste Systeme

| System | Datei | Warum alt / offen? | Empfehlung |
|---|---|---|---|
| Scan String-Fallback | `scan_info_builder.gd` `_entry_to_scan_resource()` | Alte String-Einträge in Arrays | Behalten bis alle Daten geprüft |
| Legacy orbit_radius/speed | `system_body_definition.gd` | Noch in älteren `.tres` | Schrittweise auf Referenzdaten |
| DEFAULT_MINING_DURATION | `automation_controller.gd` | Cargo stoppt Mining, nicht Timer | Dokumentiert / optional refactoren |
| can_build_base | `system_body_definition.gd` | Export, wenig Code-Nutzung | Auswerten oder entfernen |
| `storage_info_row.tscn` | ungenutzt | StoragePanel nutzt Code-Zeilen | Löschen oder wiederverwenden |
| `ColonizationDevButton` | `galaxy_map_hud` | DEV-only | Nicht als Spiel-Feature dokumentieren |

---

## 11. Fehler- und Risiko-Liste

| Risiko | Datei | Ursache | Auswirkung | Fix-Vorschlag |
|---|---|---|---|---|
| Scan-String-Fallback | `scan_info_builder.gd` | Alte String-Einträge → `richness_percent = -1` | UI zeigt „--“ | Fallback entfernen wenn Daten bereinigt |
| automation_state_changed sehr häufig | `automation_controller.gd` | Signal wird bei fast jedem State-Wechsel emittiert (15+ Stellen) | Jeder Emit triggert `SystemUIController`-Refresh (`update_object_info`, `update_base_panel`, `_update_top_hud`; Production/Upgrade bei Sichtbarkeit) | Debounce/defer oder targeted refresh einbauen |
| _process() jedes Frame für alle Mining Ships | `automation_controller.gd` L431+ | Immer aktiv wenn `mining_ship_runtime_by_unit_id` nicht leer | Kein Performance-Problem bei kleiner Einheitenzahl; könnte bei vielen Ships skalieren | Akzeptabel, bei Bedarf optimieren |
| Save ohne aktive SystemScene | `save_manager.gd` | Automation-Snapshot nur wenn `AutomationController` im Baum | Save aus Galaxy/MainMenu ohne laufende Missions-Visuals | Beim Speichern aus System-Szene bleiben oder dokumentieren |
| Alte Saves ohne `automation`-Key | `game_session.apply_save_data` | Optionaler Block | Leere Automation nach Load | Abwärtskompatibel (OK) |
| Drohnen-Einheitenanzahl Diskrepanz | `automation_controller.gd` L71-73 | BaseStore-Count und idle_drones-Array können divergieren | Visual und Data Count stimmen ggf. nicht überein nach Reload | Reinitialisierungslogik bei Scene-Load prüfen |
| can_build_base wird nicht ausgewertet | `system_body_definition.gd` L23 | Export-Feld ohne Code-Nutzung | Jeder Planet hat can_build_base=true, aber keine Logik nutzt es | Auswerten in system_ui_controller oder entfernen |

---

## 12. Abhängigkeitskarte

```
main.tscn
  └─ main.gd
	   ├─ SceneFlow.register_main_root()
	   └─ GameSession.ensure_boot_state()

Autoloads (immer aktiv):
  GameSession ──► BaseStore, AutomationStore, ObjectScanStore, ScannerStore, SystemEntryStore
  SaveManager ──► GameSession (save/load)
  SceneFlow   (keine eigenen Abhängigkeiten)

galaxy_map.tscn
  └─ galaxy_map.gd
	   ├─ GameSession (ensure_default_system_loaded, get_object_scan_state, stage_system_entry)
	   ├─ SceneFlow (goto_system)
	   └─ GalaxyMapHUD ──► enter_requested Signal

system_scene.tscn
  └─ system_scene.gd
	   ├─ GameSession (set_current_system, consume_selected_system_definition)
	   ├─ SystemSpawner
	   │    ├─ SystemBody (per Planet)
	   │    │    ├─ OrbitingObjectComponent
	   │    │    ├─ SelectableObjectComponent
	   │    │    └─ ScanInfoBuilder ──► GameSession (Scan-Konstanten)
	   │    └─ PointOfInterest (per POI)
	   │         └─ ScanInfoBuilder
	   ├─ SystemSelectionController ──► selection_changed Signal
	   ├─ SystemUIController
	   │    ├─ ◄─ selection.selection_changed
	   │    ├─ ◄─ automation_controller.automation_state_changed
	   │    ├─ ◄─ object_info_panel.scan_requested / mining_requested / recall_* / close_requested
	   │    ├─ ◄─ base_management_panel.open_production_requested / open_upgrades_requested / open_storage_requested
	   │    ├─ ◄─ production_panel.build_* / close_requested
	   │    ├─ ◄─ upgrade_panel.close_requested
	   │    ├─ ◄─ storage_panel.close_requested / discard_resource_requested
	   │    ├─ ◄─ top_hud.hover_requested / hover_cleared
	   │    ├─ ──► ObjectInfoPanel (show_body_info, show_poi_info, show_empty, set_distance_text)
	   │    ├─ ──► BaseManagementPanel (show_for_base, hide_panel, refresh_while_hold_open)
	   │    ├─ ──► ProductionPanel / UpgradePanel / StoragePanel
	   │    └─ ──► TopHudHoverPanel (show_details / clear; floating height fit)
	   ├─ AutomationController
	   │    ├─ GameSession (add_base_resource, scan_state, missions, drone/ship count)
	   │    ├─ SystemSpawner (get_spawned_object)
	   │    ├─ AutomationUnit (drone/mining_ship Instanzen)
	   │    └─ ──► automation_state_changed Signal
	   ├─ TopHUD / TopHudHoverPanel
	   │    └─ GameSession (Lesen von Base-Ressourcen / Counts für Labels)
	   ├─ ObjectInfoPanel
	   │    ├─ ResourceInfoRow (dynamisch instanziiert)
	   │    └─ GameSession (SCAN_UNKNOWN Konstante)
	   └─ BaseManagementPanel
			└─ GameSession (Population etc.)
```

---

## 13. Empfohlene nächste Aufräum-Reihenfolge

1. **`PROJECT_DEPENDENCIES.json` mit Repo abgleichen** — veraltete `planet_resources`- und `storage_row`-Einträge
2. **`can_build_base` auswerten oder entfernen**
3. **Legacy `orbit_*`-Felder in Body-`.tres` bereinigen** (nach visuellem Test)
4. **`scan_info_builder` String-Fallback entfernen**, wenn alle Scan-Daten `ScannedResourceEntry` sind
5. **`automation_state_changed`-Debounce** (Performance)
6. **Ungenutzte `planet_resources` / `storage_info_row.tscn`** — nach Design-Entscheid
7. **Outer/Proxima-Bodies:** `scan_resources` befüllen oder als „ohne Deposits“ dokumentieren

---

## 14. Konkrete Suchtreffer

### `cargo` / Mining-Runtime (automation_controller.gd)
- Kanonisch: `cargo_resources: Dictionary` (RID → Menge)
- Legacy-Fallback: `_merge_legacy_cargo_into_dictionary` (`cargo_resource_id`, `current_cargo`)
- Unload: `unload_cargo_snapshot`, `unload_xfer_buffers`, `GameSession.add_base_resource` pro RID

### `OreLabel`, `FuelLabel`, `FoodLabel`
— **Nicht gefunden** in keiner Datei. Vollständig entfernt.

### `cargo_row`
— **Nicht gefunden** in keiner Datei. Vollständig entfernt.

### `ResourceList`
| Datei | Zeile | Kontext |
|---|---|---|
| object_info_panel.gd | `@onready` | `$Margin/Root/ResourcePanel/.../ResourceList` |
| object_info_panel.tscn | ResourceList | unter `ResourceScroll` |

### `storage_row` / Storage UI
| Datei | Kontext |
|---|---|
| `storage_panel.gd` | Aktives Lager-UI mit -10 Discard |
| `storage_info_row.tscn` | Ungenutzt |
| `storage_row.gd` | **Nicht im Repo** |

### `automation_state_changed`
| Datei | Zeilen | Kontext |
|---|---|---|
| automation_controller.gd | 6 | `signal automation_state_changed` (Definition) |
| automation_controller.gd | 75,93,111,138,179,258,315,360,370,376,399,406,529,539,550 | `.emit()` Aufrufe |
| system_ui_controller.gd | 131-133 | Signal-Verbindung |
| system_ui_controller.gd | 271 | `func _on_automation_state_changed()` |

### `scan_resources` / `ScannedResourceEntry`
| Datei | Kontext |
|---|---|
| system_body_definition.gd / point_of_interest_definition.gd | `scan_resources` + Layer-Getter |
| scan_info_builder.gd | Filter + String-Fallback |
| galaxy_map.gd | `get_basic_scan_resources()` für Intel-Summary |
| scanned_resource_entry.gd | `resource_id`, `layer`, `deposit_amount` |

### `preload` / `load(`
| Datei | Zeile | Ressource |
|---|---|---|
| automation_controller.gd | 8 | `drone.tscn` |
| automation_controller.gd | 9 | `mining_ship.tscn` |
| object_info_panel.gd | 11 | `resource_info_row.tscn` |
| system_spawner.gd | 19 | `system_body.tscn` |
| system_spawner.gd | 20 | `point_of_interest.tscn` |
| scene_flow.gd | 24 | `load(scene_path)` (dynamisch) |
| game_session.gd | — | `_build_system_definition_catalog()` / `get_system_definition_by_id()` |
| save_manager.gd | — | JSON Save/Load Slots 1–3 |
