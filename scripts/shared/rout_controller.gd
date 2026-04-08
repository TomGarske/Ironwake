## Rout behavior: when a fleet loses enough ships, survivors turn and flee.
## Routed ships: full sail, turn away from enemy centroid, disable batteries, flee to map edge.
## Ships despawn when far enough past the map boundary.
class_name RoutController
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

## Distance past map edge before a routed ship despawns (world units).
const DESPAWN_MARGIN: float = 500.0
## How quickly routed ships turn toward their flee direction (radians/sec).
const ROUT_TURN_RATE: float = 0.8

## Map boundaries (world units).
var map_max_x: float = 0.0
var map_max_y: float = 0.0

## Tracks which fleet IDs are currently routed.
var _routed_fleets: Dictionary = {}  # fleet_id -> true


func _init() -> void:
	map_max_x = float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE
	map_max_y = float(NC.MAP_TILES_HIGH) * NC.UNITS_PER_LOGIC_TILE


func is_fleet_routed(fleet_id: int) -> bool:
	return _routed_fleets.has(fleet_id)


func trigger_rout(fleet_id: int) -> void:
	_routed_fleets[fleet_id] = true


## Compute the flee direction: away from the enemy fleet centroid.
static func compute_flee_direction(ship_pos: Vector2, enemy_centroid: Vector2) -> Vector2:
	var away: Vector2 = ship_pos - enemy_centroid
	if away.length_squared() < 1.0:
		away = Vector2(0.0, 1.0)  # Default: flee south.
	return away.normalized()


## Apply rout behavior to a single ship. Returns true if the ship should despawn.
func tick_rout_ship(p: Dictionary, flee_dir: Vector2, delta: float) -> bool:
	if not bool(p.get("alive", true)):
		return false

	# Mark the ship as routed (for HUD/rendering).
	p["is_routed"] = true

	# Full sail.
	var sail: Variant = p.get("sail")
	if sail != null:
		# Force to full sail state.
		while int(sail.sail_state) < 3:  # 3 = FULL
			sail.raise_step()
		sail.process(delta)

	# Turn toward flee direction.
	var hull_dir: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_dir.length_squared() < 0.0001:
		hull_dir = Vector2.RIGHT
	hull_dir = hull_dir.normalized()

	var cross: float = hull_dir.cross(flee_dir)
	var dot: float = hull_dir.dot(flee_dir)
	var angle_diff: float = atan2(cross, dot)

	# Steer toward flee direction.
	var helm: Variant = p.get("helm")
	if helm != null and absf(angle_diff) > 0.05:
		var steer_strength: float = clampf(absf(angle_diff) * 3.0, 0.3, 1.0)
		if angle_diff > 0:
			helm.process_steer(delta, steer_strength, 0.0)
		else:
			helm.process_steer(delta, 0.0, steer_strength)
	elif helm != null:
		helm.process_steer(delta, 0.0, 0.0)

	# Move forward at current speed.
	var speed: float = float(p.get("move_speed", 0.0))
	var move_dir: Vector2 = hull_dir
	p.wx = float(p.wx) + move_dir.x * speed * delta
	p.wy = float(p.wy) + move_dir.y * speed * delta

	# Update heading based on rudder.
	if helm != null:
		var rudder: float = float(helm.rudder_angle)
		if absf(rudder) > 0.01 and speed > 1.0:
			var turn_rate: float = rudder * ROUT_TURN_RATE * (speed / 40.0)
			var new_heading: Vector2 = hull_dir.rotated(turn_rate * delta)
			p.dir = new_heading

	# Check for despawn: ship is far enough past map edge.
	var wx: float = float(p.wx)
	var wy: float = float(p.wy)
	if wx < -DESPAWN_MARGIN or wx > map_max_x + DESPAWN_MARGIN \
		or wy < -DESPAWN_MARGIN or wy > map_max_y + DESPAWN_MARGIN:
		return true  # Despawn this ship.

	return false


## Compute the centroid of alive ships in a set of indices.
static func compute_centroid(players: Array, indices: Array[int]) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for idx in indices:
		if idx >= 0 and idx < players.size():
			var p: Dictionary = players[idx]
			if bool(p.get("alive", true)):
				sum += Vector2(float(p.wx), float(p.wy))
				count += 1
	if count == 0:
		return Vector2(float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE * 0.5,
			float(NC.MAP_TILES_HIGH) * NC.UNITS_PER_LOGIC_TILE * 0.5)
	return sum / float(count)
