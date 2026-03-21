extends RefCounted
class_name BlacksiteMapProfile

# Shared map profile for both gameplay and menu background.
# The perimeter wall treatment emulates modular space-station panels.

const MAP_WIDTH: int = 64
const MAP_HEIGHT: int = 64
const WALL_THICKNESS: int = 2
const RING_MARGIN: int = 20
const GATE_WIDTH: int = 10
const BUILDING_W: int = 14
const BUILDING_H: int = 10

const SKY_DAY: Color = Color(0.76, 0.84, 0.94, 1.0)
const BUILDING_DECAL: Texture2D = preload("res://assets/tilesets/tileset.png")

static func configure_renderer(renderer: IsoTerrainRenderer) -> Dictionary:
	var data: Dictionary = build_area51_surface_map()
	renderer.chunk_size = 16
	apply_bright_desert_palette(renderer)
	renderer.load_static_map(data)
	return data.get("layout", {})

static func draw_map_overlay(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, layout: Dictionary, pulse_time: float = 0.0) -> void:
	draw_metal_perimeter(canvas, origin, tile_w, tile_h, layout, pulse_time)
	draw_building_with_doors(canvas, origin, tile_w, tile_h, layout, pulse_time)

static func get_default_view_focus(layout: Dictionary) -> Vector2:
	# Match Blacksite gameplay initial camera (player spawn 0).
	var map_w: float = float(layout.get("map_width", MAP_WIDTH))
	var map_h: float = float(layout.get("map_height", MAP_HEIGHT))
	return Vector2(map_w * 0.5 - 7.0, map_h * 0.5 + 10.0)

static func world_focus_to_origin(viewport_size: Vector2, focus_world: Vector2, tile_w: float, tile_h: float, zoom: float = 1.0) -> Vector2:
	return viewport_size * 0.5 - Vector2(
		(focus_world.x - focus_world.y) * tile_w * zoom * 0.5,
		(focus_world.x + focus_world.y) * tile_h * zoom * 0.5
	)

static func build_area51_surface_map(width: int = MAP_WIDTH, height: int = MAP_HEIGHT) -> Dictionary:
	var tiles: PackedInt32Array = PackedInt32Array()
	tiles.resize(width * height)

	# Baseline terrain: bright desert floor.
	for i in range(tiles.size()):
		tiles[i] = IsoTerrainRenderer.T_SAND

	# Arena perimeter walls.
	_fill_rect(tiles, width, height, 0, 0, width, WALL_THICKNESS, IsoTerrainRenderer.T_MOUNTAIN)
	_fill_rect(tiles, width, height, 0, height - WALL_THICKNESS, width, WALL_THICKNESS, IsoTerrainRenderer.T_MOUNTAIN)
	_fill_rect(tiles, width, height, 0, 0, WALL_THICKNESS, height, IsoTerrainRenderer.T_MOUNTAIN)
	_fill_rect(tiles, width, height, width - WALL_THICKNESS, 0, WALL_THICKNESS, height, IsoTerrainRenderer.T_MOUNTAIN)

	# Main Area 51 building footprint in the middle.
	var building_x: int = floori(float(width - BUILDING_W) * 0.5)
	var building_y: int = floori(float(height - BUILDING_H) * 0.5)
	_fill_rect(tiles, width, height, building_x, building_y, BUILDING_W, BUILDING_H, IsoTerrainRenderer.T_MOUNTAIN)

	# Perimeter gate ring around the building.
	var ring_left: int = building_x - RING_MARGIN
	var ring_top: int = building_y - RING_MARGIN
	var ring_right: int = building_x + BUILDING_W + RING_MARGIN - 1
	var ring_bottom: int = building_y + BUILDING_H + RING_MARGIN - 1
	_draw_hollow_rect(tiles, width, height, ring_left, ring_top, ring_right, ring_bottom, IsoTerrainRenderer.T_MOUNTAIN)

	# South gate zone centered on the ring (kept physically closed for now).
	var gate_center: int = floori(float(ring_left + ring_right) * 0.5)
	var gate_half: int = floori(float(GATE_WIDTH) * 0.5)
	for x in range(gate_center - gate_half, gate_center + gate_half + 1):
		_set_tile(tiles, width, height, x, ring_bottom, IsoTerrainRenderer.T_MOUNTAIN)

	# Guard apron and lane hints.
	_fill_rect(tiles, width, height, gate_center - 6, ring_bottom + 1, 12, 9, IsoTerrainRenderer.T_GRASS)
	_draw_lane(tiles, width, height, gate_center, ring_bottom + 1, gate_center, height - WALL_THICKNESS - 1)
	_draw_lane(tiles, width, height, gate_center, ring_top - 1, gate_center, WALL_THICKNESS)
	var ring_mid_y: int = floori(float(ring_top + ring_bottom) * 0.5)
	_draw_lane(tiles, width, height, ring_left - 1, ring_mid_y, WALL_THICKNESS, ring_mid_y)
	_draw_lane(tiles, width, height, ring_right + 1, ring_mid_y, width - WALL_THICKNESS - 1, ring_mid_y)

	var door_tiles: Array = [
		Vector2i(building_x + floori(float(BUILDING_W) * 0.5), building_y - 1), # north
		Vector2i(building_x + floori(float(BUILDING_W) * 0.5), building_y + BUILDING_H), # south
		Vector2i(building_x - 1, building_y + floori(float(BUILDING_H) * 0.5)), # west
		Vector2i(building_x + BUILDING_W, building_y + floori(float(BUILDING_H) * 0.5)), # east
	]

	return {
		"width": width,
		"height": height,
		"tiles": tiles,
		"layout": {
			"map_width": width,
			"map_height": height,
			"building_x": building_x,
			"building_y": building_y,
			"building_w": BUILDING_W,
			"building_h": BUILDING_H,
			"ring_left": ring_left,
			"ring_top": ring_top,
			"ring_right": ring_right,
			"ring_bottom": ring_bottom,
			"gate_center": gate_center,
			"door_tiles": door_tiles,
		}
	}

static func build_drone_spawns(data: Dictionary) -> Array:
	var width: int = int(data.get("width", MAP_WIDTH))
	var height: int = int(data.get("height", MAP_HEIGHT))
	var cx: float = width * 0.5
	var cy: float = height * 0.5
	return [
		Vector2(cx - 7.0, cy + 10.0),
		Vector2(cx - 3.0, cy + 10.0),
		Vector2(cx + 1.0, cy + 10.0),
		Vector2(cx + 5.0, cy + 10.0),
		Vector2(cx - 7.0, cy + 14.0),
		Vector2(cx - 3.0, cy + 14.0),
		Vector2(cx + 1.0, cy + 14.0),
		Vector2(cx + 5.0, cy + 14.0),
	]

static func apply_bright_desert_palette(renderer: IsoTerrainRenderer) -> void:
	renderer.clear_tile_modulates()
	renderer.set_tile_modulate(IsoTerrainRenderer.T_DEEP, Color(0.38, 0.56, 0.68, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_WATER, Color(0.52, 0.68, 0.78, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_SAND, Color(0.88, 0.80, 0.62, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_MOUNTAIN, Color(0.56, 0.62, 0.68, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_GRASS, Color(0.73, 0.78, 0.66, 1.0))
	renderer.set_tile_modulate(IsoTerrainRenderer.T_SNOW, Color(0.86, 0.90, 0.93, 1.0))

static func draw_metal_perimeter(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, layout: Dictionary, pulse_time: float = 0.0) -> void:
	if layout.is_empty():
		return
	var left: int = int(layout.get("ring_left", 0))
	var top: int = int(layout.get("ring_top", 0))
	var right: int = int(layout.get("ring_right", 0))
	var bottom: int = int(layout.get("ring_bottom", 0))
	var gate_center: int = int(layout.get("gate_center", floori(float(left + right) * 0.5)))
	var gate_half: int = floori(float(GATE_WIDTH) * 0.5)

	var shimmer: float = 0.18 + sin(pulse_time * 1.5) * 0.05
	var outer_col: Color = Color(0.34, 0.42, 0.50, 0.95)
	var inner_col: Color = Color(0.55 + shimmer, 0.63 + shimmer, 0.70 + shimmer, 0.78)

	var panel_stride: int = 4
	for x in range(left, right + 1):
		_draw_wall_panel(canvas, origin, tile_w, tile_h, x, top, outer_col, inner_col, x % panel_stride == 0)
		_draw_wall_panel(canvas, origin, tile_w, tile_h, x, bottom, outer_col, inner_col, x % panel_stride == 0)
	for y in range(top + 1, bottom):
		_draw_wall_panel(canvas, origin, tile_w, tile_h, left, y, outer_col, inner_col, y % panel_stride == 0)
		_draw_wall_panel(canvas, origin, tile_w, tile_h, right, y, outer_col, inner_col, y % panel_stride == 0)

	# Gate pylons and closed gate bar.
	_draw_gate_pylon(canvas, origin, tile_w, tile_h, gate_center - gate_half - 1, bottom, pulse_time)
	_draw_gate_pylon(canvas, origin, tile_w, tile_h, gate_center + gate_half + 1, bottom, pulse_time)
	var gate_pos: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(gate_center), float(bottom))
	canvas.draw_line(gate_pos + Vector2(-34.0, 8.0), gate_pos + Vector2(34.0, 8.0), Color(0.92, 0.40, 0.20, 0.95), 3.0)
	canvas.draw_line(gate_pos + Vector2(-34.0, 12.0), gate_pos + Vector2(34.0, 12.0), Color(0.70, 0.72, 0.76, 0.85), 2.0)

static func draw_building_with_doors(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, layout: Dictionary, pulse_time: float = 0.0) -> void:
	if layout.is_empty():
		return
	var bx: int = int(layout.get("building_x", 0))
	var by: int = int(layout.get("building_y", 0))
	var bw: int = int(layout.get("building_w", BUILDING_W))
	var bh: int = int(layout.get("building_h", BUILDING_H))

	var base_col: Color = Color(0.42, 0.46, 0.52, 0.96)
	var side_col: Color = Color(0.30, 0.34, 0.40, 0.96)
	var roof_col: Color = Color(0.76, 0.80, 0.84, 0.97)

	for y in range(by, by + bh):
		for x in range(bx, bx + bw):
			var p0: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(x), float(y))
			var p1: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(x + 1), float(y))
			var p2: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(x + 1), float(y + 1))
			var p3: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(x), float(y + 1))
			var lift := Vector2(0.0, -18.0)
			var t0: Vector2 = p0 + lift
			var t1: Vector2 = p1 + lift
			var t2: Vector2 = p2 + lift
			var t3: Vector2 = p3 + lift

			canvas.draw_colored_polygon(PackedVector2Array([t0, t1, t2, t3]), roof_col)
			canvas.draw_colored_polygon(PackedVector2Array([t1, t2, p2, p1]), base_col)
			canvas.draw_colored_polygon(PackedVector2Array([t2, t3, p3, p2]), side_col)
			if (x + y) % 2 == 0:
				canvas.draw_line(t3.lerp(t2, 0.18), t3.lerp(t2, 0.82), Color(0.24, 0.95, 0.95, 0.20), 1.2)

	var doors: Array = layout.get("door_tiles", [])
	var pulse: float = 0.65 + 0.30 * sin(pulse_time * 5.0)
	var center: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(bx) + float(bw) * 0.5, float(by) + float(bh) * 0.5)
	var roof_rect := Rect2(center.x - 42.0, center.y - 66.0, 84.0, 50.0)
	canvas.draw_texture_rect(BUILDING_DECAL, roof_rect, false, Color(0.84, 0.90, 1.0, 0.26))
	canvas.draw_rect(roof_rect.grow(-5.0), Color(0.10, 0.16, 0.20, 0.20), false, 1.3)
	canvas.draw_rect(Rect2(center.x - 8.0, center.y - 72.0, 16.0, 8.0), Color(0.62, 0.68, 0.74, 0.92))
	canvas.draw_line(Vector2(center.x, center.y - 72.0), Vector2(center.x, center.y - 88.0), Color(0.70, 0.74, 0.80, 0.88), 2.0)
	canvas.draw_circle(Vector2(center.x, center.y - 89.0), 2.6, Color(0.24, 1.0, 0.90, pulse))
	for door in doors:
		var dv: Vector2i = door
		var dc: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(dv.x) + 0.5, float(dv.y) + 0.5)
		canvas.draw_rect(Rect2(dc.x - 5.0, dc.y - 19.0, 10.0, 10.0), Color(0.15, 0.19, 0.24, 0.95))
		canvas.draw_rect(Rect2(dc.x - 3.0, dc.y - 17.0, 6.0, 6.0), Color(0.25, 1.0, 0.72, pulse))

static func get_door_spawn_points(layout: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var doors: Array = layout.get("door_tiles", [])
	for door in doors:
		var dv: Vector2i = door
		out.append(Vector2(float(dv.x) + 0.5, float(dv.y) + 0.5))
	return out

static func _draw_wall_panel(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, tx: int, ty: int, outer_col: Color, inner_col: Color, with_crossbar: bool) -> void:
	var p0: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx), float(ty))
	var p1: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx + 1), float(ty))
	var p2: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx + 1), float(ty + 1))
	var p3: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx), float(ty + 1))

	var lift := Vector2(0.0, -22.0)
	var t0: Vector2 = p0 + lift
	var t1: Vector2 = p1 + lift
	var t2: Vector2 = p2 + lift
	var t3: Vector2 = p3 + lift

	# Isometric top and visible side faces.
	canvas.draw_colored_polygon(PackedVector2Array([t0, t1, t2, t3]), Color(0.70, 0.76, 0.82, 0.95))
	canvas.draw_colored_polygon(PackedVector2Array([t1, t2, p2, p1]), outer_col)
	canvas.draw_colored_polygon(PackedVector2Array([t2, t3, p3, p2]), inner_col)
	canvas.draw_polyline(PackedVector2Array([t0, t1, t2, t3]), Color(0.34, 0.40, 0.48, 0.9), 1.4, true)

	if with_crossbar:
		var cross_a: Vector2 = t3.lerp(t2, 0.28)
		var cross_b: Vector2 = t3.lerp(t2, 0.72)
		canvas.draw_line(cross_a, cross_b, Color(0.82, 0.86, 0.90, 0.92), 1.8)

static func _draw_gate_pylon(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, tx: int, ty: int, pulse_time: float) -> void:
	var p0: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx), float(ty))
	var p1: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx + 1), float(ty))
	var p2: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx + 1), float(ty + 1))
	var p3: Vector2 = _iso_to_screen(origin, tile_w, tile_h, float(tx), float(ty + 1))
	var lift := Vector2(0.0, -34.0)
	var t0: Vector2 = p0 + lift
	var t1: Vector2 = p1 + lift
	var t2: Vector2 = p2 + lift
	var t3: Vector2 = p3 + lift

	canvas.draw_colored_polygon(PackedVector2Array([t0, t1, t2, t3]), Color(0.74, 0.78, 0.84, 0.95))
	canvas.draw_colored_polygon(PackedVector2Array([t1, t2, p2, p1]), Color(0.28, 0.34, 0.42, 0.96))
	canvas.draw_colored_polygon(PackedVector2Array([t2, t3, p3, p2]), Color(0.34, 0.40, 0.48, 0.96))

	var glow: float = 0.70 + 0.20 * sin(pulse_time * 4.0)
	var beacon_center: Vector2 = t3.lerp(t2, 0.5) + Vector2(0.0, 8.0)
	canvas.draw_rect(Rect2(beacon_center.x - 5.0, beacon_center.y - 3.0, 10.0, 7.0), Color(1.0, 0.52, 0.24, glow))

static func _iso_to_screen(origin: Vector2, tile_w: float, tile_h: float, wx: float, wy: float) -> Vector2:
	return origin + Vector2((wx - wy) * tile_w * 0.5, (wx + wy) * tile_h * 0.5)

static func _draw_hollow_rect(tiles: PackedInt32Array, width: int, height: int, left: int, top: int, right: int, bottom: int, tile_id: int) -> void:
	for x in range(left, right + 1):
		_set_tile(tiles, width, height, x, top, tile_id)
		_set_tile(tiles, width, height, x, bottom, tile_id)
	for y in range(top, bottom + 1):
		_set_tile(tiles, width, height, left, y, tile_id)
		_set_tile(tiles, width, height, right, y, tile_id)

static func _draw_lane(tiles: PackedInt32Array, width: int, height: int, x0: int, y0: int, x1: int, y1: int) -> void:
	var sx: int = 1 if x1 >= x0 else -1
	var sy: int = 1 if y1 >= y0 else -1
	var x: int = x0
	var y: int = y0
	while x != x1 or y != y1:
		_set_tile(tiles, width, height, x, y, IsoTerrainRenderer.T_GRASS)
		if x != x1:
			x += sx
		if y != y1:
			y += sy
	_set_tile(tiles, width, height, x1, y1, IsoTerrainRenderer.T_GRASS)

static func _fill_rect(tiles: PackedInt32Array, width: int, height: int, x: int, y: int, w: int, h: int, tile_id: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_set_tile(tiles, width, height, xx, yy, tile_id)

static func _set_tile(tiles: PackedInt32Array, width: int, height: int, x: int, y: int, tile_id: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	tiles[y * width + x] = tile_id
