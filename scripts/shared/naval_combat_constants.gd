## Tunables for req-naval-combat-prototype-v1 (Ironwake naval mode).
## World coordinates use UNITS_PER_LOGIC_TILE world units per terrain grid cell.
## 1 world unit = 1 meter.
extends Object

const UNITS_PER_LOGIC_TILE: float = 10.0

const MAP_TILES_WIDE: int = 400
const MAP_TILES_HIGH: int = 400

## Movement tuning (higher top-end speed with same accel/decel feel).
## Residual speed when sails furled: zero — ship comes to a full stop once momentum decays.
const SAILS_DOWN_DRIFT_SPEED: float = 0.0
const MIN_SPEED_DRIFT: float = 3.8
const QUARTER_SPEED: float = 17.1
const CRUISE_SPEED: float = 30.5
const MAX_SPEED: float = 52.4

## Time (s) to accelerate 0 → MAX_SPEED under sail thrust.
const ACCEL_TIME_ZERO_TO_MAX: float = 10.0
## Decel is slower — heavy hull carries momentum (thousands of tons of inertia).
const DECEL_TIME_SAILS_DOWN: float = 40.0

## Derived linear accel (u/s²)
static func accel_rate() -> float:
	return MAX_SPEED / maxf(0.001, ACCEL_TIME_ZERO_TO_MAX)


static func decel_rate_sails() -> float:
	return MAX_SPEED / maxf(0.001, DECEL_TIME_SAILS_DOWN)


## Turning — rate depends on water flow over the rudder (speed).
## Near-zero speed: almost no turn (no hydrodynamic force on rudder).
## Ramps up quickly, then stays high — more water over the rudder means
## more steering force. The turning CIRCLE widens at speed naturally
## because radius = speed / angular_velocity, no artificial nerf needed.
static func turn_rate_deg_for_speed(speed: float) -> float:
	var s: float = clampf(speed, 0.0, MAX_SPEED * 1.1)
	# Near-standstill: barely any rudder authority — ship is a floating log.
	if s <= MIN_SPEED_DRIFT:
		var t: float = s / maxf(0.001, MIN_SPEED_DRIFT)
		return lerpf(2.5, 10.0, t)
	# Low speed → ramp up as water hits the rudder.
	if s <= QUARTER_SPEED:
		var t: float = (s - MIN_SPEED_DRIFT) / maxf(0.001, QUARTER_SPEED - MIN_SPEED_DRIFT)
		return lerpf(10.0, 18.0, t)
	# Quarter → max: stays near peak.
	if s <= CRUISE_SPEED:
		var t: float = (s - QUARTER_SPEED) / maxf(0.001, CRUISE_SPEED - QUARTER_SPEED)
		return lerpf(18.0, 16.0, t)
	# High speed: mild dropoff — hull inertia resists slightly.
	var t2: float = (s - CRUISE_SPEED) / maxf(0.001, MAX_SPEED - CRUISE_SPEED)
	return lerpf(16.0, 14.0, clampf(t2, 0.0, 1.0))


## Rudder / heading inertia (lower = heading catches rudder faster).
## 1,600-ton hull has rotational inertia — tuned for responsive gameplay feel.
const HELM_TURN_LAG_SEC: float = 0.01

## Speed at which rudder reaches full steering authority (linear ramp MIN→1).
## Need ~3 knots (≈8 u/s) of way on before rudder bites fully.
const RUDDER_AUTHORITY_SPEED: float = 8.0
## Minimum rudder authority at zero speed (warping/kedging — some authority at anchor).
const RUDDER_AUTHORITY_MIN: float = 0.15

## Maximum physical rudder deflection (degrees). Shared with HelmController for display.
## Used in physics: the deflection angle determines hydrodynamic turning force.
const MAX_RUDDER_DEFLECTION_DEG: float = 45.0

## Rudder effectiveness: converts normalized rudder (-1..+1) to hydrodynamic force scalar.
## Real rudder lift follows ~sin(2*angle): peaks at 45°, drops off beyond.
## A 90° rudder at full lock stalls and is less effective than 45°.
static func rudder_effectiveness(rudder: float) -> float:
	var angle_deg: float = absf(rudder) * MAX_RUDDER_DEFLECTION_DEG
	var angle_rad: float = deg_to_rad(angle_deg)
	# sin(2*a) peaks at 45°, falls to 0 at 0° and 90°.
	var eff: float = sin(2.0 * angle_rad)
	return eff * signf(rudder)

## Unified turning computation. All ship heading rotation goes through this.
## rudder: normalized -1..+1 (caller applies deadzone if needed).
## turn_scalar: whirlpool penalty or similar; defaults to 1.0.
## Returns the new angular velocity (rad/s).
static func compute_angular_velocity(
	rudder: float, speed: float, angular_velocity: float,
	delta: float, turn_scalar: float = 1.0
) -> float:
	var max_turn_rad: float = deg_to_rad(turn_rate_deg_for_speed(speed))
	var steer_auth: float = maxf(RUDDER_AUTHORITY_MIN, clampf(speed / RUDDER_AUTHORITY_SPEED, 0.0, 1.0)) * turn_scalar
	var eff_rudder: float = rudder_effectiveness(rudder)
	var target_av: float = max_turn_rad * eff_rudder * steer_auth
	return lerpf(angular_velocity, target_av, 1.0 - exp(-delta / maxf(0.001, HELM_TURN_LAG_SEC)))


## §4 Firing — half-angle from broadside normal (total arc per side ≈ 90°).
## Cannons can only traverse ±6° at the gunport; the arc represents the combined
## coverage of all guns along the hull.  Peak accuracy at 90° (beam), degraded
## toward the 45° and 135° edges where only extreme guns bear.
const BROADSIDE_HALF_ARC_DEG: float = 45.0
const BROADSIDE_QUALITY_PEAK_DEG: float = 90.0
const BROADSIDE_QUALITY_FALLOFF_START_DEG: float = 25.0
const BROADSIDE_QUALITY_FALLOFF_END_DEG: float = 45.0
const CANNON_FINE_AIM_DEG: float = 6.0

## Broadside quality: 1.0 at beam (90° from bow), dropping to 0.3 at arc edges.
## angle_from_bow: absolute angle between ship forward and target direction.
static func broadside_quality(angle_from_bow_deg: float) -> float:
	var off_beam: float = absf(angle_from_bow_deg - BROADSIDE_QUALITY_PEAK_DEG)
	if off_beam <= BROADSIDE_QUALITY_FALLOFF_START_DEG:
		return 1.0
	if off_beam >= BROADSIDE_QUALITY_FALLOFF_END_DEG:
		return 0.3
	var t: float = (off_beam - BROADSIDE_QUALITY_FALLOFF_START_DEG) / (BROADSIDE_QUALITY_FALLOFF_END_DEG - BROADSIDE_QUALITY_FALLOFF_START_DEG)
	return lerpf(1.0, 0.3, t)

const RELOAD_TIME_SEC: float = 8.4

## §4.1 Max engagement (same unit space as wx, wy)
## Calibrated to 24-pounder long gun ballistics (410 m/s muzzle velocity, 9.81 g).
## Flat shot (0° elev) ≈ 307 m; +1° ≈ 726 m; +2° ≈ 1269 m; +3° ≈ 1846 m.
const OPTIMAL_RANGE: float = 400.0
const MAX_CANNON_RANGE: float = 2000.0
const CLOSE_RANGE: float = 120.0

## Max flight time before projectile is removed.
## Must exceed flight time at max elevation (+10° ≈ 14.6 s) to avoid clipping arcs.
const PROJECTILE_LIFETIME: float = 16.0

## Range band labels for HUD display.  No artificial hit probability —
## accuracy is purely physical (elevation, positioning, slight yaw variance).
## Bands calibrated to real ballistic reach at practical elevations.
const ACC_PISTOL_RANGE: float = 100.0     ## depression angles — point blank
const ACC_CLOSE_RANGE: float = 300.0      ## near-flat, very reliable
const ACC_MUSKET_RANGE: float = 600.0     ## flat to +1°, good accuracy
const ACC_MEDIUM_RANGE: float = 1000.0    ## +1° to +2°, moderate accuracy
const ACC_LONG_RANGE: float = 1800.0      ## +2° to +3°, marginal accuracy

## Base half-spread (degrees) — historical age-of-sail dispersion.
## Gunport tolerances, powder variance, and crew timing.
## Grows with range as crew estimation and environmental factors compound.
static func spread_deg_for_range(distance: float) -> float:
	var d: float = maxf(0.0, distance)
	if d < 100.0:
		return lerpf(0.4, 0.8, clampf(d / 100.0, 0.0, 1.0))
	if d < 300.0:
		return lerpf(0.8, 1.5, (d - 100.0) / 200.0)
	if d < 600.0:
		return lerpf(1.5, 2.5, (d - 300.0) / 300.0)
	if d < 1000.0:
		return lerpf(2.5, 3.5, (d - 600.0) / 400.0)
	if d < 1800.0:
		return lerpf(3.5, 5.0, (d - 1000.0) / 800.0)
	var t_far: float = clampf((d - 1800.0) / 700.0, 0.0, 1.0)
	return lerpf(5.0, 7.0, t_far)

const TURNING_SPREAD_MULT: float = 1.3
const HIGH_SPEED_SPREAD_MULT: float = 1.15
const HIGH_SPEED_THRESHOLD: float = 24.0


## Ship footprint for collision / hits (world units ≈ metres).
## Based on a 74-gun 3rd rate (e.g. HMS Bellona): 168 ft × 47 ft ≈ 52 m × 14.5 m.
const SHIP_LENGTH_UNITS: float = 52.0
const SHIP_WIDTH_UNITS: float = 14.5
## Lower gun deck port sill above the waterline (~5 ft 6 in on a 74).
const SHIP_DECK_HEIGHT_UNITS: float = 1.7
## Muzzle height above water — lower gun deck 24-pounders (~6–7 ft).
const CANNON_MUZZLE_HEIGHT_UNITS: float = 2.0
## Altitude band (above water) for counting cannon hits on the hull silhouette.
## Min ≈ waterline; max ≈ top of upper works / bulwarks (~20 ft).
const SHIP_HULL_HIT_H_MIN: float = 0.06
const SHIP_HULL_HIT_H_MAX: float = 6.0
## Ellipse hit test tolerance: k <= this value counts as a hull hit (1.0 = exact ellipse).
const ELLIPSE_HIT_SLACK: float = 1.15


## Camera: zoom baseline so ~20–40 tiles visible (tune with iso TILE_W)
const NAVAL_DEFAULT_ZOOM: float = 0.12
