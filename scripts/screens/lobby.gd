extends Control
const UiStyleScript := preload("res://scripts/ui/ui_style.gd")
const _FleetSpawner := preload("res://scripts/shared/fleet_spawner.gd")

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
# Left panel — config + actions
@onready var lobby_id_label: Label = $LobbyCard/MainHBox/LeftPanel/LobbyIdLabel
@onready var lobby_status_label: Label = $LobbyCard/MainHBox/LeftPanel/LobbyStatusLabel
@onready var game_mode_title_label: Label = $LobbyCard/MainHBox/LeftPanel/GameModeTitle
@onready var game_mode_selector: OptionButton = $LobbyCard/MainHBox/LeftPanel/GameModeSelector
@onready var game_mode_description_label: Label = $LobbyCard/MainHBox/LeftPanel/GameModeDescriptionLabel
@onready var ship_class_title: Label = $LobbyCard/MainHBox/LeftPanel/ShipClassTitle
@onready var ship_class_selector: OptionButton = $LobbyCard/MainHBox/LeftPanel/ShipClassSelector
@onready var ship_class_desc: Label = $LobbyCard/MainHBox/LeftPanel/ShipClassDesc
@onready var ready_button: CheckBox = $LobbyCard/MainHBox/LeftPanel/ReadyButton
@onready var start_button: Button = $LobbyCard/MainHBox/LeftPanel/StartButton
@onready var back_button: Button = $LobbyCard/MainHBox/LeftPanel/BackButton
# Center panel — crew roster
@onready var player_list: VBoxContainer = $LobbyCard/MainHBox/CenterPanel/PlayerList
@onready var handshake_status_label: Label = $LobbyCard/MainHBox/CenterPanel/HandshakeStatusLabel
# Right panel — invites
@onready var friends_title: Label = $LobbyCard/MainHBox/RightPanel/FriendsTitle
@onready var friends_list: VBoxContainer = $LobbyCard/MainHBox/RightPanel/FriendsScroll/FriendsList
@onready var invite_note_label: Label = $LobbyCard/MainHBox/RightPanel/InviteNoteLabel
@onready var refresh_timer: Timer = $RefreshTimer

var _lobby_members_updated_handler: Callable
var _friends_refresh_elapsed: float = 0.0
var _game_mode_ids: Array[String] = []

const _FRIENDS_REFRESH_INTERVAL: float = 6.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_refresh_crew_status()
	_apply_warm_tactical_theme()
	# Set visibility BEFORE configuring navigation so focus chains reflect actual visibility.
	start_button.visible = SteamManager.is_host
	game_mode_selector.disabled = not SteamManager.is_host
	_configure_navigation()
	start_button.disabled = true
	ready_button.text = "Ready"
	ready_button.button_pressed = SteamManager.local_ready
	ready_button.toggled.connect(_on_ready_toggled)
	if not game_mode_selector.item_selected.is_connected(_on_game_mode_selector_item_selected):
		game_mode_selector.item_selected.connect(_on_game_mode_selector_item_selected)
	if GameManager != null and not GameManager.selected_game_mode_changed.is_connected(_on_selected_game_mode_changed):
		GameManager.selected_game_mode_changed.connect(_on_selected_game_mode_changed)
	_setup_game_mode_selector()
	_setup_ship_class_selector()

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
		accept_event()

func _configure_navigation() -> void:
	ready_button.focus_mode = Control.FOCUS_ALL
	game_mode_selector.focus_mode = Control.FOCUS_ALL
	start_button.focus_mode = Control.FOCUS_ALL
	back_button.focus_mode = Control.FOCUS_ALL
	ready_button.focus_neighbor_bottom = ready_button.get_path_to(game_mode_selector)
	game_mode_selector.focus_neighbor_top = game_mode_selector.get_path_to(ready_button)
	game_mode_selector.focus_neighbor_bottom = game_mode_selector.get_path_to(start_button if start_button.visible else back_button)
	start_button.focus_neighbor_top = start_button.get_path_to(game_mode_selector)
	start_button.focus_neighbor_bottom = start_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(start_button if start_button.visible else game_mode_selector)
	(ready_button if ready_button.visible else back_button).grab_focus()

func _apply_warm_tactical_theme() -> void:
	UiStyleScript.style_title(lobby_id_label, 20)
	UiStyleScript.style_body(lobby_status_label)
	UiStyleScript.style_title(game_mode_title_label, 16)
	game_mode_selector.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
	game_mode_selector.add_theme_color_override("font_disabled_color", UiStyleScript.TEXT_MUTED)
	ship_class_selector.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
	UiStyleScript.style_body(game_mode_description_label, true)
	UiStyleScript.style_body(handshake_status_label, true)
	UiStyleScript.style_body(invite_note_label, true)
	UiStyleScript.style_title(friends_title, 16)
	if ship_class_title != null:
		UiStyleScript.style_title(ship_class_title, 16)
	UiStyleScript.style_button(ready_button)
	UiStyleScript.style_button(start_button)
	UiStyleScript.style_button(back_button)

func _exit_tree() -> void:
	if GameManager != null and GameManager.selected_game_mode_changed.is_connected(_on_selected_game_mode_changed):
		GameManager.selected_game_mode_changed.disconnect(_on_selected_game_mode_changed)
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
func _setup_game_mode_selector() -> void:
	_game_mode_ids.clear()
	game_mode_selector.clear()
	var modes: Array[Dictionary] = GameManager.get_game_modes()
	for mode in modes:
		if not bool(mode.get("enabled", true)):
			continue
		var mode_id: String = str(mode.get("id", ""))
		if mode_id.is_empty():
			continue
		_game_mode_ids.append(mode_id)
		var badge: String = str(mode.get("badge", "")).strip_edges()
		var label: String = str(mode.get("label", mode_id.capitalize()))
		if not badge.is_empty():
			label = "%s %s" % [badge, label]
		if mode_id != GameManager.DEFAULT_GAME_MODE_ID:
			label += " [WIP]"
		game_mode_selector.add_item(label)
	_on_selected_game_mode_changed(GameManager.selected_game_mode_id)

func _on_game_mode_selector_item_selected(index: int) -> void:
	if not SteamManager.is_host:
		return
	if index < 0 or index >= _game_mode_ids.size():
		return
	GameManager.set_selected_game_mode(_game_mode_ids[index])

func _on_selected_game_mode_changed(mode_id: String) -> void:
	var selected_idx: int = -1
	for i in range(_game_mode_ids.size()):
		if _game_mode_ids[i] == mode_id:
			selected_idx = i
			break
	if selected_idx >= 0:
		game_mode_selector.select(selected_idx)
	var mode: Dictionary = GameManager.get_selected_game_mode()
	var subtitle: String = str(mode.get("subtitle", "")).strip_edges()
	var mode_desc: String = str(mode.get("description", "No description yet."))
	if subtitle.is_empty():
		game_mode_description_label.text = mode_desc
	else:
		game_mode_description_label.text = "%s\n%s" % [subtitle, mode_desc]
	_update_ship_class_section_for_mode(mode_id)
	_refresh_crew_status()
	game_mode_selector.disabled = not SteamManager.is_host

func _setup_ship_class_selector() -> void:
	ship_class_selector.clear()
	for i in range(ShipClassConfig.CLASS_COUNT):
		ship_class_selector.add_item(ShipClassConfig.CLASS_NAMES[i])
	ship_class_selector.select(GameManager.local_ship_class)
	_update_ship_class_desc(GameManager.local_ship_class)
	if not ship_class_selector.item_selected.is_connected(_on_ship_class_selected):
		ship_class_selector.item_selected.connect(_on_ship_class_selected)

func _on_ship_class_selected(index: int) -> void:
	GameManager.set_local_ship_class(index)
	if str(GameManager.get_selected_game_mode().get("id", "")) != "fleet_battle":
		_update_ship_class_desc(index)

func _update_ship_class_desc(index: int) -> void:
	if ship_class_desc != null and index >= 0 and index < ShipClassConfig.CLASS_DESCRIPTIONS.size():
		ship_class_desc.text = ShipClassConfig.CLASS_DESCRIPTIONS[index]


func _fleet_battle_preview_text() -> String:
	var comp: Array = _FleetSpawner.DEFAULT_FLEET_COMPOSITION
	var galleys: int = 0
	var brigs: int = 0
	var schooners: int = 0
	for cls in comp:
		match int(cls):
			ShipClassConfig.ShipClass.GALLEY:
				galleys += 1
			ShipClassConfig.ShipClass.BRIG:
				brigs += 1
			ShipClassConfig.ShipClass.SCHOONER:
				schooners += 1
	var parts: PackedStringArray = []
	if galleys > 0:
		parts.append("%d Galley%s" % [galleys, " (flagship)" if galleys == 1 else "s"])
	if brigs > 0:
		parts.append("%d Brig%s" % [brigs, "s" if brigs != 1 else ""])
	if schooners > 0:
		parts.append("%d Schooner%s" % [schooners, "s" if schooners != 1 else ""])
	return "Your Fleet: " + " + ".join(parts)


func _update_ship_class_section_for_mode(mode_id: String) -> void:
	var is_fleet: bool = mode_id == "fleet_battle"
	if ship_class_title != null:
		ship_class_title.visible = not is_fleet
	if ship_class_selector != null:
		ship_class_selector.visible = not is_fleet
	if ship_class_desc == null:
		return
	if is_fleet:
		ship_class_desc.text = _fleet_battle_preview_text()
	else:
		_update_ship_class_desc(GameManager.local_ship_class)


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
		var row_panel := PanelContainer.new()
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStyleScript.style_panel(row_panel)
		player_list.add_child(row_panel)

		var row := HBoxContainer.new()
		row_panel.add_child(row)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", 8)

		row.add_child(_create_avatar_rect(member_id, 24))

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ready_icon: String = "\u2611" if SteamManager.is_member_ready(member_id) else "\u2610"
		var mode_id: String = str(GameManager.get_selected_game_mode().get("id", ""))
		var role_label: String
		if mode_id == "fleet_battle":
			role_label = "Fleet Cmdr"
		else:
			var cls: int = GameManager.get_ship_class_for_steam_id(member_id)
			role_label = ShipClassConfig.CLASS_NAMES[cls] if cls >= 0 and cls < ShipClassConfig.CLASS_COUNT else "Brig"
		label.text = "%s %s [%s]" % [ready_icon, member_name, role_label]
		UiStyleScript.style_body(label)
		row.add_child(label)

	var ready_counts: Dictionary = SteamManager.get_ready_counts()
	_refresh_crew_status()
	lobby_status_label.text = "Crew: %d/%d | Ready: %d/%d" % [member_count, GameConstants.MAX_PLAYERS, int(ready_counts.get("ready", 0)), int(ready_counts.get("total", 0))]
	ready_button.button_pressed = SteamManager.local_ready

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
	if app_id > 0:
		invite_note_label.text = "Invites appear as Ironwake (App ID %d)." % app_id
	else:
		invite_note_label.text = "Invites appear as Ironwake."

	var online_friends: Array[Dictionary] = SteamManager.get_online_friends()
	if online_friends.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No online friends available to invite."
		UiStyleScript.style_body(empty_label, true)
		friends_list.add_child(empty_label)
		return

	for friend in online_friends:
		var row_panel := PanelContainer.new()
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStyleScript.style_panel(row_panel)
		friends_list.add_child(row_panel)

		var row := HBoxContainer.new()
		row_panel.add_child(row)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)

		var friend_id: int = int(friend.get("steam_id", 0))
		row.add_child(_create_avatar_rect(friend_id, 20))

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = str(friend.get("name", "Unknown"))
		UiStyleScript.style_body(name_label)
		row.add_child(name_label)

		var friend_status := SteamManager.get_friend_status(friend_id)
		var has_invite_state: bool = SteamManager.invited_friend_ids.has(friend_id)
		var invite_state: SteamManager.InviteState = SteamManager.InviteState.INVITED
		if has_invite_state:
			invite_state = SteamManager.get_invite_state(friend_id)

		var invite_button := Button.new()
		invite_button.text = "Invite"
		UiStyleScript.style_button(invite_button)
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


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_start_button_pressed() -> void:
	GameManager.start_match()

func _on_invite_friend_pressed(friend_steam_id: int) -> void:
	if friend_steam_id > 0:
		SteamManager.invite_friend_to_lobby(friend_steam_id)
	_refresh_online_friends()

func _on_ready_toggled(toggled_on: bool) -> void:
	SteamManager.set_local_ready_state(toggled_on)
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
	get_tree().change_scene_to_file(GameManager.HOME_SCREEN_SCENE_PATH)

func _create_avatar_rect(steam_id: int, avatar_size: int) -> TextureRect:
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(avatar_size, avatar_size)
	avatar.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var texture: Texture2D = SteamManager.get_player_avatar_texture(steam_id)
	if texture != null:
		avatar.texture = texture
	else:
		avatar.modulate = Color(1, 1, 1, 0.35)
	return avatar

func _refresh_crew_status() -> void:
	if lobby_id_label == null:
		return
	var role_text: String = "Command Lead" if SteamManager.is_host else "Operative"
	var mode: Dictionary = GameManager.get_selected_game_mode()
	var mode_label: String = str(mode.get("label", "Unknown Mission"))
	lobby_id_label.text = "Crew Status: %s | %s" % [role_text, mode_label]
