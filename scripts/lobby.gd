extends Control

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var lobby_id_label: Label = $VBoxContainer/LobbyIdLabel
@onready var lobby_status_label: Label = $VBoxContainer/LobbyStatusLabel
@onready var player_list: VBoxContainer = $VBoxContainer/PlayerList
@onready var handshake_status_label: Label = $VBoxContainer/HandshakeStatusLabel
@onready var friends_title: Label = $VBoxContainer/FriendsTitle
@onready var friends_list: VBoxContainer = $VBoxContainer/FriendsScroll/FriendsList
@onready var invite_note_label: Label = $VBoxContainer/InviteNoteLabel
@onready var ready_button: Button = $VBoxContainer/ReadyButton
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var refresh_timer: Timer = $RefreshTimer

var _lobby_members_updated_handler: Callable
var _friends_refresh_elapsed: float = 0.0

const _FRIENDS_REFRESH_INTERVAL: float = 6.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	lobby_id_label.text = "Lobby ID: %d" % SteamManager.lobby_id
	_configure_navigation()

	# Only the host sees the Start button
	start_button.visible = SteamManager.is_host
	start_button.disabled = true
	ready_button.text = "Ready"
	ready_button.pressed.connect(_on_ready_button_pressed)

	# Refresh list when peers connect/disconnect
	SteamManager.peer_connected.connect(_refresh_player_list)
	SteamManager.peer_disconnected.connect(_refresh_player_list)
	_lobby_members_updated_handler = _refresh_player_list.bind(0)
	SteamManager.lobby_members_updated.connect(_lobby_members_updated_handler)
	SteamManager.handshake_status_updated.connect(_on_handshake_status_updated)
	SteamManager.avatar_texture_updated.connect(_on_avatar_texture_updated)

	refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	refresh_timer.start()

	handshake_status_label.text = SteamManager.get_handshake_status_row()
	_refresh_player_list(0)
	_refresh_online_friends()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave_lobby_and_return_to_menu()
		get_viewport().set_input_as_handled()

func _configure_navigation() -> void:
	ready_button.focus_neighbor_bottom = ready_button.get_path_to(start_button if start_button.visible else back_button)
	start_button.focus_neighbor_top = start_button.get_path_to(ready_button)
	start_button.focus_neighbor_bottom = start_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(start_button if start_button.visible else ready_button)
	(ready_button if ready_button.visible else back_button).grab_focus()

func _exit_tree() -> void:
	if SteamManager == null:
		return
	if SteamManager.peer_connected.is_connected(_refresh_player_list):
		SteamManager.peer_connected.disconnect(_refresh_player_list)
	if SteamManager.peer_disconnected.is_connected(_refresh_player_list):
		SteamManager.peer_disconnected.disconnect(_refresh_player_list)
	if _lobby_members_updated_handler.is_valid() and SteamManager.lobby_members_updated.is_connected(_lobby_members_updated_handler):
		SteamManager.lobby_members_updated.disconnect(_lobby_members_updated_handler)
	if SteamManager.handshake_status_updated.is_connected(_on_handshake_status_updated):
		SteamManager.handshake_status_updated.disconnect(_on_handshake_status_updated)
	if SteamManager.avatar_texture_updated.is_connected(_on_avatar_texture_updated):
		SteamManager.avatar_texture_updated.disconnect(_on_avatar_texture_updated)

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
	var member_ids: Array[int] = SteamManager.get_lobby_member_ids()
	var member_count: int = members.size()
	for i in range(member_count):
		var member_name: String = members[i]
		var member_id: int = member_ids[i] if i < member_ids.size() else 0
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_BEGIN

		row.add_child(_create_avatar_rect(member_id, 24))

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ready_text: String = "Ready" if SteamManager.is_member_ready(member_id) else "Not Ready"
		label.text = member_name + " (" + ready_text + ")"
		row.add_child(label)
		player_list.add_child(row)
	var ready_counts: Dictionary = SteamManager.get_ready_counts()
	lobby_status_label.text = "Lobby Members: %d/4 | Ready: %d/%d" % [member_count, int(ready_counts.get("ready", 0)), int(ready_counts.get("total", 0))]
	ready_button.text = "Unready" if SteamManager.local_ready else "Ready"

	# Host can only start when all currently joined lobby members are ready.
	start_button.disabled = not SteamManager.are_all_lobby_members_ready()

func _refresh_online_friends() -> void:
	for child in friends_list.get_children():
		child.queue_free()

	var host_can_invite: bool = SteamManager.is_host and SteamManager.steam_ready
	friends_title.visible = host_can_invite
	friends_list.get_parent().visible = host_can_invite
	invite_note_label.visible = host_can_invite
	if not host_can_invite:
		return

	var app_id: int = SteamManager.get_current_app_id()
	if app_id == 480:
		invite_note_label.text = "Invites currently appear as Spacewar (App ID 480). Set your BurnBridgers Steam App ID in steam_appid.txt."
	else:
		invite_note_label.text = "Invites should appear as BurnBridgers (App ID %d)." % app_id

	var online_friends: Array[Dictionary] = SteamManager.get_online_friends()
	var in_game_friends: Array[Dictionary] = []
	for friend in online_friends:
		var friend_game_app_id: int = int(friend.get("game_app_id", 0))
		if app_id > 0 and friend_game_app_id == app_id:
			in_game_friends.append(friend)

	if in_game_friends.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No friends currently in BurnBridgers."
		friends_list.add_child(empty_label)
		return

	for friend in in_game_friends:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var friend_id: int = int(friend.get("steam_id", 0))
		row.add_child(_create_avatar_rect(friend_id, 20))

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = str(friend.get("name", "Unknown"))
		row.add_child(name_label)

		var status_label := Label.new()
		var friend_status := SteamManager.get_friend_status(friend_id)
		var has_invite_state: bool = SteamManager.invited_friend_ids.has(friend_id)
		var invite_state: SteamManager.InviteState = SteamManager.InviteState.INVITED
		if has_invite_state:
			invite_state = SteamManager.get_invite_state(friend_id)
		status_label.text = friend_status
		status_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(status_label)

		var invite_button := Button.new()
		invite_button.text = "Invite"
		invite_button.disabled = friend_status == "In Lobby"
		if has_invite_state and invite_state == SteamManager.InviteState.INVITED:
			invite_button.text = "Reinvite"
		elif has_invite_state and invite_state == SteamManager.InviteState.ACCEPTED:
			invite_button.text = "Accepted"
		elif has_invite_state and invite_state == SteamManager.InviteState.JOINING:
			invite_button.text = "Joining"
		elif friend_status == "In Lobby":
			invite_button.text = "Joined"
		elif has_invite_state and invite_state == SteamManager.InviteState.FAILED:
			invite_button.text = "Retry Invite"
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

func _on_ready_button_pressed() -> void:
	SteamManager.set_local_ready_state(not SteamManager.local_ready)
	_refresh_player_list(0)

func _on_refresh_timer_timeout() -> void:
	_refresh_player_list(0)
	_friends_refresh_elapsed += refresh_timer.wait_time
	if _friends_refresh_elapsed >= _FRIENDS_REFRESH_INTERVAL:
		_friends_refresh_elapsed = 0.0
		_refresh_online_friends()

func _on_handshake_status_updated(status_text: String) -> void:
	handshake_status_label.text = status_text

func _on_avatar_texture_updated(_steam_id: int) -> void:
	_refresh_player_list(0)

func _on_back_button_pressed() -> void:
	_leave_lobby_and_return_to_menu()

func _leave_lobby_and_return_to_menu() -> void:
	DebugOverlay.log_message("[Lobby] Leaving lobby and returning to main menu...")
	
	# Clean up Steam lobby (this also closes multiplayer peer)
	if SteamManager != null:
		SteamManager.leave_lobby()
	
	# Reset game manager state
	GameManager.reset()
	
	# Return to main menu
	get_tree().change_scene_to_file(GameManager.MAIN_MENU_SCENE_PATH)

func _create_avatar_rect(steam_id: int, size: int) -> TextureRect:
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(size, size)
	avatar.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var texture: Texture2D = SteamManager.get_player_avatar_texture(steam_id)
	if texture != null:
		avatar.texture = texture
	else:
		avatar.modulate = Color(1, 1, 1, 0.35)
	return avatar
