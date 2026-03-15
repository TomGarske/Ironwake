extends RefCounted
class_name IsoTerrainRenderer

const T_DEEP: int = 0
const T_WATER: int = 1
const T_SAND: int = 2
const T_GRASS: int = 3
const T_FOREST: int = 4
const T_MTN: int = 5
const T_SNOW: int = 6

# ── Terrain tileset ────────────────────────────────────────────────────────────
# Spritesheet is 96×128 → 3 cols × 2 rows → 32×64 px per tile.
# Drawn at 2× scale → 64×128 px, matching TILE_W=64 / TILE_H=32 exactly.
#
#  Row 0: shallow water | deep water | sand
#  Row 1: mountain      | snow       | forest/grass
const _TERRAIN_TEX_PATH: String = "res://assets/tilesets/tileset.png"
const _SP_W: int = 32   # tile width in sheet
const _SP_H: int = 64   # tile height in sheet
const _SP_SCALE: float = 2.0

# Per terrain type: [sheet_row, sheet_col]
const _SPRITE_MAP: Dictionary = {
	T_DEEP:   [0, 1],
	T_WATER:  [0, 0],
	T_SAND:   [0, 2],
	T_GRASS:  [1, 2],
	T_FOREST: [1, 2],
	T_MTN:    [1, 0],
	T_SNOW:   [1, 1],
}

const _TC: Array = [
	[Color(0.05, 0.12, 0.44), Color(0.02, 0.06, 0.26)],  # deep water
	[Color(0.12, 0.28, 0.68), Color(0.07, 0.16, 0.42)],  # shallow water
	[Color(0.74, 0.68, 0.46), Color(0.46, 0.40, 0.24)],  # sand
	[Color(0.22, 0.50, 0.16), Color(0.10, 0.26, 0.07)],  # grass
	[Color(0.10, 0.30, 0.10), Color(0.05, 0.16, 0.05)],  # forest
	[Color(0.48, 0.46, 0.42), Color(0.26, 0.24, 0.20)],  # mountain
	[Color(0.82, 0.84, 0.88), Color(0.58, 0.60, 0.64)],  # snow
]

var chunk_size: int = 16

var _chunks: Dictionary = {}
var _elev_noise: FastNoiseLite = null
var _warp_noise: FastNoiseLite = null
var _moist_noise: FastNoiseLite = null
var _terrain_tex: Texture2D = null

func configure_seed(seed_val: int) -> void:
	# Keep map rendering resilient even when optional art assets are missing.
	if ResourceLoader.exists(_TERRAIN_TEX_PATH):
		_terrain_tex = load(_TERRAIN_TEX_PATH) as Texture2D
	else:
		_terrain_tex = null
	_elev_noise = FastNoiseLite.new()
	_elev_noise.seed               = seed_val
	_elev_noise.noise_type         = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elev_noise.frequency          = 0.06
	_elev_noise.fractal_type       = FastNoiseLite.FRACTAL_FBM
	_elev_noise.fractal_octaves    = 5
	_elev_noise.fractal_lacunarity = 2.0
	_elev_noise.fractal_gain       = 0.50

	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed       = seed_val + 1
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp_noise.frequency  = 0.12

	_moist_noise = FastNoiseLite.new()
	_moist_noise.seed       = seed_val + 2
	_moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moist_noise.frequency  = 0.09

	_chunks.clear()

func draw_tiles(canvas: CanvasItem, origin: Vector2, viewport: Vector2, tile_w: float, tile_h: float, render_margin: int = 2) -> void:
	if _elev_noise == null:
		_draw_fallback_tiles(canvas, origin, viewport, tile_w, tile_h)
		return
	var hw := tile_w * 0.5
	var hh := tile_h * 0.5
	var tx_min := 999999
	var tx_max := -999999
	var ty_min := 999999
	var ty_max := -999999
	for corner in [Vector2.ZERO, Vector2(viewport.x, 0.0), Vector2(0.0, viewport.y), viewport]:
		var u: float = (corner.x - origin.x) / hw
		var v: float = (corner.y - origin.y) / hh
		tx_min = mini(tx_min, floori((u + v) * 0.5) - render_margin)
		tx_max = maxi(tx_max, ceili((u + v) * 0.5) + render_margin)
		ty_min = mini(ty_min, floori((v - u) * 0.5) - render_margin)
		ty_max = maxi(ty_max, ceili((v - u) * 0.5) + render_margin)

	var cx_min: int = floori(float(tx_min) / chunk_size)
	var cx_max: int = ceili(float(tx_max) / chunk_size)
	var cy_min: int = floori(float(ty_min) / chunk_size)
	var cy_max: int = ceili(float(ty_max) / chunk_size)
	for cx in range(cx_min, cx_max + 1):
		for cy in range(cy_min, cy_max + 1):
			_ensure_chunk(cx, cy)

	var d_min: int = tx_min + ty_min
	var d_max: int = tx_max + ty_max
	for diag in range(d_min, d_max + 1):
		var tx_lo: int = maxi(tx_min, diag - ty_max)
		var tx_hi: int = mini(tx_max, diag - ty_min)
		for tx in range(tx_lo, tx_hi + 1):
			_draw_tile(canvas, origin, tile_w, tile_h, tx, diag - tx)

func _draw_tile(canvas: CanvasItem, origin: Vector2, tile_w: float, tile_h: float, tx: int, ty: int) -> void:
	var top := _w2s(origin, tile_w, tile_h, tx + 0.5, float(ty))

	var tt: int = _get_tile(tx, ty)

	# Draw sprite tiles when the texture sheet is available.
	if _terrain_tex != null and _SPRITE_MAP.has(tt):
		var info: Array = _SPRITE_MAP[tt]
		var src  := Rect2(info[1] * _SP_W, info[0] * _SP_H, _SP_W, _SP_H)
		var dw   := _SP_W * _SP_SCALE
		var dh   := _SP_H * _SP_SCALE
		var dest := Rect2(top.x - dw * 0.5, top.y, dw, dh)
		canvas.draw_texture_rect_region(_terrain_tex, dest, src)
		return

	# Fallback rendering keeps gameplay usable when art assets are unavailable.
	var rgt := _w2s(origin, tile_w, tile_h, float(tx + 1), ty + 0.5)
	var bot := _w2s(origin, tile_w, tile_h, tx + 0.5, float(ty + 1))
	var lft := _w2s(origin, tile_w, tile_h, float(tx), ty + 0.5)
	var tc: Array = _TC[tt]
	var face: Color = tc[0].lightened(0.06) if (tt == T_DEEP or tt == T_WATER) and (tx + ty) % 2 == 0 else tc[0]
	canvas.draw_polygon(PackedVector2Array([top, rgt, bot, lft]), PackedColorArray([face]))
	canvas.draw_line(lft, bot, tc[1], 1.2)
	canvas.draw_line(rgt, bot, tc[1], 1.2)

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

	for _pass in range(2):
		var sm: Array = []
		for i in range(sz):
			sm.append([])
			for j in range(sz):
				var sum: float = 0.0
				var cnt: int = 0
				for oi in range(-1, 2):
					for oj in range(-1, 2):
						var ni: int = i + oi
						var nj: int = j + oj
						if ni >= 0 and ni < sz and nj >= 0 and nj < sz:
							var w: float = 0.5 if (oi != 0 and oj != 0) else 1.0
							sum += float(raw[ni][nj]) * w
							cnt += 1 if oi == 0 or oj == 0 else 0
				sm[i].append(sum / float(maxi(cnt, 1)))
		raw = sm

	var data := PackedByteArray()
	data.resize(chunk_size * chunk_size)
	for i in range(chunk_size):
		for j in range(chunk_size):
			var e: float = float(raw[i + PAD][j + PAD])
			var wx: float = float(cx * chunk_size + i)
			var wy: float = float(cy * chunk_size + j)
			var m: float = _moist_noise.get_noise_2d(wx, wy)
			var t: int
			if e < -0.30:
				t = T_DEEP
			elif e < -0.05:
				t = T_WATER
			elif e < 0.10:
				t = T_SAND
			elif e < 0.35:
				t = T_FOREST if m > 0.10 else T_GRASS
			elif e < 0.55:
				t = T_MTN
			else:
				t = T_SNOW
			data[i * chunk_size + j] = t
	_chunks[key] = data

func _get_tile(tx: int, ty: int) -> int:
	var cx: int = floori(float(tx) / chunk_size)
	var cy: int = floori(float(ty) / chunk_size)
	_ensure_chunk(cx, cy)
	var key := Vector2i(cx, cy)
	if not _chunks.has(key):
		return T_GRASS
	var lx: int = tx - cx * chunk_size
	var ly: int = ty - cy * chunk_size
	return _chunks[key][lx * chunk_size + ly]

func get_tile_at(wx: float, wy: float) -> int:
	# Public sampling helper used by gameplay logic (movement slowdown/blocking).
	if _elev_noise == null:
		return T_GRASS
	return _get_tile(floori(wx), floori(wy))

func _draw_fallback_tiles(canvas: CanvasItem, origin: Vector2, viewport: Vector2, tile_w: float, tile_h: float) -> void:
	var rows: int = int(ceili(viewport.y / tile_h)) + 6
	var cols: int = int(ceili(viewport.x / tile_w)) + 6
	for row in range(-2, rows):
		for col in range(-2, cols):
			var tx: int = col
			var ty: int = row
			var top := _w2s(origin, tile_w, tile_h, tx + 0.5, float(ty))
			var rgt := _w2s(origin, tile_w, tile_h, float(tx + 1), ty + 0.5)
			var bot := _w2s(origin, tile_w, tile_h, tx + 0.5, float(ty + 1))
			var lft := _w2s(origin, tile_w, tile_h, float(tx), ty + 0.5)
			var color: Color = Color(0.14, 0.26, 0.18) if (tx + ty) % 2 == 0 else Color(0.11, 0.21, 0.15)
			canvas.draw_polygon(PackedVector2Array([top, rgt, bot, lft]), PackedColorArray([color]))
