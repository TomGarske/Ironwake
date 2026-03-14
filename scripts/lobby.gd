extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var lobby_id_label: Label = $VBoxContainer/LobbyIdLabel
@onready var player_list: VBoxContainer = $VBoxContainer/PlayerList
@onready var start_button: Button = $VBoxContainer/StartButton

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	lobby_id_label.text = "Lobby ID: %d" % SteamManager.lobby_id

	# Only the host sees the Start button
	start_button.visible = SteamManager.is_host
	start_button.disabled = true

	# Refresh list when peers connect/disconnect
	SteamManager.peer_connected.connect(_refresh_player_list)
	SteamManager.peer_disconnected.connect(_refresh_player_list)

	_refresh_player_list(0)

# ---------------------------------------------------------------------------
# Player list
# ---------------------------------------------------------------------------
func _refresh_player_list(_peer_id: int) -> void:
	# Clear existing entries
	for child in player_list.get_children():
		child.queue_free()

	if SteamManager.lobby_id == 0:
		return

	var member_count: int = Steam.getNumLobbyMembers(SteamManager.lobby_id)
	for i in range(member_count):
		var member_steam_id: int = Steam.getLobbyMemberByIndex(SteamManager.lobby_id, i)
		var label := Label.new()
		label.text = Steam.getFriendPersonaName(member_steam_id)
		player_list.add_child(label)

	# Host can only start with at least 2 players
	start_button.disabled = member_count < 2

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_start_button_pressed() -> void:
	GameManager.start_match()
