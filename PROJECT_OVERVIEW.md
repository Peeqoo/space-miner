# Space Miner Projektübersicht

Stand: 2026-05-14

---

## 1. Kurzfazit

### Aktueller technischer Aufbau
Space Miner ist ein Godot-4.6.1-Spiel (Forward Plus). Der Einstiegspunkt ist `scenes/core/main.tscn` → `scripts/core/main.gd`. Von dort wird über `SceneFlow` entweder die Galaxy Map oder die System Scene geladen.

Der gesamte Spielzustand wird durch den Autoload `GameSession` verwaltet, der als dünne Fassade über mehrere Store-Objekte (BaseStore, AutomationStore, ObjectScanStore, ScannerStore, SystemEntryStore) agiert. Singletons werden nicht als Godot-Autoloads registriert, sondern als Plain-GDScript-Instanzen direkt in GameSession erzeugt.

### Hauptsysteme
- **Galaxy Map**: Übersicht aller Sternensysteme, Auswahl und Einstieg in ein System
- **System Scene**: Darstellung eines Sternensystems mit Planeten und POIs
- **Automation System**: Automatisierte Drohnen (Scan) und Mining Ships (Mining)
- **System-HUD (`system_scene.tscn` / `UI`)**: `TopHUD` (globale Kurzinfos), `TopHudHoverPanel` (Widget-Hover), `BaseManagementPanel` (Base-Hub), `ProductionPanel` (Builds), `UpgradePanel` (Phase-5-Upgrades), `ObjectInfoPanel` (Objektinfos / Scan / Mine / Recall)
- **ObjectInfoPanel**: Scan-Infos und Aktionen am selektierten Body/POI; **keine** `ActionBlockerBox`; `CloseBasePanelButton` emittiert `close_requested` → `SystemUIController` cleared die Selection
- **Scan System**: Mehrstufiges Scansystem mit drei Tiers (basic, deep, special)

### Aktiv wirkende Systeme
- GameSession + alle Stores
- AutomationController (Mining, Scanning, Unit-Spawning)
- SystemUIController (Panel-Orchestrierung, Signal-Routing)
- TopHUD / TopHudHoverPanel (Status + Hoverdetails, Positionierung über `SystemUIController`)
- BaseManagementPanel (Base-Hub: Info + Navigation zu Production/Upgrades)
- ProductionPanel / UpgradePanel (eigene Build- bzw. Upgrade-UI)
- ObjectInfoPanel (ScannedResourceEntry-Darstellung über `resource_info_row.tscn`)
- ScanInfoBuilder (Build-Pipeline für Scan-Dictionaries)
- CelestialPresentationCalculator (Darstellung von Planeten im System)

### Alte / verwaiste Systeme
- `storage_row.gd`: Existiert, ist aber keiner `.tscn` zugewiesen und wird nicht instanziiert
- `PointOfInterestDefinition` nutzt noch `PackedStringArray` für Scan-Ressourcen (veraltet); `SystemBodyDefinition` nutzt bereits `Array[ScannedResourceEntry]`
- Die internen Keys `current_cargo`, `cargo_capacity`, `cargo_resource_id` in `automation_controller.gd` sind interne Transportpuffer des Mining Ships — kein separates Ship-Cargo-Entity mehr
- `cargo_row.gd` / `cargo_row.tscn` existieren im Projekt **nicht mehr** (bereits gelöscht)
- `OreLabel`, `FuelLabel`, `FoodLabel` existieren **nicht mehr** in keiner Datei

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
  - `ensure_default_system_loaded()` — lädt `solar_system.tres` falls kein System gesetzt
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
- **Zugreifende Scripts:** automation_controller.gd, system_ui_controller.gd, base_management_panel.gd, object_info_panel.gd, production_panel.gd, upgrade_panel.gd, top_hud.gd, galaxy_map.gd, system_scene.gd, scan_info_builder.gd, main.gd
- **Definierte Signale:** keine
- **Emittierte Signale:** keine
- **Verbundene Signale:** keine (ist Autoload, nicht Subscriber)

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
- **Root-Node:** Control
- **Script:** `res://scripts/ui/galaxy/galaxy_map_hud.gd`
- **Wichtige Child-Nodes:** `TopBar/Margin/Row/TitleLabel`, `TopBar/.../CurrentSystemValueLabel`, `GalaxyInfoPanel/.../SystemNameLabel`, `GalaxyInfoPanel/.../EnterButton`
- **Instanziierte Szenen:** keine

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
  - `UI/TopHUD`, `UI/TopHudHoverPanel`, `UI/BaseManagementPanel`, `UI/ObjectInfoPanel`, `UI/ProductionPanel`, `UI/UpgradePanel`
- **Instanziierte Szenen:** TopHUD, TopHudHoverPanel, ObjectInfoPanel, BaseManagementPanel, ProductionPanel, UpgradePanel; SystemBody (dynamisch), PointOfInterest (dynamisch), AutomationUnit (dynamisch)

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
  - `Margin/Root/ManagementButtonSection/OpenProductionButton`, `OpenUpgradeButton`
  - `Margin/Root/StatusTextLabel` (Hinweiszeile)
- **Signale (Script):** `open_production_requested`, `open_upgrades_requested`
- **Instanziierte Szenen:** keine (kein dynamisches `storage_info_row` mehr im Base-Hub)

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
- **Rolle:** Build ScanDrone / MiningShip; ColonyShip-Button gesperrt; internes `HoverInfoPanel` für Button-Hover
- **Wichtige Child-Nodes:** `Margin/Root/ProductionList/BuildScanDroneButton`, `BuildMiningShipButton`, `BuildColonyShipButton`, `Margin/Root/HeaderRow/CloseButton`, `Margin/Root/HoverInfoPanel/...`

### `res://scenes/ui/system/upgrade_panel.tscn`
- **Root-Node:** PanelContainer (`UpgradePanel`)
- **Script:** `res://scripts/ui/system/upgrade_panel.gd`
- **Rolle:** Phase-5-Upgrades (Storage / ScanDrone / MiningShip Upgrade I); internes `HoverInfoPanel`
- **Wichtige Child-Nodes:** `Margin/Root/UpgradeList/StorageUpgradeButton`, `ScanDroneUpgradeButton`, `MiningShipUpgradeButton`, `Margin/Root/HeaderRow/CloseButton`, `Margin/Root/HoverInfoPanel/...`

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
  - `BASE_EARTH = "earth"`, `RESOURCE_ORE = "ore"`, `RESOURCE_FUEL = "fuel"`, `RESOURCE_FOOD = "food"`
  - `DRONE_ORE_COST = 10`, `MINING_SHIP_ORE_COST = 25`
  - `bases: Dictionary` — Key: base_id, Value: `{resources, population, drones, mining_ships}`
  - Startwert Earth: `ore=50, fuel=0, food=0, population=1, drones=0, mining_ships=0`
- **Wichtige Funktionen:** `get_resources()`, `get_resource_amount()`, `add_resource()`, `spend_resource()`, `build_drone()`, `build_mining_ship()`, `add_mining_ship()`, `add_drone()`
- **Definierte Signale:** keine
- **Risiko:** kein Persistenz-System; Verlust bei Szenenwechsel nicht abgesichert

### `res://scripts/autoload/stores/automation_store.gd`
- **class_name:** AutomationStore
- **extends:** RefCounted
- **Aufgabe:** Verwaltet Mission-IDs und Missions-Dictionaries (Scan/Mine)
- **Wichtige Variablen:** `next_mission_id: int`, `missions: Dictionary`
- **Wichtige Funktionen:** `create_scan_mission()`, `create_mining_mission()`, `get_mission()`, `complete_mission()`
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
  - `DEFAULT_MINING_CARGO_CAPACITY = 20`, `DEFAULT_MINING_RATE_PER_SECOND = 2.0`
  - `DEFAULT_MINING_UNLOAD_DURATION = 2.0`, `DEFAULT_MINING_RESOURCE_ID = BaseStore.RESOURCE_ORE`
  - `DRONE_MINING_BONUS_PER_UNIT = 0.02`
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
- **Wichtige Variablen:** system_definition, selection, spawner, object_info_panel, base_management_panel, production_panel, upgrade_panel, top_hud, top_hud_hover_panel, automation_controller
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
- **Risiko:** Enthält Kompatibilitäts-Fallback für altes `PackedStringArray`-Format in POI-Definitionen (Zeile 133–142); wird aktiv genutzt, da `PointOfInterestDefinition` noch `PackedStringArray` nutzt

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
- **Definierte Signale:** `open_production_requested`, `open_upgrades_requested`
- **Wichtige @onready-Pfade:** `Margin/Root/MainRow/MetaColumn/BaseNameLabel`, `StatusLabel`, `PopulationLabel`; `Margin/Root/ManagementButtonSection/OpenProductionButton`, `OpenUpgradeButton`; `Margin/Root/StatusTextLabel`; `Margin/Root/HeaderRow/CloseBasePanelButton`
- **Wichtige Funktionen:** `show_for_base()`, `hide_panel()`, `refresh_from_game_session()`, `set_status_text()`, `_fit_height_to_content()` (fixe Breite, Höhe aus Inhalt)
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/system/object_info_panel.gd`
- **class_name:** (keine — extends PanelContainer)
- **Aufgabe:** Zeigt Scan-Info für das selektierte Objekt; Aktions-Buttons Scan/Mine/Recall
- **Definierte Signale:** `scan_requested`, `mining_requested`, `recall_drone_requested`, `recall_mining_ship_requested`, `close_requested`
- **Preloads:** `RESOURCE_INFO_ROW_SCENE = preload("res://scenes/ui/system/resource_info_row.tscn")`
- **Genutzte Autoloads:** GameSession
- **Wichtige Funktionen:** `show_empty()`, `show_body_info(info)`, `show_poi_info(info)`, `_apply_info()`, `_apply_resources()`, `_apply_lore()`, `set_distance_text()`, `_fit_height_to_content()` (nur `size.y`, Guard bei `visible`)
- **Risiko:** Legacy-Fallback in `_apply_resources()` für alte String-Einträge in Scan-Arrays

### `res://scripts/ui/system/top_hud.gd`
- **extends:** PanelContainer
- **Aufgabe:** Globale Kennzahlen (Storage, SD, MS, CS, Jobs); emittiert Hover-Anchor (`hover_requested` mit Widget-Mitte, TopHUD-Unterkante + 8 px)
- **Genutzte Autoloads:** GameSession (`base_resources_changed`)

### `res://scripts/ui/system/top_hud_hover_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** Zeigt Titel, Detailzeilen, Hint; `_fit_height_after_layout()` wartet einen Frame, dann nur `size.y`-Fit

### `res://scripts/ui/system/production_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** `GameSession.build_base_drone` / `build_base_mining_ship`; ColonyShip gesperrt; `close_requested`
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/system/upgrade_panel.gd`
- **extends:** PanelContainer
- **Aufgabe:** Phase-5-Käufe (`buy_base_storage_upgrade_i`, `buy_scan_drone_upgrade_i`, `buy_mining_ship_upgrade_i`); `close_requested`
- **Genutzte Autoloads:** GameSession

### `res://scripts/ui/system/storage_row.gd`
- **class_name:** (keine — extends HBoxContainer)
- **Aufgabe:** UNSICHER — vermutlich alte Row-Szene für Base-Storage; hat `set_row_data(name, amount: int)`
- **onready-NodePaths:** `$ResourceNameLabel`, `$ResourceAmountLabel`
- **Status:** VERWAIST — kein `.tscn` nutzt dieses Script; es wird nirgends instanziiert oder geladen
- **Risiko:** Nodename `ResourceAmountLabel` weicht von `storage_info_row.tscn` (`ResourceValueLabel`) ab

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
- **Properties:** id, display_name, description, body_type, orbit_center_id, orbit_radius (legacy), orbit_speed (legacy), body_scale (legacy), body_color, texture, can_build_base, reference_radius_earth, reference_orbit_au, reference_period_days, asset_body_diameter_px, authored_ratio_to_earth, size_authoring_mode, gameplay_size/orbit/speed_bias, use_manual_scale_override, manual_scale_override, scan_basic_resources (Array[ScannedResourceEntry]), scan_deep_resources, scan_special_resources, scan_hidden_slots_after_special
- **Nutzende Scripts:** system_body.gd, system_spawner.gd, scan_info_builder.gd, celestial_presentation_calculator.gd, galaxy_map.gd

### `res://resources/definitions/point_of_interest_definition.gd`
- **Typ:** Script (Resource-Definition)
- **class_name:** PointOfInterestDefinition
- **Properties:** id, display_name, description, poi_type, orbit_center_id, orbit_radius, orbit_speed, orbit_start_angle_degrees, poi_color, texture, scan_basic_reveal_name, scan_basic_reveal_type, scan_basic_resources (**PackedStringArray** — VERALTET), scan_deep_resources (**PackedStringArray** — VERALTET), scan_special_resources (**PackedStringArray** — VERALTET), scan_hidden_slots_after_special
- **Risiko:** Verwendet noch `PackedStringArray` statt `Array[ScannedResourceEntry]` — Kompatibilitäts-Fallback in `scan_info_builder.gd` aktiv

### `res://resources/definitions/scanned_resource_entry.gd`
- **Typ:** Script (Resource-Definition)
- **class_name:** ScannedResourceEntry
- **Properties:** `resource_id: StringName`, `richness_percent: int` (0–100)
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
- **Properties:** id="earth", body_type="planet", orbit_center_id="star", size_authoring_mode=USE_REFERENCE_DATA, gameplay_orbit_bias=1.18, keine scan_resources

### `res://data/celestial_bodies/solar_system/*.tres` (mercury, venus, mars, moon, jupiter, saturn, uranus, neptune)
- **Typ:** SystemBodyDefinition Resources
- **Kategorie:** Planetendaten des Sonnensystems

### `res://data/celestial_bodies/proxima_system/*.tres`
- **Typ:** SystemBodyDefinition Resources (proxima_b, proxima_c, proxima_d)

### `res://data/planet_resources/*.tres` (iron, aluminum, carbon, copper, exotic_gas, heavy_metals, helium-3, hydrocarbons, hydrogen, methane, platinum_clusters, quantum_crystals, rare_earth_elements, silicates, solar_crystals, sulfur, superconductive_compounds, titanium, water, antimatter_precursors)
- **Typ:** ScannedResourceEntry Resources
- **Properties:** resource_id (StringName), richness_percent (int)
- **Nutzende Scripts:** Referenziert in `.tres`-Dateien der SystemBodyDefinitions als Array-Elemente

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
   - Holt idle Mining Ship aus `idle_mining_ships`
   - Erstellt Runtime-Dictionary in `mining_ship_runtime_by_unit_id`:
	 - `"cargo_resource_id": "ore"` (intern, kein separates Cargo-Objekt)
	 - `"current_cargo": 0.0`, `"cargo_capacity": 20`
	 - `"mining_rate_per_second": 2.0`, `"unload_duration": 2.0`
	 - `"status": MiningShipStatus.TO_TARGET`
   - Verbindet `unit.arrived_at_target` und `unit.returned_to_base`
   - Ruft `unit.start_mission_to_node(target_node)` auf
   - Emittiert `automation_state_changed`
6. **AutomationUnit fliegt zum Ziel** (TRAVEL_TO_TARGET → APPROACH_ORBIT → WORKING + emittiert `arrived_at_target`)
7. **AutomationController._on_mining_ship_arrived_at_target():** setzt Status auf MINING, `transfer_orbit_to_base(target_node)`
8. **AutomationController._process() bei MINING-Status:**
   - Akkumuliert `current_cargo += mining_rate * (1 + drone_bonus) * delta`
   - Wenn `current_cargo >= cargo_capacity`: Status → TO_BASE, `unit.recall_to_base(home_node)`
9. **AutomationUnit kehrt zurück** → emittiert `returned_to_base`
10. **AutomationController._on_mining_ship_returned_to_base():**
	- `current_cargo = int(floor(current_cargo))`
	- **`GameSession.add_base_resource(base_id, "ore", current_cargo)`** ← Mining → Base Storage (direkter Call)
	- Setzt `current_cargo = 0`, Status → UNLOADING, `unload_timer = 2.0`
11. **Nach Unload-Timer:** wenn `loop_active`, startet neuer Flug zum Ziel; sonst: Ship wird freigegeben
12. **Nach jedem State-Wechsel:** `automation_state_changed.emit()` → `SystemUIController._on_automation_state_changed()` → `update_base_panel()` → ggf. `BaseManagementPanel.show_for_base()` / `refresh_while_hold_open()` / `hide_panel()` und `refresh_from_game_session()`

**Alte Ship-/Cargo-Logik:** KEINE. Es gibt kein Ship-Cargo-Objekt, keine `transfer_all_cargo_to_base()`-Funktion, keine `CargoPanel`-UI. Die Keys `current_cargo`/`cargo_capacity`/`cargo_resource_id` sind private Puffer in einem Dictionary innerhalb des AutomationControllers.

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
   - Für `PointOfInterestDefinition`: liest `PackedStringArray` (Kompatibilitäts-Fallback, richness_percent = -1)
   - Zählt `resources_hidden_count` via `_count_hidden_resource_slots()`
5. **ObjectInfoPanel._apply_resources()** erzeugt `ResourceInfoRow`-Instanzen mit Name + Prozentwert
6. **Scan-Mission:** Spieler klickt "Scan with Drone" → `scan_requested` → `AutomationController.launch_scan_drone()` → Drohne fliegt → `_on_scan_drone_arrived_at_target()` → `_complete_scan_mission()` → `GameSession.set_object_scan_state(system_id, target_id, SCAN_BASIC)` → `automation_state_changed` → UI-Update

---

## 8. Datenfluss: BaseManagementPanel (Base-Hub)

**Schrittweise Beschreibung:**

1. **Spieler wählt Earth (Body mit Basis)** → `selection_changed(earth_body)`
2. **SystemUIController.update_base_panel():** prüft `_selected_body_has_base(body)` → ruft `base_management_panel.show_for_base(system_id, body_id, "…", true)` auf
3. **BaseManagementPanel.show_for_base():** setzt `current_body_id`, `visible = true`, `refresh_from_game_session()`
4. **BaseManagementPanel.refresh_from_game_session():** liest Population etc. aus `GameSession`, setzt Labels (`BaseNameLabel`, `StatusLabel`, `PopulationLabel`, …), `call_deferred("_fit_height_to_content")`
5. **Spieler klickt „Production“ / „Upgrades“:** `open_production_requested` / `open_upgrades_requested` → `SystemUIController` blendet `ProductionPanel` bzw. `UpgradePanel` ein (und schließt das jeweils andere)
6. **Nach Mining-Unload:** wie in Abschnitt 6 — `automation_state_changed` → `update_base_panel()` erneut

**Hinweis:** Globale Lager-/Flotten-Kurzinfos liegen im **TopHUD** (`top_hud.gd`), nicht im Base-Hub.

---

## 9. UI Row Scenes

### `storage_info_row.tscn` — vorhanden, nicht Base-Hub
- **Status:** Szene existiert (`res://scenes/ui/system/storage_info_row.tscn`); **BaseManagementPanel** instanziiert sie aktuell **nicht** mehr
- **Root:** HBoxContainer (`StorageInfoRow`)
- **Labels:** `ResourceNameLabel`, `ResourceValueLabel`

### `resource_info_row.tscn` — AKTIV
- **Status:** Aktiv, wird von `object_info_panel.gd` verwendet
- **Script:** `resource_info_row.gd` (class ResourceInfoRow)
- **Root:** HBoxContainer (`ResourceInfoRow`)
- **Labels:** `ResourceNameLabel` (Name), `ResourceValueLabel` (Prozentwert als String, z.B. "90%")
- **Nutzung:** Dynamisch instanziiert in `ObjectInfoPanel._apply_resources()` für sichtbare Scan-Ressourcen
- **API:** `set_row_data(resource_name, percent_text)` — typsicher

### `storage_row.gd` — VERWAIST
- **Status:** VERALTET, kein `.tscn` verknüpft dieses Script
- **Script:** `storage_row.gd` (kein class_name, extends HBoxContainer)
- **Labels:** `ResourceNameLabel`, **`ResourceAmountLabel`** (abweichend von `storage_info_row.tscn` welches `ResourceValueLabel` hat)
- **Nutzung:** KEINE — wird nirgends instanziiert oder gepreladed
- **Empfehlung:** Kann sicher gelöscht werden

### `cargo_row.gd` / `cargo_row.tscn` — NICHT VORHANDEN
- **Status:** Nicht im Projekt vorhanden (bereits entfernt)

---

## 10. Alte / verwaiste Systeme

| System | Datei | Zeile/Funktion | Warum alt? | Sicher löschen? | Empfehlung |
|---|---|---|---|---|---|
| StorageRow Script | `scripts/ui/system/storage_row.gd` | gesamt | Kein .tscn verbindet dieses Script; `storage_info_row.tscn` ist der aktive Ersatz | Ja | Löschen |
| PackedStringArray in POI | `resources/definitions/point_of_interest_definition.gd` L18-20 | `scan_basic_resources: PackedStringArray` | POI nutzt altes Format; SystemBodyDefinition nutzt `Array[ScannedResourceEntry]` | Nein (Migrationsaufwand) | Auf `Array[ScannedResourceEntry]` migrieren + `.tres`-Dateien updaten |
| Kompatibilitäts-Fallback | `scripts/system/components/scan_info_builder.gd` L133-142 | `_entry_to_scan_resource()` | Fallback für String-Einträge; nur notwendig solange POI-Daten alt sind | Nein | Nach POI-Migration entfernen |
| Legacy orbit_radius/speed | `resources/definitions/system_body_definition.gd` L17-21 | `orbit_radius`, `orbit_speed` (Altbestand) | Werden von `reference_orbit_au`/`reference_period_days` + Calculator ersetzt | Nein (noch im Einsatz bei earth.tres) | Nach vollständiger Datenmigration entfernen |
| DEFAULT_MINING_DURATION | `scripts/system/controller/automation_controller.gd` L13 | `DEFAULT_MINING_DURATION = 999999.0` | Pseudo-unendlich; das Mining läuft per Cargo-Kapazität, nicht per Zeitlimit | Unsicher | Durch echtes unbegrenztes Loop ersetzen oder dokumentieren |
| can_build_base | `resources/definitions/system_body_definition.gd` L23 | `can_build_base: bool = true` | Export-Feld existiert, wird aber nirgends im Code ausgewertet | Unsicher | Auswerten oder entfernen |
| Galaxy-Map only PackedStringArray join | `scripts/galaxy/galaxy_map.gd` L153 | `join(PackedStringArray(display_parts))` | Unnötiger Umweg (join auf Array reicht in GD4) | Niedrig | Vereinfachen |

---

## 11. Fehler- und Risiko-Liste

| Risiko | Datei | Ursache | Auswirkung | Fix-Vorschlag |
|---|---|---|---|---|
| POI-Scan-Ressourcen ohne Prozentwert | `scan_info_builder.gd` L135-142 + POI-Definitionen | PackedStringArray-Fallback erzeugt `richness_percent = -1` | UI zeigt "--" statt Prozentwert für alle POI-Ressourcen | POI-Definitionen auf ScannedResourceEntry migrieren |
| ResourceAmountLabel vs ResourceValueLabel | `storage_row.gd` L3 vs `storage_info_row.tscn` | Falsch benanntes Label im verwaisten Script | Kein Fehler (Script nicht genutzt), aber Konfusionspotenzial | storage_row.gd löschen |
| automation_state_changed sehr häufig | `automation_controller.gd` | Signal wird bei fast jedem State-Wechsel emittiert (15+ Stellen) | Jeder Emit triggert `SystemUIController`-Refresh (`update_object_info`, `update_base_panel`, `_update_top_hud`; Production/Upgrade bei Sichtbarkeit) | Debounce/defer oder targeted refresh einbauen |
| _process() jedes Frame für alle Mining Ships | `automation_controller.gd` L431+ | Immer aktiv wenn `mining_ship_runtime_by_unit_id` nicht leer | Kein Performance-Problem bei kleiner Einheitenzahl; könnte bei vielen Ships skalieren | Akzeptabel, bei Bedarf optimieren |
| GameSession-Stores nicht persistiert | `game_session.gd` + alle Stores | RefCounted-Instanzen; kein Speichern/Laden | Spielzustand geht bei Applikationsende verloren | Save/Load System implementieren |
| Missions-ID-Zähler nicht persistiert | `automation_store.gd` | `next_mission_id` startet immer bei 1 | Nach Reload: ID-Konflikte theoretisch möglich (derzeit kein Problem) | Mit Save-System sichern |
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
	   │    ├─ ◄─ base_management_panel.open_production_requested / open_upgrades_requested
	   │    ├─ ◄─ production_panel.build_scan_drone_requested / build_mining_ship_requested / close_requested
	   │    ├─ ◄─ upgrade_panel.close_requested
	   │    ├─ ◄─ top_hud.hover_requested / hover_cleared
	   │    ├─ ──► ObjectInfoPanel (show_body_info, show_poi_info, show_empty, set_distance_text)
	   │    ├─ ──► BaseManagementPanel (show_for_base, hide_panel, refresh_while_hold_open)
	   │    ├─ ──► ProductionPanel / UpgradePanel (sichtbarkeit, refresh)
	   │    └─ ──► TopHudHoverPanel (show_details / clear)
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

1. **`storage_row.gd` löschen** — sicher, wird nirgends genutzt; beseitigt Konfusion mit `storage_info_row.tscn`
2. **`can_build_base` auswerten oder entfernen** — einfache Änderung; im `system_ui_controller._selected_body_has_base()` prüfen statt hart auf "earth" testen
3. **`PointOfInterestDefinition` auf `Array[ScannedResourceEntry]` migrieren** — mittlerer Aufwand; alle POI-`.tres`-Dateien updaten; danach Kompatibilitäts-Fallback in `scan_info_builder.gd` entfernen
4. **Legacy `orbit_radius`/`orbit_speed`/`body_scale`-Felder in SystemBodyDefinition bereinigen** — nach vollständiger Datenmigration auf Referenzdaten
5. **`automation_state_changed`-Frequenz reduzieren** — z.B. mit einem `call_deferred`-Debounce oder gezieltem dirty-Flag
6. **Save/Load-System implementieren** — GameSession-State persistieren; alle Stores absichern
7. **Galaxy Map: Ressourcen-Summary auf echte ScannedResourceEntry-Daten umstellen** — derzeit nutzt galaxy_map.gd noch die alten PackedStringArray-Felder von SystemBodyDefinition (L162)

---

## 14. Konkrete Suchtreffer

### `cargo` / interne Puffer-Keys (automation_controller.gd)
| Datei | Zeile | Treffer |
|---|---|---|
| automation_controller.gd | 167 | `"cargo_resource_id": DEFAULT_MINING_RESOURCE_ID` |
| automation_controller.gd | 168 | `"current_cargo": 0.0` |
| automation_controller.gd | 169 | `"cargo_capacity": DEFAULT_MINING_CARGO_CAPACITY` |
| automation_controller.gd | 171 | `"unload_duration": DEFAULT_MINING_UNLOAD_DURATION` |
| automation_controller.gd | 172 | `"unload_timer": 0.0` |
| automation_controller.gd | 455 | `current_cargo := float(runtime.get("current_cargo", 0.0))` |
| automation_controller.gd | 456 | `cargo_capacity := float(runtime.get("cargo_capacity", ...))` |
| automation_controller.gd | 461 | `current_cargo = minf(current_cargo + ..., cargo_capacity)` |
| automation_controller.gd | 515 | `resource_id := str(runtime.get("cargo_resource_id", ...))` |
| automation_controller.gd | 516 | `current_cargo := int(floor(...))` |
| automation_controller.gd | 519 | `GameSession.add_base_resource(base_id, resource_id, current_cargo)` |

**Fazit:** Alle `cargo`-Treffer sind interne Dictionary-Keys des Mining-Laufzeit-Puffers. Kein eigenständiges Ship-Cargo-Objekt.

### `OreLabel`, `FuelLabel`, `FoodLabel`
— **Nicht gefunden** in keiner Datei. Vollständig entfernt.

### `cargo_row`
— **Nicht gefunden** in keiner Datei. Vollständig entfernt.

### `ResourceList`
| Datei | Zeile | Kontext |
|---|---|---|
| object_info_panel.gd | `@onready` | `$Margin/Root/ResourcePanel/.../ResourceList` |
| object_info_panel.tscn | ResourceList | unter `ResourceScroll` |

### `storage_row` / `storage_info_row`
| Datei | Kontext |
|---|---|
| `storage_info_row.tscn` | Vorhandene Row-Szene (aktuell nicht vom Base-Hub genutzt) |
| `storage_row.gd` | Verwaistes Script — siehe `old_systems` / Abschnitt 13 |

### `automation_state_changed`
| Datei | Zeilen | Kontext |
|---|---|---|
| automation_controller.gd | 6 | `signal automation_state_changed` (Definition) |
| automation_controller.gd | 75,93,111,138,179,258,315,360,370,376,399,406,529,539,550 | `.emit()` Aufrufe |
| system_ui_controller.gd | 131-133 | Signal-Verbindung |
| system_ui_controller.gd | 271 | `func _on_automation_state_changed()` |

### `scan_basic_resources` / `ScannedResourceEntry` / `PackedStringArray`
| Datei | Zeile | Kontext |
|---|---|---|
| system_body_definition.gd | 48-50 | `Array[ScannedResourceEntry]` für basic/deep/special |
| point_of_interest_definition.gd | 18-20 | `PackedStringArray` für basic/deep/special (VERALTET) |
| scan_info_builder.gd | 113,133,157 | Kommentare + Fallback-Logik |
| galaxy_map.gd | 162 | `for resource_id in body_def.scan_basic_resources` |
| scanned_resource_entry.gd | 1 | `class_name ScannedResourceEntry` |

### `preload` / `load(`
| Datei | Zeile | Ressource |
|---|---|---|
| automation_controller.gd | 8 | `drone.tscn` |
| automation_controller.gd | 9 | `mining_ship.tscn` |
| object_info_panel.gd | 11 | `resource_info_row.tscn` |
| system_spawner.gd | 19 | `system_body.tscn` |
| system_spawner.gd | 20 | `point_of_interest.tscn` |
| scene_flow.gd | 24 | `load(scene_path)` (dynamisch) |
| game_session.gd | 55 | `load(DEFAULT_SYSTEM_PATH)` (dynamisch) |
