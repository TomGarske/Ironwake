extends Node2D
class_name FogDrawer

## Civ-style fog of war drawn via _draw() each frame.
##
## Three tiers:
##   VISIBLE  — hex currently in a creature's vision radius  → nothing drawn (full color)
##   SEEN     — hex revealed before but not currently visible → grey semi-transparent overlay
##   UNSEEN   — hex never seen                               → fully black
##
## Drawn as hex polygons matching the terrain tile size.  Lives in the 2D scene
## tree and is therefore naturally below all CanvasLayer UI nodes.

const UNSEEN_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const SEEN_COLOR   := Color(0.25, 0.25, 0.25, 0.65)

## How many extra rings beyond a creature's vision radius get the grey "seen" overlay
const SEEN_RING_WIDTH := 3

## Hex half-extents matching the 64×56 terrain atlas tiles (flat-top hexagon)
const HEX_RX := 30.0
const HEX_RY := 26.0

var _seen_hexes:    Dictionary = {}   # Vector2i → true
var _visible_hexes: Dictionary = {}   # Vector2i → true (rebuilt each reveal call)

var _terrain_layer: TileMapLayer
var _camera: Camera2D


func _ready() -> void:
	_terrain_layer = get_parent().get_node("TerrainLayer") as TileMapLayer
	_camera        = get_parent().get_node("Camera2D")     as Camera2D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _terrain_layer or not _camera:
		return

	# Convert camera viewport corners to hex grid coordinates
	var vp_size := get_viewport().get_visible_rect().size
	var cam_pos  := _camera.global_position
	var zoom     := _camera.zoom
	var half_vp  := vp_size * 0.5 / zoom

	var tl := _terrain_layer.local_to_map(
		_terrain_layer.to_local(cam_pos - half_vp))
	var br := _terrain_layer.local_to_map(
		_terrain_layer.to_local(cam_pos + half_vp))

	# 1-cell margin so hex edges don't pop in at screen borders
	tl = Vector2i(maxi(0,   tl.x - 1), maxi(0,  tl.y - 1))
	br = Vector2i(mini(179, br.x + 1), mini(89, br.y + 1))

	for col in range(tl.x, br.x + 1):
		for row in range(tl.y, br.y + 1):
			var cell := Vector2i(col, row)
			if _visible_hexes.has(cell):
				continue  # fully visible — draw nothing
			var center := _terrain_layer.map_to_local(cell)
			if _seen_hexes.has(cell):
				_draw_hex(center, SEEN_COLOR)
			else:
				_draw_hex(center, UNSEEN_COLOR)


func _draw_hex(center: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(HEX_RX * cos(a), HEX_RY * sin(a)))
	draw_colored_polygon(pts, color)


## Reveals hexes around `center`:
##   inner `radius` rings  → VISIBLE (fog cleared)
##   next SEEN_RING_WIDTH rings → SEEN (grey overlay)
## Already-revealed cells are never re-darkened.
func reveal_hexes(center: Vector2i, radius: int) -> void:
	if not _terrain_layer:
		return
	_seen_hexes[center]    = true
	_visible_hexes[center] = true

	var visited: Dictionary = {center: true}
	var ring: Array[Vector2i] = [center]
	var total := radius + SEEN_RING_WIDTH

	for r in total:
		var next: Array[Vector2i] = []
		for cell: Vector2i in ring:
			for nb: Vector2i in _terrain_layer.get_surrounding_cells(cell):
				if visited.has(nb):
					continue
				visited[nb] = true
				next.append(nb)
				_seen_hexes[nb] = true
				if r < radius:
					_visible_hexes[nb] = true
		ring = next


func is_hex_seen(cell: Vector2i) -> bool:
	return _seen_hexes.has(cell)


func clear_current_visibility() -> void:
	_visible_hexes.clear()
