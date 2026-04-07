## Individual crew member with location, movement, health, and loyalty.
## The CrewController owns an Array[CrewAgent] and ticks them each frame.
class_name CrewAgent
extends RefCounted

const _ShipRoom := preload("res://scripts/shared/ship_room.gd")

enum Loyalty { LOYAL, PRESSED, PRISONER }
enum Task { IDLE, WORKING, MOVING, FIGHTING, REPAIRING_FIRE, BAILING }

## Seconds to traverse one room-graph edge.
const SECONDS_PER_HOP: float = 1.5
## Pressed crew efficiency multiplier.
const PRESSED_EFFICIENCY_MULT: float = 0.5
## Loyalty shift: seconds of peace before PRISONER -> PRESSED and PRESSED -> LOYAL.
const LOYALTY_SHIFT_INTERVAL: float = 45.0

var loyalty: Loyalty = Loyalty.LOYAL
var task: Task = Task.IDLE
var health: float = 1.0
## Current room (where the agent "is" for efficiency purposes).
var current_room: _ShipRoom = null
## When moving, the destination room.
var target_room: _ShipRoom = null
## BFS path: rooms to traverse (not including current_room).
var move_path: Array[_ShipRoom] = []
## Progress along the current hop (0.0 → 1.0).
var move_progress: float = 0.0
## Accumulated time in peaceful state for loyalty conversion.
var loyalty_timer: float = 0.0
## Unique id within the ship's crew roster (for stable identification).
var agent_id: int = 0


func _init(p_room: _ShipRoom = null, p_loyalty: Loyalty = Loyalty.LOYAL) -> void:
	current_room = p_room
	loyalty = p_loyalty
	task = Task.IDLE if p_room == null else Task.WORKING


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func is_moving() -> bool:
	return task == Task.MOVING


func is_alive() -> bool:
	return health > 0.0


## Effective contribution: 0 while moving, reduced if pressed, 0 if prisoner.
func get_effectiveness() -> float:
	if task == Task.MOVING or not is_alive():
		return 0.0
	if loyalty == Loyalty.PRISONER:
		return 0.0
	if loyalty == Loyalty.PRESSED:
		return PRESSED_EFFICIENCY_MULT
	return 1.0


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
## Start moving to a target room. Computes the BFS path.
## Returns false if already there or path is impossible.
func begin_move_to(destination: _ShipRoom) -> bool:
	if destination == null or destination == current_room:
		return false
	if current_room == null:
		current_room = destination
		return false
	# Build BFS path.
	var path: Array[_ShipRoom] = _bfs_path(current_room, destination)
	if path.is_empty():
		return false
	move_path = path
	move_progress = 0.0
	task = Task.MOVING
	target_room = destination
	# Leave current room crew count.
	if current_room.crew_count > 0:
		current_room.crew_count -= 1
	return true


## Tick movement. Returns true when the agent has arrived.
func process_movement(delta: float) -> bool:
	if task != Task.MOVING or move_path.is_empty():
		return false
	move_progress += delta / SECONDS_PER_HOP
	if move_progress >= 1.0:
		# Arrive at next hop.
		current_room = move_path[0]
		move_path.remove_at(0)
		move_progress = 0.0
		if move_path.is_empty():
			# Final destination reached.
			current_room.crew_count += 1
			target_room = null
			task = Task.WORKING
			return true
	return false


## Tick loyalty conversion (call once per frame while not in combat).
func process_loyalty(delta: float, in_combat: bool) -> void:
	if loyalty == Loyalty.LOYAL:
		return
	if in_combat:
		loyalty_timer = 0.0
		return
	loyalty_timer += delta
	if loyalty_timer >= LOYALTY_SHIFT_INTERVAL:
		loyalty_timer -= LOYALTY_SHIFT_INTERVAL
		if loyalty == Loyalty.PRISONER:
			loyalty = Loyalty.PRESSED
		elif loyalty == Loyalty.PRESSED:
			loyalty = Loyalty.LOYAL


## Kill this crew member. Removes from their room.
func kill() -> void:
	health = 0.0
	task = Task.IDLE
	if not is_moving() and current_room != null and current_room.crew_count > 0:
		current_room.crew_count -= 1
	current_room = null
	target_room = null
	move_path.clear()


# ---------------------------------------------------------------------------
# BFS pathfinding
# ---------------------------------------------------------------------------
static func _bfs_path(from: _ShipRoom, to: _ShipRoom) -> Array[_ShipRoom]:
	if from == to:
		return []
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array[_ShipRoom] = [from]
	visited[from.room_index] = true
	while not queue.is_empty():
		var current: _ShipRoom = queue.pop_front()
		for neighbor: _ShipRoom in current.adjacent_rooms:
			if visited.has(neighbor.room_index):
				continue
			visited[neighbor.room_index] = true
			parent[neighbor.room_index] = current
			if neighbor == to:
				# Reconstruct path.
				var path: Array[_ShipRoom] = []
				var step: _ShipRoom = to
				while step != from:
					path.insert(0, step)
					var p: Variant = parent.get(step.room_index)
					if p == null:
						break
					step = p as _ShipRoom
				return path
			queue.append(neighbor)
	return []
