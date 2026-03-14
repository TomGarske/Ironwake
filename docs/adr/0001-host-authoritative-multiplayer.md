# ADR 0001: Host-Authoritative Multiplayer

**Status:** Accepted  
**Date:** 2025  
**References:** [Networking Model](../systems/networking_model.md)

---

## Context

BurnBridgers is a two-player real-time-over-turns tactical game distributed via Steam. The game requires:

- Contested state that both players influence (combat resolution, turn order, win conditions)
- Probability-based resolution that must produce identical results on both clients
- A distribution model that does not depend on a dedicated server (cost and operational complexity are unacceptable for an indie POC)
- Steam as the transport and social layer (friends list, lobby discovery, P2P relay)

The core challenge is **contested state with random resolution**: when a player attacks, the RNG outcome must be the same for both players. Without coordination, two independent RNG calls diverge immediately.

Three networking architectures were considered:

1. **Lockstep**: both clients simulate identically from a shared seed. Every input is delayed until both peers confirm receipt. Divergence causes desyncs that are catastrophic and hard to detect.
2. **Client-authoritative**: each player's client resolves actions on its own behalf. Results are broadcast to the other peer. This is simple but completely cheatable — any client can fabricate favorable outcomes.
3. **Host-authoritative**: one peer acts as the authoritative server. All action requests are validated and resolved by the host. Results are broadcast to all peers.

---

## Decision

**Adopt host-authoritative multiplayer using Godot's `MultiplayerAPI` over `SteamMultiplayerPeer`.**

One player (the lobby creator) acts as the match host. All contested state — action validation, RNG resolution, turn advancement, win conditions — runs exclusively on the host. Clients send `request_*` RPCs to the host; the host sends `apply_*` RPCs to all peers (including itself via `call_local`).

The host is not a "server" in the traditional sense: it is one of the two players running additional authority logic. Both players have equal visibility into match state; only the resolution path differs.

---

## Consequences

**Positive:**
- Correct contested state by construction. No client can observe a different outcome from a RNG resolution; the result is determined once on the host and transmitted.
- No dedicated infrastructure. Steam P2P (SDR) handles NAT traversal and relay without any server deployment.
- Simple to reason about. The authority boundary is clear: if it mutates game state, it runs on the host. If it renders or handles input, it runs client-local.
- Compatible with Godot's built-in `MultiplayerAPI` and `@rpc` annotations, which are designed for this authority model.
- Offline test mode is straightforward: both logical players share the host peer ID, and the same code paths run without modification.

**Negative:**
- The host player has a latency advantage for their own inputs: their actions resolve and apply locally without a round-trip. The client always waits for host confirmation. In a turn-based game with low action frequency, this is acceptable.
- If the host quits or crashes, the match ends for the client. There is no host migration. For a two-player game, this is equivalent to either player quitting, which ends the match regardless.
- The host must validate all incoming `request_*` RPCs defensively. Malformed or out-of-turn requests from the client must be rejected gracefully without corrupting host state.
- Scaling beyond 2 players adds complexity: the host validates all players' requests, which increases the authority logic burden. This is not a concern for the current 2-player design but must be considered if larger squad counts are introduced.
