extends Node2D

## 16-bit style 2D side-scrolling background.
## Draws sky bands, stars, layered mountain silhouettes, ground, and
## a player-controlled armored knight.
##
## Controls:
##   Left / Right arrows  — move
##   Space (ui_accept)    — jump
##   Up arrow (ui_up)     — sword attack
##   Down arrow (ui_down) — raise shield / block

# ── Palette ──────────────────────────────────────────────────────────────────
const _C_SKY   := [
	Color(0.03, 0.05, 0.18),
	Color(0.06, 0.10, 0.28),
	Color(0.10, 0.20, 0.42),
	Color(0.18, 0.35, 0.55),
	Color(0.32, 0.52, 0.68),
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

# ── Knight state ──────────────────────────────────────────────────────────────
var _walker_x:    float = 640.0
var _walker_dir:  float = 1.0    # 1 = facing right, -1 = facing left
var _walk_time:   float = 0.0

var _jump_vel:    float = 0.0
var _jump_y:      float = 0.0    # screen-y offset; 0 = on ground, < 0 = airborne

var _attack_time: float = 0.0    # counts down from _ATTACK_DUR; > 0 = mid-swing
var _is_blocking: bool  = false

const _WALK_SPEED:  float = 120.0
const _GRAVITY:     float = 700.0
const _JUMP_FORCE:  float = -340.0
const _ATTACK_DUR:  float = 0.45

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	z_index = -10
	queue_redraw()

func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	if _walker_x <= 0.0:
		_walker_x = vp.x * 0.5

	# ── Horizontal movement ───────────────────────────────────────────────
	var moving := false
	if Input.is_action_pressed("ui_left"):
		_walker_x  -= _WALK_SPEED * delta
		_walker_dir = -1.0
		moving = true
	elif Input.is_action_pressed("ui_right"):
		_walker_x  += _WALK_SPEED * delta
		_walker_dir = 1.0
		moving = true
	_walker_x = clamp(_walker_x, vp.x * 0.05, vp.x * 0.95)

	# ── Jump ─────────────────────────────────────────────────────────────
	var on_ground := _jump_y >= 0.0
	if Input.is_action_just_pressed("ui_accept") and on_ground:
		_jump_vel = _JUMP_FORCE
		on_ground = false
	_jump_vel += _GRAVITY * delta
	_jump_y   += _jump_vel * delta
	if _jump_y >= 0.0:
		_jump_y   = 0.0
		_jump_vel = 0.0
		on_ground = true

	# ── Attack ────────────────────────────────────────────────────────────
	if Input.is_action_just_pressed("ui_up") and _attack_time <= 0.0:
		_attack_time = _ATTACK_DUR
	_attack_time = maxf(_attack_time - delta, 0.0)

	# ── Block ─────────────────────────────────────────────────────────────
	_is_blocking = Input.is_action_pressed("ui_down")

	# ── Walk cycle — only advance when moving on the ground ───────────────
	if moving and on_ground:
		_walk_time += delta

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
	draw_rect(Rect2(0.0, h * 0.650, w, 3.0), _C_GRASS)
	draw_rect(Rect2(0.0, h * 0.653, w, 2.0), Color(0.14, 0.40, 0.12))
	draw_rect(Rect2(w * 0.30, h * 0.650, w * 0.40, h * 0.05), _C_DIRT)
	draw_rect(Rect2(w * 0.30, h * 0.650, w * 0.40, 2.0), Color(0.30, 0.22, 0.12))

# ── Knight ────────────────────────────────────────────────────────────────────
# Helper: filled rect relative to (base_x, fy) anchor.
func _kr(base_x: float, fy: float, ox: float, oy: float, rw: float, rh: float, col: Color) -> void:
	draw_rect(Rect2(base_x + ox, fy + oy, rw, rh), col)

func _draw_knight(vp: Vector2) -> void:
	var phase:  float = sin(_walk_time * 5.0)    # -1..1 walk cycle
	var stride: float = phase * 8.0              # leg spread (flip handles direction)
	var swing:  float = -stride * 0.6            # arm counter-swing
	var bob:    float = -absf(phase) * 2.5       # vertical body bob
	var fy:     float = vp.y * 0.65 + bob + _jump_y
	_draw_knight_at(_walker_x, fy, stride, swing)

func _draw_knight_at(cx: float, fy: float, stride: float, swing: float) -> void:
	# Mirror all draw calls horizontally around cx when facing left.
	if _walker_dir < 0.0:
		draw_set_transform(Vector2(cx * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))

	var rl := cx + stride   # right leg anchor
	var ll := cx - stride   # left leg anchor
	var ra := cx + swing    # right arm anchor
	var la := cx - swing    # left arm anchor

	# ── Feet ──────────────────────────────────────────────────────────────
	_kr(ll, fy, -18.0, -12.0, 15.0, 12.0, _C_STEEL)
	_kr(rl, fy,   3.0, -12.0, 15.0, 12.0, _C_STEEL)
	_kr(ll, fy, -18.0, -12.0, 15.0,  2.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -12.0, 15.0,  2.0, _C_STEEL_HI)
	_kr(ll, fy, -18.0,  -3.0, 15.0,  3.0, _C_STEEL_SH)
	_kr(rl, fy,   3.0,  -3.0, 15.0,  3.0, _C_STEEL_SH)

	# ── Greaves (lower legs) ──────────────────────────────────────────────
	_kr(ll, fy, -15.0, -46.0, 12.0, 34.0, _C_STEEL)
	_kr(rl, fy,   3.0, -46.0, 12.0, 34.0, _C_STEEL)
	_kr(ll, fy, -15.0, -46.0,  2.0, 34.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -46.0,  2.0, 34.0, _C_STEEL_HI)
	_kr(ll, fy,  -4.0, -46.0,  2.0, 34.0, _C_STEEL_SH)
	_kr(rl, fy,  13.0, -46.0,  2.0, 34.0, _C_STEEL_SH)

	# ── Kneecaps ──────────────────────────────────────────────────────────
	_kr(ll, fy, -16.0, -54.0, 13.0,  9.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -54.0, 13.0,  9.0, _C_STEEL_HI)
	_kr(ll, fy, -15.0, -54.0, 11.0,  2.0, _C_GOLD)
	_kr(rl, fy,   4.0, -54.0, 11.0,  2.0, _C_GOLD)

	# ── Thighs ────────────────────────────────────────────────────────────
	_kr(ll, fy, -14.0, -84.0, 12.0, 30.0, _C_STEEL)
	_kr(rl, fy,   2.0, -84.0, 12.0, 30.0, _C_STEEL)
	_kr(ll, fy, -14.0, -84.0,  2.0, 30.0, _C_STEEL_HI)
	_kr(rl, fy,   2.0, -84.0,  2.0, 30.0, _C_STEEL_HI)
	_kr(ll, fy,  -3.0, -84.0,  2.0, 30.0, _C_STEEL_SH)
	_kr(rl, fy,  13.0, -84.0,  2.0, 30.0, _C_STEEL_SH)

	# ── Hips / Faulds ─────────────────────────────────────────────────────
	_kr(cx, fy, -20.0,  -98.0, 40.0, 16.0, _C_STEEL_SH)
	_kr(cx, fy, -20.0,  -98.0, 40.0,  3.0, _C_STEEL)
	_kr(cx, fy, -20.0,  -99.0, 40.0,  2.0, _C_GOLD)

	# ── Breastplate / Torso ───────────────────────────────────────────────
	_kr(cx, fy, -18.0, -156.0, 36.0, 58.0, _C_STEEL)
	_kr(cx, fy, -18.0, -156.0,  3.0, 58.0, _C_STEEL_HI)
	_kr(cx, fy,  15.0, -156.0,  3.0, 58.0, _C_STEEL_SH)
	_kr(cx, fy,  -2.0, -156.0,  4.0, 58.0, _C_STEEL_HI)
	_kr(cx, fy, -18.0, -156.0, 36.0,  3.0, _C_GOLD)
	_kr(cx, fy, -18.0, -100.0, 36.0,  3.0, _C_GOLD)

	# ── Pauldrons ─────────────────────────────────────────────────────────
	_kr(cx, fy, -34.0, -156.0, 18.0, 22.0, _C_STEEL)
	_kr(cx, fy,  16.0, -156.0, 18.0, 22.0, _C_STEEL)
	_kr(cx, fy, -34.0, -156.0, 18.0,  2.0, _C_STEEL_HI)
	_kr(cx, fy,  16.0, -156.0, 18.0,  2.0, _C_STEEL_HI)
	_kr(cx, fy, -34.0, -156.0,  2.0, 22.0, _C_STEEL_HI)
	_kr(cx, fy,  32.0, -156.0,  2.0, 22.0, _C_STEEL_SH)
	_kr(cx, fy, -34.0, -158.0, 18.0,  2.0, _C_GOLD)
	_kr(cx, fy,  16.0, -158.0, 18.0,  2.0, _C_GOLD)

	# ── Upper arms ────────────────────────────────────────────────────────
	_kr(la, fy, -32.0, -136.0, 10.0, 36.0, _C_STEEL)
	_kr(ra, fy,  22.0, -136.0, 10.0, 36.0, _C_STEEL)
	_kr(la, fy, -32.0, -136.0,  2.0, 36.0, _C_STEEL_HI)
	_kr(ra, fy,  30.0, -136.0,  2.0, 36.0, _C_STEEL_SH)

	# ── Vambraces (lower arms) ────────────────────────────────────────────
	_kr(la, fy, -30.0, -100.0,  9.0, 28.0, _C_STEEL)
	_kr(ra, fy,  21.0, -100.0,  9.0, 28.0, _C_STEEL)
	_kr(la, fy, -30.0, -100.0,  2.0, 28.0, _C_STEEL_HI)
	_kr(ra, fy,  28.0, -100.0,  2.0, 28.0, _C_STEEL_SH)

	# ── Gauntlets ─────────────────────────────────────────────────────────
	_kr(la, fy, -30.0, -74.0, 12.0, 14.0, _C_STEEL_SH)
	_kr(ra, fy,  18.0, -74.0, 12.0, 14.0, _C_STEEL_SH)
	_kr(la, fy, -30.0, -74.0, 12.0,  2.0, _C_STEEL)
	_kr(ra, fy,  18.0, -74.0, 12.0,  2.0, _C_STEEL)

	# ── Shield (blocking) — raised on left arm ────────────────────────────
	if _is_blocking:
		var sx := la - 38.0
		var sy := fy - 164.0
		draw_rect(Rect2(sx,        sy,        18.0, 56.0), Color(0.42, 0.26, 0.08))
		draw_rect(Rect2(sx + 1.0,  sy + 1.0,  16.0, 54.0), Color(0.58, 0.38, 0.14))
		draw_rect(Rect2(sx,        sy,        18.0, 56.0), _C_GOLD, false, 2.0)
		draw_rect(Rect2(sx + 5.0,  sy + 25.0,  8.0,  8.0), _C_GOLD)   # boss
		draw_rect(Rect2(sx + 6.0,  sy + 26.0,  6.0,  6.0), _C_STEEL_HI)

	# ── Gorget / Helmet ───────────────────────────────────────────────────
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

	# ── Plume ─────────────────────────────────────────────────────────────
	_kr(cx, fy,  -4.0, -222.0,  8.0, 16.0, _C_DARK)
	_kr(cx, fy,  -6.0, -238.0, 12.0, 16.0, _C_PLUME_A)
	_kr(cx, fy,  -5.0, -252.0, 10.0, 14.0, _C_PLUME_B)
	_kr(cx, fy,  -4.0, -264.0,  8.0, 12.0, _C_PLUME_C)

	# ── Sword (attacking) — swings from raised to forward on right arm ────
	if _attack_time > 0.0:
		var t     := 1.0 - (_attack_time / _ATTACK_DUR)          # 0→1 as swing progresses
		var angle := lerp(-PI * 0.65, PI * 0.12, t)              # raised → forward-down
		var base  := Vector2(ra + 26.0, fy - 74.0)               # grip point
		var bdir  := Vector2(cos(angle), sin(angle))
		var perp  := Vector2(-bdir.y, bdir.x)
		draw_line(base,                     base - bdir * 14.0,  Color(0.28, 0.16, 0.06), 5.0)  # handle
		draw_line(base - perp * 10.0,       base + perp * 10.0,  _C_GOLD, 5.0)                  # crossguard
		draw_line(base,                     base + bdir * 55.0,  _C_STEEL, 4.0)                 # blade
		draw_line(base + bdir * 2.0,        base + bdir * 50.0,  _C_STEEL_HI, 2.0)              # blade highlight

	# ── Reset transform ───────────────────────────────────────────────────
	if _walker_dir < 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
