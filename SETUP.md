# Ironwake — Developer Setup

## Prerequisites
- [Godot Engine 4.6+](https://godotengine.org/download) installed
- [Steam](https://store.steampowered.com/) installed and logged in
- A Steam account (free tier is sufficient for testing)
- Git + GitHub access

## 1. Clone the Repository
```
git clone https://github.com/TomGarske/BurnBridgers.git
cd BurnBridgers
```

## 2. Install Addons (Required — not in repo)
Addon binaries (GodotSteam) are **not committed** to this repository due to their size and binary nature.

The easiest way to install them is with the platform setup scripts in `dev/`:
- **macOS:** `./dev/setup-mac.sh`
- **Linux / SteamOS:** `./dev/setup-steamos.sh`
- **Windows:** `.\dev\setup-windows.ps1`

> **Note:** You must open the project in Godot at least once before running a setup script so that `.godot/extension_list.cfg` is generated.

The scripts inline version config (GodotSteam 4.17.1) and derive addon paths from `.godot/extension_list.cfg`.

### Manual installation
If you prefer to install manually:

**GodotSteam:**
1. Visit: https://codeberg.org/godotsteam/godotsteam/releases
2. Download the **GDExtension** archive matching your Godot Engine version (4.4+ plugin).
3. Extract into `addons/godotsteam/` at the project root.

`addons/godotsteam/` is git-ignored — each developer must do this step.

## 3. Create steam_appid.txt
The setup scripts create this file automatically. It lives at the project root and contains the Steam App ID.

For playtesting use the **Ironwake Playtest** app ID:
```
4530870
```

This file is git-ignored and must never be committed.

## 4. Open in Godot
1. Launch Godot Engine
2. Open the project by selecting the `BurnBridgers/` folder (or `project.godot` directly)
3. Godot will import assets on first open — this is normal
4. The GodotSteam extension should load automatically (no plugin enable step needed for GDExtension)

## 5. Run & Test
- **Steam must be running** before launching the game
- Press **F5** (Run Project) in Godot
- **Solo Sim** mode on the home screen runs offline Fleet Battle (no Steam required)
- **Local multiplayer testing:** `./dev/test-multiplayer-local.sh` (Unix) or `dev/test-multiplayer-local.ps1` (Windows; set `GODOT_EXE` or `PATH`). Host in the left window, join from the right.
- **Automated smoke / Cursor MCP:** see `tests/cursor_mcp_qa.txt` (game flow, naval systems, fleet systems, offline bootstraps).
- **Remote multiplayer:** run two separate exports on different machines on the same LAN, both logged into Steam

## 6. Project Structure

| Path | Description |
|------|-------------|
| `scenes/screens/home_screen.tscn` | Main menu |
| `scenes/screens/lobby.tscn` | Multiplayer lobby |
| `scenes/game/ironwake/ironwake_arena.tscn` | Naval duel arena |
| `scenes/game/ironwake/ironwake_fleet_arena.tscn` | Fleet Battle (PVE) arena |
| `scripts/game_modes/ironwake_arena.gd` | Arena logic (~3000 lines) |
| `scripts/shared/` | Ship systems: sail, helm, battery, motion, ballistics |
| `scripts/autoload/game_manager.gd` | Match flow and mode routing |
| `ai/tasks/naval/` | LimboAI behavior tree tasks for bot AI |
| `docs/` | Requirement specs and architecture docs |
| `dev/` | Setup scripts and test harnesses |

