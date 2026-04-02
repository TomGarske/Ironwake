## Centered whirlpool arena mechanic — gravity well model.
##
## Water velocity profile: v ∝ 1/sqrt(r), like planetary orbital velocity.
## Peaks at core boundary, decays outward, fades to zero at influence edge.
## Radial inflow equals tangential flow — ships spiral inward as strongly as
## they orbit. Both components use the same gravity-well curve.
##
## (req-whirlpool-arena-v1)
extends RefCounted
class_name WhirlpoolController

# ═══════════════════════════════════════════════════════════════════════
#  Ring classification (visual / gameplay zones only — physics is continuous)
# ═══════════════════════════════════════════════════════════════════════

enum Ring { NONE, OUTER, CONTROL, DANGER, CORE }

# ═══════════════════════════════════════════════════════════════════════
#  Geometry (world-unit radii)
# ═══════════════════════════════════════════════════════════════════════

var center: Vector2 = Vector2.ZERO

## Ring boundaries — used for classification and visuals.
var influence_radius: float = 600.0
var control_ring_radius: float = 280.0
var danger_ring_radius: float = 120.0
var core_radius: float = 40.0

# ═══════════════════════════════════════════════════════════════════════
#  Drag / force tuning
# ═══════════════════════════════════════════════════════════════════════

## Quadratic drag coefficient for translational force.
var drag_k: float = 0.0018

## Torque coefficient for cross-flow turning.
var torque_k: float = 0.0012

## Maximum angular velocity the whirlpool torque can contribute (rad/s).
var max_torque_av: float = 0.5

## Turn authority penalty inside the whirlpool.
## Interpolated: 1.0 at edge → this value at core.
var min_turn_authority: float = 0.7

# ═══════════════════════════════════════════════════════════════════════
#  Disruption — whirlpool escalates over time
# ═══════════════════════════════════════════════════════════════════════

## Elapsed time since whirlpool started (seconds). Call advance_time() each tick.
var elapsed_time: float = 0.0

## Time (seconds) for disruption to go from 0% → 100%.
var disruption_ramp_sec: float = 180.0

## At full disruption, turbulence jitter amplitude (world units/s² on drag force).
var disruption_turbulence_max: float = 3.0

## Base influence radius (set once at init).
var _base_influence_radius: float = 600.0

## Current disruption level (0.0–1.0). Read-only outside; use advance_time().
var disruption: float = 0.0

## Total elapsed time for disruption ramp (never wrapped).
var _disruption_time: float = 0.0

## Call once per tick with delta to advance disruption.
func advance_time(delta: float) -> void:
	_disruption_time += delta
	disruption = clampf(_disruption_time / maxf(0.01, disruption_ramp_sec), 0.0, 1.0)
	elapsed_time = fmod(elapsed_time + delta, 1.0)


## Pseudorandom turbulence vector for a given position + time (deterministic noise).
func _turbulence_at(pos: Vector2, time: float) -> Vector2:
	var seed_x: float = pos.x * 0.013 + pos.y * 0.0079 + time * 1.7
	var seed_y: float = pos.x * 0.0091 + pos.y * 0.017 + time * 2.3
	return Vector2(sin(seed_x * 6.28) * cos(seed_y * 3.14), cos(seed_x * 3.14) * sin(seed_y * 6.28))


# ═══════════════════════════════════════════════════════════════════════
#  Per-ship state
# ═══════════════════════════════════════════════════════════════════════

var _ship_states: Dictionary = {}


class WhirlpoolShipState:
	var is_in_whirlpool: bool = false
	var distance_to_center: float = 0.0
	var ring_type: int = Ring.NONE
	var water_velocity: Vector2 = Vector2.ZERO
	var water_speed: float = 0.0
	var water_speed_tangential: float = 0.0
	var water_speed_radial: float = 0.0
	var v_relative: Vector2 = Vector2.ZERO
	var v_lateral: float = 0.0
	var v_longitudinal: float = 0.0
	var drag_force: Vector2 = Vector2.ZERO
	var water_carry: Vector2 = Vector2.ZERO
	var torque: float = 0.0
	var flow_direction: Vector2 = Vector2.ZERO
	var flow_alignment: float = 0.0
	var turn_modifier: float = 1.0
	var acceleration_modifier: float = 1.0
	var prev_ring: int = Ring.NONE
	var _frame_id: int = -1


# ═══════════════════════════════════════════════════════════════════════
#  Public API
# ═══════════════════════════════════════════════════════════════════════

var frame_id: int = 0


func get_ship_state(ship_id: int) -> WhirlpoolShipState:
	if not _ship_states.has(ship_id):
		_ship_states[ship_id] = WhirlpoolShipState.new()
	return _ship_states[ship_id]


func classify_ring(distance: float) -> int:
	if distance > influence_radius:
		return Ring.NONE
	if distance > control_ring_radius:
		return Ring.OUTER
	if distance > danger_ring_radius:
		return Ring.CONTROL
	if distance > core_radius:
		return Ring.DANGER
	return Ring.CORE


static func ring_name(ring: int) -> String:
	match ring:
		Ring.NONE: return "NONE"
		Ring.OUTER: return "OUTER"
		Ring.CONTROL: return "CONTROL"
		Ring.DANGER: return "DANGER"
		Ring.CORE: return "CORE"
	return "?"


## Gravity-well water speed: v ∝ 1/sqrt(r), like planetary orbital velocity.
## Peaks at core boundary (= max_speed), decays outward, fades to zero at edge.
## Used for both tangential AND radial components (radial = tangential).
func water_speed_at_radius(r: float, max_speed: float) -> float:
	if r > influence_radius:
		return 0.0
	# 1/sqrt(r) profile, normalized so v = max_speed at core boundary.
	var v: float = max_speed * sqrt(core_radius / maxf(core_radius, r))
	# Fade to zero in outer 25% of influence radius.
	var edge_start: float = influence_radius * 0.75
	if r > edge_start:
		v *= 1.0 - (r - edge_start) / (influence_radius - edge_start)
	return v


## Process whirlpool effects for a single ship. Call EXACTLY ONCE per tick.
func process_ship(ship_id: int, ship_pos: Vector2, ship_dir: Vector2, ship_speed: float, max_speed: float, _delta: float) -> WhirlpoolShipState:
	var state: WhirlpoolShipState = get_ship_state(ship_id)

	if state._frame_id == frame_id:
		return state
	state._frame_id = frame_id

	var to_center: Vector2 = center - ship_pos
	var dist: float = to_center.length()

	state.distance_to_center = dist
	state.prev_ring = state.ring_type
	state.ring_type = classify_ring(dist)
	state.is_in_whirlpool = state.ring_type != Ring.NONE

	state.drag_force = Vector2.ZERO
	state.water_carry = Vector2.ZERO
	state.torque = 0.0

	if not state.is_in_whirlpool:
		state.water_velocity = Vector2.ZERO
		state.water_speed = 0.0
		state.water_speed_tangential = 0.0
		state.water_speed_radial = 0.0
		state.v_relative = Vector2.ZERO
		state.v_lateral = 0.0
		state.v_longitudinal = 0.0
		state.flow_direction = Vector2.ZERO
		state.flow_alignment = 0.0
		state.turn_modifier = 1.0
		state.acceleration_modifier = 1.0
		return state

	# ── Directional basis ──
	var radial_inward: Vector2 = to_center.normalized() if dist > 0.01 else Vector2.UP
	var tangential: Vector2 = radial_inward.rotated(-PI * 0.5)
	state.flow_direction = tangential

	# ── Water velocity: gravity-well profile, equal tangential and radial ──
	var v_tan: float = water_speed_at_radius(dist, max_speed)
	var v_rad: float = v_tan  # Radial pull equals tangential current.
	var water_vel: Vector2 = tangential * v_tan + radial_inward * v_rad

	state.water_velocity = water_vel
	state.water_speed = water_vel.length()
	state.water_speed_tangential = v_tan
	state.water_speed_radial = v_rad

	# ── Ship velocity vector ──
	var ship_dir_n: Vector2 = ship_dir.normalized() if ship_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var ship_vel: Vector2 = ship_dir_n * ship_speed

	# ── Relative velocity: water w.r.t. ship ──
	var v_rel: Vector2 = water_vel - ship_vel
	state.v_relative = v_rel

	var v_long: float = v_rel.dot(ship_dir_n)
	var v_lat_vec: Vector2 = v_rel - ship_dir_n * v_long
	var v_lat_mag: float = v_lat_vec.length()
	state.v_longitudinal = v_long
	state.v_lateral = v_lat_mag

	# ── Flow alignment ──
	state.flow_alignment = ship_dir_n.dot(tangential)

	# ── Quadratic drag force ──
	var v_rel_sq: float = v_rel.length_squared()
	if v_rel_sq > 0.01:
		state.drag_force = v_rel.normalized() * drag_k * v_rel_sq
	else:
		state.drag_force = Vector2.ZERO

	# ── Turbulence ──
	if disruption > 0.01:
		var depth_norm: float = 1.0 - clampf(dist / influence_radius, 0.0, 1.0)
		var turb_amp: float = disruption_turbulence_max * disruption * depth_norm
		state.drag_force += _turbulence_at(ship_pos, elapsed_time) * turb_amp

	# ── Water carry: current drags ship position directly ──
	# Full water velocity applied regardless of ship speed.
	state.water_carry = water_vel

	# ── Torque from cross-flow ──
	if v_lat_mag > 0.1:
		var cross_sign: float = signf(ship_dir_n.x * v_lat_vec.y - ship_dir_n.y * v_lat_vec.x)
		var water_frac: float = clampf(water_vel.length() / maxf(0.01, max_speed), 0.0, 1.0)
		state.torque = clampf(torque_k * v_lat_mag * water_frac * cross_sign, -max_torque_av, max_torque_av)
	else:
		state.torque = 0.0

	# ── Turn authority ──
	var depth_frac: float = 1.0 - clampf((dist - core_radius) / maxf(0.01, influence_radius - core_radius), 0.0, 1.0)
	state.turn_modifier = lerpf(1.0, min_turn_authority, depth_frac)

	# ── Acceleration modifier ──
	var alignment: float = state.flow_alignment
	var accel_depth: float = depth_frac * depth_frac
	if alignment > 0.0:
		state.acceleration_modifier = lerpf(1.0, 1.3, alignment * accel_depth)
	else:
		state.acceleration_modifier = lerpf(1.0, 0.7, -alignment * accel_depth)

	return state


# ═══════════════════════════════════════════════════════════════════════
#  AI data hooks
# ═══════════════════════════════════════════════════════════════════════

func get_ai_data(ship_id: int, ship_pos: Vector2, ship_dir: Vector2) -> Dictionary:
	var state: WhirlpoolShipState = get_ship_state(ship_id)
	var to_center: Vector2 = center - ship_pos
	var dist: float = to_center.length()
	var tangential: Vector2 = Vector2.ZERO
	if dist > 0.01:
		tangential = to_center.normalized().rotated(-PI * 0.5)
	var ship_dir_n: Vector2 = ship_dir.normalized() if ship_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var slingshot_score: float = 0.0
	if state.ring_type == Ring.CONTROL:
		slingshot_score = maxf(0.0, ship_dir_n.dot(tangential))
	return {
		"distance_to_whirlpool_center": dist,
		"whirlpool_ring": state.ring_type,
		"whirlpool_ring_name": ring_name(state.ring_type),
		"whirlpool_flow_direction": tangential,
		"whirlpool_water_speed": state.water_speed,
		"is_in_danger_ring": state.ring_type == Ring.DANGER,
		"is_in_core": state.ring_type == Ring.CORE,
		"slingshot_alignment_score": slingshot_score,
	}
