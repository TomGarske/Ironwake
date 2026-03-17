# REQ_02: Game State Machine
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines all game states, transitions, and state-machine flow governing a Blacksite Breakout run. Includes handling of real-time movement vs. ability pauses, alarm escalation mechanics, and win/loss conditions.

---

## 1. State Overview

Blacksite Breakout uses a **hierarchical state machine** with primary states and sub-states for fine-grained control during encounters.

### 1.1 Primary State Diagram

```
┌─────────┐
│  LOBBY  │  (menu, player selection, co-op lobby setup)
└────┬────┘
     │ START_RUN
┌────▼────────────┐
│    BRIEFING     │  (show objective, sector overview, confirm ready)
└────┬────────────┘
     │ BEGIN_SECTOR
┌────▼──────────────────┐
│ SECTOR_EXPLORATION    │  (real-time movement, discovery)
└────┬─────────┬────────┘
     │         │ ALARM_TRIGGERED
     │    ┌────▼──────────┐
     │    │ ALARM_STATE   │  (escalation sub-states)
     │    └────┬──────────┘
     │         │ ALARM_REDUCED / ESCAPED_ALARM
     │    ┌────▼──────────────────────┐
     │    │ SECTOR_EXPLORATION        │
     │    └────┬──────────────────────┘
     │         │ OBJECTIVE_MET
     │         │ SECTOR_EXIT_FOUND
     │    ┌────▼─────────────────────┐
     │    │ SECTOR_EXIT_TRANSITION   │  (loading, fade-out)
     │    └────┬─────────────────────┘
     │ NEXT_SECTOR or END_ESCAPE
     │         │
     │    ┌────▼─────────────────┐
     │    │ FACILITY_EXIT        │  (escape complete, victory)
     │    └──────────────────────┘
     │
     └──> ENCOUNTER (if surprise ambush) → back to EXPLORATION
          or
     ┌─────────────────────┐
     │  ALL_CAPTURED       │  (run failed, all entities downed/captured)
     └─────────────────────┘
```

---

## 2. State Definitions

### 2.1 LOBBY
**Entry:** Game launch, player selects "New Run"
**Exit:** All players ready, co-op session confirmed
**Behavior:**
- Display player count (1–4 local or co-op).
- Allow player to select entity class (if not locked by co-op role assignment).
- Show sector difficulty indicators.
- Confirm start when all players ready.

**Signals:**
```gdscript
signal players_ready()
signal run_started()
```

---

### 2.2 BRIEFING
**Entry:** Run initialized, before first sector spawn
**Exit:** Player confirms ready / timer expires
**Behavior:**
- Present written objective: "Escape Area 51 through 5 sectors."
- Show map overview of current sector (fog of war active—only layout hints visible, no guard or item placement).
- Display entity roster with health, abilities, and synergy hints.
- Audio: tension-building instrumental (MusicManager intensity = 1.15, speed = 0.80).
- Player can review controls, toggle difficulty modifiers, confirm when ready.

**Signals:**
```gdscript
signal briefing_confirmed()
signal skip_briefing_on_sector_2_plus()
```

---

### 2.3 SECTOR_EXPLORATION
**Entry:** Player spawned in sector entry zone
**Exit:** Encounter triggered, alarm escalates, sector objective complete, or all players downed
**Behavior (detailed below in Section 3):**
- Real-time movement, co-op entity navigation.
- Fog of war reveals on movement.
- Guards patrol per LimboAI behavior trees.
- Player activates abilities (ability use briefly pauses movement).
- Interactables become available when player enters proximity.
- Noise radius tracks cumulative sound; exceeds threshold → LOCAL_ALERT.

**Sub-States:**
- **QUIET:** No alarm, guards on standard patrol.
- **HUNTING (during alarm escalation):** See Section 2.5 (ALARM_STATE).

**Signals:**
```gdscript
signal noise_level_changed(noise: float)
signal alarm_triggered(origin: Vector2)
signal objective_completed()
signal sector_exit_found()
signal entity_downed(entity: EntityCharacter)
signal entity_captured(entity: EntityCharacter)
```

---

### 2.4 ENCOUNTER
**Entry:** Surprise guard ambush, or deliberate entity-guard engagement
**Exit:** Guards defeated/fled, entity downed, or entities escape zone
**Behavior:**
- Guards switch to aggressive LimboAI state (ENGAGE).
- Entities can still move and use abilities (no true turn-based lock).
- Increased difficulty: multiple guards attack simultaneously; reinforcements may arrive.
- Player can attempt to flee encounter or hide.
- Duration: encounter ends when guards lose line-of-sight and time passes (3–5 seconds investigation).

**Signals:**
```gdscript
signal encounter_started(guard_count: int)
signal encounter_ended()
```

---

### 2.5 ALARM_STATE
**Entry:** Guard detects entity, camera spots movement, noise threshold breached
**Exit:** Alarm reduced to QUIET (time + no further triggers) or escalated to next level
**Sub-States (Alarm Levels):**

#### 2.5.1 LOCAL_ALERT
- **Duration:** 45 seconds (can be extended by re-triggering).
- **Guard Response:** Patrol guards in vicinity switch to INVESTIGATE; call for backup; non-patrol guards increase alertness.
- **Facility Effect:** Alarm siren briefly sounds; red warning light visible on-screen.
- **De-escalation:** No noise/detection for 45 seconds → return to QUIET.
- **Escalation Trigger:** Another detection or guard engagement → SECTOR_LOCKDOWN.

#### 2.5.2 SECTOR_LOCKDOWN
- **Duration:** 60 seconds (can extend).
- **Guard Response:** ALL guards in sector become active, aggressive search patterns; Response Teams may spawn at sector exits.
- **Facility Effect:** Red emergency lighting, continuous alarm loop, facility comms chatter.
- **De-escalation:** No detection for 60 seconds → LOCAL_ALERT → QUIET.
- **Escalation Trigger:** Entity caught, captured, or alarm sabotage fails → FACILITY_ALERT.

#### 2.5.3 FACILITY_ALERT
- **Duration:** 90 seconds hard lock (cannot de-escalate mid-alert).
- **Guard Response:** Response Teams sweep all sectors; Specialist guards deploy; all sector exits guarded.
- **Facility Effect:** Continuous red emergency state; facility lockdown audio loop.
- **De-escalation:** After 90 seconds, if no new threats detected → SECTOR_LOCKDOWN.
- **Escalation Trigger:** Cannot escalate further; only direction is de-escalation.

**Alarm State Machine GDScript:**
```gdscript
class_name AlarmState
extends Node

enum Level { QUIET, LOCAL_ALERT, SECTOR_LOCKDOWN, FACILITY_ALERT }

var current_level: Level = Level.QUIET
var time_in_level: float = 0.0
var origin_position: Vector2 = Vector2.ZERO
var active_guards: Array[ContainmentGuard] = []

const DURATIONS = {
	Level.QUIET: 999999.0,  # No timer
	Level.LOCAL_ALERT: 45.0,
	Level.SECTOR_LOCKDOWN: 60.0,
	Level.FACILITY_ALERT: 90.0,
}

signal level_changed(new_level: Level)
signal alarm_reduced(new_level: Level)
signal alarm_escalated(new_level: Level)

func escalate_alarm(new_origin: Vector2) -> void:
	origin_position = new_origin
	if current_level == Level.QUIET:
		set_level(Level.LOCAL_ALERT)
	elif current_level == Level.LOCAL_ALERT:
		set_level(Level.SECTOR_LOCKDOWN)
	elif current_level == Level.SECTOR_LOCKDOWN:
		set_level(Level.FACILITY_ALERT)
	# FACILITY_ALERT cannot escalate further

func set_level(new_level: Level) -> void:
	current_level = new_level
	time_in_level = 0.0
	alarm_escalated.emit(new_level)
	print("Alarm: %s" % Level.keys()[new_level])

func reduce_alarm(new_level: Level) -> void:
	current_level = new_level
	time_in_level = 0.0
	alarm_reduced.emit(new_level)
	print("Alarm reduced: %s" % Level.keys()[new_level])

func _process(delta: float) -> void:
	time_in_level += delta
	if current_level != Level.QUIET:
		var duration = DURATIONS[current_level]
		if time_in_level >= duration:
			if current_level == Level.FACILITY_ALERT:
				reduce_alarm(Level.SECTOR_LOCKDOWN)
			elif current_level == Level.SECTOR_LOCKDOWN:
				reduce_alarm(Level.LOCAL_ALERT)
			elif current_level == Level.LOCAL_ALERT:
				reduce_alarm(Level.QUIET)
```

---

### 2.6 SECTOR_EXIT_TRANSITION
**Entry:** Sector exit discovered and approached
**Exit:** Next sector loads, or final exit reached
**Behavior:**
- Fade screen to black (1 second).
- Load next sector (or facility exit scene).
- Restore player entity positions, health state, and ability cooldowns.
- Transition music: brief silence, then new sector briefing tone.
- Display sector number on-screen briefly (e.g., "SECTOR 3 OF 5").

**Signals:**
```gdscript
signal sector_transition_started()
signal sector_transition_complete(sector_number: int)
```

---

### 2.7 FACILITY_EXIT
**Entry:** Final sector exit reached and traversed
**Exit:** Run completes, return to lobby
**Behavior:**
- Victory cutscene or summary screen.
- Display run statistics: time elapsed, guards avoided/defeated, items collected, entities survived.
- Audio: triumphant theme (MusicManager intensity = 1.40, speed = 1.05).
- Player can view collectibles, achievements, or return to lobby.

**Signals:**
```gdscript
signal facility_exit_reached()
signal run_completed_victory()
```

---

### 2.8 ALL_CAPTURED
**Entry:** All entities downed simultaneously or last entity captured
**Exit:** Return to lobby
**Behavior:**
- Red screen tint, alarm loop fades to ominous silence.
- On-screen message: "ALL ENTITIES CONTAINED."
- Summary shows how far the run progressed (sector, time, objectives).
- Option to retry from LOBBY or review run.

**Signals:**
```gdscript
signal all_entities_captured()
signal run_failed()
```

---

## 3. Real-Time Movement vs. Ability Pause

### 3.1 Movement Phase (Continuous Real-Time)
- Player holds directional input or clicks target position.
- Entity moves toward target at `move_speed` (150.0 units/sec by default).
- Movement is not interrupted by NPC actions or ability activation.
- **Noise radius** expands based on movement type:
  - **Walk** (WASD held): small noise radius (10 units), quiet.
  - **Sprint** (Shift held): large noise radius (40 units), fast movement.
  - **Crawl** (entity-dependent, e.g., through vents): minimal noise (2 units), slowest.

### 3.2 Ability Activation & Recovery
When player activates an ability (e.g., press Shoulder Button L1 for Ability 1):
1. **Ability executes instantly** (e.g., spore cloud appears, hack initiates).
2. **Brief animation/effect plays** (~0.5–2.0 seconds depending on ability).
3. **Action Recovery Timer starts:** ability cannot be re-cast until timer expires.
4. **Entity can still move** during recovery.
5. **Other abilities can queue:** while Ability 1 is on cooldown, Ability 2 and Ultimate can still be activated (if their cooldowns permit).

**Recovery Timers per Ability:**
| Ability Type | Cooldown Duration | Notes |
|---|---|---|
| Active Ability 1 | 5–8 seconds | Most frequent, shortest cooldown |
| Active Ability 2 | 12–20 seconds | Moderate strategic use |
| Ultimate | 40–60 seconds | Powerful; long preparation required |
| Passive Trait | N/A | Always active (no cooldown) |

**GDScript Implementation:**
```gdscript
class_name EntityAbilityController
extends Node

@export var ability_1: BaseAbility
@export var ability_2: BaseAbility
@export var ultimate: BaseAbility

var cooldown_1: float = 0.0
var cooldown_2: float = 0.0
var cooldown_ult: float = 0.0
var is_executing_ability: bool = false

signal ability_executed(ability_index: int)
signal cooldown_updated(ability_index: int, remaining: float)

func _process(delta: float) -> void:
	if cooldown_1 > 0.0:
		cooldown_1 -= delta
		cooldown_updated.emit(0, cooldown_1)
	if cooldown_2 > 0.0:
		cooldown_2 -= delta
		cooldown_updated.emit(1, cooldown_2)
	if cooldown_ult > 0.0:
		cooldown_ult -= delta
		cooldown_updated.emit(2, cooldown_ult)

func activate_ability_1() -> void:
	if cooldown_1 > 0.0 or is_executing_ability:
		return
	is_executing_ability = true
	ability_1.execute(owner)
	cooldown_1 = ability_1.cooldown_duration
	await get_tree().create_timer(ability_1.execution_duration).timeout
	is_executing_ability = false
	ability_executed.emit(0)

func activate_ability_2() -> void:
	if cooldown_2 > 0.0 or is_executing_ability:
		return
	is_executing_ability = true
	ability_2.execute(owner)
	cooldown_2 = ability_2.cooldown_duration
	await get_tree().create_timer(ability_2.execution_duration).timeout
	is_executing_ability = false
	ability_executed.emit(1)

func activate_ultimate() -> void:
	if cooldown_ult > 0.0 or is_executing_ability:
		return
	is_executing_ability = true
	ultimate.execute(owner)
	cooldown_ult = ultimate.cooldown_duration
	await get_tree().create_timer(ultimate.execution_duration).timeout
	is_executing_ability = false
	ability_executed.emit(2)
```

---

## 4. Cooperative Alarm State & Noise Sharing

### 4.1 Shared Alarm State
All players in a co-op session share the same `AlarmState`. When **any** entity triggers noise or is detected:
- **Alarm level immediately escalates for all players.**
- All entity HUDs update to reflect new alarm level.
- All guards in all sectors become aware of increased threat level.

### 4.2 Noise Accumulation
Each sector tracks cumulative noise from all entities:
- **Noise sources:** footsteps during sprint, ability activation sounds, guard engagement, item pickup sounds.
- **Noise dissipation:** each second in QUIET state reduces cumulative noise by 5 points.
- **Threshold:** cumulative noise ≥ 50 points → escalate to LOCAL_ALERT.

**Noise Accumulation GDScript:**
```gdscript
class_name NoiseTracker
extends Node

@export var noise_threshold: float = 50.0
var accumulated_noise: float = 0.0

signal noise_changed(current_noise: float)
signal threshold_exceeded()

func add_noise(amount: float, source_position: Vector2) -> void:
	accumulated_noise += amount
	noise_changed.emit(accumulated_noise)
	if accumulated_noise >= noise_threshold:
		threshold_exceeded.emit()
		accumulated_noise = noise_threshold  # Cap at threshold

func _process(delta: float) -> void:
	if accumulated_noise > 0.0:
		accumulated_noise = max(0.0, accumulated_noise - (5.0 * delta))
		noise_changed.emit(accumulated_noise)
```

---

## 5. Sector Completion & Progression

### 5.1 Sector Structure
Each sector contains:
- **Entry zone:** Entity spawn location (usually guarded or observed).
- **Objectives:** At least one primary goal (retrieve keycard, hack terminal, reach vent, defeat key guard).
- **Hidden paths:** Optional shortcuts unlocked by entity abilities (Rogue AI hack, Chris mutation, Fungus mycelium network).
- **Exit zone:** Door or vent to next sector (locked until objective met or specific condition satisfied).

### 5.2 Objective Completion
When an entity triggers an objective (e.g., collects keycard item, reads terminal, opens locked door):
- **Event broadcast:** ObjectiveCompleted signal fired.
- **HUD update:** Objectives panel updates.
- **Exit unlock:** If all objectives met, sector exit becomes accessible.

### 5.3 Sector Exit Trigger
When player reaches exit zone:
- **Prompt:** "Press [INTERACT] to proceed to next sector."
- **State transition:** SECTOR_EXIT_TRANSITION → next sector load.
- **Cooldown reset:** All entity ability cooldowns reset (fresh start in new sector).
- **Health state maintained:** Entity health carries over (unless downed entity, which resets to 50% health on revive).

---

## 6. Downed & Captured System

### 6.1 Downed State
When entity health reaches 0:
- Entity becomes **Downed** (prone, uncontrollable, semi-transparent).
- Entity appears on all player HUDs as "NEEDS REVIVE."
- Downed entity broadcasts distress signal (audio/visual cue to allies).
- No longer contributes to alarm detection (guards don't see downed entity as threat).

### 6.2 Revive Mechanic
Another entity must move adjacent to downed entity and press **[INTERACT]**:
- Revive takes 3 seconds (uninterruptible).
- Reviving entity cannot move or use abilities during revive.
- Downed entity revives with 50% max health.
- Revived entity regains control immediately after revive completes.
- HUD shows revive progress bar (visual feedback to allies).

### 6.3 Captured
If downed entity remains unrevived for 60 seconds (or all allies also downed):
- Entity is **Captured** by guards.
- Entity removed from run permanently (no respawn).
- Entity no longer controllable or visible on map.
- If last entity captured → ALL_CAPTURED state → run failed.

**Downed/Revive GDScript:**
```gdscript
class_name DownedSystem
extends Node

@export var revive_duration: float = 3.0
@export var capture_timeout: float = 60.0

var downed_entities: Dictionary = {}  # entity -> time_downed

signal entity_downed(entity: EntityCharacter)
signal entity_revived(entity: EntityCharacter)
signal entity_captured(entity: EntityCharacter)

func mark_downed(entity: EntityCharacter) -> void:
	if entity not in downed_entities:
		downed_entities[entity] = 0.0
		entity_downed.emit(entity)
		entity.is_downed = true

func revive_entity(entity: EntityCharacter, reviver: EntityCharacter) -> void:
	if entity not in downed_entities:
		return
	await get_tree().create_timer(revive_duration).timeout
	downed_entities.erase(entity)
	entity.revive_by_ally(reviver)
	entity_revived.emit(entity)

func _process(delta: float) -> void:
	for entity in downed_entities.keys():
		downed_entities[entity] += delta
		if downed_entities[entity] >= capture_timeout:
			entity_captured.emit(entity)
			downed_entities.erase(entity)
```

---

## 7. Win & Lose Conditions

### 7.1 Win Condition: FACILITY_EXIT
**Triggered when:** Any entity reaches the final sector exit and initiates transition.

### 7.2 Lose Condition: ALL_CAPTURED
**Triggered when:**
- All four entities are captured, OR
- All four entities are simultaneously downed with no revive possible.

### 7.3 Soft Fail (Low Progress)
- If run reaches SECTOR_LOCKDOWN and remains locked for 90+ seconds (unable to progress), the run effectively ends in failure.
- Optional: auto-trigger ALL_CAPTURED state if entities trapped.

---

## 8. Implementation Notes

### 8.1 State Persistence Across Sectors
- Entity health and cooldown state carried over between sectors (cooldowns reset).
- Downed state does NOT carry over; downed entity must be revived before sector exit.
- Alarm state resets to QUIET when entering new sector (tension reprieve).

### 8.2 Co-op Synchronization
- All state changes (alarm escalation, entity downed, objective completed) broadcast to all connected players.
- GameManager maintains authoritative state; clients update local UI based on broadcasts.

### 8.3 Music Manager Integration
- Alarm escalation triggers MusicManager to increase intensity.
  - QUIET: intensity = 1.15, speed = 0.80
  - LOCAL_ALERT: intensity = 1.25, speed = 0.95
  - SECTOR_LOCKDOWN: intensity = 1.35, speed = 1.10
  - FACILITY_ALERT: intensity = 1.45, speed = 1.20

### 8.4 Save/Load
- Current design emphasizes run-based progression (no mid-run saves).
- Optional: checkpoint at sector start (player can reload last sector if all die).

---

## 9. Related Documents
- REQ_01: Vision and Architecture (node structure, overall design)
- REQ_03: Entity Classes and Abilities (ability cooldown values)
- REQ_06: Guard AI and Alarm System (guard behavior tree coordination with alarm states)

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
