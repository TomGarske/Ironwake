## Ballistic round shot for naval broadsides: horizontal world motion (wx, wy) plus height h and vz.
## Realistic 24-pounder long gun ballistics (1 world unit = 1 meter).
class_name CannonBallistics
extends RefCounted

const _NC := preload("res://scripts/shared/naval_combat_constants.gd")

## Real gravity (m/s²).
const GRAVITY: float = 9.81
## Default muzzle elevation (deg above horizontal) when no battery quoin is supplied.
const DEFAULT_ELEVATION_DEG: float = 0.0
## 24-pounder long gun muzzle velocity (~410 m/s historical).
const MUZZLE_SPEED: float = 410.0
## Height above water at muzzle (world units) — matches raised gun deck.
const MUZZLE_HEIGHT: float = _NC.CANNON_MUZZLE_HEIGHT_UNITS

## Pass through this height band to count as hitting the hull (not flying high overhead).
const HULL_HIT_MIN_H: float = _NC.SHIP_HULL_HIT_H_MIN
const HULL_HIT_MAX_H: float = _NC.SHIP_HULL_HIT_H_MAX

const PHYSICS_SUBSTEP: float = 1.0 / 120.0

## Visual: screen Y offset per world-unit height (scaled by arena zoom in caller).
const SCREEN_HEIGHT_PX_PER_UNIT: float = 16.0


## Velocity vector for a round shot at the given elevation.
## Returns vx, vy (horizontal world axes) and vz (vertical).
static func initial_velocity(horizontal_dir: Vector2, elevation_deg: float = DEFAULT_ELEVATION_DEG) -> Dictionary:
	var dir: Vector2 = horizontal_dir.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var elev_rad: float = deg_to_rad(elevation_deg)
	var ch: float = cos(elev_rad)
	var sh: float = sin(elev_rad)
	return {
		"vx": dir.x * MUZZLE_SPEED * ch,
		"vy": dir.y * MUZZLE_SPEED * ch,
		"vz": MUZZLE_SPEED * sh,
	}
