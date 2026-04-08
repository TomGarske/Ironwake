## Fleet spawner: creates ship dictionaries for two opposing fleets in formation.
## Player fleet spawns at south edge heading north; enemy fleet at north heading south.
class_name FleetSpawner
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const _ShipClassConfig := preload("res://scripts/shared/ship_class_config.gd")
const _LocalSimController := preload("res://scripts/shared/local_sim_controller.gd")

## Default fleet composition: 1 Galley (flagship), 2 Brigs (line), 2 Schooners (scouts).
const DEFAULT_FLEET_COMPOSITION: Array[int] = [
	_ShipClassConfig.ShipClass.GALLEY,    # index 0 = flagship
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.SCHOONER,
	_ShipClassConfig.ShipClass.SCHOONER,
]

## Spacing between ships in formation (world units).
const FORMATION_SPACING: float = 150.0
## Starting distance from map center for each fleet (world units).
const FLEET_START_OFFSET: float = 1800.0


## Spawn a fleet in inverted-V formation around a center point.
## heading: the direction the fleet faces (unit vector).
## Returns Array[Dictionary] of spawn infos: {wx, wy, dir, ship_class}.
static func spawn_fleet_formation(
		center: Vector2,
		heading: Vector2,
		composition: Array[int] = DEFAULT_FLEET_COMPOSITION
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var hull_dir: Vector2 = heading.normalized()
	var perp: Vector2 = hull_dir.rotated(PI * 0.5)
	var count: int = composition.size()
	if count == 0:
		return result
	# Flagship at center (index 0).
	result.append({
		"wx": center.x,
		"wy": center.y,
		"dir": hull_dir,
		"ship_class": composition[0],
	})
	# Remaining ships in inverted-V: alternate port/starboard, each row further back.
	for i in range(1, count):
		@warning_ignore("integer_division")
		var row: int = (i + 1) / 2   # row 1, 1, 2, 2, 3, 3 ...
		var side: float = -1.0 if (i % 2 == 1) else 1.0  # odd=port, even=starboard
		var lateral: float = side * float(row) * FORMATION_SPACING
		var behind: float = -float(row) * FORMATION_SPACING * 0.7  # staggered behind flagship
		var pos: Vector2 = center + hull_dir * behind + perp * lateral
		result.append({
			"wx": pos.x,
			"wy": pos.y,
			"dir": hull_dir,
			"ship_class": composition[i],
		})
	return result


## Compute fleet center positions for two opposing fleets on the map.
## Returns {player_center: Vector2, enemy_center: Vector2}.
static func compute_fleet_centers(map_center: Vector2) -> Dictionary:
	# Player fleet at south, heading north (negative Y in world space).
	var player_center: Vector2 = map_center + Vector2(0.0, FLEET_START_OFFSET)
	var enemy_center: Vector2 = map_center - Vector2(0.0, FLEET_START_OFFSET)
	return {
		"player_center": player_center,
		"enemy_center": enemy_center,
		"player_heading": Vector2(0.0, -1.0),  # north
		"enemy_heading": Vector2(0.0, 1.0),    # south
	}


## Create a bot ship dictionary from spawn info, following LocalSimController patterns.
static func create_fleet_ship_entry(
		spawn_info: Dictionary,
		fleet_index: int,
		ship_index_in_fleet: int,
		team: int,
		palette: Array = [],
		label: String = ""
	) -> Dictionary:
	# Use negative peer IDs to distinguish bots: -(team * 100 + ship_index).
	var bot_peer_id: int = -(team * 100 + fleet_index * 10 + ship_index_in_fleet + 1)
	if palette.is_empty():
		palette = _LocalSimController.BOT_PALETTES[ship_index_in_fleet % _LocalSimController.BOT_PALETTES.size()]
	if label.is_empty():
		label = "F%d-%d" % [fleet_index, ship_index_in_fleet]
	return {
		"peer_id": bot_peer_id,
		"wx": float(spawn_info.get("wx", 0.0)),
		"wy": float(spawn_info.get("wy", 0.0)),
		"dir": spawn_info.get("dir", Vector2.RIGHT),
		"health": 6.0,
		"alive": true,
		"atk_time": 0.0,
		"hit_landed": false,
		"palette": palette,
		"label": label,
		"walk_time": 0.0,
		"moving": false,
		"is_bot": true,
		"team": team,
		"ship_class_id": int(spawn_info.get("ship_class", _ShipClassConfig.ShipClass.BRIG)),
	}
