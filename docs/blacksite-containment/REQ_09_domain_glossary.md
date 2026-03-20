# REQ_09: Domain Glossary
**Blacksite Containment Terms and Definitions**

## Core Entities

### Drone
**Definition**: A hovering security vessel piloted by a player. Drones patrol the containment facility and intercept escapees using four core abilities.

**Code Equivalent**: `DronePlayer` (CharacterBody3D), inherits from `Character3D` or similar base.

**Key Properties**:
- Position (global_position: Vector3).
- Health (100 HP, not visible to player; drones are invincible in MVP).
- Velocity (current_velocity: Vector3).
- Facing direction (global_transform.basis.z).
- Ability states (charge_laser_progress, overheat_cooldown, etc.).
- Owner/Authority (is_multiplayer_authority(): bool for networking).

**Behaviors**:
- Hovers freely in 3D space (no gravity).
- Responds to player input (movement, abilities).
- Emits laser and orbital strikes.
- Gains points for escapee destruction (assist/kill credit).

**Network Role**: Each drone is authority over its own input (client-side); position synced to other players via RPC.

---

### Escapee
**Definition**: A hostile entity attempting to breach the facility perimeter. Escapees spawn in containment lanes, travel toward breach zones, and are destroyed by drone fire.

**Code Equivalent**: `EscapeeEntity` (CharacterBody3D base), subclasses: `EscapeeRunner`, `EscapeeEvader`, `EscapeeTank`, `EscapeeSwarm`, `EscapeeElite`.

**Key Properties**:
- Type (string: "runner", "evader", "tank", "swarm", "elite").
- Health (int: varies by type, 20–250).
- Max Health (int: baseline value before multipliers).
- Speed (float: m/s, varies by type and difficulty).
- Position (global_position: Vector3).
- Behavior Tree (root node).
- Damage Sources (array of drone IDs that have dealt damage; used for scoring).

**Behaviors** (vary by type):
- Pathfind toward breach zone using NavigationAgent3D.
- Detect nearby drones (threat awareness, type-dependent).
- Evade, strafe, or flee (type-dependent evasion).
- Take damage; health decreases.
- Destroy on health <= 0; emit destruction signal.
- Breach perimeter if reaching breach zone; trigger integrity loss.

**Network Role**: Host (server) runs all escapee AI and movement. Clients receive position updates via RPC; visual interpolation is client-side.

---

### Containment Lane
**Definition**: A designated patrol corridor where escapees spawn and travel toward the perimeter. Drones patrol lanes to intercept.

**Code Equivalent**: `ContainmentLane` (Area3D + Node3D composite).

**Components**:
- **Lane Path** (Path3D): Breadcrumb waypoints guiding escapee navigation.
- **Spawn Zone** (Area3D): Trigger area where escapees are instantiated.
- **Spawn Points** (Marker3D array): Discrete positions within spawn zone; escapees pick random point at spawn.
- **Lane Collider** (StaticBody3D): Collision geometry defining lane boundaries.
- **Visual Markers** (optional): Subtle floor lines or warning signage (clinical aesthetic).

**Gameplay Role**:
- Multiple lanes (3–4 per mission) allow drones to anticipate and intercept.
- Lane choice by escapees is somewhat random (different spawn points per escapee).
- Drones position themselves to cover multiple lanes or focus on high-threat lanes.

**Data Representation**:
```gdscript
class LaneConfig:
	var lane_id: String = "lane_north"
	var spawn_points: Array[Vector3] = []  # Marker positions
	var breach_target: Vector3 = Vector3.ZERO  # Shared perimeter zone
	var path_waypoints: Array[Vector3] = []  # Navigation hints
```

---

### Perimeter Breach
**Definition**: The act or event of an escapee reaching the facility's outer boundary. A breach triggers facility containment loss.

**Code Equivalent**: `PerimeterBreach` (Area3D + script), `PerimeterDetector` (Node managing breach zones).

**Mechanics**:
- **Detection**: Area3D `area_entered` signal triggers on escapee collision.
- **Consequence**: Mission integrity meter decreases by 25 points.
- **Escapee Removal**: Breaching escapee is destroyed; no longer a threat.
- **Broadcast**: All drones notified of breach via signal/HUD alert.
- **Audio/Visual**: Klaxon alarm, red screen flash.

**Instances**:
- One or more breach zones positioned around arena perimeter (e.g., N, S, E, W, NE, NW).
- Escapees navigate to nearest breach zone.
- Multiple breaches possible per wave (count tracked in wave state).

**Scoring Impact**: Each breach reduces wave score (see REQ_05).

---

## Core Mechanics

### Charge Laser
**Definition**: The drone's primary weapon. Hold Right Trigger to charge energy over 1 second; release to fire a hitscan beam. Damage scales with charge level.

**Code Equivalent**: `DroneAbilityManager.charge_laser_*` properties and methods.

**Mechanics**:
- **Charge Phase**:
  - Duration: 0–1.0 second.
  - Charge ratio: `charge_duration / CHARGE_TIME` (0.0 to 1.0).
  - Charge Levels:
    - 0.0–0.33: Weak (25 damage).
    - 0.33–0.67: Medium (65 damage).
    - 0.67–1.0: Full (100 damage).
  - Charging visual: Cyan barrel glow, intensity scales.
  - Charging audio: Rising hum, pitch 200Hz → 800Hz.

- **Fire Phase**:
  - Occurs on RT release (if charge < 1.0s) or auto-fire on overheat (charge > 1.0s).
  - Type: Hitscan raycast from drone to 50-meter range.
  - Target detection: Physics raycast intersect, filters for escapees.
  - Damage application: `escapee.take_damage(damage, source_drone_id)`.
  - VFX: Cyan laser beam, impact bloom.
  - Audio: Sharp laser zap, ~50ms duration.

- **Overheat Phase**:
  - Triggered if RT held > 1.0 second.
  - Effect: Automatic fire at full damage (100), then 2-second cooldown.
  - During cooldown: RT input ignored; no charging allowed.
  - VFX: Red drone glow, smoke particles.
  - Audio: Three warning beeps, harsh error alarm.

**Tuning Parameters**:
- `CHARGE_TIME: float = 1.0` (seconds to full charge).
- `OVERHEAT_COOLDOWN: float = 2.0` (seconds penalty).
- `LASER_DAMAGE_FULL: float = 100.0` (damage at full charge).
- `LASER_RANGE: float = 50.0` (meters).

**Player Skill**: Timing charge release at the moment of full charge (avoiding overheat) + aiming at moving escapees (leading shots).

---

### Overheat
**Definition**: A penalty state triggered by holding the charge laser beyond full charge. Overheat locks the ability for a cooldown period, preventing spam.

**Code Equivalent**: `DroneAbilityManager.is_overheat_cooldown: bool`, `overheat_cooldown_remaining: float`.

**Mechanics**:
- **Trigger**: Charge duration > 1.0 second while RT held.
- **Immediate Effect**: Automatic fire at full damage (100), then lock charging.
- **Cooldown**: 2 seconds. During cooldown, RT input is ignored; HUD shows countdown.
- **Recovery**: After cooldown expires, charging is re-enabled.
- **Penalty**: Overheat count incremented (stats); no score penalty in MVP.

**Visual Feedback**:
- Drone barrel glows red.
- Screen tint briefly red.
- HUD overheat meter fills to red and decrements during cooldown.

**Audio Feedback**:
- Three ascending beeps (warning).
- Harsh alarm tone (fail state).
- Hiss or pop (system error effect).

**Design Goal**: Punish careless trigger discipline; reward precise, controlled charging.

---

### Orbital Strike Call-in
**Definition**: A tactical area-of-effect ability that calls down a satellite strike. Targeted, delayed impact; limited uses per mission.

**Code Equivalent**: `DroneAbilityManager.orbital_strike_*` properties; `_orbital_impact_delayed()` RPC.

**Mechanics**:
- **Activation**: Press RB to enter targeting mode.
- **Targeting**: Reticle (8m radius) appears 10m ahead of drone; right stick adjusts aim.
- **Confirmation**: Press RB again to call strike.
- **Delay**: 2–3 seconds between call and impact (telegraphed to all players).
- **Impact**: Sphere collision check at target position (8m radius), damage 200 center → 50 edges (linear falloff).
- **Effect**: All escapees within radius take damage; drones are immune (no friendly fire).
- **Uses**: 2 per mission (recharge on 20s cooldown each, stackable to 2).

**Tuning Parameters**:
- `ORBITAL_STRIKE_DELAY: float = 2.5` (seconds to impact).
- `ORBITAL_RADIUS: float = 8.0` (explosion radius).
- `ORBITAL_CENTER_DAMAGE: float = 200.0` (peak damage).

**Deferred in MVP**: Implemented post-launch.

---

### Burst Speed Maneuver
**Definition**: A short-distance dash that briefly grants invincibility. Useful for evasion and repositioning.

**Code Equivalent**: `DroneAbilityManager.burst_*` properties; `activate_burst()` method.

**Mechanics**:
- **Activation**: Press LB.
- **Direction**: Dash in current movement direction (or forward if idle).
- **Distance**: 15 meters.
- **Duration**: 0.3 seconds.
- **Invincibility**: Drone cannot take damage during dash (if damage were possible).
- **Cooldown**: 8 seconds (shared pool with framerate control energy).
- **Interrupt**: Cancels ongoing charge laser (if RT held).

**Tuning Parameters**:
- `BURST_DISTANCE: float = 15.0` (meters).
- `BURST_COOLDOWN: float = 8.0` (seconds).

**Deferred in MVP**: Implemented post-launch.

---

### Framerate Control (Bullet Time)
**Definition**: A client-side time-dilation ability that slows perceived time for the activating drone, aiding precision and dodging.

**Code Equivalent**: `DroneAbilityManager.framerate_control_*` properties; client-side `Engine.time_scale` manipulation.

**Mechanics**:
- **Activation**: Press LT.
- **Effect**: Client time scale drops to 30% (0.3x speed).
- **Scope**: Only the activating drone perceives slowdown; other players see normal speed (no network desync).
- **Duration**: 5 seconds subjective time (~1.67 seconds real time).
- **Energy Cost**: 60 points from shared energy pool (100 max).
- **Energy Regen**: +10 per second passively.
- **Cooldown**: 6 seconds between uses (prevents spam).

**Tuning Parameters**:
- `FRAMERATE_CONTROL_TIME_SCALE: float = 0.3`.
- `FRAMERATE_CONTROL_DURATION: float = 5.0` (subjective).
- `FRAMERATE_CONTROL_COST: float = 60.0` (energy).
- `ENERGY_REGEN_RATE: float = 10.0` (per second).

**Design Goal**: Gives skilled players a tactical perception shift; requires energy management.

**Deferred in MVP**: Implemented post-launch.

---

## Ability & Resource Management

### Wave
**Definition**: A spawning phase of a mission during which a fixed number of escapees are released into the arena in sequence. Waves escalate in difficulty.

**Code Equivalent**: Wave configuration (JSON or Godot resource), `WaveConfig` struct.

**Data**:
```gdscript
class WaveConfig:
	var wave_number: int = 1
	var name: String = "Initial Assessment"
	var escapee_count: int = 20
	var spawn_rate: float = 0.33  # per second
	var duration_seconds: int = 60
	var composition: Dictionary = {"basic_runner": 20}  # type → count
	var difficulty_multiplier: float = 1.0
	var elite_chance: float = 0.0  # 0.0 to 1.0
```

**Lifecycle**:
1. **Spawn Phase**: Escapees instantiated at intervals per `spawn_rate`.
2. **Active Phase**: Drones fight escapees; spawning continues until quota met.
3. **Clear Phase**: Last escapee destroyed; no new spawns.
4. **Completion**: Signal `wave_complete` emitted; next wave begins (or mission ends if final).

**Difficulty Scaling**:
- Escapee health multiplied by `difficulty_multiplier` (e.g., Wave 2: * 1.15).
- Spawn rate increases per wave (Wave 1: 0.33/s, Wave 2: 0.67/s, Wave 3: 1.0/s).
- Further scaled by player count multiplier (1-player: 0.7x, 4-player: 1.0x, 8-player: 1.6x).

---

### Mission Integrity
**Definition**: A shared facility containment metric. Starts at 100 points; each breach reduces it by 25. Mission fails if integrity reaches 0.

**Code Equivalent**: `MissionIntegrity` (Node), `integrity: int` property (0–100).

**Mechanics**:
- **Start Value**: 100 points.
- **Breach Cost**: 25 points per breach event (fixed).
- **Tolerance Per Wave**: ceil(escapee_count / 10). E.g., 20 escapees = tolerance of 2 breaches before score penalty.
- **Failure Threshold**: 0 points → immediate mission failure.
- **Recovery**: No healing; integrity only decreases.

**Display**:
- HUD: Progress bar, percentage text, color gradient (green → red).
- Updates: Real-time on breach event.

**Scoring Impact** (REQ_05):
- Breach prevention score calculated as: `100 * (1.0 - breaches_this_wave / tolerance)`.
- Multiple breaches = reduced score; zero breaches = perfect score.

---

### Breach Event
**Definition**: The occurrence of an escapee reaching the perimeter and triggering a facility containment loss.

**Code Equivalent**: Signal `breach_occurred(remaining_integrity: int)`.

**Trigger**:
- Escapee enters `PerimeterBreach` Area3D.
- Automatically on any escapee collision with breach zone geometry.

**Immediate Consequence**:
1. Escapee removed from arena.
2. Mission integrity decreases by 25.
3. Signal emitted to all drones and UI.
4. Klaxon alarm sounds; red screen flash.
5. HUD displays "BREACH EVENT - Integrity: 75%".

**Impact on Mission**:
- If integrity > 0: game continues (mission resilient; can sustain multiple breaches).
- If integrity = 0: immediate transition to MISSION_FAILED state.

**Scoring**: Breaches tracked per wave; reduce wave score if tolerance exceeded.

---

### Alert State
**Definition**: A heightened threat condition triggered when a drone detects a nearby escapee. Chase timer begins; destruction urgency escalates.

**Code Equivalent**: `StateManager` state, `state == "ALERT"`.

**Trigger**:
- Escapee enters detection radius (~20m) of any drone.
- Signal `escapee_detected(escapee_node)` emitted.

**Duration**:
- Active until escapee destroyed (transition to SUCCESS) or timer expires (transition to BREACH_ATTEMPT).
- Chase timer: ~30 seconds (tunable).

**Active Behavior**:
- All drones alerted (notification broadcast).
- Escapee position visible on minimap (threat marker).
- Audio: klaxon + escalated music profile.
- Visual: HUD flashes; threat direction displayed.

**Purpose**: Creates urgency; prevents passive patrols; rewards coordinated response.

**Deferred in MVP**: Simplified to direct breach detection (no intermediate ALERT state).

---

### Debrief
**Definition**: The end-of-mission screen displaying mission outcome, score breakdown, and statistics.

**Code Equivalent**: `DebriefUI` (CanvasLayer), `DebriefsScreen.tscn`.

**Displayed Information**:
- **Mission Status**: "Successful" (green), "Failed" (red), "Partial" (yellow).
- **Final Score**: Large, prominent number.
- **Breakdown**:
  - Per-wave score (Wave 1: 350, Wave 2: 425, etc.).
  - Breach prevention bonus/penalty.
  - Kill count total.
  - Assist count (if applicable).
  - Time bonus (if applicable).
- **Team Stats**:
  - Top killer, most assists, accuracy (overheats avoided).
  - Integrity remaining (%).
- **Navigation**:
  - "Next Mission" button → return to LOBBY, reload scene.
  - "Return to Lobby" button → quit mission, return to main hub.

**Display Duration**: 10 seconds auto-advance (or until input), then options appear.

**MVP Scope**: Minimal debrief; basic score display. Full breakdown deferred to Phase 6+ (REQ_08).

---

## Difficulty & Progression

### Difficulty Multiplier (Per Wave)
**Definition**: A scaling factor applied to escapee stats per wave to increase challenge.

**Code Equivalent**: `WaveConfig.difficulty_multiplier: float` (1.0 baseline, > 1.0 harder).

**Application**:
- Health: `health = base_health * difficulty_multiplier`.
- Speed: `speed = base_speed * (1.0 + (multiplier - 1.0) * 0.5)`.
- Example Wave 3 (multiplier 1.35): Runners have 50 * 1.35 = 67.5 HP; speed 15 * (1.0 + 0.35 * 0.5) = 15 * 1.175 = 17.6 m/s.

**Purpose**: Natural escalation without introducing new enemy types.

---

### Player Count Multiplier
**Definition**: Scaling applied to wave parameters based on player count, ensuring appropriate difficulty balance.

**Code Equivalent**: `get_player_count_multiplier(player_count: int) -> float`.

**Multipliers**:
- 1 player: 0.8x health, 0.7x spawn rate (solo is easier).
- 2–3 players: 0.9x health, 0.85x spawn rate (small team, moderate).
- 4 players: 1.0x health, 1.0x spawn rate (baseline, intended difficulty).
- 5–6 players: 1.2x health, 1.3x spawn rate (large team, harder).
- 7–8 players: 1.5x health, 1.6x spawn rate (full squad, very hard).

**Application**: Combined with wave difficulty_multiplier.
- Example: 8-player Wave 3: health = 50 * 1.35 (wave) * 1.5 (players) = 101.25 HP per Runner.

---

## Score & Statistics

### Kill Credit
**Definition**: Attribution of escapee destruction to a specific drone. Killer receives 10 points per escapee; assists give 15 points.

**Code Equivalent**: Signal `escapee_destroyed(source_drone_id: String)` → ScoreTracker increments kills.

**Mechanism**:
- Escapee tracks damage sources (array of drone IDs in order).
- On death, first source = kill credit, rest = assist credit.
- RPC broadcast to all clients for score sync.

**Scoring**:
- Kill: +10 points.
- Assist: +15 points (encouraging cooperation).

---

### Mission Success / Failure Conditions
**Definition**: End-state criteria determining mission outcome.

**Success**:
- All waves cleared (escapees spawned and destroyed).
- Integrity > 0 (no critical containment failure).
- **Outcome**: MISSION_COMPLETE state → victory debrief, full score awarded.

**Failure**:
- Integrity reduced to 0 before all waves cleared.
- **Outcome**: MISSION_FAILED state → defeat debrief, minimal/zero score.

**Partial Success** (future variant):
- All waves cleared but integrity < 50%.
- **Outcome**: MISSION_COMPLETE but score reduced by integrity multiplier.

---

## Network & Synchronization

### Host Authority
**Definition**: The server (host player) runs game logic; clients send input/requests and receive state updates.

**Applies To**:
- Escapee AI movement and pathfinding.
- Damage registration (validation, application).
- State machine transitions.
- Wave progression and scoring.

**Rationale**: Prevents cheating (damage denial, escapee manipulation). Single source of truth.

---

### RPC Protocol (Client ↔ Host)

**Client → Host**:
- `_request_escapee_damage(escapee_id: String, damage: float, source_drone_id: String)`: Client fire event.
- `_sync_position_to_network()`: Periodic drone position update.

**Host → All**:
- `_apply_escapee_damage_vfx(hit_position: Vector3)`: Broadcast impact visual.
- `_escapee_destroyed(escapee_id: String)`: Broadcast destruction signal.
- `_sync_escapee_position(escapee_id: String, position: Vector3)`: Broadcast escapee position.
- `_breach_occurred(remaining_integrity: int)`: Broadcast breach event.
- `_wave_complete()`: Signal wave progression.

**Rate Limiting**:
- Position updates: every 2 frames (~33ms at 60fps), with delta compression (only send if moved >0.5m).
- Damage requests: per laser fire (1 request per release).
- State changes: immediate broadcast (no batching).

---

## Summary Table

| Term | Code Equivalent | Purpose |
|------|-----------------|---------|
| Drone | DronePlayer | Player-controlled floating vessel |
| Escapee | EscapeeEntity | Hostile entity to destroy |
| Containment Lane | ContainmentLane | Spawn/patrol corridor |
| Perimeter Breach | PerimeterBreach | Facility boundary; breach triggers loss |
| Charge Laser | charge_laser_* | Primary weapon ability |
| Overheat | overheat_cooldown_* | Penalty for overcharging |
| Orbital Strike | orbital_strike_* | Area-of-effect ability (deferred) |
| Burst Speed | burst_* | Dash/evasion ability (deferred) |
| Framerate Control | framerate_control_* | Time-dilation ability (deferred) |
| Wave | WaveConfig | Spawning phase of escalating difficulty |
| Mission Integrity | MissionIntegrity | Shared containment health (0–100) |
| Breach Event | breach_occurred signal | Escapee reaches perimeter |
| Alert State | state == "ALERT" | Heightened threat phase (deferred MVP) |
| Debrief | DebriefUI | End-mission results screen |

---

**Implementation Notes:**
- All terms are used consistently across all REQ docs (REQ_01 through REQ_08).
- Code examples use GDScript 2.0 (Godot 4.1+).
- Network concepts assume Godot's built-in MultiplayerAPI and RPC system.
- Deferred features (MVP notes) will be fully implemented in post-launch phases.
