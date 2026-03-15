# FireTeam MNG

FireTeam MNG is a Godot 4 sci-fi multiplayer prototype with selectable mission profiles.  
Every mode is currently **PVE** and supports **1 to max players**.

The project uses [GodotSteam](https://godotsteam.com/) for Steam lobbies and peer-to-peer multiplayer. One player hosts and acts as authority for match start and mode selection.

> **Status:** Active prototype. Core lobby + mode routing is implemented; gameplay systems are in-progress per mode.

---

## Current Game Modes

- **Blacksite Containment** (`Blacksite Border Patrol`)  
  Floating drone defense mode: front laser, side shotguns, orbital strike support, and burst speed interception.
- **Chrimera** (`Bioforge Run`)  
  Side-scroller roguelike escape concept.
- **Replicants** (`Swarm Command`)  
  Strategy expansion and replication concept.
- **Blacksite Breakout** (`Escape from Area 51`)  
  Tactical escape concept with procedural map goals.

Detailed concept docs live in `docs/game-info/`.

---

## Quickstart

See **[SETUP.md](SETUP.md)** for full setup instructions.

Short version:
1. Install [Godot 4.x](https://godotengine.org/download)
2. Download the GodotSteam GDExtension and extract it into `addons/godotsteam/`
3. Create `steam_appid.txt` at the project root containing `480` (Valve's SpaceWar test app ID)
4. Open the project in Godot (Steam running)
5. Press **F5** to run

---

## Play Flow

- **Open Operations** in main menu to host a Steam lobby.
- In lobby, choose a **Mission Profile** (game mode).
- All players ready up, then host launches mission.
- **Solo Sim (Offline)** starts local testing without Steam.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Engine | Godot 4.x (GDScript) |
| Multiplayer transport | GodotSteam GDExtension (`SteamMultiplayerPeer`) |
| Session model | Host-controlled lobby + mode selection |
| Audio | Procedural synth with mode-specific presets (`intensity`, `speed`, `tone`) |

---

## Repo Notes

- Main scene: `res://scenes/screens/main_menu.tscn`
- Lobby scene: `res://scenes/screens/lobby.tscn`
- Blacksite Containment scene: `res://scenes/game/blacksite/blacksite_containment_arena.tscn`
- Legacy arena scene (untouched): `res://scenes/game/iso_arena.tscn`
- Mode metadata and routing: `scripts/autoload/game_manager.gd`

---

## Contributing

This repository uses feature-branch workflow:
- `main` stays stable; PRs target `main`
- Use short-lived branches like `feature/*` and `fix/*`

Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for submissions.
