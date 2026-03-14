extends Node2D

## Local 2-player fighting game.
##
## P1 (blue plume): A/D move · W jump · Q attack · S block
## P2 (red plume):  ←/→ move · ↑ jump · K attack · ↓ block
##
## Escape → return to main menu.

# ── Palette ───────────────────────────────────────────────────────────────────
const _C_SKY := [
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

# ── Physics / combat ──────────────────────────────────────────────────────────
const _WALK_SPEED:    float = 140.0
const _GRAVITY:       float = 700.0
const _JUMP_FORCE:    float = -340.0
const _ATTACK_DUR:    float = 0.45
const _SWORD_REACH:   float = 95.0   # px for hit detection
const _HIT_WIN_START: float = 0.38   # fraction of swing where damage lands
const _HIT_WIN_END:   float = 0.72
const _DMG_FULL:      float = 20.0
const _DMG_BLOCK:     float = 5.0
const _MAX_HP:        float = 100.0
const _END_DELAY:     float = 3.0    # seconds before returning to menu

# ── Fighter state dictionaries ────────────────────────────────────────────────
var _p1 := {
	x = 0.0, jump_y = 0.0, jump_vel = 0.0,
	dir = 1.0, walk_time = 0.0,
	attack_time = 0.0, hit_landed = false,
	blocking = false, moving = false,
	health = _MAX_HP, alive = true,
}
var _p2 := {
	x = 0.0, jump_y = 0.0, jump_vel = 0.0,
	dir = -1.0, walk_time = 0.0,
	attack_time = 0.0, hit_landed = false,
	blocking = false, moving = false,
	health = _MAX_HP, alive = true,
}

# ── Match state ───────────────────────────────────────────────────────────────
var _winner: int = 0   # 0 = in progress, 1 = P1 wins, 2 = P2 wins, -1 = draw
var _end_timer: float = 0.0

# ── Input action names ────────────────────────────────────────────────────────
const _A1 := { left="fp1_l", right="fp1_r", jump="fp1_j", attack="fp1_a", block="fp1_b" }
const _A2 := { left="fp2_l", right="fp2_r", jump="fp2_j", attack="fp2_a", block="fp2_b" }

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_register_inputs()
	var vp := get_viewport_rect().size
	_p1.x = vp.x * 0.28
	_p2.x = vp.x * 0.72
	queue_redraw()

func _register_inputs() -> void:
	var map := {
		"fp1_l": KEY_A,     "fp1_r": KEY_D,
		"fp1_j": KEY_W,     "fp1_a": KEY_Q,     "fp1_b": KEY_S,
		"fp2_l": KEY_LEFT,  "fp2_r": KEY_RIGHT,
		"fp2_j": KEY_UP,    "fp2_a": KEY_K,     "fp2_b": KEY_DOWN,
	}
	for action: String in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.keycode = map[action]
		InputMap.action_add_event(action, ev)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	if _winner != 0:
		_end_timer += delta
		if _end_timer >= _END_DELAY:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		queue_redraw()
		return

	_tick_fighter(_p1, _A1, delta)
	_tick_fighter(_p2, _A2, delta)
	_resolve_collision()
	_check_hit(_p1, _p2)
	_check_hit(_p2, _p1)
	_check_win()
	queue_redraw()

# ── Fighter update ────────────────────────────────────────────────────────────
func _tick_fighter(p: Dictionary, a: Dictionary, delta: float) -> void:
	if not p.alive:
		return

	var vp := get_viewport_rect().size

	# Horizontal
	var moving := false
	if Input.is_action_pressed(a.left):
		p.x    -= _WALK_SPEED * delta
		p.dir   = -1.0
		moving  = true
	elif Input.is_action_pressed(a.right):
		p.x    += _WALK_SPEED * delta
		p.dir   = 1.0
		moving  = true
	p.x = clamp(p.x, vp.x * 0.06, vp.x * 0.94)
	p.moving = moving

	# Jump
	var on_ground: bool = p.jump_y >= 0.0
	if Input.is_action_just_pressed(a.jump) and on_ground:
		p.jump_vel = _JUMP_FORCE
		on_ground  = false
	p.jump_vel += _GRAVITY * delta
	p.jump_y   += p.jump_vel * delta
	if p.jump_y >= 0.0:
		p.jump_y   = 0.0
		p.jump_vel = 0.0
		on_ground  = true

	# Attack
	if Input.is_action_just_pressed(a.attack) and p.attack_time <= 0.0:
		p.attack_time = _ATTACK_DUR
		p.hit_landed  = false
	p.attack_time = maxf(p.attack_time - delta, 0.0)

	# Block
	p.blocking = Input.is_action_pressed(a.block)

	# Walk cycle only when grounded and moving
	if moving and on_ground:
		p.walk_time += delta

# ── Collision — keep knights from overlapping ─────────────────────────────────
func _resolve_collision() -> void:
	const MIN_DIST := 50.0
	var dx := _p2.x - _p1.x
	if absf(dx) < MIN_DIST:
		var push := (MIN_DIST - absf(dx)) * 0.5
		if dx >= 0.0:
			_p1.x -= push
			_p2.x += push
		else:
			_p1.x += push
			_p2.x -= push

# ── Hit detection ─────────────────────────────────────────────────────────────
func _check_hit(attacker: Dictionary, defender: Dictionary) -> void:
	if not attacker.alive or attacker.attack_time <= 0.0 or attacker.hit_landed:
		return
	var phase := 1.0 - (attacker.attack_time / _ATTACK_DUR)
	if phase < _HIT_WIN_START or phase > _HIT_WIN_END:
		return
	# Must be facing the defender
	var dx: float = defender.x - attacker.x
	if sign(dx) != attacker.dir:
		return
	# Must be in reach and similar height
	if absf(dx) > _SWORD_REACH:
		return
	if absf(attacker.jump_y - defender.jump_y) > 80.0:
		return
	attacker.hit_landed = true
	var dmg: float = _DMG_BLOCK if defender.blocking else _DMG_FULL
	defender.health = maxf(defender.health - dmg, 0.0)
	if defender.health <= 0.0:
		defender.alive = false

func _check_win() -> void:
	if _winner != 0:
		return
	var p1_dead := not _p1.alive
	var p2_dead := not _p2.alive
	if p1_dead and p2_dead:
		_winner = -1
	elif p1_dead:
		_winner = 2
	elif p2_dead:
		_winner = 1

# ── Draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_sky(vp)
	_draw_stars(vp)
	_draw_far_mountains(vp)
	_draw_near_mountains(vp)
	_draw_ground(vp)

	_draw_fighter(_p1, Color(0.30, 0.55, 1.00), Color(0.50, 0.75, 1.00), Color(0.70, 0.90, 1.00), vp)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_fighter(_p2, Color(0.78, 0.12, 0.08), Color(0.95, 0.30, 0.10), Color(1.00, 0.55, 0.10), vp)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_hud(vp)
	if _winner != 0:
		_draw_win_screen(vp)

func _draw_fighter(p: Dictionary, pa: Color, pb: Color, pc: Color, vp: Vector2) -> void:
	var phase:  float = sin(p.walk_time * 5.0)
	var stride: float = phase * 8.0
	var swing:  float = -stride * 0.6
	var bob:    float = -absf(phase) * 2.5 if p.alive else 0.0
	var fy:     float = vp.y * 0.65 + bob + p.jump_y
	_draw_knight_at(p.x, fy, stride, swing, p.dir, p.attack_time, p.blocking, pa, pb, pc)

# ── Knight drawing (based on background_scene.gd) ────────────────────────────
func _kr(bx: float, fy: float, ox: float, oy: float, rw: float, rh: float, col: Color) -> void:
	draw_rect(Rect2(bx + ox, fy + oy, rw, rh), col)

func _draw_knight_at(cx: float, fy: float, stride: float, swing: float,
		facing: float, attack_time: float, blocking: bool,
		plume_a: Color, plume_b: Color, plume_c: Color) -> void:

	if facing < 0.0:
		draw_set_transform(Vector2(cx * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))

	var rl := cx + stride
	var ll := cx - stride
	var ra := cx + swing
	var la := cx - swing

	# Feet
	_kr(ll, fy, -18.0, -12.0, 15.0, 12.0, _C_STEEL)
	_kr(rl, fy,   3.0, -12.0, 15.0, 12.0, _C_STEEL)
	_kr(ll, fy, -18.0, -12.0, 15.0,  2.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -12.0, 15.0,  2.0, _C_STEEL_HI)
	_kr(ll, fy, -18.0,  -3.0, 15.0,  3.0, _C_STEEL_SH)
	_kr(rl, fy,   3.0,  -3.0, 15.0,  3.0, _C_STEEL_SH)

	# Greaves
	_kr(ll, fy, -15.0, -46.0, 12.0, 34.0, _C_STEEL)
	_kr(rl, fy,   3.0, -46.0, 12.0, 34.0, _C_STEEL)
	_kr(ll, fy, -15.0, -46.0,  2.0, 34.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -46.0,  2.0, 34.0, _C_STEEL_HI)
	_kr(ll, fy,  -4.0, -46.0,  2.0, 34.0, _C_STEEL_SH)
	_kr(rl, fy,  13.0, -46.0,  2.0, 34.0, _C_STEEL_SH)

	# Kneecaps
	_kr(ll, fy, -16.0, -54.0, 13.0,  9.0, _C_STEEL_HI)
	_kr(rl, fy,   3.0, -54.0, 13.0,  9.0, _C_STEEL_HI)
	_kr(ll, fy, -15.0, -54.0, 11.0,  2.0, _C_GOLD)
	_kr(rl, fy,   4.0, -54.0, 11.0,  2.0, _C_GOLD)

	# Thighs
	_kr(ll, fy, -14.0, -84.0, 12.0, 30.0, _C_STEEL)
	_kr(rl, fy,   2.0, -84.0, 12.0, 30.0, _C_STEEL)
	_kr(ll, fy, -14.0, -84.0,  2.0, 30.0, _C_STEEL_HI)
	_kr(rl, fy,   2.0, -84.0,  2.0, 30.0, _C_STEEL_HI)
	_kr(ll, fy,  -3.0, -84.0,  2.0, 30.0, _C_STEEL_SH)
	_kr(rl, fy,  13.0, -84.0,  2.0, 30.0, _C_STEEL_SH)

	# Hips / Faulds
	_kr(cx, fy, -20.0,  -98.0, 40.0, 16.0, _C_STEEL_SH)
	_kr(cx, fy, -20.0,  -98.0, 40.0,  3.0, _C_STEEL)
	_kr(cx, fy, -20.0,  -99.0, 40.0,  2.0, _C_GOLD)

	# Breastplate
	_kr(cx, fy, -18.0, -156.0, 36.0, 58.0, _C_STEEL)
	_kr(cx, fy, -18.0, -156.0,  3.0, 58.0, _C_STEEL_HI)
	_kr(cx, fy,  15.0, -156.0,  3.0, 58.0, _C_STEEL_SH)
	_kr(cx, fy,  -2.0, -156.0,  4.0, 58.0, _C_STEEL_HI)
	_kr(cx, fy, -18.0, -156.0, 36.0,  3.0, _C_GOLD)
	_kr(cx, fy, -18.0, -100.0, 36.0,  3.0, _C_GOLD)

	# Pauldrons
	_kr(cx, fy, -34.0, -156.0, 18.0, 22.0, _C_STEEL)
	_kr(cx, fy,  16.0, -156.0, 18.0, 22.0, _C_STEEL)
	_kr(cx, fy, -34.0, -156.0, 18.0,  2.0, _C_STEEL_HI)
	_kr(cx, fy,  16.0, -156.0, 18.0,  2.0, _C_STEEL_HI)
	_kr(cx, fy, -34.0, -156.0,  2.0, 22.0, _C_STEEL_HI)
	_kr(cx, fy,  32.0, -156.0,  2.0, 22.0, _C_STEEL_SH)
	_kr(cx, fy, -34.0, -158.0, 18.0,  2.0, _C_GOLD)
	_kr(cx, fy,  16.0, -158.0, 18.0,  2.0, _C_GOLD)

	# Upper arms
	_kr(la, fy, -32.0, -136.0, 10.0, 36.0, _C_STEEL)
	_kr(ra, fy,  22.0, -136.0, 10.0, 36.0, _C_STEEL)
	_kr(la, fy, -32.0, -136.0,  2.0, 36.0, _C_STEEL_HI)
	_kr(ra, fy,  30.0, -136.0,  2.0, 36.0, _C_STEEL_SH)

	# Vambraces
	_kr(la, fy, -30.0, -100.0,  9.0, 28.0, _C_STEEL)
	_kr(ra, fy,  21.0, -100.0,  9.0, 28.0, _C_STEEL)
	_kr(la, fy, -30.0, -100.0,  2.0, 28.0, _C_STEEL_HI)
	_kr(ra, fy,  28.0, -100.0,  2.0, 28.0, _C_STEEL_SH)

	# Gauntlets
	_kr(la, fy, -30.0, -74.0, 12.0, 14.0, _C_STEEL_SH)
	_kr(ra, fy,  18.0, -74.0, 12.0, 14.0, _C_STEEL_SH)
	_kr(la, fy, -30.0, -74.0, 12.0,  2.0, _C_STEEL)
	_kr(ra, fy,  18.0, -74.0, 12.0,  2.0, _C_STEEL)

	# Shield when blocking
	if blocking:
		var sx := la - 38.0
		var sy := fy - 164.0
		draw_rect(Rect2(sx,       sy,       18.0, 56.0), Color(0.42, 0.26, 0.08))
		draw_rect(Rect2(sx + 1.0, sy + 1.0, 16.0, 54.0), Color(0.58, 0.38, 0.14))
		draw_rect(Rect2(sx,       sy,       18.0, 56.0), _C_GOLD, false, 2.0)
		draw_rect(Rect2(sx + 5.0, sy + 25.0, 8.0,  8.0), _C_GOLD)
		draw_rect(Rect2(sx + 6.0, sy + 26.0, 6.0,  6.0), _C_STEEL_HI)

	# Gorget / Helmet
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

	# Plume (player-coloured)
	_kr(cx, fy,  -4.0, -222.0,  8.0, 16.0, _C_DARK)
	_kr(cx, fy,  -6.0, -238.0, 12.0, 16.0, plume_a)
	_kr(cx, fy,  -5.0, -252.0, 10.0, 14.0, plume_b)
	_kr(cx, fy,  -4.0, -264.0,  8.0, 12.0, plume_c)

	# Sword when attacking
	if attack_time > 0.0:
		var t     := 1.0 - (attack_time / _ATTACK_DUR)
		var angle := lerp(-PI * 0.65, PI * 0.12, t)
		var base  := Vector2(ra + 26.0, fy - 74.0)
		var bdir  := Vector2(cos(angle), sin(angle))
		var perp  := Vector2(-bdir.y, bdir.x)
		draw_line(base,                   base - bdir * 14.0,  Color(0.28, 0.16, 0.06), 5.0)
		draw_line(base - perp * 10.0,     base + perp * 10.0,  _C_GOLD, 5.0)
		draw_line(base,                   base + bdir * 55.0,  _C_STEEL, 4.0)
		draw_line(base + bdir * 2.0,      base + bdir * 50.0,  _C_STEEL_HI, 2.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── HUD ───────────────────────────────────────────────────────────────────────
func _draw_hud(vp: Vector2) -> void:
	var font      := ThemeDB.fallback_font
	var font_size := 16
	var bar_w     := vp.x * 0.33
	var bar_h     := 22.0
	var bar_y     := 18.0
	var margin    := 20.0

	# P1 bar (left)
	draw_rect(Rect2(margin, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15))
	var p1_fill := bar_w * (_p1.health / _MAX_HP)
	draw_rect(Rect2(margin, bar_y, p1_fill, bar_h), Color(0.25, 0.65, 0.25))
	draw_rect(Rect2(margin, bar_y, bar_w, bar_h), Color.WHITE, false, 1.5)
	draw_string(font, Vector2(margin + 4.0, bar_y + bar_h - 5.0), "P1  %d HP" % int(_p1.health),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# P2 bar (right, fills right-to-left)
	var p2_x := vp.x - margin - bar_w
	draw_rect(Rect2(p2_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15))
	var p2_fill := bar_w * (_p2.health / _MAX_HP)
	draw_rect(Rect2(p2_x + bar_w - p2_fill, bar_y, p2_fill, bar_h), Color(0.65, 0.20, 0.20))
	draw_rect(Rect2(p2_x, bar_y, bar_w, bar_h), Color.WHITE, false, 1.5)
	draw_string(font, Vector2(p2_x + bar_w - 4.0, bar_y + bar_h - 5.0), "%d HP  P2" % int(_p2.health),
			HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, Color.WHITE)

	# VS label
	draw_string(font, Vector2(vp.x * 0.5, bar_y + bar_h - 5.0), "VS",
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.9, 0.8, 0.2))

func _draw_win_screen(vp: Vector2) -> void:
	# Dim overlay
	draw_rect(Rect2(0.0, 0.0, vp.x, vp.y), Color(0.0, 0.0, 0.0, 0.55))

	var font      := ThemeDB.fallback_font
	var cx        := vp.x * 0.5
	var cy        := vp.y * 0.45

	var msg: String
	match _winner:
		1:  msg = "PLAYER 1 WINS!"
		2:  msg = "PLAYER 2 WINS!"
		_:  msg = "DRAW!"

	draw_string(font, Vector2(cx, cy), msg,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 48, Color(1.0, 0.85, 0.1))

	var remaining := ceili(_END_DELAY - _end_timer)
	draw_string(font, Vector2(cx, cy + 60.0),
			"Returning to menu in %d..." % remaining,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(0.8, 0.8, 0.8))

# ── Background drawing (identical to background_scene.gd) ────────────────────
func _draw_sky(vp: Vector2) -> void:
	var stops: Array[float] = [0.00, 0.14, 0.30, 0.46, 0.58, 0.65]
	for i in range(_C_SKY.size()):
		var y0: float = stops[i] * vp.y
		var y1: float = stops[i + 1] * vp.y
		draw_rect(Rect2(0.0, y0, vp.x, y1 - y0 + 1.0), _C_SKY[i])

func _draw_stars(vp: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDEAD_BEEF
	for _i in 150:
		var x  := int(rng.randf_range(0.0, vp.x))
		var y  := int(rng.randf_range(0.0, vp.y * 0.50))
		var b  := rng.randf_range(0.5, 1.0)
		var sz := 1 if rng.randf() < 0.72 else 2
		draw_rect(Rect2(x, y, sz, sz), Color(b, b, b * 0.92, 0.88))

func _mountain_poly(vp: Vector2, peaks: Array, base_frac: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, base_frac * vp.y))
	for p in peaks:
		pts.append(Vector2(p[0] * vp.x, p[1] * vp.y))
	pts.append(Vector2(vp.x, base_frac * vp.y))
	pts.append(Vector2(vp.x, vp.y))
	pts.append(Vector2(0.0, vp.y))
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

func _draw_ground(vp: Vector2) -> void:
	var w := vp.x
	var h := vp.y
	draw_rect(Rect2(0.0, h * 0.65, w, h * 0.35), _C_GND_TOP)
	draw_rect(Rect2(0.0, h * 0.72, w, h * 0.28), _C_GND_BOT)
	draw_rect(Rect2(0.0, h * 0.650, w, 3.0), _C_GRASS)
	draw_rect(Rect2(0.0, h * 0.653, w, 2.0), Color(0.14, 0.40, 0.12))
	draw_rect(Rect2(w * 0.25, h * 0.650, w * 0.50, h * 0.05), _C_DIRT)
	draw_rect(Rect2(w * 0.25, h * 0.650, w * 0.50, 2.0), Color(0.30, 0.22, 0.12))
