extends Node

# ---------------------------------------------------------------------------
# Enums & Constants
# ---------------------------------------------------------------------------
# GAME_OVER is set when the match ends (currently only win/draw is handled via TurnManager signal).
# TODO: assign GAME_OVER in _on_match_over handler once end-match UI flow is implemented.
enum MatchPhase { LOBBY, IN_MATCH, GAME_OVER }
const MATCH_SCENE_PATH: String = "res://scenes/game/ironwake/ironwake_arena.tscn"
const IRONWAKE_SCENE_PATH: String = "res://scenes/game/ironwake/ironwake_arena.tscn"
const HOME_SCREEN_SCENE_PATH: String = "res://scenes/screens/home_screen.tscn"
const LOBBY_SCENE_PATH: String = "res://scenes/screens/lobby.tscn"
const DEFAULT_GAME_MODE_ID: String = "ironwake"
const DEFAULT_MUSIC_PROFILE: Dictionary = {
	"intensity": 1.0,
	"speed": 1.0,
	"tone": 1.0,
}
const MODE_MUSIC_PROFILES: Dictionary = {
	"ironwake": {"intensity": 1.05, "speed": 0.95, "tone": 0.96},
}
const GAME_MODES: Array[Dictionary] = [
	{
		"id": "ironwake",
		"label": "Ironwake",
		"subtitle": "Age of Sail Naval Combat",
		"badge": "[NAVAL]",
		"scene_path": IRONWAKE_SCENE_PATH,
		"description": "Command a 74-gun third-rate warship in age-of-sail naval combat. Helm, sail, and battery controls with realistic ballistics.",
		"enabled": true,
	},
]
# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
## Registry: peer_id (int) -> { steam_id: int, username: String, team: int }
var players: Dictionary = {}
var match_phase: MatchPhase = MatchPhase.LOBBY
var _next_team_id: int = 0
var music_enabled: bool = true
var selected_game_mode_id: String = DEFAULT_GAME_MODE_ID
var music_volume: float = 0.38
var sfx_volume: float = 0.45
var music_intensity: float = float(DEFAULT_MUSIC_PROFILE["intensity"])
var music_speed: float = float(DEFAULT_MUSIC_PROFILE["speed"])
var music_tone: float = float(DEFAULT_MUSIC_PROFILE["tone"])

signal music_enabled_changed(enabled: bool)
signal selected_game_mode_changed(mode_id: String)
signal audio_volume_changed(music_volume: float, sfx_volume: float)
signal music_profile_changed(intensity: float, speed: float, tone: float)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_apply_music_profile_for_mode(selected_game_mode_id, false)

func set_music_enabled(enabled: bool) -> void:
	if music_enabled == enabled:
		return
	music_enabled = enabled
	music_enabled_changed.emit(music_enabled)

func set_audio_volumes(next_music_volume: float, next_sfx_volume: float) -> void:
	var clamped_music: float = clampf(next_music_volume, 0.0, 1.0)
	var clamped_sfx: float = clampf(next_sfx_volume, 0.0, 1.0)
	if is_equal_approx(clamped_music, music_volume) and is_equal_approx(clamped_sfx, sfx_volume):
		return
	music_volume = clamped_music
	sfx_volume = clamped_sfx
	audio_volume_changed.emit(music_volume, sfx_volume)

func set_music_profile(intensity: float, speed: float, _tone: float) -> void:
	var next_intensity: float = clampf(intensity, 0.2, 2.0)
	var next_speed: float = clampf(speed, 0.3, 1.3)
	var next_tone: float = 1.0
	if is_equal_approx(next_intensity, music_intensity) and is_equal_approx(next_speed, music_speed) and is_equal_approx(next_tone, music_tone):
		return
	music_intensity = next_intensity
	music_speed = next_speed
	music_tone = next_tone
	music_profile_changed.emit(music_intensity, music_speed, music_tone)

func get_game_modes() -> Array[Dictionary]:
	return GAME_MODES.duplicate(true)

func get_game_mode(mode_id: String) -> Dictionary:
	for mode in GAME_MODES:
		if str(mode.get("id", "")) == mode_id:
			return mode.duplicate(true)
	return {}

func get_selected_game_mode() -> Dictionary:
	var selected: Dictionary = get_game_mode(selected_game_mode_id)
	if not selected.is_empty():
		return selected
	return get_game_mode(DEFAULT_GAME_MODE_ID)

func set_selected_game_mode(mode_id: String) -> void:
	if not _is_valid_game_mode_id(mode_id):
		push_warning("[GameManager] Invalid game mode '%s'." % mode_id)
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_apply_selected_game_mode.rpc(mode_id)

@rpc("authority", "call_local", "reliable")
func _apply_selected_game_mode(mode_id: String) -> void:
	if not _is_valid_game_mode_id(mode_id):
		return
	if selected_game_mode_id == mode_id:
		return
	selected_game_mode_id = mode_id
	_apply_music_profile_for_mode(selected_game_mode_id)
	selected_game_mode_changed.emit(selected_game_mode_id)

func _is_valid_game_mode_id(mode_id: String) -> bool:
	for mode in GAME_MODES:
		if str(mode.get("id", "")) == mode_id:
			return true
	return false

func _apply_music_profile_for_mode(mode_id: String, should_emit: bool = true) -> void:
	var profile: Dictionary = DEFAULT_MUSIC_PROFILE
	if MODE_MUSIC_PROFILES.has(mode_id):
		profile = MODE_MUSIC_PROFILES[mode_id]
	music_intensity = clampf(float(profile.get("intensity", 1.0)), 0.2, 2.0)
	music_speed = clampf(float(profile.get("speed", 1.0)), 0.3, 1.3)
	music_tone = 1.0
	if should_emit:
		music_profile_changed.emit(music_intensity, music_speed, music_tone)

func _ensure_controller_ui_actions() -> void:
	_ensure_joy_button_for_action("ui_up", JOY_BUTTON_DPAD_UP)
	_ensure_joy_button_for_action("ui_down", JOY_BUTTON_DPAD_DOWN)
	_ensure_joy_button_for_action("ui_left", JOY_BUTTON_DPAD_LEFT)
	_ensure_joy_button_for_action("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_ensure_joy_button_for_action("ui_accept", JOY_BUTTON_A)
	_ensure_joy_button_for_action("ui_cancel", JOY_BUTTON_B)
	_ensure_joy_motion_for_action("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_joy_motion_for_action("ui_right", JOY_AXIS_LEFT_X, 1.0)
	_ensure_joy_motion_for_action("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_ensure_joy_motion_for_action("ui_down", JOY_AXIS_LEFT_Y, 1.0)

func _ensure_joy_button_for_action(action: String, button_index: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button_index:
			return
	var button_event := InputEventJoypadButton.new()
	button_event.button_index = button_index
	InputMap.action_add_event(action, button_event)

func _ensure_joy_motion_for_action(action: String, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and is_equal_approx(event.axis_value, axis_value):
			return
	var motion_event := InputEventJoypadMotion.new()
	motion_event.axis = axis
	motion_event.axis_value = axis_value
	InputMap.action_add_event(action, motion_event)

# ---------------------------------------------------------------------------
# Player registration
# ---------------------------------------------------------------------------
## Any peer can call this; only the host processes it.
@rpc("any_peer", "call_local", "reliable")
func register_player_rpc(steam_id: int, username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_register_player(sender_id, steam_id, username)

func register_local_player(peer_id: int, steam_id: int, username: String) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_register_player(peer_id, steam_id, username)

func _register_player(peer_id: int, steam_id: int, username: String) -> void:
	if players.has(peer_id):
		return
	var team: int = _next_team_id
	_next_team_id += 1
	players[peer_id] = {
		"steam_id": steam_id,
		"username": username,
		"team": team
	}
	print("[GameManager] Registered player '%s' as team %d (peer %d)" % [username, team, peer_id])

# ---------------------------------------------------------------------------
# Match flow
# ---------------------------------------------------------------------------
func start_match() -> void:
	if not multiplayer.is_server():
		push_warning("[GameManager] start_match called on non-host — ignoring.")
		return
	if players.size() < 1:
		push_warning("[GameManager] Not enough players to start (%d registered, need at least 1)." % players.size())
		return
	if SteamManager.lobby_id != 0 and not SteamManager.are_all_lobby_members_ready():
		push_warning("[GameManager] Cannot start: not all lobby players are ready.")
		return

	var mode: Dictionary = get_selected_game_mode()
	var target_scene_path: String = str(mode.get("scene_path", MATCH_SCENE_PATH))
	if target_scene_path.is_empty():
		target_scene_path = MATCH_SCENE_PATH
	match_phase = MatchPhase.IN_MATCH
	print("[GameManager] Starting '%s' with %d players." % [str(mode.get("label", "Ironwake")), players.size()])
	_load_match_scene.rpc(target_scene_path)

@rpc("authority", "call_local", "reliable")
func _load_match_scene(scene_path: String = MATCH_SCENE_PATH) -> void:
	get_tree().change_scene_to_file(scene_path)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
func _on_peer_disconnected(peer_id: int) -> void:
	if players.has(peer_id):
		print("[GameManager] Player '%s' (peer %d) disconnected." % [players[peer_id]["username"], peer_id])
		players.erase(peer_id)

func reset() -> void:
	players.clear()
	match_phase = MatchPhase.LOBBY
	_next_team_id = 0
	if selected_game_mode_id != DEFAULT_GAME_MODE_ID:
		selected_game_mode_id = DEFAULT_GAME_MODE_ID
		_apply_music_profile_for_mode(selected_game_mode_id)
		selected_game_mode_changed.emit(selected_game_mode_id)

## Populates two local test players for offline development — no Steam required.
func setup_offline_test() -> void:
	players.clear()
	players[1] = {"steam_id": 0, "username": "Player 1 (Test)", "team": 0}
	players[2] = {"steam_id": 0, "username": "Player 2 (Test)", "team": 1}
	_next_team_id = 2
	selected_game_mode_id = DEFAULT_GAME_MODE_ID
	_apply_music_profile_for_mode(selected_game_mode_id)
	match_phase = MatchPhase.IN_MATCH
	print("[GameManager] Offline test mode: 2 players registered.")
