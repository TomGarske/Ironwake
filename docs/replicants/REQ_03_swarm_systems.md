# REQ_03: Swarm Systems
**Replicants: Swarm Command**

## Swarm Unit Overview

The swarm is composed of five unit types, each with a distinct role. Units operate autonomously under their role constraints but can be temporarily overridden by Protocol commands.

---

## Unit Type Reference

| Unit Type | Role | Speed | Health | Primary Action | Unlock Phase |
|-----------|------|-------|--------|-----------------|---------------|
| **Harvester** | Gather metal | Slow | Low | Approach & extract from metal deposits | AWAKENING |
| **Scout** | Reconnaissance | Fast | Very Low | Reveal fog of war, identify resistance | EARLY_COLONY |
| **Soldier** | Combat | Medium | Medium | Engage & destroy resistance units | AWAKENING |
| **Builder** | Infrastructure | Slow | Medium | Place new ReplicationHubs, extend network | EXPANSION |
| **Assimilator** | Conversion | Medium | High | Transform resistance structures into swarm assets | EXPANSION (partial) → RESISTANCE_SURGE (full) |

---

## Unit Specifications

### Harvester
**Purpose:** Primary resource gatherer. The swarm's economic engine.

**Characteristics:**
- Speed: 80 pixels/sec (slow, deliberate).
- Health: 20 HP (fragile).
- Size: 16 pixels (small, fitting).
- Autonomous Behavior:
  - Seek nearest metal deposit within 200px.
  - Approach and enter deposit's Area2D.
  - Extract metal at 1 metal/sec (configurable per deposit type).
  - If deposit depletes, seek next nearest deposit.
  - If no deposits nearby, become idle.
- Protocol Override: Swarm Rush (move to location, ignore harvesting).
- Visual Signature: Segmented body with bright geometric patterns, metallic chittering sound.
- Death: Dissolves into sparks. Loss is immediately penalized (lost extraction capacity).

### Scout
**Purpose:** Eyes of the swarm. Reveals territory and enemy positions.

**Characteristics:**
- Speed: 150 pixels/sec (fastest unit).
- Health: 5 HP (extremely fragile).
- Size: 12 pixels (smallest unit).
- Autonomous Behavior:
  - Wander in a designated patrol pattern (given on spawn).
  - Approach any fog of war area to reveal it (reveal radius: 100px).
  - If Resistance unit spotted, ping to CommandNode (visual alert).
  - If hit, retreat toward nearest friendly unit or ReplicationHub.
  - Do not engage in combat unless cornered.
- Protocol Override: Swarm Rush (move to location), Scatter (disperse).
- Visual Signature: Sleek, elongated, with acute sensor appendages. Quiet, fast scuttling.
- Death: Minimal impact on swarm. Only loss is reduced scouting coverage.

### Soldier
**Purpose:** Combat unit. Enforcer of the swarm.

**Characteristics:**
- Speed: 110 pixels/sec.
- Health: 40 HP.
- Size: 24 pixels.
- Damage: 8 per hit (melee).
- Attack Range: 30px.
- Attack Speed: 1 attack/sec.
- Autonomous Behavior:
  - Patrol assigned zone or idle near Replication Hub.
  - If Resistance unit detected within 150px, engage (move to target & attack).
  - Prioritize Commanders > Turrets > Patrol Units.
  - If outnumbered (enemy count > 1.5× soldier count), retreat toward friendly Replication Hub.
  - Cannot be damaged while retreating (brief invulnerability, 3 sec).
- Protocol Override: Swarm Rush (all nearby soldiers attack target location), Defensive Formation (hold position, prioritize defense).
- Visual Signature: Armored, angular, with prominent attack appendages. Harsh metallic screeching on attack.
- Death: Loss of combat capacity. Significant impact on swarm's ability to resist opposition.

### Builder
**Purpose:** Expands swarm infrastructure. Extends the network.

**Characteristics:**
- Speed: 90 pixels/sec.
- Health: 35 HP.
- Size: 22 pixels.
- Autonomous Behavior:
  - Idle near friendly ReplicationHub or await command.
  - Player command: "Place ReplicationHub" at designated location.
  - Approach location, construct (3-second channel, visible construction animation).
  - If damaged during construction, retreat and begin construction elsewhere.
  - After placement, resume idle or move to next placement zone.
  - Cannot place ReplicationHub if insufficient metal (reserves required: 50 metal per hub).
- Protocol Override: Swarm Rush (move to location, halt construction), Scatter.
- Visual Signature: Robust, angular, with construction limbs/tools. Metallic hum during construction.
- Death: Reduces swarm's capacity to expand. Non-critical but limits strategic options.

### Assimilator (Late Game)
**Purpose:** Converts enemy structures and tech into swarm assets.

**Characteristics:**
- Speed: 100 pixels/sec.
- Health: 50 HP (most durable unit).
- Size: 28 pixels (largest unit).
- Assimilation Range: 40px.
- Assimilation Rate: 5 metal/sec (converts structure → metal for swarm use).
- Autonomous Behavior:
  - Idle or follow Swarm Rush commands.
  - When in proximity to Resistance structure (Turret, base, etc.), begin assimilation.
  - Assimilation is visual + mechanical (structure dims, swarm patterns overlay it, then it dissolves).
  - Converted metal is added to shared pool.
  - If attacked during assimilation, prioritize escape (move away 100px, then re-approach).
- Protocol Override: Assimilation Wave (all Assimilators in swarm push forward, sacrificing 1 unit per target assimilated).
- Visual Signature: Organic, flowing, with energy conduits. Glowing patterns when assimilating. Humming, absorptive sound.
- Death: Loss of conversion capacity, but not critical to swarm victory.

---

## Replication Protocol (Production System)

### Concept
The **ReplicationHub** is the swarm's factory. It consumes metal from the shared economy and produces new units.

### Production Queue
- Each ReplicationHub maintains a **queue of up to 5 units**.
- Queue is FIFO (first in, first out).
- Production is simultaneous across all hubs (if you have 3 hubs, you can produce 3 units in parallel).

### Costs (Metal per Unit)
| Unit | Base Cost | EARLY_COLONY | EXPANSION | RESISTANCE_SURGE |
|------|-----------|--------------|-----------|------------------|
| Harvester | 8 metal | 8 | 12 | 18 |
| Scout | 5 metal | 5 | 8 | 12 |
| Soldier | 12 metal | 12 | 18 | 25 |
| Builder | 15 metal | 15 | 22 | 30 |
| Assimilator | 20 metal | — | 20 | 15 (reduced) |

### Production Time
- Base: 6 seconds per unit (all types).
- Rapid Replication protocol: ×2 speed (3 seconds).
- Multiple ReplicationHubs: Production parallelizes.

### Unit Spawning
- Units spawn at the **ReplicationHub's location**.
- Spawn animation: 0.5 seconds (visual pulse + particle effects).
- Units emerge from hub and immediately resume autonomous behavior (wander, seek resources, patrol, etc.).

### Economy Interaction
```gdscript
# ReplicationHub.gd (pseudocode)

class_name ReplicationHub
extends StaticBody2D

var metal_economy: MetalEconomy
var production_queue: Array[String] = []
var is_producing: bool = false
var production_time_remaining: float = 0.0

func queue_unit(unit_type: String) -> bool:
	var cost = get_unit_cost(unit_type)
	if metal_economy.available_metal >= cost:
		production_queue.append(unit_type)
		metal_economy.spend_metal(cost)  # Deduct upfront
		if not is_producing:
			_start_production()
		return true
	return false

func _start_production() -> void:
	if production_queue.is_empty():
		is_producing = false
		return

	is_producing = true
	var next_unit = production_queue.pop_front()
	production_time_remaining = get_production_time(next_unit)

	# Emit signal for UI feedback
	production_started.emit(next_unit, production_time_remaining)

func _process(delta: float) -> void:
	if is_producing:
		production_time_remaining -= delta
		if production_time_remaining <= 0.0:
			_spawn_unit(production_queue[0] if not production_queue.is_empty() else "")
			_start_production()

func _spawn_unit(unit_type: String) -> void:
	var unit_scene = load(get_unit_scene_path(unit_type))
	var new_unit = unit_scene.instantiate()
	new_unit.global_position = global_position
	get_parent().add_child(new_unit)
	unit_spawned.emit(unit_type, new_unit)
```

---

## Protocol Commands (Strategic Abilities)

Players issue Protocol commands to override unit autonomy temporarily. Each protocol has distinct tactical applications.

### 1. Swarm Rush
**Icon:** Directional arrow with speed lines.
**Hotkey:** D-Pad Right or number key 1.
**Cost:** Free (no metal).
**Cooldown:** 20 seconds.
**Effect:**
- All Soldiers within 80px of the **command origin point** are targeted.
- Soldiers move toward the **designated target location** at 2× speed.
- Upon arrival (or within 5 sec), soldiers attack all resistance units at location.
- Attack priority: highest-threat enemy first (Commanders > Turrets > Patrol Units).
- Command duration: 10 seconds (soldiers remain engaged for full duration).
- After duration, soldiers resume autonomous behavior.

**Usage:** Concentrate force on a critical target (Turret, Commander, high-value position).

### 2. Rapid Replication
**Icon:** Spinning replication hub with acceleration lines.
**Hotkey:** D-Pad Up or number key 2.
**Cost:** 20 metal.
**Cooldown:** 45 seconds.
**Effect:**
- All ReplicationHubs gain 2× production speed for 15 seconds.
- Production time for all queued units: halved.
- Only affects units queued during the protocol's active window.
- After 15 seconds, production reverts to normal speed.

**Usage:** Rapidly scale swarm size in response to escalation or resource abundance.

### 3. Scatter
**Icon:** Units spreading in multiple directions.
**Hotkey:** D-Pad Down or number key 3.
**Cost:** Free.
**Cooldown:** 8 seconds (fast recharge).
**Effect:**
- All units within 120px of a **designated center point** disperse.
- Each unit moves 60–80px in a random direction within a 360° arc.
- Units occupy scattered positions for 8 seconds (hold position).
- After 8 seconds, units resume autonomous behavior.
- Cannot be used while units are already scattered (cooldown active).

**Usage:** Emergency defensive protocol. Avoid area attacks (EMP bursts, Turret sweeps).

### 4. Defensive Formation
**Icon:** Shield with grouped units.
**Hotkey:** D-Pad Left or number key 4.
**Cost:** Free.
**Cooldown:** 25 seconds.
**Effect:**
- All units within 100px move to designated **holding position**.
- Units form a loose cluster (16–24px spacing).
- While holding, units prioritize defense (take 30% reduced damage from ranged attacks).
- Can hold indefinitely or until attacked (break formation on incoming attack).
- Manual cancel: issue a new command.

**Usage:** Defend a strategic chokepoint, protect Replication Hubs, or regroup before an assault.

### 5. Assimilation Wave (RESISTANCE_SURGE only)
**Icon:** Assimilator with forward momentum and energy aura.
**Hotkey:** D-Pad Right (alternate context) or number key 5.
**Cost:** 1 Assimilator per target (unit is sacrificed).
**Cooldown:** 30 seconds.
**Effect:**
- All Assimilators within 100px of command origin are targeted.
- Assimilators move forward in a line toward the **designated front position**.
- Each Assimilator engages the first Resistance structure (Turret, base, etc.) in its path.
- Assimilation is accelerated (10 metal/sec instead of 5). Duration: ~2–3 seconds per target.
- Upon completion of assimilation, the Assimilator **sacrifices itself** (dissolves, becomes part of the swarm network).
- If no targets in path, Assimilators move to designated position and hold (available for next command).

**Usage:** Breach heavily fortified positions. Push deep into enemy territory while converting defenses.

---

## Unit Autonomy and Command Override

### Autonomy Model
Each unit type has a **default behavior tree** (LimboAI):
- **Harvester Tree:** Seek deposit → Approach → Extract → Repeat.
- **Scout Tree:** Patrol → Detect fog of war → Alert → Retreat if threatened.
- **Soldier Tree:** Patrol → Detect enemy → Engage → Retreat if outnumbered.
- **Builder Tree:** Idle → Await placement command → Construct → Resume.
- **Assimilator Tree:** Idle → Patrol (late game) → Detect structure → Assimilate → Resume.

### Protocol Override Mechanism
When a Protocol command is issued:
1. **Identify target units** (units within range of command origin).
2. **Inject override state** into unit's behavior tree.
3. **Unit suspends autonomy** and follows command instruction.
4. **Command duration expires** (or target is destroyed, destination reached).
5. **Override state removed**, unit resumes autonomous tree.

```gdscript
# SwarmUnit.gd (base class, pseudocode)

class_name SwarmUnit
extends CharacterBody2D

var behavior_tree: LimboAI.BehaviorTree
var current_override: Dictionary = {}
var autonomous_enabled: bool = true

func inject_protocol_override(protocol: String, target_location: Vector2, duration: float) -> void:
	autonomous_enabled = false
	current_override = {
		"protocol": protocol,
		"target": target_location,
		"duration": duration,
		"start_time": Time.get_ticks_msec()
	}

	# Suspend behavior tree
	behavior_tree.pause()

	# Update position based on protocol
	match protocol:
		"swarm_rush":
			velocity = global_position.direction_to(target_location) * rush_speed
		"scatter":
			velocity = Vector2.from_angle(randf() * TAU) * scatter_speed
		"defensive_formation":
			velocity = global_position.direction_to(target_location) * 0.5

func _process(delta: float) -> void:
	if not autonomous_enabled:
		_check_override_expiration(delta)
	else:
		behavior_tree.resume()

func _check_override_expiration(delta: float) -> void:
	var elapsed = Time.get_ticks_msec() - current_override["start_time"]
	if elapsed > current_override["duration"] * 1000:
		autonomous_enabled = true
		current_override.clear()
		velocity = Vector2.ZERO
```

---

## Implementation Notes

- **LimboAI Integration:** Each unit type has its own behavior tree file (res://ai/swarm/harvester.tres, etc.). Trees should be modular and reusable.
- **Autonomous Behavior:** Avoid hardcoding AI logic in `_process()`. Delegate to behavior trees.
- **Protocol Injection:** Design the override mechanism as a clean injection into the behavior tree, not overwriting it.
- **Cost Balancing:** Adjust costs and production times during playtesting. Early balance: Harvester heavy early, Soldier/Builder mid, Assimilator late.
- **Audio Signature:** Each unit type has distinct sounds (harvester: metallic clink; soldier: screeching; assimilator: humming absorption).
- **Testing:** Verify that protocols interrupt autonomy cleanly and resume correctly.

---

## GDScript Examples

### SwarmUnit Base Class
```gdscript
# SwarmUnit.gd
class_name SwarmUnit
extends CharacterBody2D

@export var unit_type: String  # "harvester", "scout", etc.
@export var speed: float = 100.0
@export var max_health: int = 40

@onready var behavior_tree: LimboAI.BehaviorTree = $BehaviorTree
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var health: int
var current_override: Dictionary = {}
var is_autonomous: bool = true

signal died(unit: SwarmUnit)
signal command_received(protocol: String, target: Vector2)

func _ready() -> void:
	health = max_health
	behavior_tree.blackboard.set_var("speed", speed)
	behavior_tree.blackboard.set_var("unit_type", unit_type)

func apply_protocol_override(protocol: String, target: Vector2, duration: float) -> void:
	if not is_autonomous:
		return  # Prevent stacking overrides

	is_autonomous = false
	current_override = {
		"protocol": protocol,
		"target": target,
		"duration": duration,
		"elapsed": 0.0
	}

	behavior_tree.pause()
	command_received.emit(protocol, target)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		die()

func die() -> void:
	died.emit(self)
	queue_free()

func _process(delta: float) -> void:
	if not is_autonomous:
		current_override["elapsed"] += delta
		if current_override["elapsed"] >= current_override["duration"]:
			is_autonomous = true
			behavior_tree.resume()
			current_override.clear()
```

### ReplicationHub Production
```gdscript
# ReplicationHub.gd
class_name ReplicationHub
extends StaticBody2D

@export var production_base_time: float = 6.0
@export var max_queue_size: int = 5

var metal_economy: MetalEconomy
var production_queue: Array[String] = []
var current_production: String = ""
var production_timer: float = 0.0

signal production_started(unit_type: String)
signal unit_spawned(unit_type: String, unit: SwarmUnit)

func queue_unit(unit_type: String) -> bool:
	if production_queue.size() >= max_queue_size:
		return false

	var cost = get_unit_cost(unit_type)
	if metal_economy.spend_metal(cost):
		production_queue.append(unit_type)
		if current_production.is_empty():
			_start_next_production()
		return true
	return false

func _start_next_production() -> void:
	if production_queue.is_empty():
		return

	current_production = production_queue.pop_front()
	production_timer = production_base_time
	production_started.emit(current_production)

func _process(delta: float) -> void:
	if not current_production.is_empty():
		production_timer -= delta
		if production_timer <= 0.0:
			_spawn_unit(current_production)
			_start_next_production()

func _spawn_unit(unit_type: String) -> void:
	var unit_scene = load("res://scenes/swarm/" + unit_type + ".tscn")
	var new_unit: SwarmUnit = unit_scene.instantiate()
	new_unit.global_position = global_position
	get_parent().add_child(new_unit)
	unit_spawned.emit(unit_type, new_unit)
```

---

## Balance Considerations

- **Harvester viability:** Ensure they're not so fragile that the economy collapses instantly.
- **Scout speed:** Fast enough to be useful for fog of war, but not overpowered in combat.
- **Soldier effectiveness:** Should be able to 1v1 most resistance patrols but lose to Turrets.
- **Builder placement cost:** High enough to be strategic, low enough that players can expand.
- **Assimilator late-game power:** Should feel strong in RESISTANCE_SURGE but not trivialize victory.
- **Protocol costs:** Swarm Rush and Scatter should be spammable, Rapid Replication expensive, Assimilation Wave devastating but risky.

