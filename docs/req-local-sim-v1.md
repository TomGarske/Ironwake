# Local Simulation — Bot Spawning Requirements

**Project:** Naval Game
**System:** Local Simulation Controller
**Engine:** Godot (GDScript)
**Date:** 2026-03-29
**Version:** 1.1

---

## 1. Purpose

This document specifies the local simulation mode for testing the naval combat prototype. It handles automatic spawning of **one or more** bot ships for offline play without multiplayer infrastructure.

**Dependencies:**
- `req-ai-naval-bot-v1.md` — bot controller and behavior tree
- `req-master-architecture.md` — ShipContext, controller architecture

---

## 2. Requirements

### 2.1 Core Behavior

When running in local simulation mode:

- Automatically spawn **N** bot enemy ships (default **N = 3**, tunable on the arena).
- Place bots at a **square formation** around the player (see §2.3).
- Keep opening positions outside immediate knife-fight range (distance governed by spawn range parameters).
- Orient each bot **toward the player** with a small random yaw jitter (not a fixed head-on line).
- Attach `NavalBotController` and LimboAI behavior tree to each bot.

### 2.2 Spawn Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `local_sim_bot_count` | `3` | `@export` on `blacksite_containment_arena.gd`, clamped **1–4** |
| `spawn_distance_min` / `spawn_distance_max` | `220` / `320` world units | On `LocalSimController`; used to set corner distance (see §2.3) |
| `local_sim_enabled` | `true` | `@export` on arena; when false, no bots spawn |

**Distance semantics:** Let `dist = (spawn_distance_min + spawn_distance_max) / 2`. Bots sit on corners of an **axis-aligned square** centered on the player with **half-side** `s = dist / √2`, so the **straight-line distance** from the player to each corner is approximately **`dist`**.

**Multiple bots:** Corner order is **(+,+), (−,+), (−,−), (+,−)** in world **X/Y**. With **three** bots, the first three corners are used; with **four**, all four corners are used.

### 2.3 Spawn Logic (Implementation)

- `LocalSimController.create_bot_entry(player_dict, bot_index)` computes world position from the square-corner rule above, then clamps to map bounds.
- **No** random radius or random bearing sector per bot (formation is deterministic aside from heading jitter).
- Each bot receives a unique negative `peer_id`, palette, and label.

### 2.4 Arena Integration

- Spawning runs only when **offline** (`not multiplayer.has_multiplayer_peer()`), `local_sim_enabled` is true, and at least one player exists in `_players`.
- Dummy offline P2 placeholders are removed before bots are appended.
- Each bot gets the same controller setup as the player (sail, helm, batteries, motion), with **initial sail at HALF** (see `req-sail-fsm.md` implementation note).

---

## 3. Isolation Requirement

Bot spawning logic must be isolated from future multiplayer logic.

### 3.1 Implementation

`LocalSimController.gd` is a **RefCounted** helper invoked by the arena:

- Only runs when `local_sim_enabled` is true (arena gate).
- Does not depend on networking APIs.
- Can be disabled without affecting multiplayer code paths.

### 3.2 Recommended Architecture

```text
Arena (blacksite_containment_arena)
├── LocalSimController.create_bot_entry(...) per bot
├── _init_bot_controllers per bot
├── BotShipAgent + NavalBotController per bot
└── _tick_bot per bot each frame
```

---

## 4. Tunable Parameters

Spawn distance endpoints and bot count are **`@export`** on the arena (`local_sim_bot_count`, `local_sim_enabled`). `LocalSimController` fields `spawn_distance_min` / `spawn_distance_max` are set from code when the sim instance is created (extend to `@export` on a resource if shared tuning is needed).

---

## 5. Out of Scope

- Multiplayer networking
- Bot difficulty selection (future phase)
- Respawning after destruction
