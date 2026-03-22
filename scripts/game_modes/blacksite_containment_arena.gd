extends "res://scripts/iso_arena.gd"

# Open-sea sailing mode on the iso arena baseline (pirate ship sprites, helm + sail).

const MapProfile := preload("res://scripts/shared/blacksite_map_profile.gd")
const _SailController := preload("res://scripts/shared/sail_controller.gd")
const _HelmController := preload("res://scripts/shared/helm_controller.gd")
const _MotionStateResolver := preload("res://scripts/shared/motion_state_resolver.gd")
const _BatteryController := preload("res://scripts/shared/battery_controller.gd")
const _CannonBallistics := preload("res://scripts/shared/cannon_ballistics.gd")

## Emitted when local ship linear motion classification or turn flags change (req-motion-fsm §9).
signal motion_state_changed(prev_linear: int, new_linear: int, is_turning: bool, is_turning_hard: bool)
## Forwards BatteryController state transitions with battery reference (req-battery-fsm §8).
signal battery_fsm_state_changed(battery: _BatteryController, new_state: _BatteryController.BatteryState)

var _map_layout: Dictionary = {}
var _projectiles: Array[Dictionary] = []
## Transient water splashes from cannonballs: { wx, wy, t }
var _splash_fx: Array[Dictionary] = []
var _move_sfx_cooldown: float = 0.0
var _ability_e_enabled: bool = false
var _sfx_player: AudioStreamPlayer = null
var _pad_fire_prev: bool = false
var _pad_e_prev: bool = false
var _motion_sig_init: bool = false
var _prev_motion_linear: int = 0
var _prev_motion_turn: bool = false
var _prev_motion_turn_hard: bool = false

const ABILITY_E_ACTION: String = "bf_ability_e"
const SAIL_RAISE_ACTION: String = "bf_sail_raise"
const SAIL_LOWER_ACTION: String = "bf_sail_lower"
const BROADSIDE_PORT_ACTION: String = "bf_broadside_port"
const BROADSIDE_STBD_ACTION: String = "bf_broadside_stbd"
const FIRE_MODE_ACTION: String = "bf_fire_mode"
const AUTOFIRE_ACTION: String = "bf_autofire"
## Min dot(aim, direction_to_opponent) to treat opponent as aim target for battery range (req-battery-fsm §6).
const _BATTERY_AIM_ALIGN_DOT: float = 0.35
## Half-angle (degrees) for broadside cone — tighter than full swivel for ship-appropriate arcs.
const _BROADSIDE_ARC_DEG: float = 36.0

## Forward motion (req-motion-fsm §5.1) + sail coasting (req-sail-fsm §6.3).
const MOTION_ACCEL: float = 24.0
const MOTION_DECEL_ABOVE_TARGET: float = 0.95
const MOTION_PASSIVE_DRAG_K: float = 0.35
const COAST_DRAG_MULT: float = 2.0
const MOTION_ZERO_SAIL_DRAG: float = 0.55
## req-motion-fsm §5.3 / §7 — rudder bleeds forward speed.
const MOTION_TURNING_SPEED_LOSS: float = 0.22
const MOTION_HARD_TURN_SPEED_LOSS: float = 0.38
const MOTION_HARD_TURN_RUDDER: float = 0.7
## Rudder authority scales with forward speed (req-helm-fsm §7); ~50% max_speed for full authority.
const HELM_EFFECTIVE_TURN_SPEED: float = 2.5
const HELM_TURN_ACCEL: float = 2.8
const HELM_TURN_DAMPING: float = 0.92
const PROJECTILE_DAMAGE: float = 25.0
const _STICK_DEADZONE: float = 0.2
const _SPLASH_DURATION: float = 0.42

func _load_geo_map() -> void:
	_map_layout = MapProfile.configure_renderer(_terrain_renderer)
	_terrain_renderer.chunk_size = CHUNK_SIZE
	var data: Dictionary = {
		"width": int(_map_layout.get("map_width", MapProfile.MAP_WIDTH)),
		"height": int(_map_layout.get("map_height", MapProfile.MAP_HEIGHT)),
	}
	_projectiles.clear()
	_splash_fx.clear()
	_SPAWNS = MapProfile.build_drone_spawns(data)

func _ready() -> void:
	super._ready()
	_init_blacksite_movement_state()
	_ensure_audio_player()


func _init_blacksite_movement_state() -> void:
	for p in _players:
		var sail = _SailController.new()
		sail.max_speed = SPEED
		sail.sail_raise_rate = 0.5
		sail.sail_lower_rate = 0.55
		p["sail"] = sail
		var helm = _HelmController.new()
		p["helm"] = helm
		p["move_speed"] = 0.0
		p["angular_velocity"] = 0.0
		p["aim_broadside_port"] = true
		p["aim_dir"] = Vector2(p.dir.x, p.dir.y)
		var motion: _MotionStateResolver = _MotionStateResolver.new()
		motion.max_speed_ref = SPEED
		p["motion"] = motion
		var bat_p: _BatteryController = _BatteryController.new()
		bat_p.side = _BatteryController.BatterySide.PORT
		bat_p.cannon_count = 3
		bat_p.reload_time = 2.6
		bat_p.fire_sequence_duration = 0.18
		bat_p.battery_damage = 75.0
		bat_p.firing_arc_degrees = _BROADSIDE_ARC_DEG
		bat_p.fire_mode = _BatteryController.FireMode.RIPPLE
		p["battery_port"] = bat_p
		var bat_s: _BatteryController = _BatteryController.new()
		bat_s.side = _BatteryController.BatterySide.STARBOARD
		bat_s.cannon_count = 3
		bat_s.reload_time = 2.6
		bat_s.fire_sequence_duration = 0.18
		bat_s.battery_damage = 75.0
		bat_s.firing_arc_degrees = _BROADSIDE_ARC_DEG
		bat_s.fire_mode = _BatteryController.FireMode.RIPPLE
		p["battery_stbd"] = bat_s
		p["helm_state_prev"] = -1
		bat_p.battery_state_changed.connect(func(s, ns): _forward_battery_state(bat_p, s, ns))
		bat_s.battery_state_changed.connect(func(s, ns): _forward_battery_state(bat_s, s, ns))


func _forward_battery_state(bat: _BatteryController, _side: _BatteryController.BatterySide, new_state: _BatteryController.BatteryState) -> void:
	battery_fsm_state_changed.emit(bat, new_state)


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

	_set_action_keys(BROADSIDE_PORT_ACTION, [KEY_Q, KEY_LEFT])
	_set_action_keys(BROADSIDE_STBD_ACTION, [KEY_E, KEY_RIGHT])
	_ensure_joy_button_for_action(BROADSIDE_PORT_ACTION, JOY_BUTTON_LEFT_SHOULDER)
	_ensure_joy_button_for_action(BROADSIDE_STBD_ACTION, JOY_BUTTON_RIGHT_SHOULDER)

	_set_action_keys(FIRE_MODE_ACTION, [KEY_B])
	_ensure_joy_button_for_action(FIRE_MODE_ACTION, JOY_BUTTON_BACK)
	_set_action_keys(AUTOFIRE_ACTION, [KEY_V])
	_ensure_joy_button_for_action(AUTOFIRE_ACTION, JOY_BUTTON_START)

	_set_action_keys(ABILITY_E_ACTION, [KEY_K])
	_ensure_joy_button_for_action(ABILITY_E_ACTION, JOY_BUTTON_Y)

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

func _process(delta: float) -> void:
	super._process(delta)
	_tick_projectiles(delta)
	_tick_splash_fx(delta)
	_tick_local_timers(delta)
	_handle_ability_toggles()
	queue_redraw()

func _tick_player(p: Dictionary, delta: float) -> void:
	if pause_menu_panel != null and pause_menu_panel.visible:
		return
	if not p.alive:
		return

	var pad_id: int = _get_primary_pad_id()

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

	var helm = p.get("helm")
	if helm == null:
		helm = _HelmController.new()
		p["helm"] = helm
	helm.process_steer(delta, steer_l, steer_r)

	var hull: Vector2 = Vector2(p.dir.x, p.dir.y)
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var ang_vel: float = float(p.get("angular_velocity", 0.0))
	var spd_for_turn: float = float(p.get("move_speed", 0.0))
	var speed_factor: float = clampf(spd_for_turn / HELM_EFFECTIVE_TURN_SPEED, 0.0, 1.0)
	var turn_strength: float = helm.rudder_angle * speed_factor
	ang_vel += turn_strength * HELM_TURN_ACCEL * delta
	ang_vel *= HELM_TURN_DAMPING
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
		if Input.is_action_just_pressed(AUTOFIRE_ACTION):
			var na: bool = not port_bat.auto_fire_enabled
			port_bat.auto_fire_enabled = na
			stbd_bat.auto_fire_enabled = na
			_play_tone(260.0 if na else 190.0, 0.05, 0.11)

	var sail = p.get("sail")
	if sail == null:
		sail = _SailController.new()
		sail.max_speed = SPEED
		p["sail"] = sail
	sail.process(delta)

	if Input.is_action_just_pressed(SAIL_RAISE_ACTION):
		sail.raise_step()
		_play_tone(255.0, 0.04, 0.14)
	if Input.is_action_just_pressed(SAIL_LOWER_ACTION):
		sail.lower_step()
		_play_tone(175.0, 0.04, 0.12)

	var target_cap: float = sail.get_target_speed()
	var spd: float = float(p.get("move_speed", 0.0))
	var drag_mult: float = COAST_DRAG_MULT if sail.current_sail_level < sail.coast_drag_threshold else 1.0
	var rud_abs: float = absf(helm.rudder_angle)

	if spd < target_cap:
		spd = minf(spd + MOTION_ACCEL * delta, target_cap)
	else:
		spd = maxf(0.0, spd - MOTION_DECEL_ABOVE_TARGET * drag_mult * delta)

	spd = maxf(0.0, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * delta)
	if sail.current_sail_level < sail.coast_drag_threshold:
		spd = maxf(0.0, spd - MOTION_ZERO_SAIL_DRAG * drag_mult * delta)

	spd = maxf(0.0, spd - rud_abs * MOTION_TURNING_SPEED_LOSS * delta)
	if rud_abs > MOTION_HARD_TURN_RUDDER:
		spd = maxf(0.0, spd - rud_abs * MOTION_HARD_TURN_SPEED_LOSS * delta)

	spd = clampf(spd, 0.0, sail.max_speed * 1.15)
	p["move_speed"] = spd

	var motion = p.get("motion")
	if motion != null:
		motion.max_speed_ref = sail.max_speed
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
		if _is_walkable_tile(_terrain_renderer.get_tile_at(new_wx, new_wy)):
			p.wx = new_wx
			p.wy = new_wy
		p.moving = true
		p.walk_time += delta
		if _move_sfx_cooldown <= 0.0 and spd > 0.35:
			_play_tone(108.0, 0.050, 0.14)
			_move_sfx_cooldown = 0.11
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
	var pd: float = aim_n.dot(hull_n.rotated(PI * 0.5))
	var sd: float = aim_n.dot(hull_n.rotated(-PI * 0.5))
	var prefer_port: bool = pd >= sd

	var ship_pos := Vector2(float(p.wx), float(p.wy))
	var port_b = port_bat
	var stbd_b = stbd_bat
	var max_bat_range: float = 14.0
	if port_b != null:
		max_bat_range = maxf(max_bat_range, port_b.max_range)
	if stbd_b != null:
		max_bat_range = maxf(max_bat_range, stbd_b.max_range)
	var target_dist_m: float = _battery_target_distance_m(p, aim_n, max_bat_range)
	var fired_any: bool = false
	if port_b != null:
		for spread in port_b.process_frame(delta, hull_n, aim_n, ship_pos, fire_just_pressed and prefer_port, target_dist_m):
			_fire_projectile(p, spread, port_b.damage_per_shot_for_current_mode())
			fired_any = true
	if stbd_b != null:
		for spread in stbd_b.process_frame(delta, hull_n, aim_n, ship_pos, fire_just_pressed and not prefer_port, target_dist_m):
			_fire_projectile(p, spread, stbd_b.damage_per_shot_for_current_mode())
			fired_any = true

	if fired_any:
		_play_tone(410.0, 0.045, 0.10)
		p.atk_time = ATK_DUR
		p.hit_landed = false
	p.atk_time = maxf(p.atk_time - delta, 0.0)

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

func _check_hit(_attacker: Dictionary, _defender: Dictionary) -> void:
	# Disable melee arc checks; combat in Blacksite is ranged projectile-driven.
	return

func _fire_projectile(p: Dictionary, spread_bias: float = 0.0, shot_damage: float = PROJECTILE_DAMAGE) -> void:
	var dir: Vector2 = p.get("aim_dir", p.dir)
	if dir.length_squared() <= 0.001:
		dir = Vector2(p.dir.x, p.dir.y)
	if dir.length_squared() <= 0.001:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var owner_peer: int = int(p.get("peer_id", 1))
	if owner_peer <= 0 and multiplayer.has_multiplayer_peer():
		owner_peer = multiplayer.get_unique_id()
	var shot_dir: Vector2 = dir.rotated(spread_bias).normalized()
	var start_x: float = float(p.wx) + shot_dir.x * 0.65
	var start_y: float = float(p.wy) + shot_dir.y * 0.65
	var mass: float = _CannonBallistics.mass_from_damage(shot_damage)
	var vel: Dictionary = _CannonBallistics.initial_velocity(shot_dir, mass)
	if multiplayer.has_multiplayer_peer():
		_spawn_cannonball_rpc.rpc(
			start_x,
			start_y,
			float(vel.vx),
			float(vel.vy),
			float(vel.vz),
			_CannonBallistics.MUZZLE_HEIGHT,
			mass,
			owner_peer,
			shot_damage
		)
	else:
		_spawn_cannonball_local(
			start_x,
			start_y,
			float(vel.vx),
			float(vel.vy),
			float(vel.vz),
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
		"alive": true,
	})


func _tick_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var can_apply_hits: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	var grav: float = _CannonBallistics.GRAVITY
	var sub: float = _CannonBallistics.PHYSICS_SUBSTEP
	var hit_r: float = _CannonBallistics.SHIP_HIT_RADIUS
	var h_min: float = _CannonBallistics.HULL_HIT_MIN_H
	var h_max: float = _CannonBallistics.HULL_HIT_MAX_H
	var t_max: float = _CannonBallistics.MAX_FLIGHT_TIME

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

			if t_flight >= t_max:
				remove_proj = true
				break

			if h <= 0.0:
				_spawn_splash_at_world(wx, wy)
				remove_proj = true
				break

			for j in range(_players.size()):
				var q: Dictionary = _players[j]
				if not bool(q.get("alive", true)):
					continue
				if int(q.get("peer_id", -1)) == owner_peer:
					continue
				var qx: float = float(q.wx)
				var qy: float = float(q.wy)
				var ddx: float = wx - qx
				var ddy: float = wy - qy
				if ddx * ddx + ddy * ddy > hit_r * hit_r:
					continue
				if h < h_min or h > h_max:
					continue
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
			_projectiles[i] = proj


func _spawn_splash_at_world(wx: float, wy: float) -> void:
	_splash_fx.append({"wx": wx, "wy": wy, "t": 0.0})


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


func _apply_cannon_hit_impl(attacker_peer_id: int, defender_peer_id: int, damage: float) -> void:
	var defender_idx: int = _find_player_index_by_peer_id(defender_peer_id)
	if defender_idx < 0:
		return
	var d: Dictionary = _players[defender_idx]
	if not bool(d.get("alive", true)):
		return
	var new_health: float = maxf(float(d.health) - damage, 0.0)
	var defender_alive: bool = new_health > 0.0
	d.health = new_health
	d.alive = defender_alive
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_check_win()


@rpc("authority", "call_local", "reliable")
func _apply_cannon_hit(attacker_peer_id: int, defender_peer_id: int, damage: float) -> void:
	_apply_cannon_hit_impl(attacker_peer_id, defender_peer_id, damage)

func _tick_local_timers(delta: float) -> void:
	_move_sfx_cooldown = maxf(_move_sfx_cooldown - delta, 0.0)

func _handle_ability_toggles() -> void:
	var pad_id: int = _get_primary_pad_id()
	var e_pad: bool = pad_id >= 0 and Input.is_joy_button_pressed(pad_id, JOY_BUTTON_Y)
	var e_just: bool = Input.is_action_just_pressed(ABILITY_E_ACTION) or (e_pad and not _pad_e_prev)
	_pad_e_prev = e_pad

	if e_just:
		_ability_e_enabled = not _ability_e_enabled
		_play_tone(390.0, 0.05, 0.20)

func _ensure_audio_player() -> void:
	if _sfx_player != null:
		return
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "BlacksiteSfxPlayer"
	add_child(_sfx_player)

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

func _draw() -> void:
	var vp := get_viewport_rect().size
	var me: Dictionary = _players[_my_index]
	_origin = vp * 0.5 - Vector2((me.wx - me.wy) * TILE_W * _zoom * 0.5, (me.wx + me.wy) * TILE_H * _zoom * 0.5)

	draw_rect(Rect2(Vector2.ZERO, vp), MapProfile.SEA_SKY)
	_draw_tiles(vp)
	var pulse_time: float = Time.get_ticks_msec() * 0.001
	MapProfile.draw_map_overlay(self, _origin, TILE_W * _zoom, TILE_H * _zoom, _map_layout, pulse_time)
	_draw_splash_fx()

	var sorted := _players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.wx + a.wy) < (b.wx + b.wy))
	for p in sorted:
		_draw_player(p)

	_draw_projectiles()
	_draw_motion_battery_hud(vp)
	_draw_helm_sail_hud(vp)
	_draw_offscreen_indicators(vp)
	_draw_hud(vp)
	_draw_keybindings_panel(vp)
	_draw_ability_bar(vp)
	if _winner != -2:
		_draw_win_screen(vp)

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
		var trail: Vector2 = _dir_screen(vx, vy) * 6.0 * _zoom if horiz.length_squared() > 0.0001 else Vector2.RIGHT * 4.0 * _zoom
		var core: Color = Color(0.18, 0.17, 0.16, 1.0)
		var rim: Color = Color(0.42, 0.40, 0.38, 0.95)
		var rad: float = (2.4 + minf(h * 0.12, 1.2)) * _zoom
		draw_line(sp - trail * 0.35, sp + trail * 0.5, Color(0.35, 0.32, 0.28, 0.45), 1.5)
		draw_circle(sp, rad + 0.8 * _zoom, rim)
		draw_circle(sp, rad, core)


func _draw_motion_battery_hud(vp: Vector2) -> void:
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
	draw_string(font, Vector2(x, bat_y), "Batteries", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	_draw_battery_row(font, x, bat_y + 16.0, panel_w, p.get("battery_port"), txt, sub, dim)
	_draw_battery_row(font, x, bat_y + 44.0, panel_w, p.get("battery_stbd"), txt, sub, dim)


func _draw_battery_row(font: Font, x: float, y: float, panel_w: float, bat: Variant, txt: Color, sub: Color, dim: Color) -> void:
	if bat == null:
		draw_string(font, Vector2(x, y), "Battery —", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		return
	var b: _BatteryController = bat
	var line: String = "%s · %s · %s" % [b.side_label(), b.fire_mode_display(), b.state_display()]
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

	var bar_w: float = panel_w - 8.0
	var sail_y: float = y + 72.0
	draw_rect(Rect2(x, sail_y, bar_w, 8.0), Color(0.08, 0.1, 0.14, 0.92))
	draw_rect(Rect2(x, sail_y, bar_w * clampf(sail.current_sail_level, 0.0, 1.0), 8.0), Color(0.26, 0.74, 0.96, 0.92))

	var wheel_y: float = sail_y + 18.0
	var cx: float = x + bar_w * 0.5
	draw_rect(Rect2(x, wheel_y, bar_w, 11.0), Color(0.08, 0.1, 0.14, 0.92))
	draw_line(Vector2(cx, wheel_y + 1.0), Vector2(cx, wheel_y + 10.0), Color(0.42, 0.48, 0.56, 0.75), 1.0)
	var t_wheel: float = (helm.wheel_position + 1.0) * 0.5
	var knob_cx: float = x + clampf(t_wheel, 0.0, 1.0) * bar_w
	draw_rect(Rect2(knob_cx - 2.5, wheel_y + 2.0, 5.0, 7.0), Color(0.92, 0.86, 0.68, 0.96))
	var t_rud: float = (helm.rudder_angle + 1.0) * 0.5
	var rud_cx: float = x + clampf(t_rud, 0.0, 1.0) * bar_w
	draw_circle(Vector2(rud_cx, wheel_y + 5.5), 3.2, Color(0.4, 0.92, 0.7, 0.88))
	draw_string(font, Vector2(x, wheel_y + 14.0), "Wheel bar · rudder dot", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.62, 0.72, 0.82))


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
		"Q / ← / LB: aim PORT broadside only (does not shoot)",
		"E / → / RB: aim STARBOARD broadside only (does not shoot)",
		"F / X / RT: manual fire (no enemy needed). Autofire on: needs target in arc + range",
		"—  E is not fire or scan. Scan = K / Y. F alone shoots; no E+F combo.",
		"Steer: %s / %s" % [_action_keys_display(_ACTIONS.left), _action_keys_display(_ACTIONS.right)],
		"Sail up · down: %s · %s" % [_action_keys_display(SAIL_RAISE_ACTION), _action_keys_display(SAIL_LOWER_ACTION)],
		"Fire mode: %s" % _action_keys_display(FIRE_MODE_ACTION),
		"Autofire: %s" % _action_keys_display(AUTOFIRE_ACTION),
		"Scan: %s" % _action_keys_display(ABILITY_E_ACTION),
	]
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
	var bar_w: float = 420.0
	var bar_h: float = 54.0
	var x: float = (vp.x - bar_w) * 0.5
	var y: float = vp.y - bar_h - 16.0
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.10, 0.12, 0.16, 0.82))
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.34, 0.42, 0.52, 0.9), false, 2.0)
	var p: Dictionary = _players[_my_index] if not _players.is_empty() else {}
	var port_b: Variant = p.get("battery_port")
	var mode_lbl: String = "Ripple"
	if port_b != null and port_b.fire_mode == _BatteryController.FireMode.SALVO:
		mode_lbl = "Barrage"
	var auto_on: bool = port_b != null and port_b.auto_fire_enabled
	_draw_ability_slot(font, Vector2(x + 8.0, y + 12.0), _slot_key_caption(ABILITY_E_ACTION), "Scan", _ability_e_enabled)
	_draw_ability_slot(font, Vector2(x + 128.0, y + 12.0), _slot_key_caption(FIRE_MODE_ACTION), mode_lbl, true)
	_draw_ability_slot(font, Vector2(x + 248.0, y + 12.0), _slot_key_caption(AUTOFIRE_ACTION), "Auto fire", auto_on)
	var hint: String = "Bindings shown in panel above · Pause Esc"
	draw_string(font, Vector2(x + 10.0, y - 4.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.82, 0.64, 0.95))

func _draw_ability_slot(font: Font, pos: Vector2, key_name: String, label: String, enabled: bool) -> void:
	var col: Color = Color(0.28, 0.85, 0.56, 0.95) if enabled else Color(0.56, 0.64, 0.72, 0.95)
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), Color(0.16, 0.20, 0.24, 0.9))
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), col, false, 1.6)
	draw_string(font, pos + Vector2(6.0, 18.0), "[%s] %s" % [key_name, label], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
