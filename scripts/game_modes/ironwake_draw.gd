class_name IronwakeDraw
extends RefCounted

## Drawing helper extracted from the arena — all CanvasItem draw calls go through `a`.

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const _BatteryController := preload("res://scripts/shared/battery_controller.gd")
const _MotionStateResolver := preload("res://scripts/shared/motion_state_resolver.gd")

var a = null  # Arena node reference (CanvasItem). Untyped: draw helper accesses arena-specific consts.


func init(arena_node) -> void:
	a = arena_node


# ── Coordinate utilities (internal) ──────────────────────────────────

func _w2s(wx: float, wy: float) -> Vector2:
	return a._origin + Vector2(wx, wy) * a._TD_SCALE * a._zoom


func _dir_screen(dx: float, dy: float) -> Vector2:
	var v := Vector2(dx, dy)
	return v.normalized() if v.length_squared() > 0.001 else Vector2.DOWN


## Screen position of the drawn hull (deck lift + bob) — matches visible ship, not raw wx/wy waterline.
func _hull_visual_screen_pos(p: Dictionary) -> Vector2:
	return _w2s(float(p.wx), float(p.wy)) + _deck_lift_offset_for_screen(p)


func _hud_fade_alpha(fade_timer: float) -> float:
	if fade_timer >= a._HUD_FADE_DURATION:
		return 1.0
	if fade_timer <= 0.0:
		return 0.0
	return clampf(fade_timer / a._HUD_FADE_DURATION, 0.0, 1.0)


func _deck_lift_offset_for_screen(p: Dictionary) -> Vector2:
	var bob: float = sin(float(p.get("walk_time", 0.0)) * 3.0) * 1.4 if bool(p.get("moving", false)) else 0.0
	var v_lift_px: float = NC.SHIP_DECK_HEIGHT_UNITS * a._CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * a._zoom
	return Vector2(0.0, -v_lift_px + bob * a._zoom)


# ── Helper functions used by draw functions ──────────────────────────

## Half-angle (deg) of the yaw spread cone — physical dispersion only.
func _spread_cone_half_deg(p: Dictionary, aim_dist: float) -> float:
	var base_deg: float = NC.spread_deg_for_range(aim_dist)
	if bool(p.get("motion_is_turning", false)):
		base_deg *= NC.TURNING_SPREAD_MULT
	if float(p.get("_naval_spd", 0.0)) >= NC.HIGH_SPEED_THRESHOLD:
		base_deg *= NC.HIGH_SPEED_SPREAD_MULT
	return base_deg


## Prefer stored aim (auto-aim / lead) when it bears on the selected broadside; else pure port/starboard normal.
func _effective_broadside_aim_for_side(p: Dictionary, hull_n: Vector2, is_port: bool) -> Vector2:
	var perp: Vector2 = hull_n.rotated(PI * 0.5) if is_port else hull_n.rotated(-PI * 0.5)
	var ad: Variant = p.get("aim_dir", null)
	if ad is Vector2:
		var av: Vector2 = ad as Vector2
		if av.length_squared() > 0.0001:
			av = av.normalized()
			if av.dot(perp) > 0.12:
				return av
	return perp


func _cannon_muzzle_world(p: Dictionary, battery: RefCounted, cannon_index: int) -> Vector2:
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_n.length_squared() < 0.001:
		hull_n = Vector2.RIGHT
	hull_n = hull_n.normalized()
	var perp: Vector2 = battery._broadside_perp(hull_n)
	var n_g: int = maxi(1, battery.cannon_count)
	var idx: int = clampi(cannon_index, 0, n_g - 1)
	# Fixed gunport spacing: ~2.3 m between guns (historical 24-pdr ship of the line).
	var half_span: float = float(n_g - 1) * 0.5 * 2.3
	var along_t: float = 0.0
	if n_g > 1:
		along_t = (float(idx) - float(n_g - 1) * 0.5) / float(n_g - 1)
	var along: Vector2 = hull_n * (along_t * half_span * 2.0)
	# Muzzle at hull edge — half-width of the ship (gunport in the hull side).
	var out_m: float = NC.SHIP_WIDTH_UNITS * 0.5
	return Vector2(float(p.wx), float(p.wy)) + along + perp * out_m


# ── FX draw functions ────────────────────────────────────────────────

func draw_splash_fx() -> void:
	if a._proj.splash_fx.is_empty():
		return
	for s in a._proj.splash_fx:
		var wx: float = float(s.get("wx", 0.0))
		var wy: float = float(s.get("wy", 0.0))
		var t: float = float(s.get("t", 0.0))
		var u: float = clampf(t / a._SPLASH_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy)
		var z: float = a._zoom
		# Expanding ripples + a few droplet dots
		for ring in range(3):
			var rr: float = (4.0 + float(ring) * 7.0) * z * (0.15 + u * 0.92)
			var al: float = 0.28 * fade * (1.0 - float(ring) * 0.22)
			var c: Color = Color(0.65, 0.82, 0.96, al)
			a.draw_arc(sp, rr, 0.0, TAU, maxi(16, int(18.0 + rr * 0.4)), c, 1.6 * z, true)
		var droplet_a: float = 0.45 * fade
		for k in range(5):
			var ang: float = float(k) * TAU / 5.0 + t * 8.0
			var d: float = (10.0 + u * 14.0) * z
			var dp: Vector2 = sp + Vector2(cos(ang), sin(ang)) * d * 0.35
			a.draw_circle(dp, (1.2 - u * 0.4) * z, Color(0.85, 0.93, 1.0, droplet_a * 0.6))


func draw_hull_strike_fx() -> void:
	if a._proj.hull_strike_fx.is_empty():
		return
	var hs: float = a._CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * a._zoom
	for s in a._proj.hull_strike_fx:
		var wx: float = float(s.get("wx", 0.0))
		var wy: float = float(s.get("wy", 0.0))
		var hit_h: float = float(s.get("h", 0.0))
		var t: float = float(s.get("t", 0.0))
		var u: float = clampf(t / a._HULL_STRIKE_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy)
		sp += Vector2(0.0, -hit_h * hs)
		var z: float = a._zoom
		# Core flash + expanding ember ring (reads as "ball struck hull").
		var flash_a: float = 0.85 * fade * (1.0 - u * 0.7)
		a.draw_circle(sp, (5.5 + u * 3.0) * z, Color(1.0, 0.94, 0.72, flash_a * 0.5))
		a.draw_circle(sp, (3.2 - u * 1.2) * z, Color(1.0, 0.55, 0.2, flash_a * 0.75))
		for ring in range(2):
			var rr: float = (6.0 + float(ring) * 10.0) * z * (0.2 + u * 1.05)
			var al: float = 0.4 * fade * (1.0 - float(ring) * 0.35)
			a.draw_arc(sp, rr, 0.0, TAU, maxi(14, int(16.0 + rr * 0.35)), Color(0.35, 0.22, 0.12, al), 2.0 * z, true)
		var spark_n: int = 10
		for k in range(spark_n):
			var base_ang: float = float(k) * TAU / float(spark_n) + t * 14.0
			var burst: float = (18.0 + u * 28.0) * z * fade
			var p1: Vector2 = sp + Vector2(cos(base_ang), sin(base_ang)) * burst * 0.15
			var p2: Vector2 = sp + Vector2(cos(base_ang), sin(base_ang)) * burst * (0.45 + u * 0.35)
			var sc: Color = Color(1.0, 0.72 + u * 0.2, 0.35, 0.55 * fade)
			a.draw_line(p1, p2, sc, (1.8 - u * 0.6) * z)


func draw_muzzle_fx() -> void:
	var z: float = a._zoom
	for f in a._proj.muzzle_flash_fx:
		var wx: float = float(f.get("wx", 0.0))
		var wy: float = float(f.get("wy", 0.0))
		var t: float = float(f.get("t", 0.0))
		var u: float = clampf(t / a._MUZZLE_FLASH_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy)
		var dir: Vector2 = _dir_screen(float(f.get("dirx", 1.0)), float(f.get("diry", 0.0)))
		a.draw_circle(sp, (9.0 + 8.0 * u) * z, Color(1.0, 0.92, 0.65, 0.55 * fade))
		a.draw_circle(sp, (5.0 + 4.0 * u) * z, Color(1.0, 0.64, 0.22, 0.75 * fade))
		a.draw_line(sp, sp + dir * (18.0 + 8.0 * u) * z, Color(1.0, 0.86, 0.48, 0.65 * fade), 2.0 * z)
	for s in a._proj.muzzle_smoke_fx:
		var wx: float = float(s.get("wx", 0.0))
		var wy: float = float(s.get("wy", 0.0))
		var t: float = float(s.get("t", 0.0))
		var u: float = clampf(t / a._MUZZLE_SMOKE_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy) + Vector2(0.0, -8.0 * u * z)
		var rr: float = (6.0 + 22.0 * u) * z
		a.draw_circle(sp, rr, Color(0.22, 0.22, 0.24, 0.28 * fade))


# ── Win screen ───────────────────────────────────────────────────────

func draw_win_screen(vp: Vector2) -> void:
	a.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.58))
	var font: Font = ThemeDB.fallback_font
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.28

	var msg: String
	if a._winner == -1:
		msg = "DRAW!"
	else:
		msg = "%s WINS!" % a._players[a._winner].label
	a.draw_string(font, Vector2(cx, cy), msg,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 52, Color(0.95, 0.75, 0.35, 1.0))

	# Scoreboard is drawn separately by the _draw() caller when _match_over is true.

	if a._post_match_ready:
		a.draw_string(font, Vector2(cx, vp.y * 0.88),
			"Press any key to continue...",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, a._HUD_TEXT)
	else:
		var remaining: int = ceili(a.END_DELAY - a._end_timer)
		a.draw_string(font, Vector2(cx, vp.y * 0.88),
			"Returning to menu in %d..." % remaining,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, a._HUD_TEXT_MUTED)


# ── Player ship drawing ─────────────────────────────────────────────

func draw_player(p: Dictionary) -> void:
	var sp: Vector2 = _w2s(p.wx, p.wy)
	var draw_pos: Vector2 = _hull_visual_screen_pos(p)
	if not bool(p.get("alive", true)):
		# ── Sinking animation ──
		var respawn_t: float = float(p.get("respawn_timer", 0.0))
		var time_dead: float = a.RESPAWN_DELAY_SEC - respawn_t
		var sink_frac: float = clampf(time_dead / a.SINK_ANIM_DURATION, 0.0, 1.0)

		if sink_frac < 1.0:
			# Ship is still sinking — draw it tilting and descending.
			var sink_hull_v: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
			if sink_hull_v.length_squared() < 0.0001:
				sink_hull_v = Vector2.RIGHT
			sink_hull_v = sink_hull_v.normalized()
			var sink_fwd: Vector2 = _dir_screen(sink_hull_v.x, sink_hull_v.y)
			var sink_right: Vector2 = Vector2(-sink_fwd.y, sink_fwd.x)
			var sink_px_len: float = maxf(14.0 * a._zoom, (_w2s(p.wx + sink_hull_v.x * NC.SHIP_LENGTH_UNITS, p.wy + sink_hull_v.y * NC.SHIP_LENGTH_UNITS) - sp).length())
			var sink_px_wid: float = maxf(8.0 * a._zoom, (_w2s(p.wx + sink_right.x * NC.SHIP_WIDTH_UNITS, p.wy + sink_right.y * NC.SHIP_WIDTH_UNITS) - sp).length())

			# Sink offset: ship drops downward on screen as it sinks.
			var sink_drop: float = sink_frac * 18.0 * a._zoom
			# List (tilt): ship rolls to one side as it goes down.
			var list_angle: float = sink_frac * 0.35  # radians of tilt
			var tilt_offset: Vector2 = sink_right * sin(list_angle) * sink_px_wid * 0.4

			var sink_pos: Vector2 = draw_pos + Vector2(0.0, sink_drop) + tilt_offset
			# Hull shrinks as it submerges (foreshortening into water).
			var sk_shrink: float = 1.0 - sink_frac * 0.4
			var sk_len: float = sink_px_len * sk_shrink
			var sk_wid: float = sink_px_wid * sk_shrink

			# Fade out during sink.
			var sink_alpha: float = 1.0 - sink_frac * 0.7

			# Simplified hull shape.
			var sk_bow: Vector2 = sink_pos + sink_fwd * sk_len * 0.44
			var sk_bow_l: Vector2 = sink_pos + sink_fwd * sk_len * 0.32 - sink_right * sk_wid * 0.35
			var sk_bow_r: Vector2 = sink_pos + sink_fwd * sk_len * 0.32 + sink_right * sk_wid * 0.35
			var sk_mid_l: Vector2 = sink_pos - sink_right * sk_wid * 0.72
			var sk_mid_r: Vector2 = sink_pos + sink_right * sk_wid * 0.72
			var sk_str_l: Vector2 = sink_pos - sink_fwd * sk_len * 0.38 - sink_right * sk_wid * 0.48
			var sk_str_r: Vector2 = sink_pos - sink_fwd * sk_len * 0.38 + sink_right * sk_wid * 0.48
			var sk_trans: Vector2 = sink_pos - sink_fwd * sk_len * 0.35

			var sink_col: Color = Color(0.30, 0.18, 0.08, sink_alpha * 0.85)
			var sk_outline: Color = Color(0.45, 0.30, 0.15, sink_alpha * 0.7)
			var sk_poly := PackedVector2Array([sk_bow, sk_bow_r, sk_mid_r, sk_str_r, sk_trans, sk_str_l, sk_mid_l, sk_bow_l])
			if sk_len > 1.0 and sk_wid > 1.0:
				a.draw_colored_polygon(sk_poly, sink_col)
			a.draw_polyline(PackedVector2Array([sk_bow, sk_bow_r, sk_mid_r, sk_str_r, sk_trans, sk_str_l, sk_mid_l, sk_bow_l, sk_bow]),
				sk_outline, 1.6 * a._zoom, true)

			# Bubbles rising from the sinking ship.
			var bubble_count: int = int(sink_frac * 6.0) + 1
			var game_t: float = float(Time.get_ticks_msec()) / 1000.0
			for bi in range(bubble_count):
				var bt: float = fmod(game_t * 1.5 + float(bi) * 1.7, 3.0) / 3.0
				var bx: float = sin(float(bi) * 2.3 + game_t) * sk_wid * 0.5
				var by: float = -bt * 20.0 * a._zoom
				var bubble_pos: Vector2 = sink_pos + Vector2(bx, sink_drop * 0.5 + by)
				var bubble_alpha: float = (1.0 - bt) * sink_alpha * 0.5
				a.draw_circle(bubble_pos, (1.5 + bt * 2.0) * a._zoom, Color(0.7, 0.85, 0.95, bubble_alpha))
		else:
			# Fully sunk — wreck X marker sized to match the ship hull.
			var wreck_alpha: float = clampf(respawn_t / (a.RESPAWN_DELAY_SEC - a.SINK_ANIM_DURATION), 0.0, 0.6)
			if wreck_alpha > 0.02:
				var wx_half_l: float = maxf(14.0 * a._zoom, NC.SHIP_LENGTH_UNITS * a._TD_SCALE * a._zoom * 0.4)
				var wx_half_w: float = maxf(8.0 * a._zoom, NC.SHIP_WIDTH_UNITS * a._TD_SCALE * a._zoom * 0.4)
				var wreck_col: Color = Color(0.55, 0.15, 0.1, wreck_alpha)
				a.draw_line(draw_pos + Vector2(-wx_half_l, -wx_half_w), draw_pos + Vector2(wx_half_l, wx_half_w),
					wreck_col, 3.0 * a._zoom)
				a.draw_line(draw_pos + Vector2(wx_half_l, -wx_half_w), draw_pos + Vector2(-wx_half_l, wx_half_w),
					wreck_col, 3.0 * a._zoom)
		return
	var hull := Vector2(float(p.dir.x), float(p.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var fwd: Vector2 = _dir_screen(hull.x, hull.y)
	var right: Vector2 = Vector2(-fwd.y, fwd.x)
	var px_len: float = maxf(14.0 * a._zoom, (_w2s(p.wx + hull.x * NC.SHIP_LENGTH_UNITS, p.wy + hull.y * NC.SHIP_LENGTH_UNITS) - sp).length())
	var px_wid: float = maxf(8.0 * a._zoom, (_w2s(p.wx + right.x * NC.SHIP_WIDTH_UNITS, p.wy + right.y * NC.SHIP_WIDTH_UNITS) - sp).length())
	var h_len: float = px_len
	var h_wid: float = px_wid
	# FTL-style schematic hull (same proportions as _draw_ftl_ship_hud), oriented with bow = fwd.
	var bow_tip: Vector2 = draw_pos + fwd * h_len * 0.44
	var bow_l: Vector2 = draw_pos + fwd * h_len * 0.32 - right * h_wid * 0.35
	var bow_r: Vector2 = draw_pos + fwd * h_len * 0.32 + right * h_wid * 0.35
	var fwd_l: Vector2 = draw_pos + fwd * h_len * 0.15 - right * h_wid * 0.62
	var fwd_r: Vector2 = draw_pos + fwd * h_len * 0.15 + right * h_wid * 0.62
	var mid_l: Vector2 = draw_pos - fwd * h_len * 0.02 - right * h_wid * 0.72
	var mid_r: Vector2 = draw_pos - fwd * h_len * 0.02 + right * h_wid * 0.72
	var aft_l: Vector2 = draw_pos - fwd * h_len * 0.22 - right * h_wid * 0.65
	var aft_r: Vector2 = draw_pos - fwd * h_len * 0.22 + right * h_wid * 0.65
	var stern_l: Vector2 = draw_pos - fwd * h_len * 0.38 - right * h_wid * 0.48
	var stern_r: Vector2 = draw_pos - fwd * h_len * 0.38 + right * h_wid * 0.48
	var transom: Vector2 = draw_pos - fwd * h_len * 0.35
	var mod_color: Color = p.palette[0]
	var hp_frac: float = clampf(float(p.get("health", a.HULL_HITS_MAX)) / a.HULL_HITS_MAX, 0.0, 1.0)
	# Tint hull toward red/brown as damage accumulates.
	var dmg_t: float = 1.0 - hp_frac
	var base_r: float = lerpf(mod_color.r * 0.55, 0.35, dmg_t * 0.6)
	var base_g: float = lerpf(mod_color.g * 0.55, 0.12, dmg_t * 0.7)
	var base_b: float = lerpf(mod_color.b * 0.58, 0.08, dmg_t * 0.7)
	var hull_dark: Color = Color(base_r, base_g, base_b, 0.96)
	var hull_mid: Color = Color(lerpf(mod_color.r * 0.78, 0.45, dmg_t * 0.5),
		lerpf(mod_color.g * 0.78, 0.25, dmg_t * 0.6),
		lerpf(mod_color.b * 0.82, 0.18, dmg_t * 0.6), 0.94)
	var hull_poly := PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l])
	if h_len > 1.0 and h_wid > 1.0:
		a.draw_colored_polygon(hull_poly, hull_dark)
	a.draw_polyline(PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l, bow_tip]),
		hull_mid, 2.0 * a._zoom, true)
	# Damage marks — dark scorch spots along hull, more as health drops.
	var marks_count: int = int((1.0 - hp_frac) * 8.0)
	if marks_count > 0 and h_len > 3.0:
		var mark_col: Color = Color(0.08, 0.05, 0.03, 0.5 + dmg_t * 0.3)
		for mi in range(marks_count):
			# Deterministic positions based on index so they don't flicker.
			var mt: float = (float(mi) + 0.5) / 8.0
			var along_off: float = lerpf(-0.3, 0.3, mt)
			var side_f: float = -0.3 if mi % 2 == 0 else 0.3
			var mark_pos: Vector2 = draw_pos + fwd * h_len * along_off + right * h_wid * side_f
			a.draw_circle(mark_pos, (1.5 + dmg_t * 1.5) * a._zoom, mark_col)
	a.draw_line(draw_pos + fwd * h_len * 0.40, draw_pos + fwd * h_len * 0.52, Color(0.55, 0.45, 0.30, 0.75), 1.6 * a._zoom, true)
	a.draw_line(draw_pos + fwd * h_len * 0.06, draw_pos + fwd * h_len * 0.28, Color(0.48, 0.40, 0.28, 0.55), 1.2 * a._zoom, true)
	var ctr_w: Vector2 = Vector2(float(p.wx), float(p.wy))
	var sc_w: float = a._TD_SCALE * a._zoom
	var barrel_col: Color = Color(0.22, 0.20, 0.18, 0.95)
	var mzl_col: Color = Color(0.42, 0.38, 0.32, 0.9)
	var zc: float = a._zoom
	for bat_var in [p.get("battery_port"), p.get("battery_stbd")]:
		if bat_var == null:
			continue
		var bat_c = bat_var as _BatteryController
		var perp_w: Vector2 = bat_c._broadside_perp(hull)
		var out_scr: Vector2 = _dir_screen(perp_w.x, perp_w.y)
		for gi in range(bat_c.cannon_count):
			var mw: Vector2 = _cannon_muzzle_world(p, bat_c, gi)
			var gun_sp: Vector2 = draw_pos + (mw - ctr_w) * sc_w
			# Barrel: breech inside hull, muzzle poking out at gunport.
			var breech: Vector2 = gun_sp - out_scr * (4.0 * zc)
			a.draw_line(breech, gun_sp + out_scr * (3.0 * zc), barrel_col, 2.4 * zc, true)
			a.draw_circle(gun_sp + out_scr * (3.5 * zc), 1.3 * zc, mzl_col)
	var font := ThemeDB.fallback_font
	a.draw_string(font, draw_pos + Vector2(0.0, -42.0 * a._zoom), str(p.get("label", "Ship")), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 1.0, 1.0, 0.88))

	# Direction indicator — bow line for all ships, arcs only for local player.
	var c_bow_bot: Color = Color(mod_color.r, mod_color.g, mod_color.b, 0.5)
	a.draw_line(draw_pos, draw_pos + fwd * (h_len * 0.7), c_bow_bot, 1.8 * a._zoom)

	if a._players.is_empty():
		return
	if p != a._players[a._my_index]:
		return
	var L: float = 70.0 * a._zoom
	var c_arc: Color = Color(0.42, 0.86, 0.52, 0.36)
	var c_bow: Color = Color(0.92, 0.78, 0.42, 0.45)
	for sgn in [-1.0, 1.0]:
		var perp: Vector2 = hull.rotated(sgn * PI * 0.5)
		var half: float = deg_to_rad(NC.BROADSIDE_HALF_ARC_DEG)
		var a0: Vector2 = perp.rotated(-half)
		var a1: Vector2 = perp.rotated(half)
		a.draw_line(draw_pos, draw_pos + _dir_screen(a0.x, a0.y) * L, c_arc, 2.0 * a._zoom)
		a.draw_line(draw_pos, draw_pos + _dir_screen(a1.x, a1.y) * L, c_arc, 2.0 * a._zoom)
	a.draw_line(draw_pos, draw_pos + _dir_screen(hull.x, hull.y) * (32.0 * a._zoom), c_bow, 2.2 * a._zoom)


# ── HUD ──────────────────────────────────────────────────────────────

func draw_hud(vp: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var bar_h: float = 20.0
	var pad: float = 14.0
	const MAX_COLS: int = 4
	var bar_w: float = minf((vp.x - pad * (MAX_COLS + 1)) / MAX_COLS, 200.0)
	var spacing: float = bar_w + pad
	var row_stride: float = bar_h + 8.0
	var status_y: float = pad + row_stride * 2.0 + 10.0
	for i in range(a._status_messages.size()):
		var entry: Dictionary = a._status_messages[i]
		a.draw_string(
			font,
			Vector2(pad, status_y + float(i) * 18.0),
			str(entry.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			a._HUD_TEXT
		)
	for i in range(a._players.size()):
		var p: Dictionary = a._players[i]
		var col_idx: int = i % MAX_COLS
		@warning_ignore("integer_division")
		var row_idx: int = i / MAX_COLS
		var bx: float = pad + float(col_idx) * spacing
		var by: float = pad + float(row_idx) * row_stride
		var fill: float = bar_w * clampf(float(p.health) / a.HULL_HITS_MAX, 0.0, 1.0)
		var col: Color = p.palette[0]
		a.draw_rect(Rect2(bx, by, bar_w, bar_h), a._HUD_BG)
		if p.alive and fill > 0.0:
			a.draw_rect(Rect2(bx, by, fill, bar_h), col)
		a.draw_rect(Rect2(bx, by, bar_w, bar_h), a._HUD_BORDER, false, 1.5)
		var bar_txt: String
		if p.alive:
			bar_txt = "%s  %d/%d" % [p.label, int(maxf(p.health, 0.0)), int(a.HULL_HITS_MAX)]
		else:
			var rt: float = float(p.get("respawn_timer", 0.0))
			bar_txt = "%s  respawn %.1fs" % [p.label, rt] if rt > 0.001 else "%s  —" % p.label
		a.draw_string(font, Vector2(bx + 5.0, by + bar_h - 5.0), bar_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, a._HUD_TEXT)


# ── Scoreboard ───────────────────────────────────────────────────────

func draw_scoreboard(vp: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	# Panel dimensions.
	var col_widths: Array[float] = [140.0, 60.0, 60.0, 55.0, 60.0, 55.0, 75.0, 75.0]
	var total_w: float = 0.0
	for w in col_widths:
		total_w += w
	var row_h: float = 26.0
	var header_h: float = 30.0
	var pad: float = 16.0
	var n_rows: int = a._players.size()
	var total_h: float = header_h + float(n_rows) * row_h + pad * 2.0
	var panel_x: float = (vp.x - total_w - pad * 2.0) * 0.5
	var panel_y: float = (vp.y - total_h) * 0.5

	# Background panel.
	a.draw_rect(Rect2(panel_x, panel_y, total_w + pad * 2.0, total_h), Color(0.05, 0.05, 0.08, 0.88))
	a.draw_rect(Rect2(panel_x, panel_y, total_w + pad * 2.0, total_h), a._HUD_BORDER, false, 2.0)

	# Column headers.
	var headers: Array[String] = ["Player", "Kills", "Deaths", "K/D", "Shots", "Hits", "Accuracy", "Damage"]
	var hx: float = panel_x + pad
	var hy: float = panel_y + pad + 14.0
	for ci in range(headers.size()):
		a.draw_string(font, Vector2(hx, hy), headers[ci], HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[ci]), 13, a._HUD_TEXT_MUTED)
		hx += col_widths[ci]

	# Header separator line.
	a.draw_line(
		Vector2(panel_x + pad, panel_y + pad + header_h - 6.0),
		Vector2(panel_x + pad + total_w, panel_y + pad + header_h - 6.0),
		a._HUD_BORDER, 1.0)

	# Sort players by kills descending.
	var sorted_players: Array = a._players.duplicate()
	sorted_players.sort_custom(func(pa: Dictionary, pb: Dictionary) -> bool:
		var a_pid: int = int(pa.get("peer_id", 0))
		var b_pid: int = int(pb.get("peer_id", 0))
		var a_kills: int = int(a._scoreboard.get(a_pid, {}).get("kills", 0))
		var b_kills: int = int(a._scoreboard.get(b_pid, {}).get("kills", 0))
		return a_kills > b_kills)

	# Rows.
	var ry: float = panel_y + pad + header_h + 12.0
	for p in sorted_players:
		var pid: int = int(p.get("peer_id", 0))
		var stats: Dictionary = a._scoreboard.get(pid, {})
		var kills: int = int(stats.get("kills", 0))
		var deaths: int = int(stats.get("deaths", 0))
		var shots_fired: int = int(stats.get("shots_fired", 0))
		var shots_hit: int = int(stats.get("shots_hit", 0))
		var dmg_dealt: float = float(stats.get("damage_dealt", 0.0))
		var kd: float = float(kills) / float(maxi(deaths, 1))
		var accuracy: float = (float(shots_hit) / float(shots_fired) * 100.0) if shots_fired > 0 else 0.0
		var row_col: Color = Color(p.palette[0], 0.9)

		var rx: float = panel_x + pad
		a.draw_string(font, Vector2(rx, ry), str(p.get("label", "?")), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[0]), 13, row_col)
		rx += col_widths[0]
		a.draw_string(font, Vector2(rx, ry), str(kills), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[1]), 13, row_col)
		rx += col_widths[1]
		a.draw_string(font, Vector2(rx, ry), str(deaths), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[2]), 13, row_col)
		rx += col_widths[2]
		a.draw_string(font, Vector2(rx, ry), "%.1f" % kd, HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[3]), 13, row_col)
		rx += col_widths[3]
		a.draw_string(font, Vector2(rx, ry), str(shots_fired), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[4]), 13, row_col)
		rx += col_widths[4]
		a.draw_string(font, Vector2(rx, ry), str(shots_hit), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[5]), 13, row_col)
		rx += col_widths[5]
		a.draw_string(font, Vector2(rx, ry), "%.0f%%" % accuracy, HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[6]), 13, row_col)
		rx += col_widths[6]
		a.draw_string(font, Vector2(rx, ry), "%.1f" % dmg_dealt, HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[7]), 13, row_col)
		ry += row_h


# ── Range helpers ────────────────────────────────────────────────────

func ballistic_splash_range_for_player(p: Dictionary) -> float:
	var port_on: bool = bool(p.get("aim_port_active", true))
	var bat: Variant = p.get("battery_port") if port_on else p.get("battery_stbd")
	var elev_deg: float = 0.0
	if bat != null:
		elev_deg = bat.elevation_degrees()
	var elev_rad: float = deg_to_rad(elev_deg)
	var vh: float = a._CannonBallistics.MUZZLE_SPEED * cos(elev_rad)
	var vz: float = a._CannonBallistics.MUZZLE_SPEED * sin(elev_rad)
	var h0: float = a._CannonBallistics.MUZZLE_HEIGHT
	var g: float = a._CannonBallistics.GRAVITY
	var disc: float = vz * vz + 2.0 * g * h0
	var t_splash: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, g)
	return vh * minf(t_splash, NC.PROJECTILE_LIFETIME)


func draw_world_range_ring(center: Vector2, range_units: float, color: Color, width: float = 1.6, screen_y_offset_px: float = 0.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var segs: int = 96
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var ang: float = t * TAU
		var wx: float = center.x + cos(ang) * range_units
		var wy: float = center.y + sin(ang) * range_units
		points.append(_w2s(wx, wy) + Vector2(0.0, screen_y_offset_px))
	a.draw_polyline(points, color, width * a._zoom, true)


# ── Top-down ocean ───────────────────────────────────────────────────

func draw_top_down_ocean(vp: Vector2) -> void:
	var u: float = NC.UNITS_PER_LOGIC_TILE
	var map_w: float = float(NC.MAP_TILES_WIDE) * u
	var map_h: float = float(NC.MAP_TILES_HIGH) * u
	var tl: Vector2 = _w2s(0.0, 0.0)
	var br: Vector2 = _w2s(map_w, map_h)
	var water_col: Color = Color(0.18, 0.44, 0.64, 1.0)
	var deep_col: Color = Color(0.06, 0.22, 0.42, 1.0)
	a.draw_rect(Rect2(tl, br - tl), water_col)
	var edge_u: float = 3.0 * u
	var inner_tl: Vector2 = _w2s(edge_u, edge_u)
	var inner_br: Vector2 = _w2s(map_w - edge_u, map_h - edge_u)
	a.draw_rect(Rect2(tl, Vector2(br.x - tl.x, inner_tl.y - tl.y)), deep_col)
	a.draw_rect(Rect2(Vector2(tl.x, inner_br.y), Vector2(br.x - tl.x, br.y - inner_br.y)), deep_col)
	a.draw_rect(Rect2(Vector2(tl.x, inner_tl.y), Vector2(inner_tl.x - tl.x, inner_br.y - inner_tl.y)), deep_col)
	a.draw_rect(Rect2(Vector2(inner_br.x, inner_tl.y), Vector2(br.x - inner_br.x, inner_br.y - inner_tl.y)), deep_col)
	var grid_spacing: float = 100.0
	var grid_col: Color = Color(0.22, 0.48, 0.68, 0.25)
	var px_per_unit: float = a._TD_SCALE * a._zoom
	if px_per_unit * grid_spacing < 8.0:
		grid_spacing = 500.0
	if px_per_unit * grid_spacing < 4.0:
		return
	var vis_x0: float = maxf(0.0, -a._origin.x / px_per_unit)
	var vis_y0: float = maxf(0.0, -a._origin.y / px_per_unit)
	var vis_x1: float = minf(map_w, (vp.x - a._origin.x) / px_per_unit)
	var vis_y1: float = minf(map_h, (vp.y - a._origin.y) / px_per_unit)
	var gx: float = floorf(vis_x0 / grid_spacing) * grid_spacing
	while gx <= vis_x1:
		a.draw_line(_w2s(gx, vis_y0), _w2s(gx, vis_y1), grid_col, 1.0)
		gx += grid_spacing
	var gy: float = floorf(vis_y0 / grid_spacing) * grid_spacing
	while gy <= vis_y1:
		a.draw_line(_w2s(vis_x0, gy), _w2s(vis_x1, gy), grid_col, 1.0)
		gy += grid_spacing


# ── Accuracy bands ───────────────────────────────────────────────────

func draw_accuracy_bands(center: Vector2, screen_y_offset_px: float = 0.0, alpha_mult: float = 1.0) -> void:
	var bands: Array[Dictionary] = [
		{"r0": 0.0, "r1": NC.ACC_PISTOL_RANGE, "col": Color(0.1, 0.95, 0.2, 0.06 * alpha_mult), "label": "Point Blank"},
		{"r0": NC.ACC_PISTOL_RANGE, "r1": NC.ACC_CLOSE_RANGE, "col": Color(0.3, 0.9, 0.15, 0.05 * alpha_mult), "label": "Close"},
		{"r0": NC.ACC_CLOSE_RANGE, "r1": NC.ACC_MUSKET_RANGE, "col": Color(0.9, 0.85, 0.1, 0.045 * alpha_mult), "label": "Effective"},
		{"r0": NC.ACC_MUSKET_RANGE, "r1": NC.ACC_MEDIUM_RANGE, "col": Color(0.95, 0.5, 0.08, 0.04 * alpha_mult), "label": "Long"},
		{"r0": NC.ACC_MEDIUM_RANGE, "r1": NC.ACC_LONG_RANGE, "col": Color(0.95, 0.15, 0.08, 0.035 * alpha_mult), "label": "Extreme"},
	]
	var segs: int = 72
	for band in bands:
		var inner_r: float = float(band.r0)
		var outer_r: float = float(band.r1)
		var col: Color = band.col
		var verts: PackedVector2Array = PackedVector2Array()
		for i in range(segs + 1):
			var ang: float = float(i) / float(segs) * TAU
			var wx_in: float = center.x + cos(ang) * inner_r
			var wy_in: float = center.y + sin(ang) * inner_r
			verts.append(_w2s(wx_in, wy_in) + Vector2(0.0, screen_y_offset_px))
		for i in range(segs, -1, -1):
			var ang: float = float(i) / float(segs) * TAU
			var wx_out: float = center.x + cos(ang) * outer_r
			var wy_out: float = center.y + sin(ang) * outer_r
			verts.append(_w2s(wx_out, wy_out) + Vector2(0.0, screen_y_offset_px))
		if verts.size() >= 3:
			a.draw_colored_polygon(verts, col)
		draw_world_range_ring(center, outer_r, col * 2.5, 1.2, screen_y_offset_px)
	var label_ang: float = -PI * 0.25
	var label_font_size: int = int(maxf(9.0, 11.0 * a._zoom))
	for band in bands:
		var r_mid: float = (float(band.r0) + float(band.r1)) * 0.5
		var lx: float = center.x + cos(label_ang) * r_mid
		var ly: float = center.y + sin(label_ang) * r_mid
		var sp: Vector2 = _w2s(lx, ly) + Vector2(0.0, screen_y_offset_px)
		a.draw_string(ThemeDB.fallback_font, sp, String(band.label),
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size, Color(1, 1, 1, 0.55 * alpha_mult))


# ── Main draw orchestrator ───────────────────────────────────────────

func draw_all() -> void:
	var vp: Vector2 = a.get_viewport_rect().size
	var me: Dictionary = a._players[a._my_index] if not a._players.is_empty() else {}
	var cam_focus: Vector2 = a._update_camera_origin(vp)
	var me_deck_y_off: float = 0.0
	if not me.is_empty() and bool(me.get("alive", true)):
		me_deck_y_off = -NC.SHIP_DECK_HEIGHT_UNITS * a._CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * a._zoom
	var me_world: Vector2 = Vector2(float(me.wx), float(me.wy)) if not me.is_empty() else cam_focus
	var ring_alpha: float = _hud_fade_alpha(a._fade_accuracy_ring)
	if ring_alpha > 0.01:
		draw_accuracy_bands(me_world, me_deck_y_off, ring_alpha)
		var ballistic_max: float = ballistic_splash_range_for_player(me)
		draw_world_range_ring(me_world, ballistic_max, Color(1.0, 0.25, 0.1, 0.7 * ring_alpha), 2.4, me_deck_y_off)

	var sorted: Array = a._players.duplicate()
	sorted.sort_custom(func(sa: Dictionary, sb: Dictionary) -> bool:
		return (sa.wx + sa.wy) < (sb.wx + sb.wy))
	for p in sorted:
		draw_player(p)


	draw_muzzle_fx()
	if a._fade_path_line > 0.01:
		draw_ship_trajectory_arc_preview(_hud_fade_alpha(a._fade_path_line))
	if a._fade_ballistics_arc > 0.01:
		draw_trajectory_arc_preview(_hud_fade_alpha(a._fade_ballistics_arc))
	draw_aim_cursor()
	draw_projectiles()
	draw_hull_strike_fx()
	draw_motion_battery_hud(vp)
	draw_helm_sail_hud(vp)
	draw_ftl_ship_hud(vp)
	draw_offscreen_indicators(vp)
	draw_hud(vp)
	if a.pause_menu_panel != null and a.pause_menu_panel.visible:
		draw_keybindings_panel(vp)
	draw_ability_bar(vp)
	if a._winner != -2:
		draw_win_screen(vp)
	if Input.is_action_pressed(a.SCOREBOARD_ACTION) or a._match_over:
		draw_scoreboard(vp)


# ── Off-screen indicators ───────────────────────────────────────────

## Off-screen arrows aim at the **drawn** hull (deck lift), not waterline wx/wy.
func draw_offscreen_indicators(vp: Vector2) -> void:
	const EDGE_PAD := 30.0
	const ARROW_R := 12.0
	var font: Font = ThemeDB.fallback_font
	var screen_center: Vector2 = vp * 0.5
	for p in a._players:
		if not p.alive:
			continue
		var sp: Vector2 = _hull_visual_screen_pos(p)
		if sp.x >= EDGE_PAD and sp.x <= vp.x - EDGE_PAD \
				and sp.y >= EDGE_PAD and sp.y <= vp.y - EDGE_PAD:
			continue
		var dir: Vector2 = (sp - screen_center).normalized()
		var t_x: float = INF
		var t_y: float = INF
		if absf(dir.x) > 0.0001:
			var tx0: float = (EDGE_PAD - screen_center.x) / dir.x
			var tx1: float = (vp.x - EDGE_PAD - screen_center.x) / dir.x
			t_x = tx1 if dir.x > 0.0 else tx0
		if absf(dir.y) > 0.0001:
			var ty0: float = (EDGE_PAD - screen_center.y) / dir.y
			var ty1: float = (vp.y - EDGE_PAD - screen_center.y) / dir.y
			t_y = ty1 if dir.y > 0.0 else ty0
		var t: float = minf(t_x, t_y)
		var ap: Vector2 = screen_center + dir * t
		var pa: Color = p.palette[0]
		var R: float = ARROW_R
		var side: Vector2 = Vector2(-dir.y, dir.x)
		# Ship silhouette: pointed bow, widest at midship, tapered stern.
		var bow: Vector2 = ap + dir * R * 1.1
		var bow_l: Vector2 = ap + dir * R * 0.7 - side * R * 0.3
		var bow_r: Vector2 = ap + dir * R * 0.7 + side * R * 0.3
		var mid_l: Vector2 = ap + dir * R * 0.1 - side * R * 0.52
		var mid_r: Vector2 = ap + dir * R * 0.1 + side * R * 0.52
		var aft_l: Vector2 = ap - dir * R * 0.6 - side * R * 0.42
		var aft_r: Vector2 = ap - dir * R * 0.6 + side * R * 0.42
		var stern_l: Vector2 = ap - dir * R * 0.85 - side * R * 0.28
		var stern_r: Vector2 = ap - dir * R * 0.85 + side * R * 0.28
		var stern: Vector2 = ap - dir * R * 0.75
		var ship_poly := PackedVector2Array([bow, bow_r, mid_r, aft_r, stern_r, stern, stern_l, aft_l, mid_l, bow_l])
		const S := 1.18
		var shadow_poly := PackedVector2Array()
		var center: Vector2 = ap
		for pt in ship_poly:
			shadow_poly.append(center + (pt - center) * S)
		a.draw_colored_polygon(shadow_poly, Color(0.0, 0.0, 0.0, 0.55))
		a.draw_colored_polygon(ship_poly, pa)
		var label_pos: Vector2 = ap - dir * (ARROW_R + 10.0)
		a.draw_string(font, label_pos, p.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(pa.r, pa.g, pa.b, 0.90))


# ── Bot debug HUD ────────────────────────────────────────────────────

func draw_bot_debug_hud(vp: Vector2) -> void:
	if a._bot_indices.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs: int = 10
	var panel_w: float = 260.0
	var x: float = 10.0
	var total_lines: int = 0
	for ci in range(a._bot_indices.size()):
		var bi: int = a._bot_indices[ci]
		if bi < 0 or bi >= a._players.size():
			continue
		if bool(a._players[bi].get("alive", false)):
			total_lines += 8
		else:
			total_lines += 6
	var y: float = vp.y - float(total_lines) * 13.0 - 24.0
	var label_colors: Array = [
		Color(0.95, 0.40, 0.35, 1.0),
		Color(1.00, 0.80, 0.30, 1.0),
		Color(0.80, 0.55, 0.95, 1.0),
	]
	for ci in range(a._bot_indices.size()):
		var bi: int = a._bot_indices[ci]
		if bi < 0 or bi >= a._players.size():
			continue
		var p: Dictionary = a._players[bi]
		var col: Color = label_colors[ci % label_colors.size()]
		var lines: Array[String] = []
		var ship_label: String = str(p.get("label", "Bot%d" % ci))
		var alive: bool = bool(p.get("alive", false))
		lines.append("── %s (%s) ──" % [ship_label, "ALIVE" if alive else "DEAD"])
		if not alive:
			var rt: float = float(p.get("respawn_timer", 0.0))
			lines.append("  Respawn: %.1fs" % rt)
		else:
			var spd: float = float(p.get("move_speed", 0.0))
			var ang_v: float = float(p.get("angular_velocity", 0.0))
			lines.append("  Spd: %.1f  AngVel: %.2f" % [spd, ang_v])
			var sail_obj = p.get("sail")
			if sail_obj != null:
				lines.append("  Sail: %s  Deploy: %d%%" % [sail_obj.get_display_name(), int(sail_obj.current_sail_level * 100.0)])
			var helm_obj = p.get("helm")
			if helm_obj != null:
				var rud_deg: float = helm_obj.rudder_angle * a._HelmController.MAX_RUDDER_DEFLECTION_DEG
				lines.append("  Helm: %s  Rudder: %.0f°" % [helm_obj.get_helm_state_label(), rud_deg])
		var ctrl: Variant = null
		if ci < a._bot_controllers.size():
			ctrl = a._bot_controllers[ci]
		if ctrl != null:
			lines.append("  BT: %s  Man: %s" % [ctrl.current_bt_state, ctrl.last_maneuver])
			lines.append("  Dist: %.0f  Band: %s  Bearing: %.0f°" % [ctrl.distance_to_target, NavalCombatEvaluator.band_name(ctrl.range_band), ctrl.bearing_to_target_deg])
			lines.append("  Steer: L%.1f R%.1f  Sail: %d" % [ctrl.steer_left, ctrl.steer_right, ctrl.desired_sail_state])
			lines.append("  Block: %s" % ctrl.fire_block_reason)
			if not ctrl._bt_initialised:
				lines.append("  !! BT INIT FAILED")
		else:
			lines.append("  !! NO CONTROLLER")

		var panel_h: float = float(lines.size()) * 13.0 + 6.0
		a.draw_rect(Rect2(x - 5.0, y - 2.0, panel_w, panel_h), Color(0.0, 0.0, 0.0, 0.62))
		for line in lines:
			a.draw_string(font, Vector2(x, y + 11.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += 13.0
		y += 6.0


# ── Projectiles ──────────────────────────────────────────────────────

func draw_projectiles() -> void:
	var hs: float = a._CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * a._zoom
	for proj in a._proj.projectiles:
		if not bool(proj.get("alive", true)):
			continue
		var wx: float = float(proj.get("wx", 0.0))
		var wy: float = float(proj.get("wy", 0.0))
		var h: float = float(proj.get("h", 0.0))
		var vx: float = float(proj.get("vx", 0.0))
		var vy: float = float(proj.get("vy", 0.0))
		var sp: Vector2 = _w2s(wx, wy)
		# Lift draw position so the ball reads as flying above the water plane.
		sp += Vector2(0.0, -h * hs)
		var horiz := Vector2(vx, vy)
		var trail: Vector2 = _dir_screen(vx, vy) * 16.0 * a._zoom if horiz.length_squared() > 0.0001 else Vector2.RIGHT * 10.0 * a._zoom
		var core: Color = Color(0.18, 0.17, 0.16, 1.0)
		var rim: Color = Color(0.42, 0.40, 0.38, 0.95)
		var rad: float = (9.0 + minf(h * 0.4, 4.0)) * a._zoom
		a.draw_line(sp - trail * 0.35, sp + trail * 0.5, Color(0.35, 0.32, 0.28, 0.65), 3.5 * a._zoom)
		a.draw_circle(sp, rad + 2.0 * a._zoom, rim)
		a.draw_circle(sp, rad, core)


# ── Trajectory arc preview ───────────────────────────────────────────

func draw_trajectory_arc_preview(alpha_mult: float = 1.0) -> void:
	if a._players.is_empty():
		return
	var p: Dictionary = a._players[a._my_index]
	if not bool(p.get("alive", true)):
		return
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_n.length_squared() < 0.0001:
		hull_n = Vector2.RIGHT
	else:
		hull_n = hull_n.normalized()
	var batteries: Array[Dictionary] = []
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	var port_active: bool = bool(p.get("aim_port_active", true))
	var stbd_active: bool = bool(p.get("aim_stbd_active", false))
	if port_b != null and port_active:
		var aim_p: Vector2 = _effective_broadside_aim_for_side(p, hull_n, true)
		batteries.append({"bat": port_b, "aim": aim_p, "col": Color(1.0, 0.28, 0.22, 0.82 * alpha_mult)})
	if stbd_b != null and stbd_active:
		var aim_s: Vector2 = _effective_broadside_aim_for_side(p, hull_n, false)
		batteries.append({"bat": stbd_b, "aim": aim_s, "col": Color(1.0, 0.45, 0.18, 0.82 * alpha_mult)})
	for bd in batteries:
		draw_single_battery_arc(p, bd.aim, bd.bat, bd.col, alpha_mult)


func draw_single_battery_arc(p: Dictionary, aim_dir: Vector2, bat: RefCounted, color: Color, alpha_mult: float = 1.0) -> void:
	var est_range: float = float(p.get("_naval_acc_dist", NC.OPTIMAL_RANGE))
	if est_range < 0.0 or est_range > NC.MAX_CANNON_RANGE:
		est_range = NC.OPTIMAL_RANGE
	var spread_half: float = _spread_cone_half_deg(p, est_range)
	var dirs: Array[Vector2] = [
		aim_dir,
		aim_dir.rotated(deg_to_rad(spread_half)),
		aim_dir.rotated(deg_to_rad(-spread_half)),
	]
	var elev_deg_arc: float = bat.elevation_degrees()
	@warning_ignore("integer_division")
	var mid_gun: int = maxi(0, (bat.cannon_count - 1) / 2)
	var muzzle_w: Vector2 = _cannon_muzzle_world(p, bat, mid_gun)
	for idx in range(dirs.size()):
		var d: Vector2 = dirs[idx].normalized()
		var vel: Dictionary = a._CannonBallistics.initial_velocity(d, elev_deg_arc)
		var vx: float = float(vel.vx)
		var vy: float = float(vel.vy)
		var vz: float = float(vel.vz)
		var wx0: float = muzzle_w.x
		var wy0: float = muzzle_w.y
		var h0: float = a._CannonBallistics.MUZZLE_HEIGHT
		var grav: float = a._CannonBallistics.GRAVITY
		var hs_px: float = a._CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * a._zoom
		var vz0: float = vz
		var disc: float = vz0 * vz0 + 2.0 * grav * h0
		var t_splash: float = (vz0 + sqrt(maxf(0.0, disc))) / maxf(0.001, grav)
		var max_t: float = minf(t_splash, NC.PROJECTILE_LIFETIME)
		var steps: int = 40
		var dt: float = max_t / maxf(1.0, float(steps))
		var points: PackedVector2Array = PackedVector2Array()
		for i_step in range(steps + 1):
			var t: float = float(i_step) * dt
			var wx_t: float = wx0 + vx * t
			var wy_t: float = wy0 + vy * t
			var h_t: float = h0 + vz0 * t - 0.5 * grav * t * t
			if h_t < 0.0:
				break
			var sp: Vector2 = _w2s(wx_t, wy_t) + Vector2(0.0, -h_t * hs_px)
			points.append(sp)
		if points.size() < 2:
			continue
		var line_w: float = 2.0 if idx == 0 else 1.0
		var line_col: Color = color if idx == 0 else Color(color.r, color.g, color.b, color.a * 0.4)
		a.draw_polyline(points, line_col, line_w, true)
		if idx == 0:
			for i in range(0, points.size(), 4):
				var dot_alpha: float = lerpf(0.8, 0.15, float(i) / maxf(1.0, float(points.size() - 1))) * alpha_mult
				a.draw_circle(points[i], 1.4, Color(color.r, color.g, color.b, dot_alpha))


# ── Ship trajectory arc preview ──────────────────────────────────────

func draw_ship_trajectory_arc_preview(alpha_mult: float = 1.0) -> void:
	if a._players.is_empty():
		return
	var p: Dictionary = a._players[a._my_index]
	if not bool(p.get("alive", true)):
		return
	var helm = p.get("helm")
	var sail = p.get("sail")
	if helm == null or sail == null:
		return

	var hull: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var wx: float = float(p.wx)
	var wy: float = float(p.wy)
	var spd: float = float(p.get("move_speed", 0.0))
	var ang_vel: float = float(p.get("angular_velocity", 0.0))

	var prev_sail_eff: float = lerpf(1.0, a._SailController.MIN_EFFICIENCY, sail.damage)
	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match int(sail.sail_state):
		a._SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED * prev_sail_eff
		a._SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED * prev_sail_eff
		a._SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED * prev_sail_eff
		_:
			target_cap = NC.SAILS_DOWN_DRIFT_SPEED
			sails_provide_thrust = false

	var accel_r: float = NC.accel_rate()
	var decel_r: float = NC.decel_rate_sails()
	var sim_t: float = 0.0
	var sim_max_t: float = 15.0
	var points: PackedVector2Array = PackedVector2Array()
	var deck_lift_y: float = -(NC.SHIP_DECK_HEIGHT_UNITS * a._CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * a._zoom) - 2.0 * a._zoom
	var deck_off: Vector2 = Vector2(0.0, deck_lift_y)
	var dt_step: float = 1.0 / 60.0
	var sim_sail_level: float = float(sail.current_sail_level)
	var sim_sail_target: float = float(sail.get_target_sail_level())
	var sim_sail_rate: float = float(sail.sail_raise_rate) if sim_sail_level < sim_sail_target else float(sail.sail_lower_rate)
	var sim_coast_thresh: float = float(sail.coast_drag_threshold)

	var preview_rudder: float = helm.rudder_angle
	while sim_t <= sim_max_t:
		points.append(_w2s(wx, wy) + deck_off)

		ang_vel = NC.compute_angular_velocity(preview_rudder, spd, ang_vel, dt_step)
		hull = hull.rotated(ang_vel * dt_step).normalized()

		sim_sail_level = move_toward(sim_sail_level, sim_sail_target, sim_sail_rate * dt_step)
		var drag_mult: float = a.COAST_DRAG_MULT if sim_sail_level < sim_coast_thresh else 1.0
		var sim_drift_floor: float = NC.SAILS_DOWN_DRIFT_SPEED if not sails_provide_thrust and spd > 0.01 else 0.0
		if spd < target_cap and sails_provide_thrust:
			spd = minf(spd + accel_r * dt_step, target_cap)
		elif spd > target_cap:
			spd = maxf(0.0, spd - decel_r * drag_mult * dt_step)
		spd = maxf(sim_drift_floor, spd - a.MOTION_PASSIVE_DRAG_K * spd * drag_mult * dt_step)
		if sim_sail_level < sim_coast_thresh:
			spd = maxf(sim_drift_floor, spd - a.MOTION_ZERO_SAIL_DRAG * drag_mult * dt_step)
		var rud_abs: float = absf(preview_rudder)
		spd = maxf(sim_drift_floor, spd - rud_abs * a.MOTION_TURNING_SPEED_LOSS * dt_step)
		if rud_abs > a.MOTION_HARD_TURN_RUDDER:
			spd = maxf(sim_drift_floor, spd - rud_abs * a.MOTION_HARD_TURN_SPEED_LOSS * dt_step)
		spd = clampf(spd, 0.0, NC.MAX_SPEED * 1.05)

		wx += hull.x * spd * dt_step
		wy += hull.y * spd * dt_step
		sim_t += dt_step

	if points.size() < 2:
		return
	a.draw_polyline(points, Color(0.36, 0.86, 1.0, 0.82 * alpha_mult), 2.4, true)
	for i in range(0, points.size(), 6):
		var al: float = lerpf(0.85, 0.18, float(i) / maxf(1.0, float(points.size() - 1))) * alpha_mult
		a.draw_circle(points[i], 1.7, Color(0.62, 0.95, 1.0, al))


# ── Aim cursor ───────────────────────────────────────────────────────

func draw_aim_cursor() -> void:
	if a._players.is_empty():
		return
	var p: Dictionary = a._players[a._my_index]
	if not bool(p.get("alive", true)):
		return
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_n.length_squared() < 0.0001:
		hull_n = Vector2.RIGHT
	hull_n = hull_n.normalized()
	# Draw a reticle for each active battery independently.
	if bool(p.get("aim_port_active", true)):
		var bat: Variant = p.get("battery_port")
		if bat != null:
			draw_battery_reticle(p, hull_n, bat as _BatteryController, true)
	if bool(p.get("aim_stbd_active", false)):
		var bat: Variant = p.get("battery_stbd")
		if bat != null:
			draw_battery_reticle(p, hull_n, bat as _BatteryController, false)


# ── Battery reticle ──────────────────────────────────────────────────

func draw_battery_reticle(p: Dictionary, hull_n: Vector2, bat_br: RefCounted, is_port: bool) -> void:
	var aim_dir: Vector2 = _effective_broadside_aim_for_side(p, hull_n, is_port)
	var elev_deg: float = bat_br.elevation_degrees()
	var vel: Dictionary = a._CannonBallistics.initial_velocity(aim_dir, elev_deg)
	var vx: float = float(vel.vx)
	var vy: float = float(vel.vy)
	var vz: float = float(vel.vz)
	@warning_ignore("integer_division")
	var mid_gun: int = maxi(0, (bat_br.cannon_count - 1) / 2)
	var muzzle_w: Vector2 = _cannon_muzzle_world(p, bat_br, mid_gun)
	var wx0: float = muzzle_w.x
	var wy0: float = muzzle_w.y
	var h0: float = a._CannonBallistics.MUZZLE_HEIGHT
	var grav: float = a._CannonBallistics.GRAVITY
	var disc: float = vz * vz + 2.0 * grav * h0
	var t_splash: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, grav)
	var impact_t: float = minf(t_splash, NC.PROJECTILE_LIFETIME)
	var impact_wx: float = wx0 + vx * impact_t
	var impact_wy: float = wy0 + vy * impact_t
	var sp: Vector2 = _w2s(impact_wx, impact_wy)
	var ship_sp: Vector2 = _hull_visual_screen_pos(p)

	var impact_dist: float = Vector2(impact_wx - muzzle_w.x, impact_wy - muzzle_w.y).length()
	var spread_half_deg: float = _spread_cone_half_deg(p, minf(impact_dist, NC.MAX_CANNON_RANGE))
	var spread_world: float = impact_dist * tan(deg_to_rad(spread_half_deg))
	var n_guns: int = maxi(1, bat_br.cannon_count)
	var hull_half_span: float = float(n_guns - 1) * 0.5 * 2.3
	var is_barrage: bool = bat_br.fire_mode == _BatteryController.FireMode.SALVO
	var w2px: float = a._TD_SCALE * a._zoom
	var aim_s: Vector2 = _dir_screen(aim_dir.x, aim_dir.y)
	if aim_s.length_squared() < 0.0001:
		aim_s = Vector2(1.0, 0.0)
	aim_s = aim_s.normalized()
	var perp_s: Vector2 = Vector2(-aim_s.y, aim_s.x)

	# --- Range line: dashed line from ship to impact point ---
	var range_col: Color = Color(1.0, 1.0, 1.0, 0.15)
	var dash_len: float = 6.0
	var gap_len: float = 8.0
	var line_vec: Vector2 = sp - ship_sp
	var line_len: float = line_vec.length()
	if line_len > 1.0:
		var line_dir: Vector2 = line_vec / line_len
		var drawn: float = 0.0
		while drawn < line_len:
			var seg_start: float = drawn
			var seg_end: float = minf(drawn + dash_len, line_len)
			a.draw_line(ship_sp + line_dir * seg_start, ship_sp + line_dir * seg_end, range_col, 1.0, true)
			drawn = seg_end + gap_len

	if is_barrage:
		# --- BARRAGE: bracket zone showing the wall of iron ---
		# Two parallel lines (hull span + spread) with range-depth end caps.
		var col: Color = Color(1.0, 0.40, 0.15, 0.80)
		var col_fill: Color = Color(1.0, 0.40, 0.15, 0.06)
		var cross_w: float = (hull_half_span + spread_world) * w2px
		var depth_w: float = spread_world * 0.7 * w2px
		cross_w = maxf(cross_w, 6.0)
		depth_w = maxf(depth_w, 4.0)

		# Four corners of the impact zone rectangle.
		var c_tl: Vector2 = sp - perp_s * cross_w - aim_s * depth_w
		var c_tr: Vector2 = sp + perp_s * cross_w - aim_s * depth_w
		var c_br: Vector2 = sp + perp_s * cross_w + aim_s * depth_w
		var c_bl: Vector2 = sp - perp_s * cross_w + aim_s * depth_w

		# Filled zone (very subtle).
		a.draw_colored_polygon(PackedVector2Array([c_tl, c_tr, c_br, c_bl]), col_fill)
		# Bracket lines: two long sides (perpendicular to aim = hull-length spread).
		a.draw_line(c_tl, c_tr, col, 1.8, true)
		a.draw_line(c_bl, c_br, col, 1.8, true)
		# End caps: short lines closing the bracket at each end.
		var cap_len: float = minf(depth_w * 0.6, 8.0)
		a.draw_line(c_tl, c_tl + aim_s * cap_len, col, 1.5, true)
		a.draw_line(c_tr, c_tr + aim_s * cap_len, col, 1.5, true)
		a.draw_line(c_bl, c_bl - aim_s * cap_len, col, 1.5, true)
		a.draw_line(c_br, c_br - aim_s * cap_len, col, 1.5, true)
		# Center dot.
		a.draw_circle(sp, 2.5, col)

		# Range text (meters).
		var range_m: int = int(impact_dist)
		var font: Font = ThemeDB.fallback_font
		a.draw_string(font, sp + aim_s * (depth_w + 10.0) + perp_s * 2.0,
			"%dm" % range_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r, col.g, col.b, 0.6))
	else:
		# --- RIPPLE: focused crosshair at convergence point ---
		var col: Color = Color(0.3, 0.85, 1.0, 0.80)
		var spread_px: float = maxf(spread_world * w2px, 4.0)
		var arm_inner: float = spread_px * 0.4
		var arm_outer: float = spread_px + 6.0

		# Four crosshair arms with gap in the center.
		a.draw_line(sp + perp_s * arm_inner, sp + perp_s * arm_outer, col, 1.5, true)
		a.draw_line(sp - perp_s * arm_inner, sp - perp_s * arm_outer, col, 1.5, true)
		a.draw_line(sp + aim_s * arm_inner, sp + aim_s * arm_outer, col, 1.5, true)
		a.draw_line(sp - aim_s * arm_inner, sp - aim_s * arm_outer, col, 1.5, true)

		# Diamond showing the spread cone.
		var d_cross: float = spread_px
		var d_along: float = spread_px * 0.6
		var diamond: PackedVector2Array = PackedVector2Array([
			sp - perp_s * d_cross,
			sp + aim_s * d_along,
			sp + perp_s * d_cross,
			sp - aim_s * d_along,
			sp - perp_s * d_cross,
		])
		a.draw_polyline(diamond, Color(col.r, col.g, col.b, 0.5), 1.2, true)

		# Center dot.
		a.draw_circle(sp, 2.0, col)

		# Range text.
		var range_m: int = int(impact_dist)
		var font: Font = ThemeDB.fallback_font
		a.draw_string(font, sp + aim_s * (arm_outer + 6.0) + perp_s * 2.0,
			"%dm" % range_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r, col.g, col.b, 0.6))


# ── Motion / Battery HUD ────────────────────────────────────────────

func draw_motion_battery_hud(_vp: Vector2) -> void:
	if a._players.is_empty():
		return
	var p: Dictionary = a._players[a._my_index]
	var font: Font = ThemeDB.fallback_font
	var x: float = 14.0
	var y: float = 94.0
	var panel_w: float = 200.0
	var txt: Color = Color(0.94, 0.95, 1.0, 0.96)
	var sub: Color = Color(0.78, 0.86, 0.98, 0.9)
	var dim: Color = Color(0.55, 0.62, 0.72, 0.88)

	var bs_port_on: bool = bool(p.get("aim_port_active", true))
	var bs_stbd_on: bool = bool(p.get("aim_stbd_active", false))
	var bs_txt: String
	if bs_port_on and bs_stbd_on:
		bs_txt = "Both broadsides"
	elif bs_port_on:
		bs_txt = "Port broadside"
	elif bs_stbd_on:
		bs_txt = "Starboard broadside"
	else:
		bs_txt = "No battery selected"
	a.draw_string(font, Vector2(x, y), "Aim: %s" % bs_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, txt)
	var spr_info: Dictionary = a.compute_ship_sprite_for_world_heading(float(p.dir.x), float(p.dir.y))
	var spr_label: String = str(spr_info.get("sprite_compass", "?"))
	var fidx: int = int(spr_info.get("frame_idx", 0))
	var wdeg: float = float(spr_info.get("world_deg", 0.0))
	var scrdeg: float = float(spr_info.get("screen_deg", 0.0))
	var secdeg: float = float(spr_info.get("screen_norm_sector_deg", 0.0))
	a.draw_string(font, Vector2(x, y + 14.0), "Ship texture: %s [_SHIP_TEXTURES[%d]]" % [spr_label, fidx], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	a.draw_string(font, Vector2(x, y + 28.0), "Heading world (wx,wy): %.1f deg" % wdeg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	a.draw_string(font, Vector2(x, y + 40.0), "Heading screen (sprite axis): %.1f deg  sector 0-360: %.1f" % [scrdeg, secdeg], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	var motion = p.get("motion")
	var lin_raw: Variant = p.get("linear_motion_state", 0)
	var turn: bool = bool(p.get("motion_is_turning", false))
	var turn_h: bool = bool(p.get("motion_is_turning_hard", false))
	var motion_line: String = "—"
	if motion != null:
		motion_line = motion.format_motion_summary(lin_raw as _MotionStateResolver.LinearMotionState, turn, turn_h)
	a.draw_string(font, Vector2(x, y + 56.0), "Motion FSM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	a.draw_string(font, Vector2(x, y + 72.0), motion_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	var spd: float = float(p.get("move_speed", 0.0))
	var cap: float = 0.0
	var sail = p.get("sail")
	if sail != null:
		match sail.sail_state:
			a._SailController.SailState.FULL:
				cap = NC.MAX_SPEED
			a._SailController.SailState.HALF:
				cap = NC.CRUISE_SPEED
			a._SailController.SailState.QUARTER:
				cap = NC.QUARTER_SPEED
			_:
				cap = NC.SAILS_DOWN_DRIFT_SPEED
	a.draw_string(font, Vector2(x, y + 88.0), "Speed %.2f / %.1f" % [spd, cap], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)

	var bat_y: float = y + 108.0
	var sel_port_on: bool = bool(p.get("aim_port_active", true))
	var sel_stbd_on: bool = bool(p.get("aim_stbd_active", false))
	var fire_sel: String
	if sel_port_on and sel_stbd_on:
		fire_sel = "Both (E/Q)"
	elif sel_port_on:
		fire_sel = "Port (E)"
	elif sel_stbd_on:
		fire_sel = "Starboard (Q)"
	else:
		fire_sel = "None"
	a.draw_string(font, Vector2(x, bat_y), "Fire battery: %s · F/RT" % fire_sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sub)
	a.draw_string(font, Vector2(x, bat_y + 14.0), "Batteries", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	draw_battery_row(font, x, bat_y + 30.0, panel_w, p.get("battery_port"), txt, sub, dim, sel_port_on)
	draw_battery_row(font, x, bat_y + 58.0, panel_w, p.get("battery_stbd"), txt, sub, dim, sel_stbd_on)


func draw_battery_row(font: Font, x: float, y: float, panel_w: float, bat: Variant, txt: Color, _sub: Color, dim: Color, selected: bool = false) -> void:
	if bat == null:
		a.draw_string(font, Vector2(x, y), "Battery —", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		return
	var b = bat as _BatteryController
	var sel_tag: String = " [selected]" if selected else ""
	var line: String = "%s · %s · %s%s" % [b.side_label(), b.fire_mode_display(), b.state_display(), sel_tag]
	a.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	var bar_w: float = panel_w - 4.0
	var bar_y: float = y + 12.0
	var fill: float = b.reload_progress()
	var bg: Color = Color(0.08, 0.1, 0.14, 0.92)
	var fg: Color = Color(0.85, 0.62, 0.35, 0.9) if b.state == _BatteryController.BatteryState.RELOADING else Color(0.35, 0.72, 0.48, 0.85)
	a.draw_rect(Rect2(x, bar_y, bar_w, 6.0), bg)
	a.draw_rect(Rect2(x, bar_y, bar_w * fill, 6.0), fg)
	var rtxt: String = "Reload" if b.state == _BatteryController.BatteryState.RELOADING else "Ready"
	a.draw_string(font, Vector2(x + bar_w + 6.0, bar_y + 5.0), rtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)


# ── FTL Ship HUD ─────────────────────────────────────────────────────

func draw_ftl_ship_hud(vp: Vector2) -> void:
	if a._players.is_empty():
		return
	var hud_idx: int = clampi(a._camera_follow_index, 0, a._players.size() - 1)
	var p: Dictionary = a._players[hud_idx]
	var font: Font = ThemeDB.fallback_font
	var sel_fire_port: bool = bool(p.get("aim_port_active", true))
	var sel_fire_stbd: bool = bool(p.get("aim_stbd_active", false))
	var hw: float = 64.0
	var hh: float = 180.0
	var cx: float = vp.x - hw - 20.0
	var cy: float = vp.y * 0.5
	var panel_x: float = cx - hw - 10.0
	var panel_y: float = cy - hh * 0.5 - 28.0
	var panel_w: float = hw * 2.0 + 20.0
	var panel_h: float = hh + 80.0

	a.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.03, 0.05, 0.09, 0.92))
	a.draw_rect(Rect2(panel_x + 1.0, panel_y + 1.0, panel_w - 2.0, panel_h - 2.0), Color(0.18, 0.24, 0.36, 0.85), false, 1.0)
	a.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.28, 0.36, 0.50, 0.9), false, 1.5)

	var title_y: float = panel_y + 16.0
	a.draw_string(font, Vector2(cx - 28.0, title_y), "SHIP STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.78, 0.88, 0.9))
	a.draw_line(Vector2(panel_x + 6.0, title_y + 4.0), Vector2(panel_x + panel_w - 6.0, title_y + 4.0), Color(0.28, 0.36, 0.48, 0.6), 1.0)

	var hull_dark: Color = Color(0.24, 0.20, 0.16, 0.95)
	var hull_mid: Color = Color(0.38, 0.32, 0.24, 0.92)
	var bow_tip: Vector2 = Vector2(cx, cy - hh * 0.44)
	var bow_l: Vector2 = Vector2(cx - hw * 0.35, cy - hh * 0.32)
	var bow_r: Vector2 = Vector2(cx + hw * 0.35, cy - hh * 0.32)
	var fwd_l: Vector2 = Vector2(cx - hw * 0.62, cy - hh * 0.15)
	var fwd_r: Vector2 = Vector2(cx + hw * 0.62, cy - hh * 0.15)
	var mid_l: Vector2 = Vector2(cx - hw * 0.72, cy + hh * 0.02)
	var mid_r: Vector2 = Vector2(cx + hw * 0.72, cy + hh * 0.02)
	var aft_l: Vector2 = Vector2(cx - hw * 0.65, cy + hh * 0.22)
	var aft_r: Vector2 = Vector2(cx + hw * 0.65, cy + hh * 0.22)
	var stern_l: Vector2 = Vector2(cx - hw * 0.48, cy + hh * 0.38)
	var stern_r: Vector2 = Vector2(cx + hw * 0.48, cy + hh * 0.38)
	var transom: Vector2 = Vector2(cx, cy + hh * 0.35)
	var hull_poly: PackedVector2Array = PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l])
	a.draw_colored_polygon(hull_poly, hull_dark)
	a.draw_polyline(PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l, bow_tip]),
		hull_mid, 1.8, true)

	a.draw_line(Vector2(cx, cy - hh * 0.42), Vector2(cx, cy - hh * 0.50), Color(0.55, 0.45, 0.30, 0.85), 2.0, true)
	a.draw_line(Vector2(cx - 8.0, cy - hh * 0.50), Vector2(cx + 8.0, cy - hh * 0.50), Color(0.55, 0.45, 0.30, 0.7), 1.5, true)
	a.draw_line(Vector2(cx, cy - hh * 0.08), Vector2(cx, cy - hh * 0.32), Color(0.50, 0.42, 0.28, 0.7), 1.5, true)
	a.draw_line(Vector2(cx - 12.0, cy - hh * 0.28), Vector2(cx + 12.0, cy - hh * 0.28), Color(0.50, 0.42, 0.28, 0.6), 1.2, true)
	a.draw_line(Vector2(cx, cy + 0.0), Vector2(cx, cy + hh * 0.15), Color(0.50, 0.42, 0.28, 0.6), 1.2, true)

	var hp: float = float(p.get("health", a.HULL_HITS_MAX))
	var hp_frac: float = clampf(hp / a.HULL_HITS_MAX, 0.0, 1.0)

	var zone_names: Array[String] = ["Bowsprit", "Bow", "Fwd Gun", "Mid", "Main", "Aft Gun", "Quarter", "Stern"]
	var zone_count: int = zone_names.size()
	var zone_y_start: float = cy - hh * 0.42
	var zone_total_h: float = hh * 0.80
	var zone_h: float = zone_total_h / float(zone_count)

	var zone_widths: Array[float] = [0.30, 0.50, 0.68, 0.72, 0.72, 0.65, 0.52, 0.40]
	for zi in range(zone_count):
		var zy: float = zone_y_start + float(zi) * zone_h
		var zw: float = hw * zone_widths[zi]
		var zone_hp: float = hp_frac
		var zone_col: Color
		if hp <= 0.0:
			zone_col = Color(0.12, 0.10, 0.08, 0.5)
		elif zone_hp > 0.7:
			zone_col = Color(0.18, 0.48, 0.28, 0.55)
		elif zone_hp > 0.4:
			zone_col = Color(0.62, 0.52, 0.18, 0.55)
		elif zone_hp > 0.15:
			zone_col = Color(0.72, 0.32, 0.14, 0.55)
		else:
			zone_col = Color(0.78, 0.18, 0.12, 0.65)
		a.draw_rect(Rect2(cx - zw * 0.5, zy + 1.0, zw, zone_h - 2.0), zone_col)
		a.draw_line(Vector2(cx - zw * 0.5, zy + zone_h - 1.0), Vector2(cx + zw * 0.5, zy + zone_h - 1.0), Color(0.40, 0.44, 0.52, 0.35), 0.8)
		var lbl_col: Color = Color(0.82, 0.85, 0.92, 0.75)
		a.draw_string(font, Vector2(cx - zw * 0.5 + 3.0, zy + zone_h - 4.0), zone_names[zi], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, lbl_col)

	var bat_icon_r: float = 6.0
	var bat_entries: Array[Dictionary] = []
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	if port_b != null:
		bat_entries.append({"bat": port_b, "pos": Vector2(cx - hw * 0.88, cy - hh * 0.05), "label": "P"})
	if stbd_b != null:
		bat_entries.append({"bat": stbd_b, "pos": Vector2(cx + hw * 0.88, cy - hh * 0.05), "label": "S"})
	for be in bat_entries:
		var bat = be.bat as _BatteryController
		var bp: Vector2 = be.pos
		var is_ready: bool = bat.state == _BatteryController.BatteryState.READY
		var reloading: bool = bat.state == _BatteryController.BatteryState.RELOADING
		var firing: bool = bat.state == _BatteryController.BatteryState.FIRING
		var disabled: bool = bat.state == _BatteryController.BatteryState.DISABLED
		var bc: Color
		var state_label: String
		if disabled:
			bc = Color(0.25, 0.12, 0.10, 0.8)
			state_label = "DISABLED"
		elif firing:
			bc = Color(1.0, 0.65, 0.15, 0.95)
			state_label = "FIRING"
		elif reloading:
			var prog: float = bat.reload_progress()
			bc = Color(lerpf(0.65, 0.30, prog), lerpf(0.22, 0.68, prog), 0.28, 0.9)
			state_label = "RELOAD %d%%" % int(prog * 100.0)
		elif is_ready:
			bc = Color(0.2, 0.85, 0.35, 0.95)
			state_label = "READY"
		else:
			bc = Color(0.45, 0.48, 0.55, 0.7)
			state_label = bat.state_display()
		a.draw_circle(bp, bat_icon_r, Color(0.06, 0.08, 0.12, 0.9))
		a.draw_circle(bp, bat_icon_r - 1.5, bc)
		a.draw_arc(bp, bat_icon_r, 0.0, TAU, 20, Color(0.6, 0.65, 0.75, 0.7), 1.2, true)
		var bat_is_selected: bool = (bat.side == _BatteryController.BatterySide.PORT and sel_fire_port) \
			or (bat.side == _BatteryController.BatterySide.STARBOARD and sel_fire_stbd)
		if bat_is_selected:
			a.draw_arc(bp, bat_icon_r + 3.5, 0.0, TAU, 24, Color(1.0, 0.88, 0.30, 0.92), 2.0, true)
		if is_ready:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			a.draw_arc(bp, bat_icon_r + 2.0, 0.0, TAU, 16, Color(0.2, 1.0, 0.4, 0.35 * pulse), 1.5, true)
		if reloading:
			a.draw_arc(bp, bat_icon_r + 2.0, -PI * 0.5, -PI * 0.5 + TAU * bat.reload_progress(), 16, Color(0.82, 0.70, 0.32, 0.9), 2.2, true)
		a.draw_string(font, bp + Vector2(-3.0, 3.5), be.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.95, 1.0, 0.95))
		var lbl_offset: Vector2
		match bat.side:
			_BatteryController.BatterySide.PORT:
				lbl_offset = Vector2(-bat_icon_r - 4.0, 3.5)
				a.draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_RIGHT, int(bat_icon_r * 8.0), 7, bc)
			_BatteryController.BatterySide.STARBOARD:
				lbl_offset = Vector2(bat_icon_r + 4.0, 3.5)
				a.draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, bc)
			_:
				lbl_offset = Vector2(-16.0, bat_icon_r + 9.0)
				a.draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_CENTER, 32, 7, bc)

	# Gun port dots along the hull sides.
	var gun_count: int = 8
	for gi in range(gun_count):
		var t: float = 0.18 + float(gi) / float(gun_count - 1) * 0.58
		var gy: float = cy - hh * 0.42 + zone_total_h * t
		var gw_t: float = lerpf(0.50, 0.72, clampf((t - 0.1) / 0.4, 0.0, 1.0))
		if t > 0.6:
			gw_t = lerpf(0.72, 0.45, clampf((t - 0.6) / 0.3, 0.0, 1.0))
		var gx_off: float = hw * gw_t * 0.5 - 2.0
		var gc: Color = Color(0.55, 0.48, 0.32, 0.7)
		a.draw_rect(Rect2(cx - gx_off - 2.5, gy - 1.0, 5.0, 2.0), gc)
		a.draw_rect(Rect2(cx + gx_off - 2.5, gy - 1.0, 5.0, 2.0), gc)

	var hp_bar_x: float = panel_x + 6.0
	var hp_bar_y: float = cy + hh * 0.5 - 4.0
	var hp_bar_w: float = panel_w - 12.0
	a.draw_rect(Rect2(hp_bar_x, hp_bar_y, hp_bar_w, 12.0), Color(0.06, 0.08, 0.12, 0.95))
	a.draw_rect(Rect2(hp_bar_x, hp_bar_y, hp_bar_w, 12.0), Color(0.25, 0.30, 0.42, 0.7), false, 1.0)
	var hp_col: Color
	if hp_frac > 0.6:
		hp_col = Color(0.25, 0.72, 0.35, 0.92)
	elif hp_frac > 0.3:
		hp_col = Color(0.78, 0.68, 0.22, 0.92)
	else:
		hp_col = Color(0.85, 0.22, 0.18, 0.92)
	a.draw_rect(Rect2(hp_bar_x + 1.0, hp_bar_y + 1.0, (hp_bar_w - 2.0) * hp_frac, 10.0), hp_col)
	for tick_i in range(1, int(a.HULL_HITS_MAX)):
		var tx: float = hp_bar_x + hp_bar_w * (float(tick_i) / a.HULL_HITS_MAX)
		a.draw_line(Vector2(tx, hp_bar_y + 1.0), Vector2(tx, hp_bar_y + 11.0), Color(0.12, 0.14, 0.18, 0.6), 0.8)
	a.draw_string(font, Vector2(hp_bar_x, hp_bar_y + 24.0), "Hull %d / %d" % [int(maxf(hp, 0.0)), int(a.HULL_HITS_MAX)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.88, 0.95, 0.95))

	var elev_y: float = hp_bar_y + 36.0
	var elev_alpha: float = _hud_fade_alpha(a._fade_elev_hud)
	var ref_bat: Variant = p.get("battery_port") if sel_fire_port else p.get("battery_stbd")
	if ref_bat != null and elev_alpha > 0.01:
		var elev_val: float = ref_bat.cannon_elevation
		var elev_deg: float = ref_bat.elevation_degrees()
		var elev_col: Color = Color(0.6, 0.75, 0.95, 0.9 * elev_alpha)
		a.draw_rect(Rect2(hp_bar_x, elev_y, hp_bar_w, 8.0), Color(0.06, 0.08, 0.12, 0.92 * elev_alpha))
		a.draw_rect(Rect2(hp_bar_x + 1.0, elev_y + 1.0, (hp_bar_w - 2.0) * elev_val, 6.0), elev_col)
		var tick_x: float = hp_bar_x + hp_bar_w * elev_val
		a.draw_rect(Rect2(tick_x - 1.0, elev_y - 1.0, 3.0, 10.0), Color(1.0, 1.0, 1.0, 0.9 * elev_alpha))
		var zero_frac: float = absf(ref_bat.ELEV_MIN_DEG) / (ref_bat.ELEV_MAX_DEG - ref_bat.ELEV_MIN_DEG)
		var zero_x: float = hp_bar_x + hp_bar_w * zero_frac
		a.draw_rect(Rect2(zero_x - 0.5, elev_y - 2.0, 1.0, 12.0), Color(1.0, 1.0, 0.6, 0.7 * elev_alpha))
		var sign_str: String = "+" if elev_deg >= 0.0 else ""
		a.draw_string(font, Vector2(hp_bar_x, elev_y + 20.0), "Quoin %s%.1f° (R/T)" % [sign_str, elev_deg], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, elev_col)


# ── Helm / Sail HUD ──────────────────────────────────────────────────

func draw_helm_sail_hud(vp: Vector2) -> void:
	if a._players.is_empty():
		return
	var p: Dictionary = a._players[a._my_index]
	var sail = p.get("sail")
	var helm = p.get("helm")
	if sail == null or helm == null:
		return
	var font: Font = ThemeDB.fallback_font
	var panel_w: float = 188.0
	var x: float = vp.x - panel_w - 14.0
	var y: float = 94.0
	var txt: Color = Color(0.94, 0.95, 1.0, 0.96)
	var sub: Color = Color(0.78, 0.86, 0.98, 0.9)
	a.draw_string(font, Vector2(x, y), "Helm FSM: %s" % helm.get_helm_state_enum_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	a.draw_string(font, Vector2(x, y + 18.0), "%s · %s" % [helm.get_helm_state_label(), helm.get_rudder_label()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	a.draw_string(font, Vector2(x, y + 36.0), "Sail: %s" % sail.get_display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, txt)
	a.draw_string(font, Vector2(x, y + 54.0), "Deploy %d%%" % int(clampf(sail.current_sail_level, 0.0, 1.0) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	var spd_u: float = float(p.get("move_speed", 0.0))
	var spd_kn: float = spd_u * a._KNOTS_PER_GAME_UNIT
	a.draw_string(font, Vector2(x, y + 68.0), "Speed: %.1f kn" % spd_kn, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, txt)

	# --- Component damage indicators ---
	var comp_y: float = y + 82.0
	var bar_w: float = panel_w - 8.0
	var comp_bar_h: float = 5.0
	# Sail damage bar
	if sail.damage > 0.01:
		var sail_dmg_col: Color = Color(0.95, 0.65, 0.20, 0.92) if sail.damage < 0.6 else Color(0.92, 0.30, 0.18, 0.95)
		a.draw_rect(Rect2(x, comp_y, bar_w, comp_bar_h), Color(0.08, 0.1, 0.14, 0.8))
		a.draw_rect(Rect2(x, comp_y, bar_w * clampf(sail.damage, 0.0, 1.0), comp_bar_h), sail_dmg_col)
		a.draw_string(font, Vector2(x + bar_w + 3.0, comp_y + comp_bar_h), "Rigging -%d%%" % int(sail.damage * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, sail_dmg_col)
		comp_y += comp_bar_h + 3.0
	# Helm damage bar
	if helm.damage > 0.01:
		var helm_dmg_col: Color = Color(0.95, 0.65, 0.20, 0.92) if helm.damage < 0.6 else Color(0.92, 0.30, 0.18, 0.95)
		a.draw_rect(Rect2(x, comp_y, bar_w, comp_bar_h), Color(0.08, 0.1, 0.14, 0.8))
		a.draw_rect(Rect2(x, comp_y, bar_w * clampf(helm.damage, 0.0, 1.0), comp_bar_h), helm_dmg_col)
		a.draw_string(font, Vector2(x + bar_w + 3.0, comp_y + comp_bar_h), "Rudder -%d%%" % int(helm.damage * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, helm_dmg_col)
		comp_y += comp_bar_h + 3.0
	var comp_offset: float = comp_y - (y + 82.0)

	var sail_y: float = y + 86.0 + comp_offset
	a.draw_rect(Rect2(x, sail_y, bar_w, 8.0), Color(0.08, 0.1, 0.14, 0.92))
	a.draw_rect(Rect2(x, sail_y, bar_w * clampf(sail.current_sail_level, 0.0, 1.0), 8.0), Color(0.26, 0.74, 0.96, 0.92))

	var wheel_y: float = sail_y + 18.0

	var wheel_c: Vector2 = Vector2(x + 24.0, wheel_y + 20.0)
	var wheel_r: float = 14.0
	var wood_dark: Color = Color(0.28, 0.18, 0.10, 0.96)
	var wood_mid: Color = Color(0.44, 0.27, 0.14, 0.95)
	var brass: Color = Color(0.80, 0.67, 0.40, 0.95)
	a.draw_circle(wheel_c, wheel_r + 2.4, Color(0.05, 0.07, 0.10, 0.9))
	a.draw_circle(wheel_c, wheel_r + 0.9, wood_dark)
	a.draw_arc(wheel_c, wheel_r, 0.0, TAU, 40, wood_mid, 3.2, true)
	a.draw_arc(wheel_c, wheel_r - 1.5, 0.0, TAU, 40, brass, 1.1, true)
	a.draw_circle(wheel_c, 3.9, wood_dark)
	a.draw_circle(wheel_c, 2.5, brass)
	var wheel_rot: float = helm.wheel_position * TAU * 2.0
	var base_ang: float = -PI * 0.5 + wheel_rot
	for i in range(8):
		var spoke_ang: float = base_ang + float(i) * TAU / 8.0
		var spoke_dir: Vector2 = Vector2(cos(spoke_ang), sin(spoke_ang))
		a.draw_line(wheel_c + spoke_dir * 3.6, wheel_c + spoke_dir * (wheel_r - 2.0), wood_mid, 1.4, true)
		a.draw_circle(wheel_c + spoke_dir * (wheel_r + 0.6), 1.35, brass)
	var top_spoke: Vector2 = Vector2(cos(base_ang), sin(base_ang))
	a.draw_line(wheel_c, wheel_c + top_spoke * (wheel_r - 1.0), Color(0.95, 0.90, 0.72, 0.98), 2.0, true)
	a.draw_circle(wheel_c + top_spoke * (wheel_r - 1.0), 1.9, Color(0.99, 0.94, 0.76, 1.0))
	a.draw_line(wheel_c + Vector2(0.0, -wheel_r - 3.0), wheel_c + Vector2(0.0, -wheel_r + 1.0), Color(1.0, 0.35, 0.25, 0.95), 2.0, true)
	var rud_max_rad: float = deg_to_rad(a._HelmController.MAX_RUDDER_DEFLECTION_DEG)
	var rud_visual_ang: float = -PI * 0.5 + helm.rudder_angle * rud_max_rad
	var rud_tip: Vector2 = wheel_c + Vector2(cos(rud_visual_ang), sin(rud_visual_ang)) * (wheel_r - 5.0)
	a.draw_line(wheel_c, rud_tip, Color(0.45, 0.95, 0.74, 0.9), 1.7, true)
	a.draw_circle(rud_tip, 1.6, Color(0.45, 0.95, 0.74, 0.95))
	var lock_text: String = "LOCK ON" if helm.wheel_locked else "LOCK OFF"
	var lock_col: Color = Color(0.96, 0.68, 0.38, 0.96) if helm.wheel_locked else Color(0.62, 0.70, 0.82, 0.9)
	a.draw_string(font, Vector2(x + 52.0, wheel_y + 16.0), "Wheel %s" % lock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lock_col)
	var rud_deg: float = helm.rudder_angle * a._HelmController.MAX_RUDDER_DEFLECTION_DEG
	var rud_side: String = "P" if rud_deg < -0.5 else ("S" if rud_deg > 0.5 else "mid")
	if helm.wheel_locked:
		a.draw_string(font, Vector2(x + 52.0, wheel_y + 30.0), "Hold · Rudder %.0f° %s" % [absf(rud_deg), rud_side], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.85, 0.72, 0.88))
	else:
		a.draw_string(font, Vector2(x + 52.0, wheel_y + 30.0), "Rudder %.0f° %s" % [absf(rud_deg), rud_side], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.62, 0.72, 0.82))


# ── Input display helpers ────────────────────────────────────────────

func _joy_button_short_name(button_idx: int) -> String:
	match button_idx:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_GUIDE:
			return "Guide"
	return "B%d" % button_idx


func _action_keys_display(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "—"
	var parts: Array[String] = []
	var seen: Dictionary = {}
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			var code: int = ke.physical_keycode
			if code == KEY_NONE:
				code = ke.keycode
			if code != KEY_NONE:
				var label: String = OS.get_keycode_string(code)
				if not seen.has(label):
					seen[label] = true
					parts.append(label)
		elif ev is InputEventJoypadButton:
			var jb := ev as InputEventJoypadButton
			var jlabel: String = _joy_button_short_name(jb.button_index)
			if not seen.has(jlabel):
				seen[jlabel] = true
				parts.append(jlabel)
	return " · ".join(parts) if parts.size() > 0 else "—"


func _slot_key_caption(action_name: String) -> String:
	return _action_keys_display(action_name).replace(" · ", "/")


# ── Keybindings panel ────────────────────────────────────────────────

func draw_keybindings_panel(vp: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var line_h: float = 13.0
	var lines: Array[String] = [
		"Bindings (keyboard · gamepad)",
		"E / LB: select PORT battery (aim + elevation + fire target)",
		"Q / RB: select STARBOARD battery",
		"F / X / RT: fire selected battery only",
		"Steer: %s / %s" % [_action_keys_display(a._ACTIONS.left), _action_keys_display(a._ACTIONS.right)],
		"Sail up · down: %s · %s" % [_action_keys_display(a.SAIL_RAISE_ACTION), _action_keys_display(a.SAIL_LOWER_ACTION)],
		"Fire mode: %s" % _action_keys_display(a.FIRE_MODE_ACTION),
		"Elevation up · down: %s · %s" % [_action_keys_display(a.ELEV_UP_ACTION), _action_keys_display(a.ELEV_DOWN_ACTION)],
		"Wheel lock toggle: %s" % _action_keys_display(a.WHEEL_LOCK_ACTION),
		"Zoom: mouse wheel or +/- buttons (top-right)",
		"Pan: arrow keys or middle-mouse drag",
		"1 / Home / Tab: lock camera to follow your ship",
	]
	if OS.is_debug_build():
		lines.append("Debug (dev build): F3 bot HUD · F4 bot world overlays")
	var panel_pad: float = 8.0
	var box_w: float = minf(vp.x - 28.0, 560.0)
	var box_h: float = panel_pad * 2.0 + float(lines.size()) * line_h
	var ability_bar_top: float = vp.y - 54.0 - 16.0
	var y_top: float = ability_bar_top - 10.0 - box_h
	var x: float = 14.0
	a.draw_rect(Rect2(x - 6.0, y_top - 2.0, box_w, box_h + 4.0), Color(0.05, 0.07, 0.11, 0.88))
	var sub: Color = Color(0.62, 0.70, 0.82, 0.95)
	var txt: Color = Color(0.88, 0.91, 0.96, 0.96)
	for i in range(lines.size()):
		var c: Color = sub if i == 0 else txt
		var sz: int = 11 if i == 0 else 11
		a.draw_string(font, Vector2(x, y_top + panel_pad + float(i + 1) * line_h - 2.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)


# ── Ability bar ──────────────────────────────────────────────────────

func draw_ability_bar(vp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var bar_w: float = 550.0
	var bar_h: float = 54.0
	var x: float = (vp.x - bar_w) * 0.5
	var y: float = vp.y - bar_h - 16.0
	a.draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.10, 0.12, 0.16, 0.82))
	a.draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.34, 0.42, 0.52, 0.9), false, 2.0)
	var p: Dictionary = a._players[a._my_index] if not a._players.is_empty() else {}
	var port_b: Variant = p.get("battery_port")
	var stbd_b2: Variant = p.get("battery_stbd")
	var sel_port_ab: bool = bool(p.get("aim_port_active", true)) if not p.is_empty() else true
	var sel_stbd_ab: bool = bool(p.get("aim_stbd_active", false)) if not p.is_empty() else false
	var active_bat: Variant = port_b if sel_port_ab else stbd_b2
	var mode_lbl: String = "Ripple"
	if port_b != null and port_b.fire_mode == _BatteryController.FireMode.SALVO:
		mode_lbl = "Barrage"
	draw_ability_slot(font, Vector2(x + 8.0, y + 12.0), _slot_key_caption(a.FIRE_MODE_ACTION), mode_lbl, true)
	var elev_lbl: String = "+0.0°"
	if active_bat != null:
		elev_lbl = active_bat.elevation_label()
	draw_ability_slot(font, Vector2(x + 138.0, y + 12.0), "R/T", elev_lbl, true)
	var helm: Variant = p.get("helm")
	var wheel_locked: bool = helm != null and bool(helm.wheel_locked)
	draw_ability_slot(font, Vector2(x + 268.0, y + 12.0), _slot_key_caption(a.WHEEL_LOCK_ACTION), "Wheel lock", wheel_locked)
	var ready_count: int = 0
	var total_count: int = 0
	if sel_port_ab and port_b != null:
		total_count += 1
		if port_b.state == _BatteryController.BatteryState.READY:
			ready_count += 1
	if sel_stbd_ab and stbd_b2 != null:
		total_count += 1
		if stbd_b2.state == _BatteryController.BatteryState.READY:
			ready_count += 1
	var side_lbl: String
	if sel_port_ab and sel_stbd_ab:
		side_lbl = "P+S"
	elif sel_port_ab:
		side_lbl = "P"
	elif sel_stbd_ab:
		side_lbl = "S"
	else:
		side_lbl = "—"
	var fire_key: String = _slot_key_caption(a._ACTIONS.atk)
	var fire_lbl: String = "FIRE %s %d/%d" % [side_lbl, ready_count, total_count]
	draw_ability_slot(font, Vector2(x + 398.0, y + 12.0), fire_key, fire_lbl, ready_count > 0)
	var cam_hint: String = ""
	if not a._camera_locked:
		cam_hint = " · FREE CAM (press 1 to snap back)"
	var hint: String = "Bindings shown in panel above · Pause Esc" + cam_hint
	a.draw_string(font, Vector2(x + 10.0, y - 4.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.82, 0.64, 0.95))


func draw_ability_slot(font: Font, pos: Vector2, key_name: String, label: String, enabled: bool) -> void:
	var col: Color = Color(0.28, 0.85, 0.56, 0.95) if enabled else Color(0.56, 0.64, 0.72, 0.95)
	a.draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), Color(0.16, 0.20, 0.24, 0.9))
	a.draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), col, false, 1.6)
	a.draw_string(font, pos + Vector2(6.0, 18.0), "[%s] %s" % [key_name, label], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


# ═══════════════════════════════════════════════════════════════════════
#  Whirlpool visuals  (req-whirlpool-arena-v1)
# ═══════════════════════════════════════════════════════════════════════

## Main whirlpool visual — always-on concentric ring rendering with flow indicators.
func draw_whirlpool_visuals() -> void:
	if a._whirlpool == null or not a.whirlpool_enabled:
		return

	var wc: Vector2 = a._whirlpool.center
	var sc: Vector2 = _w2s(wc.x, wc.y)
	var wp_scale: float = a._TD_SCALE * a._zoom

	var outer_r: float = a._whirlpool.influence_radius * wp_scale

	# Skip if completely off-screen.
	var vp: Vector2 = a.get_viewport_rect().size
	if sc.x + outer_r < 0.0 or sc.x - outer_r > vp.x or sc.y + outer_r < 0.0 or sc.y - outer_r > vp.y:
		return

	# ── Animated swirl streaks ──
	const SWIRL_PERIOD: float = 12.0
	var t: float = fmod(Time.get_ticks_msec() / 1000.0, SWIRL_PERIOD) / SWIRL_PERIOD
	var streak_count: int = 48
	for si in range(streak_count):
		var base_angle: float = (float(si) / float(streak_count)) * TAU
		var r_frac: float = 0.08 + float(si % 9) * 0.105
		var r_world: float = a._whirlpool.influence_radius * r_frac
		var r_px: float = r_world * wp_scale
		if r_px < 2.0 or r_px > outer_r:
			continue
		var speed_scale: float = 0.08 / maxf(0.01, r_frac)
		var angle: float = base_angle + t * TAU * speed_scale
		var p1: Vector2 = sc + Vector2(cos(angle), sin(angle)) * r_px
		var arc_len: float = clampf(speed_scale * 0.3, 0.06, 0.4)
		var p2: Vector2 = sc + Vector2(cos(angle + arc_len), sin(angle + arc_len)) * r_px
		var depth: float = 1.0 - r_frac
		var streak_col: Color
		if depth < 0.5:
			streak_col = Color(0.35, 0.60, 0.85, 0.06 + depth * 0.10)
		else:
			streak_col = Color(0.45, 0.55, 0.70, 0.10 + (depth - 0.5) * 0.16)
		a.draw_line(p1, p2, streak_col, 1.0 + depth * 1.5)



## Draw a ring as a polyline circle.
func draw_whirlpool_ring_arc(center_s: Vector2, radius: float, color: Color, width: float) -> void:
	if radius < 1.0:
		return
	var seg_count: int = clampi(int(radius * 0.3), 24, 128)
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(seg_count + 1)
	for i in range(seg_count + 1):
		var angle: float = (float(i) / float(seg_count)) * TAU
		points[i] = center_s + Vector2(cos(angle), sin(angle)) * radius
	a.draw_polyline(points, color, width, true)
