# BurnBridgers — Developer Setup

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

## 2. Install the GodotSteam Plugin (Required — not in repo)
GodotSteam binaries are **not committed** to this repository due to their size and binary nature.

1. Visit: https://codeberg.org/godotsteam/godotsteam/releases
2. Download the **GDExtension** zip matching your Godot Engine version:
   - Godot 4.4+: use the latest `GodotSteam-gdextension-plugin-4.x.zip`
   - Godot 4.1–4.3: use the legacy version linked on the releases page
3. Extract the zip contents into `addons/godotsteam/` at the project root:
   ```
   BurnBridgers/
   └── addons/
       └── godotsteam/
           ├── godotsteam.gdextension
           ├── win64/
           │   └── godotsteam.dll
           └── ...
   ```
4. The `addons/godotsteam/` directory is git-ignored — each developer must do this step.

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

## Project Structure
See `PLAN.md` for the full architecture overview.
