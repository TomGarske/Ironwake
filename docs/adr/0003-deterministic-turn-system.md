# ADR 0003: Deterministic Turn System

**Status:** Accepted  
**Date:** 2025  
**References:** [Turn System](../systems/turn_system.md) · [Networking Model](../systems/networking_model.md)

---

## Context

BurnBridgers is a two-player squad tactics game that requires both players to agree at all times on whose turn it is, which units may act, and when the round ends. Turn management is a sequencing problem with the following constraints:

- Turn order must be unambiguous. If the two peers ever disagree about who is the active player, actions become invalid and state diverges.
- The system must integrate cleanly with the host-authoritative architecture (ADR 0001). The host is the authority on turn state; clients cannot self-advance.
- Interrupts (overwatch, reactions) may be needed in future phases. The system should not structurally prevent them.
- Turn advancement must be resilient to delayed or dropped `end_turn` requests.

Several turn ordering models were evaluated:

1. **Initiative-based ordering**: units act in initiative order interleaved between players (A1, B1, A2, B2, ...). Complex to synchronize; ambiguous state if a unit is killed out of order; requires significant host logic per-unit.
2. **Simultaneous action submission**: both players submit sealed action lists; plans are revealed and resolved together. Very high design complexity; not appropriate for a POC.
3. **Alternating player turns with all-unit action within a turn**: each player takes a complete turn (all their units act in any order), then yields to the opponent. Simple, unambiguous, and standard in the genre (XCOM, Into the Breach).

---

## Decision

**Implement alternating player turns: each player acts with all of their units in any order, then explicitly ends their turn. Round increments when both players have completed a turn.**

Turn state is owned entirely by the host's `TurnManager`. The canonical state is:
- `current_round: int`
- `active_player: int` (0 or 1)
- `has_moved / has_attacked` flags on each unit (reset per turn)

Clients send `request_end_turn` to the host. The host validates the caller, advances `active_player`, resets units for the incoming player, and broadcasts `turn_changed` to all peers. Clients update their display only in response to `turn_changed`; they never self-advance.

Turn state does not need to be replicated in full — it is reconstructed from the stream of `turn_changed` events, each of which carries `round_number` and `active_player`.

---

## Consequences

**Positive:**
- Completely deterministic from the host's perspective. The active player is always a single integer (0 or 1) derived from a simple alternation rule.
- No ambiguity. A client that receives `turn_changed(round=3, active_player=1)` knows exactly who acts next without any local computation.
- Resilient to client slowness. The host only advances the turn when it receives a valid `request_end_turn` from the correct peer. A client that is slow or temporarily disconnected does not advance the turn on anyone's behalf.
- Easy to debug. Turn history is a flat sequence of `(round, active_player)` pairs. Diagnosing desyncs requires only comparing this sequence between peers.
- Genre-standard. Players familiar with XCOM, Into the Breach, or Fire Emblem will immediately understand the alternating turn model.
- Compatible with future interrupt mechanics. An interrupt phase can be inserted between `request_end_turn` and the final `turn_changed` broadcast without changing the outer turn structure.

**Negative:**
- The active player waits while the opponent takes their entire turn. With 3–4 units per player, each turn may involve multiple move+attack actions. This wait time is unavoidable in the alternating model and must be managed through UI clarity (clear "opponent's turn" indication) and pacing decisions (turn time limits in future phases).
- No initiative variation in the current design. Both players always alternate: Player 0, Player 1, Player 0, etc. A mechanic that grants an extra turn or skips a turn requires special-casing the alternation logic.
- `force_advance_turn()` exists in the POC for offline test mode, where both logical players share the same peer ID. This bypass is a latent bug risk if not gated behind `GameManager.is_offline`. It must be removed or fully isolated before the networking layer is hardened.
- The "all units act freely within a turn" model means a skilled player can sequence their unit actions to maximize positioning before committing to attacks. This is intentional (it rewards skill) but means the turn order within a player's turn is as tactically significant as the turn order between players.
