# FireTeam MNG

FireTeam MNG is a Godot 4 sci-fi multiplayer prototype currently focused on **Blacksite Containment**.  
Gameplay is currently **PVE** and supports **1 to max players**.

The project uses [GodotSteam](https://godotsteam.com/) for Steam lobbies and peer-to-peer multiplayer. One player hosts and acts as authority for match start and mode selection.

> **Status:** Active prototype. Core lobby + Blacksite routing are implemented; gameplay systems are in progress.

---

## Current Game Mode

- **Blacksite Containment**  
  Floating drone defense mode with a directional charge laser, orbital strikes, burst speed, and framerate-control perception.
Detailed mode docs live in `docs/blacksite-containment/`.

---

## Quickstart

See **[SETUP.md](SETUP.md)** for full setup instructions.

Short version:
1. Install [Godot 4.x](https://godotengine.org/download)
2. Download the GodotSteam GDExtension and extract it into `addons/godotsteam/`
3. Create `steam_appid.txt` at the project root containing `4530870` (Fireteam MNG Playtest app ID) — the setup scripts do this automatically
4. Open the project in Godot (Steam running)
5. Press **F5** to run

---

## Play Flow

- **Open Operations** on the home screen to host a Steam lobby.
- In lobby, ready up for the **Blacksite Containment** mission.
- All players ready up, then host launches mission.
- **Solo Sim (Offline)** starts local testing without Steam.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Engine | Godot 4.x (GDScript) |
| Multiplayer transport | GodotSteam GDExtension (`SteamMultiplayerPeer`) |
| Session model | Host-controlled lobby + Blacksite mission flow |
| Audio | Procedural synth with Blacksite profile presets (`intensity`, `speed`, `tone`) |

---

## Repo Notes

- Main scene: `res://scenes/screens/home_screen.tscn`
- Lobby scene: `res://scenes/screens/lobby.tscn`
- Blacksite Containment scene: `res://scenes/game/blacksite/blacksite_containment_arena.tscn`
- Mode metadata and routing: `scripts/autoload/game_manager.gd`

---

## Contributing

This repository uses feature-branch workflow:
- `main` stays stable; PRs target `main`
- Use short-lived branches like `feature/*` and `fix/*`

Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for submissions.
