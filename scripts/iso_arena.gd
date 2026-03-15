extends Node2D
const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

## Isometric arena — placeholder art, up to 8 players.
##
## Controls (every player, on their own machine):
##   Arrow keys: move · Space: attack · Escape: pause menu

# ── Isometric constants ────────────────────────────────────────────────────────
const TILE_W        := 64.0   # diamond width in screen pixels
const TILE_H        := 32.0   # diamond height in screen pixels
const CHUNK_SIZE    := 16     # tiles per chunk side
const RENDER_MARGIN := 2      # extra tile buffer outside visible screen edge
const _TERRAIN_DEEP := 0
const _TERRAIN_WATER := 1

# ── Palette ───────────────────────────────────────────────────────────────────
const _C_SKY := Color(0.06, 0.07, 0.12)

# Player palettes — [primary, highlight]
const _PALETTES: Array = [
	[Color(0.22, 0.46, 1.00), Color(0.65, 0.82, 1.00)],  # blue
	[Color(1.00, 0.18, 0.12), Color(1.00, 0.58, 0.42)],  # red
	[Color(0.14, 0.76, 0.32), Color(0.52, 1.00, 0.60)],  # green
	[Color(0.92, 0.72, 0.06), Color(1.00, 0.92, 0.44)],  # gold
	[Color(0.70, 0.22, 0.96), Color(0.88, 0.62, 1.00)],  # purple
	[Color(0.10, 0.80, 0.90), Color(0.50, 0.94, 1.00)],  # cyan
	[Color(0.96, 0.52, 0.08), Color(1.00, 0.78, 0.42)],  # orange
	[Color(0.76, 0.76, 0.80), Color(0.94, 0.94, 0.96)],  # silver
]

# ── Physics / combat ──────────────────────────────────────────────────────────
const SPEED      := 5.0    # world units / sec
const ATK_DUR    := 0.45
const HIT_START  := 0.30
const HIT_END    := 0.72
const ATK_RANGE  := 1.9    # world units
const DMG        := 25.0
const MAX_HP     := 100.0
const END_DELAY  := 3.0

# ── Input (single shared set — each peer only controls their own character) ────
const _KEYS    := {l = KEY_LEFT, r = KEY_RIGHT, u = KEY_UP, d = KEY_DOWN, a = KEY_SPACE}
const _ACTIONS := {left = "ia_l", right = "ia_r", up = "ia_u", down = "ia_d", atk = "ia_a"}
const TERRAIN_RENDERER_SCRIPT := preload("res://scripts/shared/iso_terrain_renderer.gd")

# ── State ─────────────────────────────────────────────────────────────────────
@onready var quit_game_button: Button = $UILayer/QuitGameButton
@onready var pause_backdrop: ColorRect = $UILayer/PauseBackdrop
@onready var pause_menu_panel: PanelContainer = $UILayer/PauseMenuPanel
@onready var pause_resume_button: Button = $UILayer/PauseMenuPanel/PauseMenuMargin/PauseMenuVBox/PauseResumeButton
@onready var pause_music_button: Button = $UILayer/PauseMenuPanel/PauseMenuMargin/PauseMenuVBox/PauseMusicButton
@onready var pause_quit_button: Button = $UILayer/PauseMenuPanel/PauseMenuMargin/PauseMenuVBox/PauseQuitButton
@onready var quit_confirm_dialog: ConfirmationDialog = $UILayer/QuitConfirmDialog
@onready var game_music_player: AudioStreamPlayer = $UILayer/GameMusicPlayer

var _players:   Array = []
var _my_index:  int   = 0    # which player in _players this peer controls
var _winner:    int   = -2   # -2 = playing, -1 = draw, 0+ = index of winner
var _end_timer: float = 0.0
var _origin:    Vector2      # screen position of world (0, 0) — updated each draw
var _status_messages: Array[Dictionary] = []
var _music_playback: AudioStreamGeneratorPlayback = null
var _music_phase: float = 0.0
var _music_bass_phase: float = 0.0
var _music_time: float = 0.0
var _terrain_renderer = TERRAIN_RENDERER_SCRIPT.new()
var _zoom: float = 1.0
const _ZOOM_MIN: float = 0.001
const _ZOOM_MAX: float = 1.0
const _ZOOM_STEP: float = 0.1

# ── Spawn positions (world units) — populated by _load_geo_map() ──────────────
var _SPAWNS: Array = []

const _MUSIC_SAMPLE_RATE: float = 44100.0
const _MUSIC_STEP_SECONDS: float = 0.26
const _MUSIC_STEPS_PER_CHORD: int = 8
const _MUSIC_PROGRESS_ROOTS: Array[float] = [82.41, 69.30, 51.91, 55.00] # E, C#, G#, A
const _MUSIC_MELODY_BY_CHORD: Array[Array] = [
	[329.63, 369.99, 415.30, 493.88, 415.30, 369.99, 329.63, 369.99], # E
	[277.18, 329.63, 369.99, 415.30, 369.99, 329.63, 277.18, 329.63], # C#m
	[415.30, 369.99, 329.63, 369.99, 415.30, 493.88, 415.30, 369.99], # G#m
	[440.00, 415.30, 369.99, 329.63, 369.99, 415.30, 440.00, 369.99], # A
]
const _MUSIC_CHORD_TONES: Array[Array] = [
	[329.63, 415.30, 493.88], # E
	[277.18, 329.63, 415.30], # C#m
	[415.30, 493.88, 622.25], # G#m
	[440.00, 554.37, 659.25], # A
]
const _HUD_BG: Color = Color(0.10, 0.08, 0.07, 0.88)
const _HUD_BORDER: Color = Color(0.48, 0.35, 0.22, 0.90)
const _HUD_TEXT: Color = Color(0.95, 0.90, 0.83, 1.0)
const _HUD_TEXT_MUTED: Color = Color(0.79, 0.70, 0.60, 1.0)

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_register_inputs()
	_load_geo_map()
	_origin = get_viewport_rect().size * 0.5
	_spawn_players()
	_setup_game_music()
	if quit_game_button != null:
		quit_game_button.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if pause_backdrop != null:
		pause_backdrop.visible = false
	UiStyleScript.style_panel(pause_menu_panel)
	UiStyleScript.style_button(pause_resume_button)
	UiStyleScript.style_button(pause_music_button)
	UiStyleScript.style_button(pause_quit_button)
	if pause_resume_button != null and pause_music_button != null and pause_quit_button != null:
		pause_resume_button.focus_neighbor_bottom = pause_resume_button.get_path_to(pause_music_button)
		pause_music_button.focus_neighbor_top = pause_music_button.get_path_to(pause_resume_button)
		pause_music_button.focus_neighbor_bottom = pause_music_button.get_path_to(pause_quit_button)
		pause_quit_button.focus_neighbor_top = pause_quit_button.get_path_to(pause_music_button)
		pause_quit_button.focus_neighbor_bottom = pause_quit_button.get_path_to(pause_resume_button)
	if pause_resume_button != null and not pause_resume_button.pressed.is_connected(_on_pause_resume_pressed):
		pause_resume_button.pressed.connect(_on_pause_resume_pressed)
	if pause_music_button != null and not pause_music_button.pressed.is_connected(_on_pause_music_pressed):
		pause_music_button.pressed.connect(_on_pause_music_pressed)
	if pause_quit_button != null and not pause_quit_button.pressed.is_connected(_on_pause_quit_pressed):
		pause_quit_button.pressed.connect(_on_pause_quit_pressed)
	_update_pause_music_button_label()
	if quit_game_button != null and not quit_game_button.pressed.is_connected(_on_quit_game_button_pressed):
		quit_game_button.pressed.connect(_on_quit_game_button_pressed)
	if quit_confirm_dialog != null and not quit_confirm_dialog.confirmed.is_connected(_on_quit_confirmed):
		quit_confirm_dialog.confirmed.connect(_on_quit_confirmed)
	if quit_confirm_dialog != null:
		quit_confirm_dialog.title = "Leave Match"
		quit_confirm_dialog.ok_button_text = "Quit Match"
		_apply_quit_dialog_theme()
	if GameManager != null and not GameManager.music_enabled_changed.is_connected(_on_music_enabled_changed):
		GameManager.music_enabled_changed.connect(_on_music_enabled_changed)
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	queue_redraw()

func _exit_tree() -> void:
	if GameManager != null and GameManager.music_enabled_changed.is_connected(_on_music_enabled_changed):
		GameManager.music_enabled_changed.disconnect(_on_music_enabled_changed)
	if game_music_player != null:
		game_music_player.stop()
	_music_playback = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom + _ZOOM_STEP, _ZOOM_MIN, _ZOOM_MAX)
				queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom - _ZOOM_STEP, _ZOOM_MIN, _ZOOM_MAX)
				queue_redraw()

# ── Static map loader — all peers load the same committed asset ───────────────
func _load_geo_map() -> void:
	const MAP_PATH := "res://assets/maps/caribbean.json"
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		push_error("iso_arena: cannot open %s" % MAP_PATH)
		# Fallback: hardcoded spawns, noise path used if seed is set elsewhere
		_SPAWNS = [
			Vector2( 2.0,  2.0), Vector2(10.0, 10.0),
			Vector2(10.0,  2.0), Vector2( 2.0, 10.0),
			Vector2( 6.0,  2.0), Vector2( 6.0, 10.0),
			Vector2( 2.0,  6.0), Vector2(10.0,  6.0),
		]
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null:
		push_error("iso_arena: failed to parse caribbean.json")
		return
	_terrain_renderer.chunk_size = CHUNK_SIZE
	_terrain_renderer.load_static_map(parsed)
	_SPAWNS = []
	for sp in parsed["spawns"]:
		_SPAWNS.append(Vector2(float(sp[0]), float(sp[1])))

# ── Coordinate helpers ────────────────────────────────────────────────────────
func _w2s(wx: float, wy: float) -> Vector2:
	return _origin + Vector2((wx - wy) * TILE_W * _zoom * 0.5, (wx + wy) * TILE_H * _zoom * 0.5)

## Convert a world-space direction vector to a normalised screen-space direction.
func _dir_screen(dx: float, dy: float) -> Vector2:
	var v := Vector2((dx - dy) * TILE_W * _zoom * 0.5, (dx + dy) * TILE_H * _zoom * 0.5)
	return v.normalized() if v.length_squared() > 0.001 else Vector2.DOWN

# ── Input registration ────────────────────────────────────────────────────────
func _register_inputs() -> void:
	var pairs := {
		_ACTIONS.left:  _KEYS.l,
		_ACTIONS.right: _KEYS.r,
		_ACTIONS.up:    _KEYS.u,
		_ACTIONS.down:  _KEYS.d,
		_ACTIONS.atk:   _KEYS.a,
	}
	for action: String in pairs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		_ensure_key_for_action(action, pairs[action])
	_ensure_joy_motion_for_action(_ACTIONS.left, JOY_AXIS_LEFT_X, -1.0)
	_ensure_joy_motion_for_action(_ACTIONS.right, JOY_AXIS_LEFT_X, 1.0)
	_ensure_joy_motion_for_action(_ACTIONS.up, JOY_AXIS_LEFT_Y, -1.0)
	_ensure_joy_motion_for_action(_ACTIONS.down, JOY_AXIS_LEFT_Y, 1.0)
	_ensure_joy_button_for_action(_ACTIONS.left, JOY_BUTTON_DPAD_LEFT)
	_ensure_joy_button_for_action(_ACTIONS.right, JOY_BUTTON_DPAD_RIGHT)
	_ensure_joy_button_for_action(_ACTIONS.up, JOY_BUTTON_DPAD_UP)
	_ensure_joy_button_for_action(_ACTIONS.down, JOY_BUTTON_DPAD_DOWN)
	_ensure_joy_button_for_action(_ACTIONS.atk, JOY_BUTTON_A)
	_ensure_joy_button_for_action(_ACTIONS.atk, JOY_BUTTON_X)

func _ensure_key_for_action(action: String, keycode: Key) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.keycode == keycode:
			return
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)

func _ensure_joy_button_for_action(action: String, button_index: JoyButton, device: int = -1) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button_index and event.device == device:
			return
	var button_event := InputEventJoypadButton.new()
	button_event.button_index = button_index
	button_event.device = device
	InputMap.action_add_event(action, button_event)

func _ensure_joy_motion_for_action(action: String, axis: JoyAxis, axis_value: float, device: int = -1) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and is_equal_approx(event.axis_value, axis_value) and event.device == device:
			return
	var motion_event := InputEventJoypadMotion.new()
	motion_event.axis = axis
	motion_event.axis_value = axis_value
	motion_event.device = device
	InputMap.action_add_event(action, motion_event)

func _setup_game_music() -> void:
	if game_music_player == null:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = int(_MUSIC_SAMPLE_RATE)
	stream.buffer_length = 0.25
	game_music_player.stream = stream
	game_music_player.volume_db = -17.0
	if GameManager != null and GameManager.music_enabled:
		game_music_player.play()
	_music_playback = game_music_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _on_music_enabled_changed(enabled: bool) -> void:
	if game_music_player == null:
		return
	if enabled:
		if not game_music_player.playing:
			game_music_player.play()
		if _music_playback == null:
			_music_playback = game_music_player.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		game_music_player.stop()
		_music_playback = null
	_update_pause_music_button_label()

func _update_pause_music_button_label() -> void:
	if pause_music_button == null or GameManager == null:
		return
	pause_music_button.text = "Music: %s" % ("On" if GameManager.music_enabled else "Off")

func _stream_game_music() -> void:
	if _music_playback == null or GameManager == null or not GameManager.music_enabled:
		return
	var frames_available: int = _music_playback.get_frames_available()
	for _i in range(frames_available):
		var step_idx: int = int(floor(_music_time / _MUSIC_STEP_SECONDS))
		var chord_idx: int = int(floor(float(step_idx) / _MUSIC_STEPS_PER_CHORD)) % _MUSIC_PROGRESS_ROOTS.size()
		var step_in_chord: int = step_idx % _MUSIC_STEPS_PER_CHORD
		var lead_freq: float = _music_lead_for_step(chord_idx, step_in_chord)
		var root_freq: float = _MUSIC_PROGRESS_ROOTS[chord_idx]
		var chord_tones: Array = _MUSIC_CHORD_TONES[chord_idx]
		_music_phase += TAU * lead_freq / _MUSIC_SAMPLE_RATE
		_music_bass_phase += TAU * root_freq / _MUSIC_SAMPLE_RATE
		var lead_square: float = 1.0 if sin(_music_phase) >= 0.0 else -1.0
		var lead_upper: float = sin(_music_phase * 2.0) * 0.26
		var bass_square: float = 1.0 if sin(_music_bass_phase) >= 0.0 else -1.0
		var pad: float = (
			sin(_music_time * TAU * float(chord_tones[0])) +
			sin(_music_time * TAU * float(chord_tones[1])) +
			sin(_music_time * TAU * float(chord_tones[2]))
		) / 3.0
		var step_phase: float = fmod(_music_time, _MUSIC_STEP_SECONDS) / _MUSIC_STEP_SECONDS
		var gate: float = 0.92 - step_phase * 0.12
		var sample: float = (lead_square * 0.042 + lead_upper * 0.028 + bass_square * 0.022 + pad * 0.030) * gate
		_music_playback.push_frame(Vector2(sample, sample))
		_music_time += 1.0 / _MUSIC_SAMPLE_RATE

func _music_lead_for_step(chord_idx: int, step_in_chord: int) -> float:
	return float(_MUSIC_MELODY_BY_CHORD[chord_idx][step_in_chord])

# ── Player spawning ───────────────────────────────────────────────────────────
func _spawn_players() -> void:
	var peer_ids: Array[int] = []
	var labels: Array[String] = []

	# Build roster from active multiplayer peer IDs so every client resolves
	# ownership the same way, even if GameManager player metadata lags behind.
	if multiplayer.has_multiplayer_peer():
		peer_ids.append(multiplayer.get_unique_id())
		peer_ids.append_array(multiplayer.get_peers())
		peer_ids.sort()
		for i in range(peer_ids.size()):
			var pid: int = peer_ids[i]
			var fallback_name: String = "Player %d" % (i + 1)
			if GameManager.players.has(pid):
				labels.append(str(GameManager.players[pid].get("username", fallback_name)))
			else:
				labels.append(fallback_name)
	else:
		# Offline: two placeholder slots; this peer controls index 0
		peer_ids = [1, 2]
		labels   = ["P1", "P2"]

	var count: int = mini(peer_ids.size(), _PALETTES.size())
	var my_peer_id: int = multiplayer.get_unique_id()
	_my_index = 0
	for i in range(count):
		if peer_ids[i] == my_peer_id:
			_my_index = i
			break

	for i in range(count):
		var start: Vector2 = _SPAWNS[i % maxi(_SPAWNS.size(), 1)]
		_players.append({
			peer_id    = peer_ids[i],
			wx         = start.x,
			wy         = start.y,
			dir        = Vector2(1.0, 0.0) if i == 0 else Vector2(-1.0, 0.0),
			health     = MAX_HP,
			alive      = true,
			atk_time   = 0.0,
			hit_landed = false,
			palette    = _PALETTES[i],
			label      = labels[i],
			walk_time  = 0.0,
			moving     = false,
		})

func _on_quit_game_button_pressed() -> void:
	_toggle_pause_menu()

func _on_pause_resume_pressed() -> void:
	_close_pause_menu()

func _on_pause_music_pressed() -> void:
	if GameManager == null:
		return
	GameManager.set_music_enabled(not GameManager.music_enabled)
	_update_pause_music_button_label()

func _on_pause_quit_pressed() -> void:
	_request_quit_to_menu()

func _toggle_pause_menu() -> void:
	if pause_menu_panel == null:
		return
	if pause_menu_panel.visible:
		_close_pause_menu()
	else:
		_open_pause_menu()

func _open_pause_menu() -> void:
	if pause_menu_panel == null:
		return
	pause_menu_panel.visible = true
	if pause_backdrop != null:
		pause_backdrop.visible = true
	_update_pause_music_button_label()
	if pause_resume_button != null:
		pause_resume_button.grab_focus()

func _close_pause_menu() -> void:
	if pause_menu_panel == null:
		return
	pause_menu_panel.visible = false
	if pause_backdrop != null:
		pause_backdrop.visible = false

func _request_quit_to_menu() -> void:
	_close_pause_menu()
	if quit_confirm_dialog == null:
		get_tree().change_scene_to_file(GameManager.MAIN_MENU_SCENE_PATH)
		return
	_apply_quit_dialog_theme()
	quit_confirm_dialog.dialog_text = "Are you sure you want to leave this match and return to the main menu?"
	quit_confirm_dialog.popup_centered()

func _apply_quit_dialog_theme() -> void:
	if quit_confirm_dialog == null:
		return
	quit_confirm_dialog.add_theme_stylebox_override("panel", UiStyleScript.make_panel_style())
	quit_confirm_dialog.add_theme_color_override("title_color", UiStyleScript.TEXT_PRIMARY)
	quit_confirm_dialog.add_theme_color_override("font_color", UiStyleScript.TEXT_SECONDARY)
	UiStyleScript.style_button(quit_confirm_dialog.get_ok_button())
	UiStyleScript.style_button(quit_confirm_dialog.get_cancel_button())

func _on_quit_confirmed() -> void:
	get_tree().change_scene_to_file(GameManager.MAIN_MENU_SCENE_PATH)

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_announce_status.rpc(_get_peer_display_name(peer_id) + " joined the match.")

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_announce_status.rpc(_get_peer_display_name(peer_id) + " left the match.")

func _get_peer_display_name(peer_id: int) -> String:
	if GameManager != null and GameManager.players.has(peer_id):
		return str(GameManager.players[peer_id].get("username", "Player"))
	return "Player %d" % peer_id

@rpc("authority", "call_local", "reliable")
func _announce_status(message: String) -> void:
	_status_messages.append({
		"text": message,
		"time_left": 4.0
	})

func _tick_status_messages(delta: float) -> void:
	for i in range(_status_messages.size() - 1, -1, -1):
		_status_messages[i]["time_left"] = float(_status_messages[i]["time_left"]) - delta
		if float(_status_messages[i]["time_left"]) <= 0.0:
			_status_messages.remove_at(i)

# ── Game loop ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_stream_game_music()
	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_pause_menu()
		return

	if _winner != -2:
		_end_timer += delta
		if _end_timer >= END_DELAY:
			get_tree().change_scene_to_file(GameManager.MAIN_MENU_SCENE_PATH)
		queue_redraw()
		return

	# Only tick and send input for the character this peer owns
	_tick_player(_players[_my_index], delta)
	_broadcast_my_state()
	_resolve_collisions()
	var run_authoritative_logic: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if run_authoritative_logic:
		for i in range(_players.size()):
			for j in range(_players.size()):
				if i != j:
					_check_hit(_players[i], _players[j])
		_check_win()
	_tick_status_messages(delta)
	queue_redraw()

# ── Per-player update (local peer only) ───────────────────────────────────────
func _tick_player(p: Dictionary, delta: float) -> void:
	if pause_menu_panel != null and pause_menu_panel.visible:
		return
	if not p.alive:
		return

	var move := Vector2.ZERO
	if Input.is_action_pressed(_ACTIONS.left):  move.x -= 1.0
	if Input.is_action_pressed(_ACTIONS.right): move.x += 1.0
	if Input.is_action_pressed(_ACTIONS.up):    move.y -= 1.0
	if Input.is_action_pressed(_ACTIONS.down):  move.y += 1.0
	if move.length_squared() > 0.0:
		move = move.normalized()
		var new_wx: float = p.wx + move.x * SPEED * delta
		var new_wy: float = p.wy + move.y * SPEED * delta
		if _terrain_renderer.get_tile_at(new_wx, new_wy) != IsoTerrainRenderer.T_SAND:
			p.wx = new_wx
			p.wy = new_wy
		p.dir        = move
		p.moving     = true
		p.walk_time += delta
	else:
		p.moving = false

	if Input.is_action_just_pressed(_ACTIONS.atk) and p.atk_time <= 0.0:
		p.atk_time   = ATK_DUR
		p.hit_landed = false
	p.atk_time = maxf(p.atk_time - delta, 0.0)

# ── State broadcast ────────────────────────────────────────────────────────────
func _broadcast_my_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var p: Dictionary = _players[_my_index]
	_receive_player_state.rpc(
		int(p.peer_id),
		float(p.wx), float(p.wy),
		float(p.dir.x), float(p.dir.y),
		float(p.atk_time), bool(p.moving), float(p.walk_time)
	)

@rpc("any_peer", "unreliable")
func _receive_player_state(
		peer_id: int,
		wx: float, wy: float,
		dir_x: float, dir_y: float,
		atk_time: float, moving: bool, walk_time: float) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var idx: int = _find_player_index_by_peer_id(peer_id)
	if idx < 0:
		return
	var p: Dictionary = _players[idx]
	p.wx        = wx
	p.wy        = wy
	p.dir       = Vector2(dir_x, dir_y)
	p.atk_time  = atk_time
	p.moving    = moving
	p.walk_time = walk_time

func _find_player_index_by_peer_id(peer_id: int) -> int:
	for i in range(_players.size()):
		if int(_players[i].get("peer_id", -1)) == peer_id:
			return i
	return -1

# ── Collision — keep players apart ────────────────────────────────────────────
func _resolve_collisions() -> void:
	const MIN_DIST := 0.85
	for i in range(_players.size()):
		for j in range(i + 1, _players.size()):
			var p_i: Dictionary = _players[i]
			var p_j: Dictionary = _players[j]
			var dx: float = float(p_j.wx) - float(p_i.wx)
			var dy: float = float(p_j.wy) - float(p_i.wy)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < MIN_DIST and dist > 0.001:
				var push: float = (MIN_DIST - dist) * 0.5
				var nx: float = dx / dist
				var ny: float = dy / dist
				p_i.wx = float(p_i.wx) - nx * push
				p_i.wy = float(p_i.wy) - ny * push
				p_j.wx = float(p_j.wx) + nx * push
				p_j.wy = float(p_j.wy) + ny * push

# ── Hit detection ─────────────────────────────────────────────────────────────
func _check_hit(attacker: Dictionary, defender: Dictionary) -> void:
	if not attacker.alive or attacker.atk_time <= 0.0 or attacker.hit_landed:
		return
	if not defender.alive:
		return
	var phase: float = 1.0 - attacker.atk_time / ATK_DUR
	if phase < HIT_START or phase > HIT_END:
		return
	var dx: float = defender.wx - attacker.wx
	var dy: float = defender.wy - attacker.wy
	var dist := sqrt(dx * dx + dy * dy)
	if dist > ATK_RANGE:
		return
	if attacker.dir.dot(Vector2(dx, dy).normalized()) < 0.25:
		return
	attacker.hit_landed = true
	var new_health: float = maxf(defender.health - DMG, 0.0)
	var defender_alive: bool = new_health > 0.0
	_apply_hit.rpc(int(attacker.peer_id), int(defender.peer_id), new_health, defender_alive)

@rpc("authority", "call_local", "reliable")
func _apply_hit(attacker_peer_id: int, defender_peer_id: int, new_health: float, defender_alive: bool) -> void:
	var attacker_idx: int = _find_player_index_by_peer_id(attacker_peer_id)
	if attacker_idx >= 0:
		_players[attacker_idx].hit_landed = true
	var defender_idx: int = _find_player_index_by_peer_id(defender_peer_id)
	if defender_idx >= 0:
		_players[defender_idx].health = new_health
		_players[defender_idx].alive = defender_alive

# ── Win condition ─────────────────────────────────────────────────────────────
func _check_win() -> void:
	if _winner != -2:
		return
	# Solo-host sessions should not immediately auto-win just because only one
	# player exists in the match.
	if _players.size() <= 1:
		return
	var alive_count := 0
	var last_alive  := -1
	for i in range(_players.size()):
		if _players[i].alive:
			alive_count += 1
			last_alive   = i
	if alive_count == 0:
		_set_winner.rpc(-1)
	elif alive_count == 1:
		_set_winner.rpc(last_alive)

@rpc("authority", "call_local", "reliable")
func _set_winner(next_winner: int) -> void:
	if _winner != -2:
		return
	_winner = next_winner
	_end_timer = 0.0

# ── Draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size

	# Camera: keep the local player centred on screen every frame
	var me: Dictionary = _players[_my_index]
	_origin = vp * 0.5 - Vector2((me.wx - me.wy) * TILE_W * _zoom * 0.5, (me.wx + me.wy) * TILE_H * _zoom * 0.5)

	draw_rect(Rect2(Vector2.ZERO, vp), _C_SKY)
	_draw_tiles(vp)

	# Y-sort: players with lower (wx+wy) are further from camera — draw first
	var sorted := _players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.wx + a.wy) < (b.wx + b.wy))
	for p in sorted:
		_draw_player(p)

	_draw_offscreen_indicators(vp)
	_draw_hud(vp)
	if _winner != -2:
		_draw_win_screen(vp)

# ── Tile drawing ──────────────────────────────────────────────────────────────
func _draw_tiles(vp: Vector2) -> void:
	_terrain_renderer.draw_tiles(self, _origin, vp, TILE_W * _zoom, TILE_H * _zoom, RENDER_MARGIN)

# ── Character drawing (pirate ship) ──────────────────────────────────────────
func _draw_player(p: Dictionary) -> void:
	var sp  := _w2s(p.wx, p.wy)
	var pa: Color = p.palette[0]
	var pb: Color = p.palette[1]
	var hull_dark := Color(pa.r * 0.40, pa.g * 0.40, pa.b * 0.40)
	var wood      := Color(0.38, 0.24, 0.10)

	# Wake ripple shadow
	draw_set_transform(sp + Vector2(0.0, 5.0), 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, 20.0, Color(0.0, 0.15, 0.35, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not p.alive:
		# Sunken wreck — broken planks
		draw_line(sp + Vector2(-12.0, -4.0), sp + Vector2(12.0,  4.0), Color(0.38, 0.24, 0.10, 0.85), 4.0)
		draw_line(sp + Vector2( 12.0, -4.0), sp + Vector2(-12.0, 4.0), Color(0.38, 0.24, 0.10, 0.85), 4.0)
		return

	var ds   := _dir_screen(p.dir.x, p.dir.y)
	var perp := Vector2(-ds.y, ds.x)
	var bob  := sin(p.walk_time * 5.0) * 1.5 if p.moving else 0.0
	var lift := Vector2(0.0, -6.0 + bob)

	# Hull — diamond with pointed bow and stern
	var bow    := sp + ds * 22.0  + lift
	var stern  := sp - ds * 18.0  + lift
	var port   := sp + perp * 9.0 + lift + Vector2(0.0, 2.0)
	var stbd   := sp - perp * 9.0 + lift + Vector2(0.0, 2.0)
	draw_polygon(PackedVector2Array([bow, port, stern, stbd]),
				 PackedColorArray([hull_dark, pa, hull_dark, pa]))
	# Gunwale outline
	draw_polyline(PackedVector2Array([bow, port, stern, stbd, bow]),
				  Color(0.0, 0.0, 0.0, 0.45), 1.5)

	# Deck stripe
	var deck_bow   := sp + ds * 8.0  + lift
	var deck_stern := sp - ds * 8.0  + lift
	draw_line(deck_bow + perp * 6.0, deck_bow - perp * 6.0,   pb, 2.0)
	draw_line(deck_stern + perp * 5.0, deck_stern - perp * 5.0, pb, 2.0)

	# Mast
	var mast_base := sp + lift
	var mast_top  := mast_base + Vector2(0.0, -32.0)
	draw_line(mast_base, mast_top, wood, 3.0)

	# Yard-arm (horizontal spar)
	var yard := mast_base + Vector2(0.0, -24.0)
	draw_line(yard - perp * 12.0, yard + perp * 12.0, wood, 2.0)

	if p.atk_time > 0.0:
		# Cannon fire — flash on both sides
		var t: float = 1.0 - float(p.atk_time) / ATK_DUR
		var cannon_l := sp + perp * 10.0 + ds * 6.0 + lift
		var cannon_r := sp - perp * 10.0 + ds * 6.0 + lift
		draw_circle(cannon_l + ds * 18.0 * t, 6.0 * (1.0 - t * 0.6), Color(1.0, 0.65, 0.1, 0.9 - t * 0.7))
		draw_circle(cannon_r + ds * 18.0 * t, 6.0 * (1.0 - t * 0.6), Color(1.0, 0.65, 0.1, 0.9 - t * 0.7))

	# Sail — rectangle between yard and lower tie
	var sail_tl := yard - perp * 11.0
	var sail_tr := yard + perp * 11.0
	var sail_br := mast_base + Vector2(0.0, -10.0) + perp * 8.0
	var sail_bl := mast_base + Vector2(0.0, -10.0) - perp * 8.0
	draw_polygon(PackedVector2Array([sail_tl, sail_tr, sail_br, sail_bl]),
				 PackedColorArray([pb, pb, Color(pb.r, pb.g, pb.b, 0.8), Color(pb.r, pb.g, pb.b, 0.8)]))
	draw_polyline(PackedVector2Array([sail_tl, sail_tr, sail_br, sail_bl, sail_tl]),
				  Color(0.0, 0.0, 0.0, 0.25), 1.0)

	# Skull flag at mast top
	draw_rect(Rect2(mast_top.x - 6.0, mast_top.y - 8.0, 10.0, 8.0), Color(0.0, 0.0, 0.0, 0.9))
	draw_circle(mast_top + Vector2(1.0, -4.0), 2.5, Color(1.0, 1.0, 1.0, 0.85))

	# Name tag
	var font := ThemeDB.fallback_font
	draw_string(font, sp + Vector2(0.0, -54.0), p.label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 1.0, 1.0, 0.88))

# ── HUD ───────────────────────────────────────────────────────────────────────
func _draw_hud(vp: Vector2) -> void:
	var font       := ThemeDB.fallback_font
	var bar_h      := 20.0
	var pad        := 14.0
	const MAX_COLS := 4
	var bar_w      := minf((vp.x - pad * (MAX_COLS + 1)) / MAX_COLS, 200.0)
	var spacing    := bar_w + pad
	var row_stride := bar_h + 8.0
	var status_y   := pad + row_stride * 2.0 + 10.0

	for i in range(_status_messages.size()):
		var entry: Dictionary = _status_messages[i]
		draw_string(
			font,
			Vector2(pad, status_y + i * 18.0),
			str(entry.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			_HUD_TEXT
		)

	for i in range(_players.size()):
		var p: Dictionary = _players[i]
		var col_idx: int = i % MAX_COLS
		@warning_ignore("integer_division")
		var row_idx: int = i / MAX_COLS
		var bx := pad + col_idx * spacing
		var by := pad + row_idx * row_stride
		var fill := bar_w * clampf(p.health / MAX_HP, 0.0, 1.0)
		var col: Color = p.palette[0]

		# Background
		draw_rect(Rect2(bx, by, bar_w, bar_h), _HUD_BG)
		# Fill
		if p.alive and fill > 0.0:
			draw_rect(Rect2(bx, by, fill, bar_h), col)
		# Border
		draw_rect(Rect2(bx, by, bar_w, bar_h), _HUD_BORDER, false, 1.5)
		# Label
		draw_string(font, Vector2(bx + 5.0, by + bar_h - 5.0),
				"%s  %d" % [p.label, int(maxf(p.health, 0.0))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _HUD_TEXT)

func _draw_win_screen(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.58))
	var font := ThemeDB.fallback_font
	var cx   := vp.x * 0.5
	var cy   := vp.y * 0.44

	var msg: String
	if _winner == -1:
		msg = "DRAW!"
	else:
		msg = "%s WINS!" % _players[_winner].label

	draw_string(font, Vector2(cx, cy), msg,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 52, Color(0.95, 0.75, 0.35, 1.0))

	var remaining := ceili(END_DELAY - _end_timer)
	draw_string(font, Vector2(cx, cy + 62.0),
			"Returning to menu in %d..." % remaining,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, _HUD_TEXT_MUTED)

# ── Off-screen player indicators ─────────────────────────────────────────────
func _draw_offscreen_indicators(vp: Vector2) -> void:
	const EDGE_PAD := 30.0
	const ARROW_R  := 12.0

	var font          := ThemeDB.fallback_font
	var screen_center := vp * 0.5

	for p in _players:
		if not p.alive:
			continue
		var sp := _w2s(p.wx, p.wy)
		# Already on screen — no indicator needed
		if sp.x >= EDGE_PAD and sp.x <= vp.x - EDGE_PAD \
				and sp.y >= EDGE_PAD and sp.y <= vp.y - EDGE_PAD:
			continue

		# Direction from screen centre toward the off-screen player
		var dir: Vector2 = (sp - screen_center).normalized()

		# Clamp to the padded screen boundary via parametric ray
		var t_x: float = INF
		var t_y: float = INF
		if abs(dir.x) > 0.0001:
			var tx0: float = (EDGE_PAD - screen_center.x) / dir.x
			var tx1: float = (vp.x - EDGE_PAD - screen_center.x) / dir.x
			t_x = tx1 if dir.x > 0.0 else tx0
		if abs(dir.y) > 0.0001:
			var ty0: float = (EDGE_PAD - screen_center.y) / dir.y
			var ty1: float = (vp.y - EDGE_PAD - screen_center.y) / dir.y
			t_y = ty1 if dir.y > 0.0 else ty0
		var t: float   = minf(t_x, t_y)
		var ap: Vector2 = screen_center + dir * t

		var pa: Color = p.palette[0]

		# Arrow triangle pointing toward the player
		var tip   := ap + dir * ARROW_R
		var perp  := Vector2(-dir.y, dir.x) * ARROW_R * 0.6
		var base1 := ap - dir * (ARROW_R * 0.4) + perp
		var base2 := ap - dir * (ARROW_R * 0.4) - perp

		# Dark shadow (slightly larger)
		const S := 1.18
		var stip   := ap + dir * ARROW_R * S
		var sperp  := Vector2(-dir.y, dir.x) * ARROW_R * 0.6 * S
		var sbase1 := ap - dir * (ARROW_R * 0.4 * S) + sperp
		var sbase2 := ap - dir * (ARROW_R * 0.4 * S) - sperp
		draw_colored_polygon([stip, sbase1, sbase2], Color(0.0, 0.0, 0.0, 0.55))

		# Coloured arrow
		draw_colored_polygon([tip, base1, base2], pa)

		# Player label beside the arrow, pushed away from screen edge
		var label_pos := ap - dir * (ARROW_R + 10.0)
		draw_string(font, label_pos, p.label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(pa.r, pa.g, pa.b, 0.90))

func _get_primary_pad_id() -> int:
	var pads: PackedInt32Array = Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	return int(pads[0])
