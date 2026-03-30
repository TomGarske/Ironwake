# Ironwake

Ironwake is a Godot 4 multiplayer naval combat game. Command sailing warships — schooners, galleys, and brigs — through broadside engagements driven by physics-based sail, helm, and motion systems.

The project uses [GodotSteam](https://godotsteam.com/) for Steam lobbies and peer-to-peer multiplayer. One player hosts and acts as authority for match start and mode selection.

> **Status:** Active prototype. Core lobby, navigation, combat, AI (LimboAI behavior trees), scoreboard, and multiplayer sync are implemented. Polishing and balancing in progress.

---

## Gameplay

Three ship classes form the roster, each with a distinct combat role. All ships share the same state machine systems and differ through configuration values.

- **Schooner** — Fast attack and scouting. High speed, tight turning, light guns.
- **Galley** — Close-range control. Oar/sail hybrid with strong forward armament.
- **Brig** — Broadside powerhouse. Slow and heavy with devastating port and starboard batteries.

Ships are controlled through interconnected FSMs: Sail (propulsion), Helm (steering), Motion (physics integration), and Battery (cannon targeting, firing, reload). Damage feeds back into these systems — a damaged mast caps sail level, a broken rudder slows turning.

---

## Quickstart

See **[SETUP.md](SETUP.md)** for full setup instructions.

Short version:
1. Install [Godot 4.x](https://godotengine.org/download)
2. Download the GodotSteam GDExtension and extract it into `addons/godotsteam/`
3. Create `steam_appid.txt` at the project root containing `4530870` (Ironwake Playtest app ID) — the setup scripts do this automatically
4. Open the project in Godot (Steam running)
5. Press **F5** to run

---

## Play Flow

- **Open Operations** on the home screen to host a Steam lobby.
- In lobby, ready up and host launches the match.
- All players ready up, then host launches mission.
- **Solo Sim (Offline)** starts local testing with AI bots without Steam.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Engine | Godot 4.x (GDScript) |
| Multiplayer transport | GodotSteam GDExtension (`SteamMultiplayerPeer`) |
| Session model | Host-controlled lobby + mission flow |
| AI | LimboAI behavior trees (`res://ai/tasks/naval`) |
| Audio | Procedural synth with profile presets (`intensity`, `speed`, `tone`) |

---

## Repo Notes

- Main scene: `res://scenes/screens/home_screen.tscn`
- Lobby scene: `res://scenes/screens/lobby.tscn`
- Ironwake arena: `res://scenes/game/ironwake/ironwake_arena.tscn` (game mode ID: `"ironwake"`)
- Arena script: `scripts/game_modes/ironwake_arena.gd`
- Map profile: `scripts/shared/ironwake_map_profile.gd` (`class_name IronwakeMapProfile`)
- Mode metadata and routing: `scripts/autoload/game_manager.gd`
- Ship system architecture: `docs/req-master-architecture.md`

---

## Contributing

This repository uses feature-branch workflow:
- `main` stays stable; PRs target `main`
- Use short-lived branches like `feature/*` and `fix/*`

Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for submissions.
