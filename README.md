# BurnBridgers

A 2-player turn-based squad tactics game built in Godot 4. Two players control small squads of units on a tile grid, taking turns moving and attacking. Combat resolves through a tiered outcome system — no binary hit/miss — where positioning and coordination shift the probability of success.

Built with [GodotSteam](https://godotsteam.com/) for Steam lobbies and peer-to-peer multiplayer. One player hosts; the host is authoritative for all game state. No dedicated server required.

> **Status:** POC — core networked gameplay loop is playable. Art, abilities, and full combat resolution are in progress.

---

## Quickstart

See **[SETUP.md](SETUP.md)** for full setup instructions, including the required GodotSteam plugin step.

Short version:
1. Install [Godot 4.x](https://godotengine.org/download)
2. Download the GodotSteam GDExtension and extract it into `addons/godotsteam/`
3. Create `steam_appid.txt` at the project root containing `480` (Valve's SpaceWar test app ID)
4. Open the project in Godot — Steam must be running
5. Press **F5** to run

### Offline / No-Steam Testing

The main menu includes a **Test (Offline)** button that skips Steam entirely and loads a local two-player session. Both sides are controlled by the same keyboard/mouse. Useful for testing game logic without a second machine.

### Debug Logging (Steam/Lobby Issues)

Use the project launcher in debug mode to auto-capture runtime errors:

```powershell
.\run.ps1 -Mode debug
```

This runs Godot with verbose console output and writes logs to:

`logs/godot-debug-<timestamp>.log`

Share the latest log file when host/join fails so issues can be diagnosed quickly.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Engine | Godot 4.x (GDScript) |
| Multiplayer transport | GodotSteam GDExtension — Steam P2P via `SteamMultiplayerPeer` |
| Authority model | Host-authoritative — host validates all actions, broadcasts results via RPC |
| Grid | Discrete tile grid, 10×10, Manhattan-distance movement and attack |

---

## Project Layout

```
scripts/
  autoload/         # SteamManager, GameManager (global singletons)
  tactical_map.gd   # Core game loop: input, unit selection, RPC dispatch
  turn_manager.gd   # Turn sequencing and win condition
  unit.gd           # Unit data, movement/attack validation, drawing
  overlay.gd        # Grid highlights (selection, move range, attack range)
  lobby.gd          # Lobby screen (player list, start button)
  main_menu.gd      # Main menu (host/join/test buttons)
scenes/             # Godot scene files corresponding to each script
docs/
  design/           # Game philosophy and player experience principles
  systems/          # Detailed specs: combat, RNG, turns, squads, networking
  adr/              # Architecture Decision Records
```

See [docs/design/game_philosophy.md](docs/design/game_philosophy.md) for the core design principles, and [docs/systems/](docs/systems/) for detailed system specifications.

---

## Contributing

This repository uses [gitflow](https://nvie.com/posts/a-successful-git-branching-model/):
- `main` — stable releases only
- `develop` — integration branch; all feature PRs merge here
- `feature/*`, `fix/*`, `adr/*` — short-lived branches off `develop`

Architecture decisions are documented as ADRs in `docs/adr/`. Read [AGENTS.md](AGENTS.md) for the ADR governance policy (applies to human contributors too, not just AI agents).

PRs to `develop` or `main` must fill in the [PR template](.github/PULL_REQUEST_TEMPLATE.md) — the CI gate will fail otherwise.
