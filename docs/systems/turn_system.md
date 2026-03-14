# Turn System

**References:** [Game Philosophy](../design/game_philosophy.md) · [Networking Model](networking_model.md) · [Combat System](combat_system.md)

---

## Overview

BurnBridgers uses a round-based, alternating turn system. Each round consists of two turns — one per player. On a player's turn, they may act with each unit in their squad once before ending their turn and passing control to the opponent. Turn order is deterministic and consistent across the match, making it straightforward to synchronize over the network without conflict.

The turn system is the sequencing layer. It does not resolve actions — it determines who acts, in what order, and when the round ends.

---

## Design Goals

- **Deterministic order.** Turn sequencing must be identical on host and client at all times. There is no ambiguity about whose turn it is.
- **Simple and auditable.** A player always knows exactly when they will act next. The system favors clarity over exotic initiative mechanics.
- **Designed for small squads.** With 2–4 units per player, the entire turn cycle completes quickly. Long wait times between turns are a design failure.
- **Network-authoritative.** The host controls turn state. Clients cannot advance the turn; they can only submit actions that the host validates and, upon completion, trigger a turn advance.
- **Interruptible in the future.** The system should accommodate overwatch, reaction actions, and other interrupt mechanics in later phases without requiring a structural rethink.

---

## Core Mechanics

### Turn Phases

Each full round proceeds through the following phases:

```
Round Start
  └─ Player A Turn
       ├─ Action Phase (Player A acts with each unit, in any order)
       └─ End Turn (Player A submits end_turn)
  └─ Player B Turn
       ├─ Action Phase (Player B acts with each unit, in any order)
       └─ End Turn (Player B submits end_turn)
Round End (check win condition)
Repeat
```

### Turn State

The canonical turn state is maintained by the host's `TurnManager`. The state consists of:

- **Current round number** (starts at 1, increments each time both players have acted)
- **Active player index** (0 or 1, corresponding to Player A or Player B)
- **Units with remaining actions** (a set of unit IDs for the active player)

### Action Points

In the POC, each unit has two action points per turn:
- **Move action** (1 AP): move to a reachable tile within `move_range`
- **Attack action** (1 AP): attack an enemy unit in range

A unit that has used both actions is exhausted. When all units for the active player are exhausted, the player may still end their turn early or wait.

The host marks a unit exhausted after validating its actions. Clients display exhausted units with a visual indicator.

### End Turn

The active player ends their turn by sending an `end_turn` RPC to the host. The host:
1. Marks all remaining units for the active player as exhausted (cancels any unused APs).
2. Advances the active player index.
3. Resets all units for the new active player (clears `has_moved`, `has_attacked`).
4. Broadcasts `turn_changed` to all peers with the new active player index and round number.

If it is the start of Player A's turn again, the round number increments first.

### Win Condition Check

The host checks the win condition at the end of each round (after both players have acted). The match ends when one player has no units remaining. The host broadcasts `match_over` with the winner's player index.

Win condition can also trigger mid-turn if the last enemy unit is eliminated — the host checks after every `apply_attack` broadcast.

---

## Data Structures

### TurnManager State

```gdscript
# scripts/turn_manager.gd
var current_round: int         # Starts at 1
var active_player: int         # 0 or 1
var _unit_registry: Dictionary # unit_id → Unit node reference
```

### Turn Changed Event (broadcast to all peers)

```gdscript
{
    round_number:   int,    # Current round
    active_player:  int,    # 0 or 1
}
```

### End Turn RPC

```gdscript
# Called by the active player's client on the host
@rpc("any_peer", "reliable")
func request_end_turn() -> void
```

The host validates that the caller is the current active player before advancing.

---

## Implementation Notes

- `TurnManager` is a node in the tactical map scene. It is not an autoload — its lifecycle is tied to the match.
- In the current POC, `force_advance_turn()` exists to handle offline test mode where both "players" share the same peer ID. This should be removed or gated behind `GameManager.is_offline` before shipping.
- The host validates `request_end_turn` against `multiplayer.get_remote_sender_id()`. If the sender's peer ID does not match the active player's peer ID, the request is rejected silently.
- Turn state is reset by the host at match start: `current_round = 1`, `active_player = 0`, all units refreshed.
- All state transitions are broadcast via reliable RPCs. Clients never infer turn state — they only update in response to host broadcasts.

---

## Future Extensions

- **Per-unit initiative**: rather than "all units act, then end turn," each unit has an initiative value and acts in initiative order, interleaved between players.
- **Overwatch interrupts**: a unit in overwatch reacts during the opponent's turn. This requires an interrupt phase between individual unit actions.
- **Time limits**: a per-turn timer that auto-ends the turn if the player does not act within N seconds.
- **Simultaneous action planning**: both players submit action plans simultaneously; plans are revealed and resolved in parallel. This is a significant architectural shift but compatible with the deterministic resolution system.
- **Replay and undo**: logging each turn transition as an event supports future replay or undo-last-action features.
