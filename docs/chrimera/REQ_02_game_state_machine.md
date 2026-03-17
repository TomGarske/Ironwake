# REQ-02: Game State Machine
**Chrimera: Bioforge Run**

## Overview
Chrimera manages state across two scopes: **run-level** (entire escape attempt from lobby to completion or failure) and **level-level** (within a single playable segment). This document defines the state transitions, entry/exit conditions, and key signals.

---

## Run-Level State Machine

```
LOBBY
  ↓ [readied_all_players]
RUN_START (initialize lives, select archetypes)
  ↓ [enter_first_level]
LEVEL_ENTER (load level, spawn entities, initialize tools)
  ↓ [all_players_spawned]
EXPLORING (players navigate, find tools, discover exit)
  ↓ [entity_triggers_encounter OR level_timer_triggers]
THREAT_ENCOUNTER (entity spawns, escalation events occur)
  ├─→ EXPLORING [encounter resolved, no lives lost]
  └─→ THREAT_ENCOUNTER [loop] [continued danger]
  ↓ [all_players_exit OR all_lives_depleted]
LEVEL_EXIT or RUN_FAILED
  ├─→ [next_level_exists] → LEVEL_ENTER
  └─→ [final_level_completed] → RUN_COMPLETE
  ↓
RESULTS (meta-progression applied, leaderboard posted)
  ↓
LOBBY
```

### State Definitions

| State | Entry Condition | Behavior | Exit Condition |
|-------|-----------------|----------|----------------|
| **LOBBY** | Game start or run complete | Main menu, player readiness check, archetype selection. No entities spawn. | All players ready + one player initiates run start. |
| **RUN_START** | Readied signal | Initialize shared lives pool (default: 3), assign archetypes, load first level data. | Level assets loaded. |
| **LEVEL_ENTER** | Load first/next level | Spawn LevelSegment (tilemap, entities, items). Players spawn at level entrance. Music cue. | All players spawned + level_ready signal. |
| **EXPLORING** | All players spawned | Level is passable; no forced encounters. Entities patrol/sleep. Players search for tools and exit. Contamination spreads passively. | Entity density threshold exceeded (trigger encounter) OR exit found and activated. |
| **THREAT_ENCOUNTER** | Entity density spike OR player detected by Lurker/Spreader | One or more entity types actively hunt players. Escalation music layer added. Players must defend/flee. | All entities neutralized (slain or fled) OR all players downed. |
| **LEVEL_EXIT** | All players reach exit trigger (Area2D contact) | Brief transition (0.5s fade). Removal of bodies, item cleanup. Tool/upgrade selection screen if not final level. | Selection confirmed or timeout (default upgrade selected). |
| **RUN_COMPLETE** | Exit from final level | Show run summary (time, kills, tool usage stats). Apply meta-progression unlocks. Post to SteamManager leaderboard. | Player acknowledges (Continue button). |
| **RUN_FAILED** | All lives exhausted while players are downed | Show death screen with stats. Meta-progression still applied. | Player acknowledges (Retry or Quit). |

---

## Level-Level Lifecycle

### Within-Level Transitions

```
Level spawned (EXPLORING state)
├─ [Tool found] → Player picks up, slot updates, cooldown display active
├─ [Entity spawned] → Enters patrol/hunt behavior (THREAT_ENCOUNTER escalation)
├─ [Contamination spreads] → Visual overlay increases, damage zone expands
├─ [Player downed] → Timer starts, revive prompt appears for teammates
│  ├─ [Revived within timer] → Player returns to EXPLORING
│  └─ [Timer expires] → Player dead, lives pool decrements
├─ [Exit activated by all players] → Level ends
└─ [All lives exhausted] → RUN_FAILED (hard stop)
```

### Escalation During Exploration
- **Phase 1 (first 60s):** Passive entity presence. Patrolling Crawlers. Low music intensity.
- **Phase 2 (60–120s):** Increased spawn rate. Lurkers appear. Music intensity +0.2.
- **Phase 3 (120s+):** Spreaders or Amalgams spawn. Contamination zones visible. Music intensity +0.4.
- **On player attack:** Immediate escalation to THREAT_ENCOUNTER regardless of phase.

---

## Death and Downed System

### Downed State
```gdscript
# Downed flow (pseudocode structure)
if player_health <= 0:
    player.state = "downed"
    player.revive_timer = 8.0  # seconds
    player.visible = true
    player.modulate.a = 0.6    # semi-transparent

    # Teammate proximity revive
    for teammate in nearby_teammates:
        if teammate.interact_pressed:
            player.revive()
            player.health = player.max_health * 0.5
            revive_timer = 0
            break

    revive_timer -= delta
    if revive_timer <= 0:
        player.is_dead = true
        lives_pool -= 1
        player_removed_from_level()
```

### Lives Pool Behavior
- **Initialization:** RunController initializes lives_pool = 3 (configurable per difficulty).
- **Shared:** All players draw from the same pool. One death decrements by 1.
- **Visibility:** HUD shows remaining lives. Low-life warning (red flash) at ≤1 life.
- **Depletion:** When lives_pool reaches 0 and a player dies, RUN_FAILED state triggered.

### Death vs. Downed
| State | Behavior | Revivable | Impact on Lives |
|-------|----------|-----------|-----------------|
| **Downed** | Incapacitated, semi-transparent, movement disabled. | Yes, by teammate proximity interaction (interact button within 2m for 1s). | No immediate impact; lives decrease only if timer expires. |
| **Dead** | Removed from run entirely. Body despawns after 3s. | No. | Lives pool decrements by 1. |

---

## Between-Level Moments

### Level Exit Screen (Non-Final)
After exiting a level (but not the final level), players see:
1. **Tool/Upgrade Selection Panel:** Three randomized options (each option contains either a new tool or an upgrade to an existing archetype ability).
2. **Lives Pool Display:** Current lives remaining.
3. **Run Stats:** Entities slain, tools used, damage taken.
4. **Respite Duration:** 15 seconds total. Music intensity drops. No entities spawn.
5. **Auto-Advance:** If no selection is made, default (first option) is selected.

```gdscript
# Pseudocode for upgrade selection
class UpgradeOption:
    var title: String
    var description: String
    var upgrade_type: Enum  # NEW_TOOL or ARCHETYPE_ABILITY
    var tool_or_ability: Resource

func display_upgrade_screen():
    var options = []
    for i in range(3):
        options.append(generate_random_upgrade())

    ui_panel.show_options(options)
    await ui_panel.option_selected
    apply_selected_upgrade()
    lives_pool.display_update()
```

---

## Meta-Progression State

### Persistent Between Runs
Meta-progression is stored in a file (or SteamManager user data) and persists across runs:
- **Unlocked Archetypes:** Scientists with bonus abilities unlocked.
- **Increased Lives Pool:** Higher default starting lives (unlocked via kills, run completions).
- **Additional Tool Slots:** Third tool slot unlocked after X successful runs.
- **Tool Availability:** New tools added to the random upgrade pool.

### Storage
```gdscript
# Pseudocode for persistence
class MetaProgressionState:
    var unlocked_archetypes: Array[String]  # ["Virologist", "Engineer", ...]
    var lives_pool_bonus: int  # increments with each milestone
    var tool_slot_count: int   # starts at 2, unlocks to 3
    var discovered_tools: Array[String]

    func save():
        var save_data = {
            "archetypes": unlocked_archetypes,
            "lives_bonus": lives_pool_bonus,
            "tool_slots": tool_slot_count,
            "tools": discovered_tools
        }
        FileAccess.open("user://chrimera_meta.save", FileAccess.WRITE).store_var(save_data)

    func load():
        var data = FileAccess.open("user://chrimera_meta.save", FileAccess.READ).get_var()
        unlocked_archetypes = data.get("archetypes", [])
        # ... etc
```

### Difficulty Scaling
- **Per-level entity density** is tied to player count and meta-progression unlocks.
- **Spreader spawn rate** increases with each level.
- **Escalation timeline** accelerates (Phase 1 ends at 45s on level 2, 30s on level 3, etc).

---

## Key Signals and Events

### RunController Signals
```gdscript
# In RunController class
signal run_started
signal level_started(level_number: int)
signal level_completed(level_number: int)
signal run_completed(total_time: float)
signal run_failed(reason: String)

signal lives_pool_changed(remaining: int)
signal player_downed(player_id: int)
signal player_revived(player_id: int)
signal player_dead(player_id: int)

signal escalation_triggered(phase: int)
signal contamination_level_changed(percentage: float)
```

### PlayerCharacter Signals
```gdscript
signal health_changed(new_health: int)
signal tool_slot_updated(slot: int, tool: ExperimentalTool)
signal state_changed(new_state: String)
signal interact_pressed()
```

### LevelSegment Signals
```gdscript
signal level_ready()
signal exit_activated()
signal entity_spawned(entity: CRISPREntity)
signal entity_killed(entity: CRISPREntity)
```

---

## Cooperative State Synchronization (Multiplayer)

In cooperative multiplayer (via SteamManager):
- **Run state** is authority of the host (RunController on host machine).
- **Player states** (position, health, tool slot) are replicated to all peers via peer_snapshot() every 0.1s.
- **Death events** (player_downed, player_dead) are broadcast to all peers immediately.
- **Lives pool** is read-only on clients; authoritative on host.

---

## Implementation Notes

1. **State Machine Pattern:** Use a simple enum-based state with guards to prevent invalid transitions.
2. **Signal Chaining:** level_completed signal triggers ui_show_upgrade_screen(), which emits option_selected; this is caught by RunController to advance state.
3. **Downed Timer:** Use a CountdownTimer node or manual delta tracking. Consider edge case: player downed while revive is in progress (revive is interrupted).
4. **Lives Display:** HUD listens to lives_pool_changed signal and updates visual (icon count or number).
5. **Contamination Spread:** Is a separate system (see REQ-07); state machine only tracks overall level contamination percentage for music scaling.

---

## Next Steps
- **REQ-03:** Player abilities and tools (tool resource class, slot management, synergies).
- **REQ-04:** Player movement and controls (input handling, physics integration).
