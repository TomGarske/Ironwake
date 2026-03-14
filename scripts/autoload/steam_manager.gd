extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal debug_message(message: String, is_error: bool)
signal lobby_members_updated()
signal invite_join_requested(lobby_id: int)
signal lobby_invite_received(friend_id: int, lobby_id: int)
signal handshake_status_updated(status_text: String)
signal avatar_texture_updated(steam_id: int)
signal lobby_list_updated(lobbies: Array)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var steam_id: int = 0
var steam_username: String = ""
var lobby_id: int = 0
var is_host: bool = false
var steam_ready: bool = false
var _steam: Object = null
var debug_history: Array[Dictionary] = []
var invited_friend_ids: Dictionary = {}
var local_ready: bool = false
var _handshake_row_text: String = "Join test handshake: Idle"
var _avatar_cache: Dictionary = {}
var _avatar_requests_in_flight: Dictionary = {}
var _pending_invite_notifications: Array[Dictionary] = []
var _active_invite_lobby_id: int = 0
var _invite_dialog: ConfirmationDialog = null
var _pending_join_lobby_id: int = 0
var _pending_host_request: bool = false
var _host_retry_count: int = 0
var _next_init_retry_at_ms: int = 0
var _next_host_retry_at_ms: int = 0
var _cached_public_lobbies: Array[Dictionary] = []

const _RESULT_OK: int = 1
const _LOBBY_TYPE_PUBLIC: int = 2
const _CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const _FRIEND_FLAG_IMMEDIATE: int = 4
const _PERSONA_STATE_OFFLINE: int = 0
const _AVATAR_MEDIUM: int = 2
const _INVITE_TIMEOUT_SECONDS: int = 45
const _INIT_RETRY_MS: int = 2500
const _HOST_RETRY_MS: int = 3000
const _MAX_HOST_RETRIES: int = 3
const _STEAM_EXTENSION_CANDIDATES: Array[String] = [
	"res://addons/godotsteam/godotsteam.gdextension",
	"res://addons/GodotSteam/godotsteam.gdextension",
	"res://addons/godotsteam/GodotSteam.gdextension",
	"res://addons/GodotSteam/GodotSteam.gdextension"
]

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_try_initialize_steam()

func _process(_delta: float) -> void:
	# Must be called every frame to dispatch Steam callbacks
	if steam_ready and _steam != null:
		_steam.call("run_callbacks")
		# Check if we have a pending host request that needs retry
		if _pending_host_request and _host_retry_count < _MAX_HOST_RETRIES:
			var now_ms: int = Time.get_ticks_msec()
			if now_ms >= _next_host_retry_at_ms:
				_emit_debug("[SteamManager] Retrying host lobby (attempt %d/%d)..." % [_host_retry_count + 1, _MAX_HOST_RETRIES], false)
				_attempt_create_lobby()
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms >= _next_init_retry_at_ms:
		_try_initialize_steam()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func host_lobby() -> void:
	if not steam_ready:
		_pending_host_request = true
		_host_retry_count = 0
		_emit_debug("[SteamManager] Steam not initialized yet. Queueing host request and retrying init...", false)
		_try_initialize_steam()
		return

	# Reset existing state so repeated Host attempts are reliable.
	if lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
		lobby_id = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	_pending_host_request = false
	_host_retry_count = 0
	is_host = true
	_attempt_create_lobby()

func _attempt_create_lobby() -> void:
	if not steam_ready or _steam == null:
		_pending_host_request = true
		_emit_debug("[SteamManager] Cannot create lobby: Steam is not initialized.", true)
		return
	
	# Ensure P2P relay is enabled before creating lobby (important for Steam Deck/Linux)
	if _steam.has_method("allowP2PPacketRelay"):
		_steam.call("allowP2PPacketRelay", true)
		_emit_debug("[SteamManager] Enabled P2P packet relay for lobby creation.", false)
	
	_emit_debug("[SteamManager] Creating lobby (platform: %s, App ID: %d)..." % [OS.get_name(), get_current_app_id()], false)
	# LOBBY_TYPE_PUBLIC so others can find it; max 4 players per spec
	_steam.call("createLobby", _LOBBY_TYPE_PUBLIC, 4)

func join_lobby(target_lobby_id: int) -> void:
	if not steam_ready:
		_pending_join_lobby_id = target_lobby_id
		_emit_debug("[SteamManager] Steam not initialized yet. Queueing join for lobby %d and retrying init..." % target_lobby_id, true)
		_try_initialize_steam()
		return

	is_host = false
	_emit_debug("[SteamManager] Joining lobby %d..." % target_lobby_id, false)
	_steam.call("joinLobby", target_lobby_id)

func request_burnbridgers_lobby_list() -> void:
	if not steam_ready or _steam == null:
		_emit_debug("[SteamManager] Cannot request lobby list yet: Steam is not initialized.", true)
		_cached_public_lobbies = []
		lobby_list_updated.emit(_cached_public_lobbies.duplicate(true))
		_try_initialize_steam()
		return

	# Ask Steam for public lobbies then filter to this game by lobby data.
	if _steam.has_method("addRequestLobbyListStringFilter"):
		# EQUAL comparison is 0 in Steam matchmaking string comparison enum.
		_steam.call("addRequestLobbyListStringFilter", "game", "BurnBridgers", 0)
	_steam.call("requestLobbyList")
	_emit_debug("[SteamManager] Requested BurnBridgers lobby list.", false)

func get_cached_public_lobbies() -> Array[Dictionary]:
	return _cached_public_lobbies.duplicate(true)

func get_lobby_member_names() -> Array[String]:
	var members: Array[String] = []
	if not steam_ready or _steam == null or lobby_id == 0:
		return members
	var member_count: int = int(_steam.call("getNumLobbyMembers", lobby_id))
	for i in range(member_count):
		var member_steam_id: int = int(_steam.call("getLobbyMemberByIndex", lobby_id, i))
		members.append(str(_steam.call("getFriendPersonaName", member_steam_id)))
	return members

func get_lobby_member_ids() -> Array[int]:
	var members: Array[int] = []
	if not steam_ready or _steam == null or lobby_id == 0:
		return members
	var member_count: int = int(_steam.call("getNumLobbyMembers", lobby_id))
	for i in range(member_count):
		var member_steam_id: int = int(_steam.call("getLobbyMemberByIndex", lobby_id, i))
		members.append(member_steam_id)
	return members

func get_online_friends() -> Array[Dictionary]:
	var friends: Array[Dictionary] = []
	if not steam_ready or _steam == null:
		return friends
	var member_ids: Array[int] = get_lobby_member_ids()
	var now: int = int(Time.get_unix_time_from_system())
	var friend_count: int = int(_steam.call("getFriendCount", _FRIEND_FLAG_IMMEDIATE))
	for i in range(friend_count):
		var friend_steam_id: int = int(_steam.call("getFriendByIndex", i, _FRIEND_FLAG_IMMEDIATE))
		if friend_steam_id == 0 or friend_steam_id == steam_id:
			continue
		var persona_state: int = int(_steam.call("getFriendPersonaState", friend_steam_id))
		if persona_state <= _PERSONA_STATE_OFFLINE:
			continue
		var game_app_id: int = 0
		if _steam.has_method("getFriendGamePlayed"):
			var game_played: Variant = _steam.call("getFriendGamePlayed", friend_steam_id)
			if game_played is Dictionary:
				game_app_id = int(game_played.get("id", 0))
		# Update invite handshake state machine.
		if invited_friend_ids.has(friend_steam_id):
			var info: Dictionary = invited_friend_ids[friend_steam_id]
			var state: String = str(info.get("state", "Invited"))
			var updated_at: int = int(info.get("updated_at", now))
			var elapsed: int = now - updated_at
			if member_ids.has(friend_steam_id) and state != "Joined":
				_set_invite_state(friend_steam_id, "Joined")
			elif state == "Invited" and game_app_id == get_current_app_id() and game_app_id != 0:
				_set_invite_state(friend_steam_id, "Accepted")
			elif state == "Accepted" and elapsed >= 2:
				_set_invite_state(friend_steam_id, "Joining")
			elif state != "Joined" and elapsed >= _INVITE_TIMEOUT_SECONDS:
				_set_invite_state(friend_steam_id, "Failed")
		friends.append({
			"steam_id": friend_steam_id,
			"name": str(_steam.call("getFriendPersonaName", friend_steam_id)),
			"state": persona_state,
			"game_app_id": game_app_id
		})
	return friends

func invite_friend_to_lobby(friend_steam_id: int) -> bool:
	if not steam_ready or _steam == null:
		_emit_debug("[SteamManager] Cannot invite: Steam is not initialized.", true)
		return false
	if not is_host or lobby_id == 0:
		_emit_debug("[SteamManager] Cannot invite: no active host lobby.", true)
		return false
	var ok: bool = bool(_steam.call("inviteUserToLobby", lobby_id, friend_steam_id))
	if ok:
		_set_invite_state(friend_steam_id, "Invited")
		_emit_debug("[SteamManager] Invite sent to Steam ID %d." % friend_steam_id, false)
	else:
		_emit_debug("[SteamManager] Failed to invite Steam ID %d." % friend_steam_id, true)
	return ok

func get_friend_status(friend_steam_id: int) -> String:
	var member_ids: Array[int] = get_lobby_member_ids()
	if member_ids.has(friend_steam_id):
		return "In Lobby"
	if invited_friend_ids.has(friend_steam_id):
		return str(invited_friend_ids[friend_steam_id].get("state", "Invited"))
	return "Online"

func set_local_ready_state(is_ready: bool) -> void:
	local_ready = is_ready
	if not steam_ready or _steam == null or lobby_id == 0:
		return
	_steam.call("setLobbyMemberData", lobby_id, "ready", "1" if is_ready else "0")
	lobby_members_updated.emit()
	_emit_debug("[SteamManager] Local ready set to %s." % str(is_ready), false)

func is_member_ready(member_steam_id: int) -> bool:
	if not steam_ready or _steam == null or lobby_id == 0:
		return false
	var value: String = str(_steam.call("getLobbyMemberData", lobby_id, member_steam_id, "ready"))
	return value == "1" or value.to_lower() == "true" or value.to_lower() == "yes"

func get_ready_counts() -> Dictionary:
	var member_ids: Array[int] = get_lobby_member_ids()
	var ready_count: int = 0
	for member_id in member_ids:
		if is_member_ready(member_id):
			ready_count += 1
	return {"ready": ready_count, "total": member_ids.size()}

func are_all_lobby_members_ready() -> bool:
	var counts: Dictionary = get_ready_counts()
	return int(counts.get("total", 0)) > 0 and int(counts.get("ready", 0)) == int(counts.get("total", 0))

func get_current_app_id() -> int:
	if steam_ready and _steam != null:
		return int(_steam.call("getAppID"))
	return 0

func get_handshake_status_row() -> String:
	return _handshake_row_text

func get_player_avatar_texture(target_steam_id: int) -> Texture2D:
	if _avatar_cache.has(target_steam_id):
		return _avatar_cache[target_steam_id]
	if not steam_ready or _steam == null:
		return null
	if not _avatar_requests_in_flight.has(target_steam_id):
		_avatar_requests_in_flight[target_steam_id] = true
		_steam.call("getPlayerAvatar", _AVATAR_MEDIUM, target_steam_id)
	return null

# ---------------------------------------------------------------------------
# Steam callbacks
# ---------------------------------------------------------------------------
func _on_steam_lobby_created(result: int, new_lobby_id: int) -> void:
	if result == _RESULT_OK:
		_pending_host_request = false
		_host_retry_count = 0
		lobby_id = new_lobby_id
		_steam.call("setLobbyData", lobby_id, "name", steam_username + "'s Lobby")
		_steam.call("setLobbyData", lobby_id, "game", "BurnBridgers")
		_steam.call("setLobbyData", lobby_id, "platform", OS.get_name())
		if _steam.has_method("setLobbyJoinable"):
			_steam.call("setLobbyJoinable", lobby_id, true)
		_setup_multiplayer_peer()
		set_local_ready_state(false)
		lobby_created.emit(lobby_id)
		_emit_debug("[SteamManager] Lobby created successfully: %d" % lobby_id, false)
	else:
		var error_msg: String = _get_steam_result_error(result)
		_emit_debug("[SteamManager] Failed to create lobby. Result code: %d (%s)" % [result, error_msg], true)
		
		# Retry logic for transient failures
		if _host_retry_count < _MAX_HOST_RETRIES:
			_host_retry_count += 1
			_next_host_retry_at_ms = Time.get_ticks_msec() + _HOST_RETRY_MS
			_pending_host_request = true
			_emit_debug("[SteamManager] Will retry lobby creation in %d ms (attempt %d/%d)..." % [_HOST_RETRY_MS, _host_retry_count, _MAX_HOST_RETRIES], false)
		else:
			_pending_host_request = false
			_host_retry_count = 0
			is_host = false
			_emit_debug("[SteamManager] Lobby creation failed after %d attempts. Please check Steam connection and try again." % _MAX_HOST_RETRIES, true)

func _on_steam_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == _CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# Hosts can receive a join callback for their own lobby after createLobby.
		# Avoid re-creating the multiplayer peer in that case.
		if is_host and joined_lobby_id == lobby_id and multiplayer.multiplayer_peer != null:
			_emit_debug("[SteamManager] Host received self-join callback; peer already active.", false)
			return
		lobby_id = joined_lobby_id
		_setup_multiplayer_peer()
		set_local_ready_state(false)
		lobby_joined.emit(lobby_id)
		_emit_debug("[SteamManager] Joined lobby: %d" % lobby_id, false)
	else:
		_emit_debug("[SteamManager] Failed to join lobby. Response: " + str(response), true)

func _on_lobby_chat_update(_updated_lobby: int, changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if invited_friend_ids.has(changed_id) and get_lobby_member_ids().has(changed_id):
		_set_invite_state(changed_id, "Joined")
	_emit_debug("[SteamManager] Lobby member update for Steam ID: %d" % changed_id, false)
	lobby_members_updated.emit()

func _on_lobby_invite(friend_id: int, invited_lobby_id: int, _game_id: int) -> void:
	var friend_name: String = "Steam ID %d" % friend_id
	if steam_ready and _steam != null:
		friend_name = str(_steam.call("getFriendPersonaName", friend_id))
	_emit_debug("[SteamManager] Lobby invite received from %s for lobby %d." % [friend_name, invited_lobby_id], false)
	lobby_invite_received.emit(friend_id, invited_lobby_id)
	_enqueue_invite_notification(friend_name, invited_lobby_id)

func _on_lobby_match_list(lobbies: Variant) -> void:
	var lobby_ids: Array = []
	if lobbies is Array:
		lobby_ids = lobbies
	elif lobbies is int:
		var count: int = int(lobbies)
		if _steam != null and _steam.has_method("getLobbyByIndex"):
			for i in range(count):
				lobby_ids.append(_steam.call("getLobbyByIndex", i))
		else:
			_emit_debug("[SteamManager] lobby_match_list returned count=%d but getLobbyByIndex is unavailable." % count, true)
			lobby_list_updated.emit(_cached_public_lobbies.duplicate(true))
			return
	else:
		_emit_debug("[SteamManager] Unexpected lobby_match_list payload type: %s" % [typeof(lobbies)], true)
		lobby_list_updated.emit(_cached_public_lobbies.duplicate(true))
		return

	var filtered: Array[Dictionary] = []
	for entry in lobby_ids:
		var lobby_id: int = int(entry)
		if lobby_id == 0:
			continue
		var game_name: String = str(_steam.call("getLobbyData", lobby_id, "game"))
		if game_name != "BurnBridgers":
			continue
		var lobby_name: String = str(_steam.call("getLobbyData", lobby_id, "name"))
		if lobby_name.strip_edges().is_empty():
			lobby_name = "BurnBridgers Lobby"
		var member_count: int = int(_steam.call("getNumLobbyMembers", lobby_id))
		filtered.append({
			"lobby_id": lobby_id,
			"name": lobby_name,
			"members": member_count
		})
	_cached_public_lobbies = filtered
	lobby_list_updated.emit(_cached_public_lobbies.duplicate(true))
	_emit_debug("[SteamManager] Lobby list updated (%d BurnBridgers lobbies)." % _cached_public_lobbies.size(), false)

func _on_game_lobby_join_requested(requested_lobby_id: int, friend_id: int) -> void:
	_emit_debug("[SteamManager] Invite accepted from Steam friend %d. Joining lobby %d..." % [friend_id, requested_lobby_id], false)
	_join_requested_lobby(requested_lobby_id)

func _on_avatar_loaded(user_id: int, avatar_size: int, avatar_buffer: PackedByteArray) -> void:
	_avatar_requests_in_flight.erase(user_id)
	if avatar_size <= 0 or avatar_buffer.is_empty():
		return
	var image: Image = Image.create_from_data(avatar_size, avatar_size, false, Image.FORMAT_RGBA8, avatar_buffer)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_avatar_cache[user_id] = texture
	avatar_texture_updated.emit(user_id)

# ---------------------------------------------------------------------------
# Multiplayer peer setup
# ---------------------------------------------------------------------------
func _setup_multiplayer_peer() -> void:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		_emit_debug("[SteamManager] SteamMultiplayerPeer class not found. Verify GodotSteam GDExtension install.", true)
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")

	if is_host:
		var host_result: int = int(peer.call("create_host", 0))
		if host_result != OK:
			_emit_debug("[SteamManager] Failed to create host peer. Error: %d" % host_result, true)
			return
		# Register host immediately — peer_id 1 is always the server
		GameManager.players[1] = {
			"steam_id": steam_id,
			"username": steam_username,
			"team": 0
		}
	else:
		var host_steam_id: int = int(_steam.call("getLobbyOwner", lobby_id))
		var client_result: int = int(peer.call("create_client", host_steam_id, 0))
		if client_result != OK:
			_emit_debug("[SteamManager] Failed to create client peer. Error: %d" % client_result, true)
			return

	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_emit_debug("[SteamManager] Multiplayer peer ready. is_host=%s" % str(is_host), false)

func _on_peer_connected(peer_id: int) -> void:
	_emit_debug("[SteamManager] Peer connected: %d" % peer_id, false)
	peer_connected.emit(peer_id)
	# Clients register themselves with the host when connection is established
	if not is_host:
		GameManager.register_player_rpc.rpc_id(1, steam_id, steam_username)

func _on_peer_disconnected(peer_id: int) -> void:
	_emit_debug("[SteamManager] Peer disconnected: %d" % peer_id, false)
	peer_disconnected.emit(peer_id)

func _emit_debug(message: String, is_error: bool) -> void:
	debug_history.append({
		"message": message,
		"is_error": is_error
	})
	if is_error:
		push_error(message)
	else:
		print(message)
	debug_message.emit(message, is_error)

func _set_invite_state(friend_steam_id: int, state: String) -> void:
	invited_friend_ids[friend_steam_id] = {
		"state": state,
		"updated_at": int(Time.get_unix_time_from_system())
	}
	var friend_name: String = "Steam ID %d" % friend_steam_id
	if steam_ready and _steam != null:
		friend_name = str(_steam.call("getFriendPersonaName", friend_steam_id))
	_handshake_row_text = "Join test handshake: %s -> %s" % [friend_name, state]
	handshake_status_updated.emit(_handshake_row_text)

func _enqueue_invite_notification(friend_name: String, invited_lobby_id: int) -> void:
	_pending_invite_notifications.append({
		"friend_name": friend_name,
		"lobby_id": invited_lobby_id
	})
	_show_next_invite_notification()

func _show_next_invite_notification() -> void:
	if _active_invite_lobby_id != 0:
		return
	if _pending_invite_notifications.is_empty():
		return
	var next_invite: Dictionary = _pending_invite_notifications.pop_front()
	_active_invite_lobby_id = int(next_invite.get("lobby_id", 0))
	var friend_name: String = str(next_invite.get("friend_name", "A friend"))
	if _active_invite_lobby_id <= 0:
		_active_invite_lobby_id = 0
		return
	_ensure_invite_dialog()
	if _invite_dialog == null:
		_emit_debug("[SteamManager] Invite popup unavailable. Use Steam overlay to accept invite.", true)
		return
	_invite_dialog.dialog_text = "%s invited you to lobby %d.\nJoin now?" % [friend_name, _active_invite_lobby_id]
	_invite_dialog.popup_centered_ratio(0.35)

func _ensure_invite_dialog() -> void:
	if is_instance_valid(_invite_dialog):
		return
	if get_tree() == null or get_tree().root == null:
		return
	_invite_dialog = ConfirmationDialog.new()
	_invite_dialog.title = "Lobby Invite"
	_invite_dialog.ok_button_text = "Join"
	_invite_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_invite_dialog.confirmed.connect(_on_invite_dialog_confirmed)
	_invite_dialog.canceled.connect(_on_invite_dialog_canceled)
	get_tree().root.add_child(_invite_dialog)

func _on_invite_dialog_confirmed() -> void:
	var target_lobby_id: int = _active_invite_lobby_id
	_active_invite_lobby_id = 0
	if target_lobby_id > 0:
		_join_requested_lobby(target_lobby_id)
	_show_next_invite_notification()

func _on_invite_dialog_canceled() -> void:
	_active_invite_lobby_id = 0
	_show_next_invite_notification()

func _join_requested_lobby(target_lobby_id: int) -> void:
	invite_join_requested.emit(target_lobby_id)
	# Reset current session state if needed before joining invite target.
	if lobby_id != 0 and lobby_id != target_lobby_id:
		_steam.call("leaveLobby", lobby_id)
		lobby_id = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	join_lobby(target_lobby_id)

func _try_initialize_steam() -> void:
	if steam_ready and _steam != null:
		return
	_next_init_retry_at_ms = Time.get_ticks_msec() + _INIT_RETRY_MS

	if not Engine.has_singleton("Steam"):
		var extension_path: String = _find_steam_extension_path()
		if FileAccess.file_exists(extension_path):
			var load_status: int = GDExtensionManager.load_extension(extension_path)
			_emit_debug("[SteamManager] Attempted to load GodotSteam extension (%s). Status: %d" % [extension_path, load_status], false)
		else:
			_emit_debug("[SteamManager] GodotSteam extension file missing. Checked: %s" % ", ".join(_STEAM_EXTENSION_CANDIDATES), true)
			return
	if not Engine.has_singleton("Steam"):
		_emit_debug("[SteamManager] Steam singleton not available after loading extension. Will retry.", true)
		_emit_steam_environment_hints()
		return

	_steam = Engine.get_singleton("Steam")
	var init_response: Variant = _steam.call("steamInit")
	var status: int = -1
	var verbal: String = ""
	var init_ok: bool = false
	if init_response is Dictionary:
		var init_result: Dictionary = init_response
		status = int(init_result.get("status", -1))
		verbal = str(init_result.get("verbal", ""))
		# GodotSteam status enums vary slightly by version; accept known OK values + verbal fallback.
		init_ok = status == 0 or status == 1 or verbal.to_upper().find("OK") != -1
	elif init_response is bool:
		init_ok = bool(init_response)
		status = 1 if init_ok else 0
		verbal = "steamInit() bool response"
	else:
		verbal = "Unexpected steamInit() response type: %s" % [typeof(init_response)]
	if not init_ok:
		_emit_debug("[SteamManager] Steam failed to init: " + verbal + " (status=" + str(status) + "). Will retry.", true)
		_emit_steam_environment_hints()
		return

	steam_id = int(_steam.call("getSteamID"))
	steam_username = str(_steam.call("getPersonaName"))
	steam_ready = true
	_emit_debug("[SteamManager] Initialized. User: %s (%d)" % [steam_username, steam_id], false)
	_emit_debug("[SteamManager] Runtime platform: %s, App ID: %d" % [OS.get_name(), get_current_app_id()], false)

	# Connect Steamworks signals once.
	if not _steam.is_connected("lobby_created", Callable(self, "_on_steam_lobby_created")):
		_steam.connect("lobby_created", Callable(self, "_on_steam_lobby_created"))
	if not _steam.is_connected("lobby_joined", Callable(self, "_on_steam_lobby_joined")):
		_steam.connect("lobby_joined", Callable(self, "_on_steam_lobby_joined"))
	if not _steam.is_connected("lobby_chat_update", Callable(self, "_on_lobby_chat_update")):
		_steam.connect("lobby_chat_update", Callable(self, "_on_lobby_chat_update"))
	if _steam.has_signal("lobby_match_list") and not _steam.is_connected("lobby_match_list", Callable(self, "_on_lobby_match_list")):
		_steam.connect("lobby_match_list", Callable(self, "_on_lobby_match_list"))
	if _steam.has_signal("lobby_invite") and not _steam.is_connected("lobby_invite", Callable(self, "_on_lobby_invite")):
		_steam.connect("lobby_invite", Callable(self, "_on_lobby_invite"))
	if _steam.has_signal("game_lobby_join_requested") and not _steam.is_connected("game_lobby_join_requested", Callable(self, "_on_game_lobby_join_requested")):
		_steam.connect("game_lobby_join_requested", Callable(self, "_on_game_lobby_join_requested"))
	if _steam.has_signal("avatar_loaded") and not _steam.is_connected("avatar_loaded", Callable(self, "_on_avatar_loaded")):
		_steam.connect("avatar_loaded", Callable(self, "_on_avatar_loaded"))
	# Favor Steam relay when available for better cross-OS/NAT compatibility.
	if _steam.has_method("allowP2PPacketRelay"):
		_steam.call("allowP2PPacketRelay", true)

	# If a user accepted an invite before init completed, finish that join now.
	if _pending_join_lobby_id > 0:
		var queued_lobby_id: int = _pending_join_lobby_id
		_pending_join_lobby_id = 0
		_emit_debug("[SteamManager] Resuming queued join for lobby %d after Steam init." % queued_lobby_id, false)
		join_lobby(queued_lobby_id)
	# If a host request was queued, attempt it now.
	if _pending_host_request:
		_emit_debug("[SteamManager] Resuming queued host request after Steam init.", false)
		host_lobby()
	# Refresh lobby browser data on successful init.
	request_burnbridgers_lobby_list()

func _find_steam_extension_path() -> String:
	for candidate in _STEAM_EXTENSION_CANDIDATES:
		if FileAccess.file_exists(candidate):
			return candidate
	# Fall back to canonical path for logs/errors.
	return _STEAM_EXTENSION_CANDIDATES[0]

func _emit_steam_environment_hints() -> void:
	var steam_app_id: String = OS.get_environment("SteamAppId")
	var steam_game_id: String = OS.get_environment("SteamGameId")
	_emit_debug("[SteamManager] Env SteamAppId=%s SteamGameId=%s" % [steam_app_id, steam_game_id], true)
	if OS.get_name() == "Linux":
		_emit_debug("[SteamManager] Linux/Steam Deck hint: launch from Steam client OR ensure steam_appid.txt exists next to the game binary when launching outside Steam.", true)

func _get_steam_result_error(result_code: int) -> String:
	# Common Steam API result codes (EResult enum)
	match result_code:
		1: return "OK"
		2: return "Fail"
		3: return "NoConnection"
		5: return "InvalidPassword"
		6: return "LoggedInElsewhere"
		7: return "InvalidProtocolVer"
		8: return "InvalidParam"
		9: return "FileNotFound"
		10: return "Busy"
		11: return "InvalidState"
		12: return "InvalidName"
		13: return "InvalidEmail"
		14: return "DuplicateName"
		15: return "AccessDenied"
		16: return "Timeout"
		17: return "Banned"
		18: return "AccountNotFound"
		19: return "InvalidSteamID"
		20: return "ServiceUnavailable"
		21: return "NotLoggedOn"
		22: return "Pending"
		23: return "EncryptionFailure"
		24: return "InsufficientPrivilege"
		25: return "LimitExceeded"
		26: return "Revoked"
		27: return "Expired"
		28: return "AlreadyRedeemed"
		29: return "DuplicateRequest"
		30: return "AlreadyOwned"
		31: return "IPNotFound"
		32: return "PersistFailed"
		33: return "LockingFailed"
		34: return "LogonSessionReplaced"
		35: return "ConnectFailed"
		36: return "HandshakeFailed"
		37: return "IOFailure"
		38: return "RemoteDisconnect"
		39: return "ShoppingCartNotFound"
		40: return "Blocked"
		41: return "Ignored"
		42: return "NoMatch"
		43: return "AccountDisabled"
		44: return "ServiceReadOnly"
		45: return "AccountNotFeatured"
		46: return "AdministratorOK"
		47: return "ContentVersion"
		48: return "TryAnotherCM"
		49: return "PasswordRequiredToKickSession"
		50: return "AlreadyLoggedInElsewhere"
		51: return "Suspended"
		52: return "Cancelled"
		53: return "DataCorruption"
		54: return "DiskFull"
		55: return "RemoteCallFailed"
		56: return "PasswordUnset"
		57: return "ExternalAccountUnlinked"
		58: return "PSNTicketInvalid"
		59: return "ExternalAccountAlreadyLinked"
		60: return "RemoteFileConflict"
		61: return "IllegalPassword"
		62: return "SameAsPreviousValue"
		63: return "AccountLogonDenied"
		64: return "CannotUseOldPassword"
		65: return "InvalidLoginAuthCode"
		66: return "AccountLoginDeniedNoMail"
		67: return "HardwareNotCapableOfIPT"
		68: return "IPTInitError"
		69: return "ParentalControlRestricted"
		70: return "FacebookQueryError"
		71: return "ExpiredLoginAuthCode"
		72: return "IPLoginRestrictionFailed"
		73: return "AccountLockedDown"
		74: return "AccountLogonDeniedVerifiedEmailRequired"
		75: return "NoMatchingURL"
		76: return "BadResponse"
		77: return "RequirePasswordReEntry"
		78: return "ValueOutOfRange"
		79: return "UnexpectedError"
		80: return "Disabled"
		81: return "InvalidCEGSubmission"
		82: return "RestrictedDevice"
		83: return "RegionLocked"
		84: return "RateLimitExceeded"
		85: return "AccountLoginDeniedNeedTwoFactor"
		86: return "ItemDeleted"
		87: return "AccountLoginDeniedThrottle"
		88: return "TwoFactorCodeMismatch"
		89: return "TwoFactorActivationCodeMismatch"
		90: return "AccountAssociatedToMultiplePartners"
		91: return "NotModified"
		92: return "NoMobileDevice"
		93: return "TimeNotSynced"
		94: return "SmsCodeFailed"
		95: return "AccountLimitExceeded"
		96: return "AccountActivityLimitExceeded"
		97: return "PhoneActivityLimitExceeded"
		98: return "RefundToWallet"
		99: return "EmailSendFailure"
		100: return "NotSettled"
		101: return "NeedCaptcha"
		102: return "GSLTDenied"
		103: return "GSOwnerDenied"
		104: return "InvalidItemType"
		105: return "IPBanned"
		106: return "GSLTExpired"
		107: return "InsufficientFunds"
		108: return "TooManyPending"
		109: return "NoSiteLicensesFound"
		110: return "WGNetworkSendExceeded"
		111: return "AccountNotFriends"
		112: return "LimitedUserAccount"
		113: return "CantRemoveItem"
		114: return "AccountDeleted"
		115: return "ExistingUserCancelledLicense"
		116: return "CommunityCooldown"
		117: return "NoLauncherSpecified"
		118: return "MustAgreeToSSA"
		119: return "LauncherMigrated"
		120: return "SteamRealmMismatch"
		121: return "InvalidSignature"
		122: return "ParseFailure"
		123: return "NoVerifiedPhone"
		124: return "InsufficientBattery"
		_: return "Unknown error code"
