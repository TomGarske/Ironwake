extends "res://scripts/iso_arena.gd"

# Blacksite Containment starts from the legacy Iso Arena baseline.
# This script now owns a brighter Area 51 profile and metal perimeter treatment.

const MapProfile := preload("res://scripts/shared/blacksite_map_profile.gd")

var _map_layout: Dictionary = {}
var _projectiles: Array[Dictionary] = []
var _move_sfx_cooldown: float = 0.0
var _burst_shots_left: int = 0
var _burst_shot_timer: float = 0.0
var _ability_q_enabled: bool = false
var _ability_e_enabled: bool = false
var _ability_r_enabled: bool = false
var _sfx_player: AudioStreamPlayer = null
var _enemy_spawn_points: Array[Vector2] = []
var _enemies: Array[Dictionary] = []
var _enemy_spawn_timer: float = 0.0
var _turrets: Array[Dictionary] = []
var _gate_integrity: float = 1000.0
var _building_integrity: float = 750.0
var _pad_fire_prev: bool = false
var _pad_boost_prev: bool = false
var _pad_q_prev: bool = false
var _pad_e_prev: bool = false
var _pad_r_prev: bool = false

const FACE_LEFT_ACTION: String = "bf_face_left"
const FACE_RIGHT_ACTION: String = "bf_face_right"
const FACE_UP_ACTION: String = "bf_face_up"
const FACE_DOWN_ACTION: String = "bf_face_down"
const BOOST_ACTION: String = "bf_boost"
const ABILITY_Q_ACTION: String = "bf_ability_q"
const ABILITY_E_ACTION: String = "bf_ability_e"
const ABILITY_R_ACTION: String = "bf_ability_r"

const BOOST_MULTIPLIER: float = 2.2
const BURST_COUNT: int = 3
const BURST_SHOT_INTERVAL: float = 0.06
const BURST_SPREAD: float = 0.08
const PROJECTILE_RANGE: float = 10.0
const PROJECTILE_SPEED: float = 14.0
const PROJECTILE_DAMAGE: float = 25.0
const PROJECTILE_RADIUS: float = 0.62
const ENEMY_SPEED: float = 2.2
const ENEMY_HP: float = 75.0
const ENEMY_SPAWN_INTERVAL: float = 2.0
const ENEMY_GATE_DAMAGE: float = 35.0
const TURRET_MAX_HP: float = 180.0
const TURRET_RANGE: float = 8.0
const TURRET_FIRE_COOLDOWN: float = 0.45
const TURRET_DAMAGE: float = 30.0
const REPAIR_AMOUNT: float = 140.0
const _STICK_DEADZONE: float = 0.2

func _load_geo_map() -> void:
	_map_layout = MapProfile.configure_renderer(_terrain_renderer)
	_terrain_renderer.chunk_size = CHUNK_SIZE
	var data: Dictionary = {
		"width": int(_map_layout.get("map_width", MapProfile.MAP_WIDTH)),
		"height": int(_map_layout.get("map_height", MapProfile.MAP_HEIGHT)),
	}
	_enemy_spawn_points = MapProfile.get_door_spawn_points(_map_layout)
	_enemies.clear()
	_projectiles.clear()
	_turrets.clear()
	_enemy_spawn_timer = 0.4
	_gate_integrity = 1000.0
	_building_integrity = 750.0
	_SPAWNS = MapProfile.build_drone_spawns(data)

func _ready() -> void:
	super._ready()
	_ensure_audio_player()

func _register_inputs() -> void:
	_set_action_keys(_ACTIONS.left, [KEY_A])
	_set_action_keys(_ACTIONS.right, [KEY_D])
	_set_action_keys(_ACTIONS.up, [KEY_W])
	_set_action_keys(_ACTIONS.down, [KEY_S])
	_set_action_keys(_ACTIONS.atk, [KEY_F])
	_set_action_mouse_buttons(_ACTIONS.atk, [MOUSE_BUTTON_LEFT])
	_ensure_joy_button_for_action(_ACTIONS.atk, JOY_BUTTON_X)

	_set_action_keys(FACE_LEFT_ACTION, [KEY_LEFT])
	_set_action_keys(FACE_RIGHT_ACTION, [KEY_RIGHT])
	_set_action_keys(FACE_UP_ACTION, [KEY_UP])
	_set_action_keys(FACE_DOWN_ACTION, [KEY_DOWN])
	_set_action_keys(BOOST_ACTION, [KEY_SPACE])
	_set_action_keys(ABILITY_Q_ACTION, [KEY_Q])
	_set_action_keys(ABILITY_E_ACTION, [KEY_E])
	_set_action_keys(ABILITY_R_ACTION, [KEY_R])
	_ensure_joy_button_for_action(BOOST_ACTION, JOY_BUTTON_A)

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
	_tick_enemies(delta)
	_tick_turrets(delta)
	_tick_projectiles(delta)
	_tick_local_timers(delta)
	_handle_ability_toggles()
	queue_redraw()

func _tick_player(p: Dictionary, delta: float) -> void:
	if pause_menu_panel != null and pause_menu_panel.visible:
		return
	if not p.alive:
		return

	var move := Vector2.ZERO
	if Input.is_action_pressed(_ACTIONS.left):
		move.x -= 1.0
	if Input.is_action_pressed(_ACTIONS.right):
		move.x += 1.0
	if Input.is_action_pressed(_ACTIONS.up):
		move.y -= 1.0
	if Input.is_action_pressed(_ACTIONS.down):
		move.y += 1.0
	var pad_id: int = _get_primary_pad_id()
	if pad_id >= 0:
		var stick_move := Vector2(
			Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
		)
		if stick_move.length() > _STICK_DEADZONE:
			move += stick_move
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_LEFT):
			move.x -= 1.0
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_RIGHT):
			move.x += 1.0
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_UP):
			move.y -= 1.0
		if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_DOWN):
			move.y += 1.0
	_update_facing_from_inputs(p, pad_id)

	var boost_pressed: bool = Input.is_action_pressed(BOOST_ACTION) or _is_pad_boost_pressed(pad_id)
	var boost_just_pressed: bool = Input.is_action_just_pressed(BOOST_ACTION) or (boost_pressed and not _pad_boost_prev)
	_pad_boost_prev = boost_pressed
	if boost_just_pressed:
		_play_tone(190.0, 0.06, 0.28)

	var current_speed: float = SPEED
	if boost_pressed:
		current_speed *= BOOST_MULTIPLIER

	if move.length_squared() > 0.0:
		move = move.normalized()
		var new_wx: float = p.wx + move.x * current_speed * delta
		var new_wy: float = p.wy + move.y * current_speed * delta
		if _is_walkable_tile(_terrain_renderer.get_tile_at(new_wx, new_wy)):
			p.wx = new_wx
			p.wy = new_wy
		p.moving = true
		p.walk_time += delta
		if _move_sfx_cooldown <= 0.0:
			_play_tone(108.0 if not boost_pressed else 172.0, 0.050, 0.14)
			_move_sfx_cooldown = 0.11
	else:
		p.moving = false

	var fire_pressed: bool = Input.is_action_pressed(_ACTIONS.atk) or _is_pad_fire_pressed(pad_id)
	var fire_just_pressed: bool = (Input.is_action_just_pressed(_ACTIONS.atk) or (fire_pressed and not _pad_fire_prev))
	_pad_fire_prev = fire_pressed
	if fire_just_pressed and p.atk_time <= 0.0:
		p.atk_time = ATK_DUR
		p.hit_landed = false
		_burst_shots_left = BURST_COUNT
		_burst_shot_timer = 0.0
	p.atk_time = maxf(p.atk_time - delta, 0.0)
	_tick_burst_fire(p, delta)

func _tick_burst_fire(p: Dictionary, delta: float) -> void:
	if _burst_shots_left <= 0:
		return
	_burst_shot_timer = maxf(_burst_shot_timer - delta, 0.0)
	if _burst_shot_timer > 0.0:
		return
	_burst_shot_timer = BURST_SHOT_INTERVAL
	_burst_shots_left -= 1
	var spread: float = randf_range(-BURST_SPREAD, BURST_SPREAD)
	_fire_projectile(p, spread)
	_play_tone(410.0, 0.045, 0.10)

func _update_facing_from_inputs(p: Dictionary, pad_id: int) -> void:
	if pad_id >= 0:
		var aim_stick := Vector2(
			Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_Y)
		)
		if aim_stick.length() > _STICK_DEADZONE:
			var world_from_stick: Vector2 = _screen_to_world_dir(aim_stick)
			if world_from_stick.length_squared() > 0.0:
				p.dir = world_from_stick
				return

	var drone_screen: Vector2 = _w2s(float(p.wx), float(p.wy))
	var mouse_delta: Vector2 = get_local_mouse_position() - drone_screen
	if mouse_delta.length() > 10.0:
		var world_from_mouse: Vector2 = _screen_to_world_dir(mouse_delta)
		if world_from_mouse.length_squared() > 0.0:
			p.dir = world_from_mouse
			return

	_update_facing_from_arrows(p)

func _update_facing_from_arrows(p: Dictionary) -> void:
	var face := Vector2.ZERO
	if Input.is_action_pressed(FACE_LEFT_ACTION):
		face.x -= 1.0
	if Input.is_action_pressed(FACE_RIGHT_ACTION):
		face.x += 1.0
	if Input.is_action_pressed(FACE_UP_ACTION):
		face.y -= 1.0
	if Input.is_action_pressed(FACE_DOWN_ACTION):
		face.y += 1.0
	if face.length_squared() > 0.0:
		p.dir = face.normalized()

func _screen_to_world_dir(screen_vec: Vector2) -> Vector2:
	var sx_scale: float = TILE_W * _zoom * 0.5
	var sy_scale: float = TILE_H * _zoom * 0.5
	if is_zero_approx(sx_scale) or is_zero_approx(sy_scale):
		return Vector2.ZERO
	var a: float = screen_vec.x / sx_scale
	var b: float = screen_vec.y / sy_scale
	var wx: float = (a + b) * 0.5
	var wy: float = (b - a) * 0.5
	var v := Vector2(wx, wy)
	return v.normalized() if v.length_squared() > 0.0001 else Vector2.ZERO

func _is_pad_fire_pressed(pad_id: int) -> bool:
	if pad_id < 0:
		return false
	return Input.get_joy_axis(pad_id, JOY_AXIS_TRIGGER_RIGHT) > 0.35 \
		or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_RIGHT_SHOULDER) \
		or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X)

func _is_pad_boost_pressed(pad_id: int) -> bool:
	if pad_id < 0:
		return false
	return Input.is_joy_button_pressed(pad_id, JOY_BUTTON_A) \
		or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_LEFT_SHOULDER)

func _is_walkable_tile(tile_id: int) -> bool:
	# Walls/buildings are mountain tiles; everything else is traversable surface.
	return tile_id != IsoTerrainRenderer.T_MOUNTAIN

func _check_hit(_attacker: Dictionary, _defender: Dictionary) -> void:
	# Disable melee arc checks; combat in Blacksite is ranged projectile-driven.
	return

func _fire_projectile(p: Dictionary, spread_bias: float = 0.0) -> void:
	var dir: Vector2 = p.dir
	if dir.length_squared() <= 0.001:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var owner_peer: int = int(p.get("peer_id", 1))
	if owner_peer <= 0 and multiplayer.has_multiplayer_peer():
		owner_peer = multiplayer.get_unique_id()
	var shot_dir: Vector2 = dir.rotated(spread_bias).normalized()
	var start_x: float = float(p.wx) + shot_dir.x * 0.6
	var start_y: float = float(p.wy) + shot_dir.y * 0.6
	if multiplayer.has_multiplayer_peer():
		_spawn_projectile_rpc.rpc(start_x, start_y, shot_dir.x, shot_dir.y, owner_peer, PROJECTILE_DAMAGE, false)
	else:
		_spawn_projectile_local(start_x, start_y, shot_dir.x, shot_dir.y, owner_peer, PROJECTILE_DAMAGE, false)

@rpc("any_peer", "call_local", "unreliable")
func _spawn_projectile_rpc(wx: float, wy: float, dx: float, dy: float, owner_peer: int, damage: float, from_turret: bool) -> void:
	_spawn_projectile_local(wx, wy, dx, dy, owner_peer, damage, from_turret)

func _spawn_projectile_local(wx: float, wy: float, dx: float, dy: float, owner_peer: int, damage: float, from_turret: bool) -> void:
	var dir := Vector2(dx, dy)
	if dir.length_squared() <= 0.001:
		return
	dir = dir.normalized()
	_projectiles.append({
		"wx": wx,
		"wy": wy,
		"dir": dir,
		"remaining": PROJECTILE_RANGE,
		"owner_peer": owner_peer,
		"damage": damage,
		"from_turret": from_turret,
		"alive": true,
	})

func _tick_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var host_authority: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	for i in range(_projectiles.size() - 1, -1, -1):
		var proj: Dictionary = _projectiles[i]
		if not bool(proj.get("alive", true)):
			_projectiles.remove_at(i)
			continue
		var remaining: float = float(proj.get("remaining", 0.0))
		if remaining <= 0.0:
			_projectiles.remove_at(i)
			continue

		var dir: Vector2 = proj.get("dir", Vector2.RIGHT)
		var step: float = minf(PROJECTILE_SPEED * delta, remaining)
		proj["wx"] = float(proj.get("wx", 0.0)) + dir.x * step
		proj["wy"] = float(proj.get("wy", 0.0)) + dir.y * step
		proj["remaining"] = remaining - step

		if host_authority:
			var hit_done: bool = false
			var damage: float = float(proj.get("damage", PROJECTILE_DAMAGE))
			for e_idx in range(_enemies.size() - 1, -1, -1):
				var enemy: Dictionary = _enemies[e_idx]
				var dx: float = float(enemy.get("wx", 0.0)) - float(proj["wx"])
				var dy: float = float(enemy.get("wy", 0.0)) - float(proj["wy"])
				if dx * dx + dy * dy <= PROJECTILE_RADIUS * PROJECTILE_RADIUS:
					enemy["hp"] = float(enemy.get("hp", ENEMY_HP)) - damage
					if float(enemy["hp"]) <= 0.0:
						_enemies.remove_at(e_idx)
					else:
						_enemies[e_idx] = enemy
					proj["alive"] = false
					hit_done = true
					break
			if hit_done:
				_projectiles[i] = proj
				continue
		_projectiles[i] = proj

func _tick_local_timers(delta: float) -> void:
	_move_sfx_cooldown = maxf(_move_sfx_cooldown - delta, 0.0)
	_enemy_spawn_timer = maxf(_enemy_spawn_timer - delta, 0.0)

func _handle_ability_toggles() -> void:
	var pad_id: int = _get_primary_pad_id()
	var q_pad: bool = pad_id >= 0 and Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X)
	var e_pad: bool = pad_id >= 0 and Input.is_joy_button_pressed(pad_id, JOY_BUTTON_Y)
	var r_pad: bool = pad_id >= 0 and Input.is_joy_button_pressed(pad_id, JOY_BUTTON_B)
	var q_just: bool = Input.is_action_just_pressed(ABILITY_Q_ACTION) or (q_pad and not _pad_q_prev)
	var e_just: bool = Input.is_action_just_pressed(ABILITY_E_ACTION) or (e_pad and not _pad_e_prev)
	var r_just: bool = Input.is_action_just_pressed(ABILITY_R_ACTION) or (r_pad and not _pad_r_prev)
	_pad_q_prev = q_pad
	_pad_e_prev = e_pad
	_pad_r_prev = r_pad

	if q_just:
		_deploy_turret()
	if e_just:
		_ability_e_enabled = not _ability_e_enabled
		_play_tone(390.0, 0.05, 0.20)
	if r_just:
		_repair_nearest_structure()

func _tick_enemies(delta: float) -> void:
	if _enemy_spawn_points.is_empty():
		return
	if _enemy_spawn_timer <= 0.0:
		_spawn_enemy()
		_enemy_spawn_timer = ENEMY_SPAWN_INTERVAL

	var gate_target := Vector2(float(_map_layout.get("gate_center", 0)) + 0.5, float(_map_layout.get("ring_bottom", 0)) + 0.5)
	var building_target := Vector2(
		float(_map_layout.get("building_x", 0)) + float(_map_layout.get("building_w", 0)) * 0.5,
		float(_map_layout.get("building_y", 0)) + float(_map_layout.get("building_h", 0)) * 0.5
	)
	for i in range(_enemies.size() - 1, -1, -1):
		var e: Dictionary = _enemies[i]
		var pos := Vector2(float(e.get("wx", 0.0)), float(e.get("wy", 0.0)))
		var target: Vector2 = gate_target if _gate_integrity > 0.0 else building_target
		var v: Vector2 = target - pos
		if v.length_squared() > 0.001:
			var dir: Vector2 = v.normalized()
			pos += dir * ENEMY_SPEED * delta
			e["wx"] = pos.x
			e["wy"] = pos.y
		if v.length() < 0.8:
			if _gate_integrity > 0.0:
				_gate_integrity = maxf(_gate_integrity - ENEMY_GATE_DAMAGE, 0.0)
			else:
				_building_integrity = maxf(_building_integrity - ENEMY_GATE_DAMAGE * 0.7, 0.0)
			_enemies.remove_at(i)
		else:
			_enemies[i] = e

func _spawn_enemy() -> void:
	var idx: int = randi() % _enemy_spawn_points.size()
	var p: Vector2 = _enemy_spawn_points[idx]
	_enemies.append({
		"wx": p.x,
		"wy": p.y,
		"hp": ENEMY_HP,
	})
	_play_tone(240.0, 0.05, 0.10)

func _tick_turrets(delta: float) -> void:
	if _turrets.is_empty() or _enemies.is_empty():
		return
	for i in range(_turrets.size() - 1, -1, -1):
		var t: Dictionary = _turrets[i]
		var hp: float = float(t.get("hp", TURRET_MAX_HP))
		if hp <= 0.0:
			_turrets.remove_at(i)
			continue
		var cooldown: float = maxf(float(t.get("cooldown", 0.0)) - delta, 0.0)
		if cooldown > 0.0:
			t["cooldown"] = cooldown
			_turrets[i] = t
			continue
		var t_pos := Vector2(float(t.get("wx", 0.0)), float(t.get("wy", 0.0)))
		var enemy_idx: int = _nearest_enemy_index(t_pos, TURRET_RANGE)
		if enemy_idx >= 0:
			var e: Dictionary = _enemies[enemy_idx]
			var dir: Vector2 = Vector2(float(e.get("wx", 0.0)), float(e.get("wy", 0.0))) - t_pos
			if dir.length_squared() > 0.001:
				dir = dir.normalized()
				_spawn_projectile_local(t_pos.x, t_pos.y, dir.x, dir.y, -1, TURRET_DAMAGE, true)
				t["cooldown"] = TURRET_FIRE_COOLDOWN
				_play_tone(510.0, 0.03, 0.12)
		_turrets[i] = t

func _nearest_enemy_index(origin: Vector2, max_range: float) -> int:
	var best_idx: int = -1
	var best_dist_sq: float = max_range * max_range
	for i in range(_enemies.size()):
		var e: Dictionary = _enemies[i]
		var d: Vector2 = Vector2(float(e.get("wx", 0.0)), float(e.get("wy", 0.0))) - origin
		var dsq: float = d.length_squared()
		if dsq <= best_dist_sq:
			best_dist_sq = dsq
			best_idx = i
	return best_idx

func _deploy_turret() -> void:
	if _players.is_empty():
		return
	var me: Dictionary = _players[_my_index]
	var facing: Vector2 = Vector2(me.get("dir", Vector2.RIGHT))
	if facing.length_squared() <= 0.001:
		facing = Vector2.RIGHT
	var turret_pos: Vector2 = Vector2(float(me.get("wx", 0.0)), float(me.get("wy", 0.0))) + facing.normalized() * 1.2
	_turrets.append({
		"wx": turret_pos.x,
		"wy": turret_pos.y,
		"hp": TURRET_MAX_HP,
		"cooldown": 0.2,
	})
	_ability_q_enabled = true
	_play_tone(300.0, 0.08, 0.22)

func _repair_nearest_structure() -> void:
	if _players.is_empty():
		return
	var me: Dictionary = _players[_my_index]
	var origin := Vector2(float(me.get("wx", 0.0)), float(me.get("wy", 0.0)))
	var repaired: bool = false
	var best_idx: int = -1
	var best_dist_sq: float = 9.0
	for i in range(_turrets.size()):
		var t: Dictionary = _turrets[i]
		var d: Vector2 = Vector2(float(t.get("wx", 0.0)), float(t.get("wy", 0.0))) - origin
		if d.length_squared() <= best_dist_sq:
			best_dist_sq = d.length_squared()
			best_idx = i
	if best_idx >= 0:
		var turret: Dictionary = _turrets[best_idx]
		turret["hp"] = minf(float(turret.get("hp", TURRET_MAX_HP)) + REPAIR_AMOUNT, TURRET_MAX_HP)
		_turrets[best_idx] = turret
		repaired = true
	if not repaired:
		if _gate_integrity < 1000.0:
			_gate_integrity = minf(_gate_integrity + REPAIR_AMOUNT, 1000.0)
			repaired = true
		elif _building_integrity < 750.0:
			_building_integrity = minf(_building_integrity + REPAIR_AMOUNT, 750.0)
			repaired = true
	_ability_r_enabled = repaired
	_play_tone(470.0 if repaired else 220.0, 0.07, 0.18)

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

	draw_rect(Rect2(Vector2.ZERO, vp), MapProfile.SKY_DAY)
	_draw_tiles(vp)
	var pulse_time: float = Time.get_ticks_msec() * 0.001
	MapProfile.draw_map_overlay(self, _origin, TILE_W * _zoom, TILE_H * _zoom, _map_layout, pulse_time)

	var sorted := _players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.wx + a.wy) < (b.wx + b.wy))
	_draw_turrets()
	_draw_enemies()
	for p in sorted:
		_draw_player(p)

	_draw_projectiles()
	_draw_structure_status(vp)
	_draw_offscreen_indicators(vp)
	_draw_hud(vp)
	_draw_ability_bar(vp)
	if _winner != -2:
		_draw_win_screen(vp)

func _draw_player(p: Dictionary) -> void:
	var sp: Vector2 = _w2s(p.wx, p.wy)
	var primary: Color = p.palette[0]
	var glow: Color = Color(
		minf(primary.r + 0.24, 1.0),
		minf(primary.g + 0.24, 1.0),
		minf(primary.b + 0.24, 1.0),
		0.95
	)

	if not p.alive:
		draw_circle(sp + Vector2(0.0, 4.0), 10.0 * _zoom, Color(0.35, 0.12, 0.12, 0.65))
		draw_line(sp + Vector2(-8.0, -4.0), sp + Vector2(8.0, 4.0), Color(0.9, 0.2, 0.2, 0.9), 2.5)
		draw_line(sp + Vector2(8.0, -4.0), sp + Vector2(-8.0, 4.0), Color(0.9, 0.2, 0.2, 0.9), 2.5)
		return

	var bob: float = sin(p.walk_time * 6.0) * 1.4 if p.moving else 0.0
	var core: Vector2 = sp + Vector2(0.0, -7.0 + bob)
	var forward: Vector2 = _dir_screen(p.dir.x, p.dir.y)
	var right: Vector2 = Vector2(-forward.y, forward.x)

	# Hover shadow and glow.
	draw_set_transform(core + Vector2(0.0, 10.0), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, 22.0 * _zoom, Color(0.22, 0.20, 0.16, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(core, 13.0 * _zoom, Color(primary.r, primary.g, primary.b, 0.22))

	# Drone body (vector-styled hull, no texture dependency).
	draw_circle(core, 8.5 * _zoom, Color(0.20, 0.24, 0.30, 0.96))
	draw_circle(core, 6.2 * _zoom, Color(0.14, 0.18, 0.24, 1.0))
	draw_line(core - right * 8.0 * _zoom, core + right * 8.0 * _zoom, Color(0.40, 0.50, 0.60, 0.95), 2.0)
	draw_line(core - forward * 7.0 * _zoom, core + forward * 11.0 * _zoom, Color(0.40, 0.50, 0.60, 0.95), 2.0)
	draw_circle(core + forward * 11.0 * _zoom, 2.2 * _zoom, primary)

	# Engine pods + thruster flares.
	var pod_a: Vector2 = core - forward * 3.0 * _zoom + right * 11.0 * _zoom
	var pod_b: Vector2 = core - forward * 3.0 * _zoom - right * 11.0 * _zoom
	draw_circle(pod_a, 3.6 * _zoom, Color(0.16, 0.20, 0.24, 1.0))
	draw_circle(pod_b, 3.6 * _zoom, Color(0.16, 0.20, 0.24, 1.0))
	draw_circle(pod_a - forward * 3.0 * _zoom, 2.0 * _zoom, glow)
	draw_circle(pod_b - forward * 3.0 * _zoom, 2.0 * _zoom, glow)

	# Core light and callsign.
	draw_circle(core, 2.6 * _zoom, glow)
	var font := ThemeDB.fallback_font
	draw_string(font, core + Vector2(0.0, -24.0), p.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.82, 0.94, 1.0, 0.92))

func _draw_projectiles() -> void:
	for proj in _projectiles:
		if not bool(proj.get("alive", true)):
			continue
		var wx: float = float(proj.get("wx", 0.0))
		var wy: float = float(proj.get("wy", 0.0))
		var dir: Vector2 = proj.get("dir", Vector2.RIGHT)
		var sp: Vector2 = _w2s(wx, wy)
		var trail: Vector2 = _dir_screen(dir.x, dir.y) * 10.0 * _zoom
		var from_turret: bool = bool(proj.get("from_turret", false))
		var col: Color = Color(0.36, 0.94, 1.0, 0.9) if from_turret else Color(1.0, 0.74, 0.28, 0.9)
		draw_line(sp - trail, sp + trail * 0.3, col, 2.0)
		draw_circle(sp, 2.8 * _zoom, col.lightened(0.15))

func _draw_enemies() -> void:
	for e in _enemies:
		var sp: Vector2 = _w2s(float(e.get("wx", 0.0)), float(e.get("wy", 0.0)))
		var hp_ratio: float = clampf(float(e.get("hp", ENEMY_HP)) / ENEMY_HP, 0.0, 1.0)
		draw_set_transform(sp + Vector2(0.0, 6.0), 0.0, Vector2(1.0, 0.30))
		draw_circle(Vector2.ZERO, 11.0 * _zoom, Color(0.14, 0.08, 0.06, 0.30))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(sp.x - 4.0, sp.y - 10.0, 8.0, 10.0), Color(0.70, 0.18, 0.16, 0.96))
		draw_rect(Rect2(sp.x - 6.0, sp.y - 16.0, 12.0, 8.0), Color(0.88, 0.42, 0.20, 0.98))
		draw_rect(Rect2(sp.x - 9.0, sp.y - 20.0, 18.0, 3.0), Color(0.15, 0.12, 0.12, 0.85))
		draw_rect(Rect2(sp.x - 9.0, sp.y - 20.0, 18.0 * hp_ratio, 3.0), Color(0.96, 0.30, 0.24, 0.95))

func _draw_turrets() -> void:
	for t in _turrets:
		var sp: Vector2 = _w2s(float(t.get("wx", 0.0)), float(t.get("wy", 0.0)))
		var hp_ratio: float = clampf(float(t.get("hp", TURRET_MAX_HP)) / TURRET_MAX_HP, 0.0, 1.0)
		draw_circle(sp + Vector2(0.0, 5.0), 8.5 * _zoom, Color(0.10, 0.14, 0.16, 0.65))
		draw_circle(sp + Vector2(0.0, -4.0), 5.8 * _zoom, Color(0.22, 0.34, 0.42, 1.0))
		draw_circle(sp + Vector2(0.0, -8.0), 2.8 * _zoom, Color(0.32, 0.95, 0.88, 0.95))
		draw_rect(Rect2(sp.x - 10.0, sp.y - 18.0, 20.0, 3.0), Color(0.10, 0.14, 0.18, 0.88))
		draw_rect(Rect2(sp.x - 10.0, sp.y - 18.0, 20.0 * hp_ratio, 3.0), Color(0.24, 0.90, 0.58, 0.95))

func _draw_structure_status(vp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var gate_ratio: float = clampf(_gate_integrity / 1000.0, 0.0, 1.0)
	var build_ratio: float = clampf(_building_integrity / 750.0, 0.0, 1.0)
	draw_string(font, Vector2(20.0, 28.0), "Gate Integrity: %d%%" % int(gate_ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.92, 0.98, 0.96))
	draw_rect(Rect2(20.0, 34.0, 170.0, 6.0), Color(0.12, 0.14, 0.18, 0.9))
	draw_rect(Rect2(20.0, 34.0, 170.0 * gate_ratio, 6.0), Color(0.30, 0.80, 0.96, 0.95))
	draw_string(font, Vector2(20.0, 58.0), "Building Integrity: %d%%" % int(build_ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.92, 0.98, 0.96))
	draw_rect(Rect2(20.0, 64.0, 170.0, 6.0), Color(0.12, 0.14, 0.18, 0.9))
	draw_rect(Rect2(20.0, 64.0, 170.0 * build_ratio, 6.0), Color(0.98, 0.74, 0.26, 0.95))
	if _gate_integrity <= 0.0:
		draw_string(font, Vector2(vp.x * 0.5, 52.0), "GATE BREACHED", HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(1.0, 0.28, 0.24, 1.0))

func _draw_ability_bar(vp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var bar_w: float = 420.0
	var bar_h: float = 54.0
	var x: float = (vp.x - bar_w) * 0.5
	var y: float = vp.y - bar_h - 16.0
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.10, 0.12, 0.16, 0.82))
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.34, 0.42, 0.52, 0.9), false, 2.0)
	_draw_ability_slot(font, Vector2(x + 16.0, y + 12.0), "Q", "Drop Turret", true)
	_draw_ability_slot(font, Vector2(x + 150.0, y + 12.0), "E", "Scan", _ability_e_enabled)
	_draw_ability_slot(font, Vector2(x + 284.0, y + 12.0), "R", "Repair", _ability_r_enabled)
	var boost_text: String = "Boost [HOLD SPACE/A/LB] Continuous"
	draw_string(font, Vector2(x + 16.0, y - 4.0), boost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.82, 0.64, 0.95))

func _draw_ability_slot(font: Font, pos: Vector2, key_name: String, label: String, enabled: bool) -> void:
	var col: Color = Color(0.28, 0.85, 0.56, 0.95) if enabled else Color(0.56, 0.64, 0.72, 0.95)
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), Color(0.16, 0.20, 0.24, 0.9))
	draw_rect(Rect2(pos.x, pos.y, 120.0, 28.0), col, false, 1.6)
	draw_string(font, pos + Vector2(6.0, 18.0), "[%s] %s" % [key_name, label], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
