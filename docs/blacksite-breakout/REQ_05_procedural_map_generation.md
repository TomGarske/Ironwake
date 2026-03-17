# REQ_05: Procedural Map Generation
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines the procedural sector generation system, room template assembly, fog of war mechanics, and guaranteed sector elements. Emphasizes curated replayability over pure randomness.

---

## 1. Sector Generation Overview

### 1.1 Design Philosophy
Blacksite Breakout does **not** use pure random generation. Instead, it uses **template-based assembly**:
- Pre-authored room templates (hand-designed, tested for balance and flow).
- Rooms are assembled procedurally based on seed + difficulty tier.
- Connectors (doors, vents) link rooms into a cohesive sector.
- Guaranteed elements (entry, exit, objective, obstacles) are enforced via rules.

**Benefits:**
- Maintains design quality and balance.
- Enables rapid iteration (design templates, not algorithms).
- Provides replayability (different combinations per seed).
- Ensures completability (no unsolvable procedural generation).

### 1.2 Generation Pipeline
```
Random Seed (co-op synchronized)
    ↓
Load Sector Difficulty Tier (1–5)
    ↓
Select Room Templates (based on tier + seed)
    ↓
Assemble Room Layout (connectors, placement)
    ↓
Populate Interactables (doors, terminals, items)
    ↓
Spawn Guards & Patrol Routes (difficulty-scaled)
    ↓
Bake Navigation Mesh & Fog of War
    ↓
Render Sector in Godot
```

---

## 2. Room Template System

### 2.1 Room Template Categories
Each room template is a pre-authored TileMap + Node structure saved as a `.tscn` file.

| Category | Purpose | Size | Examples |
|---|---|---|---|
| **Corridor** | Connector between rooms | 300×200 | Straight, L-bend, T-junction |
| **Guard Post** | Patrol/sentry base | 400×300 | Desk, barricade, observation window |
| **Lab** | Research facility | 500×400 | Equipment, containment vessels, workstations |
| **Storage** | Item/supply room | 350×350 | Shelves, crates, medkit spawns |
| **Server Room** | Hackable systems | 300×250 | Terminals, server racks, cooling systems |
| **Vent Network** | Hidden traversal | 400×200 | Metal ducting, grilles, tight spaces |
| **Holding Cell** | Containment chamber | 250×300 | Glass walls, isolation pods, alarm buttons |
| **Exit Zone** | Sector transition | 300×250 | Door to next sector, decontamination area |

### 2.2 Template Metadata
Each room template has a `.tres` metadata resource:

```gdscript
class_name RoomTemplate
extends Resource

@export var template_name: String = "Corridor_Straight"
@export var scene_path: String = "res://scenes/game/area51/room_templates/Corridor_Straight.tscn"
@export var size: Vector2i = Vector2i(300, 200)
@export var category: String = "corridor"
@export var difficulty_min: int = 1  # Can appear in sector tier 1+
@export var difficulty_max: int = 5  # Can appear up to sector tier 5
@export var required_connection_points: int = 2  # How many connectors this room expects
@export var has_objective_location: bool = false  # Can place objective here
@export var has_item_spawn: bool = false  # Can spawn items here
@export var has_guard_spawn: bool = true  # Guards can patrol here
@export var has_hidden_vent: bool = false  # Contains optional vent path

func can_use_in_sector(sector_tier: int) -> bool:
	return sector_tier >= difficulty_min and sector_tier <= difficulty_max
```

### 2.3 Room Template Assembly
**Assembly algorithm:**
1. Seed the random number generator with co-op session seed.
2. For each sector tier (1–5):
   - Determine room count: 4–6 rooms per sector (tier determines range).
   - Select entry room (always "Entry_Zone" template).
   - Select 2–3 main rooms from allowed templates.
   - Select exit room (always "Exit_Zone" template).
   - Generate 1–2 connector corridors between main rooms.
3. Place rooms on a virtual grid; connectors link them.
4. Validate sector layout (entry→main→exit path exists).
5. Instantiate rooms in Godot scene tree.

**GDScript - Sector Generator:**
```gdscript
class_name SectorGenerator
extends Node

@export var room_template_directory: String = "res://scenes/game/area51/room_templates/"
@export var sector_tier: int = 1
@export var random_seed: int = 42

var room_templates: Array[RoomTemplate] = []
var sector_rooms: Array[Node2D] = []

func _ready() -> void:
	load_room_templates()

func load_room_templates() -> void:
	var dir = DirAccess.open(room_template_directory)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			if filename.ends_with(".tres"):
				var template = load(room_template_directory + filename)
				room_templates.append(template)
			filename = dir.get_next()
	print("Loaded %d room templates" % room_templates.size())

func generate_sector() -> void:
	randi_seed(random_seed)

	# Step 1: Select rooms
	var selected_rooms = select_rooms_for_tier(sector_tier)
	print("Selected %d rooms for sector tier %d" % [selected_rooms.size(), sector_tier])

	# Step 2: Assemble layout
	var layout = assemble_room_layout(selected_rooms)

	# Step 3: Instantiate rooms
	for room_data in layout:
		instantiate_room(room_data)

	# Step 4: Populate interactables and guards
	populate_interactables()
	populate_guards()

	print("Sector generation complete")

func select_rooms_for_tier(tier: int) -> Array:
	var selected = []

	# Entry room
	var entry_template = room_templates.filter(func(t): return t.template_name.contains("Entry"))[0]
	selected.append(entry_template)

	# Main rooms
	var main_room_count = randi_range(2, 3)
	var allowed_templates = room_templates.filter(func(t): return t.can_use_in_sector(tier))
	for i in range(main_room_count):
		var random_template = allowed_templates[randi() % allowed_templates.size()]
		selected.append(random_template)

	# Exit room
	var exit_template = room_templates.filter(func(t): return t.template_name.contains("Exit"))[0]
	selected.append(exit_template)

	return selected

func assemble_room_layout(selected_rooms: Array) -> Array:
	var layout = []
	var current_position = Vector2i.ZERO

	for room_template in selected_rooms:
		var room_data = {
			"template": room_template,
			"position": current_position
		}
		layout.append(room_data)

		# Advance position for next room
		current_position += Vector2i(room_template.size.x + 100, 0)

	return layout

func instantiate_room(room_data: Dictionary) -> void:
	var template = room_data["template"]
	var position = room_data["position"]

	var room_scene = load(template.scene_path)
	var room_instance = room_scene.instantiate()
	room_instance.position = position

	add_child(room_instance)
	sector_rooms.append(room_instance)

func populate_interactables() -> void:
	for room in sector_rooms:
		var interactables = room.get_tree().get_nodes_in_group("interactables")
		for interactable in interactables:
			# Assign type, properties based on room and sector tier
			pass

func populate_guards() -> void:
	var guard_count = sector_tier * 2 + randi_range(0, 2)
	for i in range(guard_count):
		spawn_guard_in_random_room()

func spawn_guard_in_random_room() -> void:
	var room = sector_rooms[randi() % sector_rooms.size()]
	var guard_type = randi() % 3  # Select guard type
	# Instantiate guard in room
```

---

## 3. Fog of War System

### 3.1 Fog Layer
- Fog of war is rendered as a separate TileMap layer on top of the sector.
- Tiles in the fog layer represent unexplored areas.
- As entities explore, tiles are removed from fog layer (revealed).

### 3.2 Visibility States
Each tile has three visibility states:

| State | Visual | Behavior |
|---|---|---|
| **Hidden (Fog)** | Opaque gray overlay | Tile layout unknown; guards invisible; items not visible |
| **Explored** | Partially transparent | Tile layout visible; static objects visible; guards/items not visible (last known state) |
| **Current Visible** | Fully transparent | Tile fully visible; guards and dynamic objects visible in real-time |

### 3.3 Revelation Mechanics
Fog is revealed when:
1. **Player movement:** Entity moves through a tile; that tile and adjacent tiles (9-tile radius) revealed.
2. **Line of sight:** Walls block revelation; entity must navigate to see beyond obstruction.
3. **Ability effects:** Spore clouds, hacks, and other abilities may reveal small areas temporarily.

**GDScript - Fog of War:**
```gdscript
class_name FogOfWarSystem
extends TileMap

@export var fog_layer: int = 1
@export var reveal_radius: int = 3  # 3-tile radius around entity

var revealed_tiles: Dictionary = {}  # tile_pos -> true (for fast lookup)

func _ready() -> void:
	initialize_fog()

func initialize_fog() -> void:
	# Fill entire fog layer with fog tiles
	for cell in get_used_cells(0):  # Layer 0 = base map
		set_cell(fog_layer, cell, 0, Vector2i.ZERO)  # Place fog tile

func reveal_tiles_around_entity(entity: EntityCharacter) -> void:
	var entity_tile_pos = local_to_map(entity.global_position)

	# Reveal entity tile and radius
	for x in range(entity_tile_pos.x - reveal_radius, entity_tile_pos.x + reveal_radius + 1):
		for y in range(entity_tile_pos.y - reveal_radius, entity_tile_pos.y + reveal_radius + 1):
			var tile_pos = Vector2i(x, y)

			# Check line of sight from entity to tile
			if has_line_of_sight(entity.global_position, map_to_local(tile_pos)):
				reveal_tile(tile_pos)

func reveal_tile(tile_pos: Vector2i) -> void:
	if tile_pos not in revealed_tiles:
		erase_cell(fog_layer, tile_pos)  # Remove fog tile
		revealed_tiles[tile_pos] = true

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from, to)
	var result = space_state.intersect_ray(query)
	return result.is_empty()  # No obstruction = line of sight

func get_revealed_area_percentage() -> float:
	var total_tiles = get_used_cells(0).size()
	var revealed_count = revealed_tiles.size()
	return float(revealed_count) / float(total_tiles) * 100.0
```

---

## 4. Guaranteed Sector Elements

Every generated sector must include:

### 4.1 Entry Point
- **Location:** Room labeled "Entry_Zone."
- **Spawn position:** Entities spawn here at sector start.
- **Visibility:** Visible to guards initially; guards may be patrolling nearby.

### 4.2 Sector Objective
- **Type:** One of: retrieve item, hack terminal, reach location, defeat key guard.
- **Placement:** Randomly placed in 1 of 2–3 main rooms.
- **Difficulty scaling:** Tier 1 = simple (item pickup), Tier 5 = complex (multi-step hack).

### 4.3 Obstacle Requiring Entity Ability
- **Example:** Metal grating (requires Replicator assimilate or Chris acid).
- **Placement:** On path to objective or exit; guarantees entity specialization is useful.
- **Guarantee:** Sector includes at least one ability-gated obstacle unique to each entity class.

**GDScript - Obstacle Placement:**
```gdscript
class_name ObstaclePlacement
extends Node

@export var obstacles_per_sector: int = 3

enum ObstacleType { METAL_GRATE, LOCKED_DOOR, BIOHAZARD_WALL, SENSOR_GRID, FUNGAL_GROWTH }

var placed_obstacles: Array = []

func place_obstacles_for_sector(sector_rooms: Array) -> void:
	for i in range(obstacles_per_sector):
		var obstacle_type = ObstacleType.values()[randi() % ObstacleType.size()]
		var random_room = sector_rooms[randi() % sector_rooms.size()]
		place_obstacle(random_room, obstacle_type)

func place_obstacle(room: Node2D, obstacle_type: int) -> void:
	var obstacle_scene: PackedScene
	match obstacle_type:
		ObstacleType.METAL_GRATE:
			obstacle_scene = load("res://scenes/game/area51/obstacles/MetalGrate.tscn")
		ObstacleType.LOCKED_DOOR:
			obstacle_scene = load("res://scenes/game/area51/obstacles/LockedDoor.tscn")
		# ... other obstacles

	var obstacle_instance = obstacle_scene.instantiate()
	obstacle_instance.position = room.get_random_spawn_position()
	room.add_child(obstacle_instance)
	placed_obstacles.append(obstacle_instance)
```

### 4.4 Exit Zone
- **Location:** Room labeled "Exit_Zone."
- **Access:** Unlocked after objective completed.
- **Interaction:** Entity enters exit zone and interacts to transition to next sector.

### 4.5 At Least One Hidden Path
- **Type:** Optional vent, secret passage, or skill-gated shortcut.
- **Access:** Requires entity ability (Replicator vent teleport, Fungus mycelium, CRISPR mutation, Rogue AI hack).
- **Benefit:** Faster route to exit; rewards exploration and ability use.

---

## 5. Guard Placement & Patrol Routes

### 5.1 Guard Count by Sector Tier
| Sector Tier | Guard Count | Heavy Guards | Response Teams |
|---|---|---|---|
| 1 | 2–3 | 0 | 0 |
| 2 | 3–4 | 0 | 0 |
| 3 | 4–5 | 1 | 0 |
| 4 | 5–7 | 2 | 1 |
| 5 | 7–10 | 3 | 2 |

### 5.2 Guard Type Distribution
- **Patrol Guards:** 70% of total count.
- **Stationary Sentries:** 20% (placed at key points: entry, objective, exit).
- **Specialist Guards:** 10% (tier 3+ only).

### 5.3 Patrol Route Generation
Patrol routes are generated per guard:
1. Guard spawns in a room.
2. Seed-based pathfinding algorithm generates 3–5 waypoints within connected rooms.
3. Guard walks waypoint→waypoint, loops on completion.
4. Waypoints avoid player start position (entities have initial safety period).

**GDScript - Patrol Route:**
```gdscript
class_name PatrolRoute
extends Node2D

@export var waypoints: Array[Vector2] = []
@export var wait_time_at_waypoint: float = 2.0

var current_waypoint_index: int = 0
var guard_ref: ContainmentGuard

func generate_route(start_pos: Vector2, connected_rooms: Array[Node2D], seed: int) -> void:
	randi_seed(seed)
	var route_length = randi_range(3, 5)

	var current_pos = start_pos
	for i in range(route_length):
		var random_room = connected_rooms[randi() % connected_rooms.size()]
		var waypoint = random_room.get_random_spawn_position()
		waypoints.append(waypoint)

	print("Generated patrol route with %d waypoints" % waypoints.size())

func get_next_waypoint() -> Vector2:
	var waypoint = waypoints[current_waypoint_index]
	current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
	return waypoint

func assign_to_guard(guard: ContainmentGuard) -> void:
	guard_ref = guard
	guard_ref.patrol_route = self
```

---

## 6. Item Placement

### 6.1 Item Distribution
| Item Type | Quantity | Placement | Visibility |
|---|---|---|---|
| Keycard | 1–2 | Guard post, storage | After exploration |
| Medkit | 2–3 | Storage, lab, hidden corner | Visible (high-value pickup) |
| Tool (hacking, lockpick) | 0–1 | Terminal room, hidden vent | Hidden initially |
| Objective Key Item | 1 | Objective location, guarded | Visible but protected |

### 6.2 Item Randomization
Items are placed using seed-based random selection:
- Seed determines which rooms receive items.
- Seed determines item type and quantity per room.
- Co-op ensures all players see same item placement.

---

## 7. Difficulty Progression

### 7.1 Sector Tier Scaling
| Tier | Rooms | Guards | Difficulty | Theme |
|---|---|---|---|---|
| 1 | 4 | 2–3 | Easy | Clean containment |
| 2 | 5 | 3–4 | Easy-Medium | Standard facility |
| 3 | 5–6 | 4–5 | Medium | Beginning breach |
| 4 | 6 | 5–7 | Medium-Hard | Active containment failure |
| 5 | 6–7 | 7–10 | Hard | Full facility collapse |

### 7.2 Difficulty Modifiers
Optional gameplay modifiers (player selectable at LOBBY state):
- **Iron Mode:** No medkits; downed entities captured immediately.
- **Hardcore:** Permadeath (failed run cannot be retried; must restart entire facility escape).
- **Speedrun:** Timer; must escape within 20 minutes.

---

## 8. Seed Management & Co-op Sync

### 8.1 Run Seed
- **Generation:** Random seed generated at run start (via GameManager).
- **Synchronization:** All players receive same seed via GameManager.broadcast_run_seed(seed).
- **Persistence:** Same seed used for all five sectors (Sector 1–5 generation uses Sector + Seed to ensure unique-but-consistent layouts).

### 8.2 Sector-Specific Seed
Each sector derives its unique seed:
```
sector_seed = (base_seed * 73856093 ^ sector_number * 19349663) % 2^31
```
This ensures Sector 1 looks different from Sector 2 with same base seed, while remaining deterministic.

**GDScript - Seed Management:**
```gdscript
class_name SeedManager
extends Node

var run_seed: int = 0
var sector_number: int = 1

func initialize_run_seed() -> void:
	run_seed = randi()
	print("Run seed: %d" % run_seed)

func get_sector_seed() -> int:
	var sector_seed = (run_seed * 73856093) ^ (sector_number * 19349663)
	return int(sector_seed) % int(pow(2, 31))

func next_sector() -> void:
	sector_number += 1
```

---

## 9. Navigation Mesh Baking

After sector generation:
1. Sector TileMap and collision shapes are finalized.
2. NavigationRegion2D is baked using Godot's built-in navigation system.
3. NavMesh is used for:
   - Player pathfinding (click-to-move).
   - Guard patrol pathfinding.
   - Entity AI avoidance.

**Baking script:**
```gdscript
class_name NavigationMeshBaker
extends Node

@export var tilemap: TileMap
@export var navigation_region: NavigationRegion2D

func bake_navigation_mesh() -> void:
	print("Baking navigation mesh...")
	NavigationServer2D.bake_from_source_geometry_data(
		navigation_region.navigation_polygon,
		NavigationPolygon.new()
	)
	print("Navigation mesh baked")
```

---

## 10. Implementation Notes

### 10.1 Room Template Structure
Each room template `.tscn` should include:
- **TileMap layer:** Base floor/wall tiles.
- **Collision layer:** Collision shapes for walls, obstacles.
- **Interactable nodes:** Doors, terminals, vents (named and tagged).
- **Spawn points:** Named Node2D markers for guard/item spawning.
- **Metadata:** RoomTemplate resource attached as script/property.

### 10.2 Procedural Validation
Before rendering a sector:
1. Validate path exists from entry→objective→exit.
2. Check that at least one entity-ability obstacle exists per entity class.
3. Verify guard placement doesn't completely block all paths.
4. Confirm items are placed in accessible locations.

### 10.3 Performance Optimization
- Pre-load room template scenes in editor (avoid runtime loading delays).
- Use object pooling for guard instances (reuse instances across sectors).
- Bake navigation mesh at sector load time, not generation time.

---

## 11. Related Documents
- REQ_01: Vision and Architecture (SectorMap node structure)
- REQ_02: Game State Machine (SECTOR_EXPLORATION state)
- REQ_03: Entity Classes and Abilities (ability-gated obstacles)
- REQ_06: Guard AI and Alarm System (guard placement, patrol routes)

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
