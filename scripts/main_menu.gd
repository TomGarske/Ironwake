extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var join_input: LineEdit = $VBoxContainer/JoinLobbyIdInput
@onready var confirm_join_button: Button = $VBoxContainer/ConfirmJoinButton
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var debug_panel: PanelContainer = $DebugPanel
@onready var debug_log: RichTextLabel = $DebugPanel/MarginContainer/DebugLog

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	if SteamManager == null:
		push_error("[MainMenu] SteamManager autoload missing.")
	else:
		SteamManager.lobby_created.connect(_on_lobby_ready)
		SteamManager.lobby_joined.connect(_on_lobby_ready)
		SteamManager.debug_message.connect(_on_steam_debug_message)
	join_input.visible = false
	confirm_join_button.visible = false

	# Keep console visible for active debugging.
	debug_panel.visible = true
	_append_debug("[MainMenu] Debug console enabled.")
	if SteamManager == null:
		_append_debug("[MainMenu] SteamManager autoload missing.", true)
	else:
		for entry in SteamManager.debug_history:
			_append_debug(str(entry.get("message", "")), bool(entry.get("is_error", false)))
		host_button.disabled = not SteamManager.steam_ready
		if host_button.disabled:
			host_button.tooltip_text = "Steam is not initialized. Check debug console output."

func _exit_tree() -> void:
	if SteamManager == null:
		return
	if SteamManager.lobby_created.is_connected(_on_lobby_ready):
		SteamManager.lobby_created.disconnect(_on_lobby_ready)
	if SteamManager.lobby_joined.is_connected(_on_lobby_ready):
		SteamManager.lobby_joined.disconnect(_on_lobby_ready)
	if SteamManager.debug_message.is_connected(_on_steam_debug_message):
		SteamManager.debug_message.disconnect(_on_steam_debug_message)

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	_append_debug("[MainMenu] Host button pressed.")
	if SteamManager != null:
		SteamManager.host_lobby()

func _on_join_button_pressed() -> void:
	join_input.visible = true
	confirm_join_button.visible = true
	join_input.grab_focus()

func _on_confirm_join_button_pressed() -> void:
	var lobby_id: int = int(join_input.text.strip_edges())
	if lobby_id > 0:
		_append_debug("[MainMenu] Attempting join for lobby %d." % lobby_id)
		if SteamManager != null:
			SteamManager.join_lobby(lobby_id)
	else:
		_append_debug("[MainMenu] Invalid lobby ID entered.", true)

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

func _on_steam_debug_message(message: String, is_error: bool) -> void:
	_append_debug(message, is_error)

func _append_debug(message: String, is_error: bool = false) -> void:
	if not debug_panel.visible:
		return
	var prefix: String = "[ERR] " if is_error else "[LOG] "
	debug_log.append_text(prefix + message + "\n")
	debug_log.scroll_to_line(debug_log.get_line_count())
