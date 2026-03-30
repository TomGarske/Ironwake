## Ballistic round shot for naval broadsides: horizontal world motion (wx, wy) plus height h and vz.
## Heavier shot (higher mass) gets lower muzzle speed for the same charge → shorter range, steeper arc.
class_name CannonBallistics
extends RefCounted

const _NC := preload("res://scripts/shared/naval_combat_constants.gd")

## World units / s² — tuned with muzzle speed so hang time feels like a heavy iron ball (~0.5–2 s in air).
const GRAVITY: float = 38.0
## Default muzzle elevation (deg above horizontal) when no battery quoin is supplied.
const DEFAULT_ELEVATION_DEG: float = 0.0
## Baseline muzzle speed along the shot line at mass == 1.0 (world units/s). Heavier balls use lower speed.
const BASE_MUZZLE_SPEED: float = 26.0
## Height above water at muzzle (world units) — matches raised gun deck (see NC.CANNON_MUZZLE_HEIGHT_UNITS).
const MUZZLE_HEIGHT: float = _NC.CANNON_MUZZLE_HEIGHT_UNITS
const MIN_MASS: float = 0.5
const MAX_MASS: float = 1.75

## How far from a ship plan position (wx, wy) a ball can score a hull hit (world units).
const SHIP_HIT_RADIUS: float = 1.35
## Pass through this height band to count as hitting the hull (not flying high overhead).
const HULL_HIT_MIN_H: float = _NC.SHIP_HULL_HIT_H_MIN
const HULL_HIT_MAX_H: float = _NC.SHIP_HULL_HIT_H_MAX

const PHYSICS_SUBSTEP: float = 1.0 / 120.0
const MAX_FLIGHT_TIME: float = 16.0

## Visual: screen Y offset per world-unit height (scaled by arena zoom in caller).
const SCREEN_HEIGHT_PX_PER_UNIT: float = 16.0


static func mass_from_damage(damage: float, ref_damage: float = 75.0) -> float:
	return clampf(damage / ref_damage, MIN_MASS, MAX_MASS)


static func horizontal_speed(vx: float, vy: float) -> float:
	return sqrt(vx * vx + vy * vy)


## Heavier mass → lower v_line (same powder, harder to accelerate).
## elevation_deg: barrel elevation in degrees above horizontal (e.g. battery quoin −5° … +10°).
static func initial_velocity(horizontal_dir: Vector2, mass: float, line_speed_scale: float = 1.0, elevation_deg: float = DEFAULT_ELEVATION_DEG) -> Dictionary:
	var dir: Vector2 = horizontal_dir.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var m: float = clampf(mass, MIN_MASS, MAX_MASS)
	var v_line: float = BASE_MUZZLE_SPEED * line_speed_scale / sqrt(m)
	var elev_rad: float = deg_to_rad(elevation_deg)
	var ch: float = cos(elev_rad)
	var sh: float = sin(elev_rad)
	return {
		"vx": dir.x * v_line * ch,
		"vy": dir.y * v_line * ch,
		"vz": v_line * sh,
	}
