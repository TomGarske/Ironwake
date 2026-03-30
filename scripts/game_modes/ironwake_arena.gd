extends "res://scripts/iso_arena.gd"

# Open-sea sailing mode on the iso arena baseline (pirate ship sprites, helm + sail).

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const MapProfile := preload("res://scripts/shared/ironwake_map_profile.gd")
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
## When unlocked, viewport center tracks this world point (ship is not re-centered each frame).
var _camera_world_anchor: Vector2 = Vector2.ZERO
## When true, view follows local ship each frame. Default off until 1/Home/Tab.
var _camera_locked: bool = false
## Which player index the camera follows (separate from _my_index for spectating bots).
var _camera_follow_index: int = 0
var _middle_drag_active: bool = false
var _middle_drag_prev: Vector2 = Vector2.ZERO
## Bot integration: arrays for multi-bot support.  (req-ai-naval-bot-v1)
var _bot_controllers: Array = []   # Array[NavalBotController]
var _bot_agents: Array = []        # Array[BotShipAgent]
var _bot_indices: Array[int] = []  # indices into _players
var _is_local_sim: bool = false
## Tracks cooldown between ram damage events: key = "i_j" (sorted indices), value = seconds remaining.
var _ram_cooldowns: Dictionary = {}
## Per-player scoreboard stats: peer_id -> {kills, deaths, shots_fired, shots_hit, damage_dealt, damage_taken}
var _scoreboard: Dictionary = {}
## Set true when match ends — gates post-match HUD and return flow.
var _match_over: bool = false
## Post-match: after END_DELAY, accept any key to return to menu.
var _post_match_ready: bool = false
## Smooth zoom target — lerped toward each frame when auto-zoom is active.
var _zoom_target: float = NC.NAVAL_DEFAULT_ZOOM

## Fade timers: each HUD element fades out after its trigger condition stops.
## Value = seconds remaining of full opacity; element fades over last 1.5s.
const _HUD_FADE_DURATION: float = 1.5
var _fade_path_line: float = 0.0
var _fade_accuracy_ring: float = 0.0
var _fade_ballistics_arc: float = 0.0
var _fade_elev_hud: float = 0.0
## Track previous-frame state to detect changes.
var _prev_rudder_angle: float = 0.0
var _prev_sail_state: int = -1
var _prev_wheel_velocity: float = 0.0
var _prev_elev_adjusting: bool = false

@export_group("Local sim (req-local-sim-v1)")
@export var local_sim_enabled: bool = true
@export_range(1, 4, 1) var local_sim_bot_count: int = 3

@export_group("Combat debug (req-debug-combat-v1)")
@export var combat_debug_hud_enabled: bool = false  # agent state panels; F3 to expand (debug builds)
@export var combat_debug_world_draw: bool = false
@export var combat_debug_log: bool = true

const CAMERA_LOCK_ACTION: String = "bf_camera_lock"
const SCOREBOARD_ACTION: String = "bf_scoreboard"

const SAIL_RAISE_ACTION: String = "bf_sail_raise"
const SAIL_LOWER_ACTION: String = "bf_sail_lower"
const BROADSIDE_PORT_ACTION: String = "bf_broadside_port"
const BROADSIDE_STBD_ACTION: String = "bf_broadside_stbd"
const FIRE_MODE_ACTION: String = "bf_fire_mode"
const WHEEL_LOCK_ACTION: String = "bf_wheel_lock"
const ELEV_UP_ACTION: String = "bf_elev_up"
const ELEV_DOWN_ACTION: String = "bf_elev_down"
## Min dot(aim, direction_to_opponent) to treat opponent as aim target for battery range (req-battery-fsm §6).
const _BATTERY_AIM_ALIGN_DOT: float = 0.35
## Auto-aim elevation: how fast (fraction per second) cannon_elevation lerps toward the target angle.
## 0.25 = 25% of the gap closed per second — slow enough to feel manual, fast enough to be useful.
const _AUTO_AIM_RATE: float = 0.25
## Auto-zoom: zoom range mapped from minimum ballistic range to maximum.
const _AUTO_ZOOM_RATE: float = 2.5   ## zoom units/sec lerp speed
const _AUTO_ZOOM_MARGIN: float = 1.5 ## show 50% more world than the impact point

## Forward motion — heavy hull: very low drag so speed carries (momentum).
const MOTION_PASSIVE_DRAG_K: float = 0.012
const COAST_DRAG_MULT: float = 1.6
const MOTION_ZERO_SAIL_DRAG: float = 0.025
## Rudder deadzone — below this normalized angle the helm produces no turn (reduces twitchiness).
## Inputs above the deadzone are rescaled to fill the full 0→1 range so feel is preserved.
const RUDDER_DEADZONE: float = 0.08
## Rudder bleeds forward speed — sharper turns lose more speed.
## A hard turn at full sail should cost 20–30% speed within a few seconds.
const MOTION_TURNING_SPEED_LOSS: float = 0.18
const MOTION_HARD_TURN_SPEED_LOSS: float = 0.35
const MOTION_HARD_TURN_RUDDER: float = 0.7
## Each cannonball impact removes this many hull points (structural hit model).
const HULL_DAMAGE_PER_HIT: float = 1.0
## Hull integrity: total structural hits before sinking.
const HULL_HITS_MAX: float = 16.0
## Ramming — collision between two ships.
## Minimum closing speed (m/s) before any damage is applied.
const RAM_MIN_SPEED: float = 3.0
## Damage per m/s of closing velocity above the threshold.
## At 10 m/s closing speed: (10-3) * 0.35 ≈ 2.4 hull hits. Lethal ramming takes serious speed.
const RAM_DAMAGE_PER_MPS: float = 0.35
## Bow/stern take half damage — reinforced structure, ram beak at prow.
const RAM_BOW_STERN_DAMAGE_MULT: float = 0.5
## Speed bled from each ship on impact, proportional to closing velocity.
const RAM_SPEED_LOSS_MULT: float = 0.6
## Minimum time between collision checks for the same pair (prevents double-tick damage).
const RAM_COOLDOWN_SEC: float = 1.5
## Overlap distance (m) below which hulls are considered colliding.
## Ships have an elliptical footprint; this is the sum-of-radii threshold in the
## approach direction. Checked against the average half-width for side-on collisions.
const RAM_COLLISION_DIST: float = 12.0
const _STICK_DEADZONE: float = 0.2
const _SPLASH_DURATION: float = 0.42
const _HULL_STRIKE_DURATION: float = 0.4
const _PROJECTILE_HIT_ARM_TIME: float = 0.025
const _MUZZLE_FLASH_DURATION: float = 0.15
const _MUZZLE_SMOKE_DURATION: float = 2.0
## Display scale: maps game speed to realistic age-of-sail knots (~13 kn at full speed).
## 74-gun 3rd rate (HMS Bellona): ~13 kn full, ~7.6 kn half, ~4.3 kn quarter.
const _KNOTS_PER_GAME_UNIT: float = 0.4727
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
	return _w2s(float(p.wx), float(p.wy)) + _deck_lift_offset_for_screen(p)


func _ready() -> void:
	super._ready()
	_init_ironwake_movement_state()
	_spawn_local_sim_bot_if_needed()
	# Set spawn zoom to match the ballistic range at default 0° elevation.
	# This is the same zoom level the player sees when adjusting cannons at 0°.
	var spawn_bat: Variant = null
	if not _players.is_empty():
		spawn_bat = _players[_my_index].get("battery_port")
	if spawn_bat != null:
		_zoom = _zoom_for_battery_range(spawn_bat)
	else:
		_zoom = NC.NAVAL_DEFAULT_ZOOM
	_zoom_target = _zoom
	# Start with camera locked on the player's ship.
	_camera_locked = true
	_camera_follow_index = _my_index
	if not _players.is_empty():
		var sp: Dictionary = _players[_my_index]
		_camera_world_anchor = Vector2(float(sp.wx), float(sp.wy))
	else:
		_camera_world_anchor = MapProfile.get_default_view_focus(_map_layout)
	_ensure_audio_player()


func _unhandled_input(event: InputEvent) -> void:
	# Post-match: any key/button press returns to menu.
	if _post_match_ready and event.is_pressed() and not event.is_echo():
		# Ignore mouse motion and scroll wheel.
		if event is InputEventMouseMotion:
			pass
		elif event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			pass
		else:
			_return_to_menu()
			return
	if event is InputEventMouseButton:
		# Consume scroll wheel — zoom is driven entirely by battery ballistics.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				_middle_drag_active = true
				_middle_drag_prev = event.position
				if _camera_locked and not _players.is_empty():
					var cfi: int = clampi(_camera_follow_index, 0, _players.size() - 1)
					var mp: Dictionary = _players[cfi]
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
		if event.keycode == KEY_HOME or event.keycode == KEY_1:
			_camera_follow_index = _my_index
			_camera_locked = true
			queue_redraw()
			return
		if event.keycode >= KEY_2 and event.keycode <= KEY_9:
			var target_idx: int = int(event.keycode) - int(KEY_1)
			if target_idx >= 0 and target_idx < _players.size():
				_camera_follow_index = target_idx
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


func _init_ironwake_movement_state() -> void:
	for p in _players:
		p["health"] = HULL_HITS_MAX
		p.erase("respawn_timer")
		_apply_naval_controllers_to_ship(p)
		var pid: int = int(p.get("peer_id", 0))
		if not _scoreboard.has(pid):
			_scoreboard[pid] = {
				"kills": 0, "deaths": 0,
				"shots_fired": 0, "shots_hit": 0,
				"damage_dealt": 0.0, "damage_taken": 0.0,
			}


## Sail/helm/batteries/motion — quarter sail deployed at max quarter speed.
func _apply_naval_controllers_to_ship(p: Dictionary) -> void:
	var sail := _SailController.new()
	sail.max_speed = NC.MAX_SPEED
	## Raise rate: ~6.5s STOP→FULL (setting canvas is slow — unfurl, sheet home, brace).
	sail.sail_raise_rate = 0.15
	## Lower rate: ~3s FULL→STOP (gravity-assisted — clew up and furl).
	sail.sail_lower_rate = 0.33
	sail.sail_state = _SailController.SailState.QUARTER
	sail.current_sail_level = 0.25
	p["sail"] = sail
	var helm := _HelmController.new()
	helm.wheel_spin_accel = 2.0
	helm.wheel_max_spin = 0.55
	helm.wheel_friction = 2.5
	## Rudder follow rate: ~2 seconds center-to-full deflection (responsive gameplay).
	helm.rudder_follow_rate = 0.5
	p["helm"] = helm
	p["move_speed"] = NC.QUARTER_SPEED
	p["angular_velocity"] = 0.0
	p["aim_port_active"] = true
	p["aim_stbd_active"] = true
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
	bat_p.cannon_count = 14
	bat_p.reload_time = NC.RELOAD_TIME_SEC
	bat_p.fire_sequence_duration = 4.0
	bat_p.battery_damage = 75.0
	bat_p.firing_arc_degrees = NC.BROADSIDE_HALF_ARC_DEG
	bat_p.max_range = NC.MAX_CANNON_RANGE
	bat_p.fire_mode = _BatteryController.FireMode.RIPPLE
	p["battery_port"] = bat_p
	var bat_s: _BatteryController = _BatteryController.new()
	bat_s.side = _BatteryController.BatterySide.STARBOARD
	bat_s.cannon_count = 14
	bat_s.reload_time = NC.RELOAD_TIME_SEC
	bat_s.fire_sequence_duration = 4.0
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
	var total_ships: int = 1 + bot_count

	# Compute spawn ring around the map center — player + all bots on a circle facing inward.
	var u: float = NC.UNITS_PER_LOGIC_TILE
	var center: Vector2 = Vector2(float(NC.MAP_TILES_WIDE) * 0.5 * u, float(NC.MAP_TILES_HIGH) * 0.5 * u)
	var ring: Array[Dictionary] = _LocalSimController.compute_spawn_ring(center, sim.spawn_circle_radius, total_ships)

	# Reposition player onto the ring (index 0).
	player_dict.wx = ring[0].wx
	player_dict.wy = ring[0].wy
	player_dict.dir = ring[0].dir
	print("[LocalSim] Player respawned onto ring at (%.0f, %.0f)" % [player_dict.wx, player_dict.wy])

	for bot_i in range(bot_count):
		var spawn_info: Dictionary = ring[1 + bot_i]
		var bot_dict: Dictionary = sim.create_bot_entry(spawn_info, bot_i)
		_players.append(bot_dict)
		var idx: int = _players.size() - 1
		_bot_indices.append(idx)

		# Initialize movement controllers on the bot — same as player init.
		var p: Dictionary = _players[idx]
		_init_bot_controllers(p)
		# Initialize scoreboard entry for the bot.
		var bot_pid: int = int(p.get("peer_id", 0))
		if not _scoreboard.has(bot_pid):
			_scoreboard[bot_pid] = {
				"kills": 0, "deaths": 0,
				"shots_fired": 0, "shots_hit": 0,
				"damage_dealt": 0.0, "damage_taken": 0.0,
			}

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
	_apply_bot_helm_overrides(p)
	# Bots auto-fire: battery fires as soon as target is in arc and battery is loaded.
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	if port_b != null:
		port_b.auto_fire_enabled = true
	if stbd_b != null:
		stbd_b.auto_fire_enabled = true


func _apply_bot_helm_overrides(p: Dictionary) -> void:
	var helm: Variant = p.get("helm")
	if helm != null:
		helm.wheel_spin_accel = 4.0
		helm.wheel_max_spin = 1.2
		helm.wheel_friction = 6.0
		helm.rudder_follow_rate = 1.4


## Find the bot controller for a given _players index.
func _get_bot_controller_for_index(player_idx: int) -> Variant:
	for i in range(_bot_indices.size()):
		if _bot_indices[i] == player_idx:
			if i < _bot_controllers.size():
				return _bot_controllers[i]
	return null


## Tick the bot ship: run AI decision, then apply intents through identical physics.
## TODO(refactor): Extract shared physics (heading rotation, speed physics, motion FSM,
## position update) into _tick_ship_physics() and call from both _tick_player() and _tick_bot().
## Currently ~130 lines of physics code are duplicated between the two methods.
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
	var steer_auth: float = maxf(NC.RUDDER_AUTHORITY_MIN, clampf(spd_for_turn / NC.RUDDER_AUTHORITY_SPEED, 0.0, 1.0))
	var target_av: float = max_turn_rad * helm.rudder_angle * steer_auth
	var tau: float = NC.HELM_TURN_LAG_SEC
	ang_vel = lerpf(ang_vel, target_av, 1.0 - exp(-delta / tau))
	hull = hull.rotated(ang_vel * delta).normalized()
	p.dir = hull
	p["angular_velocity"] = ang_vel

	# --- Speed physics (identical to _tick_player) ---
	var bot_sail_eff: float = lerpf(1.0, _SailController.MIN_EFFICIENCY, sail.damage)
	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match sail.sail_state:
		_SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED * bot_sail_eff
		_SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED * bot_sail_eff
		_SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED * bot_sail_eff
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
	elif spd > target_cap:
		spd = maxf(0.0, spd - decel_r * drag_mult * delta)

	spd = maxf(drift_floor, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * delta)
	if sail.current_sail_level < sail.coast_drag_threshold:
		spd = maxf(drift_floor, spd - MOTION_ZERO_SAIL_DRAG * drag_mult * delta)

	# Turning bleeds speed proportional to rudder angle; harder turns cost much more.
	var turn_loss: float = rud_abs * MOTION_TURNING_SPEED_LOSS * (1.0 + spd / maxf(1.0, NC.MAX_SPEED))
	spd = maxf(drift_floor, spd - turn_loss * delta)
	if rud_abs > MOTION_HARD_TURN_RUDDER:
		var hard_loss: float = rud_abs * MOTION_HARD_TURN_SPEED_LOSS * (1.0 + spd / maxf(1.0, NC.MAX_SPEED))
		spd = maxf(drift_floor, spd - hard_loss * delta)

	spd = clampf(spd, 0.0, NC.MAX_SPEED * 1.05)
	p["move_speed"] = spd

	# --- Motion FSM (mirrors _tick_player) ---
	var motion = p.get("motion")
	if motion != null:
		motion.max_speed_ref = NC.MAX_SPEED
		var lin: int = motion.resolve_linear(spd, target_cap, sail.get_target_sail_level(), sail.current_sail_level)
		var tf: Dictionary = motion.compute_turn_flags(spd, helm.rudder_angle)
		p["linear_motion_state"] = lin
		p["motion_is_turning"] = bool(tf.get("is_turning", false))
		p["motion_is_turning_hard"] = bool(tf.get("is_turning_hard", false))
	var helm_st: int = int(helm.get_helm_state())
	if helm_st != int(p.get("helm_state_prev", -1)):
		p["helm_state_prev"] = helm_st

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
	var aim_n: Vector2 = hull_n.rotated(PI * 0.5) if bool(p.get("aim_port_active", true)) else hull_n.rotated(-PI * 0.5)
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
		var eff_port_aim_b: Vector2 = _effective_broadside_aim_for_side(p, hull_n, true)
		for cannon_slot in port_bat.process_frame(delta, hull_n, eff_port_aim_b, ship_pos, fire_port, target_dist_m):
			_fire_projectile(p, int(cannon_slot), port_bat.damage_per_shot_for_current_mode(), eff_port_aim_b, port_bat)
			fired_any = true
	if stbd_bat != null:
		var eff_stbd_aim_b: Vector2 = _effective_broadside_aim_for_side(p, hull_n, false)
		for cannon_slot in stbd_bat.process_frame(delta, hull_n, eff_stbd_aim_b, ship_pos, fire_stbd, target_dist_m):
			_fire_projectile(p, int(cannon_slot), stbd_bat.damage_per_shot_for_current_mode(), eff_stbd_aim_b, stbd_bat)
			fired_any = true

	if fired_any:
		p.atk_time = ATK_DUR
		p.hit_landed = false
		bot_ctrl._has_fired_at_least_once = true
		print("[Arena] Bot %s fired — port=%s stbd=%s dist=%.0f bearing=%.1f" % [
			str(p.get("label", "?")), fire_port, fire_stbd, target_dist_m, bot_ctrl.bearing_to_target_deg])
	p.atk_time = maxf(p.atk_time - delta, 0.0)

	# --- Update aim side based on target bearing ---
	var target_pos: Vector2 = Vector2(float(bot_ctrl.target_dict.get("wx", 0.0)), float(bot_ctrl.target_dict.get("wy", 0.0)))
	var to_target: Vector2 = target_pos - ship_pos
	if to_target.length_squared() > 1.0:
		var cross_val: float = hull_n.cross(to_target.normalized())
		p["aim_port_active"] = cross_val > 0.0
		p["aim_stbd_active"] = cross_val <= 0.0


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

	_set_action_keys(BROADSIDE_PORT_ACTION, [KEY_E])
	_set_action_keys(BROADSIDE_STBD_ACTION, [KEY_Q])
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

	_set_action_keys(SCOREBOARD_ACTION, [KEY_TAB])


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
	# Post-match: once the delay has elapsed, show "press any key" instead of
	# auto-returning to the menu (the parent would call change_scene_to_file).
	if _match_over and _winner != -2:
		if Input.is_action_just_pressed("ui_cancel"):
			_toggle_pause_menu()
			return
		_end_timer += delta
		if _end_timer >= END_DELAY:
			_post_match_ready = true
		queue_redraw()
	else:
		super._process(delta)
	for bi in _bot_indices:
		if bi >= 0 and bi < _players.size():
			_tick_bot(_players[bi], bi, delta)
	_tick_projectiles(delta)
	_tick_splash_fx(delta)
	_tick_hull_strike_fx(delta)
	_tick_muzzle_fx(delta)
	_tick_local_timers(delta)
	_tick_ramming(delta)
	_tick_respawn(delta)
	_update_hud_fade_timers(delta)
	# Smooth zoom toward target (set by elevation auto-zoom).
	if absf(_zoom - _zoom_target) > 0.0001:
		_zoom = move_toward(_zoom, _zoom_target, _AUTO_ZOOM_RATE * _zoom * delta)
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
			var cfi: int = clampi(_camera_follow_index, 0, _players.size() - 1)
			var ap: Dictionary = _players[cfi]
			_camera_world_anchor = Vector2(float(ap.wx), float(ap.wy))
		_camera_locked = false
		var world_scale: float = _TD_SCALE * _zoom
		if world_scale > 0.001:
			_camera_world_anchor += pan_dir.normalized() * _CAM_PAN_SPEED * delta / world_scale
	queue_redraw()


func _update_hud_fade_timers(delta: float) -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	var helm = p.get("helm")
	var sail = p.get("sail")

	var rudder_changing: bool = false
	var sail_changing: bool = false
	var elev_adjusting: bool = Input.is_action_pressed(ELEV_UP_ACTION) or Input.is_action_pressed(ELEV_DOWN_ACTION)

	if helm != null:
		var cur_rudder: float = helm.rudder_angle
		var cur_wheel_vel: float = helm.wheel_velocity
		rudder_changing = absf(cur_wheel_vel) > 0.02 or absf(cur_rudder - _prev_rudder_angle) > 0.005
		_prev_rudder_angle = cur_rudder
		_prev_wheel_velocity = cur_wheel_vel

	if sail != null:
		var cur_sail: int = int(sail.sail_state)
		sail_changing = cur_sail != _prev_sail_state and _prev_sail_state >= 0
		if sail_changing:
			_prev_sail_state = cur_sail
		elif _prev_sail_state < 0:
			_prev_sail_state = int(sail.sail_state)

	if rudder_changing or sail_changing:
		_fade_path_line = _HUD_FADE_DURATION
	else:
		_fade_path_line = maxf(0.0, _fade_path_line - delta)

	if elev_adjusting:
		_fade_accuracy_ring = _HUD_FADE_DURATION
		_fade_ballistics_arc = _HUD_FADE_DURATION
		_fade_elev_hud = _HUD_FADE_DURATION
	else:
		_fade_accuracy_ring = maxf(0.0, _fade_accuracy_ring - delta)
		_fade_ballistics_arc = maxf(0.0, _fade_ballistics_arc - delta)
		_fade_elev_hud = maxf(0.0, _fade_elev_hud - delta)

	_prev_elev_adjusting = elev_adjusting


func _hud_fade_alpha(fade_timer: float) -> float:
	if fade_timer >= _HUD_FADE_DURATION:
		return 1.0
	if fade_timer <= 0.0:
		return 0.0
	return clampf(fade_timer / _HUD_FADE_DURATION, 0.0, 1.0)

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
	var steer_auth: float = maxf(NC.RUDDER_AUTHORITY_MIN, clampf(spd_for_turn / NC.RUDDER_AUTHORITY_SPEED, 0.0, 1.0))
	# Apply deadzone: ignore small rudder deflections around center to prevent drift.
	var eff_rudder: float = _apply_rudder_deadzone(helm.rudder_angle)
	var target_av: float = max_turn_rad * eff_rudder * steer_auth
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
	var _aim_port_on: bool = bool(p.get("aim_port_active", true))
	var _aim_stbd_on: bool = bool(p.get("aim_stbd_active", false))
	# Elevation adjusts ALL active batteries simultaneously.
	if elev_up or elev_down:
		var elev_dir: float = 1.0 if elev_up else -1.0
		if _aim_port_on and port_bat != null:
			port_bat.adjust_elevation(delta, elev_dir)
		if _aim_stbd_on and stbd_bat != null:
			stbd_bat.adjust_elevation(delta, elev_dir)
	else:
		if port_bat != null:
			port_bat.reset_elevation_hold()
		if stbd_bat != null:
			stbd_bat.reset_elevation_hold()
	# Zoom locks to the farthest active battery's ballistic range — always in sync.
	# Picks whichever active battery has the longer range (lower zoom = wider view).
	var best_zoom: float = _ZOOM_MAX
	var has_active_bat: bool = false
	if _aim_port_on and port_bat != null:
		best_zoom = minf(best_zoom, _zoom_for_battery_range(port_bat))
		has_active_bat = true
	if _aim_stbd_on and stbd_bat != null:
		best_zoom = minf(best_zoom, _zoom_for_battery_range(stbd_bat))
		has_active_bat = true
	if has_active_bat:
		_zoom_target = best_zoom
		_zoom = best_zoom
	else:
		_zoom_target = NC.NAVAL_DEFAULT_ZOOM
		_zoom = NC.NAVAL_DEFAULT_ZOOM

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

	var player_sail_eff: float = lerpf(1.0, _SailController.MIN_EFFICIENCY, sail.damage)
	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match sail.sail_state:
		_SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED * player_sail_eff
		_SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED * player_sail_eff
		_SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED * player_sail_eff
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
	elif spd > target_cap:
		spd = maxf(0.0, spd - decel_r * drag_mult * delta)

	spd = maxf(drift_floor, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * delta)
	if sail.current_sail_level < sail.coast_drag_threshold:
		spd = maxf(drift_floor, spd - MOTION_ZERO_SAIL_DRAG * drag_mult * delta)

	# Turning bleeds speed proportional to rudder angle; harder turns cost much more.
	var turn_loss: float = rud_abs * MOTION_TURNING_SPEED_LOSS * (1.0 + spd / maxf(1.0, NC.MAX_SPEED))
	spd = maxf(drift_floor, spd - turn_loss * delta)
	if rud_abs > MOTION_HARD_TURN_RUDDER:
		var hard_loss: float = rud_abs * MOTION_HARD_TURN_SPEED_LOSS * (1.0 + spd / maxf(1.0, NC.MAX_SPEED))
		spd = maxf(drift_floor, spd - hard_loss * delta)

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
	var fire_port_active: bool = bool(p.get("aim_port_active", true))
	var fire_stbd_active: bool = bool(p.get("aim_stbd_active", false))
	var fired_any: bool = false
	if port_b != null:
		var eff_port_aim: Vector2 = _effective_broadside_aim_for_side(p, hull_n, true)
		var port_fire: bool = fire_just_pressed and fire_port_active
		for cannon_slot in port_b.process_frame(delta, hull_n, eff_port_aim, ship_pos, port_fire, target_dist_m):
			_fire_projectile(p, int(cannon_slot), port_b.damage_per_shot_for_current_mode(), eff_port_aim, port_b)
			fired_any = true
	if stbd_b != null:
		var eff_stbd_aim: Vector2 = _effective_broadside_aim_for_side(p, hull_n, false)
		var stbd_fire: bool = fire_just_pressed and fire_stbd_active
		for cannon_slot in stbd_b.process_frame(delta, hull_n, eff_stbd_aim, ship_pos, stbd_fire, target_dist_m):
			_fire_projectile(p, int(cannon_slot), stbd_b.damage_per_shot_for_current_mode(), eff_stbd_aim, stbd_b)
			fired_any = true

	if fired_any:
		_play_tone(410.0, 0.045, 0.10)
		p.atk_time = ATK_DUR
		p.hit_landed = false
	p.atk_time = maxf(p.atk_time - delta, 0.0)

	# Auto-aim elevation: DISABLED for now.
	# if not elev_up and not elev_down:
	# 	if bool(p.get("aim_port_active", true)) and port_b != null:
	# 		_auto_aim_elevation(p, port_b, hull_n, delta)
	# 	if bool(p.get("aim_stbd_active", false)) and stbd_b != null:
	# 		_auto_aim_elevation(p, stbd_b, hull_n, delta)


func _aim_dir_broadside_to_target(hull: Vector2, to_target_n: Vector2, use_port: bool, half_arc_deg: float) -> Vector2:
	var perp: Vector2 = hull.rotated(PI * 0.5) if use_port else hull.rotated(-PI * 0.5)
	var lim: float = deg_to_rad(half_arc_deg)
	var delta: float = atan2(perp.cross(to_target_n), perp.dot(to_target_n))
	delta = clampf(delta, -lim, lim)
	return perp.rotated(delta).normalized()




## Deadzone + rescale so inputs above the deadzone still reach full authority.
func _apply_rudder_deadzone(raw: float) -> float:
	var a: float = absf(raw)
	if a < RUDDER_DEADZONE:
		return 0.0
	return signf(raw) * (a - RUDDER_DEADZONE) / (1.0 - RUDDER_DEADZONE)


## Compute what zoom level frames the ballistic impact point on screen.
## Uses actual viewport size so it works at any resolution.
func _zoom_for_battery_range(bat: _BatteryController) -> float:
	var elev_rad: float = deg_to_rad(bat.elevation_degrees())
	var vh: float = _CannonBallistics.MUZZLE_SPEED * cos(elev_rad)
	var vz: float = _CannonBallistics.MUZZLE_SPEED * sin(elev_rad)
	var h0: float = _CannonBallistics.MUZZLE_HEIGHT
	var g: float = _CannonBallistics.GRAVITY
	var disc: float = vz * vz + 2.0 * g * h0
	var t_splash: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, g)
	var range_m: float = maxf(1.0, vh * minf(t_splash, NC.PROJECTILE_LIFETIME))
	# Zoom so the impact point sits at the edge of the viewport (with margin).
	# Broadside fires perpendicular to heading, so use the shorter viewport axis
	# to guarantee the reticle is always on screen regardless of ship orientation.
	var vp: Vector2 = get_viewport_rect().size
	var vp_half: float = minf(vp.x, vp.y) * 0.5
	var target_z: float = vp_half / (_TD_SCALE * range_m * _AUTO_ZOOM_MARGIN)
	return clampf(target_z, _ZOOM_MIN, _ZOOM_MAX)


## Binary search for the elevation (degrees) that produces the given range.
## Returns degrees in [ELEV_MIN_DEG, ELEV_MAX_DEG], clamped if range is outside reachable band.
func _elevation_for_range(range_m: float) -> float:
	var lo: float = _BatteryController.ELEV_MIN_DEG
	var hi: float = _BatteryController.ELEV_MAX_DEG
	var h0: float = _CannonBallistics.MUZZLE_HEIGHT
	var g: float = _CannonBallistics.GRAVITY
	var mv: float = _CannonBallistics.MUZZLE_SPEED
	# Check reachable bounds.
	var range_at_lo: float = _range_for_elev_deg(lo, mv, g, h0)
	var range_at_hi: float = _range_for_elev_deg(hi, mv, g, h0)
	if range_m <= range_at_lo:
		return lo
	if range_m >= range_at_hi:
		return hi
	# Binary search — 16 iterations is plenty for float precision.
	for _i in range(16):
		var mid: float = (lo + hi) * 0.5
		if _range_for_elev_deg(mid, mv, g, h0) < range_m:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _range_for_elev_deg(elev_deg: float, mv: float, g: float, h0: float) -> float:
	var elev_rad: float = deg_to_rad(elev_deg)
	var vh: float = mv * cos(elev_rad)
	var vz: float = mv * sin(elev_rad)
	var disc: float = vz * vz + 2.0 * g * h0
	var t: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, g)
	return vh * minf(t, NC.PROJECTILE_LIFETIME)


## Slowly nudge battery elevation toward the correct angle for the nearest ship in arc.
## Returns true if a target was found and elevation is being adjusted.
## When no target is in arc, returns false and drifts elevation back to 0°.
func _auto_aim_elevation(p: Dictionary, bat: _BatteryController, hull_n: Vector2, delta: float) -> bool:
	var ship_pos: Vector2 = Vector2(float(p.wx), float(p.wy))
	var perp: Vector2 = bat._broadside_perp(hull_n)
	var best_dist: float = NC.MAX_CANNON_RANGE
	var found: bool = false
	for other in _players:
		if other.get("peer_id", -1) == p.get("peer_id", -2):
			continue
		if not bool(other.get("alive", true)):
			continue
		var to_other: Vector2 = Vector2(float(other.wx), float(other.wy)) - ship_pos
		var d: float = to_other.length()
		if d < 1.0 or d > NC.MAX_CANNON_RANGE:
			continue
		# Must be in the battery's arc.
		if to_other.normalized().dot(perp) < 0.25:
			continue
		if d < best_dist:
			best_dist = d
			found = true
	if not found:
		# No target in arc — drift back to 0° elevation.
		bat.cannon_elevation = lerpf(bat.cannon_elevation, _BatteryController.CANNON_ELEVATION_ZERO_DEG, _AUTO_AIM_RATE * delta)
		return false
	# Compute required elevation for that range and nudge toward it.
	var target_elev_deg: float = _elevation_for_range(best_dist)
	var target_norm: float = (target_elev_deg - _BatteryController.ELEV_MIN_DEG) / \
		(_BatteryController.ELEV_MAX_DEG - _BatteryController.ELEV_MIN_DEG)
	bat.cannon_elevation = lerpf(bat.cannon_elevation, target_norm, _AUTO_AIM_RATE * delta)
	return true


func _update_broadside_aim(p: Dictionary, _pad_id: int) -> void:
	if Input.is_action_just_pressed(BROADSIDE_PORT_ACTION):
		p["aim_port_active"] = not bool(p.get("aim_port_active", true))
	if Input.is_action_just_pressed(BROADSIDE_STBD_ACTION):
		p["aim_stbd_active"] = not bool(p.get("aim_stbd_active", false))
	var hull := Vector2(p.dir.x, p.dir.y)
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()
	var port_on: bool = bool(p.get("aim_port_active", true))
	var stbd_on: bool = bool(p.get("aim_stbd_active", false))
	if port_on and stbd_on:
		p["aim_dir"] = hull.rotated(PI * 0.5)
	elif port_on:
		p["aim_dir"] = hull.rotated(PI * 0.5)
	elif stbd_on:
		p["aim_dir"] = hull.rotated(-PI * 0.5)
	else:
		p["aim_dir"] = hull


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
	var k: float = (fwd * fwd) / (a * a) + (lat * lat) / (b * b)
	return k <= NC.ELLIPSE_HIT_SLACK


func _resolve_collisions() -> void:
	# Ships may overlap — no separation impulse (naval boarding range).
	pass


func _check_hit(_attacker: Dictionary, _defender: Dictionary) -> void:
	# Disable melee arc checks; combat in Ironwake is ranged projectile-driven.
	return

func _spawn_muzzle_fx(wx: float, wy: float, dir: Vector2) -> void:
	_muzzle_flash_fx.append({"wx": wx, "wy": wy, "dirx": dir.x, "diry": dir.y, "t": 0.0})
	_muzzle_smoke_fx.append({"wx": wx, "wy": wy, "t": 0.0})


## Half-angle (deg) of the yaw spread cone — physical dispersion only.
## No artificial accuracy modifiers: spread comes from range (powder variance,
## crew timing) plus penalties for turning and high speed.  Whether you hit
## depends on your elevation, positioning, and heading — not a hidden score.
func _spread_cone_half_deg(p: Dictionary, aim_dist: float) -> float:
	var base_deg: float = NC.spread_deg_for_range(aim_dist)
	if bool(p.get("motion_is_turning", false)):
		base_deg *= NC.TURNING_SPREAD_MULT
	if float(p.get("_naval_spd", 0.0)) >= NC.HIGH_SPEED_THRESHOLD:
		base_deg *= NC.HIGH_SPEED_SPREAD_MULT
	return base_deg


func _spread_yaw_deg_for_cannon(p: Dictionary, aim_dist: float, cannon_index: int, battery: Variant = null) -> float:
	var half: float = _spread_cone_half_deg(p, aim_dist)
	var is_ripple: bool = battery != null and battery.fire_mode == _BatteryController.FireMode.RIPPLE
	if is_ripple:
		# Ripple: each cannon aims at the center point. Small jitter only (crew variance).
		var jitter: float = randf_range(-0.12, 0.12)
		return half * jitter
	else:
		# Barrage (salvo): each cannon fires straight out its own gunport.
		# Symmetric spread pattern fills the full cone.
		var pattern: Array[float] = [0.0, -0.5, 0.5, -0.85, 0.85, -0.3, 0.3, -0.7, 0.7]
		var idx: int = posmod(cannon_index, pattern.size())
		var jitter: float = randf_range(-0.15, 0.15)
		return half * (pattern[idx] + jitter)


## Prefer stored aim (auto-aim / lead) when it bears on the selected broadside; else pure port/starboard normal.
func _effective_broadside_aim_for_side(p: Dictionary, hull_n: Vector2, is_port: bool) -> Vector2:
	var perp: Vector2 = hull_n.rotated(PI * 0.5) if is_port else hull_n.rotated(-PI * 0.5)
	var ad: Variant = p.get("aim_dir", null)
	if ad is Vector2:
		var av: Vector2 = ad as Vector2
		if av.length_squared() > 0.0001:
			av = av.normalized()
			if av.dot(perp) > 0.12:
				return av
	return perp


func _cannon_muzzle_world(p: Dictionary, battery: _BatteryController, cannon_index: int) -> Vector2:
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_n.length_squared() < 0.001:
		hull_n = Vector2.RIGHT
	hull_n = hull_n.normalized()
	var perp: Vector2 = battery._broadside_perp(hull_n)
	var n_g: int = maxi(1, battery.cannon_count)
	var idx: int = clampi(cannon_index, 0, n_g - 1)
	# Fixed gunport spacing: ~2.3 m between guns (historical 24-pdr ship of the line).
	var half_span: float = float(n_g - 1) * 0.5 * 2.3
	var along_t: float = 0.0
	if n_g > 1:
		along_t = (float(idx) - float(n_g - 1) * 0.5) / float(n_g - 1)
	var along: Vector2 = hull_n * (along_t * half_span * 2.0)
	# Muzzle at hull edge — half-width of the ship (gunport in the hull side).
	var out_m: float = NC.SHIP_WIDTH_UNITS * 0.5
	return Vector2(float(p.wx), float(p.wy)) + along + perp * out_m


func _deck_lift_offset_for_screen(p: Dictionary) -> Vector2:
	var bob: float = sin(float(p.get("walk_time", 0.0)) * 3.0) * 1.4 if bool(p.get("moving", false)) else 0.0
	var v_lift_px: float = NC.SHIP_DECK_HEIGHT_UNITS * _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
	return Vector2(0.0, -v_lift_px + bob * _zoom)


func _fire_projectile(p: Dictionary, cannon_index: int = 0, _shot_damage: float = 1.0, aim_override: Variant = null, battery: Variant = null) -> void:
	var fire_peer: int = int(p.get("peer_id", 1))
	if _scoreboard.has(fire_peer):
		_scoreboard[fire_peer]["shots_fired"] += 1
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
	var spread_deg: float = _spread_yaw_deg_for_cannon(p, aim_dist, cannon_index, battery)
	var shot_dir: Vector2 = dir.rotated(deg_to_rad(spread_deg)).normalized()
	var start_x: float
	var start_y: float
	if battery != null:
		var bat: _BatteryController = battery as _BatteryController
		var mw: Vector2 = _cannon_muzzle_world(p, bat, cannon_index)
		start_x = mw.x
		start_y = mw.y
	else:
		var muzzle: float = 6.5
		start_x = float(p.wx) + shot_dir.x * muzzle
		start_y = float(p.wy) + shot_dir.y * muzzle
	_spawn_muzzle_fx(start_x, start_y, shot_dir)
	var elev_deg: float = _CannonBallistics.DEFAULT_ELEVATION_DEG
	if battery != null:
		elev_deg = battery.elevation_degrees()
	var vel: Dictionary = _CannonBallistics.initial_velocity(shot_dir, elev_deg)
	var vx: float = float(vel.vx)
	var vy: float = float(vel.vy)
	var vz: float = float(vel.vz)
	var hull_dmg: float = HULL_DAMAGE_PER_HIT
	if multiplayer.has_multiplayer_peer():
		_spawn_cannonball_rpc.rpc(
			start_x, start_y, vx, vy, vz,
			_CannonBallistics.MUZZLE_HEIGHT, owner_peer, hull_dmg
		)
	else:
		_spawn_cannonball_local(
			start_x, start_y, vx, vy, vz,
			_CannonBallistics.MUZZLE_HEIGHT, owner_peer, hull_dmg
		)


@rpc("any_peer", "call_local", "reliable")
func _spawn_cannonball_rpc(
		wx: float, wy: float,
		vx: float, vy: float, vz: float,
		h: float, owner_peer: int, damage: float
	) -> void:
	_spawn_cannonball_local(wx, wy, vx, vy, vz, h, owner_peer, damage)


func _spawn_cannonball_local(
		wx: float, wy: float,
		vx: float, vy: float, vz: float,
		h: float, owner_peer: int, damage: float
	) -> void:
	_projectiles.append({
		"wx": wx, "wy": wy, "h": h,
		"vx": vx, "vy": vy, "vz": vz,
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
	var grav: float = _CannonBallistics.GRAVITY
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
		var dmg: float = float(proj.get("damage", HULL_DAMAGE_PER_HIT))
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
						_apply_cannon_hit.rpc(owner_peer, def_peer, dmg, h)
					else:
						_apply_cannon_hit_impl(owner_peer, def_peer, dmg, h)
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


## Height zones for component damage routing.
## Upper hull / rigging (masts, yards, sails) — shots above the gun deck.
const _SAIL_HIT_H_MIN: float = 3.5
## Lower hull near waterline — tiller, rudder post, steering gear.
const _HELM_HIT_H_MAX: float = 1.5

func _apply_cannon_hit_impl(attacker_peer_id: int, defender_peer_id: int, damage: float, hit_h: float = 3.0) -> void:
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
	# --- Component damage based on hit height ---
	# Upper hull → sail rigging (masts, yards, canvas).
	if hit_h >= _SAIL_HIT_H_MIN:
		var sail_obj = d.get("sail")
		if sail_obj != null:
			sail_obj.apply_hit()
	# Lower hull → helm / rudder / tiller.
	elif hit_h <= _HELM_HIT_H_MAX:
		var helm_obj = d.get("helm")
		if helm_obj != null:
			helm_obj.apply_hit()
	# Mid-hull hits deal structural damage only (already applied above).
	# Scoreboard: track hit stats.
	if _scoreboard.has(attacker_peer_id):
		_scoreboard[attacker_peer_id]["shots_hit"] += 1
		_scoreboard[attacker_peer_id]["damage_dealt"] += damage
	if _scoreboard.has(defender_peer_id):
		_scoreboard[defender_peer_id]["damage_taken"] += damage
	if not defender_alive:
		d["respawn_timer"] = RESPAWN_DELAY_SEC
		# Scoreboard: track kill/death.
		if _scoreboard.has(attacker_peer_id):
			_scoreboard[attacker_peer_id]["kills"] += 1
		if _scoreboard.has(defender_peer_id):
			_scoreboard[defender_peer_id]["deaths"] += 1
	if bool(d.get("is_bot", false)):
		var bc: Variant = _get_bot_controller_for_index(defender_idx)
		if bc != null:
			bc.notify_cannon_hit(attacker_peer_id)
	_play_cannon_hit_sound()
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_check_win()


@rpc("authority", "call_local", "reliable")
func _apply_cannon_hit(attacker_peer_id: int, defender_peer_id: int, damage: float, hit_h: float = 3.0) -> void:
	_apply_cannon_hit_impl(attacker_peer_id, defender_peer_id, damage, hit_h)

func _tick_local_timers(_delta: float) -> void:
	pass


# ── Naval state broadcast (overrides base iso_arena) ─────────────────────────
func _broadcast_my_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var p: Dictionary = _players[_my_index]
	var sail_obj: Variant = p.get("sail")
	var helm_obj: Variant = p.get("helm")
	var sail_level: float = sail_obj.current_sail_level if sail_obj != null else 0.0
	var sail_state: int = int(sail_obj.sail_state) if sail_obj != null else 0
	var sail_dmg: float = sail_obj.damage if sail_obj != null else 0.0
	var rudder: float = helm_obj.rudder_angle if helm_obj != null else 0.0
	var helm_dmg: float = helm_obj.damage if helm_obj != null else 0.0
	_receive_naval_state.rpc(
		int(p.peer_id),
		float(p.wx), float(p.wy),
		float(p.dir.x), float(p.dir.y),
		float(p.atk_time), bool(p.moving), float(p.walk_time),
		float(p.get("move_speed", 0.0)),
		float(p.get("angular_velocity", 0.0)),
		float(p.get("health", HULL_HITS_MAX)),
		bool(p.get("alive", true)),
		sail_level, sail_state, rudder,
		sail_dmg, helm_dmg
	)


@rpc("any_peer", "unreliable")
func _receive_naval_state(
		peer_id: int,
		wx: float, wy: float,
		dir_x: float, dir_y: float,
		atk_time: float, moving: bool, walk_time: float,
		move_speed: float, angular_velocity: float,
		health: float, alive: bool,
		sail_level: float, sail_state: int, rudder: float,
		sail_dmg: float = 0.0, helm_dmg: float = 0.0) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var idx: int = _find_player_index_by_peer_id(peer_id)
	if idx < 0:
		return
	var p: Dictionary = _players[idx]
	p.wx        = wx
	p.wy        = wy
	p.dir       = Vector2(dir_x, dir_y)
	p.atk_time  = atk_time
	p.moving    = moving
	p.walk_time = walk_time
	p["move_speed"]        = move_speed
	p["angular_velocity"]  = angular_velocity
	p["health"]            = health
	p["alive"]             = alive
	var sail_obj: Variant = p.get("sail")
	if sail_obj != null:
		sail_obj.current_sail_level = sail_level
		sail_obj.sail_state = sail_state
		sail_obj.damage = sail_dmg
	var helm_obj: Variant = p.get("helm")
	if helm_obj != null:
		helm_obj.rudder_angle = rudder
		helm_obj.damage = helm_dmg


func _tick_ramming(delta: float) -> void:
	# Decay cooldown timers.
	for key in _ram_cooldowns.keys():
		_ram_cooldowns[key] = maxf(0.0, float(_ram_cooldowns[key]) - delta)
		if _ram_cooldowns[key] <= 0.0:
			_ram_cooldowns.erase(key)

	var n: int = _players.size()
	if n < 2:
		return

	for i in range(n):
		var a: Dictionary = _players[i]
		if not bool(a.get("alive", true)):
			continue
		for j in range(i + 1, n):
			var b: Dictionary = _players[j]
			if not bool(b.get("alive", true)):
				continue

			var ax: float = float(a.wx)
			var ay: float = float(a.wy)
			var bx: float = float(b.wx)
			var by: float = float(b.wy)
			var dx: float = bx - ax
			var dy: float = by - ay
			var dist_sq: float = dx * dx + dy * dy
			# Quick broad-phase: skip pairs that are clearly too far apart.
			if dist_sq > (RAM_COLLISION_DIST * 2.5) * (RAM_COLLISION_DIST * 2.5):
				continue

			var dist: float = sqrt(dist_sq)
			if dist < 0.001:
				dist = 0.001

			# Collision normal pointing from A to B.
			var nx: float = dx / dist
			var ny: float = dy / dist

			# Ellipse overlap check: each ship occupies an ellipse LENGTH×WIDTH.
			# Project the half-extents of each ship along the collision normal.
			var a_hull: Vector2 = Vector2(float(a.dir.x), float(a.dir.y)).normalized()
			var b_hull: Vector2 = Vector2(float(b.dir.x), float(b.dir.y)).normalized()
			var col_n: Vector2 = Vector2(nx, ny)

			# Ellipse half-extent along collision normal (Lamé approximation).
			var a_fwd_dot: float = absf(a_hull.dot(col_n))
			var b_fwd_dot: float = absf(b_hull.dot(col_n))
			var a_half: float = lerpf(NC.SHIP_WIDTH_UNITS * 0.5, NC.SHIP_LENGTH_UNITS * 0.5, a_fwd_dot)
			var b_half: float = lerpf(NC.SHIP_WIDTH_UNITS * 0.5, NC.SHIP_LENGTH_UNITS * 0.5, b_fwd_dot)
			var threshold: float = a_half + b_half
			if dist > threshold:
				continue

			# Cooldown check.
			var pair_key: String = "%d_%d" % [i, j]
			if _ram_cooldowns.get(pair_key, 0.0) > 0.0:
				continue
			_ram_cooldowns[pair_key] = RAM_COOLDOWN_SEC

			# Closing velocity along collision normal.
			var a_spd: float = float(a.get("move_speed", 0.0))
			var b_spd: float = float(b.get("move_speed", 0.0))
			var a_vel_n: float = a_hull.dot(col_n) * a_spd     # positive = moving toward B
			var b_vel_n: float = -b_hull.dot(col_n) * b_spd    # positive = moving toward A
			var closing: float = a_vel_n + b_vel_n
			if closing <= RAM_MIN_SPEED:
				continue

			var excess: float = closing - RAM_MIN_SPEED
			var base_damage: float = excess * RAM_DAMAGE_PER_MPS

			# Angle of impact on each hull — bow/stern = half damage, beam = full.
			# For ship A: how much of the collision is along A's hull axis (bow/stern)?
			var a_bow_factor: float = absf(a_hull.dot(col_n))   # 1.0 = pure bow/stern, 0.0 = pure beam
			var b_bow_factor: float = absf(b_hull.dot(col_n))
			var a_mult: float = lerpf(1.0, RAM_BOW_STERN_DAMAGE_MULT, a_bow_factor)
			var b_mult: float = lerpf(1.0, RAM_BOW_STERN_DAMAGE_MULT, b_bow_factor)

			# Apply damage — server authoritative; clients only see visual FX.
			var dmg_a: float = base_damage * a_mult
			var dmg_b: float = base_damage * b_mult
			if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
				_apply_ram_damage(a, dmg_a, i, j)
				_apply_ram_damage(b, dmg_b, j, i)
				if multiplayer.has_multiplayer_peer():
					_rpc_apply_ram_damage.rpc(i, dmg_a, j, dmg_b)

			# Speed loss — both ships lose momentum proportional to closing velocity.
			var speed_bleed: float = closing * RAM_SPEED_LOSS_MULT
			a["move_speed"] = maxf(0.0, a_spd - speed_bleed * a_vel_n / maxf(0.001, closing))
			b["move_speed"] = maxf(0.0, b_spd - speed_bleed * b_vel_n / maxf(0.001, closing))

			# Separate overlapping ships so they don't stick.
			var overlap: float = threshold - dist
			var sep: float = overlap * 0.5
			a.wx = ax - nx * sep
			a.wy = ay - ny * sep
			b.wx = bx + nx * sep
			b.wy = by + ny * sep

			# Spawn a splash FX at the point of contact.
			var cx: float = ax + nx * (dist * 0.5)
			var cy: float = ay + ny * (dist * 0.5)
			_splash_fx.append({"wx": cx, "wy": cy, "t": _SPLASH_DURATION * 1.8})

			if combat_debug_log:
				var a_lbl: String = str(a.get("label", "?"))
				var b_lbl: String = str(b.get("label", "?"))
				print("[Ram] %s↔%s closing=%.1f dmg_a=%.2f dmg_b=%.2f spd_loss=%.1f" % [
					a_lbl, b_lbl, closing, dmg_a, dmg_b, speed_bleed])


func _apply_ram_damage(p: Dictionary, damage: float, idx: int, other_idx: int = -1) -> void:
	if not bool(p.get("alive", true)):
		return
	var new_health: float = maxf(float(p.health) - damage, 0.0)
	p.health = new_health
	# Ramming damages the helm — collision shocks the tiller and rudder post.
	var helm_obj: Variant = p.get("helm")
	if helm_obj != null and damage > 0.5:
		helm_obj.apply_hit()
	# Scoreboard: track ramming damage.
	var def_pid: int = int(p.get("peer_id", 0))
	if _scoreboard.has(def_pid):
		_scoreboard[def_pid]["damage_taken"] += damage
	if other_idx >= 0 and other_idx < _players.size():
		var atk_pid: int = int(_players[other_idx].get("peer_id", 0))
		if _scoreboard.has(atk_pid):
			_scoreboard[atk_pid]["damage_dealt"] += damage
	if new_health <= 0.0:
		p.alive = false
		p["respawn_timer"] = RESPAWN_DELAY_SEC
		# Scoreboard: track ram kill/death.
		if _scoreboard.has(def_pid):
			_scoreboard[def_pid]["deaths"] += 1
		if other_idx >= 0 and other_idx < _players.size():
			var atk_pid2: int = int(_players[other_idx].get("peer_id", 0))
			if _scoreboard.has(atk_pid2):
				_scoreboard[atk_pid2]["kills"] += 1
		if bool(p.get("is_bot", false)):
			var bc: Variant = _get_bot_controller_for_index(idx)
			if bc != null:
				bc.notify_cannon_hit(-1)
	_hull_strike_fx.append({
		"wx": float(p.wx), "wy": float(p.wy),
		"h": NC.SHIP_DECK_HEIGHT_UNITS,
		"t": _HULL_STRIKE_DURATION,
	})
	_play_cannon_hit_sound()
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_check_win()


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_ram_damage(idx_a: int, dmg_a: float, idx_b: int, dmg_b: float) -> void:
	if idx_a >= 0 and idx_a < _players.size():
		_apply_ram_damage(_players[idx_a], dmg_a, idx_a, idx_b)
	if idx_b >= 0 and idx_b < _players.size():
		_apply_ram_damage(_players[idx_b], dmg_b, idx_b, idx_a)


func _tick_respawn(delta: float) -> void:
	# Only the server (or offline host) decrements respawn timers and triggers respawns.
	var is_authority: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	for i in range(_players.size()):
		var p: Dictionary = _players[i]
		if bool(p.get("alive", true)):
			continue
		var t: float = float(p.get("respawn_timer", 0.0))
		if t <= 0.0:
			continue
		if is_authority:
			t = maxf(0.0, t - delta)
			p["respawn_timer"] = t
			if t <= 0.0:
				_respawn_ship(i)
				if multiplayer.has_multiplayer_peer():
					_rpc_respawn_ship.rpc(i)


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
	if bool(p.get("is_bot", false)):
		_apply_bot_helm_overrides(p)
	var bc: Variant = _get_bot_controller_for_index(idx)
	if bc != null:
		bc.reset_combat_state()


@rpc("authority", "call_remote", "reliable")
func _rpc_respawn_ship(idx: int) -> void:
	_respawn_ship(idx)


## Naval arena: use the base win condition (last ship standing).
func _check_win() -> void:
	super._check_win()


func _set_winner(next_winner: int) -> void:
	super._set_winner(next_winner)
	_match_over = true


func _draw_win_screen(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.58))
	var font: Font = ThemeDB.fallback_font
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.28

	var msg: String
	if _winner == -1:
		msg = "DRAW!"
	else:
		msg = "%s WINS!" % _players[_winner].label
	draw_string(font, Vector2(cx, cy), msg,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 52, Color(0.95, 0.75, 0.35, 1.0))

	# Scoreboard is drawn separately by the _draw() caller when _match_over is true.

	if _post_match_ready:
		draw_string(font, Vector2(cx, vp.y * 0.88),
			"Press any key to continue...",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, _HUD_TEXT)
	else:
		var remaining: int = ceili(END_DELAY - _end_timer)
		draw_string(font, Vector2(cx, vp.y * 0.88),
			"Returning to menu in %d..." % remaining,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, _HUD_TEXT_MUTED)


func _return_to_menu() -> void:
	GameManager.match_phase = GameManager.MatchPhase.LOBBY
	# Clean up Steam lobby (this also closes multiplayer peer).
	if SteamManager != null:
		SteamManager.leave_lobby()
	elif multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	get_tree().change_scene_to_file(GameManager.HOME_SCREEN_SCENE_PATH)


func _ensure_audio_player() -> void:
	if _sfx_player != null:
		return
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "IronwakeSfxPlayer"
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
	var px_len: float = maxf(14.0 * _zoom, (_w2s(p.wx + hull.x * NC.SHIP_LENGTH_UNITS, p.wy + hull.y * NC.SHIP_LENGTH_UNITS) - sp).length())
	var px_wid: float = maxf(8.0 * _zoom, (_w2s(p.wx + right.x * NC.SHIP_WIDTH_UNITS, p.wy + right.y * NC.SHIP_WIDTH_UNITS) - sp).length())
	var h_len: float = px_len
	var h_wid: float = px_wid
	# FTL-style schematic hull (same proportions as _draw_ftl_ship_hud), oriented with bow = fwd.
	var bow_tip: Vector2 = draw_pos + fwd * h_len * 0.44
	var bow_l: Vector2 = draw_pos + fwd * h_len * 0.32 - right * h_wid * 0.35
	var bow_r: Vector2 = draw_pos + fwd * h_len * 0.32 + right * h_wid * 0.35
	var fwd_l: Vector2 = draw_pos + fwd * h_len * 0.15 - right * h_wid * 0.62
	var fwd_r: Vector2 = draw_pos + fwd * h_len * 0.15 + right * h_wid * 0.62
	var mid_l: Vector2 = draw_pos - fwd * h_len * 0.02 - right * h_wid * 0.72
	var mid_r: Vector2 = draw_pos - fwd * h_len * 0.02 + right * h_wid * 0.72
	var aft_l: Vector2 = draw_pos - fwd * h_len * 0.22 - right * h_wid * 0.65
	var aft_r: Vector2 = draw_pos - fwd * h_len * 0.22 + right * h_wid * 0.65
	var stern_l: Vector2 = draw_pos - fwd * h_len * 0.38 - right * h_wid * 0.48
	var stern_r: Vector2 = draw_pos - fwd * h_len * 0.38 + right * h_wid * 0.48
	var transom: Vector2 = draw_pos - fwd * h_len * 0.35
	var mod_color: Color = p.palette[0]
	var hp_frac: float = clampf(float(p.get("health", HULL_HITS_MAX)) / HULL_HITS_MAX, 0.0, 1.0)
	# Tint hull toward red/brown as damage accumulates.
	var dmg_t: float = 1.0 - hp_frac
	var base_r: float = lerpf(mod_color.r * 0.55, 0.35, dmg_t * 0.6)
	var base_g: float = lerpf(mod_color.g * 0.55, 0.12, dmg_t * 0.7)
	var base_b: float = lerpf(mod_color.b * 0.58, 0.08, dmg_t * 0.7)
	var hull_dark: Color = Color(base_r, base_g, base_b, 0.96)
	var hull_mid: Color = Color(lerpf(mod_color.r * 0.78, 0.45, dmg_t * 0.5),
		lerpf(mod_color.g * 0.78, 0.25, dmg_t * 0.6),
		lerpf(mod_color.b * 0.82, 0.18, dmg_t * 0.6), 0.94)
	var hull_poly := PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l])
	if h_len > 1.0 and h_wid > 1.0:
		draw_colored_polygon(hull_poly, hull_dark)
	draw_polyline(PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l, bow_tip]),
		hull_mid, 2.0 * _zoom, true)
	# Damage marks — dark scorch spots along hull, more as health drops.
	var marks_count: int = int((1.0 - hp_frac) * 8.0)
	if marks_count > 0 and h_len > 3.0:
		var mark_col: Color = Color(0.08, 0.05, 0.03, 0.5 + dmg_t * 0.3)
		for mi in range(marks_count):
			# Deterministic positions based on index so they don't flicker.
			var mt: float = (float(mi) + 0.5) / 8.0
			var along_off: float = lerpf(-0.3, 0.3, mt)
			var side_f: float = -0.3 if mi % 2 == 0 else 0.3
			var mark_pos: Vector2 = draw_pos + fwd * h_len * along_off + right * h_wid * side_f
			draw_circle(mark_pos, (1.5 + dmg_t * 1.5) * _zoom, mark_col)
	draw_line(draw_pos + fwd * h_len * 0.40, draw_pos + fwd * h_len * 0.52, Color(0.55, 0.45, 0.30, 0.75), 1.6 * _zoom, true)
	draw_line(draw_pos + fwd * h_len * 0.06, draw_pos + fwd * h_len * 0.28, Color(0.48, 0.40, 0.28, 0.55), 1.2 * _zoom, true)
	var ctr_w: Vector2 = Vector2(float(p.wx), float(p.wy))
	var sc_w: float = _TD_SCALE * _zoom
	var barrel_col: Color = Color(0.22, 0.20, 0.18, 0.95)
	var mzl_col: Color = Color(0.42, 0.38, 0.32, 0.9)
	var zc: float = _zoom
	for bat_var in [p.get("battery_port"), p.get("battery_stbd")]:
		if bat_var == null:
			continue
		var bat_c: _BatteryController = bat_var as _BatteryController
		var perp_w: Vector2 = bat_c._broadside_perp(hull)
		var out_scr: Vector2 = _dir_screen(perp_w.x, perp_w.y)
		for gi in range(bat_c.cannon_count):
			var mw: Vector2 = _cannon_muzzle_world(p, bat_c, gi)
			var gun_sp: Vector2 = draw_pos + (mw - ctr_w) * sc_w
			# Barrel: breech inside hull, muzzle poking out at gunport.
			var breech: Vector2 = gun_sp - out_scr * (4.0 * zc)
			draw_line(breech, gun_sp + out_scr * (3.0 * zc), barrel_col, 2.4 * zc, true)
			draw_circle(gun_sp + out_scr * (3.5 * zc), 1.3 * zc, mzl_col)
	var font := ThemeDB.fallback_font
	draw_string(font, draw_pos + Vector2(0.0, -42.0 * _zoom), str(p.get("label", "Ship")), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 1.0, 1.0, 0.88))

	# Direction indicator — bow line for all ships, arcs only for local player.
	var c_bow_bot: Color = Color(mod_color.r, mod_color.g, mod_color.b, 0.5)
	draw_line(draw_pos, draw_pos + fwd * (h_len * 0.7), c_bow_bot, 1.8 * _zoom)

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


func _draw_scoreboard(vp: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	# Panel dimensions.
	var col_widths: Array[float] = [140.0, 60.0, 60.0, 55.0, 60.0, 55.0, 75.0, 75.0]
	var total_w: float = 0.0
	for w in col_widths:
		total_w += w
	var row_h: float = 26.0
	var header_h: float = 30.0
	var pad: float = 16.0
	var n_rows: int = _players.size()
	var total_h: float = header_h + float(n_rows) * row_h + pad * 2.0
	var panel_x: float = (vp.x - total_w - pad * 2.0) * 0.5
	var panel_y: float = (vp.y - total_h) * 0.5

	# Background panel.
	draw_rect(Rect2(panel_x, panel_y, total_w + pad * 2.0, total_h), Color(0.05, 0.05, 0.08, 0.88))
	draw_rect(Rect2(panel_x, panel_y, total_w + pad * 2.0, total_h), _HUD_BORDER, false, 2.0)

	# Column headers.
	var headers: Array[String] = ["Player", "Kills", "Deaths", "K/D", "Shots", "Hits", "Accuracy", "Damage"]
	var hx: float = panel_x + pad
	var hy: float = panel_y + pad + 14.0
	for ci in range(headers.size()):
		draw_string(font, Vector2(hx, hy), headers[ci], HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[ci]), 13, _HUD_TEXT_MUTED)
		hx += col_widths[ci]

	# Header separator line.
	draw_line(
		Vector2(panel_x + pad, panel_y + pad + header_h - 6.0),
		Vector2(panel_x + pad + total_w, panel_y + pad + header_h - 6.0),
		_HUD_BORDER, 1.0)

	# Sort players by kills descending.
	var sorted_players: Array = _players.duplicate()
	sorted_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_pid: int = int(a.get("peer_id", 0))
		var b_pid: int = int(b.get("peer_id", 0))
		var a_kills: int = int(_scoreboard.get(a_pid, {}).get("kills", 0))
		var b_kills: int = int(_scoreboard.get(b_pid, {}).get("kills", 0))
		return a_kills > b_kills)

	# Rows.
	var ry: float = panel_y + pad + header_h + 12.0
	for p in sorted_players:
		var pid: int = int(p.get("peer_id", 0))
		var stats: Dictionary = _scoreboard.get(pid, {})
		var kills: int = int(stats.get("kills", 0))
		var deaths: int = int(stats.get("deaths", 0))
		var shots_fired: int = int(stats.get("shots_fired", 0))
		var shots_hit: int = int(stats.get("shots_hit", 0))
		var dmg_dealt: float = float(stats.get("damage_dealt", 0.0))
		var kd: float = float(kills) / float(maxi(deaths, 1))
		var accuracy: float = (float(shots_hit) / float(shots_fired) * 100.0) if shots_fired > 0 else 0.0
		var row_col: Color = Color(p.palette[0], 0.9)

		var rx: float = panel_x + pad
		draw_string(font, Vector2(rx, ry), str(p.get("label", "?")), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[0]), 13, row_col)
		rx += col_widths[0]
		draw_string(font, Vector2(rx, ry), str(kills), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[1]), 13, row_col)
		rx += col_widths[1]
		draw_string(font, Vector2(rx, ry), str(deaths), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[2]), 13, row_col)
		rx += col_widths[2]
		draw_string(font, Vector2(rx, ry), "%.1f" % kd, HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[3]), 13, row_col)
		rx += col_widths[3]
		draw_string(font, Vector2(rx, ry), str(shots_fired), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[4]), 13, row_col)
		rx += col_widths[4]
		draw_string(font, Vector2(rx, ry), str(shots_hit), HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[5]), 13, row_col)
		rx += col_widths[5]
		draw_string(font, Vector2(rx, ry), "%.0f%%" % accuracy, HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[6]), 13, row_col)
		rx += col_widths[6]
		draw_string(font, Vector2(rx, ry), "%.1f" % dmg_dealt, HORIZONTAL_ALIGNMENT_LEFT, int(col_widths[7]), 13, row_col)
		ry += row_h


func _ballistic_splash_range_for_player(p: Dictionary) -> float:
	var port_on: bool = bool(p.get("aim_port_active", true))
	var bat: Variant = p.get("battery_port") if port_on else p.get("battery_stbd")
	var elev_deg: float = 0.0
	if bat != null:
		elev_deg = bat.elevation_degrees()
	var elev_rad: float = deg_to_rad(elev_deg)
	var vh: float = _CannonBallistics.MUZZLE_SPEED * cos(elev_rad)
	var vz: float = _CannonBallistics.MUZZLE_SPEED * sin(elev_rad)
	var h0: float = _CannonBallistics.MUZZLE_HEIGHT
	var g: float = _CannonBallistics.GRAVITY
	var disc: float = vz * vz + 2.0 * g * h0
	var t_splash: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, g)
	return vh * minf(t_splash, NC.PROJECTILE_LIFETIME)


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


func _draw_accuracy_bands(center: Vector2, screen_y_offset_px: float = 0.0, alpha_mult: float = 1.0) -> void:
	var bands: Array[Dictionary] = [
		{"r0": 0.0, "r1": NC.ACC_PISTOL_RANGE, "col": Color(0.1, 0.95, 0.2, 0.06 * alpha_mult), "label": "Point Blank"},
		{"r0": NC.ACC_PISTOL_RANGE, "r1": NC.ACC_CLOSE_RANGE, "col": Color(0.3, 0.9, 0.15, 0.05 * alpha_mult), "label": "Close"},
		{"r0": NC.ACC_CLOSE_RANGE, "r1": NC.ACC_MUSKET_RANGE, "col": Color(0.9, 0.85, 0.1, 0.045 * alpha_mult), "label": "Effective"},
		{"r0": NC.ACC_MUSKET_RANGE, "r1": NC.ACC_MEDIUM_RANGE, "col": Color(0.95, 0.5, 0.08, 0.04 * alpha_mult), "label": "Long"},
		{"r0": NC.ACC_MEDIUM_RANGE, "r1": NC.ACC_LONG_RANGE, "col": Color(0.95, 0.15, 0.08, 0.035 * alpha_mult), "label": "Extreme"},
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
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size, Color(1, 1, 1, 0.55 * alpha_mult))


func _draw() -> void:
	var vp := get_viewport_rect().size
	var me: Dictionary = _players[_my_index] if not _players.is_empty() else {}
	var cam_target_idx: int = clampi(_camera_follow_index, 0, maxi(0, _players.size() - 1))
	var cam_target: Dictionary = _players[cam_target_idx] if not _players.is_empty() else {}
	var cam_focus: Vector2
	if _camera_locked and not cam_target.is_empty():
		cam_focus = Vector2(float(cam_target.wx), float(cam_target.wy))
	else:
		cam_focus = _camera_world_anchor
	_origin = vp * 0.5 - cam_focus * _TD_SCALE * _zoom

	draw_rect(Rect2(Vector2.ZERO, vp), MapProfile.SEA_SKY)
	_draw_top_down_ocean(vp)
	var me_deck_y_off: float = 0.0
	if not me.is_empty() and bool(me.get("alive", true)):
		me_deck_y_off = -NC.SHIP_DECK_HEIGHT_UNITS * _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom
	var me_world: Vector2 = Vector2(float(me.wx), float(me.wy)) if not me.is_empty() else cam_focus
	var ring_alpha: float = _hud_fade_alpha(_fade_accuracy_ring)
	if ring_alpha > 0.01:
		_draw_accuracy_bands(me_world, me_deck_y_off, ring_alpha)
		var ballistic_max: float = _ballistic_splash_range_for_player(me)
		_draw_world_range_ring(me_world, ballistic_max, Color(1.0, 0.25, 0.1, 0.7 * ring_alpha), 2.4, me_deck_y_off)
	_draw_splash_fx()

	var sorted := _players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.wx + a.wy) < (b.wx + b.wy))
	for p in sorted:
		_draw_player(p)

	if OS.is_debug_build() and combat_debug_world_draw:
		_draw_combat_debug_world_overlays()

	_draw_muzzle_fx()
	if _fade_path_line > 0.01:
		_draw_ship_trajectory_arc_preview(_hud_fade_alpha(_fade_path_line))
	if _fade_ballistics_arc > 0.01:
		_draw_trajectory_arc_preview(_hud_fade_alpha(_fade_ballistics_arc))
	_draw_aim_cursor()
	_draw_projectiles()
	_draw_hull_strike_fx()
	_draw_motion_battery_hud(vp)
	_draw_helm_sail_hud(vp)
	_draw_ftl_ship_hud(vp)
	_draw_offscreen_indicators(vp)
	_draw_hud(vp)
	if pause_menu_panel != null and pause_menu_panel.visible:
		_draw_keybindings_panel(vp)
	_draw_ability_bar(vp)
	if _winner != -2:
		_draw_win_screen(vp)
	if Input.is_action_pressed(SCOREBOARD_ACTION) or _match_over:
		_draw_scoreboard(vp)


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
		var R: float = ARROW_R
		var side: Vector2 = Vector2(-dir.y, dir.x)
		# Ship silhouette: pointed bow, widest at midship, tapered stern.
		var bow: Vector2 = ap + dir * R * 1.1
		var bow_l: Vector2 = ap + dir * R * 0.7 - side * R * 0.3
		var bow_r: Vector2 = ap + dir * R * 0.7 + side * R * 0.3
		var mid_l: Vector2 = ap + dir * R * 0.1 - side * R * 0.52
		var mid_r: Vector2 = ap + dir * R * 0.1 + side * R * 0.52
		var aft_l: Vector2 = ap - dir * R * 0.6 - side * R * 0.42
		var aft_r: Vector2 = ap - dir * R * 0.6 + side * R * 0.42
		var stern_l: Vector2 = ap - dir * R * 0.85 - side * R * 0.28
		var stern_r: Vector2 = ap - dir * R * 0.85 + side * R * 0.28
		var stern: Vector2 = ap - dir * R * 0.75
		var ship_poly := PackedVector2Array([bow, bow_r, mid_r, aft_r, stern_r, stern, stern_l, aft_l, mid_l, bow_l])
		const S := 1.18
		var shadow_poly := PackedVector2Array()
		var center: Vector2 = ap
		for pt in ship_poly:
			shadow_poly.append(center + (pt - center) * S)
		draw_colored_polygon(shadow_poly, Color(0.0, 0.0, 0.0, 0.55))
		draw_colored_polygon(ship_poly, pa)
		var label_pos: Vector2 = ap - dir * (ARROW_R + 10.0)
		draw_string(font, label_pos, p.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(pa.r, pa.g, pa.b, 0.90))


func _draw_bot_debug_hud(vp: Vector2) -> void:
	if _bot_indices.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs: int = 10
	var panel_w: float = 260.0
	var x: float = 10.0
	var total_lines: int = 0
	for ci in range(_bot_indices.size()):
		var bi: int = _bot_indices[ci]
		if bi < 0 or bi >= _players.size():
			continue
		if bool(_players[bi].get("alive", false)):
			total_lines += 8
		else:
			total_lines += 6
	var y: float = vp.y - float(total_lines) * 13.0 - 24.0
	var label_colors: Array = [
		Color(0.95, 0.40, 0.35, 1.0),
		Color(1.00, 0.80, 0.30, 1.0),
		Color(0.80, 0.55, 0.95, 1.0),
	]
	for ci in range(_bot_indices.size()):
		var bi: int = _bot_indices[ci]
		if bi < 0 or bi >= _players.size():
			continue
		var p: Dictionary = _players[bi]
		var col: Color = label_colors[ci % label_colors.size()]
		var lines: Array[String] = []
		var ship_label: String = str(p.get("label", "Bot%d" % ci))
		var alive: bool = bool(p.get("alive", false))
		lines.append("── %s (%s) ──" % [ship_label, "ALIVE" if alive else "DEAD"])
		if not alive:
			var rt: float = float(p.get("respawn_timer", 0.0))
			lines.append("  Respawn: %.1fs" % rt)
		else:
			var spd: float = float(p.get("move_speed", 0.0))
			var ang_v: float = float(p.get("angular_velocity", 0.0))
			lines.append("  Spd: %.1f  AngVel: %.2f" % [spd, ang_v])
			var sail_obj = p.get("sail")
			if sail_obj != null:
				lines.append("  Sail: %s  Deploy: %d%%" % [sail_obj.get_display_name(), int(sail_obj.current_sail_level * 100.0)])
			var helm_obj = p.get("helm")
			if helm_obj != null:
				var rud_deg: float = helm_obj.rudder_angle * _HelmController.MAX_RUDDER_DEFLECTION_DEG
				lines.append("  Helm: %s  Rudder: %.0f°" % [helm_obj.get_helm_state_label(), rud_deg])
		var ctrl: Variant = null
		if ci < _bot_controllers.size():
			ctrl = _bot_controllers[ci]
		if ctrl != null:
			lines.append("  BT: %s  Man: %s" % [ctrl.current_bt_state, ctrl.last_maneuver])
			lines.append("  Dist: %.0f  Band: %s  Bearing: %.0f°" % [ctrl.distance_to_target, NavalCombatEvaluator.band_name(ctrl.range_band), ctrl.bearing_to_target_deg])
			lines.append("  Steer: L%.1f R%.1f  Sail: %d" % [ctrl.steer_left, ctrl.steer_right, ctrl.desired_sail_state])
			lines.append("  Block: %s" % ctrl.fire_block_reason)
			if not ctrl._bt_initialised:
				lines.append("  !! BT INIT FAILED")
		else:
			lines.append("  !! NO CONTROLLER")

		var panel_h: float = float(lines.size()) * 13.0 + 6.0
		draw_rect(Rect2(x - 5.0, y - 2.0, panel_w, panel_h), Color(0.0, 0.0, 0.0, 0.62))
		for line in lines:
			draw_string(font, Vector2(x, y + 11.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += 13.0
		y += 6.0


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


func _draw_trajectory_arc_preview(alpha_mult: float = 1.0) -> void:
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
	var port_active: bool = bool(p.get("aim_port_active", true))
	var stbd_active: bool = bool(p.get("aim_stbd_active", false))
	if port_b != null and port_active:
		var aim_p: Vector2 = _effective_broadside_aim_for_side(p, hull_n, true)
		batteries.append({"bat": port_b, "aim": aim_p, "col": Color(1.0, 0.28, 0.22, 0.82 * alpha_mult)})
	if stbd_b != null and stbd_active:
		var aim_s: Vector2 = _effective_broadside_aim_for_side(p, hull_n, false)
		batteries.append({"bat": stbd_b, "aim": aim_s, "col": Color(1.0, 0.45, 0.18, 0.82 * alpha_mult)})
	for bd in batteries:
		_draw_single_battery_arc(p, bd.aim, bd.bat, bd.col, alpha_mult)


func _draw_single_battery_arc(p: Dictionary, aim_dir: Vector2, bat: _BatteryController, color: Color, alpha_mult: float = 1.0) -> void:
	var est_range: float = float(p.get("_naval_acc_dist", NC.OPTIMAL_RANGE))
	if est_range < 0.0 or est_range > NC.MAX_CANNON_RANGE:
		est_range = NC.OPTIMAL_RANGE
	var spread_half: float = _spread_cone_half_deg(p, est_range)
	var dirs: Array[Vector2] = [
		aim_dir,
		aim_dir.rotated(deg_to_rad(spread_half)),
		aim_dir.rotated(deg_to_rad(-spread_half)),
	]
	var elev_deg_arc: float = bat.elevation_degrees()
	@warning_ignore("integer_division")
	var mid_gun: int = maxi(0, (bat.cannon_count - 1) / 2)
	var muzzle_w: Vector2 = _cannon_muzzle_world(p, bat, mid_gun)
	for idx in range(dirs.size()):
		var d: Vector2 = dirs[idx].normalized()
		var vel: Dictionary = _CannonBallistics.initial_velocity(d, elev_deg_arc)
		var vx: float = float(vel.vx)
		var vy: float = float(vel.vy)
		var vz: float = float(vel.vz)
		var wx0: float = muzzle_w.x
		var wy0: float = muzzle_w.y
		var h0: float = _CannonBallistics.MUZZLE_HEIGHT
		var grav: float = _CannonBallistics.GRAVITY
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
				var dot_alpha: float = lerpf(0.8, 0.15, float(i) / maxf(1.0, float(points.size() - 1))) * alpha_mult
				draw_circle(points[i], 1.4, Color(color.r, color.g, color.b, dot_alpha))


func _draw_ship_trajectory_arc_preview(alpha_mult: float = 1.0) -> void:
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

	var prev_sail_eff: float = lerpf(1.0, _SailController.MIN_EFFICIENCY, sail.damage)
	var target_cap: float = 0.0
	var sails_provide_thrust: bool = true
	match int(sail.sail_state):
		_SailController.SailState.FULL:
			target_cap = NC.MAX_SPEED * prev_sail_eff
		_SailController.SailState.HALF:
			target_cap = NC.CRUISE_SPEED * prev_sail_eff
		_SailController.SailState.QUARTER:
			target_cap = NC.QUARTER_SPEED * prev_sail_eff
		_:
			target_cap = NC.SAILS_DOWN_DRIFT_SPEED
			sails_provide_thrust = false

	var accel_r: float = NC.accel_rate()
	var decel_r: float = NC.decel_rate_sails()
	var tau: float = maxf(0.001, NC.HELM_TURN_LAG_SEC)
	var sim_t: float = 0.0
	var sim_max_t: float = 45.0
	var points: PackedVector2Array = PackedVector2Array()
	var deck_lift_y: float = -(NC.SHIP_DECK_HEIGHT_UNITS * _CannonBallistics.SCREEN_HEIGHT_PX_PER_UNIT * _zoom) - 2.0 * _zoom
	var deck_off: Vector2 = Vector2(0.0, deck_lift_y)
	var dt_step: float = 1.0 / 60.0
	var sim_sail_level: float = float(sail.current_sail_level)
	var sim_sail_target: float = float(sail.get_target_sail_level())
	var sim_sail_rate: float = float(sail.sail_raise_rate) if sim_sail_level < sim_sail_target else float(sail.sail_lower_rate)
	var sim_coast_thresh: float = float(sail.coast_drag_threshold)

	var preview_rudder: float = helm.rudder_angle
	while sim_t <= sim_max_t:
		points.append(_w2s(wx, wy) + deck_off)

		var rudder: float = preview_rudder

		var turn_deg: float = NC.turn_rate_deg_for_speed(spd)
		var max_turn_rad: float = deg_to_rad(turn_deg)
		var steer_auth: float = maxf(NC.RUDDER_AUTHORITY_MIN, clampf(spd / NC.RUDDER_AUTHORITY_SPEED, 0.0, 1.0))
		var target_av: float = max_turn_rad * rudder * steer_auth
		ang_vel = lerpf(ang_vel, target_av, 1.0 - exp(-dt_step / tau))
		hull = hull.rotated(ang_vel * dt_step).normalized()

		sim_sail_level = move_toward(sim_sail_level, sim_sail_target, sim_sail_rate * dt_step)
		var drag_mult: float = COAST_DRAG_MULT if sim_sail_level < sim_coast_thresh else 1.0
		var sim_drift_floor: float = NC.SAILS_DOWN_DRIFT_SPEED if not sails_provide_thrust and spd > 0.01 else 0.0
		if spd < target_cap and sails_provide_thrust:
			spd = minf(spd + accel_r * dt_step, target_cap)
		elif spd > target_cap:
			spd = maxf(0.0, spd - decel_r * drag_mult * dt_step)
		spd = maxf(sim_drift_floor, spd - MOTION_PASSIVE_DRAG_K * spd * drag_mult * dt_step)
		if sim_sail_level < sim_coast_thresh:
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
	draw_polyline(points, Color(0.36, 0.86, 1.0, 0.82 * alpha_mult), 2.4, true)
	for i in range(0, points.size(), 6):
		var a: float = lerpf(0.85, 0.18, float(i) / maxf(1.0, float(points.size() - 1))) * alpha_mult
		draw_circle(points[i], 1.7, Color(0.62, 0.95, 1.0, a))


func _draw_aim_cursor() -> void:
	if _players.is_empty():
		return
	var p: Dictionary = _players[_my_index]
	if not bool(p.get("alive", true)):
		return
	var hull_n: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if hull_n.length_squared() < 0.0001:
		hull_n = Vector2.RIGHT
	hull_n = hull_n.normalized()
	# Draw a reticle for each active battery independently.
	if bool(p.get("aim_port_active", true)):
		var bat: Variant = p.get("battery_port")
		if bat != null:
			_draw_battery_reticle(p, hull_n, bat as _BatteryController, true)
	if bool(p.get("aim_stbd_active", false)):
		var bat: Variant = p.get("battery_stbd")
		if bat != null:
			_draw_battery_reticle(p, hull_n, bat as _BatteryController, false)


func _draw_battery_reticle(p: Dictionary, hull_n: Vector2, bat_br: _BatteryController, is_port: bool) -> void:
	var aim_dir: Vector2 = _effective_broadside_aim_for_side(p, hull_n, is_port)
	var elev_deg: float = bat_br.elevation_degrees()
	var vel: Dictionary = _CannonBallistics.initial_velocity(aim_dir, elev_deg)
	var vx: float = float(vel.vx)
	var vy: float = float(vel.vy)
	var vz: float = float(vel.vz)
	@warning_ignore("integer_division")
	var mid_gun: int = maxi(0, (bat_br.cannon_count - 1) / 2)
	var muzzle_w: Vector2 = _cannon_muzzle_world(p, bat_br, mid_gun)
	var wx0: float = muzzle_w.x
	var wy0: float = muzzle_w.y
	var h0: float = _CannonBallistics.MUZZLE_HEIGHT
	var grav: float = _CannonBallistics.GRAVITY
	var disc: float = vz * vz + 2.0 * grav * h0
	var t_splash: float = (vz + sqrt(maxf(0.0, disc))) / maxf(0.001, grav)
	var impact_t: float = minf(t_splash, NC.PROJECTILE_LIFETIME)
	var impact_wx: float = wx0 + vx * impact_t
	var impact_wy: float = wy0 + vy * impact_t
	var sp: Vector2 = _w2s(impact_wx, impact_wy)
	var ship_sp: Vector2 = _hull_visual_screen_pos(p)

	var impact_dist: float = Vector2(impact_wx - muzzle_w.x, impact_wy - muzzle_w.y).length()
	var spread_half_deg: float = _spread_cone_half_deg(p, minf(impact_dist, NC.MAX_CANNON_RANGE))
	var spread_world: float = impact_dist * tan(deg_to_rad(spread_half_deg))
	var n_guns: int = maxi(1, bat_br.cannon_count)
	var hull_half_span: float = float(n_guns - 1) * 0.5 * 2.3
	var is_barrage: bool = bat_br.fire_mode == _BatteryController.FireMode.SALVO
	var w2px: float = _TD_SCALE * _zoom
	var aim_s: Vector2 = _dir_screen(aim_dir.x, aim_dir.y)
	if aim_s.length_squared() < 0.0001:
		aim_s = Vector2(1.0, 0.0)
	aim_s = aim_s.normalized()
	var perp_s: Vector2 = Vector2(-aim_s.y, aim_s.x)

	# --- Range line: dashed line from ship to impact point ---
	var range_col: Color = Color(1.0, 1.0, 1.0, 0.15)
	var dash_len: float = 6.0
	var gap_len: float = 8.0
	var line_vec: Vector2 = sp - ship_sp
	var line_len: float = line_vec.length()
	if line_len > 1.0:
		var line_dir: Vector2 = line_vec / line_len
		var drawn: float = 0.0
		while drawn < line_len:
			var seg_start: float = drawn
			var seg_end: float = minf(drawn + dash_len, line_len)
			draw_line(ship_sp + line_dir * seg_start, ship_sp + line_dir * seg_end, range_col, 1.0, true)
			drawn = seg_end + gap_len

	if is_barrage:
		# --- BARRAGE: bracket zone showing the wall of iron ---
		# Two parallel lines (hull span + spread) with range-depth end caps.
		var col: Color = Color(1.0, 0.40, 0.15, 0.80)
		var col_fill: Color = Color(1.0, 0.40, 0.15, 0.06)
		var cross_w: float = (hull_half_span + spread_world) * w2px
		var depth_w: float = spread_world * 0.7 * w2px
		cross_w = maxf(cross_w, 6.0)
		depth_w = maxf(depth_w, 4.0)

		# Four corners of the impact zone rectangle.
		var c_tl: Vector2 = sp - perp_s * cross_w - aim_s * depth_w
		var c_tr: Vector2 = sp + perp_s * cross_w - aim_s * depth_w
		var c_br: Vector2 = sp + perp_s * cross_w + aim_s * depth_w
		var c_bl: Vector2 = sp - perp_s * cross_w + aim_s * depth_w

		# Filled zone (very subtle).
		draw_colored_polygon(PackedVector2Array([c_tl, c_tr, c_br, c_bl]), col_fill)
		# Bracket lines: two long sides (perpendicular to aim = hull-length spread).
		draw_line(c_tl, c_tr, col, 1.8, true)
		draw_line(c_bl, c_br, col, 1.8, true)
		# End caps: short lines closing the bracket at each end.
		var cap_len: float = minf(depth_w * 0.6, 8.0)
		draw_line(c_tl, c_tl + aim_s * cap_len, col, 1.5, true)
		draw_line(c_tr, c_tr + aim_s * cap_len, col, 1.5, true)
		draw_line(c_bl, c_bl - aim_s * cap_len, col, 1.5, true)
		draw_line(c_br, c_br - aim_s * cap_len, col, 1.5, true)
		# Center dot.
		draw_circle(sp, 2.5, col)

		# Range text (meters).
		var range_m: int = int(impact_dist)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, sp + aim_s * (depth_w + 10.0) + perp_s * 2.0,
			"%dm" % range_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r, col.g, col.b, 0.6))
	else:
		# --- RIPPLE: focused crosshair at convergence point ---
		var col: Color = Color(0.3, 0.85, 1.0, 0.80)
		var spread_px: float = maxf(spread_world * w2px, 4.0)
		var arm_inner: float = spread_px * 0.4
		var arm_outer: float = spread_px + 6.0

		# Four crosshair arms with gap in the center.
		draw_line(sp + perp_s * arm_inner, sp + perp_s * arm_outer, col, 1.5, true)
		draw_line(sp - perp_s * arm_inner, sp - perp_s * arm_outer, col, 1.5, true)
		draw_line(sp + aim_s * arm_inner, sp + aim_s * arm_outer, col, 1.5, true)
		draw_line(sp - aim_s * arm_inner, sp - aim_s * arm_outer, col, 1.5, true)

		# Diamond showing the spread cone.
		var d_cross: float = spread_px
		var d_along: float = spread_px * 0.6
		var diamond: PackedVector2Array = PackedVector2Array([
			sp - perp_s * d_cross,
			sp + aim_s * d_along,
			sp + perp_s * d_cross,
			sp - aim_s * d_along,
			sp - perp_s * d_cross,
		])
		draw_polyline(diamond, Color(col.r, col.g, col.b, 0.5), 1.2, true)

		# Center dot.
		draw_circle(sp, 2.0, col)

		# Range text.
		var range_m: int = int(impact_dist)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, sp + aim_s * (arm_outer + 6.0) + perp_s * 2.0,
			"%dm" % range_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r, col.g, col.b, 0.6))


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

	var bs_port_on: bool = bool(p.get("aim_port_active", true))
	var bs_stbd_on: bool = bool(p.get("aim_stbd_active", false))
	var bs_txt: String
	if bs_port_on and bs_stbd_on:
		bs_txt = "Both broadsides"
	elif bs_port_on:
		bs_txt = "Port broadside"
	elif bs_stbd_on:
		bs_txt = "Starboard broadside"
	else:
		bs_txt = "No battery selected"
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
		match sail.sail_state:
			_SailController.SailState.FULL:
				cap = NC.MAX_SPEED
			_SailController.SailState.HALF:
				cap = NC.CRUISE_SPEED
			_SailController.SailState.QUARTER:
				cap = NC.QUARTER_SPEED
			_:
				cap = NC.SAILS_DOWN_DRIFT_SPEED
	draw_string(font, Vector2(x, y + 88.0), "Speed %.2f / %.1f" % [spd, cap], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)

	var bat_y: float = y + 108.0
	var sel_port_on: bool = bool(p.get("aim_port_active", true))
	var sel_stbd_on: bool = bool(p.get("aim_stbd_active", false))
	var fire_sel: String
	if sel_port_on and sel_stbd_on:
		fire_sel = "Both (E/Q)"
	elif sel_port_on:
		fire_sel = "Port (E)"
	elif sel_stbd_on:
		fire_sel = "Starboard (Q)"
	else:
		fire_sel = "None"
	draw_string(font, Vector2(x, bat_y), "Fire battery: %s · F/RT" % fire_sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sub)
	draw_string(font, Vector2(x, bat_y + 14.0), "Batteries", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub)
	_draw_battery_row(font, x, bat_y + 30.0, panel_w, p.get("battery_port"), txt, sub, dim, sel_port_on)
	_draw_battery_row(font, x, bat_y + 58.0, panel_w, p.get("battery_stbd"), txt, sub, dim, sel_stbd_on)


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
	var hud_idx: int = clampi(_camera_follow_index, 0, _players.size() - 1)
	var p: Dictionary = _players[hud_idx]
	var font: Font = ThemeDB.fallback_font
	var sel_fire_port: bool = bool(p.get("aim_port_active", true))
	var sel_fire_stbd: bool = bool(p.get("aim_stbd_active", false))
	var hw: float = 64.0
	var hh: float = 180.0
	var cx: float = vp.x - hw - 20.0
	var cy: float = vp.y * 0.5
	var panel_x: float = cx - hw - 10.0
	var panel_y: float = cy - hh * 0.5 - 28.0
	var panel_w: float = hw * 2.0 + 20.0
	var panel_h: float = hh + 80.0

	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.03, 0.05, 0.09, 0.92))
	draw_rect(Rect2(panel_x + 1.0, panel_y + 1.0, panel_w - 2.0, panel_h - 2.0), Color(0.18, 0.24, 0.36, 0.85), false, 1.0)
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.28, 0.36, 0.50, 0.9), false, 1.5)

	var title_y: float = panel_y + 16.0
	draw_string(font, Vector2(cx - 28.0, title_y), "SHIP STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.78, 0.88, 0.9))
	draw_line(Vector2(panel_x + 6.0, title_y + 4.0), Vector2(panel_x + panel_w - 6.0, title_y + 4.0), Color(0.28, 0.36, 0.48, 0.6), 1.0)

	var hull_dark: Color = Color(0.24, 0.20, 0.16, 0.95)
	var hull_mid: Color = Color(0.38, 0.32, 0.24, 0.92)
	var bow_tip: Vector2 = Vector2(cx, cy - hh * 0.44)
	var bow_l: Vector2 = Vector2(cx - hw * 0.35, cy - hh * 0.32)
	var bow_r: Vector2 = Vector2(cx + hw * 0.35, cy - hh * 0.32)
	var fwd_l: Vector2 = Vector2(cx - hw * 0.62, cy - hh * 0.15)
	var fwd_r: Vector2 = Vector2(cx + hw * 0.62, cy - hh * 0.15)
	var mid_l: Vector2 = Vector2(cx - hw * 0.72, cy + hh * 0.02)
	var mid_r: Vector2 = Vector2(cx + hw * 0.72, cy + hh * 0.02)
	var aft_l: Vector2 = Vector2(cx - hw * 0.65, cy + hh * 0.22)
	var aft_r: Vector2 = Vector2(cx + hw * 0.65, cy + hh * 0.22)
	var stern_l: Vector2 = Vector2(cx - hw * 0.48, cy + hh * 0.38)
	var stern_r: Vector2 = Vector2(cx + hw * 0.48, cy + hh * 0.38)
	var transom: Vector2 = Vector2(cx, cy + hh * 0.35)
	var hull_poly: PackedVector2Array = PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l])
	draw_colored_polygon(hull_poly, hull_dark)
	draw_polyline(PackedVector2Array([
		bow_tip, bow_r, fwd_r, mid_r, aft_r, stern_r, transom, stern_l, aft_l, mid_l, fwd_l, bow_l, bow_tip]),
		hull_mid, 1.8, true)

	draw_line(Vector2(cx, cy - hh * 0.42), Vector2(cx, cy - hh * 0.50), Color(0.55, 0.45, 0.30, 0.85), 2.0, true)
	draw_line(Vector2(cx - 8.0, cy - hh * 0.50), Vector2(cx + 8.0, cy - hh * 0.50), Color(0.55, 0.45, 0.30, 0.7), 1.5, true)
	draw_line(Vector2(cx, cy - hh * 0.08), Vector2(cx, cy - hh * 0.32), Color(0.50, 0.42, 0.28, 0.7), 1.5, true)
	draw_line(Vector2(cx - 12.0, cy - hh * 0.28), Vector2(cx + 12.0, cy - hh * 0.28), Color(0.50, 0.42, 0.28, 0.6), 1.2, true)
	draw_line(Vector2(cx, cy + 0.0), Vector2(cx, cy + hh * 0.15), Color(0.50, 0.42, 0.28, 0.6), 1.2, true)

	var hp: float = float(p.get("health", HULL_HITS_MAX))
	var hp_frac: float = clampf(hp / HULL_HITS_MAX, 0.0, 1.0)

	var zone_names: Array[String] = ["Bowsprit", "Bow", "Fwd Gun", "Mid", "Main", "Aft Gun", "Quarter", "Stern"]
	var zone_count: int = zone_names.size()
	var zone_y_start: float = cy - hh * 0.42
	var zone_total_h: float = hh * 0.80
	var zone_h: float = zone_total_h / float(zone_count)

	var zone_widths: Array[float] = [0.30, 0.50, 0.68, 0.72, 0.72, 0.65, 0.52, 0.40]
	for zi in range(zone_count):
		var zy: float = zone_y_start + float(zi) * zone_h
		var zw: float = hw * zone_widths[zi]
		var zone_hp: float = hp_frac
		var zone_col: Color
		if hp <= 0.0:
			zone_col = Color(0.12, 0.10, 0.08, 0.5)
		elif zone_hp > 0.7:
			zone_col = Color(0.18, 0.48, 0.28, 0.55)
		elif zone_hp > 0.4:
			zone_col = Color(0.62, 0.52, 0.18, 0.55)
		elif zone_hp > 0.15:
			zone_col = Color(0.72, 0.32, 0.14, 0.55)
		else:
			zone_col = Color(0.78, 0.18, 0.12, 0.65)
		draw_rect(Rect2(cx - zw * 0.5, zy + 1.0, zw, zone_h - 2.0), zone_col)
		draw_line(Vector2(cx - zw * 0.5, zy + zone_h - 1.0), Vector2(cx + zw * 0.5, zy + zone_h - 1.0), Color(0.40, 0.44, 0.52, 0.35), 0.8)
		var lbl_col: Color = Color(0.82, 0.85, 0.92, 0.75)
		draw_string(font, Vector2(cx - zw * 0.5 + 3.0, zy + zone_h - 4.0), zone_names[zi], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, lbl_col)

	var bat_icon_r: float = 6.0
	var bat_entries: Array[Dictionary] = []
	var port_b: Variant = p.get("battery_port")
	var stbd_b: Variant = p.get("battery_stbd")
	if port_b != null:
		bat_entries.append({"bat": port_b, "pos": Vector2(cx - hw * 0.88, cy - hh * 0.05), "label": "P"})
	if stbd_b != null:
		bat_entries.append({"bat": stbd_b, "pos": Vector2(cx + hw * 0.88, cy - hh * 0.05), "label": "S"})
	for be in bat_entries:
		var bat: _BatteryController = be.bat
		var bp: Vector2 = be.pos
		var is_ready: bool = bat.state == _BatteryController.BatteryState.READY
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
			bc = Color(lerpf(0.65, 0.30, prog), lerpf(0.22, 0.68, prog), 0.28, 0.9)
			state_label = "RELOAD %d%%" % int(prog * 100.0)
		elif is_ready:
			bc = Color(0.2, 0.85, 0.35, 0.95)
			state_label = "READY"
		else:
			bc = Color(0.45, 0.48, 0.55, 0.7)
			state_label = bat.state_display()
		draw_circle(bp, bat_icon_r, Color(0.06, 0.08, 0.12, 0.9))
		draw_circle(bp, bat_icon_r - 1.5, bc)
		draw_arc(bp, bat_icon_r, 0.0, TAU, 20, Color(0.6, 0.65, 0.75, 0.7), 1.2, true)
		var bat_is_selected: bool = (bat.side == _BatteryController.BatterySide.PORT and sel_fire_port) \
			or (bat.side == _BatteryController.BatterySide.STARBOARD and sel_fire_stbd)
		if bat_is_selected:
			draw_arc(bp, bat_icon_r + 3.5, 0.0, TAU, 24, Color(1.0, 0.88, 0.30, 0.92), 2.0, true)
		if is_ready:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			draw_arc(bp, bat_icon_r + 2.0, 0.0, TAU, 16, Color(0.2, 1.0, 0.4, 0.35 * pulse), 1.5, true)
		if reloading:
			draw_arc(bp, bat_icon_r + 2.0, -PI * 0.5, -PI * 0.5 + TAU * bat.reload_progress(), 16, Color(0.82, 0.70, 0.32, 0.9), 2.2, true)
		draw_string(font, bp + Vector2(-3.0, 3.5), be.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.95, 1.0, 0.95))
		var lbl_offset: Vector2
		match bat.side:
			_BatteryController.BatterySide.PORT:
				lbl_offset = Vector2(-bat_icon_r - 4.0, 3.5)
				draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_RIGHT, int(bat_icon_r * 8.0), 7, bc)
			_BatteryController.BatterySide.STARBOARD:
				lbl_offset = Vector2(bat_icon_r + 4.0, 3.5)
				draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, bc)
			_:
				lbl_offset = Vector2(-16.0, bat_icon_r + 9.0)
				draw_string(font, bp + lbl_offset, state_label, HORIZONTAL_ALIGNMENT_CENTER, 32, 7, bc)

	# Gun port dots along the hull sides.
	var gun_count: int = 8
	for gi in range(gun_count):
		var t: float = 0.18 + float(gi) / float(gun_count - 1) * 0.58
		var gy: float = cy - hh * 0.42 + zone_total_h * t
		var gw_t: float = lerpf(0.50, 0.72, clampf((t - 0.1) / 0.4, 0.0, 1.0))
		if t > 0.6:
			gw_t = lerpf(0.72, 0.45, clampf((t - 0.6) / 0.3, 0.0, 1.0))
		var gx_off: float = hw * gw_t * 0.5 - 2.0
		var gc: Color = Color(0.55, 0.48, 0.32, 0.7)
		draw_rect(Rect2(cx - gx_off - 2.5, gy - 1.0, 5.0, 2.0), gc)
		draw_rect(Rect2(cx + gx_off - 2.5, gy - 1.0, 5.0, 2.0), gc)

	var hp_bar_x: float = panel_x + 6.0
	var hp_bar_y: float = cy + hh * 0.5 - 4.0
	var hp_bar_w: float = panel_w - 12.0
	draw_rect(Rect2(hp_bar_x, hp_bar_y, hp_bar_w, 12.0), Color(0.06, 0.08, 0.12, 0.95))
	draw_rect(Rect2(hp_bar_x, hp_bar_y, hp_bar_w, 12.0), Color(0.25, 0.30, 0.42, 0.7), false, 1.0)
	var hp_col: Color
	if hp_frac > 0.6:
		hp_col = Color(0.25, 0.72, 0.35, 0.92)
	elif hp_frac > 0.3:
		hp_col = Color(0.78, 0.68, 0.22, 0.92)
	else:
		hp_col = Color(0.85, 0.22, 0.18, 0.92)
	draw_rect(Rect2(hp_bar_x + 1.0, hp_bar_y + 1.0, (hp_bar_w - 2.0) * hp_frac, 10.0), hp_col)
	for tick_i in range(1, int(HULL_HITS_MAX)):
		var tx: float = hp_bar_x + hp_bar_w * (float(tick_i) / HULL_HITS_MAX)
		draw_line(Vector2(tx, hp_bar_y + 1.0), Vector2(tx, hp_bar_y + 11.0), Color(0.12, 0.14, 0.18, 0.6), 0.8)
	draw_string(font, Vector2(hp_bar_x, hp_bar_y + 24.0), "Hull %d / %d" % [int(maxf(hp, 0.0)), int(HULL_HITS_MAX)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.88, 0.95, 0.95))

	var elev_y: float = hp_bar_y + 36.0
	var elev_alpha: float = _hud_fade_alpha(_fade_elev_hud)
	var ref_bat: Variant = p.get("battery_port") if sel_fire_port else p.get("battery_stbd")
	if ref_bat != null and elev_alpha > 0.01:
		var elev_val: float = ref_bat.cannon_elevation
		var elev_deg: float = ref_bat.elevation_degrees()
		var elev_col: Color = Color(0.6, 0.75, 0.95, 0.9 * elev_alpha)
		draw_rect(Rect2(hp_bar_x, elev_y, hp_bar_w, 8.0), Color(0.06, 0.08, 0.12, 0.92 * elev_alpha))
		draw_rect(Rect2(hp_bar_x + 1.0, elev_y + 1.0, (hp_bar_w - 2.0) * elev_val, 6.0), elev_col)
		var tick_x: float = hp_bar_x + hp_bar_w * elev_val
		draw_rect(Rect2(tick_x - 1.0, elev_y - 1.0, 3.0, 10.0), Color(1.0, 1.0, 1.0, 0.9 * elev_alpha))
		var zero_frac: float = absf(ref_bat.ELEV_MIN_DEG) / (ref_bat.ELEV_MAX_DEG - ref_bat.ELEV_MIN_DEG)
		var zero_x: float = hp_bar_x + hp_bar_w * zero_frac
		draw_rect(Rect2(zero_x - 0.5, elev_y - 2.0, 1.0, 12.0), Color(1.0, 1.0, 0.6, 0.7 * elev_alpha))
		var sign_str: String = "+" if elev_deg >= 0.0 else ""
		draw_string(font, Vector2(hp_bar_x, elev_y + 20.0), "Quoin %s%.1f° (R/T)" % [sign_str, elev_deg], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, elev_col)


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
	var spd_kn: float = spd_u * _KNOTS_PER_GAME_UNIT
	draw_string(font, Vector2(x, y + 68.0), "Speed: %.1f kn" % spd_kn, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, txt)

	# --- Component damage indicators ---
	var comp_y: float = y + 82.0
	var bar_w: float = panel_w - 8.0
	var comp_bar_h: float = 5.0
	# Sail damage bar
	if sail.damage > 0.01:
		var sail_dmg_col: Color = Color(0.95, 0.65, 0.20, 0.92) if sail.damage < 0.6 else Color(0.92, 0.30, 0.18, 0.95)
		draw_rect(Rect2(x, comp_y, bar_w, comp_bar_h), Color(0.08, 0.1, 0.14, 0.8))
		draw_rect(Rect2(x, comp_y, bar_w * clampf(sail.damage, 0.0, 1.0), comp_bar_h), sail_dmg_col)
		draw_string(font, Vector2(x + bar_w + 3.0, comp_y + comp_bar_h), "Rigging -%d%%" % int(sail.damage * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, sail_dmg_col)
		comp_y += comp_bar_h + 3.0
	# Helm damage bar
	if helm.damage > 0.01:
		var helm_dmg_col: Color = Color(0.95, 0.65, 0.20, 0.92) if helm.damage < 0.6 else Color(0.92, 0.30, 0.18, 0.95)
		draw_rect(Rect2(x, comp_y, bar_w, comp_bar_h), Color(0.08, 0.1, 0.14, 0.8))
		draw_rect(Rect2(x, comp_y, bar_w * clampf(helm.damage, 0.0, 1.0), comp_bar_h), helm_dmg_col)
		draw_string(font, Vector2(x + bar_w + 3.0, comp_y + comp_bar_h), "Rudder -%d%%" % int(helm.damage * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, helm_dmg_col)
		comp_y += comp_bar_h + 3.0
	var comp_offset: float = comp_y - (y + 82.0)

	var sail_y: float = y + 86.0 + comp_offset
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
		"E / LB: select PORT battery (aim + elevation + fire target)",
		"Q / RB: select STARBOARD battery",
		"F / X / RT: fire selected battery only",
		"Steer: %s / %s" % [_action_keys_display(_ACTIONS.left), _action_keys_display(_ACTIONS.right)],
		"Sail up · down: %s · %s" % [_action_keys_display(SAIL_RAISE_ACTION), _action_keys_display(SAIL_LOWER_ACTION)],
		"Fire mode: %s" % _action_keys_display(FIRE_MODE_ACTION),
		"Elevation up · down: %s · %s" % [_action_keys_display(ELEV_UP_ACTION), _action_keys_display(ELEV_DOWN_ACTION)],
		"Wheel lock toggle: %s" % _action_keys_display(WHEEL_LOCK_ACTION),
		"Zoom: mouse wheel or +/- buttons (top-right)",
		"Pan: arrow keys or middle-mouse drag",
		"1 / Home / Tab: lock camera to follow your ship",
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
	var sel_port_ab: bool = bool(p.get("aim_port_active", true)) if not p.is_empty() else true
	var sel_stbd_ab: bool = bool(p.get("aim_stbd_active", false)) if not p.is_empty() else false
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
	if sel_port_ab and port_b != null:
		total_count += 1
		if port_b.state == _BatteryController.BatteryState.READY:
			ready_count += 1
	if sel_stbd_ab and stbd_b2 != null:
		total_count += 1
		if stbd_b2.state == _BatteryController.BatteryState.READY:
			ready_count += 1
	var side_lbl: String
	if sel_port_ab and sel_stbd_ab:
		side_lbl = "P+S"
	elif sel_port_ab:
		side_lbl = "P"
	elif sel_stbd_ab:
		side_lbl = "S"
	else:
		side_lbl = "—"
	var fire_key: String = _slot_key_caption(_ACTIONS.atk)
	var fire_lbl: String = "FIRE %s %d/%d" % [side_lbl, ready_count, total_count]
	_draw_ability_slot(font, Vector2(x + 398.0, y + 12.0), fire_key, fire_lbl, ready_count > 0)
	var cam_hint: String = ""
	if not _camera_locked:
		cam_hint = " · FREE CAM (press 1 to snap back)"
	var hint: String = "Bindings shown in panel above · Pause Esc" + cam_hint
	draw_string(font, Vector2(x + 10.0, y - 4.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.82, 0.64, 0.95))


func _draw_ability_slot(font: Font, pos: Vector2, key_name: String, label: String, enabled: bool) -> void:
	var col: Color = Color(0.28, 0.85, 0.56, 0.95) if enabled else Color(0.56, 0.64, 0.72, 0.95)
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), Color(0.16, 0.20, 0.24, 0.9))
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), col, false, 1.6)
	draw_string(font, pos + Vector2(6.0, 18.0), "[%s] %s" % [key_name, label], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
