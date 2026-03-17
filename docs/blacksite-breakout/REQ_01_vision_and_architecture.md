# REQ_01: Vision and Architecture
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Establishes the core identity, design pillars, and technical architecture of Blacksite Breakout. This document defines what makes the game unique: asymmetric entity powers, cooperative escape gameplay, and the fundamental systems underpinning player agency.

---

## 1. Game Identity

**Core Statement:**
> "You are the thing they were trying to contain. Now you escape."

Blacksite Breakout is a cooperative tactical escape simulator where four asymmetric experimental entities must navigate the containment breach at Area 51. Each entity—Replicator, Fungus Strain, CRISPR Anomaly, and Rogue AI Construct—possesses fundamentally different movement, perception, and interaction abilities. The game rewards emergence: players discover synergies between entity types, adapt to procedurally generated sectors, and experience replaying the same escape with wildly different tactical possibilities.

---

## 2. Design Pillars

### 2.1 Asymmetric Entity Powers
- Each entity class has a distinct mechanical identity (not cosmetic variation).
- **Replicator** is a direct RTS-lite swarm — assimilates metal to grow, splits into groups to route around obstacles; **Gus (Fungus Strain)** builds a zombie army by infecting guards and researchers with spores; **Chris (CRISPR Anomaly)** starts fragile and accumulates power through environmental exposure across the run; **Rogue AI** reads facility systems passively and hacks or possesses machines to control the infrastructure.
- No "optimal" entity — team composition creates unique challenge/opportunity combinations.
- Cooperative synergy: certain entity pairs enable paths solo entities cannot access.
- **Lore connection:** The Replicator in this game is the **origin story** of the Replicants in the Replicants game. The small swarm escaping the Blacksite in Breakout is the seed colony that eventually becomes the threat in that game.

### 2.2 Tactical Decision-Making
- Movement is deliberate and consequence-weighted: sprinting attracts guards; crawling reveals position but avoids detection.
- Resource scarcity: ability cooldowns force players to prioritize and plan multi-turn sequences.
- Alarm escalation creates dynamic difficulty: a single misstep can shift a sector from exploration to combat.
- Multiple viable escape routes per sector—no single solution path.

### 2.3 Procedural Replayability
- Sector layout, guard patrol routes, and item placement vary per run (within curated constraints).
- Same seed across all players ensures synchronized procedural state (co-op consistency).
- Enough variation that repeated plays feel fresh but not chaotic—human-designed room templates assembled procedurally.

### 2.4 Cooperative Synergy
- Shared alarm state: one player's noise affects all players' risk.
- Downed system: allies can revive incapacitated teammates (no respawn).
- Entity ability combinations unlock paths: Fungus mycelium network can be used by all; Chris acid opens doors for everyone; Rogue AI hacks benefit the team.

### 2.5 Tension of Being Hunted
- Guards respond intelligently to noise and sightings—not scripted patrol routines alone.
- Alarm escalation is audible and visible: facility atmosphere shifts as danger mounts.
- No safe zones: guards adapt, search methodically, deploy in response teams.
- Resource pressure: downed allies cannot act; time spent reviving is time spent vulnerable.

---

## 3. Core Rules

### 3.1 Action-Point Movement System
Blacksite Breakout uses a **real-time movement model with ability pause**—inspired by Fallout 2's tactical hybrid:

- **Movement phase (real-time):** Players navigate via click-to-move or WASD, character auto-pathfinding to destination.
- **Ability use (pseudo-turn-based):** Activating an ability (hack, spore cloud, assimilate) causes a brief pause; ability executes; recovery timer enforces cooldown.
- **No round timer:** Exploration progresses fluidly until an encounter or alarm escalation triggers heightened tension.
- **Noise-based engagement:** Guard detection is probabilistic, distance-based—not instant.

### 3.2 Fog of War
- **Unexplored tiles:** Hidden until line of sight or movement passes through.
- **Explored tiles:** Visible in layout (walls, doors) but not live-updated (last known state remains visible).
- **Current visible area:** Bright; recently explored areas gradually fade to "remembered" visual state.
- **Guard line of sight:** Guards see through unveiled area with their detection cone; entities do not automatically see guards outside their visible radius.

### 3.3 Asymmetric Entity Classes with Distinct Ability Sets
Four playable entities, each with three abilities (one passive, two active), detailed in REQ_03.

### 3.4 No Respawn; Downed State
- When an entity takes fatal damage, it becomes **Downed** (prone, incapacitated, rendering 50% opacity).
- An ally must move adjacent and press interact to **Revive** (takes ~3 seconds, uninterruptible; reviving player cannot move during).
- If no ally revives within ~60 seconds (or all allies are also downed), the entity is **Captured** and permanently removed from the run.
- **Run fails** if all four entities are captured or downed simultaneously.

---

## 4. Visual Tone and Aesthetics

### 4.1 Isometric Facility Design
- **Camera perspective:** Isometric (45° top-down, 2D projection of 3D space conceptually).
- **Early sectors:** Sterile, gridded containment chambers; clean surveillance lighting; hum of machinery.
- **Late sectors:** Damage and corruption visible—shattered glass, sparking conduits, biohazard breaches, physical entity of the breach manifesting.
- **Color grading per sector:** Sector 1–2 cool/blue (containment intact); Sector 3–4 amber warnings; Sector 5+ red/chaotic (containment failure).

### 4.2 Entity Visual Language
Each entity has a distinct silhouette and color palette to enable quick visual parsing in co-op:

| Entity | Silhouette | Primary Color | Secondary | Aura / Special |
|--------|-----------|---------------|-----------|------|
| Replicator | Swarm of small geometric spider-units; individually tiny, collectively reads as one mass | Chrome silver | Dark metallic joints | Shimmer ripple across the swarm when moving; units visibly split into two clusters during Swarm Split |
| Gus (Fungus Strain) | Bulbous, low-slung; mycelium tendrils trailing | Deep green | Amber spore particles | Mycelium trails left on floor; Fungus Pawns (infected guards) have green-amber tint and stumbling gait |
| Chris (CRISPR Anomaly) | Humanoid but increasingly unstable outline as traits absorb; visible mutations stack on body | Iridescent shifting | Bioluminescent spots | Appearance visibly mutates on each Chimera Trait absorbed — plating, tendrils, spore patches layer on |
| Rogue AI | Angular maintenance drone chassis; sterile and utilitarian | Electric blue | Cyan code-stream | Glitch trails and pixelated edges; avatar goes dim/still during Machine Possession; target machine pulses blue |

**Replicator note:** Individual units are small enough to read as a swarm, not as individual characters. The swarm group should feel like one entity with mass, not a squad of soldiers. When split, the two groups should feel like a dividing organism.

**Chris note:** At run start, Chris looks nearly human (damaged and unstable, but recognizable). By run end with 4–5 traits, Chris should look genuinely monstrous. The visual progression communicates power state to both the player and teammates.

### 4.3 Facility Aesthetics
- **Containment chambers:** Reinforced concrete, metal grating, blast doors, observation windows.
- **Surveillance:** Rotating cameras mounted visibly on walls and ceilings with clear detection cones.
- **Vents:** Metal ducting, grilles, accessible from multiple rooms—entity-class access varies.
- **Terminals:** Soft-glowing screens, recognizable computer interfaces, clearance indicators.

---

## 5. Godot 2D Scene Architecture

### 5.1 Class Hierarchy

```
Node (Root - Blacksite_Breakout_Encounter)
├── SectorMap (TileMap + FogOfWar Layer)
├── EntityManager (tracks player entities, co-op sync)
│   ├── EntityCharacter [Replicator] (CharacterBody2D)
│   ├── EntityCharacter [Fungus Strain] (CharacterBody2D)
│   ├── EntityCharacter [CRISPR/Chris] (CharacterBody2D)
│   └── EntityCharacter [Rogue AI] (CharacterBody2D)
├── GuardManager (manages all NPC guards)
│   ├── ContainmentGuard_Patrol (CharacterBody2D + LimboAI tree)
│   ├── ContainmentGuard_Sentry (Area2D detection + LimboAI)
│   └── ContainmentGuard_Response (spawned on alarm escalation)
├── InteractableManager
│   ├── InteractableObject_Door (StaticBody2D + Area2D for prompt)
│   ├── InteractableObject_Terminal (StaticBody2D + Area2D)
│   ├── InteractableObject_Vent (Area2D, entity-class dependent)
│   ├── InteractableObject_Item (Area2D, pickup)
│   └── InteractableObject_Guard (Area2D, encounter node)
├── SurveillanceSystem
│   ├── SurveillanceCamera (Area2D detection cone, rotation)
│   └── CameraNetwork (tracks all active cameras)
├── AlarmSystem (node managing facility-wide alert state)
├── MusicManager (shared infrastructure, sets intensity multipliers)
├── GameManager (shared infrastructure, session state)
└── UILayer
    ├── HUD_EntityStatus (health, cooldowns, alarm meter)
    ├── HUD_Minimap (fog-of-war map with entity dots)
    ├── HUD_InteractPrompt (context-sensitive interact button)
    └── HUD_AlarmIndicator (visual alarm escalation)
```

### 5.2 Key Node Types

#### EntityCharacter (Base)
**Extends:** `CharacterBody2D`

**Purpose:** Base class for all four playable entities. Handles movement, ability state, health, and co-op state synchronization.

**Key Properties:**
```gdscript
class_name EntityCharacter
extends CharacterBody2D

enum EntityType { REPLICATOR, FUNGUS_STRAIN, CRISPR, ROGUE_AI }

@export var entity_type: EntityType
@export var move_speed: float = 150.0
@export var max_health: float = 100.0
@onready var health: float = max_health
@onready var is_downed: bool = false
@onready var current_alarm_level: int = 0

var velocity: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var active_abilities: Array[BaseAbility] = []
var passive_trait: PassiveTrait

# Ability state
var ability_1_cooldown: float = 0.0
var ability_2_cooldown: float = 0.0
var ultimate_cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	update_cooldowns(delta)
	if not is_downed:
		handle_movement(delta)
	velocity = move_and_slide()

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		become_downed()

func become_downed() -> void:
	is_downed = true
	modulate.a = 0.5
	signal_allies_downed()

func revive_by_ally(reviver: EntityCharacter) -> void:
	is_downed = false
	health = max_health * 0.5
	modulate.a = 1.0
	signal_revived()

func activate_ability(ability_index: int) -> void:
	if ability_index >= active_abilities.size():
		return
	var ability = active_abilities[ability_index]
	if ability.is_ready():
		ability.execute(self)
		ability.start_cooldown()
```

#### ContainmentGuard (AI)
**Extends:** `CharacterBody2D`, uses **LimboAI** behavior tree

**Purpose:** Enemy NPC with adaptive patrol, detection, and response behaviors.

**Key Behavior States:**
- **PATROL:** Walk assigned route, listen for noise.
- **INVESTIGATE:** Walk to noise source, scan area.
- **ALERT:** Call for backup, increase search intensity.
- **ENGAGE:** Attack detected entity, call response team.
- **RESPOND:** Coordinated sweep with other guards on alarm escalation.

#### SectorMap
**Extends:** `TileMap` + custom `FogOfWar` layer

**Purpose:** Renders sector layout and manages visibility state.

**Key Methods:**
```gdscript
class_name SectorMap
extends TileMap

@export var fog_layer_index: int = 1

func reveal_tile(tile_pos: Vector2i) -> void:
	var cell = get_cell_source_id(fog_layer_index, tile_pos)
	set_cell(fog_layer_index, tile_pos, -1)  # Remove fog

func get_revealed_area() -> Array[Vector2i]:
	var revealed = []
	for cell in get_used_cells(fog_layer_index):
		if get_cell_source_id(fog_layer_index, cell) == -1:
			revealed.append(cell)
	return revealed
```

#### SurveillanceCamera
**Extends:** `Area2D`

**Purpose:** Detects entities within a cone, triggers alarm if entity visible.

**Key Logic:**
```gdscript
class_name SurveillanceCamera
extends Area2D

@export var rotation_speed: float = 1.0
@export var detection_range: float = 300.0
@export var detection_angle: float = 90.0
@export var alarm_network: AlarmSystem

@onready var detection_cone: Area2D = $DetectionCone

func _process(delta: float) -> void:
	rotate(rotation_speed * delta)
	check_detection()

func check_detection() -> void:
	var entities = detection_cone.get_overlapping_areas()
	for entity in entities:
		if entity is EntityCharacter:
			if is_in_line_of_sight(entity.global_position):
				alarm_network.escalate_alarm(global_position)
				break

func is_in_line_of_sight(target_pos: Vector2) -> bool:
	var to_target = target_pos - global_position
	var angle_to_target = to_target.angle()
	var angle_diff = abs(angle_difference(rotation, angle_to_target))
	return angle_diff <= detection_angle / 2.0
```

#### AlarmSystem
**Extends:** `Node`

**Purpose:** Centralized alarm state management; coordinates guard escalation and facility-wide alerts.

**Alarm Levels:**
```gdscript
enum AlarmLevel { QUIET, LOCAL_ALERT, SECTOR_LOCKDOWN, FACILITY_ALERT }

class_name AlarmSystem
extends Node

@export var quiet_cooldown: float = 30.0
@export var local_alert_duration: float = 45.0
@export var sector_lockdown_duration: float = 60.0
@export var facility_alert_duration: float = 90.0

var current_level: AlarmLevel = AlarmLevel.QUIET
var level_timer: float = 0.0
var alarm_origin: Vector2 = Vector2.ZERO

signal alarm_escalated(level: AlarmLevel)
signal alarm_reduced(level: AlarmLevel)

func escalate_alarm(origin: Vector2) -> void:
	alarm_origin = origin
	if current_level == AlarmLevel.QUIET:
		set_alarm_level(AlarmLevel.LOCAL_ALERT)
	elif current_level == AlarmLevel.LOCAL_ALERT:
		set_alarm_level(AlarmLevel.SECTOR_LOCKDOWN)
	elif current_level == AlarmLevel.SECTOR_LOCKDOWN:
		set_alarm_level(AlarmLevel.FACILITY_ALERT)

func set_alarm_level(new_level: AlarmLevel) -> void:
	current_level = new_level
	level_timer = get_duration_for_level(new_level)
	alarm_escalated.emit(new_level)
	print("Alarm escalated to: %s" % AlarmLevel.keys()[new_level])

func get_duration_for_level(level: AlarmLevel) -> float:
	match level:
		AlarmLevel.QUIET: return 999.0  # No timer
		AlarmLevel.LOCAL_ALERT: return local_alert_duration
		AlarmLevel.SECTOR_LOCKDOWN: return sector_lockdown_duration
		AlarmLevel.FACILITY_ALERT: return facility_alert_duration
	return 0.0
```

---

## 6. Scene Hierarchy Diagram

```
Blacksite_Breakout_Encounter (Root)
│
├─ SectorMap (TileMap)
│  └─ [tiles + fog layer + collision layer]
│
├─ EntityManager (Node)
│  ├─ Player_Replicator (EntityCharacter)
│  │  └─ [Sprite, CollisionShape, DetectionArea, AnimationPlayer]
│  ├─ Player_FungusStrain (EntityCharacter)
│  │  └─ [Sprite, CollisionShape, DetectionArea, AnimationPlayer]
│  ├─ Player_CRISPR (EntityCharacter)
│  │  └─ [Sprite, CollisionShape, DetectionArea, AnimationPlayer]
│  └─ Player_RogueAI (EntityCharacter)
│     └─ [Sprite, CollisionShape, DetectionArea, AnimationPlayer]
│
├─ GuardManager (Node)
│  ├─ Guard_Patrol_01 (ContainmentGuard + LimboAI)
│  ├─ Guard_Sentry_02 (ContainmentGuard + LimboAI)
│  └─ [spawner for Response Team on alarm]
│
├─ InteractableManager (Node)
│  ├─ Door_Vault_A (InteractableObject_Door)
│  ├─ Terminal_Access (InteractableObject_Terminal)
│  ├─ Vent_East (InteractableObject_Vent)
│  ├─ Medkit_Item (InteractableObject_Item)
│  └─ [other interactables]
│
├─ SurveillanceSystem (Node)
│  ├─ Camera_NorthWest (SurveillanceCamera)
│  ├─ Camera_Center (SurveillanceCamera)
│  └─ CameraNetwork (AlarmSystem child)
│
├─ AlarmSystem (Node)
│  └─ [manages facility-wide alert escalation]
│
├─ MusicManager (Node) [shared infrastructure]
│
├─ GameManager (Node) [shared infrastructure]
│
└─ UILayer (CanvasLayer)
   ├─ HUD_EntityStatus (Control)
   ├─ HUD_Minimap (Control)
   ├─ HUD_InteractPrompt (Control)
   └─ HUD_AlarmIndicator (Control)
```

---

## 7. Implementation Notes

### 7.1 Co-op Synchronization
- All procedurally generated content (sector layout, guard patrol routes, item placement) is seeded identically across clients.
- Entity positions and alarm state are synchronized via GameManager's co-op data layer.
- Downed state is broadcast to all players in real-time.

### 7.2 Performance Considerations
- Guard pathfinding uses precomputed navigation mesh to avoid runtime A* overhead.
- Fog of war updates only on entity movement, not every frame.
- Particle effects (spore clouds, assimilation shimmer) are pooled and reused.

### 7.3 Accessibility
- All audio cues (alarm escalation, guard proximity) have visual equivalents (HUD indicators, screen tint changes).
- Controller support is primary; keyboard/mouse fallback supported.

---

## 8. Related Documents
- REQ_02: Game State Machine (state flow and transitions)
- REQ_03: Entity Classes and Abilities (detailed ability sets per entity)
- REQ_04: Movement and Interaction (input handling, interactables)
- REQ_05: Procedural Map Generation (sector assembly and room templates)
- REQ_06: Guard AI and Alarm System (LimboAI behavior trees, detection logic)

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
