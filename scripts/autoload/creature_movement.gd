extends Node

## Manages creature movement, pathfinding, placement, and autonomous explore behavior.

signal creature_selected(creature_id: String)

const SPAWN_HEX := Vector2i(90, 45)

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
var _seen_hexes: Dictionary = {}       # Vector2i → true
var _color_index: int = 0


func set_strategy_game(node: StrategyGame) -> void:
	_strategy_game = node


func on_hex_clicked(coords: Vector2i) -> void:
	# Check if any creature occupies this hex
	var occupants := HexOccupancyValidator.get_all_occupied_hexes()
	if coords in occupants:
		# Select the first creature on this hex
		var wedges := HexOccupancyValidator.get_wedge_layout(coords)
		if wedges.size() > 0:
			var cid: String = wedges[0].get("creature_id", "")
			_selected_creature_id = cid
			creature_selected.emit(cid)
			return
	# Else queue movement for the selected creature
	if not _selected_creature_id.is_empty():
		var pdata: Dictionary = GameState.placed_creatures.get(_selected_creature_id, {})
		if pdata.is_empty():
			_selected_creature_id = ""
			return
		var movement_types: Array[String] = []
		movement_types.assign(pdata.get("data", {}).get("movement_types", []))
		var from_hex: Vector2i = pdata.get("hex", SPAWN_HEX)
		var path := _a_star_path(from_hex, coords, movement_types)
		if path.size() > 1:
			_movement_queues[_selected_creature_id] = path.slice(1)  # exclude current hex


func advance_turn() -> void:
	for creature_id: String in GameState.placed_creatures.keys():
		var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
		if pdata.is_empty():
			continue
		var cdata: Dictionary = pdata.get("data", {})
		var speed: int = int(cdata.get("movement_speed", 1))
		var movement_types: Array[String] = []
		movement_types.assign(cdata.get("movement_types", []))
		var current_hex: Vector2i = pdata.get("hex", SPAWN_HEX)

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
					break
				# Reveal fog
				var vision: int = int(cdata.get("vision", 3))
				if _strategy_game:
					_strategy_game.reveal_hexes(current_hex, vision)
					_mark_seen(current_hex, vision)
				steps_taken += 1
			else:
				# Path is blocked — clear queue
				queue.clear()
				break
		_movement_queues[creature_id] = queue

		# Re-evaluate explore after arriving
		if _explore_active.get(creature_id, false) and queue.is_empty():
			if GameState.placed_creatures.has(creature_id):
				start_explore(creature_id)

	# Refresh token display
	if _strategy_game:
		_strategy_game.refresh_creature_tokens()


func start_explore(creature_id: String) -> void:
	if not GameState.placed_creatures.has(creature_id):
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


func cancel_explore(creature_id: String) -> void:
	_explore_active[creature_id] = false


func place_creature_on_map(creature_id: String, creature_data: Dictionary) -> void:
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
	}

	var vision: int = int(creature_data.get("vision", 3))
	if _strategy_game:
		_strategy_game.reveal_hexes(SPAWN_HEX, vision)
		_mark_seen(SPAWN_HEX, vision)
		_strategy_game.refresh_creature_tokens()


func _mark_seen(center: Vector2i, radius: int) -> void:
	if not _strategy_game:
		return
	_seen_hexes[center] = true
	var visited: Dictionary = {center: true}
	var frontier: Array[Vector2i] = [center]
	for _r in radius:
		var next_frontier: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for neighbor: Vector2i in _strategy_game.get_hex_neighbors(cell):
				if not visited.has(neighbor):
					visited[neighbor] = true
					_seen_hexes[neighbor] = true
					next_frontier.append(neighbor)
		frontier = next_frontier


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
				if not _seen_hexes.has(neighbor):
					var terrain: String = _strategy_game.get_terrain_at(neighbor)
					if not terrain.is_empty() and TerrainMovementRules.can_enter(movement_types, terrain):
						return neighbor
				next_frontier.append(neighbor)
		frontier = next_frontier

	return Vector2i(-1, -1)
