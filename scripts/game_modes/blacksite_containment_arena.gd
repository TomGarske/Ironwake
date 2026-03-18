extends "res://scripts/iso_arena.gd"

# Blacksite Containment starts from the legacy Iso Arena baseline.
# This duplicate entry script lets us evolve mode-specific gameplay
# without touching the original iso arena implementation.

const _LOCAL_MP_ARG_MODE := "--local-mp="
const _LOCAL_MP_ARG_PORT := "--local-mp-port="
const _LOCAL_MP_ARG_HOST := "--local-mp-host="
const _LOCAL_MP_ARG_AUTOTEST := "--local-mp-autotest"
const _LOCAL_MP_ARG_AUTOTEST_QUIT := "--local-mp-autotest-quit"
const _DEFAULT_LOCAL_MP_PORT: int = 29777
const _DEFAULT_LOCAL_MP_HOST: String = "127.0.0.1"

var _local_mp_mode: String = ""
var _local_mp_port: int = _DEFAULT_LOCAL_MP_PORT
var _local_mp_host: String = _DEFAULT_LOCAL_MP_HOST
var _local_mp_enabled: bool = false
var _local_mp_autotest: bool = false
var _local_mp_autotest_quit: bool = false
var _local_mp_connected: bool = false

func _ready() -> void:
	_parse_local_mp_args()
	_bootstrap_local_mp_if_requested()
	super._ready()
	if _local_mp_enabled:
		_attach_local_mp_hooks()
		_add_local_status_message(
			"[LocalMP] %s mode on %s:%d" % [_local_mp_mode, _local_mp_host, _local_mp_port]
		)

func _parse_local_mp_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with(_LOCAL_MP_ARG_MODE):
			_local_mp_mode = arg.trim_prefix(_LOCAL_MP_ARG_MODE).strip_edges().to_lower()
		elif arg.begins_with(_LOCAL_MP_ARG_PORT):
			_local_mp_port = int(arg.trim_prefix(_LOCAL_MP_ARG_PORT))
		elif arg.begins_with(_LOCAL_MP_ARG_HOST):
			_local_mp_host = arg.trim_prefix(_LOCAL_MP_ARG_HOST).strip_edges()
		elif arg == _LOCAL_MP_ARG_AUTOTEST:
			_local_mp_autotest = true
		elif arg == _LOCAL_MP_ARG_AUTOTEST_QUIT:
			_local_mp_autotest_quit = true
	if _local_mp_port <= 0:
		_local_mp_port = _DEFAULT_LOCAL_MP_PORT
	if _local_mp_host.is_empty():
		_local_mp_host = _DEFAULT_LOCAL_MP_HOST
	_local_mp_enabled = _local_mp_mode == "host" or _local_mp_mode == "client"

func _bootstrap_local_mp_if_requested() -> void:
	if not _local_mp_enabled:
		return
	var peer := ENetMultiplayerPeer.new()
	if _local_mp_mode == "host":
		var create_server_result: int = peer.create_server(_local_mp_port, 8)
		if create_server_result != OK:
			push_error("[LocalMP] Failed to create server: %d" % create_server_result)
			_local_mp_enabled = false
			return
		_local_mp_connected = true
		multiplayer.multiplayer_peer = peer
		print("[LocalMP] Host server listening on port %d" % _local_mp_port)
		return
	var create_client_result: int = peer.create_client(_local_mp_host, _local_mp_port)
	if create_client_result != OK:
		push_error("[LocalMP] Failed to create client: %d" % create_client_result)
		_local_mp_enabled = false
		return
	multiplayer.multiplayer_peer = peer
	print("[LocalMP] Client connecting to %s:%d" % [_local_mp_host, _local_mp_port])

func _attach_local_mp_hooks() -> void:
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.peer_connected.is_connected(_on_local_mp_peer_connected):
			multiplayer.peer_connected.connect(_on_local_mp_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_local_mp_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_local_mp_peer_disconnected)
		if not multiplayer.connected_to_server.is_connected(_on_local_mp_connected_to_server):
			multiplayer.connected_to_server.connect(_on_local_mp_connected_to_server)
		if not multiplayer.connection_failed.is_connected(_on_local_mp_connection_failed):
			multiplayer.connection_failed.connect(_on_local_mp_connection_failed)
		if not multiplayer.server_disconnected.is_connected(_on_local_mp_server_disconnected):
			multiplayer.server_disconnected.connect(_on_local_mp_server_disconnected)
	if _local_mp_mode == "host":
		_rebuild_players_for_local_mp()
		if _local_mp_autotest:
			_run_local_mp_autotest_host()

func _on_local_mp_connected_to_server() -> void:
	_local_mp_connected = true
	print("[LocalMP] Client connected to server.")
	_add_local_status_message("[LocalMP] Connected to host.")
	_rebuild_players_for_local_mp()
	if _local_mp_autotest:
		_run_local_mp_autotest_client()

func _on_local_mp_connection_failed() -> void:
	_local_mp_connected = false
	push_error("[LocalMP] Client failed to connect.")
	_add_local_status_message("[LocalMP] Connection failed.")

func _on_local_mp_server_disconnected() -> void:
	_local_mp_connected = false
	_add_local_status_message("[LocalMP] Server disconnected.")

func _on_local_mp_peer_connected(peer_id: int) -> void:
	if not _local_mp_enabled:
		return
	print("[LocalMP] Peer connected: %d" % peer_id)
	_add_local_status_message("[LocalMP] Peer %d joined." % peer_id)
	_rebuild_players_for_local_mp()
	if _local_mp_mode == "host" and _local_mp_autotest:
		_run_local_mp_autotest_host()

func _on_local_mp_peer_disconnected(peer_id: int) -> void:
	if not _local_mp_enabled:
		return
	print("[LocalMP] Peer disconnected: %d" % peer_id)
	_add_local_status_message("[LocalMP] Peer %d left." % peer_id)
	_rebuild_players_for_local_mp()

func _rebuild_players_for_local_mp() -> void:
	_players.clear()
	_my_index = 0
	_winner = -2
	_end_timer = 0.0
	_spawn_players()
	queue_redraw()

func _run_local_mp_autotest_host() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.get_peers().is_empty():
		return
	var success := _players.size() >= 2
	print("[LocalMP-Test] Host roster size=%d success=%s" % [_players.size(), str(success)])
	_add_local_status_message("[LocalMP-Test] Host ready: players=%d" % _players.size())
	if success and _local_mp_autotest_quit:
		get_tree().quit(0)

func _run_local_mp_autotest_client() -> void:
	var success := _players.size() >= 2
	print("[LocalMP-Test] Client roster size=%d success=%s" % [_players.size(), str(success)])
	_add_local_status_message("[LocalMP-Test] Client ready: players=%d" % _players.size())
	if success and _local_mp_autotest_quit:
		get_tree().quit(0)

func _add_local_status_message(message: String) -> void:
	_status_messages.append({
		"text": message,
		"time_left": 8.0
	})
