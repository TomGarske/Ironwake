class_name IronwakeWhirlpool
extends RefCounted
## Whirlpool arena-integration logic extracted from IronwakeArena.
## Owns init, per-frame advance, and per-ship physics injection.
## The WhirlpoolController (physics model) still lives on the arena as _whirlpool.

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const _WhirlpoolController := preload("res://scripts/shared/whirlpool_controller.gd")

## Spin rate applied to ships caught in the core (rad/s).
const CORE_SPIN_RATE: float = 6.0
## Seconds of spinning in the core before the ship sinks.
const CORE_SINK_TIME: float = 1.5

## Slingshot: max speed multiplier when perfectly aligned deep in the whirlpool.
const SLINGSHOT_MAX_SPEED_MULT: float = 1.6
## How quickly the slingshot boost ramps up (units/s² added to move_speed).
const SLINGSHOT_ACCEL: float = 25.0

var arena: Node = null


func init(arena_node: Node) -> void:
	arena = arena_node


func init_whirlpool() -> void:
	if not arena.whirlpool_enabled:
		return
	arena._whirlpool = _WhirlpoolController.new()
	var u: float = NC.UNITS_PER_LOGIC_TILE
	arena._whirlpool.center = Vector2(float(NC.MAP_TILES_WIDE) * 0.5 * u, float(NC.MAP_TILES_HIGH) * 0.5 * u)
	arena._whirlpool.influence_radius = arena.whirlpool_influence_radius
	arena._whirlpool.control_ring_radius = arena.whirlpool_control_radius
	arena._whirlpool.danger_ring_radius = arena.whirlpool_danger_radius
	arena._whirlpool.core_radius = arena.whirlpool_core_radius


func begin_frame(delta: float = 0.0) -> void:
	if arena._whirlpool != null:
		arena._whirlpool.frame_id += 1
		arena._whirlpool.advance_time(delta)


func pre_physics(p: Dictionary, delta: float) -> void:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		return
	if not bool(p.get("alive", false)):
		return

	var ship_id: int = int(p.get("peer_id", 0))
	var ship_pos: Vector2 = Vector2(float(p.wx), float(p.wy))
	var ship_dir: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if ship_dir.length_squared() < 0.0001:
		ship_dir = Vector2.RIGHT
	else:
		ship_dir = ship_dir.normalized()
	var spd: float = float(p.get("move_speed", 0.0))

	var ws: _WhirlpoolController.WhirlpoolShipState = arena._whirlpool.process_ship(
		ship_id, ship_pos, ship_dir, spd, NC.MAX_SPEED, delta)

	p["_wp_ring"] = ws.ring_type
	p["_wp_turn_mod"] = ws.turn_modifier
	p["_wp_accel_mod"] = ws.acceleration_modifier
	p["_wp_flow_align"] = ws.flow_alignment
	p["_wp_flow_dir"] = ws.flow_direction
	p["_wp_drag_force"] = ws.drag_force
	p["_wp_torque"] = ws.torque
	p["_wp_water_vel"] = ws.water_velocity
	p["_wp_water_speed"] = ws.water_speed
	p["_wp_v_lateral"] = ws.v_lateral
	p["_wp_water_carry"] = ws.water_carry



func turn_scalar(p: Dictionary) -> float:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		return 1.0
	return float(p.get("_wp_turn_mod", 1.0))


func accel_scalar(p: Dictionary) -> float:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		return 1.0
	return float(p.get("_wp_accel_mod", 1.0))


func inject_physics(p: Dictionary, delta: float) -> void:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		p["_wp_water_carry_vel"] = Vector2.ZERO
		return

	var ring: int = int(p.get("_wp_ring", 0))

	if ring == 0:
		p["_wp_water_carry_vel"] = Vector2.ZERO
		return

	# Water carry handles all whirlpool movement (tangential orbit + radial pull).
	# Ship's move_speed stays sail-driven; the carry adds on top in position integration.
	p["_wp_water_carry_vel"] = p.get("_wp_water_carry", Vector2.ZERO)

	# ── Slingshot: boost move_speed when aligned with the flow ──
	# Deeper rings + better alignment = bigger boost. Risk vs reward.
	var flow_align: float = float(p.get("_wp_flow_align", 0.0))
	if flow_align > 0.0:
		var water_spd: float = float(p.get("_wp_water_speed", 0.0))
		var depth_frac: float = clampf(water_spd / maxf(0.01, NC.MAX_SPEED), 0.0, 1.0)
		var slingshot_cap: float = NC.MAX_SPEED * lerpf(1.0, SLINGSHOT_MAX_SPEED_MULT, flow_align * depth_frac)
		var spd: float = float(p.get("move_speed", 0.0))
		if spd < slingshot_cap:
			spd = minf(spd + SLINGSHOT_ACCEL * flow_align * depth_frac * delta, slingshot_cap)
			p["move_speed"] = spd

	var wp_torque: float = float(p.get("_wp_torque", 0.0))
	var av: float = float(p.get("angular_velocity", 0.0))
	av += wp_torque * delta
	p["angular_velocity"] = av

	# ── Core: spin and sink ──
	if ring == _WhirlpoolController.Ring.CORE and bool(p.get("alive", false)):
		p["angular_velocity"] = CORE_SPIN_RATE
		var hull: Vector2 = Vector2(p.dir.x, p.dir.y).normalized()
		hull = hull.rotated(CORE_SPIN_RATE * delta).normalized()
		p.dir = hull
		# Accumulate time in core; sink after CORE_SINK_TIME.
		var core_t: float = float(p.get("_wp_core_timer", 0.0)) + delta
		p["_wp_core_timer"] = core_t
		if core_t >= CORE_SINK_TIME:
			p.alive = false
			p["health"] = 0.0
			p["respawn_timer"] = arena.RESPAWN_DELAY_SEC
			var pid: int = int(p.get("peer_id", 0))
			if arena._scoreboard.has(pid):
				arena._scoreboard[pid]["deaths"] += 1
			arena._check_win()
	else:
		p.erase("_wp_core_timer")
