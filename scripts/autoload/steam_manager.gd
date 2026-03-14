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

const _RESULT_OK: int = 1
const _LOBBY_TYPE_PUBLIC: int = 2
const _CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const _FRIEND_FLAG_IMMEDIATE: int = 4
const _PERSONA_STATE_OFFLINE: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		var extension_path := "res://addons/godotsteam/godotsteam.gdextension"
		if FileAccess.file_exists(extension_path):
			var load_status: int = GDExtensionManager.load_extension(extension_path)
			_emit_debug("[SteamManager] Attempted to load GodotSteam extension. Status: %d" % load_status, false)
		else:
			_emit_debug("[SteamManager] GodotSteam extension file missing at %s" % extension_path, true)
			return
	if not Engine.has_singleton("Steam"):
		_emit_debug("[SteamManager] Steam singleton not available after loading extension. Check GodotSteam/Godot version compatibility.", true)
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
		_emit_debug("[SteamManager] Steam failed to init: " + verbal + " (status=" + str(status) + ")", true)
		return

	steam_id = int(_steam.call("getSteamID"))
	steam_username = str(_steam.call("getPersonaName"))
	steam_ready = true
	_emit_debug("[SteamManager] Initialized. User: %s (%d)" % [steam_username, steam_id], false)

	# Connect Steamworks signals
	_steam.connect("lobby_created", Callable(self, "_on_steam_lobby_created"))
	_steam.connect("lobby_joined", Callable(self, "_on_steam_lobby_joined"))
	_steam.connect("lobby_chat_update", Callable(self, "_on_lobby_chat_update"))

func _process(_delta: float) -> void:
	# Must be called every frame to dispatch Steam callbacks
	if steam_ready and _steam != null:
		_steam.call("run_callbacks")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func host_lobby() -> void:
	if not steam_ready:
		_emit_debug("[SteamManager] Cannot host lobby: Steam is not initialized.", true)
		return

	# Reset existing state so repeated Host attempts are reliable.
	if lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
		lobby_id = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	is_host = true
	_emit_debug("[SteamManager] Creating lobby...", false)
	# LOBBY_TYPE_PUBLIC so others can find it; max 4 players per spec
	_steam.call("createLobby", _LOBBY_TYPE_PUBLIC, 4)

func join_lobby(target_lobby_id: int) -> void:
	if not steam_ready:
		_emit_debug("[SteamManager] Cannot join lobby: Steam is not initialized.", true)
		return

	is_host = false
	_emit_debug("[SteamManager] Joining lobby %d..." % target_lobby_id, false)
	_steam.call("joinLobby", target_lobby_id)

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
	var friend_count: int = int(_steam.call("getFriendCount", _FRIEND_FLAG_IMMEDIATE))
	for i in range(friend_count):
		var friend_steam_id: int = int(_steam.call("getFriendByIndex", i, _FRIEND_FLAG_IMMEDIATE))
		if friend_steam_id == 0 or friend_steam_id == steam_id:
			continue
		var persona_state: int = int(_steam.call("getFriendPersonaState", friend_steam_id))
		if persona_state <= _PERSONA_STATE_OFFLINE:
			continue
		friends.append({
			"steam_id": friend_steam_id,
			"name": str(_steam.call("getFriendPersonaName", friend_steam_id)),
			"state": persona_state
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
		invited_friend_ids[friend_steam_id] = Time.get_unix_time_from_system()
		_emit_debug("[SteamManager] Invite sent to Steam ID %d." % friend_steam_id, false)
	else:
		_emit_debug("[SteamManager] Failed to invite Steam ID %d." % friend_steam_id, true)
	return ok

func get_friend_status(friend_steam_id: int) -> String:
	var member_ids: Array[int] = get_lobby_member_ids()
	if member_ids.has(friend_steam_id):
		return "In Lobby"
	if invited_friend_ids.has(friend_steam_id):
		return "Invited"
	return "Online"

# ---------------------------------------------------------------------------
# Steam callbacks
# ---------------------------------------------------------------------------
func _on_steam_lobby_created(result: int, new_lobby_id: int) -> void:
	if result == _RESULT_OK:
		lobby_id = new_lobby_id
		_steam.call("setLobbyData", lobby_id, "name", steam_username + "'s Lobby")
		_steam.call("setLobbyData", lobby_id, "game", "BurnBridgers")
		_setup_multiplayer_peer()
		lobby_created.emit(lobby_id)
		_emit_debug("[SteamManager] Lobby created: %d" % lobby_id, false)
	else:
		_emit_debug("[SteamManager] Failed to create lobby. Result: " + str(result), true)

func _on_steam_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == _CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# Hosts can receive a join callback for their own lobby after createLobby.
		# Avoid re-creating the multiplayer peer in that case.
		if is_host and joined_lobby_id == lobby_id and multiplayer.multiplayer_peer != null:
			_emit_debug("[SteamManager] Host received self-join callback; peer already active.", false)
			return
		lobby_id = joined_lobby_id
		_setup_multiplayer_peer()
		lobby_joined.emit(lobby_id)
		_emit_debug("[SteamManager] Joined lobby: %d" % lobby_id, false)
	else:
		_emit_debug("[SteamManager] Failed to join lobby. Response: " + str(response), true)

func _on_lobby_chat_update(_updated_lobby: int, changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	_emit_debug("[SteamManager] Lobby member update for Steam ID: %d" % changed_id, false)
	lobby_members_updated.emit()

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
