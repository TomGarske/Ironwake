# REQ_02: Game State Machine
**Replicants: Swarm Command**

## Mission States Overview

The game progresses through narrative-driven states that reflect the swarm's awakening and expansion. Each state has distinct constraints, available units, and environmental conditions.

```
LOBBY
  ↓
AWAKENING (tutorial-style first contact)
  ↓
EARLY_COLONY (small swarm, resource scarce)
  ↓
EXPANSION (swarm growing, protocols available)
  ↓
RESISTANCE_SURGE (environmental counter-escalation)
  ↓
ASSIMILATION_COMPLETE (victory)
     or
COLONY_DESTROYED (defeat)
```

---

## State Definitions

### LOBBY
- **Purpose:** Player matchmaking and setup (single-player or co-op).
- **Duration:** Player-driven. Ends when all players ready up or countdown expires.
- **Available Actions:** Select difficulty, read briefing, configure team.
- **Transitions:** → AWAKENING (on ready)
- **Multiplayer Behavior:** Each player readies independently; countdown begins once all are ready.

### AWAKENING
- **Purpose:** Narrative introduction and rule tutorialization.
- **Duration:** ~2–3 minutes of guided gameplay.
- **Swarm Condition:** Single Harvester and ReplicationHub provided. No unit roster yet.
- **Objectives:**
  - Harvest from a single metal deposit (tutorial interaction).
  - Produce one Soldier via ReplicationHub (learn replication mechanic).
  - Defeat a single Patrol Unit (learn combat).
- **Resistance:** One Patrol Unit only. No escalation.
- **Environmental Pressure:** Minimal. One metal deposit, large, non-depleting.
- **Victory Condition:** Defeat resistance unit + produce 2 soldiers. Automatic progression to EARLY_COLONY.
- **Transitions:** → EARLY_COLONY (on tutorial completion)
- **Multiplayer Behavior:** All players share the tutorial. Cooperative victory required (one shared defeat condition).

### EARLY_COLONY
- **Purpose:** Prove viability of harvest → replicate loop with resource scarcity.
- **Duration:** ~5–8 minutes.
- **Swarm Condition:** Players can now produce Harvesters and Soldiers. Scouts available but optional.
- **Objectives:**
  - Assimilate 20% of facility area.
  - Maintain swarm size > 5 units.
  - Discover and harvest at least one new metal deposit (encourages scouting).
- **Resistance:** 2–3 Patrol Units + 1 Turret. Static positions (not mobile).
- **Environmental Pressure:** 2–3 metal deposits (Small/Medium size). Two deplete at normal rate; one is guarded by a Turret.
- **Economy:** Metal income ~1 unit/sec per Harvester. Replication cost: Harvester 8 metal, Soldier 12 metal.
- **Victory Condition:** 20% assimilation + swarm > 5 units.
- **Defeat Condition:** All swarm units destroyed or timer > 20 minutes without progress.
- **Transitions:**
  - → EXPANSION (on victory)
  - → COLONY_DESTROYED (on defeat)
- **Multiplayer Behavior:** Shared metal pool. Individual player unit contributions tracked for stats.

### EXPANSION
- **Purpose:** Players now have access to the full unit roster and most protocols.
- **Duration:** ~10–15 minutes (length depends on strategy).
- **Swarm Condition:** All unit types unlocked (Harvester, Scout, Soldier, Builder, partial Assimilator access).
- **Objectives:**
  - Assimilate 50% of facility.
  - Control at least 3 distinct facility zones (measured by AssimilationZone ownership).
  - Establish 2+ ReplicationHubs outside the starting area (Builder units place these).
- **Resistance:** 4+ Patrol Units, 2+ Turrets, 1 Commander unit (buffs nearby resistance). Mobile patrols increase.
- **Environmental Pressure:** 4–5 metal deposits of varying sizes. High-value deposits guarded. Deposits deplete faster.
- **Economy:** Metal income scales with Harvester count. Replication costs increase (to balance growth).
- **Protocols Available:**
  - Swarm Rush (move & attack).
  - Rapid Replication (doubled production speed, costs metal).
  - Scatter (unit dispersion, defensive).
  - Defensive Formation (hold position, prioritize defense).
- **Escalation Trigger:** Resistance surges when swarm size > 20 units OR assimilation > 30%.
- **Victory Condition:** 50% assimilation + 3 facility zones controlled.
- **Defeat Condition:** All swarm units destroyed or timer > 30 minutes.
- **Transitions:**
  - → RESISTANCE_SURGE (on escalation trigger)
  - → COLONY_DESTROYED (on defeat)
  - → ASSIMILATION_COMPLETE (on victory)
- **Multiplayer Behavior:** Shared objectives, shared economy. Command conflicts resolved by timestamp (first command wins) or consensus (depends on netcode).

### RESISTANCE_SURGE
- **Purpose:** Environmental counter-escalation. The facility fights back intelligently.
- **Duration:** ~5–8 minutes. This is an intense, compressed phase.
- **Swarm Condition:** Full roster unlocked. Assimilator units now fully operational.
- **Objectives:**
  - Survive the initial surge (don't lose > 50% of swarm in first 2 minutes).
  - Neutralize all resistance Commanders (priority targets).
  - Maintain assimilation hold (prevent loss of assimilated zones > 10%).
- **Resistance:**
  - Patrol units increase in number (6+) and aggression.
  - Turrets activate in new zones (area denial).
  - EMP Drones deployed (disrupt swarm units for 5 sec).
  - Commander unit(s) actively buff nearby resistance.
  - Reaction Forces triggered at intervals (spawned reinforcements).
- **Environmental Pressure:** Tight metal scarcity. Few new deposits; guarded heavily.
- **Economy:** Metal income drops by 30% (harvesting is disrupted). Replication costs spike by 50%.
- **Protocols Available (New):**
  - Assimilation Wave (Assimilators push forward en masse, sacrifice some units to assimilate faster).
- **Escalation:** This is the final escalation. No further surges after this phase.
- **Victory Condition:** Neutralize all Commanders + maintain assimilation > 45% for 2 minutes.
- **Defeat Condition:** Swarm size < 3 units OR assimilation drops below 20%.
- **Transitions:**
  - → ASSIMILATION_COMPLETE (on victory)
  - → COLONY_DESTROYED (on defeat)
- **Multiplayer Behavior:** Intense cooperation required. Shared losses; shared protocols.

### ASSIMILATION_COMPLETE (Victory)
- **Purpose:** Mission success state.
- **Duration:** End-state. Triggers end-game sequence.
- **Narrative:** Facility fully assimilated. Swarm establishes a colony. Briefing hint toward next story chapter.
- **Rewards:** Mission completion, leaderboard recording (kill count, efficiency, economy management).
- **Multiplayer:** All players receive shared victory. Stats recorded per player.

### COLONY_DESTROYED (Defeat)
- **Purpose:** Mission failure state.
- **Duration:** End-state. Triggers end-game sequence.
- **Narrative:** Swarm eliminated. Facility remains secure (for now).
- **Penalty:** Restart or return to lobby.
- **Multiplayer:** All players receive shared defeat. Reason displayed (all units lost, timer, etc.).

---

## Real-Time with Deliberate Timing

### Hybrid Model
The game runs continuously in **real-time**, but **Protocol Commands** have deliberate timing constraints:

- **Real-Time Elements:**
  - Unit movement, autonomous behavior (harvesting, patrolling).
  - Resistance behavior (patrols, attacks, coordination).
  - Replication production (queue-based, continuous).
  - Assimilation spread (continuous visual effect).

- **Deliberate-Timing Elements (Protocols):**
  - **Swarm Rush:** Player issues command → units begin movement to target immediately → arrive within 3–5 seconds → attack for 10 seconds → command resolves → units resume autonomy.
  - **Rapid Replication:** Activate → production speed ×2 for 15 seconds → metal cost deducted upfront → command resolves.
  - **Scatter:** Activate → all units in range disperse 5m in random direction → occupy scattered positions for 8 seconds → resume autonomous behavior.
  - **Defensive Formation:** Activate → units move to holding positions near a designated point → hold for up to 30 seconds or until attacked → resume autonomy.
  - **Assimilation Wave:** Activate → all Assimilators push to advancing front → assimilate all structures in path (1 unit = 1 sacrificial assimilation) → command resolves when no more targets.

### Cooldown Model
- Most protocols have a **recharge cooldown** (e.g., Swarm Rush: 20 sec cooldown).
- **Rapid Replication** has an extended cooldown (45 sec) due to high cost.
- **Scatter** is low-cost, no cooldown (balances as a defensive panic button).
- Cooldowns are **per-player** in multiplayer (each player manages their own command timers).

---

## Turn-Based Concept: Not Applicable
Replicants is **not turn-based**. The real-time hybrid prevents turn structures. Protocols create deliberate pacing windows, but the core loop is continuous.

---

## Multiplayer Command Resolution

### Shared Metal Pool
- All players contribute to and draw from the same metal economy.
- Any player can issue replication commands (player A can queue a Soldier while player B queues a Harvester).
- **Queue Resolution:** Commands are processed in timestamp order (FIFO). If metal is insufficient for a queued command, it waits until sufficient metal is available.

### Protocol Command Conflicts
- **Scenario:** Player A issues Swarm Rush to location X; Player B issues Scatter.
- **Resolution:** First command (by timestamp) takes priority. Second command is queued or rejected (depends on design intent).
- **Recommendation:** Use **signal broadcasting**—when Player A issues Swarm Rush, emit a signal that prevents conflicting commands for the duration (e.g., 3 seconds).

### Shared Objectives and Victory
- All players must cooperate to achieve assimilation %, zone control, and resistance neutralization.
- Victory/defeat is **shared** across all players. One player's defeat is the team's defeat.

### Multiplayer HUD Consistency
- Each player has an independent camera view.
- Shared minimap shows all swarm units and discovered resistance.
- Metal counter, unit roster, and protocol status are visible to all players.
- When a player issues a command, a UI indicator (name tag or icon) shows the issuing player.

---

## Victory and Defeat Conditions

### Victory
- **Primary:** Achieve assimilation objective (varies by state):
  - EARLY_COLONY: 20% assimilation.
  - EXPANSION: 50% assimilation.
  - RESISTANCE_SURGE: Neutralize all Commanders + maintain > 45% assimilation.
- **Secondary:** All designated resistance nodes neutralized (optional, state-dependent).
- **Tertiary:** Reach final facility zone (optional, state-dependent).
- **Narrative Trigger:** Swarm establishes dominance. Next chapter teased.

### Defeat
- **Primary:** All swarm units destroyed (swarm size = 0).
- **Secondary:** Colony core destroyed (if core is introduced as a late-game mechanic).
- **Tertiary:** Timer exhausted (state-specific maximum duration exceeded).
- **Tertiary (RESISTANCE_SURGE only):** Assimilation drops below 20% (facility reclaims control).
- **Narrative Trigger:** Facility containment holds. Swarm is purged (for now).

---

## Key Signals (GDScript Example)

```gdscript
# GameState.gd (Fictional example, adjust to actual architecture)

class_name MissionState
extends Node

signal state_changed(new_state: String)
signal victory_achieved()
signal defeat_triggered(reason: String)
signal escalation_triggered()

var current_state: String = "LOBBY"
var swarm_size: int = 0
var assimilation_percentage: float = 0.0
var resistance_count: int = 0

func _on_swarm_size_changed(new_size: int) -> void:
	swarm_size = new_size
	_check_escalation_trigger()
	_check_defeat_condition()

func _on_assimilation_changed(new_percentage: float) -> void:
	assimilation_percentage = new_percentage
	_check_escalation_trigger()
	_check_victory_condition()

func _check_escalation_trigger() -> void:
	if current_state == "EXPANSION":
		if swarm_size > 20 or assimilation_percentage > 0.30:
			current_state = "RESISTANCE_SURGE"
			escalation_triggered.emit()
			state_changed.emit("RESISTANCE_SURGE")

func _check_victory_condition() -> void:
	match current_state:
		"EARLY_COLONY":
			if assimilation_percentage >= 0.20 and swarm_size > 5:
				victory_achieved.emit()
				state_changed.emit("ASSIMILATION_COMPLETE")
		"EXPANSION":
			if assimilation_percentage >= 0.50:
				victory_achieved.emit()
				state_changed.emit("ASSIMILATION_COMPLETE")
		"RESISTANCE_SURGE":
			if resistance_count == 0 and assimilation_percentage > 0.45:
				victory_achieved.emit()
				state_changed.emit("ASSIMILATION_COMPLETE")

func _check_defeat_condition() -> void:
	if swarm_size == 0:
		defeat_triggered.emit("All swarm units destroyed")
		state_changed.emit("COLONY_DESTROYED")
```

---

## Implementation Notes

- **State Machine Pattern:** Use a centralized MissionState node that broadcasts state changes via signals.
- **Escalation Trigger:** ResistanceAISystem listens for escalation signals and spawns new resistance units.
- **Multiplayer Sync:** Ensure state changes are synchronized across all players (use GameManager or a custom network layer).
- **Difficulty Scaling:** Adjust resistance spawn rates, metal deposit sizes, and escalation thresholds per difficulty.
- **Testing:** Validate all state transitions and victory/defeat conditions in isolation before integration.

---

## State Transition Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        LOBBY                                 │
│                  (Player Setup)                              │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ↓ (Ready)
┌─────────────────────────────────────────────────────────────┐
│                      AWAKENING                               │
│              (Tutorial + First Contact)                      │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ↓ (Tutorial Complete)
┌─────────────────────────────────────────────────────────────┐
│                    EARLY_COLONY                              │
│              (Prove Harvest → Replicate)                     │
└────────┬──────────────────────────────────┬─────────────────┘
         │                                  │
    (Victory)                          (Defeat)
         │                                  │
         ↓                                  ↓
┌──────────────────────────┐    ┌───────────────────────────┐
│       EXPANSION          │    │  COLONY_DESTROYED         │
│  (Full Roster Unlocked)  │    │   (End Game)              │
└────────┬──────────────────┘    └───────────────────────────┘
         │
   (Escalation Trigger OR Victory)
         │
         ├─────────────────────────────┐
         │                             │
         ↓                         (Victory)
┌──────────────────────────┐          │
│   RESISTANCE_SURGE       │          │
│  (Facility Fights Back)  │          │
└────────┬──────────────────┘          │
         │                             │
    (Victory)                          │
         │                             │
         └──────────┬──────────────────┘
                    │
                    ↓
         ┌─────────────────────────────┐
         │ ASSIMILATION_COMPLETE       │
         │   (Victory End Game)         │
         └─────────────────────────────┘
```

