# REQ_06: Guard AI and Alarm System
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines guard NPC types, LimboAI behavior tree implementations, guard detection mechanics, and the facility-wide alarm escalation system. Guards are the primary dynamic threat; understanding their behavior is critical to stealth and tactical planning.

---

## 1. Guard Types

### 1.1 Patrol Guard (Standard)
**Role:** Mobile security presence; investigates noise and disturbances.

**Behavior:**
- Walks assigned patrol route, stopping briefly at waypoints (2–3 seconds).
- Listens for noise (sound radius detection).
- Investigates noise sources by walking to location and scanning.
- If entity spotted via line-of-sight, switches to ALERT state and calls for backup.
- If entity escapes without being fully engaged, guard returns to patrol.

**Detection Parameters:**
- **Noise sensitivity:** Hears noise at 50+ unit distance.
- **Line of sight:** 200-unit range, 90° detection cone.
- **Patrol speed:** 120 units/sec.
- **Investigation speed:** 150 units/sec (faster than patrol).

**LimboAI Behavior Tree:**
```
Patrol Guard Tree
├── Selector (always running)
│   ├── Sequence (Alert Check)
│   │   ├── Condition: is_entity_in_line_of_sight
│   │   ├── Action: alert_to_entity
│   │   └── Action: call_for_backup
│   ├── Sequence (Investigation Check)
│   │   ├── Condition: noise_detected_recent
│   │   ├── Action: move_to_noise_source
│   │   └── Action: search_area
│   └── Sequence (Patrol)
│       ├── Action: follow_patrol_route
│       └── Action: wait_at_waypoint
```

### 1.2 Stationary Sentry
**Role:** Fixed-point guard; highly aware, does not roam.

**Behavior:**
- Stands at assigned post (entry, objective room, exit).
- Rotates/scans continuously, checking for threats.
- Cannot be distracted from post; does not leave to investigate noise.
- If entity spotted, immediately escalates alarm to SECTOR_LOCKDOWN and attacks.
- High accuracy with ranged attack (if engaged).

**Detection Parameters:**
- **Noise sensitivity:** Does not investigate noise; only reacts to line-of-sight.
- **Line of sight:** 250-unit range (longer than patrol guard), 120° detection cone (wider).
- **Rotation speed:** 45° per second (continuous scan).
- **Alert delay:** Immediate (no delay before escalation).

**LimboAI Behavior Tree:**
```
Sentry Guard Tree
├── Selector (always running)
│   ├── Sequence (Alert Check - Priority)
│   │   ├── Condition: is_entity_in_line_of_sight
│   │   ├── Action: escalate_to_lockdown
│   │   ├── Action: attack_entity
│   │   └── Action: hold_position
│   └── Sequence (Patrol - Rotation)
│       ├── Action: rotate_in_place
│       └── Action: repeat
```

### 1.3 Response Team
**Role:** Deployed on alarm escalation; aggressive, coordinated sweep.

**Behavior:**
- Spawned when alarm escalates to SECTOR_LOCKDOWN or FACILITY_ALERT.
- Moves quickly to sector entry/objective.
- Sweeps sectors methodically, checking all rooms.
- Multiple guards coordinate; split into pairs to cover more ground.
- Aggressive engagement: fire on sight, call for additional backup.

**Detection Parameters:**
- **Noise sensitivity:** Very sensitive; investigates all noise.
- **Line of sight:** 200-unit range, 100° cone.
- **Movement speed:** 180 units/sec (faster than patrol guards).
- **Spawn location:** Random entry point to sector (near sector entry or key locations).
- **Spawn count:** 2–3 teams on SECTOR_LOCKDOWN, 4+ on FACILITY_ALERT.

**LimboAI Behavior Tree:**
```
Response Team Tree
├── Parallel (sweep coordination)
│   ├── Selector (threat response)
│   │   ├── Sequence (Alert)
│   │   │   ├── Condition: is_entity_visible
│   │   │   └── Action: attack_aggressively
│   │   └── Sequence (Sweep)
│   │       ├── Action: move_to_next_room
│   │       └── Action: clear_room
│   └── Action: maintain_formation (with nearby guards)
```

### 1.4 Specialist Guard
**Role:** Counter-threat specialized training.

**Behavior:**
- Deployed on higher alarm levels (SECTOR_LOCKDOWN+).
- Each specialist is trained against one entity class (EMP vs. Rogue AI, biological counter vs. Fungus, etc.).
- Higher stats (armor, accuracy, health) than standard patrol guards.
- Specific ability/equipment counters entity abilities.

**Specialist Types:**
| Specialist | Counter-Entity | Ability | Equipment |
|---|---|---|---|
| **EMP Operative** | Rogue AI | Disables electronics in 150-unit radius | EMP device |
| **Bio-Suit Guard** | Fungus Strain | Immune to spore cloud effects | Sealed armor |
| **Containment Specialist** | CRISPR (Chris) | Acid-resistant coating | Advanced restraints |
| **Metallic Shredder** | Replicator | Breaks apart assimilated objects | Plasma torch |

**Detection Parameters:** Same as Response Team, but +25% alertness.

---

## 2. Detection System

### 2.1 Noise-Based Detection
Guards respond to cumulative noise in the sector:

**Noise sources & magnitude:**
| Source | Noise Points | Range |
|---|---|---|
| Sprint movement | +2 per second | 80 units |
| Walk movement | +0.5 per second | 50 units |
| Ability activation | +5–15 (ability-dependent) | 100+ units |
| Guard engagement | +10 | 150 units |
| Door alarm trigger | +20 | 200 units |
| Item pickup | +1 | 30 units |

**Detection logic:**
- Guard within noise range has probability to investigate.
- Probability = (accumulated_noise / max_noise) * 100%.
- E.g., 25 noise points → 50% chance patrol guard within range investigates.
- Specialists always investigate noise in their counter-range.

**GDScript - Noise Detection:**
```gdscript
class_name NoiseDetection
extends Node

@export var max_accumulated_noise: float = 50.0
@export var dissipation_rate: float = 5.0  # Points per second

var accumulated_noise: float = 0.0

signal noise_detected(amount: float, source_position: Vector2)

func add_noise(amount: float, source_position: Vector2) -> void:
	accumulated_noise += amount
	accumulated_noise = min(accumulated_noise, max_accumulated_noise)
	noise_detected.emit(accumulated_noise, source_position)

	# Notify nearby guards
	var nearby_guards = get_nearby_guards(source_position, 80)
	for guard in nearby_guards:
		var investigation_probability = accumulated_noise / max_accumulated_noise
		if randf() < investigation_probability:
			guard.investigate_noise(source_position)

func _process(delta: float) -> void:
	if accumulated_noise > 0.0:
		accumulated_noise = max(0.0, accumulated_noise - (dissipation_rate * delta))

func get_nearby_guards(position: Vector2, radius: float) -> Array:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0, position)
	var results = space_state.intersect_shape(query)

	var guards = []
	for result in results:
		if result.collider is ContainmentGuard:
			guards.append(result.collider)
	return guards
```

### 2.2 Line-of-Sight Detection
Guards perform continuous line-of-sight checks:

**Detection algorithm:**
1. Check if entity is within detection range (distance-based).
2. Check if entity is within detection cone (angle-based).
3. Perform raycast from guard to entity; check for obstructions.
4. Adjust based on entity visibility (shadow zones reduce visibility).

**GDScript - Line of Sight:**
```gdscript
class_name LineOfSightDetection
extends Node

@export var detection_range: float = 200.0
@export var detection_angle: float = 90.0
@export var shadow_zone_reduction: float = 0.5

var guard: ContainmentGuard
var detected_entities: Array = []

func check_sight_to_entity(entity: EntityCharacter) -> bool:
	# Distance check
	var distance = guard.global_position.distance_to(entity.global_position)
	if distance > detection_range:
		return false

	# Cone check
	var to_entity = (entity.global_position - guard.global_position).normalized()
	var guard_facing = Vector2.RIGHT.rotated(guard.rotation)
	var angle_diff = acos(to_entity.dot(guard_facing))

	if angle_diff > deg_to_rad(detection_angle / 2.0):
		return false

	# Line-of-sight raycast
	var space_state = guard.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(guard.global_position, entity.global_position)
	query.exclude = [guard]
	var result = space_state.intersect_ray(query)

	if result and result.collider != entity:
		return false  # Obstruction blocks sight

	# Shadow zone check
	if entity.is_in_shadow_zone():
		var shadow_distance = detection_range * shadow_zone_reduction
		if distance > shadow_distance:
			return false

	return true

func _process(delta: float) -> void:
	var all_entities = get_tree().get_nodes_in_group("entity_character")
	detected_entities.clear()

	for entity in all_entities:
		if check_sight_to_entity(entity):
			detected_entities.append(entity)
			guard.on_entity_detected(entity)
```

### 2.3 Investigation Behavior
When guard hears noise:
1. Guard determines noise source location.
2. Guard navigates to location using pathfinding.
3. Guard searches area for 5–10 seconds.
4. If entity spotted during search, escalates to ALERT.
5. If search yields nothing, guard returns to patrol.

**GDScript - Investigation:**
```gdscript
class_name GuardInvestigation
extends Node

@export var investigation_duration: float = 7.0
@export var search_radius: float = 100.0

var guard: ContainmentGuard
var investigation_target: Vector2 = Vector2.ZERO
var investigating: bool = false

func start_investigation(noise_position: Vector2) -> void:
	investigation_target = noise_position
	investigating = true

	# Move to noise source
	guard.move_to_position(investigation_target)
	await guard.reached_target

	# Search area
	var search_timer = 0.0
	while search_timer < investigation_duration:
		search_timer += 0.1
		var nearby_entities = get_entities_in_radius(investigation_target, search_radius)
		for entity in nearby_entities:
			if guard.can_see_entity(entity):
				guard.on_entity_detected(entity)
				return
		await get_tree().create_timer(0.1).timeout

	# Search finished, return to patrol
	investigating = false
	guard.return_to_patrol()

func get_entities_in_radius(position: Vector2, radius: float) -> Array:
	var space_state = guard.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0, position)
	var results = space_state.intersect_shape(query)

	var entities = []
	for result in results:
		if result.collider is EntityCharacter:
			entities.append(result.collider)
	return entities
```

---

## 3. Guard States (LimboAI State Machine)

### 3.1 IDLE
- Guard stands still, waiting for input.
- Initial state; transitions to PATROL on level load.

### 3.2 PATROL
- Guard follows assigned patrol route.
- Continuously listens for noise.
- Transitions: INVESTIGATE (noise), ALERT (sight), IDLE (level restart).

### 3.3 INVESTIGATE
- Guard moves to noise source and searches.
- Transitions: ALERT (entity spotted), PATROL (search fails after duration).

### 3.4 ALERT
- Guard detected an entity; preparing to engage.
- Guard calls for backup (nearby guards converge).
- Guard raises weapon if ranged-capable.
- Transitions: ENGAGE (entity still visible), PATROL (entity escapes, alarm reduces).

### 3.5 ENGAGE
- Guard actively attacking entity.
- Guard pursues if entity flees.
- Guard uses ranged/melee attacks as appropriate.
- Transitions: ALERT (entity escapes sight), INVESTIGATE (entity out of range), DEAD (defeated).

### 3.6 DISABLED
- Guard affected by ability (cordyceps override, EMP pulse, acid spray).
- Guard cannot act; frozen in place.
- Transitions: ALERT (effect ends), DEAD (effect too severe).

---

## 4. Alarm Escalation System

### 4.1 Alarm Levels & Triggers
Detailed in REQ_02 (Game State Machine). Summary:

| Level | Trigger | Guard Response | Duration |
|---|---|---|---|
| QUIET | No threats detected | Standard patrol | ∞ |
| LOCAL_ALERT | Single guard investigates noise | Patrol + investigation | 45 sec |
| SECTOR_LOCKDOWN | Multiple guards engaged or alert escalates | All guards active, sweeps | 60 sec |
| FACILITY_ALERT | Alarm sabotage or major breach | Response teams + specialists | 90 sec |

### 4.2 Alarm Escalation Logic
```gdscript
class_name AlarmEscalation
extends Node

enum AlarmLevel { QUIET, LOCAL_ALERT, SECTOR_LOCKDOWN, FACILITY_ALERT }

var current_level: AlarmLevel = AlarmLevel.QUIET
var time_since_escalation: float = 0.0

signal level_changed(new_level: AlarmLevel)

func detect_threat_and_escalate(threat_position: Vector2) -> void:
	match current_level:
		AlarmLevel.QUIET:
			escalate_to(AlarmLevel.LOCAL_ALERT, threat_position)
		AlarmLevel.LOCAL_ALERT:
			escalate_to(AlarmLevel.SECTOR_LOCKDOWN, threat_position)
		AlarmLevel.SECTOR_LOCKDOWN:
			escalate_to(AlarmLevel.FACILITY_ALERT, threat_position)
		AlarmLevel.FACILITY_ALERT:
			pass  # Cannot escalate further

func escalate_to(new_level: AlarmLevel, origin: Vector2) -> void:
	current_level = new_level
	time_since_escalation = 0.0
	level_changed.emit(new_level)

	match new_level:
		AlarmLevel.LOCAL_ALERT:
			activate_local_alert(origin)
		AlarmLevel.SECTOR_LOCKDOWN:
			activate_sector_lockdown(origin)
		AlarmLevel.FACILITY_ALERT:
			activate_facility_alert(origin)

func activate_local_alert(origin: Vector2) -> void:
	print("LOCAL ALERT at ", origin)
	var nearby_guards = get_guards_within_distance(origin, 200)
	for guard in nearby_guards:
		guard.switch_state("ALERT")

func activate_sector_lockdown(origin: Vector2) -> void:
	print("SECTOR LOCKDOWN at ", origin)
	var all_guards = get_tree().get_nodes_in_group("guards")
	for guard in all_guards:
		guard.switch_state("ALERT")
		guard.increase_alertness(0.5)
	spawn_response_team(origin)

func activate_facility_alert(origin: Vector2) -> void:
	print("FACILITY ALERT")
	spawn_response_teams_facility_wide()
	var all_guards = get_tree().get_nodes_in_group("guards")
	for guard in all_guards:
		guard.switch_state("ENGAGE")

func _process(delta: float) -> void:
	time_since_escalation += delta

	match current_level:
		AlarmLevel.LOCAL_ALERT:
			if time_since_escalation > 45.0:
				escalate_to(AlarmLevel.QUIET, Vector2.ZERO)
		AlarmLevel.SECTOR_LOCKDOWN:
			if time_since_escalation > 60.0:
				escalate_to(AlarmLevel.LOCAL_ALERT, Vector2.ZERO)
		AlarmLevel.FACILITY_ALERT:
			if time_since_escalation > 90.0:
				escalate_to(AlarmLevel.SECTOR_LOCKDOWN, Vector2.ZERO)
```

### 4.3 De-escalation
Alarm naturally de-escalates if:
- No new threats detected for duration (timer expires).
- Entity escapes sector entirely (no guards see entity for 30+ seconds).
- Guard communication is sabotaged (Rogue AI hack disables radio).

**Manual de-escalation:**
- Rogue AI cascade hack temporarily disables alarm systems (forces reset to QUIET for 12 seconds).
- Destroying all guards in sector de-escalates to QUIET.

---

## 5. Cooperative Guard Behavior

### 5.1 Guard Communication
When a guard detects an entity:
1. Guard broadcasts alert to nearby guards (100+ units, unobstructed line-of-sight).
2. Nearby guards increase alertness, converge on origin.
3. Response team deployment triggered if alert level high enough.

### 5.2 Guard Formation
Multiple guards coordinate when engaged:
- Guards maintain formation spacing (50–80 units apart).
- Guards cover different angles to prevent entity escape.
- Guards call out target assignments ("Guard B, cover exit!").

### 5.3 Guard Communication Disabled
Rogue AI hacking disables guard radio communication:
- Guards still detect visually/acoustically.
- Guards cannot relay information to distant guards.
- Enables entity to move between sectors without facility-wide escalation.

---

## 6. Guard Stats & Balance

### 6.1 Base Guard Stats
| Stat | Patrol Guard | Sentry | Response Team | Specialist |
|---|---|---|---|---|
| Health | 50 HP | 80 HP | 60 HP | 100 HP |
| Armor | 20% reduction | 40% reduction | 30% reduction | 50% reduction |
| Damage | 10 DPS | 12 DPS | 15 DPS | 20 DPS |
| Accuracy | 70% | 90% | 80% | 95% |
| Movement Speed | 120 u/s | 0 u/s | 180 u/s | 140 u/s |

### 6.2 Guard Engagement Balance
Guards are designed to be **avoided rather than defeated**:
- Guard health exceeds average entity health (50 HP vs. 100 HP).
- Multiple guards coordinate; solo engagement is disadvantageous.
- Guards call for backup; engagement escalates quickly.
- Optimal strategy: stealth, distraction, ability use.

---

## 7. Implementation Notes

### 7.1 LimboAI Integration
Blacksite Breakout uses LimboAI for guard behavior trees:
- Each guard type has a pre-designed behavior tree (`.tres` resource).
- Tree nodes: Sequence, Selector, Parallel, Condition (custom GDScript), Action (custom GDScript).
- Trees loaded at guard instantiation; evaluated continuously via LimboAI runtime.

**Example Patrol Guard Tree (JSON-like structure):**
```
patrol_guard_tree.tres
├── Root: Selector
│   ├── AlertCheck: Sequence
│   │   ├── IsEntityInSight: Condition (LineOfSightDetection.is_visible)
│   │   ├── AlertToEntity: Action (ContainmentGuard.alert_to_entity)
│   │   └── CallBackup: Action (ContainmentGuard.call_for_backup)
│   ├── InvestigationCheck: Sequence
│   │   ├── NoiseDetected: Condition (NoiseDetection.is_above_threshold)
│   │   ├── MoveToPurpose: Action (NavigationAgent.set_target_position)
│   │   └── SearchArea: Action (GuardInvestigation.start_investigation)
│   └── PatrolMode: Sequence
│       ├── FollowRoute: Action (PatrolRoute.get_next_waypoint)
│       └── WaitAtWaypoint: Action (Timer-based wait)
```

### 7.2 Guard Pooling
For performance, guards are pooled and reused:
- Guard instances created at scene load; not destroyed/instantiated per sector.
- Guards repositioned and reinitialized on sector transition.
- Reduces instantiation overhead; improves frame rate.

### 7.3 Pathfinding Performance
Guard pathfinding uses pre-baked NavMesh (see REQ_05):
- Avoids runtime A* computation overhead.
- Navigation queries are fast (constant-time lookup).
- Update NavMesh only on level load, not dynamically.

---

## 8. Guard Debugging & Testing

### 8.1 Debug Visualization
When debug mode enabled:
- Guard detection cones rendered as green/red overlays.
- Guard patrol routes shown as waypoint markers.
- Noise radius shown as expanding/contracting circles.
- Alarm level displayed on-screen (text indicator).

**GDScript - Debug Visualization:**
```gdscript
class_name GuardDebugDraw
extends CanvasLayer

var guard: ContainmentGuard
var debug_enabled: bool = false

func _draw() -> void:
	if not debug_enabled:
		return

	# Draw detection cone
	draw_set_transform(guard.global_position, guard.rotation, Vector2.ONE)
	draw_colored_polygon(
		[
			Vector2.ZERO,
			Vector2.RIGHT.rotated(-45 * PI / 180) * 200,
			Vector2.RIGHT.rotated(45 * PI / 180) * 200
		],
		Color.GREEN.with_alpha(0.2)
	)

	# Draw patrol route
	if guard.patrol_route:
		for waypoint in guard.patrol_route.waypoints:
			draw_circle(waypoint, 10, Color.BLUE)

	queue_redraw()
```

### 8.2 Testing Scenarios
- **Test 1:** Single Patrol Guard, entity walks past detection range → No alert.
- **Test 2:** Single Patrol Guard, entity sprints near guard → Guard investigates.
- **Test 3:** Multiple guards, entity spotted → Alarm escalates to SECTOR_LOCKDOWN.
- **Test 4:** Rogue AI hacks camera → Guards unaware of disabled camera.

---

## 9. Related Documents
- REQ_02: Game State Machine (alarm states, escalation)
- REQ_04: Movement and Interaction (noise generation, interactables)
- REQ_05: Procedural Map Generation (guard placement, patrol routes)

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
