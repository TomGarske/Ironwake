## Combat evaluator: broadside quality scoring, engagement band logic, geometry helpers.
## Stateless — all methods are static or take explicit arguments.  (req-combat-loop-v1)
class_name NavalCombatEvaluator
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

# ── Engagement-band enum ───────────────────────────────────────────────
enum RangeBand { TOO_CLOSE, PREFERRED, TOO_FAR, BEYOND_MAX }

# ── Tunable band boundaries (calibrated to 24-pdr ballistic ranges) ───
## Below this → breakaway.  Matches NC.CLOSE_RANGE.
const BAND_TOO_CLOSE: float        = 120.0
## Centre of preferred band.  Matches NC.OPTIMAL_RANGE.
const BAND_PREFERRED_CENTER: float  = 400.0
## Half-width of preferred band.
const BAND_PREFERRED_TOLERANCE: float = 120.0
## Beyond this, shots are impractical for bots.
const BAND_MAX_PRACTICAL: float     = 1000.0
## Hysteresis buffer at each boundary to prevent oscillation.
const BAND_HYSTERESIS: float        = 15.0

# ── Firing thresholds ─────────────────────────────────────────────────
const FIRE_THRESHOLD: float         = 0.75
const FIRE_SOFT_THRESHOLD: float    = 0.60
const FIRE_REACTION_DELAY_MIN: float = 0.25
const FIRE_REACTION_DELAY_MAX: float = 0.60
const FIRE_STABILITY_TIME: float    = 0.50

# ── Anti-jitter ───────────────────────────────────────────────────────
const TURN_COMMIT_DURATION: float     = 2.0
const SIDE_SWITCH_COOLDOWN: float     = 1.5
const MANEUVER_TRANSITION_LOCK: float = 0.75
const REPOSITION_DURATION_MIN: float  = 3.5
const REPOSITION_DURATION_MAX: float  = 5.0
const POST_FIRE_LOCKOUT: float        = 0.50

# ── Stuck recovery ────────────────────────────────────────────────────
const STUCK_DETECTION_TIME: float          = 2.5
const STUCK_PROGRESS_DISTANCE_EPSILON: float = 5.0


# ═══════════════════════════════════════════════════════════════════════
#  Geometry helpers
# ═══════════════════════════════════════════════════════════════════════

## Signed bearing (degrees) from ship heading to target.
## Positive → starboard, negative → port.
static func bearing_to_target(ship_pos: Vector2, ship_dir: Vector2, target_pos: Vector2) -> float:
	var to_tgt: Vector2 = (target_pos - ship_pos)
	if to_tgt.length_squared() < 0.0001:
		return 0.0
	to_tgt = to_tgt.normalized()
	var d: Vector2 = ship_dir.normalized()
	var cross_val: float = d.cross(to_tgt)
	var dot_val: float = d.dot(to_tgt)
	return rad_to_deg(atan2(cross_val, dot_val))


## Absolute angle (degrees, 0–180) between heading and direction to target.
static func angle_from_bow(ship_dir: Vector2, to_target: Vector2) -> float:
	var d: Vector2 = ship_dir.normalized()
	var t: Vector2 = to_target.normalized()
	return rad_to_deg(acos(clampf(d.dot(t), -1.0, 1.0)))


## Which side of the ship is the target on?
static func target_side(ship_pos: Vector2, ship_dir: Vector2, target_pos: Vector2) -> String:
	var bearing: float = bearing_to_target(ship_pos, ship_dir, target_pos)
	if bearing >= 0.0:
		return "starboard"
	return "port"


## Relative velocity in world space (attacker minus target).
static func relative_velocity(ship_vel: Vector2, target_vel: Vector2) -> Vector2:
	return ship_vel - target_vel


## Closing speed — positive when ships are getting closer along the line of sight.
static func closing_speed(ship_pos: Vector2, ship_vel: Vector2, target_pos: Vector2, target_vel: Vector2) -> float:
	var sep: Vector2 = target_pos - ship_pos
	var dist: float = sep.length()
	if dist < 0.001:
		return 0.0
	var sep_n: Vector2 = sep / dist
	var rel_vel: Vector2 = relative_velocity(ship_vel, target_vel)
	return rel_vel.dot(sep_n)


# ═══════════════════════════════════════════════════════════════════════
#  Engagement band evaluation
# ═══════════════════════════════════════════════════════════════════════

## Evaluate which range band the target falls in.
## prev_band is used for hysteresis; pass -1 or omit to ignore.
static func evaluate_range_band(distance: float, prev_band: int = -1) -> Dictionary:
	var band: int = RangeBand.PREFERRED
	var hyst: float = BAND_HYSTERESIS if prev_band >= 0 else 0.0

	var close_threshold: float = BAND_TOO_CLOSE
	var pref_hi: float = BAND_PREFERRED_CENTER + BAND_PREFERRED_TOLERANCE
	var max_threshold: float = BAND_MAX_PRACTICAL

	# Apply hysteresis — make it harder to leave the current band.
	if prev_band == RangeBand.TOO_CLOSE:
		close_threshold += hyst
	elif prev_band == RangeBand.PREFERRED:
		pref_hi += hyst
	elif prev_band == RangeBand.TOO_FAR:
		pref_hi -= hyst
		max_threshold += hyst
	elif prev_band == RangeBand.BEYOND_MAX:
		max_threshold -= hyst

	if distance < close_threshold:
		band = RangeBand.TOO_CLOSE
	elif distance <= pref_hi:
		# 120–180 is a transition zone: scored lower by _compute_range_score but
		# still classified PREFERRED so bots don't oscillate at the boundary.
		band = RangeBand.PREFERRED
	elif distance <= max_threshold:
		band = RangeBand.TOO_FAR
	else:
		band = RangeBand.BEYOND_MAX

	var range_score: float = _compute_range_score(distance)
	return {"band": band, "range_score": range_score}


static func _compute_range_score(distance: float) -> float:
	# Peak at BAND_PREFERRED_CENTER, falloff toward edges.
	if distance <= 0.0:
		return 0.0
	var opt: float = BAND_PREFERRED_CENTER
	if distance < BAND_TOO_CLOSE * 0.5:
		return 0.15
	if distance < BAND_TOO_CLOSE:
		return lerpf(0.15, 0.45, (distance - BAND_TOO_CLOSE * 0.5) / (BAND_TOO_CLOSE * 0.5))
	if distance <= opt:
		return lerpf(0.45, 1.0, (distance - BAND_TOO_CLOSE) / maxf(1.0, opt - BAND_TOO_CLOSE))
	if distance <= BAND_PREFERRED_CENTER + BAND_PREFERRED_TOLERANCE:
		var over: float = distance - opt
		return lerpf(1.0, 0.65, over / maxf(1.0, BAND_PREFERRED_TOLERANCE))
	if distance <= BAND_MAX_PRACTICAL:
		var over: float = distance - (opt + BAND_PREFERRED_TOLERANCE)
		var span: float = BAND_MAX_PRACTICAL - (opt + BAND_PREFERRED_TOLERANCE)
		return lerpf(0.65, 0.1, clampf(over / maxf(1.0, span), 0.0, 1.0))
	return 0.05


static func band_name(band: int) -> String:
	match band:
		RangeBand.TOO_CLOSE:
			return "Too Close"
		RangeBand.PREFERRED:
			return "Preferred"
		RangeBand.TOO_FAR:
			return "Too Far"
		RangeBand.BEYOND_MAX:
			return "Beyond Max"
	return "?"


# ═══════════════════════════════════════════════════════════════════════
#  Broadside quality scoring
# ═══════════════════════════════════════════════════════════════════════

## Full broadside quality evaluation — returns scores for both sides + best pick.
##
## ship_pos, ship_dir: attacker position / heading
## target_pos: defender position
## angular_velocity: current rad/sec of attacker
## current_speed: attacker speed in world units/sec
## port_battery, stbd_battery: BatteryController instances (may be null)
static func evaluate_broadside(
		ship_pos: Vector2,
		ship_dir: Vector2,
		target_pos: Vector2,
		angular_velocity: float,
		current_speed: float,
		port_battery: Variant,   # BatteryController or null
		stbd_battery: Variant    # BatteryController or null
	) -> Dictionary:

	var to_target: Vector2 = target_pos - ship_pos
	var dist: float = to_target.length()
	if dist < 0.01:
		return _empty_broadside_result("no_distance")

	var to_tgt_n: Vector2 = to_target / dist
	var dir_n: Vector2 = ship_dir.normalized()
	var bow_angle: float = angle_from_bow(dir_n, to_tgt_n)

	# ── Sub-scores ────────────────────────────────────────────────
	var beam_score: float = NC.broadside_quality(bow_angle)
	var range_info: Dictionary = evaluate_range_band(dist)
	var range_score: float = float(range_info.get("range_score", 0.0))
	var stability: float = _stability_score(angular_velocity, current_speed)

	# ── Per-side scores ───────────────────────────────────────────
	var side_str: String = target_side(ship_pos, dir_n, target_pos)

	var port_q: float = _side_quality(beam_score, range_score, stability, dir_n, to_tgt_n, dist, port_battery, true)
	var stbd_q: float = _side_quality(beam_score, range_score, stability, dir_n, to_tgt_n, dist, stbd_battery, false)

	var best_q: float = maxf(port_q, stbd_q)
	var best_side: String = "none"
	if best_q > 0.01:
		best_side = "port" if port_q >= stbd_q else "starboard"

	var reasons: Array = []
	if beam_score < 0.4:
		reasons.append("poor_beam_alignment")
	if range_score < 0.3:
		reasons.append("bad_range")
	if stability < 0.5:
		reasons.append("turning_too_hard")
	if port_battery != null and _battery_loaded(port_battery) == 0.0 and stbd_battery != null and _battery_loaded(stbd_battery) == 0.0:
		reasons.append("all_reloading")
	if side_str == "port" and port_battery != null and not _arc_valid(dir_n, to_tgt_n, port_battery, true):
		reasons.append("port_outside_arc")
	if side_str == "starboard" and stbd_battery != null and not _arc_valid(dir_n, to_tgt_n, stbd_battery, false):
		reasons.append("stbd_outside_arc")

	return {
		"quality_port": port_q,
		"quality_stbd": stbd_q,
		"best_quality": best_q,
		"best_side": best_side,
		"beam_alignment": beam_score,
		"range_score": range_score,
		"stability": stability,
		"distance": dist,
		"bearing_deg": bearing_to_target(ship_pos, dir_n, target_pos),
		"bow_angle_deg": bow_angle,
		"target_side": side_str,
		"range_band": int(range_info.get("band", RangeBand.TOO_FAR)),
		"block_reasons": reasons,
	}


# ── Internal helpers ──────────────────────────────────────────────────

static func _side_quality(
		beam: float,
		range_s: float,
		stability: float,
		dir_n: Vector2,
		to_tgt_n: Vector2,
		_dist: float,
		battery: Variant,
		is_port: bool,
	) -> float:
	if battery == null:
		return 0.0
	var loaded: float = _battery_loaded(battery)
	var arc_ok: float = 1.0 if _arc_valid(dir_n, to_tgt_n, battery, is_port) else 0.0

	# Weighted combination — beam alignment is dominant.
	var raw: float = beam * 0.40 + range_s * 0.25 + stability * 0.20 + 0.15

	# Hard gates.
	raw *= loaded
	raw *= arc_ok
	return clampf(raw, 0.0, 1.0)


static func _stability_score(angular_velocity: float, current_speed: float) -> float:
	var av: float = absf(angular_velocity)
	var turn_penalty: float
	if av < 0.02:
		turn_penalty = 1.0
	elif av > 0.15:
		turn_penalty = 0.3
	else:
		turn_penalty = lerpf(1.0, 0.3, (av - 0.02) / 0.13)
	# Mild speed penalty at very high speed.
	var speed_factor: float = 1.0
	if current_speed > NC.MAX_SPEED * 0.85:
		speed_factor = lerpf(1.0, 0.8, clampf((current_speed - NC.MAX_SPEED * 0.85) / (NC.MAX_SPEED * 0.15), 0.0, 1.0))
	return turn_penalty * speed_factor


static func _battery_loaded(battery: Variant) -> float:
	if battery == null:
		return 0.0
	if battery.state == battery.BatteryState.READY:
		return 1.0
	return 0.0


static func _arc_valid(dir_n: Vector2, to_tgt_n: Vector2, battery: Variant, is_port: bool) -> bool:
	if battery == null:
		return false
	var perp: Vector2
	if is_port:
		perp = dir_n.rotated(PI * 0.5).normalized()
	else:
		perp = dir_n.rotated(-PI * 0.5).normalized()
	# Check target is on the correct side.
	if to_tgt_n.dot(perp) < 0.08:
		return false
	# Check within firing arc.
	var ang: float = acos(clampf(perp.dot(to_tgt_n), -1.0, 1.0))
	return ang <= deg_to_rad(float(battery.firing_arc_degrees))


static func _empty_broadside_result(reason: String) -> Dictionary:
	return {
		"quality_port": 0.0,
		"quality_stbd": 0.0,
		"best_quality": 0.0,
		"best_side": "none",
		"beam_alignment": 0.0,
		"range_score": 0.0,
		"stability": 0.0,
		"distance": 0.0,
		"bearing_deg": 0.0,
		"bow_angle_deg": 0.0,
		"target_side": "none",
		"range_band": int(RangeBand.BEYOND_MAX),
		"block_reasons": [reason],
	}
