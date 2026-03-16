# SHARED_01: BurnBridgers Shared Engine and Infrastructure

**Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active

---

## 1. Engine Foundation

### 1.1 Core Specifications

| Specification | Value | Notes |
|---|---|---|
| Engine | Godot 4.x | GDExtensions required for Steam & LimboAI |
| Primary Language | GDScript | Fully typed; see SHARED_02 |
| Renderer | Forward+ | Real-time 2D rendering, 1–60 FPS target |
| Player Count | 1–8 players | Scales dynamically; peer ordering for determinism |
| Network Model | Host Authority | Host controls match lifecycle, mode selection, phase transitions |
| Target Platforms | Windows, macOS, SteamOS, Web | Web via JavaScriptBridge (music only) |

### 1.2 Godot 4 Implementation Notes

All BurnBridgers games share a single Godot 4 project structure. Game-specific modes load as subscenes into a common framework controlled by autoload singletons.

**Physics & Movement:**
- CharacterBody2D for all dynamic entities
- _physics_process(delta) for movement updates
- Built-in collision layers: obstacles, walls, hurtboxes, hitboxes (see each game's REQ_06)

**Rendering:**
- 2D viewport with world camera following player or lead entity
- Sprite layers via CanvasLayer z-index
- Particles for effects; keep count <500 per frame

**Scene Loading:**
- All game modes loaded via GameManager.switch_game_mode()
- Scenes unload when mode changes (garbage collected)
- No persistent entities between matches

---

## 2. Autoload Singletons (Shared Across All Games)

### 2.1 GameManager

**Path:** `res://scripts/autoload/game_manager.gd`
**Persistence:** Global (survives scene loads)
**Responsibility:** Player registry, mode routing, phase control, music application

#### 2.1.1 Core Data Structure

```gdscript
class_name GameManager
extends Node

## Player registry: peer_id → player data
var players: Dictionary = {}  # peer_id: int → {"steam_id": int, "username": str, "team": int}

## Current game mode
var selected_game_mode: GameMode = GameMode.BLACKSITE_CONTAINMENT

## Match phase
enum MatchPhase { LOBBY, IN_MATCH, GAME_OVER }
var current_phase: MatchPhase = MatchPhase.LOBBY

## Signals
signal music_enabled_changed(enabled: bool)
signal selected_game_mode_changed(mode: GameMode)
signal music_profile_changed(profile: MusicProfile)
signal phase_changed(new_phase: MatchPhase)
signal player_joined(peer_id: int, player_data: Dictionary)
signal player_left(peer_id: int)

enum GameMode {
	BLACKSITE_CONTAINMENT,
	CHRIMERA,
	REPLICANTS,
	BLACKSITE_BREAKOUT
}
```

#### 2.1.2 Mode Switching with RPC

```gdscript
## Host calls this; broadcasts mode change to all peers
@rpc("authority", "call_local", "reliable")
func switch_game_mode(mode: GameMode) -> void:
	if not multiplayer.is_server():
		push_error("Only host can switch game mode")
		return

	selected_game_mode = mode
	current_phase = MatchPhase.LOBBY

	# Apply music profile
	var profile = _get_music_profile_for_mode(mode)
	MusicManager.apply_profile(profile)

	# Load game mode scene
	var scene_path = _get_scene_path_for_mode(mode)
	await get_tree().call_group_flags(SceneTree.GROUP_CALL_DEFAULT, "game_entities", "queue_free")
	get_tree().root.add_child(load(scene_path).instantiate())

	selected_game_mode_changed.emit(mode)
	music_profile_changed.emit(profile)
```

#### 2.1.3 Player Registry

```gdscript
## Register player when they join via SteamManager
func register_player(peer_id: int, steam_id: int, username: str, team: int = 0) -> void:
	players[peer_id] = {
		"steam_id": steam_id,
		"username": username,
		"team": team,
		"ready": false
	}
	player_joined.emit(peer_id, players[peer_id])

## Remove player when they leave
func unregister_player(peer_id: int) -> void:
	if peer_id in players:
		players.erase(peer_id)
		player_left.emit(peer_id)
```

#### 2.1.4 Match Phase Control

```gdscript
@rpc("authority", "call_local", "reliable")
func set_match_phase(new_phase: MatchPhase) -> void:
	if not multiplayer.is_server():
		return
	current_phase = new_phase
	phase_changed.emit(new_phase)
```

### 2.2 SteamManager

**Path:** `res://scripts/autoload/steam_manager.gd`
**Persistence:** Global
**Responsibility:** Steam P2P, lobby lifecycle, friend management, invite state machine

#### 2.2.1 Invite State Machine

```gdscript
class_name SteamManager
extends Node

enum InviteState { INVITED, ACCEPTED, JOINING, JOINED, FAILED }

var invite_state: Dictionary = {}  # peer_id → InviteState
var lobby_id: int = 0
var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
var invite_retry_count: Dictionary = {}  # peer_id → count
var invite_timeout: Dictionary = {}  # peer_id → Timer

signal lobby_created(lobby_id: int)
signal player_lobby_join_success(peer_id: int)
signal player_lobby_join_failed(peer_id: int, reason: String)
signal handshake_complete(peer_id: int)

const MAX_INVITE_RETRIES = 3
const INVITE_TIMEOUT_SEC = 30
```

#### 2.2.2 Lobby & P2P Setup

```gdscript
## Host: Create a Steam lobby for the match
func create_lobby() -> void:
	if Steam.steamID64() == 0:
		push_error("Steam not initialized; using offline mode")
		_setup_offline_mode()
		return

	peer = SteamMultiplayerPeer.new()
	peer.create_lobby(SteamMultiplayerPeer.LOBBY_TYPE_PUBLIC, 8)
	multiplayer.multiplayer_peer = peer

	lobby_created.emit(peer.get_lobby_id())
	print("Lobby created: %d" % peer.get_lobby_id())

## Client: Join existing lobby via invite
func join_lobby(lobby_id: int, inviter_peer_id: int) -> void:
	if not lobby_id:
		push_error("Invalid lobby_id")
		return

	invite_state[inviter_peer_id] = InviteState.ACCEPTED
	invite_retry_count[inviter_peer_id] = 0

	peer = SteamMultiplayerPeer.new()
	peer.join_lobby(lobby_id)
	multiplayer.multiplayer_peer = peer

	_start_invite_timeout(inviter_peer_id)
	print("Joining lobby %d..." % lobby_id)

## Handshake: confirm player fully joined
@rpc("any_peer", "reliable")
func confirm_handshake(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	invite_state[peer_id] = InviteState.JOINED
	_clear_invite_timeout(peer_id)
	handshake_complete.emit(peer_id)
	GameManager.register_player(peer_id, Steam.getPlayerSteamID(peer_id),
		Steam.getFriendPersonaName(Steam.getPlayerSteamID(peer_id)))
```

#### 2.2.3 Retry Logic & Timeout

```gdscript
func _start_invite_timeout(peer_id: int) -> void:
	if peer_id in invite_timeout:
		invite_timeout[peer_id].queue_free()

	var timer = Timer.new()
	add_child(timer)
	timer.one_shot = true
	timer.timeout.connect(_on_invite_timeout.bind(peer_id))
	timer.start(INVITE_TIMEOUT_SEC)
	invite_timeout[peer_id] = timer

func _on_invite_timeout(peer_id: int) -> void:
	if invite_retry_count[peer_id] < MAX_INVITE_RETRIES:
		invite_retry_count[peer_id] += 1
		print("Invite retry %d for peer %d" % [invite_retry_count[peer_id], peer_id])
		_start_invite_timeout(peer_id)
	else:
		invite_state[peer_id] = InviteState.FAILED
		player_lobby_join_failed.emit(peer_id, "Max retries exceeded")

func _clear_invite_timeout(peer_id: int) -> void:
	if peer_id in invite_timeout:
		invite_timeout[peer_id].queue_free()
		invite_timeout.erase(peer_id)
```

#### 2.2.4 Offline Test Mode (Solo Sim)

```gdscript
func _setup_offline_mode() -> void:
	## Simulates 2 local players for testing
	var peer = OfflineMultiplayerPeer.new()
	peer.add_peer(1)
	peer.add_peer(2)
	multiplayer.multiplayer_peer = peer

	GameManager.register_player(1, 123456, "LocalHost", 0)
	GameManager.register_player(2, 654321, "LocalClient", 0)

	print("Offline mode: Solo Sim (2 players)")
```

#### 2.2.5 Friend & Avatar Management

```gdscript
var friend_avatars: Dictionary = {}  # steam_id → Texture2D

func get_friend_avatar(steam_id: int) -> Texture2D:
	if steam_id not in friend_avatars:
		friend_avatars[steam_id] = Steam.getPlayerAvatar(steam_id)
	return friend_avatars[steam_id]

func get_lobby_members() -> Array:
	if lobby_id == 0:
		return []
	var members = []
	var count = Steam.getNumLobbyMembers(lobby_id)
	for i in range(count):
		members.append(Steam.getLobbyMemberByIndex(lobby_id, i))
	return members
```

### 2.3 GameConstants

**Path:** `res://scripts/autoload/game_constants.gd`

```gdscript
class_name GameConstants
extends Node

const MAX_PLAYERS: int = 8
const DEFAULT_PLAYER_TEAM: int = 0
```

### 2.4 MusicManager

**Path:** `res://addons/procedural_music/music_manager.gd`
**Persistence:** Global
**Responsibility:** Cross-platform music synthesis, phase seeking, volume control

#### 2.4.1 Core API

```gdscript
class_name MusicManager
extends Node

## Volume range 0.0 (mute) to 1.0 (full)
var volume: float = 0.8

## Music profile: intensity, speed, tone
class MusicProfile:
	var intensity: float
	var speed: float
	var tone: float
	func _init(p_intensity: float, p_speed: float, p_tone: float) -> void:
		intensity = p_intensity
		speed = p_speed
		tone = p_tone

## Available phases
enum Phase { INTRO, BUILD_1, CHORUS }

signal phase_changed(new_phase: Phase)
signal chord_changed(chord_root: String)

## AudioStreamPlayer for playback
var audio_player: AudioStreamPlayer = AudioStreamPlayer.new()
var current_profile: MusicProfile = MusicProfile.new(1.0, 1.0, 1.0)
var current_phase: Phase = Phase.INTRO
```

#### 2.4.2 Profile Application

```gdscript
func apply_profile(profile: MusicProfile) -> void:
	current_profile = profile

	# Adjust synthesis parameters based on profile
	_update_synth_intensity(profile.intensity)
	_update_synth_speed(profile.speed)
	_update_synth_tone(profile.tone)

	# Restart from intro phase
	seek_phase(Phase.INTRO)

func _update_synth_intensity(intensity: float) -> void:
	# Increase amplitude & harmonic richness
	# Implementation depends on synthesis backend
	pass

func _update_synth_speed(speed: float) -> void:
	# Adjust BPM and note timing
	pass

func _update_synth_tone(tone: float) -> void:
	# Shift fundamental frequency & filter cutoff
	pass
```

#### 2.4.3 Phase Seeking

```gdscript
func seek_phase(phase: Phase) -> void:
	current_phase = phase

	if OS.get_name() == "Web":
		_seek_phase_web(phase)
	else:
		_seek_phase_native(phase)

	phase_changed.emit(phase)

func _seek_phase_web(phase: Phase) -> void:
	# JavaScriptBridge call to web synth
	var phase_str = Phase.keys()[phase].to_lower()
	JavaScriptBridge.eval("window.musicPlayer.seekPhase('%s')" % phase_str)

func _seek_phase_native(phase: Phase) -> void:
	# Native engine synthesis: regenerate procedural audio
	# from phase offset; enqueue to audio_player
	pass

func set_volume(new_volume: float) -> void:
	volume = clamp(new_volume, 0.0, 1.0)
	audio_player.volume_db = linear2db(volume)
```

---

## 3. Music Profile System

Each game mode has a **music profile** applied when GameManager switches modes. Profiles modulate the shared procedural music synthesis.

### 3.1 Music Profile Definitions

| Game Mode | Intensity | Speed | Tone | Mood |
|---|---|---|---|---|
| Blacksite Containment | 1.05 | 0.95 | 0.96 | Steady tension |
| Chrimera | 1.20 | 1.15 | 1.08 | Chaotic energy |
| Replicants | 0.92 | 0.88 | 0.90 | Introspective dread |
| Blacksite Breakout | 1.30 | 1.12 | 1.15 | Frantic escape |

### 3.2 Profile Application Flow

```gdscript
## In GameManager.switch_game_mode():
var profile = _get_music_profile_for_mode(mode)
MusicManager.apply_profile(profile)

func _get_music_profile_for_mode(mode: GameMode) -> MusicManager.MusicProfile:
	match mode:
		GameMode.BLACKSITE_CONTAINMENT:
			return MusicManager.MusicProfile.new(1.05, 0.95, 0.96)
		GameMode.CHRIMERA:
			return MusicManager.MusicProfile.new(1.20, 1.15, 1.08)
		GameMode.REPLICANTS:
			return MusicManager.MusicProfile.new(0.92, 0.88, 0.90)
		GameMode.BLACKSITE_BREAKOUT:
			return MusicManager.MusicProfile.new(1.30, 1.12, 1.15)
		_:
			return MusicManager.MusicProfile.new(1.0, 1.0, 1.0)
```

---

## 4. Steam / Multiplayer Infrastructure

### 4.1 GodotSteam GDExtension

**Source:** [GodotSteam GitHub](https://github.com/Gramps/GodotSteam)
**Integration:** SteamMultiplayerPeer for P2P via lobbies
**Installation:** Downloaded by setup scripts (see § 8.2)

### 4.2 RPC Semantics

BurnBridgers follows strict RPC patterns for deterministic, reliable multiplayer:

#### 4.2.1 Host-to-All Broadcast (Authoritative Events)

```gdscript
@rpc("authority", "call_local", "reliable")
func broadcast_event(data: Dictionary) -> void:
	# Only host can call this
	# Executes on host + all connected clients
	# Reliable delivery (TCP-like)
	process_event(data)
```

**Use cases:** Match phase changes, player joins, mode switches, round results

#### 4.2.2 Client State Streaming (Unreliable, Frequent Updates)

```gdscript
@rpc("any_peer", "unreliable")
func update_position(new_pos: Vector2) -> void:
	# Any peer can call
	# May drop frames if network congested
	# Suitable for position/velocity (resent every frame)
	position = new_pos
```

**Use cases:** Player movement, animation states, aim direction

#### 4.2.3 Query (Any Peer, Awaited Response)

```gdscript
@rpc("any_peer", "reliable")
func query_game_state() -> Dictionary:
	return {
		"phase": GameManager.current_phase,
		"players": GameManager.players.size()
	}
```

### 4.3 Peer Ordering for Determinism

```gdscript
func get_sorted_peers() -> Array:
	var peers = []
	for peer_id in multiplayer.get_peers():
		peers.append(peer_id)
	peers.sort()
	return peers
```

Use `get_sorted_peers()` when iteration order matters (entity spawn order, action tiebreaks).

### 4.4 Ready State in Lobby

Ready state is stored in Steam SDK lobby member data:

```gdscript
## Host polls ready state before starting match
func check_all_players_ready() -> bool:
	for peer_id in GameManager.players:
		var steam_id = GameManager.players[peer_id]["steam_id"]
		var ready_str = Steam.getLobbyMemberData(lobby_id, steam_id, "ready")
		if ready_str != "true":
			return false
	return true

## Client: Set ready in lobby metadata
func set_player_ready(ready: bool) -> void:
	Steam.setLobbyMemberData("ready", "true" if ready else "false")
```

### 4.5 Offline Test Mode

**Solo Sim** simulates 2 local players without Steam:

```gdscript
## In SteamManager._setup_offline_mode():
var peer = OfflineMultiplayerPeer.new()
peer.add_peer(1)  # Host
peer.add_peer(2)  # Client
multiplayer.multiplayer_peer = peer

# Both players can be controlled from single Godot instance for debugging
```

---

## 5. UI Theme & Navigation

### 5.1 Visual Theme

**Palette:**
- **Dark Background:** RGB(20, 20, 25)
- **Orange Accent:** RGB(255, 140, 60)
- **Bronze Accent:** RGB(200, 120, 60)
- **Text (Primary):** RGB(240, 240, 245)
- **Text (Secondary):** RGB(180, 180, 185)

**Typography:**
- **Headers:** Roboto Bold, 32px (home) / 24px (in-game)
- **Body:** Roboto Regular, 14px
- **Monospace (status):** JetBrains Mono, 12px

### 5.2 Controller Navigation

All menus navigate via:
- **D-Pad / Left Stick:** Move between options (4-directional)
- **A (Gamepad Button South):** Confirm
- **B (Gamepad Button East):** Back
- **X (Gamepad Button West):** Toggle ready / alt action
- **Y (Gamepad Button North):** Info / help

### 5.3 Home Screen

**Scene Path:** `HOME_SCREEN_SCENE_PATH = res://scenes/screens/home_screen.tscn`

**Layout:**
```
┌─────────────────────────────────┐
│        BURNBRIDGERS v1.0.1a     │
│        (commit: a3f2e1c)        │
├─────────────────────────────────┤
│  ► Host New Match               │
│    Test (Offline)               │
│    Globe (Friends)              │
│    Settings                     │
├─────────────────────────────────┤
│  Pro Tip: Configure your team   │
│           in Settings           │
└─────────────────────────────────┘
```

**Actions:**
- **Host New Match:** Create Steam lobby → Lobby screen
- **Test:** Enter offline Solo Sim → Lobby screen (2 local players)
- **Globe:** Browse friends, send/receive invites
- **Settings:** Adjust audio, graphics, controls, name

### 5.4 Lobby Screen

**Scene Path:** `LOBBY_SCENE_PATH = res://scenes/screens/lobby.tscn`

**Layout:**
```
┌────────────────────────────────────────┐
│  LOBBY: Blacksite Containment          │
├────────────────────────────────────────┤
│  FIRETEAM                               │
│  ► Command Lead (You)         [READY✓] │
│    Operative (steam_user_42)  [READY✓] │
│    Operative (ai_bot_1)       [ ... ]  │
│                                        │
│  GAME MODE (Host Only)                 │
│  ► Blacksite Containment               │
│    Chrimera                             │
│    Replicants                           │
│    Blacksite Breakout                   │
│                                        │
│  ONLINE FRIENDS                        │
│  free_agent_steve    [ INVITE ]        │
│  cryptid_hunter_jess [ INVITED ]       │
│                                        │
│  ► Ready (X)         [ START ] (Host)  │
└────────────────────────────────────────┘
```

**Fireteam Status:**
- **Command Lead:** Match host; controls mode, starts match
- **Operative:** Client; marked ready/unready

**Player List:**
- Name + ready checkbox (toggle with X)
- Steam avatar image (cached via SteamManager.get_friend_avatar)

**Game Mode Selector (Host Only):**
- D-Pad up/down to cycle modes
- A to select → applies music profile immediately

**Start Button (Host Only, Greyed Until All Ready):**
- Calls `GameManager.switch_game_mode()` + sets phase to IN_MATCH
- Loads game mode scene

**Version Label:**
- Bottom right: "v1.0.1a (a3f2e1c)" — git commit hash auto-populated at build

---

## 6. Scene Paths

Shared constants defined in GameManager or a dedicated config autoload:

```gdscript
const HOME_SCREEN_SCENE_PATH: String = "res://scenes/screens/home_screen.tscn"
const LOBBY_SCENE_PATH: String = "res://scenes/screens/lobby.tscn"

## Per-game landing scenes (defined in each game's REQ_01):
# BLACKSITE_CONTAINMENT_SCENE_PATH = "res://scenes/game/blacksite_containment/level_select.tscn"
# CHRIMERA_SCENE_PATH = "res://scenes/game/chrimera/arena.tscn"
# REPLICANTS_SCENE_PATH = "res://scenes/game/replicants/base_scene.tscn"
# BLACKSITE_BREAKOUT_SCENE_PATH = "res://scenes/game/blacksite_breakout/prison.tscn"
```

---

## 7. LimboAI Integration (Shared)

### 7.1 LimboAI GDExtension

**Source:** [LimboAI GitHub](https://github.com/limbonaut/limbo_ai)
**Integration:** Behavior trees for all AI entities
**Installation:** Downloaded by setup scripts

### 7.2 Shared Behavior Tree Structure

All game modes use LimboAI for NPC/enemy AI:

```gdscript
## Every AI entity has a BTPlayer node
class_name AIEntity
extends CharacterBody2D

@onready var behavior_tree: BTPlayer = $BTPlayer

func _ready() -> void:
	behavior_tree.behavior_tree = load("res://scenes/ai/trees/[game_mode]/entity_ai.tres")
	behavior_tree.set_blackboard_var("owner", self)
	behavior_tree.set_blackboard_var("velocity", velocity)
```

### 7.3 LimboHSM for State Machines

Each agent can have a per-entity state machine via LimboHSM:

```gdscript
@onready var state_machine: LimboHSM = $HSM

func _ready() -> void:
	state_machine.add_state("idle", LimboState.new())
	state_machine.add_state("chase", LimboState.new())
	state_machine.add_state("dead", LimboState.new())

	state_machine.get_state("idle").physics_process.connect(_on_idle_physics_process)
	state_machine.set_initial_state(state_machine.get_state("idle"))
	state_machine.initialize()
```

### 7.4 Blackboard System

Shared data per agent via blackboard:

```gdscript
## In behavior tree action node:
var blackboard = behavior_tree.blackboard
blackboard.set_var("target_position", Vector2(100, 50))
blackboard.set_var("alert_level", 0.8)
var owner = blackboard.get_var("owner") as Node
```

### 7.5 Per-Game Behavior Trees

Each game defines its own behavior trees in:

```
res://scenes/ai/trees/[game_mode]/
  ├── entity_ai.tres (main behavior tree)
  ├── chase_subtree.tres
  ├── patrol_subtree.tres
  └── ...
```

See each game's **REQ_06** for specific behavior tree structures and available tasks.

---

## 8. Addon Requirements & Setup

### 8.1 External Addons (GDExtensions)

These are **not** in the repository; download scripts handle installation:

| Addon | Purpose | Source |
|---|---|---|
| GodotSteam | Steam P2P networking | [GodotSteam Releases](https://github.com/Gramps/GodotSteam/releases) |
| LimboAI | Behavior trees + FSM | [LimboAI Releases](https://github.com/limbonaut/limbo_ai/releases) |

### 8.2 Setup Scripts

Run once after cloning the repository:

| Platform | Script | Command |
|---|---|---|
| macOS | `setup-mac.sh` | `bash setup-mac.sh` |
| SteamOS / Linux | `setup-steamos.sh` | `bash setup-steamos.sh` |
| Windows | `setup-windows.ps1` | `powershell -ExecutionPolicy Bypass -File setup-windows.ps1` |

**What they do:**
1. Download GodotSteam GDExtension (matching Godot 4.x version)
2. Download LimboAI GDExtension
3. Extract into `addons/`
4. Create `steam_appid.txt`

### 8.3 Steam App ID

**File:** `steam_appid.txt` (root of project, git-ignored)

| Context | App ID | Notes |
|---|---|---|
| Playtest | `4530870` | **Fireteam MNG Playtest** — use during development & playtesting |
| Main app | *(TBD)* | Update when main app is live on Steam |

The setup scripts write this file automatically. Replace manually if you need a different context.

---

## 9. Git Protocol

**From CLAUDE.md:**

### 9.1 Branch Model

- **main:** Production-ready, always deployable
- **feature/\*:** New features (e.g., `feature/music-profiles`)
- **fix/\*:** Bug fixes (e.g., `fix/steam-peer-ordering`)
- **hotfix/\*:** Urgent production fixes

### 9.2 Protection & Review

- **main** is protected; all changes require:
  - Dedicated feature/fix branch
  - Pull request with description
  - Code review approval from 1+ team member
  - CI/CD checks passing (if configured)

### 9.3 Merge Conflict Resolution

When conflicts arise during integration:

1. Create a dedicated `integrate/[feature-name]` branch
2. Merge both sides (feature + main) into it
3. Resolve conflicts **preserving behavior from both sides**
4. Test thoroughly in this branch
5. Merge integrate/ back to main
6. Delete feature branch

Example:
```bash
git checkout -b integrate/music-profiles
git merge origin/feature/music-profiles
git merge origin/main
# Resolve conflicts, preserving both music profile changes & other main updates
git commit -m "Integrate feature/music-profiles with latest main"
git checkout main
git merge integrate/music-profiles
```

---

## 10. Summary Table

| Component | Responsibility | Autoload | Path |
|---|---|---|---|
| **GameManager** | Mode routing, player registry, phase control, music application | Yes | `res://scripts/autoload/game_manager.gd` |
| **SteamManager** | Lobbies, P2P, invites, handshake | Yes | `res://scripts/autoload/steam_manager.gd` |
| **GameConstants** | Global constants (MAX_PLAYERS) | Yes | `res://scripts/autoload/game_constants.gd` |
| **MusicManager** | Procedural synthesis, profile application, phase seeking | Yes | `res://addons/procedural_music/music_manager.gd` |
| **GodotSteam** | Steam SDK bindings | GDExtension | `addons/godotsteam/` |
| **LimboAI** | Behavior trees, state machines, blackboard | GDExtension | `addons/limboai/` |

---

## 11. Quick Reference: Adding a New Game Mode

1. **Define mode enum** in GameManager:
   ```gdscript
   enum GameMode { ..., MY_NEW_MODE }
   ```

2. **Add scene path constant** in GameManager:
   ```gdscript
   const MY_NEW_MODE_SCENE_PATH: String = "res://scenes/game/my_new_mode/main.tscn"
   ```

3. **Add music profile** in `_get_music_profile_for_mode()`:
   ```gdscript
   GameMode.MY_NEW_MODE:
       return MusicManager.MusicProfile.new(1.0, 1.0, 1.0)
   ```

4. **Add RPC handler** (if needed):
   ```gdscript
   @rpc("authority", "call_local", "reliable")
   func on_my_new_mode_started() -> void:
       print("Mode started!")
   ```

5. **Create behavior trees** in `res://scenes/ai/trees/my_new_mode/`

6. **Document in game-specific REQ_01**

---

**End of SHARED_01**
