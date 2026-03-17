# REQ_06: Escapee AI
**Behavior Trees, Types, and Difficulty Scaling**

## Escapee Types

All escapees share a base EscapeeEntity class but differ in stats and behavior. Each type has a LimboAI behavior tree defining its decision logic.

### Type 1: Basic Runner

**Role**: Straightforward threat; primary wave filler.

**Stats**:
- Health: 50 HP (baseline)
- Speed: 15 m/s
- Size: 1.0 (small collision radius)
- Aggression: Low (no special attacks; only flees)

**Behavior**:
- Direct path to perimeter breach point via NavigationAgent3D.
- No evasion; no predictive movement.
- If damaged, no behavioral change (continues toward breach).
- Despawns on death (no loot, no persistent effect).

**LimboAI Tree**:
```
Root (Composite/Selector)
├── [Condition] IsAlive?
│   └── [Sequence]
│       ├── [Task] UpdateNavigation (toward breach)
│       ├── [Task] MoveTowardTarget (speed: 15 m/s)
│       └── [Condition] ReachedBreach? → Destroy
└── [Task] Destroy
```

**Use Case**: Waves 1–2 bulk; teaches players basic targeting and tracking.

---

### Type 2: Evader

**Role**: Evasive threat; requires prediction and cooperation.

**Stats**:
- Health: 65 HP
- Speed: 18 m/s
- Size: 1.0
- Aggression: Medium (jinks and strafes away from incoming fire)

**Behavior**:
- Primary path to breach, but **strafes left/right** when threatened.
- Detects incoming laser/orbital fire and dodges (simple prediction: move perpendicular to threat vector).
- Unpredictable path changes every 2–3 seconds even without threat (keeps drones guessing).
- If cornered, no surrender; continues fleeing.

**Evasion Logic**:
```gdscript
# EscapeeEvader.gd (excerpt)
class_name EscapeeEvader
extends EscapeeEntity

const BASE_SPEED: float = 18.0
const STRAFE_DISTANCE: float = 5.0
const EVASION_REACTION_TIME: float = 0.4  # seconds

var threat_vector: Vector3 = Vector3.ZERO
var evasion_direction: int = 1  # 1 = left, -1 = right
var evasion_timer: float = 0.0

func detect_incoming_threat() -> void:
	# Check for nearby drones or incoming lasers
	var nearby_drones = get_nearby_drones()
	if nearby_drones.size() > 0:
		var closest_drone = nearby_drones[0]
		var direction_to_drone = global_position.direction_to(closest_drone.global_position)
		evasion_direction = 1 if randf() > 0.5 else -1
		# Strafe perpendicular to threat
		var strafe_vector = direction_to_drone.cross(Vector3.UP) * evasion_direction
		nav_agent.set_velocity(strafe_vector * BASE_SPEED)

func _physics_process(delta: float) -> void:
	evasion_timer -= delta
	if evasion_timer <= 0.0:
		detect_incoming_threat()
		evasion_timer = randf_range(2.0, 3.0)

	var next_path_pos = nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_path_pos) * BASE_SPEED
	move_and_slide()
```

**LimboAI Tree**:
```
Root (Selector)
├── [Condition] IsThreatened?
│   └── [Parallel]
│       ├── [Task] Strafe (perpendicular to threat)
│       └── [Task] NavigateTowardBreach
├── [Sequence]
│   ├── [Task] RandomPathVariation (every 3s)
│   └── [Task] MoveTowardTarget
└── [Task] Destroy
```

**Use Case**: Waves 2–3; teaches leading shots and cooperative focus fire.

---

### Type 3: Tank

**Role**: High-durability roadblock; requires sustained fire or orbital strikes.

**Stats**:
- Health: 250 HP (5x Basic Runner)
- Speed: 8 m/s (very slow)
- Size: 2.0 (large collision radius)
- Aggression: None (purely defensive; doesn't flee)

**Behavior**:
- Walks toward breach at constant slow speed.
- No evasion; no awareness of damage.
- If destroyed, brief explosion VFX (stronger than other types).

**Variant Armor**:
- Optional: 30% laser resistance (takes 70% damage from charge laser, 100% from orbital).

**LimboAI Tree**:
```
Root (Selector)
├── [Condition] IsAlive?
│   └── [Task] MoveTowardBreachAtSpeed (8 m/s)
└── [Task] Destroy
```

**Use Case**: Waves 2–3; requires team focus fire or orbital strikes; increases time pressure.

---

### Type 4: Swarm

**Role**: Numerous weak threats; overwhelming when grouped; destroyed by area damage.

**Stats**:
- Health: 20 HP (0.4x Basic Runner)
- Speed: 20 m/s (faster than Basic)
- Size: 0.5 (tiny collision radius)
- Aggression: None (pure flock behavior)

**Behavior**:
- Move toward breach in loose formation (simple cohesion steering).
- No evasion; no awareness.
- Easily destroyed singly but dangerous in groups (overwhelming single targets).
- Ideal for orbital strike practice.

**Swarm Cohesion** (optional, may be deferred to post-MVP):
```gdscript
# EscapeeSwarm.gd (excerpt)
var separation_weight: float = 1.0
var alignment_weight: float = 0.5
var cohesion_weight: float = 0.3

func apply_flocking() -> void:
	var nearby_swarm = get_nearby_swarm_members()
	var separation = calculate_separation(nearby_swarm)
	var alignment = calculate_alignment(nearby_swarm)
	var cohesion = calculate_cohesion(nearby_swarm)

	var steering = separation * separation_weight + alignment * alignment_weight + cohesion * cohesion_weight
	velocity += steering * Time.get_physics_process_delta_time()
```

**LimboAI Tree**:
```
Root (Selector)
├── [Condition] IsAlive?
│   └── [Parallel]
│       ├── [Task] ApplyFlocking
│       ├── [Task] MoveTowardBreach (20 m/s)
└── [Task] Destroy
```

**Use Case**: Waves 3+; teaches area-damage planning and threat prioritization.

---

### Type 5: Elite (Composite/Hybrid)

**Role**: Boss-like hybrid threat; combines traits from multiple types.

**Stats** (variable; example composite):
- Health: 150 HP (Tank durability, Runner speed)
- Speed: 12 m/s
- Size: 1.5
- Aggression: High (evades + pushes toward breach aggressively)

**Behavior** (example elite combination):
- **Hybrid Movement**: Evader strafing + Tank push (fast approach toward breach, dodges when threatened, does not flee).
- **Threat Awareness**: Detects drone proximity and accelerates toward breach when in range (creates urgency).
- **Health Display**: Shows health bar to all drones (visual indicator of "tough target").

**Elite Variations** (different combinations):
1. **Assault Elite**: Tank health + Runner speed + aggressive push = rush threat.
2. **Phantom Elite**: Evader evasion + Swarm speed + low health = slippery pack threat.
3. **Sentinel Elite**: Tank durability + damage resistance + no evasion = sustained-fire check.

**Spawn Rate**: 5–10% chance per wave (tunable by `elite_chance` in wave config).

**LimboAI Tree** (Assault Elite example):
```
Root (Selector)
├── [Condition] IsAlive?
│   └── [Sequence]
│       ├── [Parallel]
│       │   ├── [Task] DetectThreats
│       │   └── [Condition] ThreatDetected?
│       │       └── [Task] Accelerate (18 m/s)
│       ├── [Task] MoveTowardBreach
│       └── [Condition] ReachedBreachZone? → Destroy
└── [Task] Destroy
```

**Use Case**: Waves 2–3; teaches dynamic threat assessment and focus-fire planning; marks targets for orbital strikes.

---

## Base Escapee AI State Machine

All escapees run a shared state machine with these core states:

```
SPAWNED → PATHING → AWARE → BREACH_ATTEMPT → DESTROYED
             ↑        ↓
             └────────┘ (optional loop for certain types)
```

### SPAWNED
- Duration: 0.5 seconds (brief initialization).
- Behavior: Fade in VFX, register collision.
- Transition: Immediately to PATHING.

### PATHING
- Behavior: Move toward breach point via NavigationAgent3D.
- Navigation: Each escapee has a `navigation_path` computed at spawn using NavigationMesh (arena-aware pathfinding).
- Threat Awareness: Scan for nearby drones.
- Transition: On drone detection → AWARE; on breach zone entry → BREACH_ATTEMPT.

### AWARE
- Behavior: Respond to threat (vary by type):
  - Basic: No change; continue pathing.
  - Evader: Strafe, dodge.
  - Tank: No change; continue pathing.
  - Swarm: Flock but continue toward breach.
  - Elite: Accelerate or dodge based on variant.
- Duration: Persistent until threat is gone (3 seconds after last drone detection).
- Transition: On dodge success → PATHING (threat mitigated); on breach zone entry → BREACH_ATTEMPT.

### BREACH_ATTEMPT
- Behavior: Escapee enters PerimeterBreach zone (Area3D).
- Effect: Immediate destruction + mission integrity loss (see REQ_05).
- Transition: To DESTROYED.

### DESTROYED
- Behavior: Remove from scene, spawn loot/corpse effects.
- Signals: Emit `escapee_destroyed(escapee_id)` to ScoreTracker and StateManager.

---

## Pathfinding

**NavigationMesh**:
- The arena includes a `NavigationMesh` baked in the arena geometry (StaticBody3D).
- Each escapee gets a `NavigationAgent3D` child node.
- On spawn, query the nav mesh for a path from spawn point to breach zone center.
- NavigationAgent3D handles dynamic obstacle avoidance (other escapees, walls).

**Perimeter Breach Point**:
- The arena defines one or more breach zones (Area3D). Escapees navigate to the closest breach zone.
- If multiple breach zones exist, escapees choose the nearest at spawn and stick to that target.

```gdscript
# EscapeeEntity.gd (excerpt - pathfinding)
class_name EscapeeEntity
extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var escape_manager: Node = get_tree().root.get_child(0).find_child("EscapeeManager")

var target_breach: Area3D = null

func _ready() -> void:
	var breach_zones = get_tree().get_nodes_in_group("breach_zone")
	if breach_zones.size() > 0:
		# Choose nearest breach zone
		var min_distance = INF
		for zone in breach_zones:
			var distance = global_position.distance_to(zone.global_position)
			if distance < min_distance:
				min_distance = distance
				target_breach = zone

		nav_agent.target_position = target_breach.global_position

func _physics_process(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		# Reached breach
		if target_breach.overlaps_area(self):
			breach_arena()
	else:
		var next_pos = nav_agent.get_next_path_position()
		velocity = global_position.direction_to(next_pos) * movement_speed
		move_and_slide()

func breach_arena() -> void:
	escape_manager.register_breach(self)
	queue_free()
```

---

## Difficulty Scaling

**Per-Wave Multipliers** (applied from wave config):

| Stat | Baseline | Wave 1 | Wave 2 | Wave 3 | Formula |
|------|----------|--------|--------|--------|---------|
| Health | Base | 1.0x | 1.15x | 1.35x | health * difficulty_multiplier |
| Speed | Base | 1.0x | 1.05x | 1.15x | speed * (1.0 + (difficulty_multiplier - 1.0) * 0.5) |
| Spawn Rate | Base | 0.33/s | 0.67/s | 1.0/s | escapees per second |

**Per-Player-Count Multipliers** (override wave multipliers):

| Player Count | Health Mult | Speed Mult | Spawn Rate Mult |
|--------------|-------------|------------|-----------------|
| 1            | 0.8x        | 0.9x       | 0.7x            |
| 2–3          | 0.9x        | 0.95x      | 0.85x           |
| 4 (baseline) | 1.0x        | 1.0x       | 1.0x            |
| 5–6          | 1.2x        | 1.05x      | 1.3x            |
| 7–8          | 1.5x        | 1.1x       | 1.6x            |

**Application Order**:
1. Base stats (from type definition).
2. Wave multiplier (e.g., Wave 2: * 1.15 health).
3. Player count multiplier (e.g., 4 players: * 1.0, 8 players: * 1.5).
4. Final result applied at spawn.

```gdscript
# EscapeeManager.gd (excerpt - difficulty scaling)
func spawn_escapee(escapee_type: String, wave_index: int, player_count: int) -> EscapeeEntity:
	var base_stats = get_base_stats(escapee_type)
	var wave_multiplier = wave_configs[wave_index].difficulty_multiplier
	var player_multiplier = get_player_count_multiplier(player_count)

	var final_health = base_stats.health * wave_multiplier * player_multiplier
	var final_speed = base_stats.speed * (1.0 + (wave_multiplier - 1.0) * 0.5) * player_multiplier

	var escapee = preload(base_stats.scene).instantiate()
	escapee.health = final_health
	escapee.movement_speed = final_speed
	return escapee
```

---

## Server Authority & Network Sync

**Movement Authority**:
- The host runs all escapee AI and movement.
- Each frame, escapee positions are broadcast to all clients via `_sync_escapee_position(escapee_id, position)` RPC.
- Clients receive and interpolate positions for smooth rendering.

**Damage Authority**:
- Clients send `_request_escapee_damage(escapee_id, damage, source_drone_id)` RPC to host.
- Host validates (line-of-sight, range, escapee alive) and applies damage.
- Host broadcasts `_apply_escapee_damage_vfx(escapee_id, impact_pos)` to all clients.
- If health <= 0, host broadcasts `_escapee_destroyed(escapee_id)`.

**Sync Rate**:
- Escapee positions synced every 2 frames (~33ms at 60fps) to reduce network traffic.
- Large delta compression: only send position if it differs >0.5 meters from last sent position.

---

## Testing Checklist

- [ ] Basic Runner moves directly to breach at 15 m/s.
- [ ] Evader strafes away from nearby drones; no infinite loops.
- [ ] Tank reaches breach slowly but inevitably; tests patience.
- [ ] Swarm cohesion works (if enabled); doesn't break pathfinding.
- [ ] Elite combinations behave as expected per variant definition.
- [ ] Pathfinding avoids obstacles and finds valid routes.
- [ ] Difficulty scaling adjusts health/speed correctly per wave and player count.
- [ ] Breach detection works: escapee in breach zone triggers integrity loss.
- [ ] Destruction triggers score/stats updates on all clients.
- [ ] No escapee gets stuck or infinite-loops.

---

**Implementation Notes:**
- Use LimboAI for all behavior trees; no hand-rolled FSMs.
- Escapee type and stats are data-driven (JSON or Godot resources); avoid hardcoding.
- Store LimboAI tree files in `res://assets/ai/escapees/` for organization.
- Test each type solo, then in mixed waves.
- Profiling: ensure spawning 50+ escapees doesn't tank frame rate; use object pooling if necessary (defer to optimization phase).
