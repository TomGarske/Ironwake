# Networking Model

**References:** [Turn System](turn_system.md) · [Combat System](combat_system.md)

---

## Overview

BurnBridgers uses a host-authoritative peer-to-peer networking model built on Steam's P2P transport layer via GodotSteam. One player acts as the match host and runs all authoritative game logic. The other player is a client: they submit action requests to the host, which validates and resolves them, then broadcasts the results to all peers.

This model is the simplest architecture that correctly handles contested state (combat resolution, turn advancement) without a dedicated server. It is appropriate for a two-player game where one player is always present as the host.

See ADR [0001-host-authoritative-multiplayer](../adr/0001-host-authoritative-multiplayer.md) for the rationale behind this choice.

---

## Design Goals

- **Single source of truth.** The host owns all game state. Clients never resolve contested actions locally. This eliminates desync from concurrent conflicting inputs.
- **No dedicated server.** Steam P2P keeps the game self-hosted and avoids ongoing server infrastructure costs for a small-scale game.
- **Minimal client prediction.** Clients display the result of actions only after receiving confirmation from the host. Latency tolerance is achieved through clear turn-based sequencing, not client-side speculation.
- **Graceful offline fallback.** The offline test mode runs the same code path as a real networked match, with both logical players sharing the host peer ID. This keeps test mode behavior representative of real networked play.
- **Deterministic over network.** No floating-point divergence between peers. The host resolves all probabilistic outcomes and transmits results as discrete integers, not floats.

---

## Core Mechanics

### Topology

```
[Player A (Host)]  ←→  Steam P2P  ←→  [Player B (Client)]
```

All game RPCs flow through Steam's relay network (SDR) unless direct connectivity is established. The host creates the Steam lobby; the client joins via lobby ID.

Godot's `MultiplayerAPI` is configured with `SteamMultiplayerPeer` as the transport. All `@rpc` annotations use this peer.

### Authority Model

| Layer | Authority |
|-------|-----------|
| Lobby creation/join | Steam (via `SteamManager`) |
| Match setup (unit spawn positions, squad data) | Host |
| Action validation (move legality, attack validity) | Host |
| Combat resolution (RNG, outcome tier) | Host |
| Turn advancement | Host |
| Win condition | Host |
| Rendering, UI, input | Client-local |

Clients are responsible only for reading input and sending `request_*` RPCs to the host. All decisions and state mutations originate on the host and are applied on all peers via `apply_*` RPCs.

### RPC Flow for an Action

The request/apply pattern is used for all game actions:

```
Client                              Host
  │                                   │
  │── request_move(unit_id, pos) ───→ │
  │                                   │ validate (legal tile, correct turn, correct player)
  │                                   │ apply mutation to host state
  │ ←── apply_move(unit_id, pos) ────→│ broadcast to all peers (including self)
  │                                   │
```

The `apply_*` RPC is sent with `@rpc("authority", "call_local", "reliable")`, meaning it executes on the host (via `call_local`) and on all connected clients via the multicast. Both peers update their local state in response to the same RPC.

### Reliability and Ordering

All game-state RPCs use Godot's `reliable` channel, which guarantees delivery and ordering. This is appropriate for a turn-based game where action throughput is low and correctness is more important than latency.

High-frequency cosmetic updates (hover highlights, cursor position) may use `unreliable` in future phases.

### Steam Lobby Flow

```
Host: Steam.createLobby()
  → lobby_created signal → SteamManager stores lobby_id
  → Host sets lobby data (game name, version)

Client: Steam.joinLobby(lobby_id)
  → lobby_joined signal → SteamManager creates SteamMultiplayerPeer
  → Godot MultiplayerAPI peer_connected fires on Host
  → Host begins match setup
```

Match setup is triggered on the host when `peer_connected` fires and the lobby reaches the expected player count (2).

### Offline Test Mode

When `GameManager.setup_offline_test()` is called:
- No Steam connection is established.
- `GameManager.players` is populated with two synthetic player entries sharing the host's peer ID.
- Turn advancement uses `force_advance_turn()` in `TurnManager`, which bypasses the peer ID validation check.
- All other game logic runs identically to a real networked match.

Offline mode is a development tool only. It must not be shipped as a user-facing feature without additional safety guards.

---

## Data Structures

### Player Entry (in GameManager)

```gdscript
# Stored in GameManager.players: Array[Dictionary]
{
    steam_id:    int,    # Steam64 ID (0 in offline mode)
    peer_id:     int,    # Godot multiplayer peer ID
    player_index: int,  # 0 or 1 (match-scoped)
    display_name: String,
}
```

### RPC Annotations (pattern used throughout)

```gdscript
# Client → Host (action request)
@rpc("any_peer", "reliable")
func request_move(unit_id: int, target_pos: Vector2i) -> void:
    # Only executes on host; others silently ignored
    if not multiplayer.is_server(): return
    ...

# Host → All peers (state update)
@rpc("authority", "call_local", "reliable")
func apply_move(unit_id: int, target_pos: Vector2i) -> void:
    # Executes on all peers including host
    ...
```

---

## Implementation Notes

- `SteamManager` (autoload) owns the Steam API lifecycle: initialization, lobby creation/join, peer setup. It emits `match_ready` when both peers are connected and the `SteamMultiplayerPeer` is assigned to `get_tree().get_multiplayer()`.
- `GameManager` (autoload) owns the player registry. It populates `players` from Steam lobby member data on the host, then replicates it to the client as part of match setup.
- `TurnManager` and `tactical_map.gd` contain all match-scoped RPC logic. They are scene-local (not autoloads) and are only active during a match.
- The host's peer ID in Godot's `MultiplayerAPI` is always `1`. All peers can check `multiplayer.is_server()` to determine host status.
- The Steam relay (SDR) means direct IP addresses are never exchanged. Steam handles NAT traversal and relay routing transparently.

---

## Future Extensions

- **Reconnection**: if a client disconnects mid-match, the host pauses the match and waits for reconnection for N seconds before declaring a forfeit.
- **Spectator support**: additional Steam lobby members receive `apply_*` broadcasts but cannot send `request_*` RPCs.
- **Match replay**: the host logs all `apply_*` events with timestamps. The log can be replayed deterministically using the same initial state and RNG seed.
- **Anti-cheat validation**: the host currently trusts that `request_*` RPCs come from the correct player. Stronger validation (rate limiting, state consistency checks) will be needed if the game scales beyond trusted P2P sessions.
- **Direct connect**: bypass Steam lobby for LAN play or developer testing with a configurable IP/port pair.
