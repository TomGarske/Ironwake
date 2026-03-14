extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var steam_id: int = 0
var steam_username: String = ""
var lobby_id: int = 0
var is_host: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	var init_result: Dictionary = Steam.steamInit()
	if init_result["status"] != Steam.STEAM_API_INIT_RESULT_OK:
		push_error("[SteamManager] Steam failed to init: " + str(init_result["verbal"]))
		get_tree().quit()
		return

	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
	print("[SteamManager] Initialized. User: %s (%d)" % [steam_username, steam_id])

	# Connect Steamworks signals
	Steam.lobby_created.connect(_on_steam_lobby_created)
	Steam.lobby_joined.connect(_on_steam_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)

func _process(_delta: float) -> void:
	# Must be called every frame to dispatch Steam callbacks
	Steam.run_callbacks()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func host_lobby() -> void:
	is_host = true
	# LOBBY_TYPE_PUBLIC so others can find it; max 4 players per spec
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)

func join_lobby(target_lobby_id: int) -> void:
	is_host = false
	Steam.joinLobby(target_lobby_id)

# ---------------------------------------------------------------------------
# Steam callbacks
# ---------------------------------------------------------------------------
func _on_steam_lobby_created(result: int, new_lobby_id: int) -> void:
	if result == 1:
		lobby_id = new_lobby_id
		Steam.setLobbyData(lobby_id, "name", steam_username + "'s Lobby")
		Steam.setLobbyData(lobby_id, "game", "BurnBridgers")
		_setup_multiplayer_peer()
		lobby_created.emit(lobby_id)
		print("[SteamManager] Lobby created: %d" % lobby_id)
	else:
		push_error("[SteamManager] Failed to create lobby. Result: " + str(result))

func _on_steam_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_id = joined_lobby_id
		_setup_multiplayer_peer()
		lobby_joined.emit(lobby_id)
		print("[SteamManager] Joined lobby: %d" % lobby_id)
	else:
		push_error("[SteamManager] Failed to join lobby. Response: " + str(response))

func _on_lobby_chat_update(_updated_lobby: int, changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	print("[SteamManager] Lobby member update for Steam ID: %d" % changed_id)

# ---------------------------------------------------------------------------
# Multiplayer peer setup
# ---------------------------------------------------------------------------
func _setup_multiplayer_peer() -> void:
	var peer := SteamMultiplayerPeer.new()

	if is_host:
		peer.create_host(0)
		# Register host immediately — peer_id 1 is always the server
		GameManager.players[1] = {
			"steam_id": steam_id,
			"username": steam_username,
			"team": 0
		}
	else:
		var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
		peer.create_client(host_steam_id, 0)

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[SteamManager] Multiplayer peer ready. is_host=%s" % str(is_host))

func _on_peer_connected(peer_id: int) -> void:
	print("[SteamManager] Peer connected: %d" % peer_id)
	peer_connected.emit(peer_id)
	# Clients register themselves with the host when connection is established
	if not is_host:
		GameManager.register_player_rpc.rpc_id(1, steam_id, steam_username)

func _on_peer_disconnected(peer_id: int) -> void:
	print("[SteamManager] Peer disconnected: %d" % peer_id)
	peer_disconnected.emit(peer_id)
