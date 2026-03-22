## Ballistic round shot for naval broadsides: horizontal world motion (wx, wy) plus height h and vz.
## Heavier shot (higher mass) gets lower muzzle speed for the same charge → shorter range, steeper arc.
class_name CannonBallistics
extends RefCounted

## World units / s² — tuned with muzzle speed so hang time feels like a heavy iron ball (~0.5–2 s in air).
const GRAVITY: float = 38.0
## Launch angle above horizontal in the vertical plane of the shot (broadside loft).
const ELEVATION_RAD: float = deg_to_rad(21.0)
## Baseline muzzle speed along the shot line at mass == 1.0 (world units/s). Heavier balls use lower speed.
const BASE_MUZZLE_SPEED: float = 26.0
## Height above water at muzzle (world units).
const MUZZLE_HEIGHT: float = 0.5
const MIN_MASS: float = 0.5
const MAX_MASS: float = 1.75

## How far from a ship plan position (wx, wy) a ball can score a hull hit (world units).
const SHIP_HIT_RADIUS: float = 1.35
## Pass through this height band to count as hitting the hull (not flying high overhead).
const HULL_HIT_MIN_H: float = 0.12
const HULL_HIT_MAX_H: float = 2.6

const PHYSICS_SUBSTEP: float = 1.0 / 120.0
const MAX_FLIGHT_TIME: float = 16.0

## Visual: screen Y offset per world-unit height (scaled by arena zoom in caller).
const SCREEN_HEIGHT_PX_PER_UNIT: float = 16.0


static func mass_from_damage(damage: float, ref_damage: float = 75.0) -> float:
	return clampf(damage / ref_damage, MIN_MASS, MAX_MASS)


static func horizontal_speed(vx: float, vy: float) -> float:
	return sqrt(vx * vx + vy * vy)


## Heavier mass → lower v_line (same powder, harder to accelerate); vertical share follows elevation.
static func initial_velocity(horizontal_dir: Vector2, mass: float) -> Dictionary:
	var dir: Vector2 = horizontal_dir.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var m: float = clampf(mass, MIN_MASS, MAX_MASS)
	# v_line scales ~ 1/sqrt(m): heavy ball exits slower → shorter ground range, quicker return to sea.
	var v_line: float = BASE_MUZZLE_SPEED / sqrt(m)
	var ch: float = cos(ELEVATION_RAD)
	var sh: float = sin(ELEVATION_RAD)
	return {
		"vx": dir.x * v_line * ch,
		"vy": dir.y * v_line * ch,
		"vz": v_line * sh,
	}
