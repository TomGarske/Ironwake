extends Node2D

## 16-bit style 2D side-scrolling background.
## Draws sky bands, stars, layered mountain silhouettes, ground, and
## an armored knight that walks back and forth on the horizon.
## Add as a child of TacticalMap with z_index = -10.

# ── Palette ──────────────────────────────────────────────────────────────────
const _C_SKY   := [
	Color(0.03, 0.05, 0.18),  # midnight
	Color(0.06, 0.10, 0.28),  # deep blue
	Color(0.10, 0.20, 0.42),  # mid blue
	Color(0.18, 0.35, 0.55),  # pale blue
	Color(0.32, 0.52, 0.68),  # horizon
]
const _C_MTN_FAR  := Color(0.30, 0.38, 0.58)
const _C_MTN_MID  := Color(0.18, 0.24, 0.38)
const _C_GND_TOP  := Color(0.08, 0.18, 0.10)
const _C_GND_BOT  := Color(0.04, 0.10, 0.06)
const _C_GRASS    := Color(0.22, 0.58, 0.18)
const _C_DIRT     := Color(0.20, 0.14, 0.08)

const _C_STEEL    := Color(0.55, 0.60, 0.65)
const _C_STEEL_HI := Color(0.74, 0.80, 0.86)
const _C_STEEL_SH := Color(0.27, 0.31, 0.36)
const _C_GOLD     := Color(0.86, 0.72, 0.18)
const _C_VISOR    := Color(0.04, 0.07, 0.16)
const _C_DARK     := Color(0.06, 0.07, 0.10)
const _C_PLUME_A  := Color(0.78, 0.12, 0.08)
const _C_PLUME_B  := Color(0.95, 0.30, 0.10)
const _C_PLUME_C  := Color(1.00, 0.55, 0.10)

# ── Walker state ──────────────────────────────────────────────────────────────
var _walker_x:   float = 640.0
var _walker_dir: float = 1.0   # 1 = right, -1 = left
var _walk_time:  float = 0.0
const _WALK_SPEED: float = 70.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	z_index = -10
	queue_redraw()

func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	if _walker_x <= 0.0:
		_walker_x = vp.x * 0.5
	_walk_time  += delta
	_walker_x   += _WALK_SPEED * _walker_dir * delta
	if _walker_x > vp.x * 0.88:
		_walker_dir = -1.0
	elif _walker_x < vp.x * 0.12:
		_walker_dir =  1.0
	queue_redraw()

# ── Draw entry ────────────────────────────────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_sky(vp)
	_draw_stars(vp)
	_draw_far_mountains(vp)
	_draw_near_mountains(vp)
	_draw_ground(vp)
	_draw_knight(vp)

# ── Sky ───────────────────────────────────────────────────────────────────────
func _draw_sky(vp: Vector2) -> void:
	var stops: Array[float] = [0.00, 0.14, 0.30, 0.46, 0.58, 0.65]
	for i in range(_C_SKY.size()):
		var y0: float = stops[i] * vp.y
		var y1: float = stops[i + 1] * vp.y
		draw_rect(Rect2(0.0, y0, vp.x, y1 - y0 + 1.0), _C_SKY[i])

# ── Stars ─────────────────────────────────────────────────────────────────────
func _draw_stars(vp: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDEAD_BEEF
	for _i in 150:
		var x  := int(rng.randf_range(0.0, vp.x))
		var y  := int(rng.randf_range(0.0, vp.y * 0.50))
		var b  := rng.randf_range(0.5, 1.0)
		var sz := 1 if rng.randf() < 0.72 else 2
		draw_rect(Rect2(x, y, sz, sz), Color(b, b, b * 0.92, 0.88))

# ── Mountain helpers ──────────────────────────────────────────────────────────
func _mountain_poly(vp: Vector2, peaks: Array, base_frac: float, col: Color) -> void:
	var w := vp.x
	var h := vp.y
	var base_y := base_frac * h
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, base_y))
	for p in peaks:
		pts.append(Vector2(p[0] * w, p[1] * h))
	pts.append(Vector2(w, base_y))
	pts.append(Vector2(w, h))
	pts.append(Vector2(0.0, h))
	draw_polygon(pts, PackedColorArray([col]))

func _draw_far_mountains(vp: Vector2) -> void:
	_mountain_poly(vp, [
		[0.00, 0.54], [0.06, 0.43], [0.13, 0.52], [0.20, 0.38],
		[0.28, 0.46], [0.36, 0.35], [0.44, 0.44], [0.51, 0.37],
		[0.59, 0.45], [0.67, 0.33], [0.74, 0.42], [0.82, 0.38],
		[0.90, 0.47], [0.97, 0.41], [1.00, 0.50],
	], 0.63, _C_MTN_FAR)

func _draw_near_mountains(vp: Vector2) -> void:
	_mountain_poly(vp, [
		[0.00, 0.60], [0.07, 0.47], [0.17, 0.56], [0.27, 0.43],
		[0.38, 0.53], [0.47, 0.41], [0.56, 0.51], [0.65, 0.45],
		[0.74, 0.54], [0.84, 0.42], [0.93, 0.56], [1.00, 0.51],
	], 0.65, _C_MTN_MID)

# ── Ground ────────────────────────────────────────────────────────────────────
func _draw_ground(vp: Vector2) -> void:
	var w := vp.x
	var h := vp.y
	draw_rect(Rect2(0.0, h * 0.65, w, h * 0.35), _C_GND_TOP)
	draw_rect(Rect2(0.0, h * 0.72, w, h * 0.28), _C_GND_BOT)
	# Bright pixel-art grass edge
	draw_rect(Rect2(0.0, h * 0.650, w, 3.0), _C_GRASS)
	draw_rect(Rect2(0.0, h * 0.653, w, 2.0), Color(0.14, 0.40, 0.12))
	# Dirt path through the middle
	draw_rect(Rect2(w * 0.30, h * 0.650, w * 0.40, h * 0.05), _C_DIRT)
	draw_rect(Rect2(w * 0.30, h * 0.650, w * 0.40, 2.0), Color(0.30, 0.22, 0.12))

# ── Knight ────────────────────────────────────────────────────────────────────
# Helper: draw a filled rect relative to a (base_x, fy) anchor.
func _kr(base_x: float, fy: float, ox: float, oy: float, rw: float, rh: float, col: Color) -> void:
	draw_rect(Rect2(base_x + ox, fy + oy, rw, rh), col)

func _draw_knight(vp: Vector2) -> void:
	var phase:  float = sin(_walk_time * 5.0)           # -1..1 walk cycle
	var stride: float = phase * 8.0 * _walker_dir       # leg spread in screen-x
	var swing:  float = -stride * 0.6                   # arm counter-swing
	var bob:    float = -absf(phase) * 2.5              # vertical body bob
	_draw_knight_at(_walker_x, vp.y * 0.65 + bob, stride, swing)

func _draw_knight_at(cx: float, fy: float, stride: float, swing: float) -> void:
	# Limb x-anchors — torso/head stay at cx, limbs stride independently.
	var rl := cx + stride   # right leg
	var ll := cx - stride   # left leg
	var ra := cx + swing    # right arm
	var la := cx - swing    # left arm
	# ── Feet (sabatons) ──────────────────────────────────────────────────────
	_kr(ll, fy, -18.0, -12.0, 15.0, 12.0, _C_STEEL)
	_kr(rl, fy,   3.0, -12.0, 15.0, 12.0, _C_STEEL)
	_kr(ll, fy, -18.0, -12.0, 15.0,  2.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -12.0, 15.0,  2.0, _C_STEEL_HI)
	_kr(ll, fy, -18.0,  -3.0, 15.0,  3.0, _C_STEEL_SH)
	_kr(rl, fy,   3.0,  -3.0, 15.0,  3.0, _C_STEEL_SH)

	# ── Greaves (lower legs) ─────────────────────────────────────────────────
	_kr(ll, fy, -15.0, -46.0, 12.0, 34.0, _C_STEEL)
	_kr(rl, fy,   3.0, -46.0, 12.0, 34.0, _C_STEEL)
	_kr(ll, fy, -15.0, -46.0,  2.0, 34.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -46.0,  2.0, 34.0, _C_STEEL_HI)
	_kr(ll, fy,  -4.0, -46.0,  2.0, 34.0, _C_STEEL_SH)
	_kr(rl, fy,  13.0, -46.0,  2.0, 34.0, _C_STEEL_SH)

	# ── Kneecaps ─────────────────────────────────────────────────────────────
	_kr(ll, fy, -16.0, -54.0, 13.0,  9.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -54.0, 13.0,  9.0, _C_STEEL_HI)
	_kr(ll, fy, -15.0, -54.0, 11.0,  2.0, _C_GOLD)
	_kr(rl, fy,   4.0, -54.0, 11.0,  2.0, _C_GOLD)

	# ── Thighs ───────────────────────────────────────────────────────────────
	_kr(ll, fy, -14.0, -84.0, 12.0, 30.0, _C_STEEL)
	_kr(rl, fy,   2.0, -84.0, 12.0, 30.0, _C_STEEL)
	_kr(ll, fy, -14.0, -84.0,  2.0, 30.0, _C_STEEL_HI)
	_kr(rl, fy,   2.0, -84.0,  2.0, 30.0, _C_STEEL_HI)
	_kr(ll, fy,  -3.0, -84.0,  2.0, 30.0, _C_STEEL_SH)
	_kr(rl, fy,  13.0, -84.0,  2.0, 30.0, _C_STEEL_SH)

	# ── Hips / Faulds (fixed to torso) ───────────────────────────────────────
	_kr(cx, fy, -20.0, -98.0, 40.0, 16.0, _C_STEEL_SH)
	_kr(cx, fy, -20.0, -98.0, 40.0,  3.0, _C_STEEL)
	_kr(cx, fy, -20.0, -99.0, 40.0,  2.0, _C_GOLD)

	# ── Breastplate / Torso ───────────────────────────────────────────────────
	_kr(cx, fy, -18.0, -156.0, 36.0, 58.0, _C_STEEL)
	_kr(cx, fy, -18.0, -156.0,  3.0, 58.0, _C_STEEL_HI)
	_kr(cx, fy,  15.0, -156.0,  3.0, 58.0, _C_STEEL_SH)
	_kr(cx, fy,  -2.0, -156.0,  4.0, 58.0, _C_STEEL_HI)
	_kr(cx, fy, -18.0, -156.0, 36.0,  3.0, _C_GOLD)
	_kr(cx, fy, -18.0, -100.0, 36.0,  3.0, _C_GOLD)

	# ── Pauldrons (fixed to torso) ────────────────────────────────────────────
	_kr(cx, fy, -34.0, -156.0, 18.0, 22.0, _C_STEEL)
	_kr(cx, fy,  16.0, -156.0, 18.0, 22.0, _C_STEEL)
	_kr(cx, fy, -34.0, -156.0, 18.0,  2.0, _C_STEEL_HI)
	_kr(cx, fy,  16.0, -156.0, 18.0,  2.0, _C_STEEL_HI)
	_kr(cx, fy, -34.0, -156.0,  2.0, 22.0, _C_STEEL_HI)
	_kr(cx, fy,  32.0, -156.0,  2.0, 22.0, _C_STEEL_SH)
	_kr(cx, fy, -34.0, -158.0, 18.0,  2.0, _C_GOLD)
	_kr(cx, fy,  16.0, -158.0, 18.0,  2.0, _C_GOLD)

	# ── Upper arms (swing with arms) ──────────────────────────────────────────
	_kr(la, fy, -32.0, -136.0, 10.0, 36.0, _C_STEEL)
	_kr(ra, fy,  22.0, -136.0, 10.0, 36.0, _C_STEEL)
	_kr(la, fy, -32.0, -136.0,  2.0, 36.0, _C_STEEL_HI)
	_kr(ra, fy,  30.0, -136.0,  2.0, 36.0, _C_STEEL_SH)

	# ── Vambraces (lower arms) ────────────────────────────────────────────────
	_kr(la, fy, -30.0, -100.0,  9.0, 28.0, _C_STEEL)
	_kr(ra, fy,  21.0, -100.0,  9.0, 28.0, _C_STEEL)
	_kr(la, fy, -30.0, -100.0,  2.0, 28.0, _C_STEEL_HI)
	_kr(ra, fy,  28.0, -100.0,  2.0, 28.0, _C_STEEL_SH)

	# ── Gauntlets ────────────────────────────────────────────────────────────
	_kr(la, fy, -30.0, -74.0, 12.0, 14.0, _C_STEEL_SH)
	_kr(ra, fy,  18.0, -74.0, 12.0, 14.0, _C_STEEL_SH)
	_kr(la, fy, -30.0, -74.0, 12.0,  2.0, _C_STEEL)
	_kr(ra, fy,  18.0, -74.0, 12.0,  2.0, _C_STEEL)

	# ── Gorget / Helmet / Plume (fixed to torso) ──────────────────────────────
	_kr(cx, fy, -10.0, -166.0, 20.0, 12.0, _C_STEEL)
	_kr(cx, fy, -10.0, -166.0, 20.0,  2.0, _C_GOLD)
	_kr(cx, fy,  -8.0, -167.0, 16.0,  2.0, _C_STEEL_HI)

	_kr(cx, fy, -18.0, -208.0, 36.0, 44.0, _C_STEEL)
	_kr(cx, fy, -18.0, -208.0,  3.0, 44.0, _C_STEEL_HI)
	_kr(cx, fy,  15.0, -208.0,  3.0, 44.0, _C_STEEL_SH)
	_kr(cx, fy, -22.0, -192.0,  5.0, 28.0, _C_STEEL_SH)
	_kr(cx, fy,  17.0, -192.0,  5.0, 28.0, _C_STEEL_SH)
	_kr(cx, fy, -16.0, -192.0, 32.0,  4.0, _C_VISOR)
	_kr(cx, fy,  -2.0, -192.0,  4.0, 24.0, _C_VISOR)
	_kr(cx, fy, -17.0, -193.0, 34.0,  5.0, _C_GOLD)
	_kr(cx, fy,  -2.0, -208.0,  4.0, 10.0, _C_STEEL_HI)
	_kr(cx, fy, -18.0, -168.0, 36.0,  3.0, _C_GOLD)

	_kr(cx, fy,  -4.0, -222.0,  8.0, 16.0, _C_DARK)
	_kr(cx, fy,  -6.0, -238.0, 12.0, 16.0, _C_PLUME_A)
	_kr(cx, fy,  -5.0, -252.0, 10.0, 14.0, _C_PLUME_B)
	_kr(cx, fy,  -4.0, -264.0,  8.0, 12.0, _C_PLUME_C)
