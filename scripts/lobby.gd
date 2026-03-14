extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var lobby_id_label: Label = $VBoxContainer/LobbyIdLabel
@onready var lobby_status_label: Label = $VBoxContainer/LobbyStatusLabel
@onready var player_list: VBoxContainer = $VBoxContainer/PlayerList
@onready var friends_title: Label = $VBoxContainer/FriendsTitle
@onready var friends_list: VBoxContainer = $VBoxContainer/FriendsScroll/FriendsList
@onready var invite_note_label: Label = $VBoxContainer/InviteNoteLabel
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var refresh_timer: Timer = $RefreshTimer

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
	SteamManager.lobby_members_updated.connect(_refresh_player_list.bind(0))

	refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	refresh_timer.start()

	_refresh_player_list(0)
	_refresh_online_friends()

# ---------------------------------------------------------------------------
# Player list
# ---------------------------------------------------------------------------
func _refresh_player_list(_peer_id: int) -> void:
	# Clear existing entries
	for child in player_list.get_children():
		child.queue_free()

	if SteamManager.lobby_id == 0:
		return

	var members: Array[String] = SteamManager.get_lobby_member_names()
	var member_count: int = members.size()
	for member_name in members:
		var label := Label.new()
		label.text = member_name + " (In Lobby)"
		player_list.add_child(label)
	lobby_status_label.text = "Lobby Members: %d/4" % member_count

	# Host can start with any non-zero lobby size.
	start_button.disabled = member_count < 1
	_refresh_online_friends()

func _refresh_online_friends() -> void:
	for child in friends_list.get_children():
		child.queue_free()

	var host_can_invite: bool = SteamManager.is_host and SteamManager.steam_ready
	friends_title.visible = host_can_invite
	friends_list.get_parent().visible = host_can_invite
	invite_note_label.visible = host_can_invite
	if not host_can_invite:
		return

	var online_friends: Array[Dictionary] = SteamManager.get_online_friends()
	if online_friends.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No online Steam friends available to invite."
		friends_list.add_child(empty_label)
		return

	for friend in online_friends:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = str(friend.get("name", "Unknown"))
		row.add_child(name_label)

		var status_label := Label.new()
		var friend_id: int = int(friend.get("steam_id", 0))
		var friend_status := SteamManager.get_friend_status(friend_id)
		status_label.text = friend_status
		status_label.custom_minimum_size = Vector2(80, 0)
		row.add_child(status_label)

		var invite_button := Button.new()
		invite_button.text = "Invite"
		invite_button.disabled = friend_status != "Online"
		if friend_status == "Invited":
			invite_button.text = "Invited"
		elif friend_status == "In Lobby":
			invite_button.text = "Joined"
		invite_button.pressed.connect(_on_invite_friend_pressed.bind(friend_id))
		row.add_child(invite_button)

		friends_list.add_child(row)

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_start_button_pressed() -> void:
	GameManager.start_match()

func _on_invite_friend_pressed(friend_steam_id: int) -> void:
	if friend_steam_id > 0:
		SteamManager.invite_friend_to_lobby(friend_steam_id)
	_refresh_online_friends()

func _on_refresh_timer_timeout() -> void:
	_refresh_player_list(0)
