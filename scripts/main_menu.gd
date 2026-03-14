extends Control

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
var _music_time: float = 0.0
var _menu_index: int = 0
var _menu_up_prev: bool = false
var _menu_down_prev: bool = false
var _menu_accept_prev: bool = false
var _menu_cancel_prev: bool = false
var _controller_debug_label: Label = null

const _MUSIC_SAMPLE_RATE: float = 44100.0
const _MUSIC_STEP_SECONDS: float = 0.36
const _MUSIC_STEPS_PER_BAR: int = 8
const _MUSIC_SECTION_BARS: int = 32
const _MUSIC_INTRO: Array[float] = [164.81, 164.81, 196.00, 196.00, 220.00, 220.00, 196.00, 196.00]
const _MUSIC_VERSE: Array[float] = [164.81, 196.00, 246.94, 196.00, 220.00, 246.94, 220.00, 196.00]
const _MUSIC_CHORUS: Array[float] = [246.94, 293.66, 329.63, 293.66, 261.63, 293.66, 246.94, 220.00]
const _MUSIC_BRIDGE: Array[float] = [196.00, 220.00, 246.94, 220.00, 196.00, 185.00, 164.81, 185.00]
const _MUSIC_HYPE: Array[float] = [329.63, 392.00, 440.00, 392.00, 369.99, 440.00, 493.88, 440.00]
const _BASS_INTRO: Array[float] = [82.41, 82.41, 98.00, 98.00]
const _BASS_VERSE: Array[float] = [82.41, 98.00, 123.47, 110.00]
const _BASS_CHORUS: Array[float] = [123.47, 146.83, 164.81, 146.83]
const _BASS_BRIDGE: Array[float] = [98.00, 110.00, 92.50, 82.41]
const _BASS_HYPE: Array[float] = [146.83, 164.81, 185.00, 164.81]

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_update_version_label()
	_setup_menu_navigation()
	_setup_controller_debug_line()
	_setup_menu_music()
	_sync_music_toggle()
	_apply_music_enabled_state()

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
	_refresh_menu_selection()

	DebugOverlay.log_message("[MainMenu] Ready.")
	if SteamManager != null:
		_refresh_lobby_browser()

func _process(_delta: float) -> void:
	_stream_menu_music()
	_handle_simple_controller_menu_input()
	_update_controller_debug_line()

func _update_version_label() -> void:
	if version_label == null:
		return
	var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = version

func _setup_menu_navigation() -> void:
	host_button.focus_mode = Control.FOCUS_ALL
	test_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL
	exit_button.focus_mode = Control.FOCUS_ALL
	confirm_join_button.focus_mode = Control.FOCUS_ALL
	refresh_lobbies_button.focus_mode = Control.FOCUS_ALL
	music_toggle.focus_mode = Control.FOCUS_ALL
	host_button.focus_neighbor_bottom = host_button.get_path_to(test_button)
	test_button.focus_neighbor_top = test_button.get_path_to(host_button)
	test_button.focus_neighbor_bottom = test_button.get_path_to(settings_button)
	settings_button.focus_neighbor_top = settings_button.get_path_to(test_button)
	settings_button.focus_neighbor_bottom = settings_button.get_path_to(exit_button)
	exit_button.focus_neighbor_top = exit_button.get_path_to(settings_button)
	exit_button.focus_neighbor_bottom = exit_button.get_path_to(host_button)
	_refresh_menu_selection()

func _get_enabled_menu_buttons() -> Array[Button]:
	var ordered: Array[Button] = [host_button, test_button, settings_button, exit_button]
	var enabled: Array[Button] = []
	for button in ordered:
		if button != null and button.visible and not button.disabled:
			enabled.append(button)
	return enabled

func _cycle_menu_focus(direction: int) -> void:
	var buttons: Array[Button] = _get_enabled_menu_buttons()
	if buttons.is_empty():
		return
	_menu_index = posmod(_menu_index + direction, buttons.size())
	buttons[_menu_index].grab_focus()

func _activate_selected_menu_button() -> void:
	var buttons: Array[Button] = _get_enabled_menu_buttons()
	if buttons.is_empty():
		return
	_menu_index = clampi(_menu_index, 0, buttons.size() - 1)
	buttons[_menu_index].pressed.emit()

func _handle_simple_controller_menu_input() -> void:
	var pad_id: int = _get_primary_pad_id()
	if pad_id < 0:
		_menu_up_prev = false
		_menu_down_prev = false
		_menu_accept_prev = false
		_menu_cancel_prev = false
		return

	var stick_y: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
	var down_now: bool = _is_pad_pressed_any(pad_id, [JOY_BUTTON_DPAD_DOWN]) or stick_y > 0.60
	var up_now: bool = _is_pad_pressed_any(pad_id, [JOY_BUTTON_DPAD_UP]) or stick_y < -0.60
	if down_now and not _menu_down_prev:
		_cycle_menu_focus(1)
	if up_now and not _menu_up_prev:
		_cycle_menu_focus(-1)
	_menu_down_prev = down_now
	_menu_up_prev = up_now

	var accept_down: bool = _is_pad_pressed_any(pad_id, [
		JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_START
	])
	if accept_down and not _menu_accept_prev:
		_activate_selected_menu_button()
	_menu_accept_prev = accept_down

	var cancel_down: bool = _is_pad_pressed_any(pad_id, [
		JOY_BUTTON_B, JOY_BUTTON_Y, JOY_BUTTON_BACK
	])
	if cancel_down and not _menu_cancel_prev:
		_on_exit_button_pressed()
	_menu_cancel_prev = cancel_down

func _is_pad_pressed_any(pad_id: int, buttons: Array[int]) -> bool:
	for button in buttons:
		if Input.is_joy_button_pressed(pad_id, button):
			return true
	return false

func _refresh_menu_selection() -> void:
	var buttons: Array[Button] = _get_enabled_menu_buttons()
	if buttons.is_empty():
		return
	_menu_index = clampi(_menu_index, 0, buttons.size() - 1)
	buttons[_menu_index].grab_focus()

func _get_primary_pad_id() -> int:
	var pads: PackedInt32Array = Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	return int(pads[0])

func _setup_controller_debug_line() -> void:
	_controller_debug_label = Label.new()
	_controller_debug_label.name = "ControllerDebugLine"
	_controller_debug_label.layout_mode = 1
	_controller_debug_label.anchors_preset = 0
	_controller_debug_label.offset_left = 12.0
	_controller_debug_label.offset_top = 12.0
	_controller_debug_label.offset_right = 900.0
	_controller_debug_label.offset_bottom = 34.0
	_controller_debug_label.add_theme_font_size_override("font_size", 12)
	_controller_debug_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.95))
	_controller_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controller_debug_label.text = "Controller debug initializing..."
	add_child(_controller_debug_label)

func _update_controller_debug_line() -> void:
	if _controller_debug_label == null:
		return
	var pad_ids: PackedInt32Array = Input.get_connected_joypads()
	var id_text: String = "none"
	if not pad_ids.is_empty():
		var parts: Array[String] = []
		for id in pad_ids:
			parts.append(str(id))
		id_text = ",".join(parts)

	var pad_id: int = _get_primary_pad_id()
	if pad_id < 0:
		_controller_debug_label.text = "Pads: [%s] | no active pad" % id_text
		return

	var a: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_A) else 0
	var b: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_B) else 0
	var x: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X) else 0
	var y: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_Y) else 0
	var up: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_UP) else 0
	var down: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_DOWN) else 0
	var left: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_LEFT) else 0
	var right: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_RIGHT) else 0
	var start: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_START) else 0
	var back: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_BACK) else 0
	var lx: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
	var ui_up: int = 1 if Input.is_action_pressed("ui_up") else 0
	var ui_down: int = 1 if Input.is_action_pressed("ui_down") else 0
	var ui_accept: int = 1 if Input.is_action_pressed("ui_accept") else 0
	var ui_cancel: int = 1 if Input.is_action_pressed("ui_cancel") else 0

	_controller_debug_label.text = "Pads:[%s] Active:%d | A:%d B:%d X:%d Y:%d U:%d D:%d L:%d R:%d Start:%d Back:%d | LX:%.2f LY:%.2f | ui U:%d D:%d A:%d C:%d" % [
		id_text, pad_id, a, b, x, y, up, down, left, right, start, back, lx, ly, ui_up, ui_down, ui_accept, ui_cancel
	]

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
		var bar_idx: int = int(floor(float(step_idx) / _MUSIC_STEPS_PER_BAR)) % _MUSIC_SECTION_BARS
		var step_in_bar: int = step_idx % _MUSIC_STEPS_PER_BAR
		var bass_step: int = int(floor(_music_time / (_MUSIC_STEP_SECONDS * 2.0))) % 4
		var section: int = _menu_section_for_bar(bar_idx)
		var freq: float = _menu_lead_for_step(section, step_in_bar)
		var bass_freq: float = _menu_bass_for_step(section, bass_step)
		var energy: float = _menu_section_energy(section)
		_music_phase += TAU * freq / _MUSIC_SAMPLE_RATE
		var bass_phase: float = _music_time * TAU * bass_freq
		var lead_square: float = 1.0 if sin(_music_phase) >= 0.0 else -1.0
		var lead_subtle: float = sin(_music_phase * 2.0) * (0.12 + energy * 0.20)
		var bass_square: float = 1.0 if sin(bass_phase) >= 0.0 else -1.0
		var gate_phase: float = fmod(_music_time, _MUSIC_STEP_SECONDS) / _MUSIC_STEP_SECONDS
		var gate: float = 0.90 - gate_phase * 0.15
		var sample: float = (lead_square * (0.035 + energy * 0.018) + lead_subtle * 0.030 + bass_square * (0.020 + energy * 0.010)) * gate
		_music_playback.push_frame(Vector2(sample, sample))
		_music_time += 1.0 / _MUSIC_SAMPLE_RATE

func _menu_section_for_bar(bar_idx: int) -> int:
	if bar_idx < 4:
		return 0 # intro
	if bar_idx < 12:
		return 1 # verse
	if bar_idx < 20:
		return 2 # chorus
	if bar_idx < 24:
		return 3 # bridge
	return 4 # hype

func _menu_section_energy(section: int) -> float:
	match section:
		0:
			return 0.45
		1:
			return 0.62
		2:
			return 0.86
		3:
			return 0.58
		_:
			return 1.0

func _menu_lead_for_step(section: int, step_in_bar: int) -> float:
	match section:
		0:
			return _MUSIC_INTRO[step_in_bar]
		1:
			return _MUSIC_VERSE[step_in_bar]
		2:
			return _MUSIC_CHORUS[step_in_bar]
		3:
			return _MUSIC_BRIDGE[step_in_bar]
		_:
			return _MUSIC_HYPE[step_in_bar]

func _menu_bass_for_step(section: int, bass_step: int) -> float:
	match section:
		0:
			return _BASS_INTRO[bass_step]
		1:
			return _BASS_VERSE[bass_step]
		2:
			return _BASS_CHORUS[bass_step]
		3:
			return _BASS_BRIDGE[bass_step]
		_:
			return _BASS_HYPE[bass_step]

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
	quit_confirm_dialog.title = "Quit Game"
	quit_confirm_dialog.ok_button_text = "Quit"
	quit_confirm_dialog.dialog_text = "Close BurnBridgers and return to desktop?"
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
		name_label.text = "%s (%d/%d)" % [lobby_name, members, GameConstants.MAX_PLAYERS]
		row.add_child(name_label)

		var join_button := Button.new()
		join_button.text = "Join"
		join_button.pressed.connect(_on_join_lobby_from_list.bind(lobby_id))
		row.add_child(join_button)

		lobby_list.add_child(row)
