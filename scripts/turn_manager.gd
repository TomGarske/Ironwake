extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal turn_started(player_id: int)
signal turn_ended(player_id: int)
signal match_over(winner_id: int)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var player_ids: Array = []
var current_turn_index: int = 0
var current_player_id: int = 0

# ---------------------------------------------------------------------------
# Setup (called by host after spawning all units)
# ---------------------------------------------------------------------------
func setup(ids: Array) -> void:
	player_ids = ids
	current_turn_index = 0
	current_player_id = player_ids[0]
	# Broadcast the first turn start to all peers
	_broadcast_turn_start.rpc(current_player_id)
	print("[TurnManager] Match started. First turn: peer %d" % current_player_id)

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func get_current_player() -> int:
	return current_player_id

func is_my_turn() -> bool:
	return multiplayer.get_unique_id() == current_player_id

# ---------------------------------------------------------------------------
# End turn — client sends request; host advances
# ---------------------------------------------------------------------------
func end_turn() -> void:
	if not is_my_turn():
		return
	if multiplayer.is_server():
		_advance_turn()
	else:
		_request_end_turn.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_end_turn() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == current_player_id:
		_advance_turn()

# ---------------------------------------------------------------------------
# Turn advancement (host only)
# ---------------------------------------------------------------------------
func _advance_turn() -> void:
	turn_ended.emit(current_player_id)
	current_turn_index = (current_turn_index + 1) % player_ids.size()
	current_player_id = player_ids[current_turn_index]
	_broadcast_turn_start.rpc(current_player_id)
	print("[TurnManager] Turn advanced to peer %d" % current_player_id)

@rpc("authority", "call_local", "reliable")
func _broadcast_turn_start(player_id: int) -> void:
	current_player_id = player_id
	turn_started.emit(player_id)

# ---------------------------------------------------------------------------
# Match over (host declares winner)
# ---------------------------------------------------------------------------
func declare_match_over(winner_id: int) -> void:
	if multiplayer.is_server():
		_broadcast_match_over.rpc(winner_id)

@rpc("authority", "call_local", "reliable")
func _broadcast_match_over(winner_id: int) -> void:
	match_over.emit(winner_id)
	print("[TurnManager] Match over. Winner peer: %d" % winner_id)

## Public shortcut for offline/test mode — bypasses the is_my_turn() check.
func force_advance_turn() -> void:
	if multiplayer.is_server():
		_advance_turn()
