## AI brain for an enemy ship.  Owns a LimboAI BTPlayer, manages the blackboard,
## and translates BT outputs into helm/sail/fire intents.  (req-ai-naval-bot-v1)
class_name NavalBotController
extends Node

const _Evaluator := preload("res://scripts/shared/naval_combat_evaluator.gd")
const _SailController := preload("res://scripts/shared/sail_controller.gd")
const _BatteryController := preload("res://scripts/shared/battery_controller.gd")

## The BotShipAgent Node2D that wraps the ship dictionary.
var agent: BotShipAgent = null
## Reference to the player's ship dictionary (the target).
var target_dict: Dictionary = {}

## LimboAI runner — MANUAL update from update().
var bt_player: BTPlayer = null

# ── Output intents (read by arena's _tick_bot) ────────────────────────
var steer_left: float = 0.0
var steer_right: float = 0.0
var fire_port_intent: bool = false
var fire_stbd_intent: bool = false
var desired_sail_state: int = 1   # 0=STOP 1=QUARTER 2=HALF 3=FULL (match arena quarter sail)

# ── Anti-jitter timers ────────────────────────────────────────────────
var turn_commit_timer: float = 0.0
var turn_commit_direction: float = 0.0   # -1 left, +1 right, 0 none
var side_switch_cooldown_timer: float = 0.0
var preferred_side: String = "none"
var fire_stability_timer: float = 0.0
var maneuver_lock_timer: float = 0.0
var post_fire_lockout_timer: float = 0.0
var reposition_timer: float = 0.0
var reposition_turn_dir: float = 0.0

# ── Stuck detection ──────────────────────────────────────────────────
var stuck_timer: float = 0.0
var last_position: Vector2 = Vector2.ZERO

# ── Combat state ──────────────────────────────────────────────────────
var currently_repositioning: bool = false
var recently_fired: bool = false
var last_maneuver: String = "idle"
var fire_block_reason: String = ""

# ── Cached evaluator results ──────────────────────────────────────────
var broadside_result: Dictionary = {}
var range_band: int = _Evaluator.RangeBand.BEYOND_MAX
var distance_to_target: float = 9999.0
var bearing_to_target_deg: float = 0.0

# ── Fire reaction delay (req-combat-loop §3.6, req-ai §FireBroadside) ───
var _pending_fire_delay: float = 0.0
var _pending_fire_side: String = ""

# ── Incoming fire (arena calls when this bot’s hull takes a cannon hit) ──
var hit_reaction_timer: float = 0.0
var last_hit_attacker_peer_id: int = 0

# ── Debug (req-debug-combat-v1) ─────────────────────────────────────────
## When false, arena skips this bot’s text panel.
var show_debug_hud_panel: bool = false
## Verbose print() for pass / reposition / stuck / side switch (off by default).
var debug_log_events: bool = false
var current_bt_state: String = "init"
## Log once if Limbo GDExtension failed to register (wrong Godot version, missing binaries).
var _limbo_missing_logged: bool = false


func _ready() -> void:
	# GDExtension classes may register after the first frame; deferred improves first-run reliability.
	call_deferred("_setup_bt_player")


func _setup_bt_player() -> void:
	if bt_player != null:
		return
	if not ClassDB.class_exists("BTPlayer"):
		return
	bt_player = BTPlayer.new()
	bt_player.name = "NavalBTPlayer"
	bt_player.update_mode = BTPlayer.MANUAL
	bt_player.active = true
	add_child(bt_player)
	if is_instance_valid(get_parent()):
		bt_player.set_scene_root_hint(get_parent())
	# Limbo resolves agent_node from BTPlayer's node, not from this controller.
	if agent != null and is_instance_valid(agent):
		bt_player.agent_node = bt_player.get_path_to(agent)
	bt_player.behavior_tree = NavalBTDuelTree.build()
	var bb: Blackboard = bt_player.blackboard
	if bb != null:
		bb.set_var(&"controller", self)


## Main update — called each frame by arena's _tick_bot().
func update(delta: float) -> void:
	if agent == null or agent.ship_dict.is_empty():
		return
	if not agent.is_alive():
		steer_left = 0.0
		steer_right = 0.0
		fire_port_intent = false
		fire_stbd_intent = false
		return

	_tick_timers(delta)
	_update_combat_context()
	_sync_limbo_blackboard()

	# LimboAI behavior tree drives maneuvers; reset outputs then let tasks write intents.
	steer_left = 0.0
	steer_right = 0.0
	fire_port_intent = false
	fire_stbd_intent = false
	if bt_player == null:
		_setup_bt_player()
	if bt_player == null or bt_player.behavior_tree == null:
		if not _limbo_missing_logged:
			push_error(
				"NavalBotController: LimboAI is required for naval bots. "
				+ "Ensure addons/limboai is present, limboai.gdextension loads (Godot 4.6+ per LimboAI 1.7.x), "
				+ "and restart the editor. Project Settings → Limbo AI should list res://ai/tasks/naval for custom tasks."
			)
			_limbo_missing_logged = true
		return
	bt_player.update(delta)


func _tick_timers(delta: float) -> void:
	hit_reaction_timer = maxf(0.0, hit_reaction_timer - delta)
	turn_commit_timer = maxf(0.0, turn_commit_timer - delta)
	side_switch_cooldown_timer = maxf(0.0, side_switch_cooldown_timer - delta)
	maneuver_lock_timer = maxf(0.0, maneuver_lock_timer - delta)
	post_fire_lockout_timer = maxf(0.0, post_fire_lockout_timer - delta)

	if currently_repositioning:
		var prev_repo: float = reposition_timer
		reposition_timer = maxf(0.0, reposition_timer - delta)
		if reposition_timer <= 0.0 and prev_repo > 0.0:
			if debug_log_events:
				print("[NavalBot] reposition_end dist=%.0f" % distance_to_target)
			currently_repositioning = false
			recently_fired = false
			reposition_turn_dir = 0.0

	# Stuck detection.
	var pos: Vector2 = agent.get_ship_pos()
	if pos.distance_to(last_position) < _Evaluator.STUCK_PROGRESS_DISTANCE_EPSILON:
		stuck_timer += delta
	else:
		stuck_timer = 0.0
	last_position = pos

	# Fire stability accumulator.
	if broadside_result.get("best_quality", 0.0) >= _Evaluator.FIRE_THRESHOLD:
		fire_stability_timer += delta
	else:
		fire_stability_timer = 0.0


func _update_combat_context() -> void:
	if target_dict.is_empty():
		broadside_result = _Evaluator._empty_broadside_result("no_target")
		range_band = _Evaluator.RangeBand.BEYOND_MAX
		distance_to_target = 9999.0
		return

	var ship_pos: Vector2 = agent.get_ship_pos()
	var ship_dir: Vector2 = agent.get_ship_dir()
	var target_pos: Vector2 = Vector2(float(target_dict.get("wx", 0.0)), float(target_dict.get("wy", 0.0)))

	distance_to_target = ship_pos.distance_to(target_pos)
	bearing_to_target_deg = _Evaluator.bearing_to_target(ship_pos, ship_dir, target_pos)

	broadside_result = _Evaluator.evaluate_broadside(
		ship_pos, ship_dir, target_pos,
		agent.get_angular_velocity(),
		agent.get_speed(),
		agent.get_battery_port(),
		agent.get_battery_stbd()
	)

	var band_info: Dictionary = _Evaluator.evaluate_range_band(distance_to_target, range_band)
	range_band = int(band_info.get("band", _Evaluator.RangeBand.BEYOND_MAX))


func _sync_limbo_blackboard() -> void:
	if bt_player == null or bt_player.blackboard == null:
		return
	var bb: Blackboard = bt_player.blackboard
	var rs: int = int(_BatteryController.BatteryState.READY)
	var port_b: Variant = agent.get_battery_port() if agent != null else null
	var stbd_b: Variant = agent.get_battery_stbd() if agent != null else null
	bb.set_var(&"distance_to_target", distance_to_target)
	bb.set_var(&"bearing_to_target_deg", bearing_to_target_deg)
	bb.set_var(&"broadside_quality_port", float(broadside_result.get("quality_port", 0.0)))
	bb.set_var(&"broadside_quality_starboard", float(broadside_result.get("quality_stbd", 0.0)))
	bb.set_var(&"best_broadside_quality", float(broadside_result.get("best_quality", 0.0)))
	bb.set_var(&"best_broadside_side", str(broadside_result.get("best_side", "none")))
	bb.set_var(&"in_preferred_range", range_band == _Evaluator.RangeBand.PREFERRED)
	bb.set_var(&"too_close", range_band == _Evaluator.RangeBand.TOO_CLOSE)
	bb.set_var(&"too_far", range_band == _Evaluator.RangeBand.TOO_FAR or range_band == _Evaluator.RangeBand.BEYOND_MAX)
	bb.set_var(&"currently_repositioning", currently_repositioning)
	bb.set_var(&"recently_fired", recently_fired)
	bb.set_var(&"stuck_timer", stuck_timer)
	bb.set_var(&"last_maneuver", last_maneuver)
	bb.set_var(&"fire_block_reason", fire_block_reason)
	bb.set_var(&"port_loaded", port_b != null and int(port_b.state) == rs)
	bb.set_var(&"starboard_loaded", stbd_b != null and int(stbd_b.state) == rs)
	bb.set_var(&"recently_hit", hit_reaction_timer > 0.0)
	bb.set_var(&"last_hit_attacker_peer_id", last_hit_attacker_peer_id)


## Called from arena when this bot receives a registered cannon hit (not every frame).
func notify_cannon_hit(attacker_peer_id: int) -> void:
	last_hit_attacker_peer_id = attacker_peer_id
	hit_reaction_timer = 0.85
	# Do not stack fire-commit state with a pending delayed shot.
	_pending_fire_delay = 0.0
	_pending_fire_side = ""
	fire_block_reason = "took_hit"
	if debug_log_events:
		print("[NavalBot] hit from peer %d" % attacker_peer_id)


# ═══════════════════════════════════════════════════════════════════════
#  LimboAI task entry points (return BT.Status for custom BTAction tasks)
# ═══════════════════════════════════════════════════════════════════════

func limbo_tick_recover(_delta: float) -> int:
	if stuck_timer < _Evaluator.STUCK_DETECTION_TIME:
		return BT.Status.FAILURE
	return BT.Status.SUCCESS if _try_recover_if_stuck(_delta) else BT.Status.FAILURE


func limbo_tick_fire(delta: float) -> int:
	if _pending_fire_delay > 0.0:
		_pending_fire_delay -= delta
		if range_band == _Evaluator.RangeBand.TOO_CLOSE \
				or float(broadside_result.get("best_quality", 0.0)) < float(_Evaluator.FIRE_SOFT_THRESHOLD):
			_pending_fire_delay = 0.0
			_pending_fire_side = ""
			fire_block_reason = "fire_delay_cancelled"
			return BT.Status.FAILURE
		current_bt_state = "fire_commit"
		last_maneuver = "fire_delay"
		fire_block_reason = "reaction_delay"
		_steer_for_broadside_on_side(_pending_fire_side)
		if _pending_fire_delay > 0.0:
			return BT.Status.RUNNING
		if _commit_broadside_volley(str(_pending_fire_side)):
			return BT.Status.SUCCESS
		return BT.Status.FAILURE

	if currently_repositioning or recently_fired:
		fire_block_reason = "repositioning"
		return BT.Status.FAILURE
	if post_fire_lockout_timer > 0.0:
		fire_block_reason = "post_fire_lockout"
		return BT.Status.FAILURE

	var best_q: float = float(broadside_result.get("best_quality", 0.0))
	var best_side_str: String = str(broadside_result.get("best_side", "none"))
	if best_q < _Evaluator.FIRE_THRESHOLD:
		fire_block_reason = "quality_%.2f_below_threshold" % best_q
		return BT.Status.FAILURE
	if fire_stability_timer < _Evaluator.FIRE_STABILITY_TIME:
		fire_block_reason = "stability_timer_%.2f" % fire_stability_timer
		return BT.Status.FAILURE
	if best_side_str == "none":
		return BT.Status.FAILURE

	_pending_fire_delay = randf_range(_Evaluator.FIRE_REACTION_DELAY_MIN, _Evaluator.FIRE_REACTION_DELAY_MAX)
	_pending_fire_side = best_side_str
	current_bt_state = "fire_commit"
	last_maneuver = "fire_delay"
	fire_block_reason = "reaction_delay"
	if debug_log_events:
		print("[NavalBot] pass_fire_prepare side=%s q=%.2f delay=%.2fs dist=%.0f" % [
			best_side_str, best_q, _pending_fire_delay, distance_to_target,
		])
	_steer_for_broadside_on_side(best_side_str)
	return BT.Status.RUNNING


func limbo_tick_breakaway(delta: float) -> int:
	if range_band != _Evaluator.RangeBand.TOO_CLOSE:
		return BT.Status.FAILURE
	_pending_fire_delay = 0.0
	_pending_fire_side = ""
	_try_break_away(delta)
	return BT.Status.RUNNING


func limbo_tick_reposition(delta: float) -> int:
	if not currently_repositioning:
		return BT.Status.FAILURE
	_try_reposition(delta)
	return BT.Status.RUNNING


func limbo_tick_preferred(delta: float) -> int:
	if range_band != _Evaluator.RangeBand.PREFERRED:
		return BT.Status.FAILURE
	_try_establish_broadside(delta)
	return BT.Status.RUNNING


func limbo_tick_approach(delta: float) -> int:
	if range_band != _Evaluator.RangeBand.TOO_FAR and range_band != _Evaluator.RangeBand.BEYOND_MAX:
		return BT.Status.FAILURE
	_try_approach(delta)
	return BT.Status.RUNNING


func limbo_tick_establish(delta: float) -> int:
	if not _try_establish_broadside(delta):
		return BT.Status.FAILURE
	return BT.Status.RUNNING


func limbo_tick_hold(delta: float) -> int:
	_hold_pattern(delta)
	return BT.Status.RUNNING


# ═══════════════════════════════════════════════════════════════════════
#  Decision branches (shared by Limbo tasks)
# ═══════════════════════════════════════════════════════════════════════

func _try_recover_if_stuck(_delta: float) -> bool:
	if stuck_timer < _Evaluator.STUCK_DETECTION_TIME:
		return false
	current_bt_state = "recover_stuck"
	last_maneuver = "stuck_recovery"
	if debug_log_events:
		print("[NavalBot] stuck_recovery turn_commit after %.1fs" % stuck_timer)
	# Commit to a random turn direction.
	if turn_commit_timer <= 0.0:
		turn_commit_direction = [-1.0, 1.0][randi() % 2]
		turn_commit_timer = 2.0
	_set_steer(turn_commit_direction)
	desired_sail_state = 2  # HALF
	stuck_timer = 0.0
	_pending_fire_delay = 0.0
	_pending_fire_side = ""
	return true


func _try_break_away(_delta: float) -> bool:
	if range_band != _Evaluator.RangeBand.TOO_CLOSE:
		return false
	current_bt_state = "break_away"
	last_maneuver = "breakaway"
	# Turn away from target.
	var away_dir: float = -1.0 if bearing_to_target_deg >= 0.0 else 1.0
	_commit_turn(away_dir, 1.5)
	desired_sail_state = 3  # FULL — maximize separation
	fire_block_reason = "too_close"
	return true


func _commit_broadside_volley(best_side_str: String) -> bool:
	current_bt_state = "fire_broadside"
	last_maneuver = "firing_%s" % best_side_str
	fire_block_reason = ""
	_pending_fire_side = ""

	if best_side_str == "port":
		fire_port_intent = true
	elif best_side_str == "starboard":
		fire_stbd_intent = true
	else:
		return false

	recently_fired = true
	currently_repositioning = true
	reposition_timer = randf_range(_Evaluator.REPOSITION_DURATION_MIN, _Evaluator.REPOSITION_DURATION_MAX)
	post_fire_lockout_timer = _Evaluator.POST_FIRE_LOCKOUT

	var away: float = -1.0 if bearing_to_target_deg >= 0.0 else 1.0
	reposition_turn_dir = away
	_commit_turn(away, reposition_timer)
	if debug_log_events:
		print("[NavalBot] reposition_start dir=%.0f dur=%.2fs" % [away, reposition_timer])

	if side_switch_cooldown_timer <= 0.0:
		var prev: String = preferred_side
		preferred_side = best_side_str
		side_switch_cooldown_timer = _Evaluator.SIDE_SWITCH_COOLDOWN
		if debug_log_events and prev != best_side_str and prev != "none":
			print("[NavalBot] side_switch %s -> %s (fired)" % [prev, best_side_str])

	if debug_log_events:
		print("[NavalBot] FIRE %s  quality=%.2f  dist=%.0f  bearing=%.1f" % [
			best_side_str, float(broadside_result.get("best_quality", 0.0)), distance_to_target, bearing_to_target_deg,
		])
	return true


## Heading control while lining up a delayed shot (same geometry as establish broadside).
func _steer_for_broadside_on_side(side_to_use: String) -> void:
	if target_dict.is_empty() or agent == null:
		return
	var target_pos: Vector2 = Vector2(float(target_dict.get("wx", 0.0)), float(target_dict.get("wy", 0.0)))
	var ship_pos: Vector2 = agent.get_ship_pos()
	var ship_dir: Vector2 = agent.get_ship_dir()
	var to_tgt: Vector2 = (target_pos - ship_pos)
	if to_tgt.length_squared() < 1.0:
		return
	var to_tgt_n: Vector2 = to_tgt.normalized()
	var use_side: String = side_to_use
	if use_side != "port" and use_side != "starboard":
		use_side = str(broadside_result.get("target_side", "port"))
	var desired_dir: Vector2 = to_tgt_n.rotated(-PI * 0.5) if use_side == "port" else to_tgt_n.rotated(PI * 0.5)
	var cross_val: float = ship_dir.cross(desired_dir)
	var steer_dir: float = clampf(cross_val * 14.0, -1.0, 1.0)
	if absf(steer_dir) < 0.38 and absf(cross_val) > 1e-4:
		steer_dir = signf(cross_val) * 0.38
	_commit_turn(steer_dir, 0.22)
	if range_band == _Evaluator.RangeBand.PREFERRED:
		desired_sail_state = 2
	else:
		desired_sail_state = 3


func _try_reposition(_delta: float) -> bool:
	if not currently_repositioning:
		return false
	current_bt_state = "reposition"
	last_maneuver = "reposition"
	# Continue committed turn.
	_set_steer(reposition_turn_dir)
	desired_sail_state = 2  # HALF — moderate speed during reposition
	fire_block_reason = "repositioning"
	return true


func _try_establish_broadside(_delta: float) -> bool:
	var target_pos: Vector2 = Vector2(float(target_dict.get("wx", 0.0)), float(target_dict.get("wy", 0.0)))
	var ship_pos: Vector2 = agent.get_ship_pos()
	var ship_dir: Vector2 = agent.get_ship_dir()
	var to_tgt: Vector2 = (target_pos - ship_pos)
	if to_tgt.length_squared() < 1.0:
		return false

	current_bt_state = "establish_broadside"
	last_maneuver = "broadside_setup"

	# Figure out which side to present.
	var side_to_use: String = str(broadside_result.get("best_side", "none"))
	if side_to_use == "none":
		side_to_use = str(broadside_result.get("target_side", "port"))
	# Respect side preference cooldown.
	if preferred_side != "none" and side_switch_cooldown_timer > 0.0:
		side_to_use = preferred_side

	# Compute desired heading: we want the target at 90° (beam).
	var to_tgt_n: Vector2 = to_tgt.normalized()
	var desired_dir: Vector2
	if side_to_use == "port":
		# Target on port → rotate heading so port beam faces target.
		desired_dir = to_tgt_n.rotated(-PI * 0.5)
	else:
		# Target on starboard → rotate heading so stbd beam faces target.
		desired_dir = to_tgt_n.rotated(PI * 0.5)

	# Steer toward desired heading (proportional + floor — avoids dead zone where AI outputs 0 and drifts).
	var cross_val: float = ship_dir.cross(desired_dir)
	var steer_dir: float = clampf(cross_val * 14.0, -1.0, 1.0)
	if absf(steer_dir) < 0.4 and absf(cross_val) > 1e-4:
		steer_dir = signf(cross_val) * 0.4
	_commit_turn(steer_dir, 0.22)

	# Speed: HALF in preferred range, FULL if far.
	if range_band == _Evaluator.RangeBand.PREFERRED:
		desired_sail_state = 2  # HALF
	else:
		desired_sail_state = 3  # FULL

	fire_block_reason = "aligning"
	return true


func _try_approach(_delta: float) -> bool:
	current_bt_state = "approach"
	last_maneuver = "approach"

	var target_pos: Vector2 = Vector2(float(target_dict.get("wx", 0.0)), float(target_dict.get("wy", 0.0)))
	var ship_pos: Vector2 = agent.get_ship_pos()
	var ship_dir: Vector2 = agent.get_ship_dir()

	# Offset approach — not direct head-on.
	var to_tgt: Vector2 = (target_pos - ship_pos)
	if to_tgt.length_squared() < 1.0:
		return false
	var to_tgt_n: Vector2 = to_tgt.normalized()
	# Apply a 15–20° offset to avoid nose chase.
	var offset: float = deg_to_rad(18.0)
	var approach_dir: Vector2 = to_tgt_n.rotated(offset if randf() > 0.5 else -offset)

	var cross_val: float = ship_dir.cross(approach_dir)
	var steer_dir: float = clampf(cross_val * 12.0, -1.0, 1.0)
	if absf(steer_dir) < 0.4 and absf(cross_val) > 1e-4:
		steer_dir = signf(cross_val) * 0.4
	_commit_turn(steer_dir, 0.22)

	desired_sail_state = 3  # FULL
	fire_block_reason = "approaching"
	return true


func _hold_pattern(_delta: float) -> void:
	current_bt_state = "hold"
	last_maneuver = "circling"
	# Gentle turn to keep moving.
	if turn_commit_timer <= 0.0:
		_commit_turn(1.0, 3.0)
	_set_steer(turn_commit_direction)
	desired_sail_state = 2  # HALF
	fire_block_reason = "holding"


# ═══════════════════════════════════════════════════════════════════════
#  Steering helpers with anti-jitter
# ═══════════════════════════════════════════════════════════════════════

## Commit to a turn direction for a minimum duration.
func _commit_turn(direction: float, min_duration: float) -> void:
	if turn_commit_timer > 0.0:
		# Break out early if we committed hard one way but geometry now needs the opposite (overshoot).
		var opp: bool = signf(direction) != signf(turn_commit_direction)
		if opp and absf(direction) > 0.45 and absf(turn_commit_direction) > 0.45:
			turn_commit_timer = 0.0
		else:
			_set_steer(turn_commit_direction)
			return
	turn_commit_direction = direction
	turn_commit_timer = maxf(min_duration, _Evaluator.TURN_COMMIT_DURATION * 0.5)
	_set_steer(direction)


## Set raw steer outputs.
func _set_steer(direction: float) -> void:
	if direction < -0.01:
		steer_left = minf(absf(direction), 1.0)
		steer_right = 0.0
	elif direction > 0.01:
		steer_left = 0.0
		steer_right = minf(absf(direction), 1.0)
	else:
		steer_left = 0.0
		steer_right = 0.0


# ═══════════════════════════════════════════════════════════════════════
#  Debug info
# ═══════════════════════════════════════════════════════════════════════

func get_debug_text() -> String:
	var lines: Array = []
	lines.append("BT: %s" % current_bt_state)
	lines.append("Maneuver: %s" % last_maneuver)
	lines.append("Dist: %.0f  Bearing: %.1f°" % [distance_to_target, bearing_to_target_deg])
	lines.append("Quality P:%.2f S:%.2f" % [
		float(broadside_result.get("quality_port", 0.0)),
		float(broadside_result.get("quality_stbd", 0.0)),
	])
	lines.append("Best: %s %.2f" % [
		str(broadside_result.get("best_side", "none")),
		float(broadside_result.get("best_quality", 0.0)),
	])
	var port_bat: Variant = agent.get_battery_port() if agent != null else null
	var stbd_bat: Variant = agent.get_battery_stbd() if agent != null else null
	var p_state: String = port_bat.state_display() if port_bat != null else "?"
	var s_state: String = stbd_bat.state_display() if stbd_bat != null else "?"
	lines.append("Bat P:%s S:%s" % [p_state, s_state])
	lines.append("Range: %s" % _Evaluator.band_name(range_band))
	lines.append("Block: %s" % fire_block_reason)
	if currently_repositioning:
		lines.append("Repo: %.1fs" % reposition_timer)
	if stuck_timer > 1.0:
		lines.append("Stuck: %.1fs" % stuck_timer)
	lines.append("Sail: %d  Steer: L%.1f R%.1f" % [desired_sail_state, steer_left, steer_right])
	return "\n".join(lines)
