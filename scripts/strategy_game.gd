extends Node2D
class_name StrategyGame

signal hex_clicked(coords: Vector2i)

## Strategy Game — 180×90 flat-top hex world map.
##
## Terrain is classified from Natural Earth GeoJSON (land polygons + bathymetry isobaths).
## Rendering is chunked: only hexes near the camera viewport are drawn, old chunks unload.
## Hover UI shows coordinates, lat/lon, terrain label, and movement types.
##
## Public API (callable from other scripts / GDScript console):
##   get_terrain_at(coords: Vector2i) -> String
##   set_tile_terrain(coords: Vector2i, terrain_type: String) -> void
##   can_enter(coords: Vector2i, movement_types: Array) -> bool

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH  := 180
const GRID_HEIGHT := 90
const CHUNK_SIZE  := 20
const MOUNTAIN_THRESHOLD := 0.60
const HEX_TILE_SIZE := Vector2i(64, 56)
const ATLAS_SOURCE_ID := 0
const PAN_SPEED := 600.0
const ZOOM_MIN := Vector2(0.05, 0.05)
const ZOOM_MAX := Vector2(2.0, 2.0)
const ZOOM_STEP := 0.1

const TERRAIN_OVERRIDE_SAVE_PATH := "user://hex_terrain_overrides.json"

const SPAWN_HEX := Vector2i(90, 45)

const TERRAIN_ATLAS_COORDS: Dictionary = {
	"deep_ocean":    Vector2i(0, 0),
	"shallow_ocean": Vector2i(1, 0),
	"mountain":      Vector2i(2, 0),
	"land":          Vector2i(3, 0),
	"surface_water": Vector2i(4, 0),
}
const HIGHLIGHT_ATLAS_COORD := Vector2i(5, 0)

# Terrain colors for built-in atlas
const _BUILTIN_COLORS: Array[Color] = [
	Color("#0D1A66"),  # 0  deep_ocean
	Color("#2666CC"),  # 1  shallow_ocean
	Color("#999999"),  # 2  mountain
	Color("#4D9933"),  # 3  land
	Color("#4DB3E6"),  # 4  surface_water
	Color("#FFFF00"),  # 5  highlight (outline only)
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var hex_terrain_map: Dictionary = {}        # Vector2i → String
var _terrain_overrides: Dictionary = {}     # Vector2i → String (player-edited cells only)
var _loaded_chunks: Dictionary  = {}        # Vector2i → true
var _pending_loads: Dictionary  = {}   # Vector2i → true (deferred, not yet drawn)
var _terrain_cache: Dictionary  = {}   # chunk Vector2i → { cell Vector2i → terrain String }
var _land_polys:    Array        = []   # Array of { bbox: Rect2, rings: Array[PackedVector2Array] }
var _bathy_feats:   Array        = []   # Array of { depth: float, bbox: Rect2, rings: Array }
var _height_noise:  FastNoiseLite
var _hovered_cell:  Vector2i = Vector2i(-1, -1)
# Camera drag
var _dragging: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_start_cam: Vector2 = Vector2.ZERO

# Custom terrain: terrain_id → atlas source_id (int)
var _custom_source_ids: Dictionary = {}

# Node refs
var _tile_set: TileSet
var _terrain_layer: TileMapLayer
var _highlight_layer: TileMapLayer
var _selection_layer: TileMapLayer
var _camera: Camera2D
var _hover_label: Label
var _hover_panel: Panel
var _terrain_creator_layer: CanvasLayer
var _fog_drawer: FogDrawer
var _creature_token_layer: Node2D
var _creature_panel_layer: CanvasLayer

# Pinned selection (set when T is pressed)
var _pinned_cell: Vector2i = Vector2i(-1, -1)

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("strategy_game")
	_camera                = $Camera2D
	_terrain_layer         = $TerrainLayer
	_highlight_layer       = $HighlightLayer
	_selection_layer       = $SelectionLayer
	_hover_panel           = $UILayer/HoverPanel
	_hover_label           = $UILayer/HoverPanel/HoverLabel
	_terrain_creator_layer = $TerrainCreatorLayer if has_node("TerrainCreatorLayer") else null
	_fog_drawer           = $FogDrawer if has_node("FogDrawer") else null
	_creature_token_layer = $CreatureTokenLayer if has_node("CreatureTokenLayer") else null
	_creature_panel_layer  = $CreaturePanelLayer if has_node("CreaturePanelLayer") else null

	_setup_noise()
	_create_and_assign_tile_set()
	_build_custom_terrain_sources()
	_load_geojson()
	_generate_terrain_map()
	_load_terrain_overrides()
	_update_chunks()

	# Start with a small revealed window around the spawn hex
	reveal_hexes(SPAWN_HEX, 4)

	# Center camera on the middle of the map
	_camera.global_position = _terrain_layer.map_to_local(Vector2i(GRID_WIDTH / 2.0, GRID_HEIGHT / 2.0))

	# Listen for terrain registry changes (custom terrain add/remove/edit)
	TerrainDefinitions.terrain_updated.connect(_on_terrain_definitions_changed)

	# Wire up creature movement singleton
	CreatureMovement.set_strategy_game(self)

	# Wire up creature panel
	_wire_creature_panel()

	set_process_input(true)
	set_process(true)

# ---------------------------------------------------------------------------
# Noise setup
# ---------------------------------------------------------------------------

func _setup_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.seed = 42
	_height_noise.frequency = 0.05

# ---------------------------------------------------------------------------
# TileSet construction
# ---------------------------------------------------------------------------

func _create_and_assign_tile_set() -> void:
	_tile_set = TileSet.new()
	_tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	_tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	_tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	_tile_set.tile_size = HEX_TILE_SIZE

	var atlas := TileSetAtlasSource.new()
	atlas.texture_region_size = HEX_TILE_SIZE
	atlas.texture = _generate_atlas_texture()
	for col in _BUILTIN_COLORS.size():
		atlas.create_tile(Vector2i(col, 0))
	_tile_set.add_source(atlas, ATLAS_SOURCE_ID)

	_terrain_layer.tile_set   = _tile_set
	_highlight_layer.tile_set = _tile_set
	_selection_layer.tile_set = _tile_set

func _generate_atlas_texture() -> ImageTexture:
	var img := Image.create(_BUILTIN_COLORS.size() * 64, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for col in _BUILTIN_COLORS.size():
		if col == 5:  # highlight tile — outline only so terrain color shows through
			_draw_hex_outline_on_image(img, col * 64, _BUILTIN_COLORS[col], 3)
		else:
			# col 6 = fog tile — solid fill with alpha
			_draw_hex_on_image(img, col * 64, _BUILTIN_COLORS[col])
	return ImageTexture.create_from_image(img)

func _generate_single_hex_texture(color: Color) -> ImageTexture:
	var img := Image.create(64, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_hex_on_image(img, 0, color)
	return ImageTexture.create_from_image(img)

func _draw_hex_on_image(img: Image, x_offset: int, color: Color) -> void:
	var cx := x_offset + 32
	var cy := 28
	var rx := 30.0
	var ry := 26.0

	# Flat-top hexagon vertices at angles 0°, 60°, 120°, 180°, 240°, 300°
	var verts: Array[Vector2] = []
	for i in 6:
		var angle_rad := deg_to_rad(60.0 * i)
		verts.append(Vector2(cx + rx * cos(angle_rad), cy + ry * sin(angle_rad)))

	# Scanline fill
	for y in 56:
		var x_min := 9999.0
		var x_max := -9999.0
		var j := 5
		for i in 6:
			var yi := verts[i].y
			var yj := verts[j].y
			var xi := verts[i].x
			var xj := verts[j].x
			if (yi <= float(y) and yj > float(y)) or (yj <= float(y) and yi > float(y)):
				var t := (float(y) - yi) / (yj - yi)
				var x_intersect := xi + t * (xj - xi)
				x_min = min(x_min, x_intersect)
				x_max = max(x_max, x_intersect)
			j = i
		if x_min <= x_max:
			for x in range(int(x_min), int(x_max) + 1):
				if x >= x_offset and x < x_offset + 64 and y >= 0 and y < 56:
					img.set_pixel(x, y, color)

func _draw_hex_outline_on_image(img: Image, x_offset: int, color: Color, border: int) -> void:
	var cx := x_offset + 32
	var cy := 28
	var rx := 30.0
	var ry := 26.0

	var verts: Array[Vector2] = []
	for i in 6:
		var angle_rad := deg_to_rad(60.0 * i)
		verts.append(Vector2(cx + rx * cos(angle_rad), cy + ry * sin(angle_rad)))

	# Build scanlines (same as fill)
	var scanlines: Dictionary = {}
	for y in 56:
		var x_min := 9999.0
		var x_max := -9999.0
		var j := 5
		for i in 6:
			var yi := verts[i].y
			var yj := verts[j].y
			var xi := verts[i].x
			var xj := verts[j].x
			if (yi <= float(y) and yj > float(y)) or (yj <= float(y) and yi > float(y)):
				var t := (float(y) - yi) / (yj - yi)
				var x_intersect := xi + t * (xj - xi)
				x_min = min(x_min, x_intersect)
				x_max = max(x_max, x_intersect)
			j = i
		if x_min <= x_max:
			scanlines[y] = [int(x_min), int(x_max)]

	# Draw border pixels only: left/right strips + flat top/bottom edges
	for y: int in scanlines.keys():
		var x_min: int = scanlines[y][0]
		var x_max: int = scanlines[y][1]
		var top_edge := not scanlines.has(y - 1)
		var bot_edge := not scanlines.has(y + 1)
		for x in range(x_min, x_max + 1):
			if x < x_offset or x >= x_offset + 64:
				continue
			if x <= x_min + border or x >= x_max - border or top_edge or bot_edge:
				img.set_pixel(x, y, color)

# ---------------------------------------------------------------------------
# Custom terrain atlas sources
# ---------------------------------------------------------------------------

func _build_custom_terrain_sources() -> void:
	for ct: Dictionary in TerrainDefinitions.custom_terrains:
		_register_custom_terrain_source(ct)

func _register_custom_terrain_source(ct: Dictionary) -> int:
	var idx: int = TerrainDefinitions.custom_terrains.find(ct)
	var source_id: int = ATLAS_SOURCE_ID + 1 + idx
	if _tile_set.has_source(source_id):
		_tile_set.remove_source(source_id)
	var atlas := TileSetAtlasSource.new()
	atlas.texture_region_size = HEX_TILE_SIZE
	atlas.texture = _generate_single_hex_texture(ct["color"])
	atlas.create_tile(Vector2i(0, 0))
	_tile_set.add_source(atlas, source_id)
	_custom_source_ids[ct["id"]] = source_id
	return source_id

func _refresh_custom_terrain_sources() -> void:
	# Remove sources that no longer exist
	for old_id: String in _custom_source_ids.keys():
		if not TerrainDefinitions.custom_terrains.any(func(ct: Dictionary) -> bool: return ct["id"] == old_id):
			var src_id: int = _custom_source_ids[old_id]
			if _tile_set.has_source(src_id):
				_tile_set.remove_source(src_id)
			_custom_source_ids.erase(old_id)
	# Re-register all custom terrains (indices may have shifted)
	_custom_source_ids.clear()
	for ct: Dictionary in TerrainDefinitions.custom_terrains:
		_register_custom_terrain_source(ct)

func _update_custom_terrain_color(id: String, color: Color) -> void:
	if not _custom_source_ids.has(id):
		return
	var source_id: int = _custom_source_ids[id]
	var atlas := _tile_set.get_source(source_id) as TileSetAtlasSource
	if atlas:
		atlas.texture = _generate_single_hex_texture(color)

func _on_terrain_definitions_changed() -> void:
	_refresh_custom_terrain_sources()
	# Repaint all loaded chunks (snapshot keys to avoid iteration error)
	var coords := _loaded_chunks.keys()
	for chunk_coord: Vector2i in coords:
		_unload_chunk_immediate(chunk_coord)
		_load_chunk(chunk_coord)

# ---------------------------------------------------------------------------
# GeoJSON loading
# ---------------------------------------------------------------------------

func _load_geojson() -> void:
	var land_file := FileAccess.open("res://assets/data/ne_110m_land.geojson", FileAccess.READ)
	if land_file:
		var text := land_file.get_as_text()
		land_file.close()
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary and parsed.has("features"):
			for feature: Variant in parsed["features"]:
				if feature is Dictionary:
					var geom: Variant = feature.get("geometry", {})
					if geom is Dictionary:
						_extract_land_rings(geom)
	else:
		push_warning("StrategyGame: ne_110m_land.geojson not found — land classification disabled")

	var bathy_file := FileAccess.open("res://assets/data/ne_110m_bathymetry_all.geojson", FileAccess.READ)
	if bathy_file:
		var text := bathy_file.get_as_text()
		bathy_file.close()
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary and parsed.has("features"):
			for feature: Variant in parsed["features"]:
				if feature is Dictionary:
					var props: Variant = feature.get("properties", {})
					var depth := 0.0
					if props is Dictionary:
						if props.has("depth"):
							depth = float(props["depth"])
							if depth > 0.0:
								depth = -depth
						elif props.has("ScaleRank"):
							depth = -float(props["ScaleRank"]) * 500.0
					if depth < 0.0:
						var geom: Variant = feature.get("geometry", {})
						if geom is Dictionary:
							_extract_bathy_rings(geom, depth)
	else:
		push_warning("StrategyGame: ne_110m_bathymetry_all.geojson not found — depth classification disabled")

	# Deepest features first (so we match the deepest applicable isobath)
	_bathy_feats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])

func _extract_land_rings(geom: Dictionary) -> void:
	var gtype: String = geom.get("type", "")
	var coords: Variant = geom.get("coordinates", [])
	if gtype == "Polygon" and coords is Array:
		_add_land_polygon(coords)
	elif gtype == "MultiPolygon" and coords is Array:
		for poly: Variant in coords:
			if poly is Array:
				_add_land_polygon(poly)

func _add_land_polygon(poly_coords: Array) -> void:
	if poly_coords.is_empty():
		return
	var outer_ring := _coords_to_vec2(poly_coords[0])
	if outer_ring.is_empty():
		return
	var bbox := _compute_bbox(outer_ring)
	_land_polys.append({"bbox": bbox, "rings": [outer_ring]})

func _extract_bathy_rings(geom: Dictionary, depth: float) -> void:
	var gtype: String = geom.get("type", "")
	var coords: Variant = geom.get("coordinates", [])
	if gtype == "Polygon" and coords is Array:
		_add_bathy_polygon(coords, depth)
	elif gtype == "MultiPolygon" and coords is Array:
		for poly: Variant in coords:
			if poly is Array:
				_add_bathy_polygon(poly, depth)

func _add_bathy_polygon(poly_coords: Array, depth: float) -> void:
	if poly_coords.is_empty():
		return
	var outer_ring := _coords_to_vec2(poly_coords[0])
	if outer_ring.is_empty():
		return
	var bbox := _compute_bbox(outer_ring)
	_bathy_feats.append({"depth": depth, "bbox": bbox, "rings": [outer_ring]})

func _coords_to_vec2(coords: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not coords is Array:
		return result
	for c: Variant in coords:
		if c is Array and c.size() >= 2:
			result.append(Vector2(float(c[0]), float(c[1])))
	return result

func _compute_bbox(ring: PackedVector2Array) -> Rect2:
	if ring.is_empty():
		return Rect2()
	var min_x := ring[0].x
	var max_x := ring[0].x
	var min_y := ring[0].y
	var max_y := ring[0].y
	for pt: Vector2 in ring:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------

func _hex_to_latlon(col: int, row: int) -> Vector2:
	var lon := -180.0 + (col + 0.5) * (360.0 / GRID_WIDTH)
	var lat :=  90.0 - (row + 0.5) * (180.0 / GRID_HEIGHT)
	return Vector2(lon, lat)  # .x = lon, .y = lat

func _hex_to_chunk(hex_coord: Vector2i) -> Vector2i:
	return Vector2i(floori(hex_coord.x / float(CHUNK_SIZE)),
					floori(hex_coord.y / float(CHUNK_SIZE)))

# ---------------------------------------------------------------------------
# Terrain generation
# ---------------------------------------------------------------------------

func _generate_terrain_map() -> void:
	for col in GRID_WIDTH:
		for row in GRID_HEIGHT:
			var latlon := _hex_to_latlon(col, row)
			var lon := latlon.x
			var lat := latlon.y
			var depth  := _sample_bathymetry(latlon)
			var on_land := _point_in_land(latlon)

			var terrain: String
			if depth < -2000.0:
				terrain = "deep_ocean"
			elif depth < 0.0:
				terrain = "shallow_ocean"
			elif on_land and _height_noise.get_noise_2d(lon, lat) > MOUNTAIN_THRESHOLD:
				terrain = "mountain"
			elif on_land:
				terrain = "land"
			else:
				terrain = "surface_water"

			var cell := Vector2i(col, row)
			hex_terrain_map[cell] = terrain

			var chunk := _hex_to_chunk(cell)
			if not _terrain_cache.has(chunk):
				_terrain_cache[chunk] = {}
			_terrain_cache[chunk][cell] = terrain

func _point_in_polygon(pt: Vector2, ring: PackedVector2Array) -> bool:
	var inside := false
	var j := ring.size() - 1
	for i in ring.size():
		var xi := ring[i].x
		var yi := ring[i].y
		var xj := ring[j].x
		var yj := ring[j].y
		if (yi > pt.y) != (yj > pt.y):
			if pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi:
				inside = !inside
		j = i
	return inside

func _sample_bathymetry(pt: Vector2) -> float:
	for feat: Dictionary in _bathy_feats:
		var bbox: Rect2 = feat["bbox"]
		if not bbox.has_point(pt):
			continue
		for ring: PackedVector2Array in feat["rings"]:
			if _point_in_polygon(pt, ring):
				return float(feat["depth"])
	return 0.0

func _point_in_land(pt: Vector2) -> bool:
	for poly: Dictionary in _land_polys:
		var bbox: Rect2 = poly["bbox"]
		if not bbox.has_point(pt):
			continue
		for ring: PackedVector2Array in poly["rings"]:
			if _point_in_polygon(pt, ring):
				return true
	return false

# ---------------------------------------------------------------------------
# Chunk rendering
# ---------------------------------------------------------------------------

func _update_chunks() -> void:
	if not _camera:
		return

	# Determine which hex range is visible
	var vp_size := get_viewport().get_visible_rect().size
	var cam_pos  := _camera.global_position
	var zoom     := _camera.zoom
	var half_vp  := vp_size * 0.5 / zoom

	# Convert world corners to map cells
	var top_left     := _terrain_layer.local_to_map(_terrain_layer.to_local(cam_pos - half_vp))
	var bottom_right := _terrain_layer.local_to_map(_terrain_layer.to_local(cam_pos + half_vp))

	# Expand by 1 chunk on each side as a buffer
	var chunk_tl := Vector2i(
		floori(float(top_left.x) / CHUNK_SIZE) - 1,
		floori(float(top_left.y) / CHUNK_SIZE) - 1)
	var chunk_br := Vector2i(
		floori(float(bottom_right.x) / CHUNK_SIZE) + 1,
		floori(float(bottom_right.y) / CHUNK_SIZE) + 1)

	# Clamp to valid chunk range
	var max_chunk_x := floori(float(GRID_WIDTH  - 1) / CHUNK_SIZE)
	var max_chunk_y := floori(float(GRID_HEIGHT - 1) / CHUNK_SIZE)
	chunk_tl.x = clampi(chunk_tl.x, 0, max_chunk_x)
	chunk_tl.y = clampi(chunk_tl.y, 0, max_chunk_y)
	chunk_br.x = clampi(chunk_br.x, 0, max_chunk_x)
	chunk_br.y = clampi(chunk_br.y, 0, max_chunk_y)

	# Determine which chunks should now be loaded
	var desired: Dictionary = {}
	for cx in range(chunk_tl.x, chunk_br.x + 1):
		for cy in range(chunk_tl.y, chunk_br.y + 1):
			desired[Vector2i(cx, cy)] = true

	# Load newly visible chunks
	for chunk_coord: Vector2i in desired.keys():
		if not _loaded_chunks.has(chunk_coord) and not _pending_loads.has(chunk_coord):
			_pending_loads[chunk_coord] = true
			call_deferred("_load_chunk_deferred", chunk_coord)

	# Unload chunks that moved out of range
	for old_chunk: Vector2i in _loaded_chunks.keys():
		if not desired.has(old_chunk):
			call_deferred("_unload_chunk", old_chunk)

func _load_chunk_deferred(chunk_coord: Vector2i) -> void:
	_pending_loads.erase(chunk_coord)
	_load_chunk(chunk_coord)

func _load_chunk(chunk_coord: Vector2i) -> void:
	_loaded_chunks[chunk_coord] = true
	var col0 := chunk_coord.x * CHUNK_SIZE
	var row0 := chunk_coord.y * CHUNK_SIZE
	for dc in CHUNK_SIZE:
		for dr in CHUNK_SIZE:
			var cell := Vector2i(col0 + dc, row0 + dr)
			if not hex_terrain_map.has(cell):
				continue
			var terrain: String = hex_terrain_map[cell]
			_set_terrain_cell_visual(cell, terrain)

func _unload_chunk(chunk_coord: Vector2i) -> void:
	_unload_chunk_immediate(chunk_coord)

func _unload_chunk_immediate(chunk_coord: Vector2i) -> void:
	_loaded_chunks.erase(chunk_coord)
	var col0 := chunk_coord.x * CHUNK_SIZE
	var row0 := chunk_coord.y * CHUNK_SIZE
	for dc in CHUNK_SIZE:
		for dr in CHUNK_SIZE:
			_terrain_layer.erase_cell(Vector2i(col0 + dc, row0 + dr))

func _set_terrain_cell_visual(cell: Vector2i, terrain: String) -> void:
	if TERRAIN_ATLAS_COORDS.has(terrain):
		_terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, TERRAIN_ATLAS_COORDS[terrain])
	elif _custom_source_ids.has(terrain):
		_terrain_layer.set_cell(cell, _custom_source_ids[terrain], Vector2i(0, 0))

# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_chunks()

	# Hover detection
	var mouse_world := get_global_mouse_position()
	var local_pos   := _terrain_layer.to_local(mouse_world)
	var cell        := _terrain_layer.local_to_map(local_pos)
	if cell != _hovered_cell:
		_update_hover(cell)

	# Pulse the pinned selection cell
	if _pinned_cell.x >= 0:
		var t := Time.get_ticks_msec() / 1000.0
		_selection_layer.modulate.a = lerpf(0.35, 1.0, sin(t * TAU * 0.75) * 0.5 + 0.5)

func _set_pinned_cell(cell: Vector2i) -> void:
	if _pinned_cell.x >= 0:
		_selection_layer.erase_cell(_pinned_cell)
	_pinned_cell = cell
	if cell.x >= 0 and hex_terrain_map.has(cell):
		_selection_layer.set_cell(cell, ATLAS_SOURCE_ID, HIGHLIGHT_ATLAS_COORD)
		_selection_layer.modulate.a = 1.0

func clear_pinned_cell() -> void:
	_set_pinned_cell(Vector2i(-1, -1))

func _update_hover(cell: Vector2i) -> void:
	# Clear previous highlight
	if _hovered_cell.x >= 0:
		_highlight_layer.erase_cell(_hovered_cell)

	if cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_HEIGHT \
			and hex_terrain_map.has(cell):
		_highlight_layer.set_cell(cell, ATLAS_SOURCE_ID, HIGHLIGHT_ATLAS_COORD)
		var terrain: String = hex_terrain_map[cell]
		var latlon  := _hex_to_latlon(cell.x, cell.y)
		var movement := TerrainDefinitions.get_required_movement_types(terrain)
		_hover_label.text = (
			"Grid: (%d, %d)\nLat/Lon: %.1f°, %.1f°\nTerrain: %s\nMovement: %s" % [
				cell.x, cell.y,
				latlon.y, latlon.x,
				TerrainDefinitions.get_terrain_label(terrain),
				", ".join(movement) if movement.size() > 0 else "none",
			]
		)
		_hover_panel.visible = true
	else:
		_hover_label.text = ""
		_hover_panel.visible = false

	_hovered_cell = cell

# ---------------------------------------------------------------------------
# Fog of war — delegates to FogDrawer Node2D
# ---------------------------------------------------------------------------

func reveal_hexes(center: Vector2i, radius: int) -> void:
	if _fog_drawer:
		_fog_drawer.reveal_hexes(center, radius)


func is_hex_seen(cell: Vector2i) -> bool:
	return _fog_drawer.is_hex_seen(cell) if _fog_drawer else false


func refresh_creature_tokens() -> void:
	if _creature_token_layer:
		_creature_token_layer.queue_redraw()

# ---------------------------------------------------------------------------
# Hex spatial helpers
# ---------------------------------------------------------------------------

func get_hex_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return _terrain_layer.get_surrounding_cells(cell)


func hex_to_world(cell: Vector2i) -> Vector2:
	return _terrain_layer.map_to_local(cell)

# ---------------------------------------------------------------------------
# Creature panel wiring
# ---------------------------------------------------------------------------

func _wire_creature_panel() -> void:
	if not _creature_panel_layer:
		return
	var builder  := _creature_panel_layer.get_node_or_null(
		"SidePanel/VBoxContainer/CreatureBuilder")
	var bucket   := _creature_panel_layer.get_node_or_null(
		"SidePanel/VBoxContainer/CharacterBucket")
	var stats    := _creature_panel_layer.get_node_or_null(
		"SidePanel/VBoxContainer/CreatureStatsPanel")
	var end_turn := _creature_panel_layer.get_node_or_null(
		"SidePanel/VBoxContainer/ButtonRow/EndTurn")
	var attr_btn := _creature_panel_layer.get_node_or_null(
		"SidePanel/VBoxContainer/ButtonRow/Attributes")
	var attr_editor := _creature_panel_layer.get_node_or_null(
		"SidePanel/VBoxContainer/AttributeCreator")

	if builder and bucket and stats:
		builder.creature_confirmed.connect(
			func(creature_data: Dictionary) -> void:
				bucket.add_creature(creature_data)
		)
		bucket.creature_selected_in_bucket.connect(stats.show_creature_by_id)
		stats.send_to_hex_world_pressed.connect(_on_send_to_hex)
		stats.explore_pressed.connect(CreatureMovement.start_explore)
		CreatureMovement.creature_selected.connect(stats.show_creature_by_id)

	if end_turn:
		end_turn.pressed.connect(CreatureMovement.advance_turn)

	if attr_btn and attr_editor:
		attr_btn.pressed.connect(func() -> void: attr_editor.visible = not attr_editor.visible)


func _on_send_to_hex(creature_id: String) -> void:
	# Find creature data from bucket
	for c: Dictionary in GameState.character_bucket:
		if c.get("id", "") == creature_id:
			CreatureMovement.place_creature_on_map(creature_id, c)
			# Remove from bucket UI
			var bucket := _creature_panel_layer.get_node_or_null(
				"SidePanel/VBoxContainer/CharacterBucket") as Node
			if bucket and bucket.has_method("remove_creature"):
				bucket.remove_creature(creature_id)
			return

# ---------------------------------------------------------------------------
# Input — camera and hex click
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# T — open Terrain Creator, pin the hovered cell, and pass it to the creator
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T and _terrain_creator_layer:
			_terrain_creator_layer.visible = true
			_set_pinned_cell(_hovered_cell)
			var creator := _terrain_creator_layer.get_node_or_null("TerrainCreator")
			if creator and creator.has_method("select_cell"):
				creator.select_cell(_hovered_cell)
			get_viewport().set_input_as_handled()
			return
		# C — toggle creature panel
		if event.keycode == KEY_C and _creature_panel_layer:
			_creature_panel_layer.visible = not _creature_panel_layer.visible
			get_viewport().set_input_as_handled()
			return
		# F — toggle fog of war
		if event.keycode == KEY_F and _fog_drawer:
			_fog_drawer.visible = not _fog_drawer.visible
			get_viewport().set_input_as_handled()
			return

	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		var ev_mb := event as InputEventMouseButton
		if ev_mb.button_index == MOUSE_BUTTON_WHEEL_UP and ev_mb.pressed:
			_zoom_camera(ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if ev_mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev_mb.pressed:
			_zoom_camera(-ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return

		# Left click — select hex / queue creature movement
		if ev_mb.button_index == MOUSE_BUTTON_LEFT and ev_mb.pressed:
			var mouse_world := get_global_mouse_position()
			var local_pos   := _terrain_layer.to_local(mouse_world)
			var cell        := _terrain_layer.local_to_map(local_pos)
			if cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_HEIGHT:
				hex_clicked.emit(cell)
				CreatureMovement.on_hex_clicked(cell)

		# Middle mouse: start/stop pan drag
		if ev_mb.button_index == MOUSE_BUTTON_MIDDLE:
			if ev_mb.pressed:
				_dragging = true
				_drag_start_screen = ev_mb.global_position
				_drag_start_cam = _camera.global_position
			else:
				_dragging = false

	# Mouse drag pan
	if event is InputEventMouseMotion and _dragging:
		var ev_mm := event as InputEventMouseMotion
		var delta: Vector2 = ev_mm.global_position - _drag_start_screen
		_camera.global_position = _drag_start_cam - delta / _camera.zoom

	# Arrow / WASD pan (handled each frame would require tracking keys;
	# instead we handle them in _process via Input.is_action_pressed checks).

func _zoom_camera(step: float) -> void:
	var new_zoom := _camera.zoom + Vector2(step, step)
	_camera.zoom = new_zoom.clamp(ZOOM_MIN, ZOOM_MAX)

# ---------------------------------------------------------------------------
# Terrain override persistence
# ---------------------------------------------------------------------------

func _save_terrain_overrides() -> void:
	var data: Dictionary = {}
	for cell: Vector2i in _terrain_overrides:
		data["%d,%d" % [cell.x, cell.y]] = _terrain_overrides[cell]
	var file := FileAccess.open(TERRAIN_OVERRIDE_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
	else:
		push_warning("StrategyGame: could not save terrain overrides")

func _load_terrain_overrides() -> void:
	var file := FileAccess.open(TERRAIN_OVERRIDE_SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	for key: String in parsed.keys():
		var parts := key.split(",")
		if parts.size() == 2:
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			var terrain: String = str(parsed[key])
			_terrain_overrides[cell] = terrain
			hex_terrain_map[cell] = terrain
			var chunk := _hex_to_chunk(cell)
			if _terrain_cache.has(chunk):
				_terrain_cache[chunk][cell] = terrain

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_tile_terrain(coords: Vector2i, terrain_type: String) -> void:
	hex_terrain_map[coords] = terrain_type
	_terrain_overrides[coords] = terrain_type
	_save_terrain_overrides()
	# Update terrain cache
	var chunk := _hex_to_chunk(coords)
	if _terrain_cache.has(chunk):
		_terrain_cache[chunk][coords] = terrain_type
	# Repaint if chunk is loaded
	if _loaded_chunks.has(chunk):
		_set_terrain_cell_visual(coords, terrain_type)
	# Refresh hover label if this is the hovered cell
	if coords == _hovered_cell:
		_update_hover(coords)

func get_terrain_at(coords: Vector2i) -> String:
	return hex_terrain_map.get(coords, "")

func can_enter(coords: Vector2i, movement_types: Array) -> bool:
	var terrain := get_terrain_at(coords)
	if terrain.is_empty():
		return false
	var required := TerrainDefinitions.get_required_movement_types(terrain)
	for mt: Variant in movement_types:
		if mt in required:
			return true
	return false
