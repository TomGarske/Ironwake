extends Node2D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const UNIT_SCENE: PackedScene = preload("res://scenes/game/unit.tscn")
const TILE_SIZE: int = 64
const GRID_WIDTH: int = 10
const GRID_HEIGHT: int = 10

## Starting grid positions per team index
const TEAM_STARTS: Dictionary = {
	0: [Vector2i(1, 1), Vector2i(2, 1)],
	1: [Vector2i(7, 8), Vector2i(8, 8)]
}

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var turn_manager: Node = $TurnManager
@onready var overlay: Node2D = $Overlay
@onready var status_label: Label = $UI/StatusLabel
@onready var end_turn_button: Button = $UI/EndTurnButton

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
## unit_id (int) -> Unit node
var units: Dictionary = {}
var unit_counter: int = 0

## Selection / input
enum InputState { IDLE, UNIT_SELECTED }
var input_state: InputState = InputState.IDLE
var selected_unit: Node = null
var valid_move_tiles: Array = []       # Array[Vector2i]
var valid_attack_positions: Array = [] # Array[Vector2i]

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.match_over.connect(_on_match_over)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	if multiplayer.is_server():
		_spawn_all_units()

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not _can_take_action():
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var gp := _screen_to_grid(get_local_mouse_position())
	_handle_grid_click(gp)

func _handle_grid_click(gp: Vector2i) -> void:
	if not _is_tile_in_bounds(gp):
		_deselect()
		return
	var clicked: Node = _get_unit_at(gp)
	match input_state:
		InputState.IDLE:
			if clicked and _is_my_unit(clicked):
				if not clicked.has_moved or not clicked.has_attacked:
					_select_unit(clicked)
		InputState.UNIT_SELECTED:
			if clicked == selected_unit:
				_deselect()
			elif clicked and _is_my_unit(clicked):
				_select_unit(clicked)
			elif valid_move_tiles.has(gp):
				_handle_move(selected_unit.unit_id, gp)
				_deselect()
			elif clicked and valid_attack_positions.has(clicked.grid_pos):
				_handle_attack(selected_unit.unit_id, clicked.unit_id)
				_deselect()
			else:
				_deselect()

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
func _select_unit(unit: Node) -> void:
	selected_unit = unit
	input_state = InputState.UNIT_SELECTED
	_calculate_valid_tiles()
	_update_overlay()

func _deselect() -> void:
	selected_unit = null
	input_state = InputState.IDLE
	valid_move_tiles.clear()
	valid_attack_positions.clear()
	_update_overlay()

func _calculate_valid_tiles() -> void:
	valid_move_tiles.clear()
	valid_attack_positions.clear()
	if selected_unit == null:
		return
	if not selected_unit.has_moved:
		for x in range(GRID_WIDTH):
			for y in range(GRID_HEIGHT):
				var pos := Vector2i(x, y)
				if selected_unit.can_move_to(pos) and not _is_cell_occupied(pos):
					valid_move_tiles.append(pos)
	if not selected_unit.has_attacked:
		for unit: Node in units.values():
			if unit.team != selected_unit.team and selected_unit.can_attack(unit.grid_pos):
				valid_attack_positions.append(unit.grid_pos)

func _update_overlay() -> void:
	overlay.selected_unit = selected_unit
	overlay.valid_move_tiles = valid_move_tiles
	overlay.valid_attack_positions = valid_attack_positions
	overlay.queue_redraw()

# ---------------------------------------------------------------------------
# Move — host-aware dispatch
# ---------------------------------------------------------------------------
func _handle_move(unit_id: int, target_pos: Vector2i) -> void:
	if multiplayer.is_server():
		_server_validate_move(turn_manager.get_current_player(), unit_id, target_pos)
	else:
		request_move.rpc_id(1, unit_id, target_pos)

@rpc("any_peer", "reliable")
func request_move(unit_id: int, target_pos: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	_server_validate_move(multiplayer.get_remote_sender_id(), unit_id, target_pos)

func _server_validate_move(sender_id: int, unit_id: int, target_pos: Vector2i) -> void:
	if sender_id != turn_manager.get_current_player():
		return
	var unit: Node = units.get(unit_id)
	if unit == null or not unit.can_move_to(target_pos):
		return
	if not _is_tile_in_bounds(target_pos) or _is_cell_occupied(target_pos):
		return
	apply_move.rpc(unit_id, target_pos)

@rpc("authority", "call_local", "reliable")
func apply_move(unit_id: int, target_pos: Vector2i) -> void:
	var unit: Node = units.get(unit_id)
	if unit:
		unit.move_to(target_pos)

# ---------------------------------------------------------------------------
# Attack — host-aware dispatch
# ---------------------------------------------------------------------------
func _handle_attack(attacker_id: int, target_id: int) -> void:
	if multiplayer.is_server():
		_server_validate_attack(turn_manager.get_current_player(), attacker_id, target_id)
	else:
		request_attack.rpc_id(1, attacker_id, target_id)

@rpc("any_peer", "reliable")
func request_attack(attacker_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_validate_attack(multiplayer.get_remote_sender_id(), attacker_id, target_id)

func _server_validate_attack(sender_id: int, attacker_id: int, target_id: int) -> void:
	if sender_id != turn_manager.get_current_player():
		return
	var attacker: Node = units.get(attacker_id)
	var target: Node = units.get(target_id)
	if attacker == null or target == null:
		return
	if attacker.team == target.team:
		return
	if not attacker.can_attack(target.grid_pos):
		return
	apply_attack.rpc(attacker_id, target_id, 1)

@rpc("authority", "call_local", "reliable")
func apply_attack(attacker_id: int, target_id: int, damage: int) -> void:
	var attacker: Node = units.get(attacker_id)
	var target: Node = units.get(target_id)
	if attacker:
		attacker.has_attacked = true
	if target:
		target.take_damage(damage)

# ---------------------------------------------------------------------------
# Unit spawning (host only)
# ---------------------------------------------------------------------------
func _spawn_all_units() -> void:
	for peer_id: int in GameManager.players:
		var team: int = GameManager.players[peer_id]["team"]
		for start_pos: Vector2i in TEAM_STARTS[team]:
			_host_spawn_unit(unit_counter, start_pos, team)
			unit_counter += 1
	turn_manager.setup(GameManager.players.keys())

func _host_spawn_unit(id: int, pos: Vector2i, team: int) -> void:
	_spawn_unit_local(id, pos, team)
	_sync_unit_spawn.rpc(id, pos, team)

@rpc("authority", "reliable")
func _sync_unit_spawn(id: int, pos: Vector2i, team: int) -> void:
	if multiplayer.is_server():
		return
	_spawn_unit_local(id, pos, team)

func _spawn_unit_local(id: int, pos: Vector2i, team: int) -> void:
	var unit: Node = UNIT_SCENE.instantiate()
	add_child(unit)
	unit.setup(id, pos, team)
	unit.unit_died.connect(_on_unit_died)
	units[id] = unit

# ---------------------------------------------------------------------------
# Win condition
# ---------------------------------------------------------------------------
func _on_unit_died(unit_id: int) -> void:
	units.erase(unit_id)
	if multiplayer.is_server():
		_check_win_condition()

func _check_win_condition() -> void:
	var teams_alive: Array = []
	for unit: Node in units.values():
		if not teams_alive.has(unit.team):
			teams_alive.append(unit.team)
	if teams_alive.size() > 1:
		return
	var winner_team: int = teams_alive[0] if teams_alive.size() == 1 else -1
	for peer_id: int in GameManager.players:
		if GameManager.players[peer_id]["team"] == winner_team:
			turn_manager.declare_match_over(peer_id)
			return
	turn_manager.declare_match_over(-1)

# ---------------------------------------------------------------------------
# Turn / UI events
# ---------------------------------------------------------------------------
func _on_turn_started(player_id: int) -> void:
	for unit: Node in units.values():
		unit.reset_actions()
	_deselect()
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var username: String = player_data.get("username", "Opponent")
	if _can_take_action():
		# Offline test: show whose turn it is; online: show "Your Turn"
		if SteamManager.lobby_id == 0:
			status_label.text = "%s's Turn" % username
		else:
			status_label.text = "Your Turn!"
		end_turn_button.disabled = false
	else:
		status_label.text = "%s's Turn..." % username
		end_turn_button.disabled = true

func _on_match_over(winner_id: int) -> void:
	end_turn_button.disabled = true
	_deselect()
	if winner_id == -1:
		status_label.text = "Draw!"
	elif winner_id == multiplayer.get_unique_id():
		status_label.text = "Victory!"
	else:
		var winner_name: String = GameManager.players.get(winner_id, {}).get("username", "Opponent")
		status_label.text = "%s Wins!" % winner_name

func _on_end_turn_pressed() -> void:
	if not _can_take_action():
		return
	_deselect()
	# In offline mode, current_player_id may be peer 2 but get_unique_id() is always 1
	if SteamManager.lobby_id == 0 and not turn_manager.is_my_turn():
		turn_manager.force_advance_turn()
	else:
		turn_manager.end_turn()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _can_take_action() -> bool:
	# Offline test mode: always allow input (control both sides for testing)
	if SteamManager.lobby_id == 0:
		return true
	return turn_manager.is_my_turn()

func _is_my_unit(unit: Node) -> bool:
	# In offline mode, restrict to the CURRENT player's units so turns still alternate
	var check_id: int
	if SteamManager.lobby_id == 0:
		check_id = turn_manager.get_current_player()
	else:
		check_id = multiplayer.get_unique_id()
	for peer_id: int in GameManager.players:
		if GameManager.players[peer_id]["team"] == unit.team:
			return peer_id == check_id
	return false

func _get_unit_at(gp: Vector2i) -> Node:
	for unit: Node in units.values():
		if unit.grid_pos == gp:
			return unit
	return null

func _screen_to_grid(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(local_pos.x / TILE_SIZE)), int(floor(local_pos.y / TILE_SIZE)))

func _is_tile_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT

func _is_cell_occupied(pos: Vector2i) -> bool:
	for unit: Node in units.values():
		if unit.grid_pos == pos:
			return true
	return false
