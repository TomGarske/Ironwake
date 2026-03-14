extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var join_input: LineEdit = $VBoxContainer/JoinLobbyIdInput
@onready var confirm_join_button: Button = $VBoxContainer/ConfirmJoinButton

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	SteamManager.lobby_created.connect(_on_lobby_ready)
	SteamManager.lobby_joined.connect(_on_lobby_ready)
	join_input.visible = false
	confirm_join_button.visible = false

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	SteamManager.host_lobby()

func _on_join_button_pressed() -> void:
	join_input.visible = true
	confirm_join_button.visible = true
	join_input.grab_focus()

func _on_confirm_join_button_pressed() -> void:
	var lobby_id: int = int(join_input.text.strip_edges())
	if lobby_id > 0:
		SteamManager.join_lobby(lobby_id)
	else:
		push_warning("[MainMenu] Invalid lobby ID entered.")

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
