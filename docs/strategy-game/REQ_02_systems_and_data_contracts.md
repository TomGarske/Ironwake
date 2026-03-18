# Strategy Game: Systems and Data Contracts

## Systems Overview

### 1) Hex Grid State

Tracks per-cell terrain and derived map semantics.

Expected contract:

- Stable coordinate keying per hex cell.
- Deterministic terrain lookup and mutation.
- Clear defaults for unassigned cells.

### 2) Terrain Editing Surface

Provides map editing controls for selecting cells and applying terrain types.

Expected contract:

- UI selection state is decoupled from authoritative map state.
- Terrain id chosen in UI maps to a valid terrain definition key.
- Invalid terrain ids are rejected safely.

### 3) Terrain Definitions Registry

Central source of available terrain ids and presentation metadata.

Expected contract:

- Terrain ids are unique and stable.
- Runtime consumers can enumerate terrain definitions.
- Registry emits update notifications when definitions change.

### 4) Multiplayer Turn + Presence HUD

Defines who acts now and provides visible peer presence in strategy mode.

Expected contract:

- Turn state is host-authoritative.
- Turn roster includes host peer id plus connected peer ids in stable sorted order.
- The active turn peer id must always exist in the roster; if a peer disconnects, host reassigns to the next valid peer.
- Client gameplay actions that mutate strategic state are rejected when the sender is not the active turn peer.
- HUD displays:
  - local peer role (`You`),
  - at least one remote peer as `Other Player` when connected,
  - explicit active-turn marker (`[TURN]`),
  - a local-turn indicator (`It's your turn` vs waiting text).

Network payload contract:

- `apply_turn_state(current_turn_peer_id: int, turn_order: Array[int])`
  - `current_turn_peer_id`: active peer id for this turn.
  - `turn_order`: host-computed ordered roster of active peer ids.
  - delivery: reliable, authority -> all peers.

## Data Contract Requirements

When changing strategy data structures, document:

- Key names and value types.
- Ownership (local UI cache vs authoritative state).
- Default/fallback behavior.
- Serialization expectations for save/network transport.

## Change Checklist

For any strategy-system update:

1. Confirm docs match new runtime symbols and payloads.
2. Verify mode routing still points to strategy scene.
3. Validate terrain edit flow from UI selection to map application.
4. Re-check multiplayer behavior for host/client state authority.
