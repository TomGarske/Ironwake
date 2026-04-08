## Mechanical helm model: wheel spools rope onto a drum → tiller → rudder.
## A/D input spins the wheel (angular velocity); wheel has inertia.
## Rudder follows wheel position with lag; max deflection set by MAX_RUDDER_DEFLECTION_DEG.
## No auto-recenter — counter-steer to straighten out.
## Call process_steer() each frame with left/right strengths in [0,1].
class_name HelmController
extends RefCounted

## Normalized rudder ±1.0 represents this many degrees port/stbd from center.
const MAX_RUDDER_DEFLECTION_DEG: float = 45.0

enum HelmState {
	CENTER,
	LEFT,
	RIGHT,
	TURNING_LEFT,
	TURNING_RIGHT,
	RECENTERING,
}

## Wheel position: normalized -1.0 (hard port) to +1.0 (hard starboard).
## ±1.0 represents ~2 full turns from center (the mechanical stop).
var wheel_position: float = 0.0
## Wheel angular velocity (normalized units/sec). Persists across frames (inertia).
var wheel_velocity: float = 0.0
## Rudder angle: normalized -1.0 to +1.0 (±MAX_RUDDER_DEFLECTION_DEG physical deflection).
var rudder_angle: float = 0.0

var wheel_locked: bool = false
var wheel_lock_position: float = 0.0

## How fast input accelerates the wheel spin (norm/sec²).
var wheel_spin_accel: float = 1.4
## Terminal wheel velocity under continuous input (norm/sec).
## 1.0 / 0.167 = ~6 seconds from center to full lock.
var wheel_max_spin: float = 0.167
## Friction deceleration when input is released (norm/sec²).
var wheel_friction: float = 1.5
## Rudder chases wheel at this rate (norm/sec). Matched to wheel speed
## so rudder and wheel arrive at full lock together in ~6 seconds.
var rudder_follow_rate: float = 0.167
## Exponential spring return toward center when no input.
## Rate scales with displacement: fast far from center, gentle near center.
## 0.15 ≈ from full lock: slow, deliberate return.
var wheel_return_rate: float = 0.15
## Damping factor when counter-steering (input opposes wheel position).
## Simulates fighting the rope tension wound around the drum.
## Higher = snappier reversal (was 0.3 — felt like input lag / “stuck” after port→stbd).
var counter_steer_damping: float = 0.72

var center_threshold: float = 0.04
## Crew manning multiplier: scales rudder responsiveness. Set by arena from CrewController efficiency.
var crew_helm_mult: float = 1.0

## Component damage: 0.0 = pristine, 1.0 = tiller/rudder destroyed.
## Reduces rudder follow rate, wheel spin accel, and max rudder deflection.
var damage: float = 0.0

## Damage per cannonball hit to helm (lower hull hits near waterline).
const DAMAGE_PER_HIT: float = 0.10
## At full damage, rudder responds this fraction as fast.
const MIN_RUDDER_EFFICIENCY: float = 0.2
## At full damage, max rudder deflection is reduced to this fraction.
const MIN_DEFLECTION_MULT: float = 0.35

var _wheel_at_tick_start: float = 0.0
var _had_steering_input: bool = false
var _steer_left: bool = false
var _steer_right: bool = false


## Copy tuning + mechanical state for trajectory preview (must match process_steer behavior).
func copy_from(other: HelmController) -> void:
	wheel_spin_accel = other.wheel_spin_accel
	wheel_max_spin = other.wheel_max_spin
	wheel_friction = other.wheel_friction
	rudder_follow_rate = other.rudder_follow_rate
	wheel_return_rate = other.wheel_return_rate
	counter_steer_damping = other.counter_steer_damping
	center_threshold = other.center_threshold
	wheel_position = other.wheel_position
	wheel_velocity = other.wheel_velocity
	rudder_angle = other.rudder_angle
	wheel_locked = other.wheel_locked
	wheel_lock_position = other.wheel_lock_position
	damage = other.damage
	crew_helm_mult = other.crew_helm_mult


func process_steer(delta: float, left_strength: float, right_strength: float) -> void:
	_wheel_at_tick_start = wheel_position

	if wheel_locked:
		_had_steering_input = false
		_steer_left = false
		_steer_right = false
		wheel_velocity = 0.0
		wheel_position = wheel_lock_position
		rudder_angle = move_toward(rudder_angle, wheel_lock_position, rudder_follow_rate * delta)
		return

	var l: float = clampf(left_strength, 0.0, 1.0)
	var r: float = clampf(right_strength, 0.0, 1.0)
	var dominant: float = absf(l - r)
	# Loose threshold + one-sided guard: float noise / near-cancelling inputs used to drop
	# below 0.02 and stall the wheel for random frames (felt like “no helm input”).
	var max_lr: float = maxf(l, r)
	var min_lr: float = minf(l, r)
	var active: bool = dominant > 0.004 or (max_lr >= 0.88 and min_lr <= 0.06)
	_had_steering_input = active
	_steer_left = active and l > r
	_steer_right = active and r > l

	if active:
		var target_vel: float = wheel_max_spin * r - wheel_max_spin * l
		var opposing: bool = (target_vel > 0.0 and wheel_position < -0.12) or (target_vel < 0.0 and wheel_position > 0.12)
		var eff_accel: float = wheel_spin_accel * crew_helm_mult * (counter_steer_damping if opposing else 1.0)
		wheel_velocity = move_toward(wheel_velocity, target_vel, eff_accel * delta)
	else:
		wheel_velocity = move_toward(wheel_velocity, 0.0, wheel_friction * delta)
		var decay: float = exp(-wheel_return_rate * delta)
		wheel_position *= decay

	wheel_position = clampf(wheel_position + wheel_velocity * delta, -1.0, 1.0)
	if absf(wheel_position) >= 1.0:
		wheel_velocity = 0.0
	# Snap only when nearly centered and idle — at 60 Hz, |velocity|*delta can stay below 0.005 while steering.
	if absf(wheel_position) < 0.005 and not _had_steering_input and absf(wheel_velocity) < 0.001:
		wheel_position = 0.0

	var eff_follow: float = rudder_follow_rate * lerpf(1.0, MIN_RUDDER_EFFICIENCY, damage) * crew_helm_mult
	rudder_angle = move_toward(rudder_angle, wheel_position, eff_follow * delta)
	# Damage limits max rudder deflection — bent tiller / fouled rope.
	var max_defl: float = lerpf(1.0, MIN_DEFLECTION_MULT, damage)
	rudder_angle = clampf(rudder_angle, -max_defl, max_defl)


func apply_hit() -> void:
	damage = clampf(damage + DAMAGE_PER_HIT, 0.0, 1.0)


func reset_damage() -> void:
	damage = 0.0


func get_effective_max_deflection() -> float:
	return lerpf(1.0, MIN_DEFLECTION_MULT, damage)


func set_wheel_lock(enabled: bool) -> void:
	wheel_locked = enabled
	if wheel_locked:
		wheel_lock_position = clampf(wheel_position, -1.0, 1.0)
		wheel_velocity = 0.0


func toggle_wheel_lock() -> bool:
	set_wheel_lock(not wheel_locked)
	return wheel_locked


func get_helm_state() -> HelmState:
	var w: float = wheel_position
	var dw: float = w - _wheel_at_tick_start
	var eps: float = 0.0001
	if absf(w) < center_threshold and absf(rudder_angle) < center_threshold:
		return HelmState.CENTER

	if _had_steering_input:
		if _steer_left:
			if dw < -eps:
				return HelmState.TURNING_LEFT
			return HelmState.LEFT
		elif _steer_right:
			if dw > eps:
				return HelmState.TURNING_RIGHT
			return HelmState.RIGHT
	else:
		if absf(dw) > eps:
			return HelmState.RECENTERING
		if w < -center_threshold:
			return HelmState.LEFT
		if w > center_threshold:
			return HelmState.RIGHT
	return HelmState.CENTER


func get_rudder_label() -> String:
	var deg: float = absf(rudder_angle) * MAX_RUDDER_DEFLECTION_DEG
	if deg < 1.0:
		return "Rudder mid"
	if rudder_angle < 0.0:
		return "Port %.0f°" % deg
	return "Stbd %.0f°" % deg


func get_helm_state_enum_name() -> String:
	match get_helm_state():
		HelmState.CENTER:
			return "CENTER"
		HelmState.LEFT:
			return "LEFT"
		HelmState.RIGHT:
			return "RIGHT"
		HelmState.TURNING_LEFT:
			return "TURNING_LEFT"
		HelmState.TURNING_RIGHT:
			return "TURNING_RIGHT"
		HelmState.RECENTERING:
			return "RECENTERING"
	return "—"


func get_helm_state_label() -> String:
	if wheel_locked:
		return "Wheel lock"
	match get_helm_state():
		HelmState.CENTER:
			return "Center"
		HelmState.LEFT:
			return "Port"
		HelmState.RIGHT:
			return "Starboard"
		HelmState.TURNING_LEFT:
			return "Wheel ←"
		HelmState.TURNING_RIGHT:
			return "Wheel →"
		HelmState.RECENTERING:
			return "Counter-steer"
	return "—"
