extends RefCounted
class_name IsoTerrainRenderer

const T_DEEP:  int = 0
const T_WATER: int = 1
const T_SAND:  int = 2

# Spritesheet: 96×128, 3 cols × 2 rows, 32×64 px per tile, drawn at 2× scale.
#  Row 0: shallow water | deep water | sand
#  Row 1: mountain      | snow       | grass
const _TERRAIN_TEX: Texture2D = preload("res://assets/tilesets/tileset.png")
const _SP_W:     int   = 32
const _SP_H:     int   = 64
const _SP_SCALE: float = 2.0
const _SP_INSET: float = 0.5  # prevents linear-filter bleeding between sheet tiles

const _SPRITE_MAP: Dictionary = {
	T_DEEP:  [0, 1],
	T_WATER: [0, 0],
	T_SAND:  [0, 2],
}

var chunk_size: int = 16

var _chunks:     Dictionary  = {}
var _elev_noise: FastNoiseLite = null
var _warp_noise: FastNoiseLite = null

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

func draw_tiles(canvas: CanvasItem, origin: Vector2, viewport: Vector2, tile_w: float, tile_h: float, render_margin: int = 2) -> void:
	if _elev_noise == null:
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

	for cx in range(floori(float(tx_min) / chunk_size), ceili(float(tx_max) / chunk_size) + 1):
		for cy in range(floori(float(ty_min) / chunk_size), ceili(float(ty_max) / chunk_size) + 1):
			_ensure_chunk(cx, cy)

	for diag in range(tx_min + ty_min, tx_max + ty_max + 1):
		for tx in range(maxi(tx_min, diag - ty_max), mini(tx_max, diag - ty_min) + 1):
			_draw_tile(canvas, origin, tile_w, tile_h, tx, diag - tx)

func _draw_tile(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, tx: int, ty: int) -> void:
	var tt:   int   = _get_tile(tx, ty)
	var info: Array = _SPRITE_MAP[tt]
	var src  := Rect2(info[1] * _SP_W + _SP_INSET, info[0] * _SP_H + _SP_INSET,
					  _SP_W - _SP_INSET * 2.0, _SP_H - _SP_INSET * 2.0)
	var dw   := _SP_W * _SP_SCALE
	var dh   := _SP_H * _SP_SCALE
	var top  := _w2s(origin, tile_w, tile_h, tx + 0.5, float(ty))
	canvas.draw_texture_rect_region(_TERRAIN_TEX, Rect2(top.x - dw * 0.5, top.y, dw, dh), src)

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
			elif e < 0.50:
				t = T_WATER
			else:
				t = T_SAND
			data[i * chunk_size + j] = t
	_chunks[key] = data

func get_tile_at(wx: float, wy: float) -> int:
	return _get_tile(floori(wx), floori(wy))

func _get_tile(tx: int, ty: int) -> int:
	var cx: int = floori(float(tx) / chunk_size)
	var cy: int = floori(float(ty) / chunk_size)
	_ensure_chunk(cx, cy)
	var key := Vector2i(cx, cy)
	if not _chunks.has(key):
		return T_SAND
	return _chunks[key][(tx - cx * chunk_size) * chunk_size + (ty - cy * chunk_size)]

func _draw_fallback_tiles(canvas: CanvasItem, origin: Vector2, viewport: Vector2, tile_w: float, tile_h: float) -> void:
	var info: Array = _SPRITE_MAP[T_SAND]
	var src := Rect2(info[1] * _SP_W + _SP_INSET, info[0] * _SP_H + _SP_INSET,
					 _SP_W - _SP_INSET * 2.0, _SP_H - _SP_INSET * 2.0)
	var dw := _SP_W * _SP_SCALE
	var dh := _SP_H * _SP_SCALE
	for row in range(-2, int(ceili(viewport.y / tile_h)) + 6):
		for col in range(-2, int(ceili(viewport.x / tile_w)) + 6):
			var top := _w2s(origin, tile_w, tile_h, col + 0.5, float(row))
			canvas.draw_texture_rect_region(_TERRAIN_TEX, Rect2(top.x - dw * 0.5, top.y, dw, dh), src)
