extends RefCounted
class_name BlacksiteMapProfile

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

# Open-sea sailing surface: expanded water grid, no structures (walls/building removed).

## req-naval-combat-prototype-v1 §2.3 — logical tiles; wx,wy use NC.UNITS_PER_LOGIC_TILE.
static var MAP_WIDTH: int = NC.MAP_TILES_WIDE
static var MAP_HEIGHT: int = NC.MAP_TILES_HIGH

const SEA_SKY: Color = Color(0.40, 0.58, 0.78, 1.0)
## Kept for callers that used the old name (e.g. menu background).
const SKY_DAY: Color = SEA_SKY


static func configure_renderer(renderer: IsoTerrainRenderer) -> Dictionary:
	var data: Dictionary = build_open_sea_map()
	renderer.chunk_size = 16
	apply_ocean_palette(renderer)
	renderer.load_static_map(data)
	return data.get("layout", {})


static func draw_map_overlay(_canvas: CanvasItem, _origin: Vector2, _tile_w: float, _tile_h: float, layout: Dictionary, _pulse_time: float = 0.0) -> void:
	if layout.get("open_sea", false):
		return


static func get_default_view_focus(layout: Dictionary) -> Vector2:
	var map_w: float = float(layout.get("map_width", MAP_WIDTH))
	var map_h: float = float(layout.get("map_height", MAP_HEIGHT))
	if bool(layout.get("open_sea", false)):
		var u: float = NC.UNITS_PER_LOGIC_TILE
		return Vector2(map_w * 0.5 * u, map_h * 0.5 * u)
	return Vector2(map_w * 0.5, map_h * 0.5)


static func world_focus_to_origin(viewport_size: Vector2, focus_world: Vector2, tile_w: float, tile_h: float, zoom: float = 1.0) -> Vector2:
	return viewport_size * 0.5 - Vector2(
		(focus_world.x - focus_world.y) * tile_w * zoom * 0.5,
		(focus_world.x + focus_world.y) * tile_h * zoom * 0.5
	)


static func build_open_sea_map(width: int = MAP_WIDTH, height: int = MAP_HEIGHT) -> Dictionary:
	var tiles: Array = []
	tiles.resize(width * height)
	for i in range(tiles.size()):
		tiles[i] = IsoTerrainRenderer.T_WATER
	# Slight depth at the outer edge (visual only; still walkable if you use non-mountain checks).
	const EDGE: int = 3
	for y in range(height):
		for x in range(width):
			if x < EDGE or y < EDGE or x >= width - EDGE or y >= height - EDGE:
				_set_tile_arr(tiles, width, height, x, y, IsoTerrainRenderer.T_DEEP)
	return {
		"width": width,
		"height": height,
		"tiles": tiles,
		"layout": {
			"map_width": width,
			"map_height": height,
			"open_sea": true,
		}
	}


## Player ship spawn positions in open water (world units; §2.1).
static func build_drone_spawns(data: Dictionary) -> Array:
	var width: int = int(data.get("width", MAP_WIDTH))
	var height: int = int(data.get("height", MAP_HEIGHT))
	var u: float = NC.UNITS_PER_LOGIC_TILE
	var cx: float = width * 0.5 * u
	var cy: float = height * 0.5 * u
	# Wide separation — ships are large and need room to manoeuvre at spawn.
	return [
		Vector2(cx - 500.0, cy + 350.0),
		Vector2(cx - 500.0, cy - 350.0),
		Vector2(cx + 500.0, cy + 350.0),
		Vector2(cx + 500.0, cy - 350.0),
		Vector2(cx - 250.0, cy + 550.0),
		Vector2(cx + 250.0, cy + 550.0),
		Vector2(cx - 250.0, cy - 550.0),
		Vector2(cx + 250.0, cy - 550.0),
	]


## Legacy API; no door exits on open sea.
static func get_door_spawn_points(_layout: Dictionary) -> Array[Vector2]:
	return []


static func apply_ocean_palette(renderer: IsoTerrainRenderer) -> void:
	renderer.clear_tile_modulates()
	renderer.set_tile_modulate(IsoTerrainRenderer.T_DEEP, Color(0.06, 0.22, 0.42, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_WATER, Color(0.18, 0.44, 0.64, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_SAND, Color(0.72, 0.68, 0.52, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_MOUNTAIN, Color(0.42, 0.46, 0.50, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_GRASS, Color(0.28, 0.52, 0.38, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_SNOW, Color(0.86, 0.90, 0.93, 1.0))


static func _set_tile_arr(tiles: Array, width: int, height: int, x: int, y: int, tile_id: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	tiles[y * width + x] = tile_id
