extends Node

## Manages creature movement, pathfinding, placement, and autonomous explore behavior.

signal creature_selected(creature_id: String)

const SPAWN_HEX := Vector2i(90, 45)
const HOST_PEER_ID: int = 1

# Creature color palette — 8 distinct colors cycled in order of placement
const _COLOR_PALETTE: Array[Color] = [
	Color("#E63946"),  # red
	Color("#2A9D8F"),  # teal
	Color("#E9C46A"),  # gold
	Color("#6A4C93"),  # purple
	Color("#F4A261"),  # orange
	Color("#264653"),  # dark teal
	Color("#A8DADC"),  # light blue
	Color("#95D5B2"),  # mint
]

var _strategy_game: StrategyGame = null
var _selected_creature_id: String = ""
var _movement_queues: Dictionary = {}  # creature_id → Array[Vector2i]
var _explore_active: Dictionary = {}   # creature_id → bool
var _color_index: int = 0

func reset_runtime_state() -> void:
	_selected_creature_id = ""
	_movement_queues.clear()
	_explore_active.clear()
	_color_index = 0


func set_strategy_game(node: StrategyGame) -> void:
	_strategy_game = node

func _get_local_peer_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return HOST_PEER_ID

func _is_creature_controlled_by_peer(creature_id: String, peer_id: int) -> bool:
	var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
	if pdata.is_empty():
		return false
	var owner_peer_id: int = int(pdata.get("owner_peer_id", 0))
	if owner_peer_id <= 0:
		return true
	return owner_peer_id == peer_id

func _is_peer_turn(peer_id: int) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	if _strategy_game and _strategy_game.has_method("is_peer_turn"):
		return _strategy_game.is_peer_turn(peer_id)
	return peer_id == HOST_PEER_ID

func _is_local_turn() -> bool:
	return _is_peer_turn(_get_local_peer_id())


func on_hex_clicked(coords: Vector2i) -> void:
	# Check if any creature occupies this hex
	var occupants := HexOccupancyValidator.get_all_occupied_hexes()
	if coords in occupants:
		# Select the first creature on this hex
		var wedges := HexOccupancyValidator.get_wedge_layout(coords)
		if wedges.size() > 0:
			var selected_cid: String = ""
			if multiplayer.has_multiplayer_peer():
				var local_peer_id: int = _get_local_peer_id()
				for wedge: Dictionary in wedges:
					var cid: String = str(wedge.get("creature_id", ""))
					if _is_creature_controlled_by_peer(cid, local_peer_id):
						selected_cid = cid
						break
			else:
				selected_cid = str(wedges[0].get("creature_id", ""))
			_selected_creature_id = selected_cid
			if not selected_cid.is_empty():
				creature_selected.emit(selected_cid)
			return
	# Else queue movement for the selected creature
	if not _selected_creature_id.is_empty():
		if multiplayer.has_multiplayer_peer() and not _is_local_turn():
			return
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			request_queue_movement.rpc_id(HOST_PEER_ID, _selected_creature_id, coords)
			return
		_queue_movement_for_creature(_selected_creature_id, coords, _get_local_peer_id())

func _queue_movement_for_creature(creature_id: String, target_hex: Vector2i, controlling_peer_id: int = -1) -> void:
	var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
	if pdata.is_empty():
		_selected_creature_id = ""
		return
	if multiplayer.has_multiplayer_peer():
		var actor_peer_id: int = controlling_peer_id if controlling_peer_id > 0 else _get_local_peer_id()
		if not _is_creature_controlled_by_peer(creature_id, actor_peer_id):
			return
	var movement_types: Array[String] = []
	movement_types.assign(pdata.get("data", {}).get("movement_types", []))
	var from_hex: Vector2i = pdata.get("hex", SPAWN_HEX)
	var path := _a_star_path(from_hex, target_hex, movement_types)
	if path.size() > 1:
		_movement_queues[creature_id] = path.slice(1)  # exclude current hex

@rpc("any_peer", "call_local", "reliable")
func request_queue_movement(creature_id: String, target_hex: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	if not _is_peer_turn(sender_peer_id):
		return
	if not _is_creature_controlled_by_peer(creature_id, sender_peer_id):
		return
	_queue_movement_for_creature(creature_id, target_hex, sender_peer_id)


func advance_turn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_advance_turn.rpc_id(HOST_PEER_ID)
		return

	var moved_creatures: Dictionary = {}
	var removed_creatures: Dictionary = {}
	for creature_id: String in GameState.placed_creatures.keys():
		var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
		if pdata.is_empty():
			continue
		var cdata: Dictionary = pdata.get("data", {})
		var speed: int = int(cdata.get("movement_speed", 1))
		var movement_types: Array[String] = []
		movement_types.assign(cdata.get("movement_types", []))
		var current_hex: Vector2i = pdata.get("hex", SPAWN_HEX)
		var start_hex: Vector2i = current_hex

		var queue: Array = _movement_queues.get(creature_id, [])
		var steps_taken := 0
		while steps_taken < speed and queue.size() > 0:
			var next_hex: Vector2i = queue[0]
			if HexOccupancyValidator.can_move(creature_id, current_hex, next_hex, movement_types):
				HexOccupancyValidator.move_creature(creature_id, current_hex, next_hex)
				current_hex = next_hex
				queue.pop_front()
				GameState.placed_creatures[creature_id]["hex"] = current_hex
				# Apply terrain consequences
				var terrain := ""
				if _strategy_game:
					terrain = _strategy_game.get_terrain_at(current_hex)
				if not terrain.is_empty():
					TerrainMovementRules.apply_entry_consequences(creature_id, terrain)
				# Creature may have died
				if not GameState.placed_creatures.has(creature_id):
					queue.clear()
					removed_creatures[creature_id] = true
					break
				# Reveal fog
				var vision: int = int(cdata.get("vision", 3))
				if _strategy_game:
					_strategy_game.reveal_hexes(current_hex, vision)
				steps_taken += 1
			else:
				# Path is blocked — clear queue
				queue.clear()
				break
		_movement_queues[creature_id] = queue
		if GameState.placed_creatures.has(creature_id) and current_hex != start_hex:
			moved_creatures[creature_id] = current_hex

		# Re-evaluate explore after arriving
		if _explore_active.get(creature_id, false) and queue.is_empty():
			if GameState.placed_creatures.has(creature_id):
				var owner_peer_id: int = int(GameState.placed_creatures[creature_id].get("owner_peer_id", HOST_PEER_ID))
				start_explore(creature_id, owner_peer_id)

	# Refresh token display
	if _strategy_game:
		_strategy_game.refresh_creature_tokens()
		if _strategy_game.has_method("broadcast_creature_moved_delta"):
			for creature_id: String in moved_creatures.keys():
				_strategy_game.broadcast_creature_moved_delta(creature_id, moved_creatures[creature_id])
		if _strategy_game.has_method("broadcast_creature_removed_delta"):
			for creature_id: String in removed_creatures.keys():
				_strategy_game.broadcast_creature_removed_delta(creature_id)

@rpc("any_peer", "call_local", "reliable")
func request_advance_turn() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	if not _is_peer_turn(sender_peer_id):
		return
	advance_turn()


func start_explore(creature_id: String, controlling_peer_id: int = -1) -> void:
	if multiplayer.has_multiplayer_peer() and controlling_peer_id <= 0 and not _is_local_turn():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_start_explore.rpc_id(HOST_PEER_ID, creature_id)
		return
	if not GameState.placed_creatures.has(creature_id):
		return
	if multiplayer.has_multiplayer_peer():
		var actor_peer_id: int = controlling_peer_id if controlling_peer_id > 0 else _get_local_peer_id()
		if not _is_creature_controlled_by_peer(creature_id, actor_peer_id):
			return
	var pdata: Dictionary = GameState.placed_creatures[creature_id]
	var from_hex: Vector2i = pdata.get("hex", SPAWN_HEX)
	var movement_types: Array[String] = []
	movement_types.assign(pdata.get("data", {}).get("movement_types", []))

	var target := _find_explore_target(creature_id)
	if target == Vector2i(-1, -1):
		_explore_active[creature_id] = false
		return

	var path := _a_star_path(from_hex, target, movement_types)
	if path.size() > 1:
		_movement_queues[creature_id] = path.slice(1)
		_explore_active[creature_id] = true
	else:
		_explore_active[creature_id] = false

@rpc("any_peer", "call_local", "reliable")
func request_start_explore(creature_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	if not _is_peer_turn(sender_peer_id):
		return
	if not _is_creature_controlled_by_peer(creature_id, sender_peer_id):
		return
	start_explore(creature_id, sender_peer_id)


func cancel_explore(creature_id: String) -> void:
	_explore_active[creature_id] = false


func place_creature_on_map(creature_id: String, creature_data: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer() and not _is_local_turn():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_place_creature_on_map.rpc_id(HOST_PEER_ID, creature_id, creature_data)
		return
	_place_creature_on_map_internal(creature_id, creature_data, _get_local_peer_id())

func _place_creature_on_map_internal(creature_id: String, creature_data: Dictionary, owner_peer_id: int) -> void:
	var physical_size: String = creature_data.get("physical_size", "Small")
	var slice_count: int = PointCostConstants.PHYSICAL_SIZE_COSTS.get(physical_size, 1)

	if not HexOccupancyValidator.place_creature(SPAWN_HEX, creature_id, slice_count):
		push_warning("CreatureMovement: could not place %s at spawn hex — no space" % creature_id)
		return

	var color := _COLOR_PALETTE[_color_index % _COLOR_PALETTE.size()]
	_color_index += 1

	GameState.placed_creatures[creature_id] = {
		"data": creature_data,
		"hex":  SPAWN_HEX,
		"color": color,
		"owner_peer_id": owner_peer_id,
	}
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		GameState.save_game()

	var vision: int = int(creature_data.get("vision", 3))
	if _strategy_game:
		_strategy_game.reveal_hexes(SPAWN_HEX, vision)
		_strategy_game.refresh_creature_tokens()
		if _strategy_game.has_method("broadcast_creature_placed_delta"):
			_strategy_game.broadcast_creature_placed_delta(creature_id)

@rpc("any_peer", "call_local", "reliable")
func request_place_creature_on_map(creature_id: String, creature_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	if not _is_peer_turn(sender_peer_id):
		return
	var canonical_prefix: String = "p%d_" % sender_peer_id
	var canonical_id: String = creature_id if creature_id.begins_with(canonical_prefix) else "%s%s" % [canonical_prefix, creature_id]
	var canonical_data: Dictionary = creature_data.duplicate(true)
	canonical_data["id"] = canonical_id
	_place_creature_on_map_internal(canonical_id, canonical_data, sender_peer_id)


func _a_star_path(from: Vector2i, to: Vector2i,
		movement_types: Array[String]) -> Array[Vector2i]:
	if not _strategy_game:
		return []

	# A* with Manhattan heuristic on hex grid
	var open_set: Dictionary = {}  # Vector2i → true
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from: 0.0}
	var f_score: Dictionary = {from: _hex_dist(from, to)}
	open_set[from] = true

	var max_iterations := 5000
	var iter := 0

	while not open_set.is_empty() and iter < max_iterations:
		iter += 1
		# Find lowest f_score in open_set
		var current := Vector2i(-1, -1)
		var best_f := INF
		for node: Vector2i in open_set.keys():
			var fs: float = f_score.get(node, INF)
			if fs < best_f:
				best_f = fs
				current = node

		if current == to:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)
		var neighbors: Array[Vector2i] = _strategy_game.get_hex_neighbors(current)
		for neighbor: Vector2i in neighbors:
			var terrain: String = _strategy_game.get_terrain_at(neighbor)
			if terrain.is_empty():
				continue
			if not TerrainMovementRules.can_enter(movement_types, terrain):
				continue
			var tentative_g: float = g_score.get(current, INF) + 1.0
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _hex_dist(neighbor, to)
				open_set[neighbor] = true

	return []


func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


func _hex_dist(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))


func _find_explore_target(creature_id: String) -> Vector2i:
	if not _strategy_game:
		return Vector2i(-1, -1)
	var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
	if pdata.is_empty():
		return Vector2i(-1, -1)

	var start: Vector2i = pdata.get("hex", SPAWN_HEX)
	var movement_types: Array[String] = []
	movement_types.assign(pdata.get("data", {}).get("movement_types", []))

	# BFS from creature position
	var visited: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var max_depth := 50
	var depth := 0

	while not frontier.is_empty() and depth < max_depth:
		depth += 1
		var next_frontier: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for neighbor: Vector2i in _strategy_game.get_hex_neighbors(cell):
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				# Target: unseen hex adjacent to a seen hex that creature can enter
				if not _strategy_game.is_hex_seen(neighbor):
					var terrain: String = _strategy_game.get_terrain_at(neighbor)
					if not terrain.is_empty() and TerrainMovementRules.can_enter(movement_types, terrain):
						return neighbor
				next_frontier.append(neighbor)
		frontier = next_frontier

	return Vector2i(-1, -1)
