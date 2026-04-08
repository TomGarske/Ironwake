class_name IronwakeProjectiles
extends RefCounted

## Projectile simulation, ballistic helpers, and visual FX management extracted
## from the arena node.  Stateless with respect to the scene tree — all node
## access goes through the arena reference handed to `init()`.

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const _BatteryController := preload("res://scripts/shared/battery_controller.gd")
const _CannonBallistics := preload("res://scripts/shared/cannon_ballistics.gd")

# ── FX duration constants (mirror the arena's private consts) ────────────────
const SPLASH_DURATION: float = 0.42
const HULL_STRIKE_DURATION: float = 0.4
const PROJECTILE_HIT_ARM_TIME: float = 0.025
const MUZZLE_FLASH_DURATION: float = 0.15
const MUZZLE_SMOKE_DURATION: float = 2.0
const HULL_DAMAGE_PER_HIT: float = 1.0

# ── State arrays ─────────────────────────────────────────────────────────────
var projectiles: Array[Dictionary] = []
## Transient water splashes from cannonballs: { wx, wy, t }
var splash_fx: Array[Dictionary] = []
## Hull impacts: { wx, wy, h, t } — shows strike/sparks where the ball met the ship.
var hull_strike_fx: Array[Dictionary] = []
## Muzzle effects: { wx, wy, dirx, diry, t }
var muzzle_flash_fx: Array[Dictionary] = []
## Smoke effects: { wx, wy, t }
var muzzle_smoke_fx: Array[Dictionary] = []

# ── Arena back-reference ─────────────────────────────────────────────────────
var arena: Node = null


func init(arena_node: Node) -> void:
	arena = arena_node


# ── Peer lookup ──────────────────────────────────────────────────────────────

## Returns the _players index for a given peer_id, or -1 if not found.
func _find_index_by_peer(peer_id: int) -> int:
	for i in range(arena._players.size()):
		if int(arena._players[i].get("peer_id", -1)) == peer_id:
			return i
	return -1


# ── Geometry / hit detection ─────────────────────────────────────────────────

func point_hits_ship_ellipse(point: Vector2, ship: Dictionary) -> bool:
	var hull: Vector2 = Vector2(float(ship.dir.x), float(ship.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var perp: Vector2 = hull.rotated(PI * 0.5)
	var rel: Vector2 = point - Vector2(float(ship.wx), float(ship.wy))
	var fwd: float = rel.dot(hull)
	var lat: float = rel.dot(perp)
	var a: float = float(ship.get("ship_length", NC.SHIP_LENGTH_UNITS)) * 0.5
	var b: float = float(ship.get("ship_width", NC.SHIP_WIDTH_UNITS)) * 0.5
	var k: float = (fwd * fwd) / (a * a) + (lat * lat) / (b * b)
	return k <= NC.ELLIPSE_HIT_SLACK


# ── Ballistic helpers ────────────────────────────────────────────────────────

## Compute what zoom level frames the ballistic impact point on screen.
## Uses actual viewport size so it works at any resolution.
func zoom_for_battery_range(bat: _BatteryController) -> float:
	var elev_rad: float = deg_to_rad(bat.elevation_degrees())
	var vh: float = _CannonBallistics.MUZZLE_SPEED * cos(elev_rad)
	var vz: float = _CannonBallistics.MUZZLE_SPEED * sin(elev_rad)
	var h0: float = _CannonBallistics.MUZZLE_HEIGHT
	var g: float = _CannonBallistics.GRAVITY
	var disc: float = vz * vz + 2.0 * g * h0
	var t_splash: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, g)
	var range_m: float = maxf(1.0, vh * minf(t_splash, NC.PROJECTILE_LIFETIME))
	# Zoom so the impact point sits at the edge of the viewport (with margin).
	# Broadside fires perpendicular to heading, so use the shorter viewport axis
	# to guarantee the reticle is always on screen regardless of ship orientation.
	var vp: Vector2 = arena.get_viewport_rect().size
	var vp_half: float = minf(vp.x, vp.y) * 0.5
	# First pass: compute raw zoom without margin to know where we are in the range.
	var raw_z: float = clampf(vp_half / (arena._TD_SCALE * range_m), arena._ZOOM_MIN, arena._ZOOM_MAX)
	# Lerp margin: close zoom (high value) -> 2.0, far zoom (low value) -> 1.1.
	var zoom_t: float = clampf((raw_z - arena._ZOOM_MIN) / maxf(0.0001, arena._ZOOM_MAX - arena._ZOOM_MIN), 0.0, 1.0)
	var margin: float = lerpf(arena._AUTO_ZOOM_MARGIN_FAR, arena._AUTO_ZOOM_MARGIN_CLOSE, zoom_t)
	var target_z: float = vp_half / (arena._TD_SCALE * range_m * margin)
	return clampf(target_z, arena._ZOOM_MIN, arena._ZOOM_MAX)


## Binary search for the elevation (degrees) that produces the given range.
## Returns degrees in [ELEV_MIN_DEG, ELEV_MAX_DEG], clamped if range is outside reachable band.
func elevation_for_range(range_m: float) -> float:
	var lo: float = _BatteryController.ELEV_MIN_DEG
	var hi: float = _BatteryController.ELEV_MAX_DEG
	var h0: float = _CannonBallistics.MUZZLE_HEIGHT
	var g: float = _CannonBallistics.GRAVITY
	var mv: float = _CannonBallistics.MUZZLE_SPEED
	# Check reachable bounds.
	var range_at_lo: float = range_for_elev_deg(lo, mv, g, h0)
	var range_at_hi: float = range_for_elev_deg(hi, mv, g, h0)
	if range_m <= range_at_lo:
		return lo
	if range_m >= range_at_hi:
		return hi
	# Binary search — 16 iterations is plenty for float precision.
	for _i in range(16):
		var mid: float = (lo + hi) * 0.5
		if range_for_elev_deg(mid, mv, g, h0) < range_m:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func range_for_elev_deg(elev_deg: float, mv: float, g: float, h0: float) -> float:
	var elev_rad: float = deg_to_rad(elev_deg)
	var vh: float = mv * cos(elev_rad)
	var vz_val: float = mv * sin(elev_rad)
	var disc: float = vz_val * vz_val + 2.0 * g * h0
	var t: float = (vz_val + sqrt(maxf(0.0, disc))) / maxf(0.001, g)
	return vh * minf(t, NC.PROJECTILE_LIFETIME)


# ── Spread / aim helpers ─────────────────────────────────────────────────────

## Half-angle (deg) of the yaw spread cone — physical dispersion only.
## No artificial accuracy modifiers: spread comes from range (powder variance,
## crew timing) plus penalties for turning and high speed.  Whether you hit
## depends on your elevation, positioning, and heading — not a hidden score.
func spread_cone_half_deg(p: Dictionary, aim_dist: float) -> float:
	var base_deg: float = NC.spread_deg_for_range(aim_dist)
	if bool(p.get("motion_is_turning", false)):
		base_deg *= NC.TURNING_SPREAD_MULT
	if float(p.get("_naval_spd", 0.0)) >= NC.HIGH_SPEED_THRESHOLD:
		base_deg *= NC.HIGH_SPEED_SPREAD_MULT
	return base_deg


func spread_yaw_deg_for_cannon(p: Dictionary, aim_dist: float, cannon_index: int, battery: Variant = null) -> float:
	var half: float = spread_cone_half_deg(p, aim_dist)
	var is_ripple: bool = battery != null and battery.fire_mode == _BatteryController.FireMode.RIPPLE
	if is_ripple:
		# Ripple: each cannon aims at the center point. Small jitter only (crew variance).
		var jitter: float = randf_range(-0.12, 0.12)
		return half * jitter
	else:
		# Barrage (salvo): each cannon fires straight out its own gunport.
		# Symmetric spread pattern fills the full cone.
		var pattern: Array[float] = [0.0, -0.5, 0.5, -0.85, 0.85, -0.3, 0.3, -0.7, 0.7]
		var idx: int = posmod(cannon_index, pattern.size())
		var jitter: float = randf_range(-0.15, 0.15)
		return half * (pattern[idx] + jitter)


func cannon_muzzle_world(p: Dictionary, battery: _BatteryController, cannon_index: int) -> Vector2:
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
	var out_m: float = float(p.get("ship_width", NC.SHIP_WIDTH_UNITS)) * 0.5
	return Vector2(float(p.wx), float(p.wy)) + along + perp * out_m


# ── Muzzle FX ────────────────────────────────────────────────────────────────

func spawn_muzzle_fx(wx: float, wy: float, dir: Vector2) -> void:
	muzzle_flash_fx.append({"wx": wx, "wy": wy, "dirx": dir.x, "diry": dir.y, "t": 0.0})
	muzzle_smoke_fx.append({"wx": wx, "wy": wy, "t": 0.0})


# ── Projectile spawning / simulation ─────────────────────────────────────────

func fire_projectile(p: Dictionary, cannon_index: int = 0, _shot_damage: float = 1.0, aim_override: Variant = null, battery: Variant = null) -> void:
	var fire_peer: int = int(p.get("peer_id", 1))
	if arena._scoreboard.has(fire_peer):
		arena._scoreboard[fire_peer]["shots_fired"] += 1
	var dir: Vector2
	if aim_override is Vector2 and aim_override.length_squared() > 0.001:
		dir = aim_override.normalized()
	else:
		dir = p.get("aim_dir", p.dir)
		if dir.length_squared() <= 0.001:
			dir = Vector2(p.dir.x, p.dir.y)
		if dir.length_squared() <= 0.001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
	var owner_peer: int = int(p.get("peer_id", 1))
	if owner_peer <= 0 and arena.multiplayer.has_multiplayer_peer():
		owner_peer = arena.multiplayer.get_unique_id()
	var aim_dist: float = float(p.get("_naval_acc_dist", 200.0))
	if aim_dist < 0.0 or aim_dist > 1e9:
		aim_dist = 200.0
	var spread_deg: float = spread_yaw_deg_for_cannon(p, aim_dist, cannon_index, battery)
	var shot_dir: Vector2 = dir.rotated(deg_to_rad(spread_deg)).normalized()
	var start_x: float
	var start_y: float
	if battery != null:
		var bat: _BatteryController = battery as _BatteryController
		var mw: Vector2 = cannon_muzzle_world(p, bat, cannon_index)
		start_x = mw.x
		start_y = mw.y
	else:
		var muzzle: float = 6.5
		start_x = float(p.wx) + shot_dir.x * muzzle
		start_y = float(p.wy) + shot_dir.y * muzzle
	spawn_muzzle_fx(start_x, start_y, shot_dir)
	# Cannon discharge SFX — close boom for local player, distant for others.
	var local_peer: int = int(arena._players[arena._my_index].get("peer_id", -1))
	if fire_peer == local_peer:
		arena._play_cannon_fire_sound()
	else:
		arena._play_cannon_fire_distant()
	var elev_deg: float = _CannonBallistics.DEFAULT_ELEVATION_DEG
	if battery != null:
		elev_deg = battery.elevation_degrees()
	var vel: Dictionary = _CannonBallistics.initial_velocity(shot_dir, elev_deg)
	var vx: float = float(vel.vx)
	var vy: float = float(vel.vy)
	var vz: float = float(vel.vz)
	var hull_dmg: float = HULL_DAMAGE_PER_HIT
	if arena.multiplayer.has_multiplayer_peer():
		arena._spawn_cannonball_rpc.rpc(
			start_x, start_y, vx, vy, vz,
			_CannonBallistics.MUZZLE_HEIGHT, owner_peer, hull_dmg
		)
	else:
		spawn_cannonball_local(
			start_x, start_y, vx, vy, vz,
			_CannonBallistics.MUZZLE_HEIGHT, owner_peer, hull_dmg
		)


func spawn_cannonball_local(
		wx: float, wy: float,
		vx: float, vy: float, vz: float,
		h: float, owner_peer: int, damage: float
	) -> void:
	projectiles.append({
		"wx": wx, "wy": wy, "h": h,
		"vx": vx, "vy": vy, "vz": vz,
		"t_flight": 0.0,
		"owner_peer": owner_peer,
		"damage": damage,
		"arm_t": PROJECTILE_HIT_ARM_TIME,
		"alive": true,
	})


func tick_projectiles(delta: float) -> void:
	if projectiles.is_empty():
		return
	var can_apply_hits: bool = not arena.multiplayer.has_multiplayer_peer() or arena.multiplayer.is_server()
	var grav: float = _CannonBallistics.GRAVITY
	var sub: float = _CannonBallistics.PHYSICS_SUBSTEP
	var h_min: float = _CannonBallistics.HULL_HIT_MIN_H
	var h_max: float = _CannonBallistics.HULL_HIT_MAX_H
	var t_max: float = NC.PROJECTILE_LIFETIME

	for i in range(projectiles.size() - 1, -1, -1):
		var proj: Dictionary = projectiles[i]
		if not bool(proj.get("alive", true)):
			projectiles.remove_at(i)
			continue

		var wx: float = float(proj.get("wx", 0.0))
		var wy: float = float(proj.get("wy", 0.0))
		var h: float = float(proj.get("h", 0.0))
		var vx: float = float(proj.get("vx", 0.0))
		var vy: float = float(proj.get("vy", 0.0))
		var vz: float = float(proj.get("vz", 0.0))
		var t_flight: float = float(proj.get("t_flight", 0.0))
		var owner_peer: int = int(proj.get("owner_peer", 0))
		var dmg: float = float(proj.get("damage", HULL_DAMAGE_PER_HIT))
		var arm_t: float = float(proj.get("arm_t", 0.0))

		var time_left: float = delta
		var remove_proj: bool = false

		while time_left > 0.0001 and not remove_proj:
			var dt: float = minf(sub, time_left)
			wx += vx * dt
			wy += vy * dt
			h += vz * dt
			vz -= grav * dt
			t_flight += dt
			time_left -= dt
			arm_t = maxf(0.0, arm_t - dt)

			if t_flight >= t_max:
				remove_proj = true
				break

			if h <= 0.0:
				spawn_splash_at_world(wx, wy)
				remove_proj = true
				break

			if arm_t > 0.0:
				continue
			for j in range(arena._players.size()):
				var q: Dictionary = arena._players[j]
				if not bool(q.get("alive", true)):
					continue
				if int(q.get("peer_id", -1)) == owner_peer:
					continue
				# Fleet-aware friendly-fire prevention: skip allies.
				if arena._fleet_registry != null and arena._fleet_registry.has_fleets():
					var owner_idx: int = _find_index_by_peer(owner_peer)
					if owner_idx >= 0 and arena._fleet_registry.are_allies(owner_idx, j):
						continue
				if not point_hits_ship_ellipse(Vector2(wx, wy), q):
					continue
				if h < h_min or h > h_max:
					continue
				spawn_hull_strike_fx(wx, wy, h)
				if can_apply_hits:
					var def_peer: int = int(q.get("peer_id", -1))
					if arena.multiplayer.has_multiplayer_peer():
						arena._apply_cannon_hit.rpc(owner_peer, def_peer, dmg, h)
					else:
						arena._apply_cannon_hit_impl(owner_peer, def_peer, dmg, h)
				remove_proj = true
				break

			if remove_proj:
				break

		if remove_proj:
			projectiles.remove_at(i)
		else:
			proj["wx"] = wx
			proj["wy"] = wy
			proj["h"] = h
			proj["vx"] = vx
			proj["vy"] = vy
			proj["vz"] = vz
			proj["t_flight"] = t_flight
			proj["arm_t"] = arm_t
			projectiles[i] = proj


# ── FX spawning ──────────────────────────────────────────────────────────────

func spawn_splash_at_world(wx: float, wy: float) -> void:
	splash_fx.append({"wx": wx, "wy": wy, "t": 0.0})


func spawn_hull_strike_fx(wx: float, wy: float, impact_h: float) -> void:
	hull_strike_fx.append({"wx": wx, "wy": wy, "h": impact_h, "t": 0.0})


# ── FX tick helpers ──────────────────────────────────────────────────────────

func tick_hull_strike_fx(delta: float) -> void:
	if hull_strike_fx.is_empty():
		return
	for i in range(hull_strike_fx.size() - 1, -1, -1):
		var s: Dictionary = hull_strike_fx[i]
		var nt: float = float(s.get("t", 0.0)) + delta
		if nt >= HULL_STRIKE_DURATION:
			hull_strike_fx.remove_at(i)
		else:
			s["t"] = nt
			hull_strike_fx[i] = s


func tick_muzzle_fx(delta: float) -> void:
	for i in range(muzzle_flash_fx.size() - 1, -1, -1):
		var f: Dictionary = muzzle_flash_fx[i]
		var nt: float = float(f.get("t", 0.0)) + delta
		if nt >= MUZZLE_FLASH_DURATION:
			muzzle_flash_fx.remove_at(i)
		else:
			f["t"] = nt
			muzzle_flash_fx[i] = f
	for i in range(muzzle_smoke_fx.size() - 1, -1, -1):
		var s: Dictionary = muzzle_smoke_fx[i]
		var nt: float = float(s.get("t", 0.0)) + delta
		if nt >= MUZZLE_SMOKE_DURATION:
			muzzle_smoke_fx.remove_at(i)
		else:
			s["t"] = nt
			muzzle_smoke_fx[i] = s


func tick_splash_fx(delta: float) -> void:
	if splash_fx.is_empty():
		return
	for i in range(splash_fx.size() - 1, -1, -1):
		var s: Dictionary = splash_fx[i]
		var nt: float = float(s.get("t", 0.0)) + delta
		if nt >= SPLASH_DURATION:
			splash_fx.remove_at(i)
		else:
			s["t"] = nt
			splash_fx[i] = s
