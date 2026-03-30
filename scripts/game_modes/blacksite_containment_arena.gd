extends "res://scripts/iso_arena.gd"

# Open-sea sailing mode on the iso arena baseline (pirate ship sprites, helm + sail).

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const MapProfile := preload("res://scripts/shared/blacksite_map_profile.gd")
const _SailController := preload("res://scripts/shared/sail_controller.gd")
const _HelmController := preload("res://scripts/shared/helm_controller.gd")
const _MotionStateResolver := preload("res://scripts/shared/motion_state_resolver.gd")
const _BatteryController := preload("res://scripts/shared/battery_controller.gd")
const _CannonBallistics := preload("res://scripts/shared/cannon_ballistics.gd")
const _LocalSimController := preload("res://scripts/shared/local_sim_controller.gd")
const _NavalBotController := preload("res://scripts/shared/naval_bot_controller.gd")

## Emitted when local ship linear motion classification or turn flags change (req-motion-fsm §9).
signal motion_state_changed(prev_linear: int, new_linear: int, is_turning: bool, is_turning_hard: bool)
## Forwards BatteryController state transitions with battery reference (req-battery-fsm §8).
signal battery_fsm_state_changed(battery: _BatteryController, new_state: _BatteryController.BatteryState)

var _map_layout: Dictionary = {}
var _projectiles: Array[Dictionary] = []
## Transient water splashes from cannonballs: { wx, wy, t }
var _splash_fx: Array[Dictionary] = []
## Hull impacts: { wx, wy, h, t } — shows strike/sparks where the ball met the ship.
var _hull_strike_fx: Array[Dictionary] = []
## Muzzle effects: { wx, wy, dirx, diry, t }
var _muzzle_flash_fx: Array[Dictionary] = []
## Smoke effects: { wx, wy, t }
var _muzzle_smoke_fx: Array[Dictionary] = []
var _sfx_player: AudioStreamPlayer = null
var _pad_fire_prev: bool = false
var _motion_sig_init: bool = false
var _prev_motion_linear: int = 0
var _prev_motion_turn: bool = false
var _prev_motion_turn_hard: bool = false
var _zoom_in_button: Button = null
var _zoom_out_button: Button = null
## When unlocked, viewport center tracks this world point (ship is not re-centered each frame).
var _camera_world_anchor: Vector2 = Vector2.ZERO
## When true, view follows local ship each frame. Default off until 1/Home/Tab.
var _camera_locked: bool = false
var _middle_drag_active: bool = false
var _middle_drag_prev: Vector2 = Vector2.ZERO
## Reused helm clone so ship arc preview runs identical process_steer() to gameplay.
var _helm_arc_sim: _HelmController = null
## Bot integration: arrays for multi-bot support.  (req-ai-naval-bot-v1)
var _bot_controllers: Array = []   # Array[NavalBotController]
var _bot_agents: Array = []        # Array[BotShipAgent]
var _bot_indices: Array[int] = []  # indices into _players
var _is_local_sim: bool = false

@export_group("Local sim (req-local-sim-v1)")
@export var local_sim_enabled: bool = true
@export_range(1, 4, 1) var local_sim_bot_count: int = 3

@export_group("Combat debug (req-debug-combat-v1)")
@export var combat_debug_hud_enabled: bool = false  # agent state panels; F3 to expand (debug builds)
@export var combat_debug_world_draw: bool = false
@export var combat_debug_log: bool = false

const CAMERA_LOCK_ACTION: String = "bf_camera_lock"

const SAIL_RAISE_ACTION: String = "bf_sail_raise"
const SAIL_LOWER_ACTION: String = "bf_sail_lower"
const BROADSIDE_PORT_ACTION: String = "bf_broadside_port"
const BROADSIDE_STBD_ACTION: String = "bf_broadside_stbd"
const FIRE_MODE_ACTION: String = "bf_fire_mode"
const AUTOFIRE_ACTION: String = "bf_autofire"
const WHEEL_LOCK_ACTION: String = "bf_wheel_lock"
const ELEV_UP_ACTION: String = "bf_elev_up"
const ELEV_DOWN_ACTION: String = "bf_elev_down"
## Min dot(aim, direction_to_opponent) to treat opponent as aim target for battery range (req-battery-fsm §6).
const _BATTERY_AIM_ALIGN_DOT: float = 0.35

## Forward motion — heavy hull: low drag so speed carries (momentum).
const MOTION_DECEL_ABOVE_TARGET: float = 0.95
const MOTION_PASSIVE_DRAG_K: float = 0.025
const COAST_DRAG_MULT: float = 2.0
const MOTION_ZERO_SAIL_DRAG: float = 0.04
## Rudder bleeds forward speed (scaled for naval speeds).
const MOTION_TURNING_SPEED_LOSS: float = 0.03
const MOTION_HARD_TURN_SPEED_LOSS: float = 0.05
const MOTION_HARD_TURN_RUDDER: float = 0.9
const PROJECTILE_DAMAGE: float = 25.0
## Hull integrity: each cannon shell that strikes the hull removes 1 hit.
const HULL_HITS_MAX: float = 6.0
const _STICK_DEADZONE: float = 0.2
const _SPLASH_DURATION: float = 0.42
const _HULL_STRIKE_DURATION: float = 0.4
const _PROJECTILE_HIT_ARM_TIME: float = 0.12
const _MUZZLE_FLASH_DURATION: float = 0.15
const _MUZZLE_SMOKE_DURATION: float = 2.0
const _METERS_PER_WORLD_UNIT: float = 1.0
const _KNOTS_PER_METER_PER_SEC: float = 1.94384
const _ZOOM_STEP_FINE: float = 0.02
const RESPAWN_DELAY_SEC: float = 5.0

func _load_geo_map() -> void:
	_map_layout = MapProfile.configure_renderer(_terrain_renderer)
	_terrain_renderer.chunk_size = CHUNK_SIZE
	var data: Dictionary = {
		"width": int(_map_layout.get("map_width", MapProfile.MAP_WIDTH)),
		"height": int(_map_layout.get("map_height", MapProfile.MAP_HEIGHT)),
	}
	_projectiles.clear()
	_splash_fx.clear()
	_hull_strike_fx.clear()
	_muzzle_flash_fx.clear()
	_muzzle_smoke_fx.clear()
	_SPAWNS = MapProfile.build_drone_spawns(data)


## Top-down pixel scale: 1 world unit = this many screen pixels at zoom 1.0.
const _TD_SCALE: float = 4.0

func _w2s(wx: float, wy: float) -> Vector2:
	return _origin + Vector2(wx, wy) * _TD_SCALE * _zoom

func _dir_screen(dx: float, dy: float) -> Vector2:
	var v := Vector2(dx, dy)
	return v.normalized() if v.length_squared() > 0.001 else Vector2.DOWN


## Screen position of the drawn hull (deck lift + bob) — matches visible ship, not raw wx/wy waterline.
func _hull_visual_screen_pos(p: Dictionary) -> Vector2:
	var sp: Vector2 = _w2s(float(p.wx), float(p.wy))
	var bob: float = sin(float(p.get("walk_time", 0.0)) * 3.0) * 1.4 if bool(p.get("moving", false)) else 0.0
	var v_lift_px: float = NC.SHIP_DECK_HEIGHT_UNITS * _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
	return sp + Vector2(0.0, -v_lift_px + (-2.0 + bob) * _zoom)


func _ready() -> void:
	super._ready()
	_zoom = NC.NAVAL_DEFAULT_ZOOM
	_init_blacksite_movement_state()
	_spawn_local_sim_bot_if_needed()
	_camera_world_anchor = MapProfile.get_default_view_focus(_map_layout)
	_ensure_audio_player()
	_ensure_zoom_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom + _ZOOM_STEP_FINE, _ZOOM_MIN, _ZOOM_MAX)
				queue_redraw()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom - _ZOOM_STEP_FINE, _ZOOM_MIN, _ZOOM_MAX)
				queue_redraw()
				return
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				_middle_drag_active = true
				_middle_drag_prev = event.position
				if _camera_locked and not _players.is_empty():
					var mp: Dictionary = _players[_my_index]
					_camera_world_anchor = Vector2(float(mp.wx), float(mp.wy))
				_camera_locked = false
				return
		else:
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				_middle_drag_active = false
				return
	if event is InputEventMouseMotion and _middle_drag_active:
		var delta_px: Vector2 = event.position - _middle_drag_prev
		_middle_drag_prev = event.position
		var world_scale: float = _TD_SCALE * _zoom
		if world_scale > 0.001:
			_camera_world_anchor -= delta_px / world_scale
		queue_redraw()
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_HOME or event.keycode == KEY_TAB or event.keycode == KEY_1:
			_camera_locked = true
			queue_redraw()
			return
		if OS.is_debug_build() and not event.echo:
			if event.keycode == KEY_F3:
				combat_debug_hud_enabled = not combat_debug_hud_enabled
				for c in _bot_controllers:
					if c != null:
						c.show_debug_hud_panel = combat_debug_hud_enabled
				queue_redraw()
				return
			if event.keycode == KEY_F4:
				combat_debug_world_draw = not combat_debug_world_draw
				queue_redraw()
				return
	super._unhandled_input(event)


func _init_blacksite_movement_state() -> void:
	for p in _players:
		p["health"] = HULL_HITS_MAX
		p.erase("respawn_timer")
		_apply_naval_controllers_to_ship(p)


## Sail/helm/batteries/motion — quarter sail deployed at max quarter speed.
func _apply_naval_controllers_to_ship(p: Dictionary) -> void:
	var sail := _SailController.new()
	sail.max_speed = NC.MAX_SPEED
	sail.sail_raise_rate = 0.22
	sail.sail_lower_rate = 0.28
	sail.sail_state = _SailController.SailState.QUARTER
	sail.current_sail_level = 0.25
	p["sail"] = sail
	var helm := _HelmController.new()
	helm.wheel_spin_accel = 3.0
	helm.wheel_max_spin = 1.08
	helm.wheel_friction = 5.1
	helm.rudder_follow_rate = 0.78
	p["helm"] = helm
	p["move_speed"] = NC.QUARTER_SPEED
	p["angular_velocity"] = 0.0
	p["aim_broadside_port"] = true
	p["aim_dir"] = Vector2(p.dir.x, p.dir.y)
	var motion: _MotionStateResolver = _MotionStateResolver.new()
	motion.max_speed_ref = NC.MAX_SPEED
	motion.idle_speed_threshold = 1.35
	motion.accel_threshold = 2.7
	motion.cruise_threshold = 2.25
	motion.coast_speed_threshold = 1.8
	motion.decel_threshold = 2.7
	p["motion"] = motion
	var bat_p: _BatteryController = _BatteryController.new()
	bat_p.side = _BatteryController.BatterySide.PORT
	bat_p.cannon_count = 8
	bat_p.reload_time = NC.RELOAD_TIME_SEC
	bat_p.fire_sequence_duration = 2.4
	bat_p.battery_damage = 75.0
	bat_p.firing_arc_degrees = NC.BROADSIDE_HALF_ARC_DEG
	bat_p.max_range = NC.MAX_CANNON_RANGE
	bat_p.fire_mode = _BatteryController.FireMode.RIPPLE
	p["battery_port"] = bat_p
	var bat_s: _BatteryController = _BatteryController.new()
	bat_s.side = _BatteryController.BatterySide.STARBOARD
	bat_s.cannon_count = 8
	bat_s.reload_time = NC.RELOAD_TIME_SEC
	bat_s.fire_sequence_duration = 2.4
	bat_s.battery_damage = 75.0
	bat_s.firing_arc_degrees = NC.BROADSIDE_HALF_ARC_DEG
	bat_s.max_range = NC.MAX_CANNON_RANGE
	bat_s.fire_mode = _BatteryController.FireMode.RIPPLE
	p["battery_stbd"] = bat_s
	p["helm_state_prev"] = -1
	bat_p.battery_state_changed.connect(func(s, ns): _forward_battery_state(bat_p, s, ns))
	bat_s.battery_state_changed.connect(func(s, ns): _forward_battery_state(bat_s, s, ns))


func _forward_battery_state(bat: _BatteryController, _side: _BatteryController.BatterySide, new_state: _BatteryController.BatteryState) -> void:
	battery_fsm_state_changed.emit(bat, new_state)


# ═══════════════════════════════════════════════════════════════════════
#  Bot spawning & tick  (req-ai-naval-bot-v1, req-local-sim-v1)
# ═══════════════════════════════════════════════════════════════════════

## Spawn local-sim bots (default 3) on a square around the player (no multiplayer peer).
## Removes the dummy P2 that the base class creates in offline mode.
func _spawn_local_sim_bot_if_needed() -> void:
	_is_local_sim = not multiplayer.has_multiplayer_peer()
	if not _is_local_sim or not local_sim_enabled:
		return
	if _players.size() < 1:
		return

	# Remove the dummy P2 placeholder the base class created for offline mode.
	# Keep only the player at _my_index (always 0 in offline).
	while _players.size() > 1:
		_players.pop_back()

	var player_dict: Dictionary = _players[_my_index]
	var sim := _LocalSimController.new()
	sim.local_sim_enabled = local_sim_enabled
	var bot_count: int = clampi(local_sim_bot_count, 1, 4)

	for bot_i in range(bot_count):
		var bot_dict: Dictionary = sim.create_bot_entry(player_dict, bot_i)
		_players.append(bot_dict)
		var idx: int = _players.size() - 1
		_bot_indices.append(idx)

		# Initialize movement controllers on the bot — same as player init.
		var p: Dictionary = _players[idx]
		_init_bot_controllers(p)

		# Create the BotShipAgent wrapper and NavalBotController.
		var agent := BotShipAgent.new()
		agent.name = "BotShipAgent_%d" % bot_i
		agent.ship_dict = p
		add_child(agent)
		_bot_agents.append(agent)

		var controller := _NavalBotController.new()
		controller.name = "NavalBot_%d" % bot_i
		controller.agent = agent
		controller.target_dict = player_dict
		controller.debug_log_events = combat_debug_log
		controller.show_debug_hud_panel = combat_debug_hud_enabled
		add_child(controller)
		_bot_controllers.append(controller)

		print("[LocalSim] Bot %d (%s) spawned at (%.0f, %.0f)" % [bot_i, p.label, p.wx, p.wy])


## Set up sail, helm, batteries, and motion resolver on a bot dictionary entry.
func _init_bot_controllers(p: Dictionary) -> void:
	p["health"] = HULL_HITS_MAX
	p.erase("respawn_timer")
	_apply_naval_controllers_to_ship(p)


## Find the bot controller for a given _players index.
func _get_bot_controller_for_index(player_idx: int) -> Variant:
	for i in range(_bot_indices.size()):
		if _bot_indices[i] == player_idx:
			if i < _bot_controllers.size():
				return _bot_controllers[i]
	return null


## Tick the bot ship: run AI decision, then apply intents through identical physics.
func _tick_bot(p: Dictionary, player_idx: int, delta: float) -> void:
	if not bool(p.get("alive", false)):
		return
	var bot_ctrl: Variant = _get_bot_controller_for_index(player_idx)
	if bot_ctrl == null:
		return

	# --- AI decision ---
	bot_ctrl.update(delta)

	# --- Apply bot intents to controllers ---
	var helm: Variant = p.get("helm")
	if helm == null:
		return
	var sail: Variant = p.get("sail")
	if sail == null:
		return

	# Steer: feed bot's steer intents to helm the same way player input does.
	helm.process_steer(delta, bot_ctrl.steer_left, bot_ctrl.steer_right)

	# Sail: drive toward desired sail state.
	var target_state: int = bot_ctrl.desired_sail_state
	var current_state: int = int(sail.sail_state)
	if target_state > current_state:
		sail.raise_step()
	elif target_state < current_state:
		sail.lower_step()
	sail.process(delta)

	# --- Heading rotation (identical to _tick_player physics) ---
	var hull: Vector2 = Vector2(p.dir.x, p.dir.y)
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var ang_vel: float = float(p.get("angular_velocity", 0.0))
	var spd_for_turn: float = float(p.get("move_speed", 0.0))
	var turn_deg: float = NC.turn_rate_deg_for_speed(spd_for_turn)
	var max_turn_rad: float = deg_to_rad(turn_deg)
	# Bots often start at 0 speed while the BT tries to align; player steer_auth would stay ~0 and
	# they never yaw. Floor keeps rudder effective until move_speed builds.
	var steer_auth: float = maxf(0.78, clampf(spd_for_turn / 8.25, 0.0, 1.0))
	var target_av: float = max_turn_rad * helm.rudder_angle * steer_auth
	var tau: float = NC.HELM_TURN_LAG_SEC
	ang_vel = lerpf(ang_vel, target_av, 1.0 - exp(-delta / tau))
	hull = hull.rotated(ang_vel * delta).normalized()
	p.dir = hull
	p["angular_velocity"] = ang_vel

	# --- Speed physics (identical to _tick_player) ---
	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match sail.sail_state:
		_SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED
		_SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED
		_SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED
		_:
			target_cap = NC.SAILS_DOWN_DRIFT_SPEED
			sails_provide_thrust = false

	var spd: float = float(p.get("move_speed", 0.0))
	var drag_mult: float = COAST_DRAG_MULT if sail.current_sail_level < sail.coast_drag_threshold else 1.0
	var rud_abs: float = absf(helm.rudder_angle)
	var accel_r: float = NC.accel_rate()
	var decel_r: float = NC.decel_rate_sails()
	var drift_floor: float = NC.SAILS_DOWN_DRIFT_SPEED if not sails_provide_thrust and spd > 0.01 else 0.0

	if spd < target_cap and sails_provide_thrust:
		spd = minf(spd + accel_r * delta, target_cap)
	elif spd > target_cap and sails_provide_thrust:
		spd = maxf(0.0, spd - decel_r * drag_mult * delta)

	spd = maxf(drift_floor, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * delta)
	if sail.current_sail_level < sail.coast_drag_threshold:
		spd = maxf(drift_floor, spd - MOTION_ZERO_SAIL_DRAG * drag_mult * delta)

	spd = maxf(drift_floor, spd - rud_abs * MOTION_TURNING_SPEED_LOSS * delta)
	if rud_abs > MOTION_HARD_TURN_RUDDER:
		spd = maxf(drift_floor, spd - rud_abs * MOTION_HARD_TURN_SPEED_LOSS * delta)

	spd = clampf(spd, 0.0, NC.MAX_SPEED * 1.05)
	p["move_speed"] = spd

	# --- Position update ---
	var dir_wx: float = p.dir.x
	var dir_wy: float = p.dir.y
	var dlen_sq: float = dir_wx * dir_wx + dir_wy * dir_wy
	if dlen_sq > 0.0001:
		var inv: float = 1.0 / sqrt(dlen_sq)
		dir_wx *= inv
		dir_wy *= inv
	else:
		dir_wx = 1.0
		dir_wy = 0.0

	if spd > 0.02:
		var new_wx: float = p.wx + dir_wx * spd * delta
		var new_wy: float = p.wy + dir_wy * spd * delta
		if _naval_tile_walkable(new_wx, new_wy):
			p.wx = new_wx
			p.wy = new_wy
		p.moving = true
		p.walk_time += delta
	else:
		p.moving = false

	# --- Battery processing with bot fire intents ---
	var hull_n: Vector2 = Vector2(p.dir.x, p.dir.y)
	if hull_n.length_squared() < 0.0001:
		hull_n = Vector2.RIGHT
	hull_n = hull_n.normalized()
	# Bot broadside aim: point at the target's current side.
	var aim_n: Vector2 = hull_n.rotated(PI * 0.5) if bool(p.get("aim_broadside_port", true)) else hull_n.rotated(-PI * 0.5)
	p["aim_dir"] = aim_n

	var ship_pos := Vector2(float(p.wx), float(p.wy))
	var port_bat: Variant = p.get("battery_port")
	var stbd_bat: Variant = p.get("battery_stbd")
	var max_bat_range: float = NC.MAX_CANNON_RANGE
	if port_bat != null:
		max_bat_range = maxf(max_bat_range, port_bat.max_range)
	if stbd_bat != null:
		max_bat_range = maxf(max_bat_range, stbd_bat.max_range)
	var target_dist_m: float = _battery_target_distance_m(p, aim_n, max_bat_range)
	p["_naval_acc_dist"] = target_dist_m
	p["_naval_spd"] = spd

	# Fire intent: bot controller decides which side.
	var fire_port: bool = bot_ctrl.fire_port_intent
	var fire_stbd: bool = bot_ctrl.fire_stbd_intent
	var fired_any: bool = false

	if port_bat != null:
		var port_aim: Vector2 = hull_n.rotated(PI * 0.5)
		for spread in port_bat.process_frame(delta, hull_n, port_aim, ship_pos, fire_port, target_dist_m):
			_fire_projectile(p, spread, port_bat.damage_per_shot_for_current_mode(), port_aim, port_bat)
			fired_any = true
	if stbd_bat != null:
		var stbd_aim: Vector2 = hull_n.rotated(-PI * 0.5)
		for spread in stbd_bat.process_frame(delta, hull_n, stbd_aim, ship_pos, fire_stbd, target_dist_m):
			_fire_projectile(p, spread, stbd_bat.damage_per_shot_for_current_mode(), stbd_aim, stbd_bat)
			fired_any = true

	if fired_any:
		p.atk_time = ATK_DUR
		p.hit_landed = false
	p.atk_time = maxf(p.atk_time - delta, 0.0)

	# --- Update aim side based on target bearing ---
	var target_pos: Vector2 = Vector2(float(bot_ctrl.target_dict.get("wx", 0.0)), float(bot_ctrl.target_dict.get("wy", 0.0)))
	var to_target: Vector2 = target_pos - ship_pos
	if to_target.length_squared() > 1.0:
		var cross_val: float = hull_n.cross(to_target.normalized())
		p["aim_broadside_port"] = cross_val > 0.0


func _battery_target_distance_m(attacker: Dictionary, aim_n: Vector2, max_range: float) -> float:
	var ship := Vector2(float(attacker.wx), float(attacker.wy))
	var my_peer: int = int(attacker.get("peer_id", -999999))
	var saw_other: bool = false
	var best: float = INF
	for q in _players:
		if int(q.get("peer_id", -888888)) == my_peer:
			continue
		if not bool(q.get("alive", true)):
			continue
		saw_other = true
		var to_q: Vector2 = Vector2(float(q.wx), float(q.wy)) - ship
		var dist: float = to_q.length()
		if dist > max_range or dist < 0.05:
			continue
		var align: float = to_q.normalized().dot(aim_n)
		if align < _BATTERY_AIM_ALIGN_DOT:
			continue
		best = minf(best, dist)
	if not saw_other:
		return -1.0
	if best >= INF:
		return max_range + 1.0
	return best


func _register_inputs() -> void:
	_set_action_keys(_ACTIONS.left, [KEY_A])
	_set_action_keys(_ACTIONS.right, [KEY_D])
	# No keyboard strafe: hull turns with A/D (helm); forward is always along heading.
	_clear_action_input_events(_ACTIONS.up)
	_clear_action_input_events(_ACTIONS.down)
	_set_action_keys(_ACTIONS.atk, [KEY_F])
	_ensure_joy_button_for_action(_ACTIONS.atk, JOY_BUTTON_X)

	_set_action_keys(BROADSIDE_PORT_ACTION, [KEY_E, KEY_LEFT])
	_set_action_keys(BROADSIDE_STBD_ACTION, [KEY_Q, KEY_RIGHT])
	_ensure_joy_button_for_action(BROADSIDE_PORT_ACTION, JOY_BUTTON_LEFT_SHOULDER)
	_ensure_joy_button_for_action(BROADSIDE_STBD_ACTION, JOY_BUTTON_RIGHT_SHOULDER)

	_set_action_keys(FIRE_MODE_ACTION, [KEY_B])
	_ensure_joy_button_for_action(FIRE_MODE_ACTION, JOY_BUTTON_BACK)
	_set_action_keys(WHEEL_LOCK_ACTION, [KEY_C])
	_ensure_joy_button_for_action(WHEEL_LOCK_ACTION, JOY_BUTTON_Y)
	_set_action_keys(ELEV_UP_ACTION, [KEY_R])
	_set_action_keys(ELEV_DOWN_ACTION, [KEY_T])

	if not InputMap.has_action(SAIL_RAISE_ACTION):
		InputMap.add_action(SAIL_RAISE_ACTION)
	if not InputMap.has_action(SAIL_LOWER_ACTION):
		InputMap.add_action(SAIL_LOWER_ACTION)
	_set_action_keys(SAIL_RAISE_ACTION, [KEY_W])
	_set_action_keys(SAIL_LOWER_ACTION, [KEY_S])
	_ensure_joy_button_for_action(SAIL_RAISE_ACTION, JOY_BUTTON_RIGHT_STICK)
	_ensure_joy_button_for_action(SAIL_LOWER_ACTION, JOY_BUTTON_LEFT_STICK)


func _clear_action_input_events(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)


func _set_action_keys(action: String, keys: Array[Key]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for keycode in keys:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		InputMap.action_add_event(action, ev)

func _set_action_mouse_buttons(action: String, buttons: Array[MouseButton]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			InputMap.action_erase_event(action, ev)
	for button_index in buttons:
		var ev := InputEventMouseButton.new()
		ev.button_index = button_index
		InputMap.action_add_event(action, ev)

const _CAM_PAN_SPEED: float = 900.0

func _process(delta: float) -> void:
	super._process(delta)
	for bi in _bot_indices:
		if bi >= 0 and bi < _players.size():
			_tick_bot(_players[bi], bi, delta)
	_tick_projectiles(delta)
	_tick_splash_fx(delta)
	_tick_hull_strike_fx(delta)
	_tick_muzzle_fx(delta)
	_tick_local_timers(delta)
	_tick_respawn(delta)
	var pan_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP):
		pan_dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pan_dir.y += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		pan_dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		pan_dir.x += 1.0
	if pan_dir.length_squared() > 0.001:
		if _camera_locked and not _players.is_empty():
			var ap: Dictionary = _players[_my_index]
			_camera_world_anchor = Vector2(float(ap.wx), float(ap.wy))
		_camera_locked = false
		var world_scale: float = _TD_SCALE * _zoom
		if world_scale > 0.001:
			_camera_world_anchor += pan_dir.normalized() * _CAM_PAN_SPEED * delta / world_scale
	queue_redraw()

func _steer_strengths(pad_id: int) -> Vector2:
	var steer_l: float = 0.0
	var steer_r: float = 0.0
	if Input.is_action_pressed(_ACTIONS.left):
		steer_l = 1.0
	if Input.is_action_pressed(_ACTIONS.right):
		steer_r = 1.0
	if pad_id >= 0:
		var ax: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
		if ax < -_STICK_DEADZONE:
			steer_l = maxf(steer_l, absf(ax))
		elif ax > _STICK_DEADZONE:
			steer_r = maxf(steer_r, absf(ax))
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_LEFT):
			steer_l = maxf(steer_l, 1.0)
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_RIGHT):
			steer_r = maxf(steer_r, 1.0)
	return Vector2(steer_l, steer_r)


func _tick_player(p: Dictionary, delta: float) -> void:
	if pause_menu_panel != null and pause_menu_panel.visible:
		return
	if not p.alive:
		return

	var pad_id: int = _get_primary_pad_id()
	var steer_lr: Vector2 = _steer_strengths(pad_id)
	var steer_l: float = steer_lr.x
	var steer_r: float = steer_lr.y

	var helm = p.get("helm")
	if helm == null:
		helm = _HelmController.new()
		p["helm"] = helm
	if Input.is_action_just_pressed(WHEEL_LOCK_ACTION):
		var is_locked: bool = helm.toggle_wheel_lock()
		_play_tone(224.0 if is_locked else 164.0, 0.05, 0.12)
	helm.process_steer(delta, steer_l, steer_r)

	var hull: Vector2 = Vector2(p.dir.x, p.dir.y)
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var ang_vel: float = float(p.get("angular_velocity", 0.0))
	var spd_for_turn: float = float(p.get("move_speed", 0.0))
	var turn_deg: float = NC.turn_rate_deg_for_speed(spd_for_turn)
	var max_turn_rad: float = deg_to_rad(turn_deg)
	var steer_auth: float = clampf(spd_for_turn / 8.25, 0.0, 1.0)
	var target_av: float = max_turn_rad * helm.rudder_angle * steer_auth
	var tau: float = NC.HELM_TURN_LAG_SEC
	ang_vel = lerpf(ang_vel, target_av, 1.0 - exp(-delta / tau))
	hull = hull.rotated(ang_vel * delta).normalized()
	p.dir = hull
	p["angular_velocity"] = ang_vel

	_update_broadside_aim(p, pad_id)

	var port_bat = p.get("battery_port")
	var stbd_bat = p.get("battery_stbd")
	if port_bat != null and stbd_bat != null:
		if Input.is_action_just_pressed(FIRE_MODE_ACTION):
			if port_bat.fire_mode == _BatteryController.FireMode.SALVO:
				port_bat.fire_mode = _BatteryController.FireMode.RIPPLE
				stbd_bat.fire_mode = _BatteryController.FireMode.RIPPLE
			else:
				port_bat.fire_mode = _BatteryController.FireMode.SALVO
				stbd_bat.fire_mode = _BatteryController.FireMode.SALVO
			_play_tone(312.0, 0.04, 0.12)
	var elev_up: bool = Input.is_action_pressed(ELEV_UP_ACTION)
	var elev_down: bool = Input.is_action_pressed(ELEV_DOWN_ACTION)
	if elev_up or elev_down:
		var elev_dir: float = 1.0 if elev_up else -1.0
		var sel_elev_key: String = "battery_port" if bool(p.get("aim_broadside_port", true)) else "battery_stbd"
		var elev_bat: Variant = p.get(sel_elev_key)
		if elev_bat != null:
			elev_bat.adjust_elevation(delta, elev_dir)

	var sail = p.get("sail")
	if sail == null:
		sail = _SailController.new()
		sail.max_speed = NC.MAX_SPEED
		p["sail"] = sail
	sail.process(delta)

	if Input.is_action_just_pressed(SAIL_RAISE_ACTION):
		sail.raise_step()
		_play_tone(255.0, 0.04, 0.14)
	if Input.is_action_just_pressed(SAIL_LOWER_ACTION):
		sail.lower_step()
		_play_tone(175.0, 0.04, 0.12)

	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match sail.sail_state:
		_SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED
		_SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED
		_SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED
		_:
			target_cap = NC.SAILS_DOWN_DRIFT_SPEED
			sails_provide_thrust = false

	var spd: float = float(p.get("move_speed", 0.0))
	var drag_mult: float = COAST_DRAG_MULT if sail.current_sail_level < sail.coast_drag_threshold else 1.0
	var rud_abs: float = absf(helm.rudder_angle)
	var accel_r: float = NC.accel_rate()
	var decel_r: float = NC.decel_rate_sails()
	var drift_floor: float = NC.SAILS_DOWN_DRIFT_SPEED if not sails_provide_thrust and spd > 0.01 else 0.0

	if spd < target_cap and sails_provide_thrust:
		spd = minf(spd + accel_r * delta, target_cap)
	elif spd > target_cap and sails_provide_thrust:
		spd = maxf(0.0, spd - decel_r * drag_mult * delta)

	spd = maxf(drift_floor, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * delta)
	if sail.current_sail_level < sail.coast_drag_threshold:
		spd = maxf(drift_floor, spd - MOTION_ZERO_SAIL_DRAG * drag_mult * delta)

	spd = maxf(drift_floor, spd - rud_abs * MOTION_TURNING_SPEED_LOSS * delta)
	if rud_abs > MOTION_HARD_TURN_RUDDER:
		spd = maxf(drift_floor, spd - rud_abs * MOTION_HARD_TURN_SPEED_LOSS * delta)

	spd = clampf(spd, 0.0, NC.MAX_SPEED * 1.05)
	p["move_speed"] = spd

	var motion = p.get("motion")
	if motion != null:
		motion.max_speed_ref = NC.MAX_SPEED
		var lin: int = motion.resolve_linear(spd, target_cap, sail.get_target_sail_level(), sail.current_sail_level)
		var tf: Dictionary = motion.compute_turn_flags(spd, helm.rudder_angle)
		p["linear_motion_state"] = lin
		var turn_b: bool = bool(tf.get("is_turning", false))
		var turn_hb: bool = bool(tf.get("is_turning_hard", false))
		p["motion_is_turning"] = turn_b
		p["motion_is_turning_hard"] = turn_hb
		if _motion_sig_init:
			if lin != _prev_motion_linear or turn_b != _prev_motion_turn or turn_hb != _prev_motion_turn_hard:
				motion_state_changed.emit(_prev_motion_linear, lin, turn_b, turn_hb)
		else:
			_motion_sig_init = true
		_prev_motion_linear = lin
		_prev_motion_turn = turn_b
		_prev_motion_turn_hard = turn_hb

	var helm_st: int = int(helm.get_helm_state())
	if helm_st != int(p.get("helm_state_prev", -1)):
		p["helm_state_prev"] = helm_st

	var dir_wx: float = p.dir.x
	var dir_wy: float = p.dir.y
	var dlen_sq: float = dir_wx * dir_wx + dir_wy * dir_wy
	if dlen_sq > 0.0001:
		var inv: float = 1.0 / sqrt(dlen_sq)
		dir_wx *= inv
		dir_wy *= inv
	else:
		dir_wx = 1.0
		dir_wy = 0.0

	if spd > 0.02:
		var new_wx: float = p.wx + dir_wx * spd * delta
		var new_wy: float = p.wy + dir_wy * spd * delta
		if _naval_tile_walkable(new_wx, new_wy):
			p.wx = new_wx
			p.wy = new_wy
		p.moving = true
		p.walk_time += delta
	else:
		p.moving = false

	var fire_pressed: bool = Input.is_action_pressed(_ACTIONS.atk) or _is_pad_fire_pressed(pad_id)
	var fire_just_pressed: bool = (Input.is_action_just_pressed(_ACTIONS.atk) or (fire_pressed and not _pad_fire_prev))
	_pad_fire_prev = fire_pressed

	var hull_n: Vector2 = Vector2(p.dir.x, p.dir.y)
	if hull_n.length_squared() < 0.0001:
		hull_n = Vector2.RIGHT
	hull_n = hull_n.normalized()
	var aim_n: Vector2 = p.get("aim_dir", hull_n)
	if aim_n.length_squared() < 0.0001:
		aim_n = hull_n
	else:
		aim_n = aim_n.normalized()

	var ship_pos := Vector2(float(p.wx), float(p.wy))
	var port_b = port_bat
	var stbd_b = stbd_bat
	var max_bat_range: float = NC.MAX_CANNON_RANGE
	if port_b != null:
		max_bat_range = maxf(max_bat_range, port_b.max_range)
	if stbd_b != null:
		max_bat_range = maxf(max_bat_range, stbd_b.max_range)
	var target_dist_m: float = _battery_target_distance_m(p, aim_n, max_bat_range)
	p["_naval_acc_dist"] = target_dist_m
	p["_naval_spd"] = spd
	var fire_port_battery: bool = bool(p.get("aim_broadside_port", true))
	var fired_any: bool = false
	if port_b != null:
		var port_aim: Vector2 = hull_n.rotated(PI * 0.5)
		var port_fire: bool = fire_just_pressed and fire_port_battery
		for spread in port_b.process_frame(delta, hull_n, port_aim, ship_pos, port_fire, target_dist_m):
			_fire_projectile(p, spread, port_b.damage_per_shot_for_current_mode(), port_aim, port_b)
			fired_any = true
	if stbd_b != null:
		var stbd_aim: Vector2 = hull_n.rotated(-PI * 0.5)
		var stbd_fire: bool = fire_just_pressed and not fire_port_battery
		for spread in stbd_b.process_frame(delta, hull_n, stbd_aim, ship_pos, stbd_fire, target_dist_m):
			_fire_projectile(p, spread, stbd_b.damage_per_shot_for_current_mode(), stbd_aim, stbd_b)
			fired_any = true

	if fired_any:
		_play_tone(410.0, 0.045, 0.10)
		p.atk_time = ATK_DUR
		p.hit_landed = false
	p.atk_time = maxf(p.atk_time - delta, 0.0)

func _aim_dir_broadside_to_target(hull: Vector2, to_target_n: Vector2, use_port: bool, half_arc_deg: float) -> Vector2:
	var perp: Vector2 = hull.rotated(PI * 0.5) if use_port else hull.rotated(-PI * 0.5)
	var lim: float = deg_to_rad(half_arc_deg)
	var delta: float = atan2(perp.cross(to_target_n), perp.dot(to_target_n))
	delta = clampf(delta, -lim, lim)
	return perp.rotated(delta).normalized()


func _naval_apply_auto_aim(p: Dictionary, hull: Vector2) -> bool:
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	if port_b == null or stbd_b == null:
		return false
	var ship_pos := Vector2(float(p.wx), float(p.wy))
	var my_peer: int = int(p.get("peer_id", -999999))
	var best_dist: float = INF
	var best_to: Vector2 = Vector2.ZERO
	var found: bool = false
	for q in _players:
		if int(q.get("peer_id", -888888)) == my_peer:
			continue
		if not bool(q.get("alive", true)):
			continue
		var to_q: Vector2 = Vector2(float(q.wx), float(q.wy)) - ship_pos
		var d: float = to_q.length()
		if d < 0.05 or d > port_b.max_range:
			continue
		found = true
		if d < best_dist:
			best_dist = d
			best_to = to_q / d
	if not found:
		return false
	var half_arc: float = port_b.firing_arc_degrees
	var aim_port: Vector2 = _aim_dir_broadside_to_target(hull, best_to, true, half_arc)
	var aim_stbd: Vector2 = _aim_dir_broadside_to_target(hull, best_to, false, half_arc)
	var valid_port: bool = port_b.is_target_valid(hull, aim_port, ship_pos, best_dist, true)
	var valid_stbd: bool = stbd_b.is_target_valid(hull, aim_stbd, ship_pos, best_dist, true)
	if valid_port and valid_stbd:
		if aim_port.dot(best_to) >= aim_stbd.dot(best_to):
			p["aim_broadside_port"] = true
			p["aim_dir"] = aim_port
		else:
			p["aim_broadside_port"] = false
			p["aim_dir"] = aim_stbd
		return true
	if valid_port:
		p["aim_broadside_port"] = true
		p["aim_dir"] = aim_port
		return true
	if valid_stbd:
		p["aim_broadside_port"] = false
		p["aim_dir"] = aim_stbd
		return true
	return false


func _update_broadside_aim(p: Dictionary, _pad_id: int) -> void:
	if Input.is_action_just_pressed(BROADSIDE_PORT_ACTION):
		p["aim_broadside_port"] = true
	if Input.is_action_just_pressed(BROADSIDE_STBD_ACTION):
		p["aim_broadside_port"] = false
	var hull := Vector2(p.dir.x, p.dir.y)
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	if bool(p.get("aim_broadside_port", true)):
		p["aim_dir"] = hull.rotated(PI * 0.5)
	else:
		p["aim_dir"] = hull.rotated(-PI * 0.5)


func _is_pad_fire_pressed(pad_id: int) -> bool:
	if pad_id < 0:
		return false
	return Input.get_joy_axis(pad_id, JOY_AXIS_TRIGGER_RIGHT) > 0.35 \
		or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X)

func _is_walkable_tile(tile_id: int) -> bool:
	# Walls/buildings are mountain tiles; everything else is traversable surface.
	return tile_id != IsoTerrainRenderer.T_MOUNTAIN


func _naval_tile_walkable(wx: float, wy: float) -> bool:
	return _is_walkable_tile(_terrain_renderer.get_tile_at_world_units(wx, wy, NC.UNITS_PER_LOGIC_TILE))


func _point_hits_ship_ellipse(point: Vector2, ship: Dictionary) -> bool:
	var hull: Vector2 = Vector2(float(ship.dir.x), float(ship.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var perp: Vector2 = hull.rotated(PI * 0.5)
	var rel: Vector2 = point - Vector2(float(ship.wx), float(ship.wy))
	var fwd: float = rel.dot(hull)
	var lat: float = rel.dot(perp)
	var a: float = NC.SHIP_LENGTH_UNITS * 0.5
	var b: float = NC.SHIP_WIDTH_UNITS * 0.5
	# Slightly relaxed edge for readable hit registration.
	var k: float = (fwd * fwd) / (a * a) + (lat * lat) / (b * b)
	return k <= 1.15


func _resolve_collisions() -> void:
	# Ships may overlap — no separation impulse (naval boarding range).
	pass


func _check_hit(_attacker: Dictionary, _defender: Dictionary) -> void:
	# Disable melee arc checks; combat in Blacksite is ranged projectile-driven.
	return

func _deterministic_spread_deg(distance: float, shooter_speed: float, is_turning: bool, shot_seq: int) -> float:
	var base_deg: float = NC.spread_deg_for_range(distance)
	if is_turning:
		base_deg *= NC.TURNING_SPREAD_MULT
	if shooter_speed >= NC.HIGH_SPEED_THRESHOLD:
		base_deg *= NC.HIGH_SPEED_SPREAD_MULT
	var pattern: Array[float] = [-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0, 0.5, -0.5]
	var idx: int = posmod(shot_seq, pattern.size())
	return base_deg * float(pattern[idx])


func _spawn_muzzle_fx(wx: float, wy: float, dir: Vector2) -> void:
	_muzzle_flash_fx.append({"wx": wx, "wy": wy, "dirx": dir.x, "diry": dir.y, "t": 0.0})
	_muzzle_smoke_fx.append({"wx": wx, "wy": wy, "t": 0.0})

func _fire_projectile(p: Dictionary, spread_bias: float = 0.0, shot_damage: float = PROJECTILE_DAMAGE, aim_override: Variant = null, battery: Variant = null) -> void:
	var dir: Vector2
	if aim_override is Vector2 and aim_override.length_squared() > 0.001:
		dir = aim_override.normalized()
	else:
		dir = p.get("aim_dir", p.dir)
		if dir.length_squared() <= 0.001:
			dir = Vector2(p.dir.x, p.dir.y)
		if dir.length_squared() <= 0.001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
	var owner_peer: int = int(p.get("peer_id", 1))
	if owner_peer <= 0 and multiplayer.has_multiplayer_peer():
		owner_peer = multiplayer.get_unique_id()
	var aim_dist: float = float(p.get("_naval_acc_dist", 200.0))
	if aim_dist < 0.0 or aim_dist > 1e9:
		aim_dist = 200.0
	var aim_spd: float = float(p.get("_naval_spd", 0.0))
	var turning: bool = bool(p.get("motion_is_turning", false))
	var shot_seq: int = int(p.get("shot_seq", 0))
	var spread_deg: float = _deterministic_spread_deg(aim_dist, aim_spd, turning, shot_seq)
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y)).normalized()
	if hull_n.length_squared() < 0.001:
		hull_n = Vector2.RIGHT
	var angle_from_bow: float = rad_to_deg(acos(clampf(hull_n.dot(dir), -1.0, 1.0)))
	var quality: float = NC.broadside_quality(angle_from_bow)
	spread_deg *= (1.0 / maxf(0.1, quality))
	p["shot_seq"] = shot_seq + 1
	var shot_dir: Vector2 = dir.rotated(spread_bias + deg_to_rad(spread_deg)).normalized()
	var muzzle: float = 6.5
	var start_x: float = float(p.wx) + shot_dir.x * muzzle
	var start_y: float = float(p.wy) + shot_dir.y * muzzle
	_spawn_muzzle_fx(start_x, start_y, shot_dir)
	var mass: float = _CannonBallistics.mass_from_damage(shot_damage)
	var elev_deg: float = _CannonBallistics.DEFAULT_ELEVATION_DEG
	if battery != null:
		elev_deg = battery.elevation_degrees()
	var vel: Dictionary = _CannonBallistics.initial_velocity(shot_dir, mass, NC.CANNON_LINE_SPEED_SCALE, elev_deg)
	var vx: float = float(vel.vx)
	var vy: float = float(vel.vy)
	var vz: float = float(vel.vz)
	var hs: float = sqrt(vx * vx + vy * vy)
	var desired_hs: float = NC.PROJECTILE_SPEED * lerpf(1.1, 0.85, clampf((mass - 0.5) / 1.25, 0.0, 1.0))
	if hs > 0.001:
		var s: float = desired_hs / hs
		vx *= s
		vy *= s
		vz *= s
	if multiplayer.has_multiplayer_peer():
		_spawn_cannonball_rpc.rpc(
			start_x,
			start_y,
			vx,
			vy,
			vz,
			_CannonBallistics.MUZZLE_HEIGHT,
			mass,
			owner_peer,
			shot_damage
		)
	else:
		_spawn_cannonball_local(
			start_x,
			start_y,
			vx,
			vy,
			vz,
			_CannonBallistics.MUZZLE_HEIGHT,
			mass,
			owner_peer,
			shot_damage
		)


@rpc("any_peer", "call_local", "reliable")
func _spawn_cannonball_rpc(
		wx: float,
		wy: float,
		vx: float,
		vy: float,
		vz: float,
		h: float,
		mass: float,
		owner_peer: int,
		damage: float
	) -> void:
	_spawn_cannonball_local(wx, wy, vx, vy, vz, h, mass, owner_peer, damage)


func _spawn_cannonball_local(
		wx: float,
		wy: float,
		vx: float,
		vy: float,
		vz: float,
		h: float,
		mass: float,
		owner_peer: int,
		damage: float
	) -> void:
	_projectiles.append({
		"wx": wx,
		"wy": wy,
		"h": h,
		"vx": vx,
		"vy": vy,
		"vz": vz,
		"mass": mass,
		"t_flight": 0.0,
		"owner_peer": owner_peer,
		"damage": damage,
		"arm_t": _PROJECTILE_HIT_ARM_TIME,
		"alive": true,
	})


func _tick_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var can_apply_hits: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	var grav: float = _CannonBallistics.GRAVITY * NC.PROJECTILE_GRAVITY_SCALE
	var sub: float = _CannonBallistics.PHYSICS_SUBSTEP
	var h_min: float = _CannonBallistics.HULL_HIT_MIN_H
	var h_max: float = _CannonBallistics.HULL_HIT_MAX_H
	var t_max: float = NC.PROJECTILE_LIFETIME

	for i in range(_projectiles.size() - 1, -1, -1):
		var proj: Dictionary = _projectiles[i]
		if not bool(proj.get("alive", true)):
			_projectiles.remove_at(i)
			continue

		var wx: float = float(proj.get("wx", 0.0))
		var wy: float = float(proj.get("wy", 0.0))
		var h: float = float(proj.get("h", 0.0))
		var vx: float = float(proj.get("vx", 0.0))
		var vy: float = float(proj.get("vy", 0.0))
		var vz: float = float(proj.get("vz", 0.0))
		var t_flight: float = float(proj.get("t_flight", 0.0))
		var owner_peer: int = int(proj.get("owner_peer", 0))
		var dmg: float = float(proj.get("damage", PROJECTILE_DAMAGE))
		var arm_t: float = float(proj.get("arm_t", 0.0))

		var time_left: float = delta
		var remove_proj: bool = false

		while time_left > 0.0001 and not remove_proj:
			var dt: float = minf(sub, time_left)
			wx += vx * dt
			wy += vy * dt
			h += vz * dt
			vz -= grav * dt
			t_flight += dt
			time_left -= dt
			arm_t = maxf(0.0, arm_t - dt)

			if t_flight >= t_max:
				remove_proj = true
				break

			if h <= 0.0:
				_spawn_splash_at_world(wx, wy)
				remove_proj = true
				break

			if arm_t > 0.0:
				continue
			for j in range(_players.size()):
				var q: Dictionary = _players[j]
				if not bool(q.get("alive", true)):
					continue
				if int(q.get("peer_id", -1)) == owner_peer:
					continue
				if not _point_hits_ship_ellipse(Vector2(wx, wy), q):
					continue
				if h < h_min or h > h_max:
					continue
				_spawn_hull_strike_fx(wx, wy, h)
				if can_apply_hits:
					var def_peer: int = int(q.get("peer_id", -1))
					if multiplayer.has_multiplayer_peer():
						_apply_cannon_hit.rpc(owner_peer, def_peer, dmg)
					else:
						_apply_cannon_hit_impl(owner_peer, def_peer, dmg)
				remove_proj = true
				break

			if remove_proj:
				break

		if remove_proj:
			_projectiles.remove_at(i)
		else:
			proj["wx"] = wx
			proj["wy"] = wy
			proj["h"] = h
			proj["vx"] = vx
			proj["vy"] = vy
			proj["vz"] = vz
			proj["t_flight"] = t_flight
			proj["arm_t"] = arm_t
			_projectiles[i] = proj


func _spawn_splash_at_world(wx: float, wy: float) -> void:
	_splash_fx.append({"wx": wx, "wy": wy, "t": 0.0})


func _spawn_hull_strike_fx(wx: float, wy: float, impact_h: float) -> void:
	_hull_strike_fx.append({"wx": wx, "wy": wy, "h": impact_h, "t": 0.0})


func _tick_hull_strike_fx(delta: float) -> void:
	if _hull_strike_fx.is_empty():
		return
	for i in range(_hull_strike_fx.size() - 1, -1, -1):
		var s: Dictionary = _hull_strike_fx[i]
		var nt: float = float(s.get("t", 0.0)) + delta
		if nt >= _HULL_STRIKE_DURATION:
			_hull_strike_fx.remove_at(i)
		else:
			s["t"] = nt
			_hull_strike_fx[i] = s


func _tick_muzzle_fx(delta: float) -> void:
	for i in range(_muzzle_flash_fx.size() - 1, -1, -1):
		var f: Dictionary = _muzzle_flash_fx[i]
		var nt: float = float(f.get("t", 0.0)) + delta
		if nt >= _MUZZLE_FLASH_DURATION:
			_muzzle_flash_fx.remove_at(i)
		else:
			f["t"] = nt
			_muzzle_flash_fx[i] = f
	for i in range(_muzzle_smoke_fx.size() - 1, -1, -1):
		var s: Dictionary = _muzzle_smoke_fx[i]
		var nt: float = float(s.get("t", 0.0)) + delta
		if nt >= _MUZZLE_SMOKE_DURATION:
			_muzzle_smoke_fx.remove_at(i)
		else:
			s["t"] = nt
			_muzzle_smoke_fx[i] = s


func _tick_splash_fx(delta: float) -> void:
	if _splash_fx.is_empty():
		return
	for i in range(_splash_fx.size() - 1, -1, -1):
		var s: Dictionary = _splash_fx[i]
		var nt: float = float(s.get("t", 0.0)) + delta
		if nt >= _SPLASH_DURATION:
			_splash_fx.remove_at(i)
		else:
			s["t"] = nt
			_splash_fx[i] = s


func _draw_splash_fx() -> void:
	if _splash_fx.is_empty():
		return
	for s in _splash_fx:
		var wx: float = float(s.get("wx", 0.0))
		var wy: float = float(s.get("wy", 0.0))
		var t: float = float(s.get("t", 0.0))
		var u: float = clampf(t / _SPLASH_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy)
		var z: float = _zoom
		# Expanding ripples + a few droplet dots
		for ring in range(3):
			var rr: float = (4.0 + float(ring) * 7.0) * z * (0.15 + u * 0.92)
			var a: float = 0.28 * fade * (1.0 - float(ring) * 0.22)
			var c: Color = Color(0.65, 0.82, 0.96, a)
			draw_arc(sp, rr, 0.0, TAU, maxi(16, int(18.0 + rr * 0.4)), c, 1.6 * z, true)
		var droplet_a: float = 0.45 * fade
		for k in range(5):
			var ang: float = float(k) * TAU / 5.0 + t * 8.0
			var d: float = (10.0 + u * 14.0) * z
			var dp: Vector2 = sp + Vector2(cos(ang), sin(ang)) * d * 0.35
			draw_circle(dp, (1.2 - u * 0.4) * z, Color(0.85, 0.93, 1.0, droplet_a * 0.6))


func _draw_hull_strike_fx() -> void:
	if _hull_strike_fx.is_empty():
		return
	var hs: float = _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
	for s in _hull_strike_fx:
		var wx: float = float(s.get("wx", 0.0))
		var wy: float = float(s.get("wy", 0.0))
		var hit_h: float = float(s.get("h", 0.0))
		var t: float = float(s.get("t", 0.0))
		var u: float = clampf(t / _HULL_STRIKE_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy)
		sp += Vector2(0.0, -hit_h * hs)
		var z: float = _zoom
		# Core flash + expanding ember ring (reads as “ball struck hull”).
		var flash_a: float = 0.85 * fade * (1.0 - u * 0.7)
		draw_circle(sp, (5.5 + u * 3.0) * z, Color(1.0, 0.94, 0.72, flash_a * 0.5))
		draw_circle(sp, (3.2 - u * 1.2) * z, Color(1.0, 0.55, 0.2, flash_a * 0.75))
		for ring in range(2):
			var rr: float = (6.0 + float(ring) * 10.0) * z * (0.2 + u * 1.05)
			var a: float = 0.4 * fade * (1.0 - float(ring) * 0.35)
			draw_arc(sp, rr, 0.0, TAU, maxi(14, int(16.0 + rr * 0.35)), Color(0.35, 0.22, 0.12, a), 2.0 * z, true)
		var spark_n: int = 10
		for k in range(spark_n):
			var base_ang: float = float(k) * TAU / float(spark_n) + t * 14.0
			var burst: float = (18.0 + u * 28.0) * z * fade
			var p1: Vector2 = sp + Vector2(cos(base_ang), sin(base_ang)) * burst * 0.15
			var p2: Vector2 = sp + Vector2(cos(base_ang), sin(base_ang)) * burst * (0.45 + u * 0.35)
			var sc: Color = Color(1.0, 0.72 + u * 0.2, 0.35, 0.55 * fade)
			draw_line(p1, p2, sc, (1.8 - u * 0.6) * z)


func _draw_muzzle_fx() -> void:
	var z: float = _zoom
	for f in _muzzle_flash_fx:
		var wx: float = float(f.get("wx", 0.0))
		var wy: float = float(f.get("wy", 0.0))
		var t: float = float(f.get("t", 0.0))
		var u: float = clampf(t / _MUZZLE_FLASH_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy)
		var dir: Vector2 = _dir_screen(float(f.get("dirx", 1.0)), float(f.get("diry", 0.0)))
		draw_circle(sp, (9.0 + 8.0 * u) * z, Color(1.0, 0.92, 0.65, 0.55 * fade))
		draw_circle(sp, (5.0 + 4.0 * u) * z, Color(1.0, 0.64, 0.22, 0.75 * fade))
		draw_line(sp, sp + dir * (18.0 + 8.0 * u) * z, Color(1.0, 0.86, 0.48, 0.65 * fade), 2.0 * z)
	for s in _muzzle_smoke_fx:
		var wx: float = float(s.get("wx", 0.0))
		var wy: float = float(s.get("wy", 0.0))
		var t: float = float(s.get("t", 0.0))
		var u: float = clampf(t / _MUZZLE_SMOKE_DURATION, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _w2s(wx, wy) + Vector2(0.0, -8.0 * u * z)
		var rr: float = (6.0 + 22.0 * u) * z
		draw_circle(sp, rr, Color(0.22, 0.22, 0.24, 0.28 * fade))


func _apply_cannon_hit_impl(attacker_peer_id: int, defender_peer_id: int, _damage: float) -> void:
	var defender_idx: int = _find_player_index_by_peer_id(defender_peer_id)
	if defender_idx < 0:
		return
	var d: Dictionary = _players[defender_idx]
	if not bool(d.get("alive", true)):
		return
	var new_health: float = maxf(float(d.health) - 1.0, 0.0)
	var defender_alive: bool = new_health > 0.0
	d.health = new_health
	d.alive = defender_alive
	if not defender_alive:
		d["respawn_timer"] = RESPAWN_DELAY_SEC
	if bool(d.get("is_bot", false)):
		var bc: Variant = _get_bot_controller_for_index(defender_idx)
		if bc != null:
			bc.notify_cannon_hit(attacker_peer_id)
	_play_cannon_hit_sound()
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_check_win()


@rpc("authority", "call_local", "reliable")
func _apply_cannon_hit(attacker_peer_id: int, defender_peer_id: int, damage: float) -> void:
	_apply_cannon_hit_impl(attacker_peer_id, defender_peer_id, damage)

func _tick_local_timers(_delta: float) -> void:
	pass


func _tick_respawn(delta: float) -> void:
	for i in range(_players.size()):
		var p: Dictionary = _players[i]
		if bool(p.get("alive", true)):
			continue
		var t: float = float(p.get("respawn_timer", 0.0))
		if t <= 0.0:
			continue
		t = maxf(0.0, t - delta)
		p["respawn_timer"] = t
		if t <= 0.0:
			_respawn_ship(i)


func _respawn_ship(idx: int) -> void:
	if idx < 0 or idx >= _players.size():
		return
	var p: Dictionary = _players[idx]
	var nsp: int = maxi(_SPAWNS.size(), 1)
	var sp: Vector2 = _SPAWNS[idx % nsp]
	p.wx = sp.x
	p.wy = sp.y
	p.alive = true
	p.health = HULL_HITS_MAX
	p.erase("respawn_timer")
	p["hit_landed"] = false
	p["atk_time"] = 0.0
	p["walk_time"] = 0.0
	p["moving"] = false
	_apply_naval_controllers_to_ship(p)


## Naval sandbox: deaths respawn — do not end the match on last standing ship.
func _check_win() -> void:
	pass

func _ensure_audio_player() -> void:
	if _sfx_player != null:
		return
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "BlacksiteSfxPlayer"
	add_child(_sfx_player)

func _play_cannon_hit_sound() -> void:
	_ensure_audio_player()
	var sfx_scale: float = 1.0
	if GameManager != null:
		sfx_scale = float(GameManager.sfx_volume)
	var mix_rate: int = 44100
	var duration_sec: float = 0.16
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 22.0)
		var s: float = (
			sin(t * TAU * 112.0) * 0.52
			+ sin(t * TAU * 268.0) * 0.28
			+ sin(t * TAU * 440.0) * 0.14
		) * env * 0.48 * sfx_scale
		s = clampf(s, -1.0, 1.0)
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	_sfx_player.stream = wav
	_sfx_player.play()


func _play_tone(freq_hz: float, duration_sec: float, volume: float) -> void:
	_ensure_audio_player()
	var sfx_scale: float = 1.0
	if GameManager != null:
		sfx_scale = float(GameManager.sfx_volume)
	var mix_rate: int = 44100
	var sample_count: int = maxi(1, int(duration_sec * mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var envelope: float = clampf(1.0 - (float(i) / float(sample_count)), 0.0, 1.0)
		var sine: float = sin(t * TAU * freq_hz)
		var buzz: float = sign(sin(t * TAU * freq_hz * 0.5))
		var s: float = (sine * 0.65 + buzz * 0.35) * envelope * volume * sfx_scale
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	_sfx_player.stream = wav
	_sfx_player.play()

func _draw_player(p: Dictionary) -> void:
	var sp: Vector2 = _w2s(p.wx, p.wy)
	var draw_pos: Vector2 = _hull_visual_screen_pos(p)
	if not bool(p.get("alive", true)):
		# Sunken wreck marker — same deck anchor as the living hull.
		draw_line(draw_pos + Vector2(-14.0, -6.0) * _zoom, draw_pos + Vector2(14.0, 6.0) * _zoom, Color(0.38, 0.24, 0.10, 0.85), 4.0 * _zoom)
		draw_line(draw_pos + Vector2(14.0, -6.0) * _zoom, draw_pos + Vector2(-14.0, 6.0) * _zoom, Color(0.38, 0.24, 0.10, 0.85), 4.0 * _zoom)
		return
	var hull := Vector2(float(p.dir.x), float(p.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var fwd: Vector2 = _dir_screen(hull.x, hull.y)
	var right: Vector2 = Vector2(-fwd.y, fwd.x)
	var px_len: float = maxf(14.0 * _zoom, (_w2s(p.wx + hull.x * NC.SHIP_LENGTH_UNITS, p.wy + hull.y * NC.SHIP_LENGTH_UNITS) - sp).length() * 0.55)
	var px_wid: float = maxf(8.0 * _zoom, (_w2s(p.wx + right.x * NC.SHIP_WIDTH_UNITS, p.wy + right.y * NC.SHIP_WIDTH_UNITS) - sp).length() * 0.9)
	var nose: Vector2 = draw_pos + fwd * px_len * 0.68
	var tail_l: Vector2 = draw_pos - fwd * px_len * 0.42 + right * px_wid * 0.52
	var tail_r: Vector2 = draw_pos - fwd * px_len * 0.42 - right * px_wid * 0.52
	var notch: Vector2 = draw_pos - fwd * px_len * 0.12
	var mod_color: Color = p.palette[0]
	var edge_col: Color = Color(0.08, 0.09, 0.12, 0.92)
	draw_colored_polygon(PackedVector2Array([nose, tail_l, notch, tail_r]), mod_color)
	draw_polyline(PackedVector2Array([nose, tail_l, notch, tail_r, nose]), edge_col, 2.0 * _zoom, true)
	draw_circle(draw_pos + Vector2(0.0, 12.0 * _zoom), 4.0 * _zoom, mod_color)
	var font := ThemeDB.fallback_font
	draw_string(font, draw_pos + Vector2(0.0, -42.0 * _zoom), str(p.get("label", "Ship")), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 1.0, 1.0, 0.88))

	if _players.is_empty():
		return
	if p != _players[_my_index]:
		return
	var L: float = 70.0 * _zoom
	var c_arc: Color = Color(0.42, 0.86, 0.52, 0.36)
	var c_bow: Color = Color(0.92, 0.78, 0.42, 0.45)
	for sgn in [-1.0, 1.0]:
		var perp: Vector2 = hull.rotated(sgn * PI * 0.5)
		var half: float = deg_to_rad(NC.BROADSIDE_HALF_ARC_DEG)
		var a0: Vector2 = perp.rotated(-half)
		var a1: Vector2 = perp.rotated(half)
		draw_line(draw_pos, draw_pos + _dir_screen(a0.x, a0.y) * L, c_arc, 2.0 * _zoom)
		draw_line(draw_pos, draw_pos + _dir_screen(a1.x, a1.y) * L, c_arc, 2.0 * _zoom)
	draw_line(draw_pos, draw_pos + _dir_screen(hull.x, hull.y) * (32.0 * _zoom), c_bow, 2.2 * _zoom)


func _draw_hud(vp: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var bar_h: float = 20.0
	var pad: float = 14.0
	const MAX_COLS: int = 4
	var bar_w: float = minf((vp.x - pad * (MAX_COLS + 1)) / MAX_COLS, 200.0)
	var spacing: float = bar_w + pad
	var row_stride: float = bar_h + 8.0
	var status_y: float = pad + row_stride * 2.0 + 10.0
	for i in range(_status_messages.size()):
		var entry: Dictionary = _status_messages[i]
		draw_string(
			font,
			Vector2(pad, status_y + float(i) * 18.0),
			str(entry.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			_HUD_TEXT
		)
	for i in range(_players.size()):
		var p: Dictionary = _players[i]
		var col_idx: int = i % MAX_COLS
		@warning_ignore("integer_division")
		var row_idx: int = i / MAX_COLS
		var bx: float = pad + float(col_idx) * spacing
		var by: float = pad + float(row_idx) * row_stride
		var fill: float = bar_w * clampf(float(p.health) / HULL_HITS_MAX, 0.0, 1.0)
		var col: Color = p.palette[0]
		draw_rect(Rect2(bx, by, bar_w, bar_h), _HUD_BG)
		if p.alive and fill > 0.0:
			draw_rect(Rect2(bx, by, fill, bar_h), col)
		draw_rect(Rect2(bx, by, bar_w, bar_h), _HUD_BORDER, false, 1.5)
		var bar_txt: String
		if p.alive:
			bar_txt = "%s  %d/%d" % [p.label, int(maxf(p.health, 0.0)), int(HULL_HITS_MAX)]
		else:
			var rt: float = float(p.get("respawn_timer", 0.0))
			bar_txt = "%s  respawn %.1fs" % [p.label, rt] if rt > 0.001 else "%s  —" % p.label
		draw_string(font, Vector2(bx + 5.0, by + bar_h - 5.0), bar_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _HUD_TEXT)


func _draw_world_range_ring(center: Vector2, range_units: float, color: Color, width: float = 1.6, screen_y_offset_px: float = 0.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var segs: int = 96
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var ang: float = t * TAU
		var wx: float = center.x + cos(ang) * range_units
		var wy: float = center.y + sin(ang) * range_units
		points.append(_w2s(wx, wy) + Vector2(0.0, screen_y_offset_px))
	draw_polyline(points, color, width * _zoom, true)


func _draw_top_down_ocean(vp: Vector2) -> void:
	var u: float = NC.UNITS_PER_LOGIC_TILE
	var map_w: float = float(NC.MAP_TILES_WIDE) * u
	var map_h: float = float(NC.MAP_TILES_HIGH) * u
	var tl: Vector2 = _w2s(0.0, 0.0)
	var br: Vector2 = _w2s(map_w, map_h)
	var water_col: Color = Color(0.18, 0.44, 0.64, 1.0)
	var deep_col: Color = Color(0.06, 0.22, 0.42, 1.0)
	draw_rect(Rect2(tl, br - tl), water_col)
	var edge_u: float = 3.0 * u
	var inner_tl: Vector2 = _w2s(edge_u, edge_u)
	var inner_br: Vector2 = _w2s(map_w - edge_u, map_h - edge_u)
	draw_rect(Rect2(tl, Vector2(br.x - tl.x, inner_tl.y - tl.y)), deep_col)
	draw_rect(Rect2(Vector2(tl.x, inner_br.y), Vector2(br.x - tl.x, br.y - inner_br.y)), deep_col)
	draw_rect(Rect2(Vector2(tl.x, inner_tl.y), Vector2(inner_tl.x - tl.x, inner_br.y - inner_tl.y)), deep_col)
	draw_rect(Rect2(Vector2(inner_br.x, inner_tl.y), Vector2(br.x - inner_br.x, inner_br.y - inner_tl.y)), deep_col)
	var grid_spacing: float = 100.0
	var grid_col: Color = Color(0.22, 0.48, 0.68, 0.25)
	var px_per_unit: float = _TD_SCALE * _zoom
	if px_per_unit * grid_spacing < 8.0:
		grid_spacing = 500.0
	if px_per_unit * grid_spacing < 4.0:
		return
	var vis_x0: float = maxf(0.0, -_origin.x / px_per_unit)
	var vis_y0: float = maxf(0.0, -_origin.y / px_per_unit)
	var vis_x1: float = minf(map_w, (vp.x - _origin.x) / px_per_unit)
	var vis_y1: float = minf(map_h, (vp.y - _origin.y) / px_per_unit)
	var gx: float = floorf(vis_x0 / grid_spacing) * grid_spacing
	while gx <= vis_x1:
		draw_line(_w2s(gx, vis_y0), _w2s(gx, vis_y1), grid_col, 1.0)
		gx += grid_spacing
	var gy: float = floorf(vis_y0 / grid_spacing) * grid_spacing
	while gy <= vis_y1:
		draw_line(_w2s(vis_x0, gy), _w2s(vis_x1, gy), grid_col, 1.0)
		gy += grid_spacing


func _draw_accuracy_bands(center: Vector2, screen_y_offset_px: float = 0.0) -> void:
	var bands: Array[Dictionary] = [
		{"r0": 0.0, "r1": NC.ACC_PISTOL_RANGE, "col": Color(0.1, 0.95, 0.2, 0.06), "label": "90%"},
		{"r0": NC.ACC_PISTOL_RANGE, "r1": NC.ACC_CLOSE_RANGE, "col": Color(0.3, 0.9, 0.15, 0.05), "label": "75%"},
		{"r0": NC.ACC_CLOSE_RANGE, "r1": NC.ACC_MUSKET_RANGE, "col": Color(0.9, 0.85, 0.1, 0.045), "label": "50%"},
		{"r0": NC.ACC_MUSKET_RANGE, "r1": NC.ACC_MEDIUM_RANGE, "col": Color(0.95, 0.5, 0.08, 0.04), "label": "25%"},
		{"r0": NC.ACC_MEDIUM_RANGE, "r1": NC.ACC_LONG_RANGE, "col": Color(0.95, 0.15, 0.08, 0.035), "label": "10%"},
	]
	var segs: int = 72
	for band in bands:
		var inner_r: float = float(band.r0)
		var outer_r: float = float(band.r1)
		var col: Color = band.col
		var verts: PackedVector2Array = PackedVector2Array()
		for i in range(segs + 1):
			var ang: float = float(i) / float(segs) * TAU
			var wx_in: float = center.x + cos(ang) * inner_r
			var wy_in: float = center.y + sin(ang) * inner_r
			verts.append(_w2s(wx_in, wy_in) + Vector2(0.0, screen_y_offset_px))
		for i in range(segs, -1, -1):
			var ang: float = float(i) / float(segs) * TAU
			var wx_out: float = center.x + cos(ang) * outer_r
			var wy_out: float = center.y + sin(ang) * outer_r
			verts.append(_w2s(wx_out, wy_out) + Vector2(0.0, screen_y_offset_px))
		if verts.size() >= 3:
			draw_colored_polygon(verts, col)
		_draw_world_range_ring(center, outer_r, col * 2.5, 1.2, screen_y_offset_px)
	var label_ang: float = -PI * 0.25
	var label_font_size: int = int(maxf(9.0, 11.0 * _zoom))
	for band in bands:
		var r_mid: float = (float(band.r0) + float(band.r1)) * 0.5
		var lx: float = center.x + cos(label_ang) * r_mid
		var ly: float = center.y + sin(label_ang) * r_mid
		var sp: Vector2 = _w2s(lx, ly) + Vector2(0.0, screen_y_offset_px)
		draw_string(ThemeDB.fallback_font, sp, String(band.label),
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size, Color(1, 1, 1, 0.55))


func _draw() -> void:
	var vp := get_viewport_rect().size
	var me: Dictionary = _players[_my_index] if not _players.is_empty() else {}
	var cam_focus: Vector2
	if _camera_locked and not me.is_empty():
		cam_focus = Vector2(float(me.wx), float(me.wy))
	else:
		cam_focus = _camera_world_anchor
	_origin = vp * 0.5 - cam_focus * _TD_SCALE * _zoom

	draw_rect(Rect2(Vector2.ZERO, vp), MapProfile.SEA_SKY)
	_draw_top_down_ocean(vp)
	var me_deck_y_off: float = 0.0
	if not me.is_empty() and bool(me.get("alive", true)):
		me_deck_y_off = -NC.SHIP_DECK_HEIGHT_UNITS * _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
	var me_world: Vector2 = Vector2(float(me.wx), float(me.wy)) if not me.is_empty() else cam_focus
	_draw_accuracy_bands(me_world, me_deck_y_off)
	_draw_world_range_ring(me_world, NC.MAX_CANNON_RANGE, Color(1.0, 0.25, 0.1, 0.7), 2.4, me_deck_y_off)
	_draw_splash_fx()

	var sorted := _players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.wx + a.wy) < (b.wx + b.wy))
	for p in sorted:
		_draw_player(p)

	if OS.is_debug_build() and combat_debug_world_draw:
		_draw_combat_debug_world_overlays()

	_draw_muzzle_fx()
	_draw_ship_trajectory_arc_preview()
	_draw_trajectory_arc_preview()
	_draw_projectiles()
	_draw_hull_strike_fx()
	_draw_motion_battery_hud(vp)
	_draw_helm_sail_hud(vp)
	_draw_ftl_ship_hud(vp)
	_draw_offscreen_indicators(vp)
	_draw_hud(vp)
	_draw_keybindings_panel(vp)
	_draw_ability_bar(vp)
	_draw_bot_debug_hud(vp)
	if _winner != -2:
		_draw_win_screen(vp)


func _draw_combat_debug_world_overlays() -> void:
	if _bot_controllers.is_empty() or _bot_indices.is_empty():
		return
	var ctrl: Variant = _bot_controllers[0]
	if ctrl == null or ctrl.agent == null:
		return
	var bot_dict: Dictionary = ctrl.agent.ship_dict
	if bot_dict.is_empty() or not bool(bot_dict.get("alive", false)):
		return
	var tgt: Dictionary = ctrl.target_dict
	if tgt.is_empty() or not bool(tgt.get("alive", false)):
		return
	var bpos: Vector2 = Vector2(float(bot_dict.wx), float(bot_dict.wy))
	var tpos: Vector2 = Vector2(float(tgt.wx), float(tgt.wy))
	var sb: Vector2 = _w2s(bpos.x, bpos.y)
	var st: Vector2 = _w2s(tpos.x, tpos.y)
	draw_line(sb, st, Color(1.0, 0.45, 0.2, 0.75), 2.0 * _zoom)
	var hull: Vector2 = Vector2(float(bot_dict.dir.x), float(bot_dict.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var fwd_len: float = 55.0 * _zoom
	draw_line(sb, sb + _dir_screen(hull.x, hull.y) * fwd_len, Color(0.35, 0.9, 1.0, 0.85), 2.2 * _zoom)
	var br: Dictionary = ctrl.broadside_result
	var side: String = str(br.get("best_side", "none"))
	var to_t: Vector2 = (tpos - bpos)
	if to_t.length_squared() > 0.01:
		to_t = to_t.normalized()
		var want: Vector2 = to_t.rotated(-PI * 0.5) if side == "port" else to_t.rotated(PI * 0.5)
		if side == "none":
			want = to_t.rotated(PI * 0.5)
		draw_line(sb, sb + _dir_screen(want.x, want.y) * fwd_len * 0.9, Color(0.45, 1.0, 0.55, 0.75), 2.0 * _zoom)
	var half_arc: float = deg_to_rad(NC.BROADSIDE_HALF_ARC_DEG)
	var perp: Vector2 = hull.rotated(PI * 0.5) if side != "starboard" else hull.rotated(-PI * 0.5)
	var L: float = 62.0 * _zoom
	var a0: Vector2 = perp.rotated(-half_arc)
	var a1: Vector2 = perp.rotated(half_arc)
	draw_line(sb, sb + _dir_screen(a0.x, a0.y) * L, Color(0.95, 0.85, 0.25, 0.5), 1.8 * _zoom)
	draw_line(sb, sb + _dir_screen(a1.x, a1.y) * L, Color(0.95, 0.85, 0.25, 0.5), 1.8 * _zoom)
	# Engagement bands around target (NavalCombatEvaluator band tuning).
	_draw_world_range_ring(tpos, NavalCombatEvaluator.BAND_TOO_CLOSE, Color(1.0, 0.25, 0.35, 0.45), 1.4)
	var pc: float = NavalCombatEvaluator.BAND_PREFERRED_CENTER
	var tol: float = NavalCombatEvaluator.BAND_PREFERRED_TOLERANCE
	_draw_world_range_ring(tpos, pc - tol, Color(0.35, 0.85, 1.0, 0.38), 1.2)
	_draw_world_range_ring(tpos, pc + tol, Color(0.35, 0.85, 1.0, 0.38), 1.2)
	_draw_world_range_ring(tpos, NavalCombatEvaluator.BAND_MAX_PRACTICAL, Color(0.75, 0.35, 1.0, 0.42), 1.4)


## Off-screen arrows aim at the **drawn** hull (deck lift), not waterline wx/wy.
func _draw_offscreen_indicators(vp: Vector2) -> void:
	const EDGE_PAD := 30.0
	const ARROW_R := 12.0
	var font: Font = ThemeDB.fallback_font
	var screen_center: Vector2 = vp * 0.5
	for p in _players:
		if not p.alive:
			continue
		var sp: Vector2 = _hull_visual_screen_pos(p)
		if sp.x >= EDGE_PAD and sp.x <= vp.x - EDGE_PAD \
				and sp.y >= EDGE_PAD and sp.y <= vp.y - EDGE_PAD:
			continue
		var dir: Vector2 = (sp - screen_center).normalized()
		var t_x: float = INF
		var t_y: float = INF
		if absf(dir.x) > 0.0001:
			var tx0: float = (EDGE_PAD - screen_center.x) / dir.x
			var tx1: float = (vp.x - EDGE_PAD - screen_center.x) / dir.x
			t_x = tx1 if dir.x > 0.0 else tx0
		if absf(dir.y) > 0.0001:
			var ty0: float = (EDGE_PAD - screen_center.y) / dir.y
			var ty1: float = (vp.y - EDGE_PAD - screen_center.y) / dir.y
			t_y = ty1 if dir.y > 0.0 else ty0
		var t: float = minf(t_x, t_y)
		var ap: Vector2 = screen_center + dir * t
		var pa: Color = p.palette[0]
		var tip: Vector2 = ap + dir * ARROW_R
		var perp: Vector2 = Vector2(-dir.y, dir.x) * ARROW_R * 0.6
		var base1: Vector2 = ap - dir * (ARROW_R * 0.4) + perp
		var base2: Vector2 = ap - dir * (ARROW_R * 0.4) - perp
		const S := 1.18
		var stip: Vector2 = ap + dir * ARROW_R * S
		var sperp: Vector2 = Vector2(-dir.y, dir.x) * ARROW_R * 0.6 * S
		var sbase1: Vector2 = ap - dir * (ARROW_R * 0.4 * S) + sperp
		var sbase2: Vector2 = ap - dir * (ARROW_R * 0.4 * S) - sperp
		draw_colored_polygon(PackedVector2Array([stip, sbase1, sbase2]), Color(0.0, 0.0, 0.0, 0.55))
		draw_colored_polygon(PackedVector2Array([tip, base1, base2]), pa)
		var label_pos: Vector2 = ap - dir * (ARROW_R + 10.0)
		draw_string(font, label_pos, p.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(pa.r, pa.g, pa.b, 0.90))


func _draw_bot_debug_hud(vp: Vector2) -> void:
	if not OS.is_debug_build():
		return
	if not combat_debug_hud_enabled:
		return
	if _bot_controllers.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs: int = 11
	var panel_w: float = 220.0
	var x: float = vp.x - panel_w
	var y: float = 10.0
	var label_colors: Array = [
		Color(0.95, 0.40, 0.35, 1.0),  # red
		Color(1.00, 0.80, 0.30, 1.0),  # gold
		Color(0.80, 0.55, 0.95, 1.0),  # purple
	]
	for ci in range(_bot_controllers.size()):
		var ctrl: Variant = _bot_controllers[ci]
		if ctrl == null or not bool(ctrl.show_debug_hud_panel):
			continue
		var text: String = ctrl.get_debug_text()
		var lines: PackedStringArray = text.split("\n")
		var panel_h: float = float(lines.size()) * 15.0 + 10.0
		draw_rect(Rect2(x - 5.0, y - 2.0, panel_w, panel_h), Color(0.0, 0.0, 0.0, 0.55))
		var col: Color = label_colors[ci % label_colors.size()]
		for line in lines:
			draw_string(font, Vector2(x, y + 12.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += 15.0
		y += 8.0  # gap between bot panels


func _draw_projectiles() -> void:
	var hs: float = _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
	for proj in _projectiles:
		if not bool(proj.get("alive", true)):
			continue
		var wx: float = float(proj.get("wx", 0.0))
		var wy: float = float(proj.get("wy", 0.0))
		var h: float = float(proj.get("h", 0.0))
		var vx: float = float(proj.get("vx", 0.0))
		var vy: float = float(proj.get("vy", 0.0))
		var sp: Vector2 = _w2s(wx, wy)
		# Lift draw position so the ball reads as flying above the water plane.
		sp += Vector2(0.0, -h * hs)
		var horiz := Vector2(vx, vy)
		var trail: Vector2 = _dir_screen(vx, vy) * 16.0 * _zoom if horiz.length_squared() > 0.0001 else Vector2.RIGHT * 10.0 * _zoom
		var core: Color = Color(0.18, 0.17, 0.16, 1.0)
		var rim: Color = Color(0.42, 0.40, 0.38, 0.95)
		var rad: float = (9.0 + minf(h * 0.4, 4.0)) * _zoom
		draw_line(sp - trail * 0.35, sp + trail * 0.5, Color(0.35, 0.32, 0.28, 0.65), 3.5 * _zoom)
		draw_circle(sp, rad + 2.0 * _zoom, rim)
		draw_circle(sp, rad, core)


func _draw_trajectory_arc_preview() -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	if not bool(p.get("alive", true)):
		return
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_n.length_squared() < 0.0001:
		hull_n = Vector2.RIGHT
	else:
		hull_n = hull_n.normalized()
	var batteries: Array[Dictionary] = []
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	var sel_port_arc: bool = bool(p.get("aim_broadside_port", true))
	if port_b != null and sel_port_arc:
		batteries.append({"bat": port_b, "aim": hull_n.rotated(PI * 0.5), "col": Color(1.0, 0.28, 0.22, 0.82)})
	if stbd_b != null and not sel_port_arc:
		batteries.append({"bat": stbd_b, "aim": hull_n.rotated(-PI * 0.5), "col": Color(1.0, 0.45, 0.18, 0.82)})
	for bd in batteries:
		_draw_single_battery_arc(p, bd.aim, bd.bat, bd.col)


func _draw_single_battery_arc(p: Dictionary, aim_dir: Vector2, bat: _BatteryController, color: Color) -> void:
	var shot_damage: float = bat.damage_per_shot_for_current_mode()
	var mass: float = _CannonBallistics.mass_from_damage(shot_damage)
	var est_range: float = NC.OPTIMAL_RANGE
	var spread_deg: float = NC.spread_deg_for_range(est_range)
	var dirs: Array[Vector2] = [aim_dir, aim_dir.rotated(deg_to_rad(spread_deg)), aim_dir.rotated(deg_to_rad(-spread_deg))]
	var elev_deg_arc: float = bat.elevation_degrees()
	for idx in range(dirs.size()):
		var d: Vector2 = dirs[idx].normalized()
		var vel: Dictionary = _CannonBallistics.initial_velocity(d, mass, NC.CANNON_LINE_SPEED_SCALE, elev_deg_arc)
		var vx: float = float(vel.vx)
		var vy: float = float(vel.vy)
		var vz: float = float(vel.vz)
		var hs_now: float = sqrt(vx * vx + vy * vy)
		var desired_hs: float = NC.PROJECTILE_SPEED * lerpf(1.1, 0.85, clampf((mass - 0.5) / 1.25, 0.0, 1.0))
		if hs_now > 0.001:
			var s: float = desired_hs / hs_now
			vx *= s
			vy *= s
			vz *= s
		var muzzle: float = 6.5
		var wx0: float = float(p.wx) + d.x * muzzle
		var wy0: float = float(p.wy) + d.y * muzzle
		var h0: float = _CannonBallistics.MUZZLE_HEIGHT
		var grav: float = _CannonBallistics.GRAVITY * NC.PROJECTILE_GRAVITY_SCALE
		var hs_px: float = _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
		var vz0: float = vz
		var disc: float = vz0 * vz0 + 2.0 * grav * h0
		var t_splash: float = (vz0 + sqrt(maxf(0.0, disc))) / maxf(0.001, grav)
		var max_t: float = minf(t_splash, NC.PROJECTILE_LIFETIME)
		var steps: int = 40
		var dt: float = max_t / maxf(1.0, float(steps))
		var points: PackedVector2Array = PackedVector2Array()
		for i_step in range(steps + 1):
			var t: float = float(i_step) * dt
			var wx_t: float = wx0 + vx * t
			var wy_t: float = wy0 + vy * t
			var h_t: float = h0 + vz0 * t - 0.5 * grav * t * t
			if h_t < 0.0:
				break
			var sp: Vector2 = _w2s(wx_t, wy_t) + Vector2(0.0, -h_t * hs_px)
			points.append(sp)
		if points.size() < 2:
			continue
		var line_w: float = 2.0 if idx == 0 else 1.0
		var line_col: Color = color if idx == 0 else Color(color.r, color.g, color.b, color.a * 0.4)
		draw_polyline(points, line_col, line_w, true)
		if idx == 0:
			for i in range(0, points.size(), 4):
				var alpha: float = lerpf(0.8, 0.15, float(i) / maxf(1.0, float(points.size() - 1)))
				draw_circle(points[i], 1.4, Color(color.r, color.g, color.b, alpha))


func _draw_ship_trajectory_arc_preview() -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	if not bool(p.get("alive", true)):
		return
	var helm = p.get("helm")
	var sail = p.get("sail")
	if helm == null or sail == null:
		return

	var hull: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var wx: float = float(p.wx)
	var wy: float = float(p.wy)
	var spd: float = float(p.get("move_speed", 0.0))
	var ang_vel: float = float(p.get("angular_velocity", 0.0))
	if _helm_arc_sim == null:
		_helm_arc_sim = _HelmController.new()
	_helm_arc_sim.copy_from(helm)
	var steer_arc: Vector2 = _steer_strengths(_get_primary_pad_id())
	var dt_step: float = clampf(get_physics_process_delta_time(), 1.0 / 120.0, 1.0 / 30.0)

	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match int(sail.sail_state):
		_SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED
		_SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED
		_SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED
		_:
			target_cap = NC.SAILS_DOWN_DRIFT_SPEED
			sails_provide_thrust = false

	var drag_mult: float = COAST_DRAG_MULT if float(sail.current_sail_level) < float(sail.coast_drag_threshold) else 1.0
	var accel_r: float = NC.accel_rate()
	var decel_r: float = NC.decel_rate_sails()
	var tau: float = maxf(0.001, NC.HELM_TURN_LAG_SEC)
	var sim_t: float = 0.0
	var sim_max_t: float = 90.0
	var points: PackedVector2Array = PackedVector2Array()

	var spd_for_turn: float = spd

	while sim_t <= sim_max_t:
		points.append(_w2s(wx, wy))

		# Identical helm integration as gameplay (wheel accel, friction, return, rudder lag).
		_helm_arc_sim.process_steer(dt_step, steer_arc.x, steer_arc.y)
		var rudder: float = _helm_arc_sim.rudder_angle

		# Turning (uses pre-drag speed, matching _tick_player).
		var turn_deg: float = NC.turn_rate_deg_for_speed(spd_for_turn)
		var max_turn_rad: float = deg_to_rad(turn_deg)
		var steer_auth: float = clampf(spd_for_turn / 8.25, 0.0, 1.0)
		var target_av: float = max_turn_rad * rudder * steer_auth
		ang_vel = lerpf(ang_vel, target_av, 1.0 - exp(-dt_step / tau))
		hull = hull.rotated(ang_vel * dt_step).normalized()

		# Speed / drag (matching _tick_player order).
		spd_for_turn = spd
		var sim_drift_floor: float = NC.SAILS_DOWN_DRIFT_SPEED if not sails_provide_thrust and spd > 0.01 else 0.0
		if spd < target_cap and sails_provide_thrust:
			spd = minf(spd + accel_r * dt_step, target_cap)
		elif spd > target_cap and sails_provide_thrust:
			spd = maxf(0.0, spd - decel_r * drag_mult * dt_step)
		spd = maxf(sim_drift_floor, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * dt_step)
		if float(sail.current_sail_level) < float(sail.coast_drag_threshold):
			spd = maxf(sim_drift_floor, spd - MOTION_ZERO_SAIL_DRAG * drag_mult * dt_step)
		var rud_abs: float = absf(rudder)
		spd = maxf(sim_drift_floor, spd - rud_abs * MOTION_TURNING_SPEED_LOSS * dt_step)
		if rud_abs > MOTION_HARD_TURN_RUDDER:
			spd = maxf(sim_drift_floor, spd - rud_abs * MOTION_HARD_TURN_SPEED_LOSS * dt_step)
		spd = clampf(spd, 0.0, NC.MAX_SPEED * 1.05)

		wx += hull.x * spd * dt_step
		wy += hull.y * spd * dt_step
		sim_t += dt_step

	if points.size() < 2:
		return
	draw_polyline(points, Color(0.36, 0.86, 1.0, 0.82), 2.4, true)
	for i in range(0, points.size(), 6):
		var a: float = lerpf(0.85, 0.18, float(i) / maxf(1.0, float(points.size() - 1)))
		draw_circle(points[i], 1.7, Color(0.62, 0.95, 1.0, a))


func _draw_motion_battery_hud(_vp: Vector2) -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	var font: Font = ThemeDB.fallback_font
	var x: float = 14.0
	var y: float = 94.0
	var panel_w: float = 200.0
	var txt: Color = Color(0.94, 0.95, 1.0, 0.96)
	var sub: Color = Color(0.78, 0.86, 0.98, 0.9)
	var dim: Color = Color(0.55, 0.62, 0.72, 0.88)

	var bs_port: bool = bool(p.get("aim_broadside_port", true))
	var bs_txt: String = "Port broadside" if bs_port else "Starboard broadside"
	draw_string(font, Vector2(x, y), "Aim: %s" % bs_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, txt)
	var spr_info: Dictionary = compute_ship_sprite_for_world_heading(float(p.dir.x), float(p.dir.y))
	var spr_label: String = str(spr_info.get("sprite_compass", "?"))
	var fidx: int = int(spr_info.get("frame_idx", 0))
	var wdeg: float = float(spr_info.get("world_deg", 0.0))
	var scrdeg: float = float(spr_info.get("screen_deg", 0.0))
	var secdeg: float = float(spr_info.get("screen_norm_sector_deg", 0.0))
	draw_string(font, Vector2(x, y + 14.0), "Ship texture: %s [_SHIP_TEXTURES[%d]]" % [spr_label, fidx], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	draw_string(font, Vector2(x, y + 28.0), "Heading world (wx,wy): %.1f deg" % wdeg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	draw_string(font, Vector2(x, y + 40.0), "Heading screen (sprite axis): %.1f deg  sector 0-360: %.1f" % [scrdeg, secdeg], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	var motion = p.get("motion")
	var lin_raw: Variant = p.get("linear_motion_state", 0)
	var turn: bool = bool(p.get("motion_is_turning", false))
	var turn_h: bool = bool(p.get("motion_is_turning_hard", false))
	var motion_line: String = "—"
	if motion != null:
		motion_line = motion.format_motion_summary(lin_raw as _MotionStateResolver.LinearMotionState, turn, turn_h)
	draw_string(font, Vector2(x, y + 56.0), "Motion FSM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	draw_string(font, Vector2(x, y + 72.0), motion_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	var spd: float = float(p.get("move_speed", 0.0))
	var cap: float = 0.0
	var sail = p.get("sail")
	if sail != null:
		cap = float(sail.max_speed)
	draw_string(font, Vector2(x, y + 88.0), "Speed %.2f / %.1f" % [spd, cap], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)

	var bat_y: float = y + 108.0
	var sel_fire_port: bool = bool(p.get("aim_broadside_port", true))
	var fire_sel: String = "Port (E/LB)" if sel_fire_port else "Starboard (Q/RB)"
	draw_string(font, Vector2(x, bat_y), "Fire battery: %s · F/RT" % fire_sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sub)
	draw_string(font, Vector2(x, bat_y + 14.0), "Batteries", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	_draw_battery_row(font, x, bat_y + 30.0, panel_w, p.get("battery_port"), txt, sub, dim, sel_fire_port)
	_draw_battery_row(font, x, bat_y + 58.0, panel_w, p.get("battery_stbd"), txt, sub, dim, not sel_fire_port)


func _draw_battery_row(font: Font, x: float, y: float, panel_w: float, bat: Variant, txt: Color, _sub: Color, dim: Color, selected: bool = false) -> void:
	if bat == null:
		draw_string(font, Vector2(x, y), "Battery —", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		return
	var b: _BatteryController = bat
	var sel_tag: String = " [selected]" if selected else ""
	var line: String = "%s · %s · %s%s" % [b.side_label(), b.fire_mode_display(), b.state_display(), sel_tag]
	draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	var bar_w: float = panel_w - 4.0
	var bar_y: float = y + 12.0
	var fill: float = b.reload_progress()
	var bg: Color = Color(0.08, 0.1, 0.14, 0.92)
	var fg: Color = Color(0.85, 0.62, 0.35, 0.9) if b.state == _BatteryController.BatteryState.RELOADING else Color(0.35, 0.72, 0.48, 0.85)
	draw_rect(Rect2(x, bar_y, bar_w, 6.0), bg)
	draw_rect(Rect2(x, bar_y, bar_w * fill, 6.0), fg)
	var rtxt: String = "Reload" if b.state == _BatteryController.BatteryState.RELOADING else "Ready"
	draw_string(font, Vector2(x + bar_w + 6.0, bar_y + 5.0), rtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)


func _draw_ftl_ship_hud(vp: Vector2) -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	var font: Font = ThemeDB.fallback_font
	var sel_fire_battery: bool = bool(p.get("aim_broadside_port", true))
	var hw: float = 60.0
	var hh: float = 160.0
	var cx: float = vp.x - hw - 20.0
	var cy: float = vp.y * 0.5
	var panel_bg: Color = Color(0.04, 0.06, 0.10, 0.88)
	draw_rect(Rect2(cx - hw - 8.0, cy - hh * 0.5 - 24.0, hw * 2.0 + 16.0, hh + 48.0), panel_bg)
	draw_rect(Rect2(cx - hw - 8.0, cy - hh * 0.5 - 24.0, hw * 2.0 + 16.0, hh + 48.0), Color(0.22, 0.30, 0.42, 0.9), false, 1.5)
	draw_string(font, Vector2(cx - hw + 2.0, cy - hh * 0.5 - 8.0), "Ship Status", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.88, 0.96, 0.95))

	var hull_col: Color = Color(0.32, 0.28, 0.22, 0.95)
	var nose: Vector2 = Vector2(cx, cy - hh * 0.46)
	var mid_l: Vector2 = Vector2(cx - hw * 0.7, cy - hh * 0.05)
	var mid_r: Vector2 = Vector2(cx + hw * 0.7, cy - hh * 0.05)
	var stern_l: Vector2 = Vector2(cx - hw * 0.5, cy + hh * 0.42)
	var stern_r: Vector2 = Vector2(cx + hw * 0.5, cy + hh * 0.42)
	var stern_c: Vector2 = Vector2(cx, cy + hh * 0.38)
	var ship_poly: PackedVector2Array = PackedVector2Array([nose, mid_r, stern_r, stern_c, stern_l, mid_l])
	draw_colored_polygon(ship_poly, hull_col)
	draw_polyline(PackedVector2Array([nose, mid_r, stern_r, stern_c, stern_l, mid_l, nose]), Color(0.52, 0.48, 0.38, 0.9), 1.5, true)

	var hp: float = float(p.get("health", HULL_HITS_MAX))
	var hp_frac: float = clampf(hp / HULL_HITS_MAX, 0.0, 1.0)
	var zone_names: Array[String] = ["Bow", "Fwd", "Mid", "Aft", "Stern"]
	var zone_count: int = zone_names.size()
	var zone_y_start: float = cy - hh * 0.40
	var zone_h: float = hh * 0.80 / float(zone_count)
	var zone_w: float = hw * 1.0
	for zi in range(zone_count):
		var zy: float = zone_y_start + float(zi) * zone_h
		var zone_hp: float = hp_frac
		var zone_col: Color
		if zone_hp > 0.6:
			zone_col = Color(0.25, 0.55, 0.32, 0.7)
		elif zone_hp > 0.3:
			zone_col = Color(0.72, 0.58, 0.22, 0.7)
		else:
			zone_col = Color(0.78, 0.22, 0.18, 0.7)
		if hp <= 0.0:
			zone_col = Color(0.15, 0.12, 0.10, 0.6)
		draw_rect(Rect2(cx - zone_w * 0.5, zy, zone_w, zone_h - 2.0), zone_col)
		draw_rect(Rect2(cx - zone_w * 0.5, zy, zone_w, zone_h - 2.0), Color(0.42, 0.46, 0.52, 0.6), false, 1.0)
		draw_string(font, Vector2(cx - zone_w * 0.5 + 3.0, zy + zone_h - 6.0), zone_names[zi], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.88, 0.90, 0.95, 0.9))

	var bat_icon_r: float = 5.0
	var bat_entries: Array[Dictionary] = []
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	if port_b != null:
		bat_entries.append({"bat": port_b, "pos": Vector2(cx - hw * 0.85, cy - hh * 0.05), "label": "P"})
	if stbd_b != null:
		bat_entries.append({"bat": stbd_b, "pos": Vector2(cx + hw * 0.85, cy - hh * 0.05), "label": "S"})
	for be in bat_entries:
		var bat: _BatteryController = be.bat
		var bp: Vector2 = be.pos
		var is_ready: bool = bat.state == _BatteryController.BatteryState.READY
		var is_aiming: bool = bat.state == _BatteryController.BatteryState.AIMING
		var is_idle: bool = bat.state == _BatteryController.BatteryState.IDLE
		var reloading: bool = bat.state == _BatteryController.BatteryState.RELOADING
		var firing: bool = bat.state == _BatteryController.BatteryState.FIRING
		var disabled: bool = bat.state == _BatteryController.BatteryState.DISABLED
		var bc: Color
		var state_label: String
		if disabled:
			bc = Color(0.25, 0.12, 0.10, 0.8)
			state_label = "DISABLED"
		elif firing:
			bc = Color(1.0, 0.65, 0.15, 0.95)
			state_label = "FIRING"
		elif reloading:
			var prog: float = bat.reload_progress()
			bc = Color(lerpf(0.7, 0.35, prog), lerpf(0.25, 0.72, prog), 0.3, 0.9)
			state_label = "RELOAD %d%%" % int(prog * 100.0)
		elif is_ready:
			bc = Color(0.2, 0.88, 0.35, 0.95)
			state_label = "READY"
		elif is_aiming:
			bc = Color(0.65, 0.72, 0.35, 0.85)
			state_label = "AIM"
		elif is_idle:
			bc = Color(0.45, 0.48, 0.55, 0.7)
			state_label = "IDLE"
		else:
			bc = Color(0.45, 0.48, 0.55, 0.7)
			state_label = "—"
		draw_circle(bp, bat_icon_r, bc)
		draw_arc(bp, bat_icon_r, 0.0, TAU, 16, Color(0.7, 0.75, 0.82, 0.8), 1.0, true)
		var bat_is_selected: bool = (bat.side == _BatteryController.BatterySide.PORT and sel_fire_battery) \
			or (bat.side == _BatteryController.BatterySide.STARBOARD and not sel_fire_battery)
		if bat_is_selected:
			draw_arc(bp, bat_icon_r + 4.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.35, 0.9), 2.0, true)
		if is_ready:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			draw_arc(bp, bat_icon_r + 2.5, 0.0, TAU, 16, Color(0.2, 1.0, 0.4, 0.4 * pulse), 1.5, true)
		if reloading:
			draw_arc(bp, bat_icon_r + 2.0, -PI * 0.5, -PI * 0.5 + TAU * bat.reload_progress(), 16, Color(0.85, 0.72, 0.35, 0.9), 2.0, true)
		draw_string(font, bp + Vector2(-3.0, 3.5), be.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.95, 1.0, 0.95))
		var lbl_offset: Vector2
		match bat.side:
			_BatteryController.BatterySide.PORT:
				lbl_offset = Vector2(-bat_icon_r - 4.0, 3.5)
				draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_RIGHT, int(bat_icon_r * 6.0), 7, bc)
			_BatteryController.BatterySide.STARBOARD:
				lbl_offset = Vector2(bat_icon_r + 4.0, 3.5)
				draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, bc)
			_:
				lbl_offset = Vector2(-16.0, bat_icon_r + 9.0)
				draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_CENTER, 32, 7, bc)

	var hp_bar_x: float = cx - hw - 4.0
	var hp_bar_y: float = cy + hh * 0.5 + 6.0
	var hp_bar_w: float = hw * 2.0 + 8.0
	draw_rect(Rect2(hp_bar_x, hp_bar_y, hp_bar_w, 10.0), Color(0.08, 0.1, 0.14, 0.92))
	var hp_col: Color
	if hp_frac > 0.6:
		hp_col = Color(0.3, 0.78, 0.38, 0.92)
	elif hp_frac > 0.3:
		hp_col = Color(0.82, 0.72, 0.25, 0.92)
	else:
		hp_col = Color(0.88, 0.25, 0.2, 0.92)
	draw_rect(Rect2(hp_bar_x, hp_bar_y, hp_bar_w * hp_frac, 10.0), hp_col)
	draw_string(font, Vector2(hp_bar_x, hp_bar_y + 22.0), "Hull %d / %d" % [int(maxf(hp, 0.0)), int(HULL_HITS_MAX)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.88, 0.90, 0.96, 0.95))
	var elev_y: float = hp_bar_y + 34.0
	var ref_bat: Variant = p.get("battery_port") if sel_fire_battery else p.get("battery_stbd")
	if ref_bat != null:
		var elev_val: float = ref_bat.cannon_elevation
		var elev_deg: float = ref_bat.elevation_degrees()
		var elev_col: Color = Color(0.6, 0.75, 0.95, 0.9)
		draw_rect(Rect2(hp_bar_x, elev_y, hp_bar_w, 8.0), Color(0.08, 0.1, 0.14, 0.92))
		draw_rect(Rect2(hp_bar_x, elev_y, hp_bar_w * elev_val, 8.0), elev_col)
		var tick_x: float = hp_bar_x + hp_bar_w * elev_val
		draw_rect(Rect2(tick_x - 1.0, elev_y - 1.0, 3.0, 10.0), Color(1.0, 1.0, 1.0, 0.9))
		var zero_frac: float = absf(ref_bat.ELEV_MIN_DEG) / (ref_bat.ELEV_MAX_DEG - ref_bat.ELEV_MIN_DEG)
		var zero_x: float = hp_bar_x + hp_bar_w * zero_frac
		draw_rect(Rect2(zero_x - 0.5, elev_y - 2.0, 1.0, 12.0), Color(1.0, 1.0, 0.6, 0.7))
		var sign_str: String = "+" if elev_deg >= 0.0 else ""
		draw_string(font, Vector2(hp_bar_x, elev_y + 20.0), "Quoin %s%.1f° (R↑ T↓)" % [sign_str, elev_deg], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, elev_col)


func _draw_helm_sail_hud(vp: Vector2) -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	var sail = p.get("sail")
	var helm = p.get("helm")
	if sail == null or helm == null:
		return
	var font: Font = ThemeDB.fallback_font
	var panel_w: float = 188.0
	var x: float = vp.x - panel_w - 14.0
	var y: float = 94.0
	var txt: Color = Color(0.94, 0.95, 1.0, 0.96)
	var sub: Color = Color(0.78, 0.86, 0.98, 0.9)
	draw_string(font, Vector2(x, y), "Helm FSM: %s" % helm.get_helm_state_enum_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	draw_string(font, Vector2(x, y + 18.0), "%s · %s" % [helm.get_helm_state_label(), helm.get_rudder_label()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	draw_string(font, Vector2(x, y + 36.0), "Sail: %s" % sail.get_display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, txt)
	draw_string(font, Vector2(x, y + 54.0), "Deploy %d%%" % int(clampf(sail.current_sail_level, 0.0, 1.0) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	var spd_u: float = float(p.get("move_speed", 0.0))
	var spd_mps: float = spd_u * _METERS_PER_WORLD_UNIT
	var spd_kn: float = spd_mps * _KNOTS_PER_METER_PER_SEC
	draw_string(font, Vector2(x, y + 68.0), "Speed: %.2f u/s · %.1f m/s · %.1f kn" % [spd_u, spd_mps, spd_kn], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, txt)

	var bar_w: float = panel_w - 8.0
	var sail_y: float = y + 86.0
	draw_rect(Rect2(x, sail_y, bar_w, 8.0), Color(0.08, 0.1, 0.14, 0.92))
	draw_rect(Rect2(x, sail_y, bar_w * clampf(sail.current_sail_level, 0.0, 1.0), 8.0), Color(0.26, 0.74, 0.96, 0.92))

	var wheel_y: float = sail_y + 18.0
	var wheel_c: Vector2 = Vector2(x + 24.0, wheel_y + 20.0)
	var wheel_r: float = 14.0
	var wood_dark: Color = Color(0.28, 0.18, 0.10, 0.96)
	var wood_mid: Color = Color(0.44, 0.27, 0.14, 0.95)
	var brass: Color = Color(0.80, 0.67, 0.40, 0.95)
	draw_circle(wheel_c, wheel_r + 2.4, Color(0.05, 0.07, 0.10, 0.9))
	draw_circle(wheel_c, wheel_r + 0.9, wood_dark)
	draw_arc(wheel_c, wheel_r, 0.0, TAU, 40, wood_mid, 3.2, true)
	draw_arc(wheel_c, wheel_r - 1.5, 0.0, TAU, 40, brass, 1.1, true)
	draw_circle(wheel_c, 3.9, wood_dark)
	draw_circle(wheel_c, 2.5, brass)
	var wheel_rot: float = helm.wheel_position * TAU * 2.0
	var base_ang: float = -PI * 0.5 + wheel_rot
	for i in range(8):
		var spoke_ang: float = base_ang + float(i) * TAU / 8.0
		var spoke_dir: Vector2 = Vector2(cos(spoke_ang), sin(spoke_ang))
		draw_line(wheel_c + spoke_dir * 3.6, wheel_c + spoke_dir * (wheel_r - 2.0), wood_mid, 1.4, true)
		draw_circle(wheel_c + spoke_dir * (wheel_r + 0.6), 1.35, brass)
	var top_spoke: Vector2 = Vector2(cos(base_ang), sin(base_ang))
	draw_line(wheel_c, wheel_c + top_spoke * (wheel_r - 1.0), Color(0.95, 0.90, 0.72, 0.98), 2.0, true)
	draw_circle(wheel_c + top_spoke * (wheel_r - 1.0), 1.9, Color(0.99, 0.94, 0.76, 1.0))
	draw_line(wheel_c + Vector2(0.0, -wheel_r - 3.0), wheel_c + Vector2(0.0, -wheel_r + 1.0), Color(1.0, 0.35, 0.25, 0.95), 2.0, true)
	var rud_max_rad: float = deg_to_rad(_HelmController.MAX_RUDDER_DEFLECTION_DEG)
	var rud_visual_ang: float = -PI * 0.5 + helm.rudder_angle * rud_max_rad
	var rud_tip: Vector2 = wheel_c + Vector2(cos(rud_visual_ang), sin(rud_visual_ang)) * (wheel_r - 5.0)
	draw_line(wheel_c, rud_tip, Color(0.45, 0.95, 0.74, 0.9), 1.7, true)
	draw_circle(rud_tip, 1.6, Color(0.45, 0.95, 0.74, 0.95))
	var lock_text: String = "LOCK ON" if helm.wheel_locked else "LOCK OFF"
	var lock_col: Color = Color(0.96, 0.68, 0.38, 0.96) if helm.wheel_locked else Color(0.62, 0.70, 0.82, 0.9)
	draw_string(font, Vector2(x + 52.0, wheel_y + 16.0), "Wheel %s" % lock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lock_col)
	var rud_deg: float = helm.rudder_angle * _HelmController.MAX_RUDDER_DEFLECTION_DEG
	var rud_side: String = "P" if rud_deg < -0.5 else ("S" if rud_deg > 0.5 else "mid")
	if helm.wheel_locked:
		draw_string(font, Vector2(x + 52.0, wheel_y + 30.0), "Hold · Rudder %.0f° %s" % [absf(rud_deg), rud_side], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.85, 0.72, 0.88))
	else:
		draw_string(font, Vector2(x + 52.0, wheel_y + 30.0), "Rudder %.0f° %s" % [absf(rud_deg), rud_side], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.62, 0.72, 0.82))


func _joy_button_short_name(button_idx: int) -> String:
	match button_idx:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_GUIDE:
			return "Guide"
	return "B%d" % button_idx


func _action_keys_display(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "—"
	var parts: Array[String] = []
	var seen: Dictionary = {}
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			var code: int = ke.physical_keycode
			if code == KEY_NONE:
				code = ke.keycode
			if code != KEY_NONE:
				var label: String = OS.get_keycode_string(code)
				if not seen.has(label):
					seen[label] = true
					parts.append(label)
		elif ev is InputEventJoypadButton:
			var jb := ev as InputEventJoypadButton
			var jlabel: String = _joy_button_short_name(jb.button_index)
			if not seen.has(jlabel):
				seen[jlabel] = true
				parts.append(jlabel)
	return " · ".join(parts) if parts.size() > 0 else "—"


func _slot_key_caption(action_name: String) -> String:
	return _action_keys_display(action_name).replace(" · ", "/")


func _draw_keybindings_panel(vp: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var line_h: float = 13.0
	var lines: Array[String] = [
		"Bindings (keyboard · gamepad)",
		"E / ← / LB: select PORT battery (aim + elevation + fire target)",
		"Q / → / RB: select STARBOARD battery",
		"F / X / RT: fire selected battery only",
		"Steer: %s / %s" % [_action_keys_display(_ACTIONS.left), _action_keys_display(_ACTIONS.right)],
		"Sail up · down: %s · %s" % [_action_keys_display(SAIL_RAISE_ACTION), _action_keys_display(SAIL_LOWER_ACTION)],
		"Fire mode: %s" % _action_keys_display(FIRE_MODE_ACTION),
		"Elevation up · down: %s · %s" % [_action_keys_display(ELEV_UP_ACTION), _action_keys_display(ELEV_DOWN_ACTION)],
		"Wheel lock toggle: %s" % _action_keys_display(WHEEL_LOCK_ACTION),
		"Zoom: mouse wheel or +/- buttons (top-right)",
		"Pan: arrow keys or middle-mouse drag · 1/Home/Tab: lock camera to follow your ship",
	]
	if OS.is_debug_build():
		lines.append("Debug (dev build): F3 bot HUD · F4 bot world overlays")
	var panel_pad: float = 8.0
	var box_w: float = minf(vp.x - 28.0, 560.0)
	var box_h: float = panel_pad * 2.0 + float(lines.size()) * line_h
	var ability_bar_top: float = vp.y - 54.0 - 16.0
	var y_top: float = ability_bar_top - 10.0 - box_h
	var x: float = 14.0
	draw_rect(Rect2(x - 6.0, y_top - 2.0, box_w, box_h + 4.0), Color(0.05, 0.07, 0.11, 0.88))
	var sub: Color = Color(0.62, 0.70, 0.82, 0.95)
	var txt: Color = Color(0.88, 0.91, 0.96, 0.96)
	for i in range(lines.size()):
		var c: Color = sub if i == 0 else txt
		var sz: int = 11 if i == 0 else 11
		draw_string(font, Vector2(x, y_top + panel_pad + float(i + 1) * line_h - 2.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)


func _draw_ability_bar(vp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var bar_w: float = 550.0
	var bar_h: float = 54.0
	var x: float = (vp.x - bar_w) * 0.5
	var y: float = vp.y - bar_h - 16.0
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.10, 0.12, 0.16, 0.82))
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.34, 0.42, 0.52, 0.9), false, 2.0)
	var p: Dictionary = _players[_my_index] if not _players.is_empty() else {}
	var port_b: Variant = p.get("battery_port")
	var stbd_b2: Variant = p.get("battery_stbd")
	var sel_port_ab: bool = bool(p.get("aim_broadside_port", true)) if not p.is_empty() else true
	var active_bat: Variant = port_b if sel_port_ab else stbd_b2
	var mode_lbl: String = "Ripple"
	if port_b != null and port_b.fire_mode == _BatteryController.FireMode.SALVO:
		mode_lbl = "Barrage"
	_draw_ability_slot(font, Vector2(x + 8.0, y + 12.0), _slot_key_caption(FIRE_MODE_ACTION), mode_lbl, true)
	var elev_lbl: String = "+0.0°"
	if active_bat != null:
		elev_lbl = active_bat.elevation_label()
	_draw_ability_slot(font, Vector2(x + 138.0, y + 12.0), "R/T", elev_lbl, true)
	var helm: Variant = p.get("helm")
	var wheel_locked: bool = helm != null and bool(helm.wheel_locked)
	_draw_ability_slot(font, Vector2(x + 268.0, y + 12.0), _slot_key_caption(WHEEL_LOCK_ACTION), "Wheel lock", wheel_locked)
	var ready_count: int = 0
	var total_count: int = 0
	if active_bat != null:
		total_count = 1
		if active_bat.state == _BatteryController.BatteryState.READY:
			ready_count = 1
	var side_lbl: String = "P" if sel_port_ab else "S"
	var fire_key: String = _slot_key_caption(_ACTIONS.atk)
	var fire_lbl: String = "FIRE %s %d/%d" % [side_lbl, ready_count, total_count]
	_draw_ability_slot(font, Vector2(x + 398.0, y + 12.0), fire_key, fire_lbl, ready_count > 0)
	var cam_hint: String = ""
	if not _camera_locked:
		cam_hint = " · FREE CAM (press 1 to snap back)"
	var hint: String = "Bindings shown in panel above · Pause Esc" + cam_hint
	draw_string(font, Vector2(x + 10.0, y - 4.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.82, 0.64, 0.95))


func _ensure_zoom_buttons() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UILayer")
	if ui_layer == null:
		return
	if _zoom_in_button == null:
		_zoom_in_button = Button.new()
		_zoom_in_button.name = "ZoomInButton"
		_zoom_in_button.text = "+"
		_zoom_in_button.size = Vector2(40.0, 36.0)
		_zoom_in_button.position = Vector2(1218.0, 14.0)
		_zoom_in_button.add_theme_font_size_override("font_size", 22)
		ui_layer.add_child(_zoom_in_button)
		if not _zoom_in_button.pressed.is_connected(_on_zoom_in_pressed):
			_zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	if _zoom_out_button == null:
		_zoom_out_button = Button.new()
		_zoom_out_button.name = "ZoomOutButton"
		_zoom_out_button.text = "-"
		_zoom_out_button.size = Vector2(40.0, 36.0)
		_zoom_out_button.position = Vector2(1172.0, 14.0)
		_zoom_out_button.add_theme_font_size_override("font_size", 22)
		ui_layer.add_child(_zoom_out_button)
		if not _zoom_out_button.pressed.is_connected(_on_zoom_out_pressed):
			_zoom_out_button.pressed.connect(_on_zoom_out_pressed)


func _on_zoom_in_pressed() -> void:
	_zoom = clampf(_zoom + _ZOOM_STEP_FINE, _ZOOM_MIN, _ZOOM_MAX)
	queue_redraw()


func _on_zoom_out_pressed() -> void:
	_zoom = clampf(_zoom - _ZOOM_STEP_FINE, _ZOOM_MIN, _ZOOM_MAX)
	queue_redraw()

func _draw_ability_slot(font: Font, pos: Vector2, key_name: String, label: String, enabled: bool) -> void:
	var col: Color = Color(0.28, 0.85, 0.56, 0.95) if enabled else Color(0.56, 0.64, 0.72, 0.95)
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), Color(0.16, 0.20, 0.24, 0.9))
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), col, false, 1.6)
	draw_string(font, pos + Vector2(6.0, 18.0), "[%s] %s" % [key_name, label], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
