# Ironwake

Ironwake is a Godot 4 multiplayer naval combat game set in the age of sail. Command a 74-gun third-rate warship (modeled on HMS Bellona) through broadside engagements driven by physics-based sail, helm, and motion systems with historically grounded ballistics.

The project uses [GodotSteam](https://godotsteam.com/) for Steam lobbies and peer-to-peer multiplayer. One player hosts and acts as authority for match start, hit detection, ramming, and respawn.

> **Status:** Active prototype. Core lobby, navigation, combat, AI (LimboAI behavior trees), component damage, scoreboard, and multiplayer sync are implemented. Polishing and balancing in progress.

---

## Gameplay

Ships are controlled through interconnected FSMs:

- **Sail** — Stepped propulsion (Stop / Quarter / Half / Full). Raise rate ~6.5s, lower rate ~3s. Max speed 13 knots.
- **Helm** — Mechanical wheel → tiller → rudder chain with inertia. Wheel lock holds course.
- **Motion** — Physics integration: speed from sail level, turning bleeds speed, passive drag.
- **Battery** — Port and starboard broadsides. Elevation -3° to +5° with realistic ballistic trajectories. Salvo or ripple fire modes. 12-second reload.

**Component damage** feeds back into ship performance:
- **Rigging hits** (upper hull) shred sails — reduces speed cap and slows sail deployment.
- **Helm hits** (waterline) damage the rudder — slows rudder response and limits max deflection.
- **Ramming** damages the helm on collision.

Zoom is locked to the farthest active battery's ballistic range. Both batteries are active on spawn.

---

## Quickstart

See **[SETUP.md](SETUP.md)** for full setup instructions.

Short version:
1. Install [Godot 4.6+](https://godotengine.org/download)
2. Run the platform setup script in `dev/` (or manually install GodotSteam GDExtension into `addons/godotsteam/`)
3. Open the project in Godot (Steam running)
4. Press **F5** to run

---

## Play Flow

- **Open Operations** on the home screen to host a Steam lobby.
- In lobby, ready up and host launches the match.
- **Solo Sim (Offline)** starts local testing with AI bots (no Steam required).
- **Tab** opens the scoreboard (kills, deaths, shots, accuracy, damage).
- **Local MP testing:** `dev/test-multiplayer-local.sh` or `dev/test-multiplayer-local.ps1` (`GODOT_EXE` or `PATH`) launches two side-by-side Godot windows.

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
