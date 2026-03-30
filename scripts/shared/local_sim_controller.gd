## Local simulation controller: spawns bot enemies for local testing.
## Isolated from multiplayer logic.  (req-local-sim-v1)
class_name LocalSimController
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

## Master toggle — when false, arena skips bot spawning entirely.
var local_sim_enabled: bool = true
## Distance from player to each bot (corner of square = this distance from center).
var spawn_distance_min: float = 220.0
var spawn_distance_max: float = 320.0

## Distinct bot palettes — visually different from player blue.
const BOT_PALETTES: Array = [
	[Color(0.85, 0.20, 0.15), Color(1.00, 0.50, 0.35)],   # red
	[Color(0.80, 0.55, 0.10), Color(1.00, 0.80, 0.30)],   # gold
	[Color(0.60, 0.15, 0.70), Color(0.85, 0.45, 0.95)],   # purple
]

const BOT_LABELS: Array = ["Red", "Gold", "Prpl"]


## Build a bot ship dictionary entry matching the arena's player format.
## Bots are placed on corners of an axis-aligned square around the player (index 0–3 → 4 corners).
## player_dict: the existing player's ship dictionary for position reference.
## bot_index: 0-based index used for unique peer_id, palette, label, and square corner.
func create_bot_entry(player_dict: Dictionary, bot_index: int = 0) -> Dictionary:
	var px: float = float(player_dict.get("wx", 400.0))
	var py: float = float(player_dict.get("wy", 400.0))

	# Mean range from player to each bot; half_side of axis-aligned square so corner distance ≈ dist.
	var dist: float = (spawn_distance_min + spawn_distance_max) * 0.5
	var half_side: float = dist / sqrt(2.0)
	var corners: Array[Vector2] = [
		Vector2(half_side, half_side),
		Vector2(-half_side, half_side),
		Vector2(-half_side, -half_side),
		Vector2(half_side, -half_side),
	]
	var ci: int = posmod(bot_index, corners.size())
	var off: Vector2 = corners[ci]

	var bot_x: float = px + off.x
	var bot_y: float = py + off.y

	# Clamp to map bounds.
	var map_max: float = float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE - 50.0
	bot_x = clampf(bot_x, 50.0, map_max)
	bot_y = clampf(bot_y, 50.0, map_max)

	# Face toward player with slight yaw jitter.
	var to_player: Vector2 = (Vector2(px, py) - Vector2(bot_x, bot_y))
	if to_player.length_squared() < 0.01:
		to_player = Vector2.RIGHT
	var bot_heading: Vector2 = to_player.normalized().rotated(randf_range(-0.2, 0.2))

	var bot_peer_id: int = -(10 + bot_index)
	var palette: Array = BOT_PALETTES[bot_index % BOT_PALETTES.size()]
	var label: String = BOT_LABELS[bot_index % BOT_LABELS.size()]

	return {
		"peer_id": bot_peer_id,
		"wx": bot_x,
		"wy": bot_y,
		"dir": bot_heading,
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
