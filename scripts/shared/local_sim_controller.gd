## Local simulation controller: spawns bot enemies for local testing.
## Isolated from multiplayer logic.  (req-local-sim-v1)
class_name LocalSimController
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

## Master toggle — when false, arena skips bot spawning entirely.
var local_sim_enabled: bool = true
## Radius of the spawn circle (all ships — player included — are placed on this circle).
var spawn_circle_radius: float = 800.0

## Distinct bot palettes — visually different from player blue.
const BOT_PALETTES: Array = [
	[Color(0.85, 0.20, 0.15), Color(1.00, 0.50, 0.35)],   # red
	[Color(0.80, 0.55, 0.10), Color(1.00, 0.80, 0.30)],   # gold
	[Color(0.60, 0.15, 0.70), Color(0.85, 0.45, 0.95)],   # purple
]

const BOT_LABELS: Array = ["Red", "Gold", "Prpl"]


## Compute spawn positions for all ships (player + bots) on a circle facing the center.
## Returns an array of { "wx", "wy", "dir" } dictionaries, one per ship.
## Index 0 is the player; indices 1..bot_count are bots.
static func compute_spawn_ring(center: Vector2, radius: float, total_ships: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map_max: float = float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE - 50.0
	for i in range(total_ships):
		var angle: float = float(i) / float(total_ships) * TAU
		var wx: float = center.x + cos(angle) * radius
		var wy: float = center.y + sin(angle) * radius
		wx = clampf(wx, 50.0, map_max)
		wy = clampf(wy, 50.0, map_max)
		# Face toward center with slight jitter.
		var to_center: Vector2 = (center - Vector2(wx, wy))
		if to_center.length_squared() < 0.01:
			to_center = Vector2.RIGHT
		var heading: Vector2 = to_center.normalized().rotated(randf_range(-0.15, 0.15))
		result.append({"wx": wx, "wy": wy, "dir": heading})
	return result


## Build a bot ship dictionary entry matching the arena's player format.
## spawn_info: one element from compute_spawn_ring (has wx, wy, dir).
func create_bot_entry(spawn_info: Dictionary, bot_index: int = 0) -> Dictionary:
	var bot_peer_id: int = -(10 + bot_index)
	var palette: Array = BOT_PALETTES[bot_index % BOT_PALETTES.size()]
	var label: String = BOT_LABELS[bot_index % BOT_LABELS.size()]

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
	}
