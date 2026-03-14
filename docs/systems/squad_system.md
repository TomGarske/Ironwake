# Squad System

**References:** [Game Philosophy](../design/game_philosophy.md) · [Combat System](combat_system.md) · [Turn System](turn_system.md)

---

## Overview

Each player commands a small squad of units — initially three to four — deployed on opposite sides of the tactical map. The squad is the player's entire presence in the match. Units are permanent: there is no reinforcement mechanic. Loss of any unit is a strategic setback; loss of all units ends the match.

Squad composition in the POC is fixed (identical units for both players). The squad system defines how units are structured, differentiated, and managed over the course of a match. It is the layer between the game state and the individual unit data model.

---

## Design Goals

- **Every unit is significant.** With a squad of 3–4, each loss reshapes the tactical situation. The system should never let a unit feel disposable.
- **Simple baseline, meaningful differentiation.** All units start on equal footing in the POC. Role differentiation (scout, support, heavy) is introduced in post-POC phases without breaking the base architecture.
- **Deterministic composition.** At match start, both players receive squads of defined composition. Squad setup is host-authoritative and replicated to both peers before the first turn begins.
- **Readable state.** Any piece of UI — selection panels, the overlay, the HUD — can query squad state from a single source of truth and produce accurate output.

---

## Core Mechanics

### Squad Composition (POC)

Both players start with three identical units:

| Slot | Type | HP | Move Range | Attack Range |
|------|------|----|-----------|--------------|
| 0 | Soldier | 2 | 3 | 4 (ranged) |
| 1 | Soldier | 2 | 3 | 4 (ranged) |
| 2 | Soldier | 2 | 3 | 4 (ranged) |

All three units share the same stats in the POC. The slot index is used to differentiate them within the squad.

### Unit Identification

Each unit is assigned a globally unique `unit_id` at match setup:

```
unit_id = (team_index * 10) + slot_index
```

- Team 0, Slot 0 → `unit_id = 0`
- Team 0, Slot 2 → `unit_id = 2`
- Team 1, Slot 0 → `unit_id = 10`
- Team 1, Slot 2 → `unit_id = 12`

This scheme is simple, collision-free for squads up to size 10, and human-readable in logs and debug output.

### Spawn Layout

Units spawn in a fixed formation at match start. The host places units at predefined grid positions and replicates initial positions to the client via the match setup RPC.

**Team 0 spawn zone**: top rows of the map  
**Team 1 spawn zone**: bottom rows of the map

Specific spawn coordinates are defined per-map, not in this system. The squad system provides the unit data; the map provides the positions.

### Unit Lifecycle

A unit moves through the following lifecycle states:

```
READY → MOVED → ATTACKED → EXHAUSTED
             ↑______________↑
             (any order; both transitions → EXHAUSTED)
```

- **READY**: No actions used this turn.
- **MOVED**: Move action used; attack action still available.
- **ATTACKED**: Attack action used; move action still available.
- **EXHAUSTED**: Both actions used, or turn ended by player.

At turn start (when the host broadcasts `turn_changed`), all units for the newly active player reset to **READY**.

### Death and Squad Size

When a unit's HP reaches 0, it is removed from the scene tree and unregistered from the squad. The squad's active unit count decreases by one. This is permanent for the match.

The `SquadManager` (or equivalent state in `TurnManager`) tracks the set of living unit IDs per team. The win condition query checks whether either team's set is empty.

---

## Data Structures

### Unit Data (per-unit fields)

```gdscript
# scripts/unit.gd
var unit_id: int
var team: int
var slot_index: int
var grid_pos: Vector2i
var health: int
var max_health: int
var move_range: int
var attack_range: int
var has_moved: bool
var has_attacked: bool
```

### Squad Registry (host-maintained, in TurnManager or GameManager)

```gdscript
# Keyed by unit_id
var squads: Dictionary = {
    0: [unit_id_0, unit_id_1, unit_id_2],  # Team 0
    1: [unit_id_10, unit_id_11, unit_id_12],  # Team 1
}
```

### Match Setup Payload (host → all peers at match start)

```gdscript
{
    squads: [
        # Team 0
        [
            { unit_id: 0, grid_pos: Vector2i(x, y), health: 2, ... },
            { unit_id: 1, grid_pos: Vector2i(x, y), health: 2, ... },
            { unit_id: 2, grid_pos: Vector2i(x, y), health: 2, ... },
        ],
        # Team 1
        [
            { unit_id: 10, grid_pos: Vector2i(x, y), health: 2, ... },
            { unit_id: 11, grid_pos: Vector2i(x, y), health: 2, ... },
            { unit_id: 12, grid_pos: Vector2i(x, y), health: 2, ... },
        ]
    ]
}
```

---

## Implementation Notes

- In the POC, squad setup is handled inline in `tactical_map.gd` during the `_ready()` call. A dedicated `SquadManager` autoload or sub-node should be introduced when role differentiation is added.
- The `unit_id` scheme is encoded into the spawning logic. Any change to squad size or team count must update the ID scheme and the match setup payload accordingly.
- Unit nodes are children of the tactical map scene. They are added during match setup and removed via `queue_free()` on death. All unit nodes are registered in the `TurnManager._unit_registry` dictionary.
- The client displays squad state (unit HP, action availability) by reading from local Unit nodes, which are updated in response to host RPCs. There is no separate "squad state" RPC; unit state flows through individual `apply_move`, `apply_attack`, and `unit_died` RPCs.

---

## Future Extensions

- **Role differentiation**: Scout (high move range, low HP), Soldier (balanced), Heavy (low move range, high HP, area attack). Roles are introduced by varying the stat block at squad setup.
- **Pre-match draft**: players select squad composition from a pool of roles before the match begins.
- **Asymmetric squads**: different squad sizes per team, balanced by role stat differences.
- **Abilities**: each role has one active ability with its own probability and outcome tiers, resolved through the RNG system.
- **Squad persistence**: squad composition and unit HP persist across multiple matches in a session (campaign mode).
