extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var join_input: LineEdit = $VBoxContainer/JoinLobbyIdInput
@onready var confirm_join_button: Button = $VBoxContainer/ConfirmJoinButton
@onready var host_button: Button = $VBoxContainer/HostButton

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	if SteamManager == null:
		push_error("[MainMenu] SteamManager autoload missing.")
	else:
		SteamManager.lobby_created.connect(_on_lobby_ready)
		SteamManager.lobby_joined.connect(_on_lobby_ready)
		SteamManager.invite_join_requested.connect(_on_invite_join_requested)
	join_input.visible = false
	confirm_join_button.visible = false

	DebugOverlay.log_message("[MainMenu] Ready.")
	if SteamManager == null:
		DebugOverlay.log_message("[MainMenu] SteamManager autoload missing.", true)
	else:
		host_button.disabled = not SteamManager.steam_ready
		if host_button.disabled:
			host_button.tooltip_text = "Steam is not initialized. Check debug console output."
		# If app was launched from a Steam invite and joined before menu connected, continue to lobby.
		if SteamManager.lobby_id > 0:
			DebugOverlay.log_message("[MainMenu] Existing lobby detected (%d). Entering lobby..." % SteamManager.lobby_id)
			call_deferred("_on_lobby_ready", SteamManager.lobby_id)

func _exit_tree() -> void:
	if SteamManager == null:
		return
	if SteamManager.lobby_created.is_connected(_on_lobby_ready):
		SteamManager.lobby_created.disconnect(_on_lobby_ready)
	if SteamManager.lobby_joined.is_connected(_on_lobby_ready):
		SteamManager.lobby_joined.disconnect(_on_lobby_ready)
	if SteamManager.invite_join_requested.is_connected(_on_invite_join_requested):
		SteamManager.invite_join_requested.disconnect(_on_invite_join_requested)

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	DebugOverlay.log_message("[MainMenu] Host button pressed.")
	if SteamManager != null:
		SteamManager.host_lobby()

func _on_join_button_pressed() -> void:
	join_input.visible = true
	confirm_join_button.visible = true
	join_input.grab_focus()

func _on_confirm_join_button_pressed() -> void:
	var lobby_id: int = int(join_input.text.strip_edges())
	if lobby_id > 0:
		DebugOverlay.log_message("[MainMenu] Attempting join for lobby %d." % lobby_id)
		if SteamManager != null:
			SteamManager.join_lobby(lobby_id)
	else:
		DebugOverlay.log_message("[MainMenu] Invalid lobby ID entered.", true)

func _on_test_button_pressed() -> void:
	GameManager.setup_offline_test()
	get_tree().change_scene_to_file("res://scenes/game/tactical_map.tscn")

func _on_exit_button_pressed() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# Lobby ready callback
# ---------------------------------------------------------------------------
func _on_lobby_ready(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_invite_join_requested(target_lobby_id: int) -> void:
	DebugOverlay.log_message("[MainMenu] Processing invite join request for lobby %d." % target_lobby_id)
