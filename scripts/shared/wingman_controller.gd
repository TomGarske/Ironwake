## Wingman AI controller: extends NavalBotController with fleet orders and formation.
## Used for player-commanded AI wingmen in PVE fleet combat.
class_name WingmanController
extends NavalBotController

enum FleetOrder {
	FORM_UP,          ## Maintain formation relative to flagship.
	ATTACK_MY_TARGET, ## Engage the flagship's nearest enemy.
	HOLD_POSITION,    ## Station-keep at current position, engage targets of opportunity.
	BREAK_AND_ATTACK, ## Independent engagement (full duel BT).
}

const ORDER_NAMES: Array[String] = ["Form Up", "Attack Target", "Hold Position", "Break & Attack"]
const ORDER_COUNT: int = 4

## Current standing order from the player.
var current_order: FleetOrder = FleetOrder.FORM_UP
## The flagship ship dictionary (player's ship) — used for formation reference.
var flagship_dict: Dictionary = {}
## This wingman's formation offset relative to flagship (set by fleet arena at spawn).
var formation_offset: Vector2 = Vector2.ZERO
## Hold position anchor (set when HOLD_POSITION is issued).
var hold_anchor: Vector2 = Vector2.ZERO
## Index in the fleet (0 = flagship, 1+ = wingmen).
var fleet_ship_index: int = 0

## Formation tolerance — how close is "in formation" (world units).
const FORMATION_TOLERANCE: float = 80.0
## Distance beyond which formation is considered broken.
const FORMATION_BROKEN_DIST: float = 400.0
## Approach speed preference when forming up.
const FORMATION_SAIL_STATE: int = 2  # HALF sail


func set_order(order: FleetOrder) -> void:
	current_order = order
	if order == FleetOrder.HOLD_POSITION:
		# Anchor at current position.
		if agent != null:
			hold_anchor = agent.get_ship_pos()
	# When switching to ATTACK_MY_TARGET or BREAK_AND_ATTACK, keep current target.
	# For FORM_UP, target becomes irrelevant (formation takes priority).


func get_formation_target_pos() -> Vector2:
	## Where this wingman should be in formation (world coords).
	if flagship_dict.is_empty():
		return agent.get_ship_pos() if agent != null else Vector2.ZERO
	var flag_pos: Vector2 = Vector2(float(flagship_dict.get("wx", 0.0)), float(flagship_dict.get("wy", 0.0)))
	var flag_dir: Vector2 = flagship_dict.get("dir", Vector2.RIGHT)
	if flag_dir.length_squared() < 0.0001:
		flag_dir = Vector2.RIGHT
	flag_dir = flag_dir.normalized()
	var flag_perp: Vector2 = flag_dir.rotated(PI * 0.5)
	return flag_pos + flag_dir * formation_offset.y + flag_perp * formation_offset.x


func get_formation_distance() -> float:
	if agent == null:
		return 9999.0
	return agent.get_ship_pos().distance_to(get_formation_target_pos())


func is_in_formation() -> bool:
	return get_formation_distance() < FORMATION_TOLERANCE


func is_formation_broken() -> bool:
	return get_formation_distance() > FORMATION_BROKEN_DIST


## Override update to inject order-based behavior BEFORE the BT runs.
func update(delta: float) -> void:
	if agent == null or agent.ship_dict.is_empty():
		return
	if not agent.is_alive():
		steer_left = 0.0
		steer_right = 0.0
		fire_port_intent = false
		fire_stbd_intent = false
		return

	_game_time_elapsed += delta
	_tick_timers(delta)
	# Only update combat context for combat orders — FORM_UP/HOLD don't need it
	# and the bearing_to_target_deg it sets would interfere with formation steering.
	if current_order == FleetOrder.ATTACK_MY_TARGET or current_order == FleetOrder.BREAK_AND_ATTACK:
		_update_combat_context()

	steer_left = 0.0
	steer_right = 0.0
	fire_port_intent = false
	fire_stbd_intent = false

	match current_order:
		FleetOrder.FORM_UP:
			_tick_form_up(delta)
		FleetOrder.ATTACK_MY_TARGET:
			_tick_attack_target(delta)
		FleetOrder.HOLD_POSITION:
			_tick_hold_position(delta)
		FleetOrder.BREAK_AND_ATTACK:
			_tick_break_and_attack(delta)

	# Only adjust sail for combat turns when in combat orders.
	# In FORM_UP and HOLD_POSITION, the order logic sets sail state directly.
	if current_order == FleetOrder.ATTACK_MY_TARGET or current_order == FleetOrder.BREAK_AND_ATTACK:
		_adjust_sail_for_turn()
	_manage_crew()


func _tick_form_up(delta: float) -> void:
	var target_pos: Vector2 = get_formation_target_pos()
	var ship_pos: Vector2 = agent.get_ship_pos()
	var to_target: Vector2 = target_pos - ship_pos
	var dist: float = to_target.length()

	if dist < FORMATION_TOLERANCE:
		# In formation — match flagship heading and speed.
		var flag_dir: Vector2 = flagship_dict.get("dir", Vector2.RIGHT)
		if flag_dir.length_squared() < 0.0001:
			flag_dir = Vector2.RIGHT
		flag_dir = flag_dir.normalized()
		_steer_toward_heading(flag_dir, delta)
		# Match flagship sail state.
		var flag_sail: Variant = flagship_dict.get("sail")
		if flag_sail != null:
			desired_sail_state = int(flag_sail.sail_state)
		else:
			desired_sail_state = FORMATION_SAIL_STATE
		# While in formation, still fire at enemies of opportunity.
		_fire_at_nearest_enemy(delta)
	else:
		# Out of formation — navigate toward formation position.
		_steer_toward_point(target_pos, delta)
		desired_sail_state = 3 if dist > FORMATION_BROKEN_DIST else FORMATION_SAIL_STATE


func _tick_attack_target(delta: float) -> void:
	# Use the standard duel BT — it already handles approach, broadside, and fire.
	if _bt_initialised and bt_player != null:
		_sync_limbo_blackboard()
		bt_player.call("update", delta)
	else:
		# Fallback: approach target directly.
		_steer_toward_dict(target_dict, delta)
		desired_sail_state = 2


func _tick_hold_position(delta: float) -> void:
	var ship_pos: Vector2 = agent.get_ship_pos()
	var to_anchor: Vector2 = hold_anchor - ship_pos
	var dist: float = to_anchor.length()

	if dist > 200.0:
		# Drifted too far — return to anchor.
		_steer_toward_point(hold_anchor, delta)
		desired_sail_state = 2
	elif dist > 50.0:
		_steer_toward_point(hold_anchor, delta)
		desired_sail_state = 1  # QUARTER
	else:
		# Near anchor — slow down and circle gently.
		desired_sail_state = 1
	# Always engage targets of opportunity.
	_fire_at_nearest_enemy(delta)


func _tick_break_and_attack(delta: float) -> void:
	# Full independent engagement using the duel BT.
	if _bt_initialised and bt_player != null:
		_sync_limbo_blackboard()
		bt_player.call("update", delta)


## Steer toward a world-space heading direction.
func _steer_toward_heading(target_heading: Vector2, _delta: float) -> void:
	var ship_dir: Vector2 = agent.get_ship_dir()
	var cross: float = ship_dir.cross(target_heading)
	var dot: float = ship_dir.dot(target_heading)
	var angle_diff: float = atan2(cross, dot)
	if absf(angle_diff) < 0.05:
		return  # Close enough.
	if angle_diff > 0:
		steer_left = clampf(absf(angle_diff) * 2.0, 0.2, 1.0)
	else:
		steer_right = clampf(absf(angle_diff) * 2.0, 0.2, 1.0)


## Steer toward a world-space point.
func _steer_toward_point(target: Vector2, delta: float) -> void:
	var to_target: Vector2 = target - agent.get_ship_pos()
	if to_target.length_squared() < 1.0:
		return
	_steer_toward_heading(to_target.normalized(), delta)


## Steer toward another ship dict.
func _steer_toward_dict(other: Dictionary, delta: float) -> void:
	var pos: Vector2 = Vector2(float(other.get("wx", 0.0)), float(other.get("wy", 0.0)))
	_steer_toward_point(pos, delta)


## Fire at nearest enemy (for formation/hold modes). Sets fire intents based on bearing.
func _fire_at_nearest_enemy(_delta: float) -> void:
	if target_dict.is_empty() or not bool(target_dict.get("alive", false)):
		return
	var ship_pos: Vector2 = agent.get_ship_pos()
	var hull_n: Vector2 = agent.get_ship_dir()
	var target_pos: Vector2 = Vector2(float(target_dict.get("wx", 0.0)), float(target_dict.get("wy", 0.0)))
	var to_target: Vector2 = target_pos - ship_pos
	var dist: float = to_target.length()
	if dist > 800.0:
		return  # Too far.
	var cross_val: float = hull_n.cross(to_target.normalized())
	if cross_val > 0.1:
		fire_port_intent = true
	elif cross_val < -0.1:
		fire_stbd_intent = true
