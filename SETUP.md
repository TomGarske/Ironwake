# FireTeam MNG — Developer Setup

## Prerequisites
- [Godot Engine 4.x](https://godotengine.org/download) installed
- [Steam](https://store.steampowered.com/) installed and logged in
- A Steam account (free tier is sufficient for testing)
- Git + GitHub access

## 1. Clone the Repository
```
git clone https://github.com/TomGarske/BurnBridgers.git
cd BurnBridgers
```

## 2. Install Addons (Required — not in repo)
Addon binaries (GodotSteam, LimboAI) are **not committed** to this repository due to their size and binary nature.

The easiest way to install them is with the setup scripts:
- **macOS:** `./setup-mac.sh`
- **Linux / SteamOS:** `./setup-steamos.sh`
- **Windows:** `.\setup-windows.ps1`

The scripts read versions from `addons/addons.cfg` and download both plugins automatically.

### Manual installation
If you prefer to install manually:

**GodotSteam:**
1. Visit: https://codeberg.org/godotsteam/godotsteam/releases
2. Download the **GDExtension** archive matching your Godot Engine version.
3. Extract into `addons/godotsteam/` at the project root.

**LimboAI (Behavior Trees & State Machines):**
1. Visit: https://github.com/limbonaut/limboai/releases
2. Download the **GDExtension** zip for your Godot version (e.g. `limboai+v1.7.0.gdextension-4.6.zip`).
3. Extract into the project root — files land in `addons/limboai/`.

Both `addons/godotsteam/` and `addons/limboai/` are git-ignored — each developer must do this step.

## 3. Create steam_appid.txt
Create a file named `steam_appid.txt` at the project root containing just the app ID:
```
480
```
App ID `480` is Valve's **SpaceWar** test app, used for local development. Replace with your real Steam App ID when registered via the Steamworks Developer portal.

This file is git-ignored and must never be committed.

## 4. Open in Godot
1. Launch Godot Engine
2. Open the project by selecting the `BurnBridgers/` folder (or `project.godot` directly)
3. Godot will import assets on first open — this is normal
4. The GodotSteam extension should load automatically (no plugin enable step needed for GDExtension)

## 5. Run & Test
- **Steam must be running** before launching the game
- Press **F5** (Run Project) in Godot
- To test multiplayer: run two separate exports, or use two machines on the same LAN logged into Steam

