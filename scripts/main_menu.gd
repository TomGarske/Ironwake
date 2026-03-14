extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var join_input: LineEdit = $RightLobbyPanel/VBoxContainer/JoinLobbyIdInput
@onready var confirm_join_button: Button = $RightLobbyPanel/VBoxContainer/ConfirmJoinButton
@onready var host_button: Button = $LeftMenuPanel/VBoxContainer/HostButton
@onready var lobby_list_title: Label = $RightLobbyPanel/VBoxContainer/PublicLobbiesTitle
@onready var refresh_lobbies_button: Button = $RightLobbyPanel/VBoxContainer/RefreshLobbiesButton
@onready var lobby_list_status: Label = $RightLobbyPanel/VBoxContainer/LobbyListStatus
@onready var lobby_list: VBoxContainer = $RightLobbyPanel/VBoxContainer/LobbyListScroll/LobbyList
@onready var version_label: Label = $VersionLabel
@onready var quit_confirm_dialog: ConfirmationDialog = $QuitConfirmDialog
@onready var menu_music_player: AudioStreamPlayer = $MenuMusicPlayer

var _music_playback: AudioStreamGeneratorPlayback = null
var _music_phase: float = 0.0
var _music_time: float = 0.0

const _MUSIC_SAMPLE_RATE: float = 44100.0
const _MUSIC_STEP_SECONDS: float = 0.40
const _MUSIC_MELODY: Array[float] = [261.63, 329.63, 392.00, 329.63, 293.66, 392.00, 523.25, 392.00]

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_update_version_label()
	_configure_navigation()
	_setup_menu_music()

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

	DebugOverlay.log_message("[MainMenu] Ready.")
	if SteamManager != null:
		_refresh_lobby_browser()

func _process(_delta: float) -> void:
	_stream_menu_music()

func _update_version_label() -> void:
	if version_label == null:
		return
	var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = version

func _configure_navigation() -> void:
	host_button.focus_neighbor_bottom = host_button.get_path_to($LeftMenuPanel/VBoxContainer/TestButton)
	$LeftMenuPanel/VBoxContainer/TestButton.focus_neighbor_top = $LeftMenuPanel/VBoxContainer/TestButton.get_path_to(host_button)
	$LeftMenuPanel/VBoxContainer/TestButton.focus_neighbor_bottom = $LeftMenuPanel/VBoxContainer/TestButton.get_path_to($LeftMenuPanel/VBoxContainer/ExitButton)
	$LeftMenuPanel/VBoxContainer/ExitButton.focus_neighbor_top = $LeftMenuPanel/VBoxContainer/ExitButton.get_path_to($LeftMenuPanel/VBoxContainer/TestButton)
	$LeftMenuPanel/VBoxContainer/ExitButton.focus_neighbor_bottom = $LeftMenuPanel/VBoxContainer/ExitButton.get_path_to(host_button)
	host_button.grab_focus()

func _setup_menu_music() -> void:
	if menu_music_player == null:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = int(_MUSIC_SAMPLE_RATE)
	stream.buffer_length = 0.25
	menu_music_player.stream = stream
	menu_music_player.volume_db = -16.0
	menu_music_player.play()
	_music_playback = menu_music_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _stream_menu_music() -> void:
	if _music_playback == null:
		return
	var frames_available: int = _music_playback.get_frames_available()
	for _i in range(frames_available):
		var note_index: int = int(floor(_music_time / _MUSIC_STEP_SECONDS)) % _MUSIC_MELODY.size()
		var freq: float = _MUSIC_MELODY[note_index]
		_music_phase += TAU * freq / _MUSIC_SAMPLE_RATE
		var harmonic: float = sin(_music_phase * 2.0) * 0.35
		var sample: float = (sin(_music_phase) + harmonic) * 0.08
		_music_playback.push_frame(Vector2(sample, sample))
		_music_time += 1.0 / _MUSIC_SAMPLE_RATE

func _exit_tree() -> void:
	if SteamManager == null:
		return
	if SteamManager.lobby_created.is_connected(_on_lobby_ready):
		SteamManager.lobby_created.disconnect(_on_lobby_ready)
	if SteamManager.lobby_joined.is_connected(_on_lobby_ready):
		SteamManager.lobby_joined.disconnect(_on_lobby_ready)
	if SteamManager.invite_join_requested.is_connected(_on_invite_join_requested):
		SteamManager.invite_join_requested.disconnect(_on_invite_join_requested)
	if SteamManager.lobby_list_updated.is_connected(_on_lobby_list_updated):
		SteamManager.lobby_list_updated.disconnect(_on_lobby_list_updated)

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
		name_label.text = "%s (%d/4)" % [lobby_name, members]
		row.add_child(name_label)

		var join_button := Button.new()
		join_button.text = "Join"
		join_button.pressed.connect(_on_join_lobby_from_list.bind(lobby_id))
		row.add_child(join_button)

		lobby_list.add_child(row)
