# BurnBridgers — Godot 4 POC Setup Plan

## Goal
Scaffold the BurnBridgers repository so two players can: launch the game via Steam, enter a lobby, start a match, and take turns moving and attacking units on a tile grid. This is a technology-validation POC — minimal gameplay, maximum integration proof.

## Technology Stack
- **Engine:** Godot 4.x (GDScript)
- **Networking:** GodotSteam GDExtension plugin (Steam lobbies + P2P via `SteamMultiplayerPeer`)
- **Grid:** Godot `TileMap` node
- **Authority model:** Host-authoritative — host validates all actions and replicates state via RPCs
- **IDE:** Cursor | **Terminal:** Warp | **VCS:** GitHub (gitflow)

## Important Manual Steps
GodotSteam ships binary `.dll` / `.so` files that cannot be scripted into the repo.
1. Download the GDExtension zip for your Godot version from [codeberg.org/godotsteam/godotsteam/releases](https://codeberg.org/godotsteam/godotsteam/releases)
2. Extract contents into `addons/godotsteam/` inside the project root
3. Place `steam_appid.txt` (containing `480` for SpaceWar testing) at the project root
4. The `addons/godotsteam/` directory is git-ignored (binary blobs); `SETUP.md` documents this step

## Project Directory Structure
```
BurnBridgers/
├── project.godot             # Godot project config (autoloads declared here)
├── steam_appid.txt           # App ID 480 for dev/testing (git-ignored)
├── icon.svg                  # Placeholder project icon
├── .gitignore
├── PLAN.md                   # This file
├── SETUP.md                  # Manual setup instructions for GodotSteam
├── addons/
│   └── godotsteam/           # GDExtension binaries (git-ignored)
├── scenes/
│   ├── main_menu.tscn
│   ├── lobby.tscn
│   └── game/
│       ├── tactical_map.tscn
│       └── unit.tscn
├── scripts/
│   ├── autoload/
│   │   ├── steam_manager.gd  # Steam init, lobby create/join, P2P peer setup
│   │   └── game_manager.gd   # Global match state, player registry
│   ├── main_menu.gd
│   ├── lobby.gd
│   ├── tactical_map.gd
│   ├── turn_manager.gd       # Turn sequencing, action validation
│   └── unit.gd               # Unit data: health, move range, team, position
└── assets/
    ├── sprites/
    └── tilesets/
```

## Core Systems

### SteamManager (Autoload)
- Calls `Steam.steamInit()` on `_ready()`; quits gracefully if Steam is not running
- Exposes `host_lobby()` and `join_lobby(lobby_id)` methods
- On lobby join/host: creates `SteamMultiplayerPeer`, assigns to `multiplayer.multiplayer_peer`
- Calls `Steam.run_callbacks()` every `_process` tick
- Emits signals: `lobby_created`, `lobby_joined`, `peer_connected`, `peer_disconnected`

### GameManager (Autoload)
- Tracks player registry: `peer_id → { steam_id, username, team }`
- Stores match phase enum: `LOBBY`, `IN_MATCH`, `GAME_OVER`
- `register_player_rpc` — any-peer RPC so clients register themselves with the host
- Host calls `start_match()` once ready; fires `load_tactical_map` RPC to all peers

### MainMenu (`scenes/main_menu.tscn`)
- Three buttons: **Host**, **Join**, **Exit**
- Join reveals a `LineEdit` + Confirm button for entering lobby ID
- On lobby ready (created or joined) → navigate to `lobby.tscn`

### Lobby (`scenes/lobby.tscn`)
- Displays connected players pulled from Steam lobby member list
- Host sees **Start Match** button; enabled when ≥ 2 players present
- On start: `GameManager.start_match()` → RPC loads `tactical_map.tscn` on all clients

### TacticalMap (`scenes/game/tactical_map.tscn`)
- `TileMap` node, 10×20 grid, placeholder tileset
- Host spawns 2 units per player in the leftmost 2 columns
- Host also spawns NPC units in the rightmost 4 columns
- All spawns are broadcast via RPC
- Holds `TurnManager` as child node

### Unit (`scenes/game/unit.tscn`)
- Fields: `health: int`, `move_range: int`, `team: int`, `grid_pos: Vector2i`
- `can_move_to(target)` — checks `has_moved` and Manhattan distance ≤ `move_range`
- `can_attack(target_pos)` — checks `has_attacked` and Manhattan distance ≤ 1 (melee)
- `reset_actions()` called at turn start

### TurnManager (`scripts/turn_manager.gd`)
- Node inside `TacticalMap`
- Tracks `player_ids`, current turn index, current player
- All move/attack requests flow: client RPC → host validates → host broadcasts confirmed state
- `end_turn()` advances to next player via `_broadcast_turn_start` authority RPC
- Signals: `turn_started(player_id)`, `turn_ended(player_id)`, `match_over(winner_id)`

## Networking Model
- `SteamMultiplayerPeer` replaces Godot's default ENet peer
- Client sends: `request_move(unit_id, target_pos)`, `request_attack(attacker_id, target_id)`
- Host validates legality, then broadcasts confirmed `apply_move` / `apply_attack` to all
- Unit `health` and `grid_pos` are the only synchronized state for the POC
- `end_turn()` client → `request_end_turn` RPC → host `_advance_turn` → `_broadcast_turn_start` RPC to all

## Success Criteria (POC)
- Two players launch through Steam, create/join a lobby, and load the tactical map
- Both clients display the same unit positions
- Players alternate turns; only the active player can issue commands
- Move and attack actions replicate correctly to both clients
- One player's units reaching 0 HP ends the match
