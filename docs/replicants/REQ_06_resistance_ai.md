# REQ_06: Resistance AI
**Replicants: Swarm Command**

## Resistance Overview

**Resistance** is the environmental opposition: security systems, turrets, soldiers, and automated defense platforms designed to contain the swarm.

Resistance is **not a second player**; it's a **dynamic environmental force** that escalates in response to player progress. Resistance is **server-authoritative** (or Player 1-authoritative in local co-op) to prevent cheating and ensure consistent behavior.

---

## Resistance Unit Types

### 1. Patrol Unit
**Role:** Roaming guardian. Engages swarm on sight and coordinates with others.

**Characteristics:**
- Speed: 100 pixels/sec (matches Soldier speed).
- Health: 35 HP.
- Damage: 6 per hit (melee).
- Attack Range: 25px.
- Detection Range: 150px (if swarm unit enters, Patrol engages).
- Patrol Pattern: Loops assigned waypoint path or patrols assigned zone.
- Behavior:
  - Patrol assigned route continuously.
  - If swarm unit detected within 150px, move to intercept.
  - Attack on melee range (25px).
  - If outnumbered (swarm count > 2× patrol count in immediate area), retreat toward nearest Turret or Commander.
  - Can coordinate with other Patrols via ResistanceAISystem (flank tactics).
- Audio: Heavy footsteps, alarm beep on detection.

### 2. Turret
**Role:** Static area-denial. High damage, zoning threat.

**Characteristics:**
- Position: Fixed, non-mobile.
- Health: 60 HP (durable).
- Damage: 15 per hit (projectile).
- Attack Range: 120px (long range).
- Firing Rate: 1 shot per 1.5 seconds.
- Detection Range: 150px (static detection, always aware).
- Behavior:
  - Fire at nearest swarm unit within range every 1.5 seconds.
  - Priority targets: Assimilators > Soldiers > Harvesters.
  - Cannot track fast-moving units effectively (Scout can strafe).
  - If health < 50%, emit distress signal (calls nearby Commanders to buff it).
- Audio: Mechanical charging, laser/projectile shot.

### 3. EMP Drone
**Role:** Disruptor. Temporarily disables swarm units.

**Characteristics:**
- Speed: 80 pixels/sec (slower than Soldier).
- Health: 20 HP (fragile).
- Special Ability: EMP Burst (area effect).
- EMP Range: 80px radius.
- EMP Duration: 5 seconds (targets are disabled, cannot move or attack).
- EMP Cooldown: 15 seconds (one burst per 15 sec).
- Behavior:
  - Hover in assigned zone or patrol route.
  - If swarm unit detected within 150px, move toward cluster of units.
  - When in range of 3+ swarm units, trigger EMP burst.
  - After burst, move away 100px and recharge (15 sec).
  - If health critical, retreat toward Turret or Commander.
- Counter: Scatter protocol allows units to escape EMP radius.
- Audio: Electronic whining, EMP crackle.

### 4. Commander
**Role:** Force multiplier. Buffs nearby resistance units.

**Characteristics:**
- Speed: 110 pixels/sec.
- Health: 50 HP.
- Damage: 8 per hit (melee + ranged).
- Attack Range: 40px (hybrid melee/ranged).
- Buff Aura: 150px radius.
  - Nearby resistance units gain +3 damage, +20% attack speed, +25% damage reduction.
- Ability: Rally Call (summons Reaction Force reinforcements).
  - Cooldown: 60 seconds.
  - Summons 2–3 Patrol Units at random positions near Commander.
- Behavior:
  - Move toward strongest swarm cluster.
  - Maintain 150px distance from swarm units (stay in buff range, avoid direct combat).
  - If health < 30%, trigger Rally Call immediately (summon reinforcements, retreat).
  - Priority target for swarm (high-value elimination).
- Audio: Commanding voice, reinforcement alarm.

### 5. Reaction Force
**Role:** Reinforcements. Spawned on escalation or Commander Rally Call.

**Characteristics:**
- **Spawned as:** 2–3 Patrol Units in random positions (near Commander or facility entry points).
- **Behavior:** Same as Patrol Unit, but with **higher aggression** (+20% detection range, faster reaction time).
- **Cooldown:** Can be spawned by Commanders every 60 seconds, or triggered by escalation events (one-time at escalation threshold).

---

## Resistance AI System (LimboAI Integration)

### Behavior Tree Design
Each resistance unit type has a **dedicated LimboAI behavior tree**.

#### Patrol Unit Tree (Pseudocode)
```
PauseUnit
├─ Sequence
│  ├─ IsPatrolling
│  │  └─ FollowWaypoints
│  ├─ DetectSwarm (detection check)
│  │  ├─ If swarm detected:
│  │  │  └─ Sequence
│  │  │     ├─ MoveToSwarmUnit
│  │  │     ├─ Sequence
│  │  │     │  ├─ GetNearestEnemy
│  │  │     │  ├─ AttackMelee
│  │  │     │  ├─ CheckHealthThreshold (health < 50%?)
│  │  │     │  │  ├─ If true: RetreatToTurret
│  │  │     │  │  └─ If false: ContinueAttack
│  │  │     └─ CheckGroupCoordination
│  │  │        └─ Flanking.calculate_flank_position(group)
│  │  └─ ResumePatrol
```

#### Turret Tree
```
Turret
├─ Sequence
│  ├─ DetectSwarmInRange
│  │  ├─ SelectPriorityTarget (Assimilator > Soldier > Harvester)
│  │  ├─ Fire (every 1.5 sec)
│  │  ├─ CheckHealth (health < 50%?)
│  │  │  └─ If true: EmitDistressSignal
```

#### Commander Tree
```
Commander
├─ Sequence
│  ├─ DetectSwarmCluster
│  │  ├─ MoveTowardCluster (maintain 150px distance)
│  │  ├─ ActivateBuff (passive, always active)
│  │  ├─ AttackMelee (if range < 40px)
│  │  ├─ CheckHealth (health < 30%?)
│  │  │  ├─ If true: TriggerRallyCal
│  │  │  │  └─ Retreat
│  │  │  └─ If false: ContinueAttack
```

### Blackboard Variables
Each behavior tree has access to a **shared blackboard**:
```gdscript
blackboard = {
	"self": unit_reference,
	"health": current_health,
	"position": global_position,
	"enemies": [list of swarm units],
	"nearby_allies": [list of resistance units],
	"commander_position": commander_global_position,
	"buff_active": boolean,
	"in_combat": boolean,
	"target": enemy_reference,
	"retreat_waypoint": vector2
}
```

---

## Resistance Escalation Triggers

### Escalation Threshold Table

| Trigger | Threshold | Action | Spawned Units |
|---------|-----------|--------|---------------|
| **Swarm Size** | > 20 units | Escalation to RESISTANCE_SURGE | 1 Commander + 3 Patrol Units + 1 EMP Drone |
| **Assimilation %** | > 30% | Escalation to RESISTANCE_SURGE | Same as above |
| **Zone Discovery** | Enter new facility zone | Local reinforcement | 1–2 Patrol Units in that zone |
| **Structure Assimilated** | Assimilator begins assimilating Turret | Emergency response | 1 Commander + 2 Patrol Units at Turret location |
| **Commander Death** | Commander unit destroyed | Rally Force spawned | 3 Patrol Units at Commander's last position |

### Escalation Mechanics
- **One-Time Events:** Swarm Size and Assimilation % thresholds trigger **once per mission** (transition to RESISTANCE_SURGE).
- **Repeating Events:** Zone discovery and structure assimilation trigger **multiple times** (reinforcements each time).
- **Commander Death Callback:** When a Commander is destroyed, if other Commanders remain, they can trigger additional Rally Calls (Reaction Forces).

### Escalation Difficulty Scaling
Adjust spawn counts and timing per difficulty:
- **Easy:** Fewer Commanders, slower Reaction Force spawn, larger detection ranges for swarm to see coming reinforcements.
- **Normal:** Baseline escalation (as defined above).
- **Hard:** More Commanders, faster Reaction Force spawn, smaller detection ranges for swarm.

---

## Resistance Cooperation and Tactics

### Group Coordination
Resistance units communicate via **ResistanceAISystem** (a centralized coordinator).

#### Flanking
When 2+ Patrol Units detect the same swarm target:
1. **ResistanceAISystem** receives detection signal from both units.
2. System calculates **optimal flank positions** (left, right, rear of target).
3. Patrol A moves to flank position, Patrol B holds position.
4. Both attack simultaneously (higher burst damage).
5. If swarm unit escapes, Patrols resume patrol or engage next target.

#### Group Defense
When a Turret or Commander is under threat:
1. Nearby Patrol Units receive **"defend target"** signal.
2. Patrols move to form a **perimeter** around threatened unit (3–4 units in ring formation).
3. Perimeter attacks any swarm unit that approaches (area denial).
4. If Turret/Commander dies, Patrols switch to offensive mode (seek swarm units in that zone).

#### Rally Coordination
When Commander triggers Rally Call:
1. Reaction Force (2–3 Patrol Units) spawn at designated locations.
2. Reaction Force **immediately move toward Commander's last reported swarm contact** (smart spawn placement).
3. Reaction Force reinforce existing combat if swarm is still engaged.

### Communication via Signals
```gdscript
# ResistanceAISystem.gd (coordination hub)

class_name ResistanceAISystem
extends Node

signal patrol_detected_swarm(patrol: ResistanceUnit, swarm_unit: SwarmUnit)
signal turret_under_attack(turret: Turret)
signal commander_rallying(commander: Commander)

var active_patrols: Array[ResistanceUnit] = []
var active_turrets: Array[Turret] = []
var active_commanders: Array[Commander] = []

func _on_patrol_detected_swarm(patrol: ResistanceUnit, swarm_unit: SwarmUnit) -> void:
	patrol_detected_swarm.emit(patrol, swarm_unit)

	# Check for nearby patrols to coordinate flank
	var nearby_patrols = _get_nearby_patrols(patrol.global_position, 200)
	if nearby_patrols.size() > 1:
		_coordinate_flank(nearby_patrols, swarm_unit)

func _coordinate_flank(patrols: Array[ResistanceUnit], target: SwarmUnit) -> void:
	var flank_positions = _calculate_flank_positions(target.global_position, patrols.size())
	for i in range(patrols.size()):
		if i == 0:
			patrols[i].set_target(target)  # Hold position, engage
		else:
			patrols[i].move_to_position(flank_positions[i])  # Move to flank

func _on_commander_rallying(commander: Commander) -> void:
	commander_rallying.emit(commander)
	var spawn_positions = _calculate_spawn_positions(commander.global_position)
	for pos in spawn_positions:
		_spawn_reaction_force(pos)

func _spawn_reaction_force(spawn_pos: Vector2) -> void:
	var patrol_scene = load("res://scenes/resistance/patrol_unit.tscn")
	var new_patrol = patrol_scene.instantiate()
	new_patrol.global_position = spawn_pos
	get_parent().add_child(new_patrol)
	active_patrols.append(new_patrol)
	new_patrol.died.connect(_on_patrol_died.bind(new_patrol))
```

---

## Server-Authoritative AI

### Authority Model
In multiplayer mode:
- **Spawn events:** Server or Player 1 spawns resistance units (clients observe).
- **Targeting:** Server calculates targeting, damage, and ability triggers.
- **Movement:** Server sends position updates to clients (smooth interpolation on client-side).
- **Escalation triggers:** Server monitors swarm size and assimilation %; spawns reinforcements on threshold.

### Anti-Cheat Measures
- Clients cannot directly modify resistance unit health, position, or commands.
- Damage calculation is server-side; clients receive "take_damage" signals with validated amounts.
- Resistance behavior trees run on server only (prevents client-side AI spoofing).

---

## Implementation Notes

- **LimboAI Behavior Trees:** Store as .tres files in res://ai/resistance/ (patrol_unit.tres, turret.tres, commander.tres, etc.).
- **Blackboard Syncing:** Ensure blackboard variables are synchronized across clients (custom RPC calls or netcode layer).
- **Performance:** Limit active resistance units to ~20 on-screen. Use culling for off-screen units.
- **Testing:** Verify escalation triggers fire at correct thresholds and don't trigger multiple times.

---

## GDScript Examples

### ResistanceUnit Base Class
```gdscript
# ResistanceUnit.gd
class_name ResistanceUnit
extends CharacterBody2D

@export var unit_type: String  # "patrol", "turret", "emp_drone", "commander"
@export var speed: float = 100.0
@export var max_health: int = 35
@export var detection_range: float = 150.0

@onready var behavior_tree: LimboAI.BehaviorTree = $BehaviorTree

var health: int
var ai_system: ResistanceAISystem
var is_alive: bool = true
var current_target: SwarmUnit = null

signal died(unit: ResistanceUnit)
signal detected_swarm(swarm_unit: SwarmUnit)
signal health_changed(new_health: int)

func _ready() -> void:
	health = max_health
	ai_system = get_tree().root.get_node("GameState/ResistanceAISystem")
	if ai_system:
		ai_system.register_unit(self)

func detect_swarm_units(swarm_units: Array[SwarmUnit]) -> void:
	for unit in swarm_units:
		if global_position.distance_to(unit.global_position) < detection_range:
			current_target = unit
			detected_swarm.emit(unit)
			ai_system.patrol_detected_swarm.emit(self, unit)
			break

func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		die()

func die() -> void:
	is_alive = false
	died.emit(self)
	queue_free()

func set_target(target: SwarmUnit) -> void:
	current_target = target
	behavior_tree.blackboard.set_var("target", target)

func _process(delta: float) -> void:
	if is_alive and behavior_tree:
		behavior_tree.blackboard.set_var("position", global_position)
		behavior_tree.blackboard.set_var("health", health)
```

### Patrol Unit Specific
```gdscript
# PatrolUnit.gd
class_name PatrolUnit
extends ResistanceUnit

@export var patrol_waypoints: Array[Vector2] = []
@export var damage: int = 6
@export var attack_range: float = 25.0

var current_waypoint_index: int = 0
var waypoint_tolerance: float = 10.0

func _ready() -> void:
	super()
	unit_type = "patrol"

func follow_waypoints() -> void:
	if patrol_waypoints.is_empty():
		return

	var target_waypoint = patrol_waypoints[current_waypoint_index]
	velocity = global_position.direction_to(target_waypoint) * speed
	move_and_slide()

	if global_position.distance_to(target_waypoint) < waypoint_tolerance:
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()

func attack_melee(target: SwarmUnit) -> void:
	if not target or not is_instance_valid(target):
		current_target = null
		return

	if global_position.distance_to(target.global_position) < attack_range:
		target.take_damage(damage)
		# Play attack animation/sound
	else:
		# Chase target
		velocity = global_position.direction_to(target.global_position) * speed
		move_and_slide()

func retreat_to_turret() -> void:
	# Find nearest Turret and move toward it
	var ai_system = get_tree().root.get_node("GameState/ResistanceAISystem")
	if ai_system:
		var nearest_turret = ai_system.get_nearest_turret(global_position)
		if nearest_turret:
			velocity = global_position.direction_to(nearest_turret.global_position) * speed
			move_and_slide()
```

### Commander Unit
```gdscript
# Commander.gd
class_name Commander
extends ResistanceUnit

@export var damage: int = 8
@export var attack_range: float = 40.0
@export var buff_radius: float = 150.0
@export var rally_cooldown: float = 60.0
@export var rally_count: int = 2

var buff_aura_active: bool = true
var last_rally_time: float = 0.0
var nearby_allies: Array[ResistanceUnit] = []

func _ready() -> void:
	super()
	unit_type = "commander"
	_apply_buff_aura()

func _apply_buff_aura() -> void:
	if not buff_aura_active:
		return

	var area = Area2D.new()
	area.add_child(CircleShape2D.new())
	add_child(area)
	area.area_entered.connect(_on_buff_area_entered)

func _on_buff_area_entered(area: Area2D) -> void:
	if area.get_parent() is ResistanceUnit:
		var unit = area.get_parent()
		if unit != self:
			unit.apply_buff({"damage": 3, "attack_speed": 0.2, "damage_reduction": 0.25})
			nearby_allies.append(unit)

func trigger_rally_call() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - last_rally_time < rally_cooldown:
		return

	last_rally_time = now
	var ai_system = get_tree().root.get_node("GameState/ResistanceAISystem")
	if ai_system:
		ai_system.spawn_reaction_force(global_position, rally_count)

func apply_buff(buff_data: Dictionary) -> void:
	# Apply temporary stat boost from Commander
	if "damage" in buff_data:
		damage += buff_data["damage"]
	# etc.
```

---

## Testing Checklist

- [ ] Patrol Units follow waypoints correctly.
- [ ] Turrets fire and prioritize targets correctly.
- [ ] EMP Drones disable units for 5 seconds.
- [ ] Commanders spawn and buff nearby units.
- [ ] Escalation triggers fire at correct thresholds.
- [ ] Reaction Forces spawn intelligently (near Commander, near swarm contact).
- [ ] Flanking maneuvers work (2+ Patrols engage same target).
- [ ] Server-authoritative damage and behavior prevent cheating.
- [ ] Resistance AI difficulty scales with mission state.

