extends RefCounted
class_name IsoTerrainRenderer

const T_DEEP:  int = 0
const T_WATER: int = 1
const T_SAND:  int = 2
const T_MOUNTAIN: int = 3
const T_SNOW:  int = 4
const T_GRASS: int = 5

const _TEXTURES: Dictionary = {
	T_DEEP:  preload("res://assets/generated/deep_water_tile_frame_0_1773704178.png"),
	T_WATER: preload("res://assets/generated/shallow_water_tile_frame_0_1773704180.png"),
	T_SAND:  preload("res://assets/generated/sand_tile_frame_0_1773704178.png"),
	T_MOUNTAIN: preload("res://assets/generated/mountain_tile_frame_0_1773704179.png"),
	T_SNOW:  preload("res://assets/generated/snow_tile_frame_0_1773704189.png"),
	T_GRASS: preload("res://assets/generated/grass_tile_frame_0_1773704181.png"),
}

const _SP_W:	 int   = 64
const _SP_H:	 int   = 64
const _SP_SCALE: float = 1.0 # New textures are already 64x64

var chunk_size: int = 16

var _chunks:     Dictionary  = {}
var _elev_noise: FastNoiseLite = null
var _warp_noise: FastNoiseLite = null

var _static_mode:    bool            = false
var _static_width:   int             = 0
var _static_height:  int             = 0
var _static_tiles:   PackedByteArray = PackedByteArray()
var _overview_tex:   ImageTexture    = null
var _tile_modulate:  Dictionary      = {}

# LOD threshold: use overview texture when tiles are smaller than this many pixels wide
const _LOD_TILE_PX: float = 4.0
const _C_DEEP:  Color = Color(0.04, 0.15, 0.35)
const _C_WATER: Color = Color(0.12, 0.42, 0.70)
const _C_SAND:  Color = Color(0.76, 0.65, 0.40)

func configure_seed(seed_val: int) -> void:
	_elev_noise = FastNoiseLite.new()
	_elev_noise.seed               = seed_val
	_elev_noise.noise_type         = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elev_noise.frequency          = 0.04
	_elev_noise.fractal_type       = FastNoiseLite.FRACTAL_FBM
	_elev_noise.fractal_octaves    = 3
	_elev_noise.fractal_lacunarity = 2.0
	_elev_noise.fractal_gain       = 0.45

	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed       = seed_val + 1
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp_noise.frequency  = 0.08

	_chunks.clear()

func load_static_map(data: Dictionary) -> void:
	_static_width  = int(data["width"])
	_static_height = int(data["height"])
	var raw: Array = data["tiles"]
	_static_tiles.resize(_static_width * _static_height)
	for i in range(_static_tiles.size()):
		_static_tiles[i] = int(raw[i])
	_static_mode = true
	_chunks.clear()
	_bake_overview_texture()

func set_tile_modulate(tile_id: int, color: Color) -> void:
	_tile_modulate[tile_id] = color
	if _static_mode:
		_bake_overview_texture()

func clear_tile_modulates() -> void:
	_tile_modulate.clear()
	if _static_mode:
		_bake_overview_texture()

func _bake_overview_texture() -> void:
	var img := Image.create(_static_width, _static_height, false, Image.FORMAT_RGB8)
	for ty in range(_static_height):
		for tx in range(_static_width):
			var t := int(_static_tiles[ty * _static_width + tx])
			var c: Color
			match t:
				T_DEEP:  c = _C_DEEP
				T_WATER: c = _C_WATER
				_:       c = _C_SAND
			if _tile_modulate.has(t):
				c = _tile_modulate[t]
			img.set_pixel(tx, ty, c)
	_overview_tex = ImageTexture.create_from_image(img)

func draw_tiles(canvas: CanvasItem, origin: Vector2, viewport: Vector2, tile_w: float, tile_h: float, render_margin: int = 2) -> void:
	if _elev_noise == null and not _static_mode:
		_draw_fallback_tiles(canvas, origin, viewport, tile_w, tile_h)
		return

	var hw := tile_w * 0.5
	var hh := tile_h * 0.5
	var tx_min := 999999;  var tx_max := -999999
	var ty_min := 999999;  var ty_max := -999999
	for corner in [Vector2.ZERO, Vector2(viewport.x, 0.0), Vector2(0.0, viewport.y), viewport]:
		var u: float = (corner.x - origin.x) / hw
		var v: float = (corner.y - origin.y) / hh
		tx_min = mini(tx_min, floori((u + v) * 0.5) - render_margin)
		tx_max = maxi(tx_max, ceili((u + v) * 0.5) + render_margin)
		ty_min = mini(ty_min, floori((v - u) * 0.5) - render_margin)
		ty_max = maxi(ty_max, ceili((v - u) * 0.5) + render_margin)

	# Clamp to map bounds so zooming out never generates a million-tile range
	if _static_mode:
		tx_min = maxi(tx_min, 0)
		tx_max = mini(tx_max, _static_width - 1)
		ty_min = maxi(ty_min, 0)
		ty_max = mini(ty_max, _static_height - 1)
		# LOD: when tiles are sub-pixel, draw the pre-baked overview texture
		if tile_w < _LOD_TILE_PX and _overview_tex != null:
			var xform := Transform2D(
				Vector2(tile_w * 0.5, tile_h * 0.5),
				Vector2(-tile_w * 0.5, tile_h * 0.5),
				origin)
			canvas.draw_set_transform_matrix(xform)
			canvas.draw_texture(_overview_tex, Vector2.ZERO)
			canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
			return

	for cx in range(floori(float(tx_min) / chunk_size), ceili(float(tx_max) / chunk_size) + 1):
		for cy in range(floori(float(ty_min) / chunk_size), ceili(float(ty_max) / chunk_size) + 1):
			_ensure_chunk(cx, cy)

	for diag in range(tx_min + ty_min, tx_max + ty_max + 1):
		for tx in range(maxi(tx_min, diag - ty_max), mini(tx_max, diag - ty_min) + 1):
			_draw_tile(canvas, origin, tile_w, tile_h, tx, diag - tx)

func _draw_tile(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, tx: int, ty: int) -> void:
	var tt:   int   = _get_tile(tx, ty)
	var tex: Texture2D = _TEXTURES.get(tt, _TEXTURES[T_SAND])
	var modulate_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	if _tile_modulate.has(tt):
		modulate_color = _tile_modulate[tt]
	var dw   := float(_SP_W) * _SP_SCALE
	var dh   := float(_SP_H) * _SP_SCALE
	var top  := _w2s(origin, tile_w, tile_h, tx + 0.5, float(ty))
	canvas.draw_texture_rect(tex, Rect2(top.x - dw * 0.5, top.y, dw, dh), false, modulate_color)

func _w2s(origin: Vector2, tile_w: float, tile_h: float, wx: float, wy: float) -> Vector2:
	return origin + Vector2((wx - wy) * tile_w * 0.5, (wx + wy) * tile_h * 0.5)

func _ensure_chunk(cx: int, cy: int) -> void:
	var key := Vector2i(cx, cy)
	if _chunks.has(key) or _elev_noise == null:
		return

	const PAD := 1
	var sz: int = chunk_size + 2 * PAD
	var raw: Array = []
	for i in range(sz):
		raw.append([])
		for j in range(sz):
			var wx: float = float(cx * chunk_size + i - PAD)
			var wy: float = float(cy * chunk_size + j - PAD)
			var dwx: float = wx + _warp_noise.get_noise_2d(wx, wy) * 4.0
			var dwy: float = wy + _warp_noise.get_noise_2d(wx + 100.0, wy + 100.0) * 4.0
			raw[i].append(_elev_noise.get_noise_2d(dwx, dwy))

	var data := PackedByteArray()
	data.resize(chunk_size * chunk_size)
	for i in range(chunk_size):
		for j in range(chunk_size):
			var e: float = float(raw[i + PAD][j + PAD])
			var t: int
			if e < -0.15:
				t = T_DEEP
			elif e < 0.20:
				t = T_WATER
			elif e < 0.45:
				t = T_SAND
			elif e < 0.70:
				t = T_GRASS
			elif e < 0.85:
				t = T_MOUNTAIN
			else:
				t = T_SNOW
			data[i * chunk_size + j] = t
	_chunks[key] = data

func _get_tile(tx: int, ty: int) -> int:
	if _static_mode:
		if tx < 0 or tx >= _static_width or ty < 0 or ty >= _static_height:
			return T_DEEP
		return int(_static_tiles[ty * _static_width + tx])
	var cx: int = floori(float(tx) / chunk_size)
	var cy: int = floori(float(ty) / chunk_size)
	_ensure_chunk(cx, cy)
	var key := Vector2i(cx, cy)
	if not _chunks.has(key):
		return T_SAND
	return _chunks[key][(tx - cx * chunk_size) * chunk_size + (ty - cy * chunk_size)]

func get_tile_at(wx: float, wy: float) -> int:
	if _elev_noise == null and not _static_mode:
		return T_SAND
	return _get_tile(floori(wx), floori(wy))


## When world coords pack multiple units per logical tile (req-naval-combat-prototype-v1 §2.1).
func get_tile_at_world_units(wx: float, wy: float, units_per_tile: float) -> int:
	if units_per_tile <= 1.0001:
		return get_tile_at(wx, wy)
	if _elev_noise == null and not _static_mode:
		return T_SAND
	return _get_tile(floori(wx / units_per_tile), floori(wy / units_per_tile))

func _draw_fallback_tiles(canvas: CanvasItem, origin: Vector2, viewport: Vector2, tile_w: float, tile_h: float) -> void:
	var tex: Texture2D = _TEXTURES[T_SAND]
	var dw := float(_SP_W) * _SP_SCALE
	var dh := float(_SP_H) * _SP_SCALE
	for row in range(-2, int(ceili(viewport.y / tile_h)) + 6):
		for col in range(-2, int(ceili(viewport.x / tile_w)) + 6):
			var top := _w2s(origin, tile_w, tile_h, col + 0.5, float(row))
			canvas.draw_texture_rect(tex, Rect2(top.x - dw * 0.5, top.y, dw, dh), false)
