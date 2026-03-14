extends Control
const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var join_input: LineEdit = $RightLobbyPanel/VBoxContainer/JoinLobbyIdInput
@onready var confirm_join_button: Button = $RightLobbyPanel/VBoxContainer/ConfirmJoinButton
@onready var host_button: Button = $LeftMenuPanel/VBoxContainer/HostButton
@onready var test_button: Button = $LeftMenuPanel/VBoxContainer/TestButton
@onready var settings_button: Button = $LeftMenuPanel/VBoxContainer/SettingsButton
@onready var exit_button: Button = $LeftMenuPanel/VBoxContainer/ExitButton
@onready var lobby_list_title: Label = $RightLobbyPanel/VBoxContainer/PublicLobbiesTitle
@onready var refresh_lobbies_button: Button = $RightLobbyPanel/VBoxContainer/RefreshLobbiesButton
@onready var lobby_list_status: Label = $RightLobbyPanel/VBoxContainer/LobbyListStatus
@onready var lobby_list: VBoxContainer = $RightLobbyPanel/VBoxContainer/LobbyListScroll/LobbyList
@onready var version_label: Label = $VersionLabel
@onready var quit_confirm_dialog: ConfirmationDialog = $QuitConfirmDialog
@onready var menu_music_player: AudioStreamPlayer = $MenuMusicPlayer
@onready var settings_popup: PopupPanel = $SettingsPopup
@onready var music_toggle: CheckButton = $SettingsPopup/SettingsMargin/VBoxContainer/MusicToggle

var _music_playback: AudioStreamGeneratorPlayback = null
var _music_phase: float = 0.0
var _music_bass_phase: float = 0.0
var _music_time: float = 0.0

const _MUSIC_SAMPLE_RATE: float = 44100.0
const _MUSIC_STEP_SECONDS: float = 0.34
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

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_update_version_label()
	_apply_warm_tactical_theme()
	_configure_navigation()
	_setup_menu_music()
	_sync_music_toggle()
	_apply_music_enabled_state()
	_apply_dialog_theme()

	if SteamManager == null:
		push_error("[MainMenu] SteamManager autoload missing.")
	else:
		SteamManager.lobby_created.connect(_on_lobby_ready)
		SteamManager.lobby_joined.connect(_on_lobby_ready)
		SteamManager.invite_join_requested.connect(_on_invite_join_requested)
		SteamManager.lobby_list_updated.connect(_on_lobby_list_updated)
		host_button.disabled = not SteamManager.steam_ready
		if host_button.disabled:
			host_button.tooltip_text = "Steam is not initialized. Check debug console output."
		# If app was launched from a Steam invite and joined before menu connected, continue to lobby.
		if SteamManager.lobby_id > 0:
			DebugOverlay.log_message("[MainMenu] Existing lobby detected (%d). Entering lobby..." % SteamManager.lobby_id)
			call_deferred("_on_lobby_ready", SteamManager.lobby_id)
	
	refresh_lobbies_button.pressed.connect(_on_refresh_lobbies_pressed)
	if not quit_confirm_dialog.confirmed.is_connected(_on_quit_confirmed):
		quit_confirm_dialog.confirmed.connect(_on_quit_confirmed)
	if GameManager != null and not GameManager.music_enabled_changed.is_connected(_on_music_enabled_changed):
		GameManager.music_enabled_changed.connect(_on_music_enabled_changed)

	DebugOverlay.log_message("[MainMenu] Ready.")
	if SteamManager != null:
		_refresh_lobby_browser()

func _process(_delta: float) -> void:
	_stream_menu_music()

func _apply_warm_tactical_theme() -> void:
	UiStyleScript.style_button(host_button)
	UiStyleScript.style_button(test_button)
	UiStyleScript.style_button(settings_button)
	UiStyleScript.style_button(exit_button)
	UiStyleScript.style_button(confirm_join_button)
	UiStyleScript.style_button(refresh_lobbies_button)
	UiStyleScript.style_line_edit(join_input)
	if music_toggle != null:
		music_toggle.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
		music_toggle.add_theme_color_override("font_pressed_color", UiStyleScript.TEXT_PRIMARY)
		music_toggle.add_theme_color_override("font_hover_color", UiStyleScript.TEXT_PRIMARY)

func _apply_dialog_theme() -> void:
	if quit_confirm_dialog == null:
		return
	quit_confirm_dialog.add_theme_stylebox_override("panel", UiStyleScript.make_panel_style())
	quit_confirm_dialog.add_theme_color_override("title_color", UiStyleScript.TEXT_PRIMARY)
	quit_confirm_dialog.add_theme_color_override("font_color", UiStyleScript.TEXT_SECONDARY)
	UiStyleScript.style_button(quit_confirm_dialog.get_ok_button())
	UiStyleScript.style_button(quit_confirm_dialog.get_cancel_button())

func _update_version_label() -> void:
	if version_label == null:
		return
	var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = version

func _configure_navigation() -> void:
	host_button.focus_mode = Control.FOCUS_ALL
	test_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL
	exit_button.focus_mode = Control.FOCUS_ALL
	confirm_join_button.focus_mode = Control.FOCUS_ALL
	refresh_lobbies_button.focus_mode = Control.FOCUS_ALL
	join_input.focus_mode = Control.FOCUS_ALL
	music_toggle.focus_mode = Control.FOCUS_ALL
	host_button.focus_neighbor_bottom = host_button.get_path_to(test_button)
	test_button.focus_neighbor_top = test_button.get_path_to(host_button)
	test_button.focus_neighbor_bottom = test_button.get_path_to(settings_button)
	settings_button.focus_neighbor_top = settings_button.get_path_to(test_button)
	settings_button.focus_neighbor_bottom = settings_button.get_path_to(exit_button)
	exit_button.focus_neighbor_top = exit_button.get_path_to(settings_button)
	exit_button.focus_neighbor_bottom = exit_button.get_path_to(host_button)
	host_button.grab_focus()

func _setup_menu_music() -> void:
	if menu_music_player == null:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = int(_MUSIC_SAMPLE_RATE)
	stream.buffer_length = 0.25
	menu_music_player.stream = stream
	menu_music_player.volume_db = -16.0
	if GameManager != null and GameManager.music_enabled:
		menu_music_player.play()
	_music_playback = menu_music_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _stream_menu_music() -> void:
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
		var lead_sine: float = sin(_music_phase * 0.5)
		var bass_square: float = 1.0 if sin(_music_bass_phase) >= 0.0 else -1.0
		var pad: float = (
			sin(_music_time * TAU * float(chord_tones[0])) +
			sin(_music_time * TAU * float(chord_tones[1])) +
			sin(_music_time * TAU * float(chord_tones[2]))
		) / 3.0
		var step_phase: float = fmod(_music_time, _MUSIC_STEP_SECONDS) / _MUSIC_STEP_SECONDS
		var gate: float = 0.94 - step_phase * 0.10
		var sample: float = (lead_square * 0.040 + lead_sine * 0.026 + bass_square * 0.018 + pad * 0.026) * gate
		_music_playback.push_frame(Vector2(sample, sample))
		_music_time += 1.0 / _MUSIC_SAMPLE_RATE

func _music_lead_for_step(chord_idx: int, step_in_chord: int) -> float:
	return float(_MUSIC_MELODY_BY_CHORD[chord_idx][step_in_chord])

func _exit_tree() -> void:
	if SteamManager != null:
		if SteamManager.lobby_created.is_connected(_on_lobby_ready):
			SteamManager.lobby_created.disconnect(_on_lobby_ready)
		if SteamManager.lobby_joined.is_connected(_on_lobby_ready):
			SteamManager.lobby_joined.disconnect(_on_lobby_ready)
		if SteamManager.invite_join_requested.is_connected(_on_invite_join_requested):
			SteamManager.invite_join_requested.disconnect(_on_invite_join_requested)
		if SteamManager.lobby_list_updated.is_connected(_on_lobby_list_updated):
			SteamManager.lobby_list_updated.disconnect(_on_lobby_list_updated)
	if GameManager != null and GameManager.music_enabled_changed.is_connected(_on_music_enabled_changed):
		GameManager.music_enabled_changed.disconnect(_on_music_enabled_changed)

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	DebugOverlay.log_message("[MainMenu] Host button pressed.")
	if SteamManager != null:
		SteamManager.host_lobby()

func _on_confirm_join_button_pressed() -> void:
	var lobby_id: int = int(join_input.text.strip_edges())
	if lobby_id > 0:
		DebugOverlay.log_message("[MainMenu] Attempting join for lobby %d." % lobby_id)
		if SteamManager != null:
			SteamManager.join_lobby(lobby_id)
	else:
		DebugOverlay.log_message("[MainMenu] Invalid lobby ID entered.", true)

func _on_test_button_pressed() -> void:
	if SteamManager != null and SteamManager.lobby_id != 0:
		SteamManager.leave_lobby()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	GameManager.setup_offline_test()
	get_tree().change_scene_to_file(GameManager.MATCH_SCENE_PATH)

func _on_exit_button_pressed() -> void:
	quit_confirm_dialog.title = "Exit BurnBridgers"
	quit_confirm_dialog.ok_button_text = "Exit Game"
	quit_confirm_dialog.dialog_text = "Are you sure you want to close BurnBridgers and return to desktop?"
	quit_confirm_dialog.popup_centered()

func _on_settings_button_pressed() -> void:
	_sync_music_toggle()
	settings_popup.popup_centered()

func _on_music_toggle_toggled(enabled: bool) -> void:
	if GameManager != null:
		GameManager.set_music_enabled(enabled)

func _on_music_enabled_changed(_enabled: bool) -> void:
	_sync_music_toggle()
	_apply_music_enabled_state()

func _sync_music_toggle() -> void:
	if music_toggle == null or GameManager == null:
		return
	music_toggle.set_pressed_no_signal(GameManager.music_enabled)

func _apply_music_enabled_state() -> void:
	if menu_music_player == null or GameManager == null:
		return
	if GameManager.music_enabled:
		if not menu_music_player.playing:
			menu_music_player.play()
		if _music_playback == null:
			_music_playback = menu_music_player.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		menu_music_player.stop()

func _on_quit_confirmed() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# Lobby ready callback
# ---------------------------------------------------------------------------
func _on_lobby_ready(_lobby_id: int) -> void:
	call_deferred("_do_scene_change_lobby")

func _do_scene_change_lobby() -> void:
	get_tree().change_scene_to_file(GameManager.LOBBY_SCENE_PATH)

func _on_invite_join_requested(target_lobby_id: int) -> void:
	DebugOverlay.log_message("[MainMenu] Processing invite join request for lobby %d." % target_lobby_id)

func _on_refresh_lobbies_pressed() -> void:
	_refresh_lobby_browser()

func _refresh_lobby_browser() -> void:
	var can_query: bool = SteamManager != null and SteamManager.steam_ready
	lobby_list_title.visible = true
	refresh_lobbies_button.visible = true
	lobby_list_status.visible = true
	lobby_list.get_parent().visible = true
	if not can_query:
		lobby_list_status.text = "Steam not initialized yet."
		_rebuild_lobby_list([])
		return
	lobby_list_status.text = "Searching for BurnBridgers lobbies..."
	SteamManager.request_burnbridgers_lobby_list()
	_rebuild_lobby_list(SteamManager.get_cached_public_lobbies())

func _on_join_lobby_from_list(target_lobby_id: int) -> void:
	DebugOverlay.log_message("[MainMenu] Joining listed lobby %d." % target_lobby_id)
	join_input.text = str(target_lobby_id)
	if SteamManager != null:
		SteamManager.join_lobby(target_lobby_id)

func _on_lobby_list_updated(lobbies: Array) -> void:
	_rebuild_lobby_list(lobbies)
	if lobbies.is_empty():
		lobby_list_status.text = "No public BurnBridgers lobbies found."
	else:
		lobby_list_status.text = "%d BurnBridgers lobby(s) found." % lobbies.size()

func _rebuild_lobby_list(lobbies: Array) -> void:
	for child in lobby_list.get_children():
		child.queue_free()
	if lobbies.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No lobbies yet. Host a game to create one."
		UiStyleScript.style_body(empty_label, true)
		lobby_list.add_child(empty_label)
		return
	for item in lobbies:
		var lobby_id: int = int(item.get("lobby_id", 0))
		if lobby_id <= 0:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lobby_name: String = str(item.get("name", "BurnBridgers Lobby"))
		var members: int = int(item.get("members", 0))
		name_label.text = "%s (%d/4)" % [lobby_name, members]
		UiStyleScript.style_body(name_label)
		row.add_child(name_label)

		var join_button := Button.new()
		join_button.text = "Join"
		UiStyleScript.style_button(join_button)
		join_button.pressed.connect(_on_join_lobby_from_list.bind(lobby_id))
		row.add_child(join_button)

		lobby_list.add_child(row)
