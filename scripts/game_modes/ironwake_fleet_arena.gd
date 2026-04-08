extends "res://scripts/game_modes/ironwake_arena.gd"

## PVE Fleet Arena: each player commands a fleet of 5 ships against AI enemies.
## Overrides spawn, respawn, and win logic from the base PVP arena.

const _FleetSpawner := preload("res://scripts/shared/fleet_spawner.gd")
const _WingmanController := preload("res://scripts/shared/wingman_controller.gd")
const _FleetRegistryClass := preload("res://scripts/shared/fleet_registry.gd")
const _RoutController := preload("res://scripts/shared/rout_controller.gd")
const _PveScoreboard := preload("res://scripts/shared/pve_scoreboard.gd")
const _MinimapRenderer := preload("res://scripts/ui/minimap_renderer.gd")
const _FleetCommandMenu := preload("res://scripts/ui/fleet_command_menu.gd")
const _CrewAiController := preload("res://scripts/shared/crew_ai_controller.gd")

const FLEET_ORDER_ACTION: String = "bf_fleet_order"

## Wingman controllers for the player's fleet (indices 1-4 in the fleet).
var _wingman_controllers: Array = []   # Array[WingmanController]
var _wingman_agents: Array = []        # Array[BotShipAgent]
var _wingman_indices: Array[int] = []  # indices into _players

## Enemy fleet controllers (standard NavalBotController).
var _enemy_controllers: Array = []
var _enemy_agents: Array = []
var _enemy_indices: Array[int] = []

## Player fleet ship indices (index 0 = player-controlled flagship).
var _player_fleet_indices: Array[int] = []

## Current fleet order for all wingmen.
var _current_fleet_order: int = _WingmanController.FleetOrder.FORM_UP

## Player fleet composition.
var _player_composition: Array[int] = _FleetSpawner.DEFAULT_FLEET_COMPOSITION
## Enemy fleet composition: 10 ships (2 Galleys, 4 Brigs, 4 Schooners).
var _enemy_composition: Array[int] = [
	_ShipClassConfig.ShipClass.GALLEY,
	_ShipClassConfig.ShipClass.GALLEY,
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.SCHOONER,
	_ShipClassConfig.ShipClass.SCHOONER,
	_ShipClassConfig.ShipClass.SCHOONER,
	_ShipClassConfig.ShipClass.SCHOONER,
]

## Palettes for player fleet and enemy fleet.
const PLAYER_FLEET_PALETTE: Array = [Color(0.22, 0.46, 1.00), Color(0.65, 0.82, 1.00)]
const ENEMY_FLEET_PALETTE: Array = [Color(0.85, 0.20, 0.15), Color(1.00, 0.50, 0.35)]

## Rout controller — handles fleeing behavior for defeated fleets.
var _rout: RoutController = null
## PVE cooperative scoreboard.
var _pve_score: PveScoreboard = null
## Track previously-alive state to detect deaths for scoreboard.
var _prev_alive_state: Dictionary = {}  # player_index -> bool
## True when the match outcome is decided but rout animation is still playing.
var _rout_in_progress: bool = false
## Which team won (0 = player, 1 = enemy, -1 = draw).
var _winning_team: int = -1
## Delay before declaring winner (let rout play out).
var _rout_timer: float = 0.0
const ROUT_DISPLAY_DELAY: float = 3.0
## Minimap renderer.
var _minimap: MinimapRenderer = null
## Radial fleet command menu.
var _radial_menu: FleetCommandMenu = null
## Other peers' wingman orders (HUD only; each peer runs local wingman AI).
var _remote_fleet_orders: Dictionary = {}
## All player fleet indices (across all peers) — for team 0 tracking.
var _all_player_fleet_indices: Array[int] = []
## Indices of ships this local peer owns (flagship + wingmen) — for state broadcast.
var _my_fleet_indices: Array[int] = []
## Enemy fleet scaling: extra ships per additional player.
const ENEMY_EXTRA_PER_PLAYER: Array[int] = [
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.BRIG,
	_ShipClassConfig.ShipClass.SCHOONER,
	_ShipClassConfig.ShipClass.SCHOONER,
	_ShipClassConfig.ShipClass.GALLEY,
	_ShipClassConfig.ShipClass.BRIG,
]
## Additional player fleet palettes (beyond blue for player 1).
const PLAYER_FLEET_PALETTES: Array = [
	[Color(0.22, 0.46, 1.00), Color(0.65, 0.82, 1.00)],  # P1 blue
	[Color(0.14, 0.76, 0.32), Color(0.52, 1.00, 0.60)],  # P2 green
	[Color(0.92, 0.72, 0.06), Color(1.00, 0.92, 0.44)],  # P3 gold
	[Color(0.70, 0.22, 0.96), Color(0.88, 0.62, 1.00)],  # P4 purple
]


func _ready() -> void:
	# Disable local sim and whirlpool — we handle fleet spawning ourselves.
	local_sim_enabled = false
	whirlpool_enabled = false
	# Enable independent camera zoom for fleet-scale viewing.
	_camera_zoom_independent = true
	# Set up PVE elimination win condition.
	var pve_win := WinCondition.PveEliminationWin.new()
	_win_condition = pve_win
	# Call parent _ready() — this will init helpers, call super._ready() (iso_arena),
	# spawn the placeholder player, and skip local sim bots.
	super._ready()
	# Disable ocean ambient noise (procedural static) — fleet mode uses music only.
	if _sound != null:
		_sound.stop_ocean_ambient()
	# Now set up fleet registry and connect to win condition.
	pve_win.fleet_registry = _fleet_registry
	# Init rout controller, scoreboard, minimap, and radial menu.
	_rout = RoutController.new()
	_pve_score = PveScoreboard.new()
	_minimap = MinimapRenderer.new()
	_minimap.configure(NC.MAP_TILES_WIDE, NC.MAP_TILES_HIGH, NC.UNITS_PER_LOGIC_TILE)
	_radial_menu = FleetCommandMenu.new()
	# Spawn both fleets.
	_spawn_fleets()
	# Init scoreboard with fleet size.
	_pve_score.reset(_all_player_fleet_indices.size())
	# Snapshot initial alive states.
	for i in range(_players.size()):
		_prev_alive_state[i] = bool(_players[i].get("alive", true))
	# Set initial zoom wider for fleet view.
	_zoom = 0.06
	_zoom_target = 0.06
	_remote_fleet_orders.clear()
	# Register fleet order input.
	_register_fleet_inputs()


func _register_fleet_inputs() -> void:
	if not InputMap.has_action(FLEET_ORDER_ACTION):
		InputMap.add_action(FLEET_ORDER_ACTION)
	_set_action_keys(FLEET_ORDER_ACTION, [KEY_G])


func _spawn_fleets() -> void:
	# Determine how many human peers are in the game.
	# In offline mode, _players has 2 placeholders; we keep only the local player.
	# In multiplayer, _players has one entry per peer from iso_arena._spawn_players().
	var is_mp: bool = multiplayer.has_multiplayer_peer()
	var peer_count: int = _players.size() if is_mp else 1

	# In offline mode, strip down to just the local player.
	if not is_mp:
		while _players.size() > 1:
			_players.pop_back()
		peer_count = 1

	var u: float = NC.UNITS_PER_LOGIC_TILE
	var map_center: Vector2 = Vector2(float(NC.MAP_TILES_WIDE) * 0.5 * u, float(NC.MAP_TILES_HIGH) * 0.5 * u)
	var centers: Dictionary = _FleetSpawner.compute_fleet_centers(map_center)
	var player_heading: Vector2 = centers["player_heading"]
	var enemy_heading: Vector2 = centers["enemy_heading"]
	var player_base_center: Vector2 = centers["player_center"]
	var enemy_center: Vector2 = centers["enemy_center"]

	# --- Spawn a fleet for each peer ---
	for pi in range(peer_count):
		var peer_dict: Dictionary = _players[pi]
		var palette: Array = PLAYER_FLEET_PALETTES[pi % PLAYER_FLEET_PALETTES.size()]
		var is_local: bool = (pi == _my_index)

		# Offset each peer's fleet laterally so they don't overlap.
		var lateral_offset: float = (float(pi) - float(peer_count - 1) * 0.5) * 400.0
		var fleet_center: Vector2 = player_base_center + player_heading.rotated(PI * 0.5) * lateral_offset

		var fleet_spawns: Array[Dictionary] = _FleetSpawner.spawn_fleet_formation(
			fleet_center, player_heading, _player_composition
		)

		# Reposition this peer's flagship.
		peer_dict.wx = fleet_spawns[0].wx
		peer_dict.wy = fleet_spawns[0].wy
		peer_dict.dir = fleet_spawns[0].dir
		peer_dict["team"] = 0
		peer_dict["palette"] = palette
		peer_dict["label"] = "P%d Flag" % (pi + 1) if peer_count > 1 else "Flagship"
		var peer_id: int = int(peer_dict.get("peer_id", 1))
		GameManager.player_ship_classes[peer_id] = _player_composition[0]
		_apply_naval_controllers_to_ship(peer_dict)
		_player_fleet_indices.append(pi)
		_all_player_fleet_indices.append(pi)
		if is_local:
			_my_fleet_indices.append(pi)

		# Spawn wingmen for this peer's fleet.
		for wi in range(1, fleet_spawns.size()):
			var spawn_info: Dictionary = fleet_spawns[wi]
			var wingman_dict: Dictionary = _FleetSpawner.create_fleet_ship_entry(
				spawn_info, pi, wi, 0, palette,
				"P%d W%d" % [pi + 1, wi]
			)
			_players.append(wingman_dict)
			var idx: int = _players.size() - 1
			_all_player_fleet_indices.append(idx)

			var bot_pid: int = int(wingman_dict.get("peer_id", 0))
			GameManager.player_ship_classes[bot_pid] = int(spawn_info.get("ship_class", _ShipClassConfig.ShipClass.BRIG))
			_init_bot_controllers(_players[idx])

			if not _scoreboard.has(bot_pid):
				_scoreboard[bot_pid] = {
					"kills": 0, "deaths": 0,
					"shots_fired": 0, "shots_hit": 0,
					"damage_dealt": 0.0, "damage_taken": 0.0,
				}

			# Only the LOCAL peer creates AI controllers for its own wingmen.
			# Remote peers' wingmen are state-synced, not locally simulated.
			if is_local:
				_player_fleet_indices.append(idx)
				_bot_indices.append(idx)
				_wingman_indices.append(idx)
				_my_fleet_indices.append(idx)

				var agent := BotShipAgent.new()
				agent.name = "WingmanAgent_P%d_%d" % [pi, wi]
				agent.ship_dict = _players[idx]
				add_child(agent)
				_wingman_agents.append(agent)

				var controller := _WingmanController.new()
				controller.name = "Wingman_P%d_%d" % [pi, wi]
				controller.agent = agent
				controller.flagship_dict = peer_dict
				controller.fleet_ship_index = wi
				var offset: Vector2 = Vector2(fleet_spawns[wi].wx, fleet_spawns[wi].wy) - Vector2(fleet_spawns[0].wx, fleet_spawns[0].wy)
				var flag_dir: Vector2 = player_heading.normalized()
				var flag_perp: Vector2 = flag_dir.rotated(PI * 0.5)
				controller.formation_offset = Vector2(offset.dot(flag_perp), offset.dot(flag_dir))
				add_child(controller)
				_wingman_controllers.append(controller)
				_bot_controllers.append(controller)
			else:
				# Remote peer's wingmen — just track them as allies, no local AI.
				_bot_indices.append(idx)

	# --- Scale enemy fleet based on player count ---
	var scaled_enemy_comp: Array[int] = _enemy_composition.duplicate()
	for extra_p in range(1, peer_count):
		for ship_class in ENEMY_EXTRA_PER_PLAYER:
			scaled_enemy_comp.append(ship_class)

	# --- Enemy fleet ---
	var enemy_spawns: Array[Dictionary] = _FleetSpawner.spawn_fleet_formation(
		enemy_center, enemy_heading, scaled_enemy_comp
	)

	# Target: pick a random alive player flagship for each enemy.
	var player_flagships: Array[Dictionary] = []
	for pi2 in range(peer_count):
		player_flagships.append(_players[pi2])

	for ei in range(enemy_spawns.size()):
		var spawn_info: Dictionary = enemy_spawns[ei]
		var enemy_dict: Dictionary = _FleetSpawner.create_fleet_ship_entry(
			spawn_info, peer_count, ei, 1, ENEMY_FLEET_PALETTE,
			"Enemy %d" % (ei + 1)
		)
		_players.append(enemy_dict)
		var idx: int = _players.size() - 1
		_bot_indices.append(idx)
		_enemy_indices.append(idx)

		var bot_pid: int = int(enemy_dict.get("peer_id", 0))
		GameManager.player_ship_classes[bot_pid] = int(spawn_info.get("ship_class", _ShipClassConfig.ShipClass.BRIG))
		_init_bot_controllers(_players[idx])

		if not _scoreboard.has(bot_pid):
			_scoreboard[bot_pid] = {
				"kills": 0, "deaths": 0,
				"shots_fired": 0, "shots_hit": 0,
				"damage_dealt": 0.0, "damage_taken": 0.0,
			}

		# Only host creates enemy AI controllers (host-authoritative).
		var is_authority: bool = not is_mp or multiplayer.is_server()
		if is_authority:
			var agent := BotShipAgent.new()
			agent.name = "EnemyAgent_%d" % ei
			agent.ship_dict = _players[idx]
			add_child(agent)
			_enemy_agents.append(agent)

			var controller := _NavalBotController.new()
			controller.name = "EnemyBot_%d" % ei
			controller.agent = agent
			# Spread enemy targeting across player flagships.
			controller.target_dict = player_flagships[ei % player_flagships.size()]
			add_child(controller)
			_enemy_controllers.append(controller)
			_bot_controllers.append(controller)

	# --- Register fleets in the registry ---
	_fleet_registry.register_fleet(0, _all_player_fleet_indices.duplicate(), 0, Color(0.22, 0.46, 1.00))
	_fleet_registry.register_fleet(1, _enemy_indices.duplicate(), 1, Color(0.85, 0.20, 0.15))

	_update_wingman_targets()

	var my_dict: Dictionary = _players[_my_index]
	_camera_world_anchor = Vector2(float(my_dict.wx), float(my_dict.wy))
	_camera_locked = true
	_camera_follow_index = _my_index


## Override _tick_respawn to do nothing (no respawn in PVE).
func _tick_respawn(_delta: float) -> void:
	pass


## Override state broadcast: send state for ALL ships this peer owns (flagship + wingmen).
func _broadcast_my_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	# Broadcast flagship (parent handles this via super).
	super._broadcast_my_state()
	# Also broadcast each wingman we own.
	for idx in _wingman_indices:
		if idx >= 0 and idx < _players.size():
			_broadcast_ship_state(_players[idx])


## Broadcast a single ship's state (reusable for wingmen).
func _broadcast_ship_state(p: Dictionary) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var sail_obj: Variant = p.get("sail")
	var helm_obj: Variant = p.get("helm")
	var sail_level: float = sail_obj.current_sail_level if sail_obj != null else 0.0
	var sail_state: int = int(sail_obj.sail_state) if sail_obj != null else 0
	var sail_dmg: float = sail_obj.damage if sail_obj != null else 0.0
	var rudder: float = helm_obj.rudder_angle if helm_obj != null else 0.0
	var helm_dmg: float = helm_obj.damage if helm_obj != null else 0.0
	var crew_obj: Variant = p.get("crew")
	var crew_packed: int = crew_obj.encode_sync() if crew_obj != null else 0
	var dmg_obj: Variant = p.get("damage_state")
	var dmg_fa: int = dmg_obj.encode_fire_a() if dmg_obj != null else 0
	var dmg_fb: int = dmg_obj.encode_fire_b() if dmg_obj != null else 0
	var dmg_misc: int = dmg_obj.encode_misc() if dmg_obj != null else 0
	_receive_naval_state.rpc(
		int(p.peer_id),
		float(p.wx), float(p.wy),
		float(p.dir.x), float(p.dir.y),
		float(p.atk_time), bool(p.moving), float(p.walk_time),
		float(p.get("move_speed", 0.0)),
		float(p.get("angular_velocity", 0.0)),
		float(p.get("health", float(p.get("hull_hits_max", 14.0)))),
		bool(p.get("alive", true)),
		sail_level, sail_state, rudder,
		sail_dmg, helm_dmg, crew_packed,
		dmg_fa, dmg_fb, dmg_misc
	)


## Override input: remap 1-5 to fleet ship camera snapping, disable crew overlay.
func _unhandled_input(event: InputEvent) -> void:
	# Intercept number keys 1-5 for fleet ship camera snapping.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			var fleet_idx: int = int(event.keycode) - int(KEY_1)  # 0-4
			if fleet_idx >= 0 and fleet_idx < _player_fleet_indices.size():
				var player_idx: int = _player_fleet_indices[fleet_idx]
				if player_idx >= 0 and player_idx < _players.size():
					_camera_follow_index = player_idx
					_camera_locked = true
					queue_redraw()
			return
		# Block crew overlay toggle (Tab) — crew is fully autonomous.
		if event.keycode == KEY_TAB:
			return
		# Block individual crew station keys (1-9 for crew) — already consumed above for 1-5.
		# Keys 6-9 would fall through to parent, which is fine.
	# Fleet-scale zoom: larger steps than parent (1.15) so scroll reaches wide zoom faster.
	if _camera_zoom_independent and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target * 1.25, _ZOOM_MIN, _ZOOM_MAX)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target / 1.25, _ZOOM_MIN, _ZOOM_MAX)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


## Process fleet input, rout behavior, and scoreboard each frame.
func _process(delta: float) -> void:
	# Fleet order: hold G = radial menu, tap G = cycle sequentially.
	if not _match_over and _radial_menu != null:
		var g_pressed: bool = Input.is_action_pressed(FLEET_ORDER_ACTION)
		var g_just_pressed: bool = Input.is_action_just_pressed(FLEET_ORDER_ACTION)
		var g_just_released: bool = Input.is_action_just_released(FLEET_ORDER_ACTION)
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var vp_center: Vector2 = get_viewport_rect().size * 0.5
		var radial_result: int = _radial_menu.process_input(delta, g_pressed, g_just_pressed,
			g_just_released, mouse_pos, vp_center)
		if radial_result >= 0:
			# Radial menu selection.
			_apply_fleet_order(radial_result)
		elif g_just_released and not _radial_menu.is_open:
			# Quick tap (released before radial opened) — cycle sequentially.
			_apply_fleet_order((_current_fleet_order + 1) % _WingmanController.ORDER_COUNT)

	# Track match time in the PVE scoreboard.
	if _pve_score != null and not _match_over:
		_pve_score.tick(delta)

	# Detect ship deaths for scoreboard + rout check.
	_check_ship_deaths()

	# Tick rout behavior for fleeing ships.
	if _rout_in_progress:
		_tick_rout(delta)

	super._process(delta)

	# Autonomous crew AI: manage crew allocation on the player's flagship.
	# (Wingmen crew is managed by their NavalBotController._manage_crew().)
	if not _match_over and _my_index >= 0 and _my_index < _players.size():
		var flag_dict: Dictionary = _players[_my_index]
		if bool(flag_dict.get("alive", false)):
			CrewAiController.tick(flag_dict)

	# Periodically update enemy targets to engage alive ships.
	if not _rout_in_progress and Engine.get_process_frames() % 60 == 0:
		_retarget_enemies()


## Detect when ships die: update scoreboard and check for rout trigger.
func _check_ship_deaths() -> void:
	for i in range(_players.size()):
		var alive_now: bool = bool(_players[i].get("alive", true))
		var alive_before: bool = bool(_prev_alive_state.get(i, true))
		if alive_before and not alive_now:
			# Ship just died.
			_prev_alive_state[i] = false
			# Is this an enemy ship? Count it as a team kill.
			if i in _enemy_indices:
				if _pve_score != null:
					_pve_score.record_kill()
			# Is this a player fleet ship?
			elif i in _player_fleet_indices:
				if _pve_score != null:
					_pve_score.fleet_ships_lost += 1
			# Check if this death triggers a rout.
			_check_rout_trigger()


## Check if either fleet has lost enough ships to trigger rout.
func _check_rout_trigger() -> void:
	if _rout_in_progress or _match_over:
		return

	# Count alive ships in each fleet (all player fleets combined).
	var player_alive: int = 0
	for idx in _all_player_fleet_indices:
		if idx >= 0 and idx < _players.size() and bool(_players[idx].get("alive", false)):
			player_alive += 1
	var enemy_alive: int = 0
	for idx in _enemy_indices:
		if idx >= 0 and idx < _players.size() and bool(_players[idx].get("alive", false)):
			enemy_alive += 1

	var player_total: int = _all_player_fleet_indices.size()
	var enemy_total: int = _enemy_indices.size()
	var player_threshold: int = ceili(float(player_total) * 0.5)
	var enemy_threshold: int = ceili(float(enemy_total) * 0.5)

	if enemy_alive <= enemy_threshold and player_alive > player_threshold:
		# Enemy fleet is routed — player wins.
		_trigger_fleet_rout(1, 0)
	elif player_alive <= player_threshold and enemy_alive > enemy_threshold:
		# Player fleet is routed — enemy wins.
		_trigger_fleet_rout(0, 1)
	elif player_alive <= player_threshold and enemy_alive <= enemy_threshold:
		# Both fleets destroyed — draw.
		_winning_team = -1
		_rout_in_progress = true
		_rout_timer = 0.0


## Trigger rout for the losing fleet.
func _trigger_fleet_rout(losing_team: int, winning_team: int) -> void:
	_winning_team = winning_team
	_rout_in_progress = true
	_rout_timer = 0.0

	# Mark the losing fleet as routed.
	var losing_fleet_id: int = losing_team  # fleet_id matches team for simplicity.
	_rout.trigger_rout(losing_fleet_id)

	# Sync scoreboard stats.
	if _pve_score != null:
		var player_peer_ids: Array[int] = []
		for idx in _all_player_fleet_indices:
			if idx >= 0 and idx < _players.size():
				player_peer_ids.append(int(_players[idx].get("peer_id", 0)))
		_pve_score.sync_from_scoreboard(_scoreboard, player_peer_ids)

	# Stop enemy/wingman AI for routed ships — they flee instead.
	var losing_indices: Array[int] = _enemy_indices if losing_team == 1 else _all_player_fleet_indices
	for idx in losing_indices:
		if idx >= 0 and idx < _players.size():
			_players[idx]["is_routed"] = true
			# Disable batteries on routed ships.
			for bat_key in BATTERY_CYCLE_KEYS:
				var bat: Variant = _players[idx].get(bat_key)
				if bat != null:
					bat.state = BatteryController.BatteryState.DISABLED


## Tick rout behavior: move fleeing ships and check for despawn / winner declaration.
func _tick_rout(delta: float) -> void:
	_rout_timer += delta

	# Determine which indices are routed.
	var routed_indices: Array[int] = []
	if _rout.is_fleet_routed(1):
		routed_indices = _enemy_indices
	elif _rout.is_fleet_routed(0):
		routed_indices = _player_fleet_indices

	# Compute flee direction: away from the winning fleet.
	var winner_indices: Array[int] = _all_player_fleet_indices if _winning_team == 0 else _enemy_indices
	var winner_centroid: Vector2 = RoutController.compute_centroid(_players, winner_indices)

	var all_despawned: bool = true
	for idx in routed_indices:
		if idx >= 0 and idx < _players.size():
			var p: Dictionary = _players[idx]
			if not bool(p.get("alive", true)):
				continue
			all_despawned = false
			var ship_pos: Vector2 = Vector2(float(p.wx), float(p.wy))
			var flee_dir: Vector2 = RoutController.compute_flee_direction(ship_pos, winner_centroid)
			var should_despawn: bool = _rout.tick_rout_ship(p, flee_dir, delta)
			if should_despawn:
				p["alive"] = false
				p["despawned"] = true

	# Declare winner after delay or when all routed ships are gone.
	if not _match_over and (_rout_timer >= ROUT_DISPLAY_DELAY or all_despawned):
		if _winning_team == 0:
			# Player wins — use player flagship index.
			_declare_winner(_my_index)
		elif _winning_team == 1:
			# Enemy wins — use first enemy index.
			if not _enemy_indices.is_empty():
				_declare_winner(_enemy_indices[0])
			else:
				_declare_winner(-1)
		else:
			_declare_winner(-1)  # Draw.


## Override the bot tick to skip routed ships (they're handled by _tick_rout).
func _tick_bot(p: Dictionary, player_idx: int, delta: float) -> void:
	if bool(p.get("is_routed", false)):
		return  # Routed ships are driven by _tick_rout, not the BT.
	super._tick_bot(p, player_idx, delta)


## Apply a fleet order to all wingmen.
func _apply_fleet_order(order: int) -> void:
	_current_fleet_order = order
	for wc in _wingman_controllers:
		if wc != null:
			wc.set_order(order as _WingmanController.FleetOrder)
			if order == _WingmanController.FleetOrder.ATTACK_MY_TARGET:
				_update_wingman_targets()
	_play_tone(350.0, 0.05, 0.12)
	if multiplayer.has_multiplayer_peer():
		_rpc_fleet_order_changed.rpc(multiplayer.get_unique_id(), order)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_fleet_order_changed(sender_peer_id: int, order: int) -> void:
	if order < 0 or order >= _WingmanController.ORDER_COUNT:
		return
	_remote_fleet_orders[sender_peer_id] = order


## Update wingman targets to engage nearest enemy to flagship.
func _update_wingman_targets() -> void:
	var flag_pos: Vector2 = Vector2(float(_players[_my_index].wx), float(_players[_my_index].wy))
	var nearest_enemy: Dictionary = _find_nearest_alive_enemy(flag_pos)
	for wc in _wingman_controllers:
		if wc != null and not nearest_enemy.is_empty():
			wc.target_dict = nearest_enemy


## Retarget enemies to engage alive player fleet ships (spread targeting).
func _retarget_enemies() -> void:
	var alive_player_ships: Array[Dictionary] = []
	for idx in _all_player_fleet_indices:
		if idx >= 0 and idx < _players.size() and bool(_players[idx].get("alive", false)):
			alive_player_ships.append(_players[idx])
	if alive_player_ships.is_empty():
		return
	for i in range(_enemy_controllers.size()):
		var ec: Variant = _enemy_controllers[i]
		if ec == null:
			continue
		if bool(ec.target_dict.get("alive", false)):
			continue
		ec.target_dict = alive_player_ships[i % alive_player_ships.size()]


func _find_nearest_alive_enemy(from_pos: Vector2) -> Dictionary:
	var best_dist: float = 1e18
	var best: Dictionary = {}
	for idx in _enemy_indices:
		if idx >= 0 and idx < _players.size():
			var e: Dictionary = _players[idx]
			if not bool(e.get("alive", false)):
				continue
			var d: float = from_pos.distance_squared_to(Vector2(float(e.wx), float(e.wy)))
			if d < best_dist:
				best_dist = d
				best = e
	return best


## Override _draw to add fleet HUD elements.
func _draw() -> void:
	super._draw()
	if not _match_over:
		_draw_formation_overlay()
	_draw_fleet_order_hud()
	_draw_fleet_status_hud()
	if _rout_in_progress and not _match_over:
		_draw_rout_banner()
	if not _match_over:
		_draw_minimap()
		if _radial_menu != null:
			_radial_menu.draw_menu(self, _current_fleet_order)


## Override the win screen with cooperative PVE stats.
func _draw_win_screen(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.62))
	var font: Font = ThemeDB.fallback_font
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.20

	# Victory / Defeat title.
	var title: String
	var title_col: Color
	if _winning_team == 0:
		title = "VICTORY"
		title_col = Color(0.30, 0.85, 0.40, 1.0)
	elif _winning_team == -1:
		title = "DRAW"
		title_col = Color(0.75, 0.70, 0.60, 1.0)
	else:
		title = "DEFEAT"
		title_col = Color(0.95, 0.30, 0.25, 1.0)
	draw_string(font, Vector2(cx, cy), title,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 56, title_col)

	# Performance rating.
	if _pve_score != null:
		var rating_y: float = cy + 40.0
		var rating: String = _pve_score.rating_name()
		var rating_col: Color = _pve_score.rating_color()
		draw_string(font, Vector2(cx, rating_y), "Rating: %s" % rating,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 36, rating_col)

		# Stats panel.
		var stats_x: float = cx - 160.0
		var stats_y: float = rating_y + 40.0
		var line_h: float = 22.0
		var txt_col: Color = Color(0.85, 0.88, 0.92, 0.95)
		var dim_col: Color = Color(0.60, 0.65, 0.72, 0.85)

		draw_rect(Rect2(stats_x - 10.0, stats_y - 10.0, 340.0, line_h * 7.0 + 20.0),
			Color(0.05, 0.07, 0.12, 0.85))
		draw_rect(Rect2(stats_x - 10.0, stats_y - 10.0, 340.0, line_h * 7.0 + 20.0),
			Color(0.3, 0.4, 0.55, 0.9), false, 1.5)

		draw_string(font, Vector2(stats_x, stats_y + line_h * 0.0),
			"Time: %s" % _pve_score.format_time(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, txt_col)
		draw_string(font, Vector2(stats_x, stats_y + line_h * 1.0),
			"Enemy Ships Sunk: %d" % _pve_score.team_ships_sunk,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, txt_col)
		draw_string(font, Vector2(stats_x, stats_y + line_h * 2.0),
			"Fleet Ships Lost: %d / %d" % [_pve_score.fleet_ships_lost, _pve_score.fleet_ships_total],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, txt_col)
		draw_string(font, Vector2(stats_x, stats_y + line_h * 3.0),
			"Fleet Survived: %d%%" % int(_pve_score.fleet_health_fraction() * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, txt_col)
		draw_string(font, Vector2(stats_x, stats_y + line_h * 4.0),
			"Total Damage: %.0f" % _pve_score.team_damage_dealt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim_col)
		draw_string(font, Vector2(stats_x, stats_y + line_h * 5.0),
			"Accuracy: %.1f%%" % _pve_score.accuracy_percent(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim_col)
		draw_string(font, Vector2(stats_x, stats_y + line_h * 6.0),
			"Shots: %d fired / %d hit" % [_pve_score.team_shots_fired, _pve_score.team_shots_hit],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim_col)

	# Continue prompt.
	if _post_match_ready:
		draw_string(font, Vector2(cx, vp.y * 0.88),
			"Press any key to continue...",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, _HUD_TEXT)
	else:
		var remaining: int = ceili(END_DELAY - _end_timer)
		draw_string(font, Vector2(cx, vp.y * 0.88),
			"Returning to menu in %d..." % remaining,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, _HUD_TEXT_MUTED)


func _draw_rout_banner() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var cx: float = vp.x * 0.5
	var banner_y: float = vp.y * 0.15
	var msg: String
	var col: Color
	if _winning_team == 0:
		msg = "ENEMY FLEET ROUTED!"
		col = Color(0.30, 0.85, 0.40, 0.95)
	elif _winning_team == 1:
		msg = "OUR FLEET IS ROUTED!"
		col = Color(0.95, 0.30, 0.25, 0.95)
	else:
		msg = "MUTUAL DESTRUCTION!"
		col = Color(0.75, 0.70, 0.60, 0.95)
	# Pulsing alpha.
	var pulse: float = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.005)
	draw_string(font, Vector2(cx, banner_y), msg,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(col.r, col.g, col.b, col.a * pulse))


## Draw formation lines from flagship to each wingman in world space.
func _draw_formation_overlay() -> void:
	if _players.is_empty():
		return
	var flag_dict: Dictionary = _players[_my_index]
	if not bool(flag_dict.get("alive", true)):
		return
	var flag_screen: Vector2 = _w2s(float(flag_dict.wx), float(flag_dict.wy))

	for i in range(_wingman_controllers.size()):
		var wi: int = _wingman_indices[i] if i < _wingman_indices.size() else -1
		if wi < 0 or wi >= _players.size():
			continue
		var wp: Dictionary = _players[wi]
		if not bool(wp.get("alive", false)):
			continue
		var wc: Variant = _wingman_controllers[i] if i < _wingman_controllers.size() else null
		if wc == null:
			continue

		var wing_screen: Vector2 = _w2s(float(wp.wx), float(wp.wy))
		var dist: float = wc.get_formation_distance()

		# Color based on formation status.
		var line_col: Color
		if wc.current_order != _WingmanController.FleetOrder.FORM_UP:
			line_col = Color(0.5, 0.5, 0.6, 0.15)  # Faint when not in formation mode.
		elif dist < _WingmanController.FORMATION_TOLERANCE:
			line_col = Color(0.3, 0.85, 0.4, 0.45)  # Green: in position.
		elif dist < _WingmanController.FORMATION_BROKEN_DIST:
			line_col = Color(0.9, 0.8, 0.2, 0.45)   # Yellow: moving to position.
		else:
			line_col = Color(0.95, 0.3, 0.2, 0.55)  # Red: broken formation.

		# Draw dashed line from flagship to wingman.
		var line_vec: Vector2 = wing_screen - flag_screen
		var line_len: float = line_vec.length()
		if line_len > 2.0:
			var line_dir: Vector2 = line_vec / line_len
			var dash: float = 8.0
			var gap: float = 6.0
			var drawn: float = 0.0
			while drawn < line_len:
				var seg_start: float = drawn
				var seg_end: float = minf(drawn + dash, line_len)
				draw_line(flag_screen + line_dir * seg_start,
					flag_screen + line_dir * seg_end, line_col, 1.2, true)
				drawn = seg_end + gap

		# Draw formation target position marker.
		if wc.current_order == _WingmanController.FleetOrder.FORM_UP:
			var target_pos: Vector2 = wc.get_formation_target_pos()
			var target_screen: Vector2 = _w2s(target_pos.x, target_pos.y)
			var marker_col: Color = Color(line_col.r, line_col.g, line_col.b, 0.3)
			draw_circle(target_screen, 4.0, marker_col)


## Draw the minimap with formation lines.
func _draw_minimap() -> void:
	if _minimap == null:
		return
	var vp: Vector2 = get_viewport_rect().size

	# Build formation lines for the minimap.
	var formation_lines: Array[Dictionary] = []
	if not _players.is_empty() and bool(_players[_my_index].get("alive", true)):
		var fw: float = float(_players[_my_index].wx)
		var fy: float = float(_players[_my_index].wy)
		for wi in _wingman_indices:
			if wi >= 0 and wi < _players.size() and bool(_players[wi].get("alive", false)):
				var wc_idx: int = _wingman_indices.find(wi)
				var wc: Variant = _wingman_controllers[wc_idx] if wc_idx >= 0 and wc_idx < _wingman_controllers.size() else null
				var col: Color = Color(0.4, 0.65, 0.9, 0.5)
				if wc != null and wc.current_order == _WingmanController.FleetOrder.FORM_UP:
					if wc.get_formation_distance() < _WingmanController.FORMATION_TOLERANCE:
						col = Color(0.3, 0.8, 0.4, 0.6)
					elif wc.get_formation_distance() < _WingmanController.FORMATION_BROKEN_DIST:
						col = Color(0.9, 0.8, 0.2, 0.5)
					else:
						col = Color(0.9, 0.3, 0.2, 0.5)
				formation_lines.append({
					"from_wx": fw, "from_wy": fy,
					"to_wx": float(_players[wi].wx), "to_wy": float(_players[wi].wy),
					"color": col,
				})

	_minimap.draw_minimap(self, vp, _players, _all_player_fleet_indices,
		_enemy_indices, _my_index, formation_lines)


func _draw_fleet_order_hud() -> void:
	if _match_over:
		return
	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var x: float = 16.0
	var y: float = vp.y - 80.0
	var order_name: String = _WingmanController.ORDER_NAMES[_current_fleet_order] if _current_fleet_order < _WingmanController.ORDER_COUNT else "Unknown"
	draw_rect(Rect2(x - 4.0, y - 14.0, 200.0, 60.0), Color(0.05, 0.07, 0.12, 0.85))
	draw_rect(Rect2(x - 4.0, y - 14.0, 200.0, 60.0), Color(0.3, 0.4, 0.55, 0.9), false, 1.5)
	draw_string(font, Vector2(x, y), "Fleet Order (G):", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.75, 0.85, 0.9))
	draw_string(font, Vector2(x, y + 16.0), order_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.88, 0.40, 1.0))
	var alive_wingmen: int = 0
	for idx in _wingman_indices:
		if idx >= 0 and idx < _players.size() and bool(_players[idx].get("alive", false)):
			alive_wingmen += 1
	draw_string(font, Vector2(x, y + 32.0), "Wingmen: %d/%d" % [alive_wingmen, _wingman_indices.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8, 0.85))


func _draw_fleet_status_hud() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var x: float = vp.x - 220.0
	var y: float = 16.0
	var alive_enemies: int = 0
	var total_enemies: int = _enemy_indices.size()
	for idx in _enemy_indices:
		if idx >= 0 and idx < _players.size() and bool(_players[idx].get("alive", false)):
			alive_enemies += 1
	var elim_threshold: int = ceili(float(total_enemies) * 0.5)
	draw_rect(Rect2(x - 4.0, y - 4.0, 210.0, 40.0), Color(0.05, 0.07, 0.12, 0.85))
	draw_rect(Rect2(x - 4.0, y - 4.0, 210.0, 40.0), Color(0.5, 0.2, 0.2, 0.9), false, 1.5)
	var status_txt: String = "ROUTED" if _rout.is_fleet_routed(1) else "%d/%d ships" % [alive_enemies, total_enemies]
	var status_col: Color = Color(0.95, 0.75, 0.2, 0.95) if _rout.is_fleet_routed(1) else Color(1.0, 0.5, 0.4, 0.95)
	draw_string(font, Vector2(x, y + 10.0), "Enemy Fleet: %s" % status_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, status_col)
	if not _rout.is_fleet_routed(1):
		draw_string(font, Vector2(x, y + 24.0), "Rout at: %d remaining" % elim_threshold, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.6, 0.55, 0.8))
	else:
		draw_string(font, Vector2(x, y + 24.0), "Fleeing the battle!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.8, 0.3, 0.85))

	if multiplayer.has_multiplayer_peer() and GameManager != null:
		var my_id: int = multiplayer.get_unique_id()
		var ally_lines: PackedStringArray = []
		for pid in GameManager.players.keys():
			var ipid: int = int(pid)
			if ipid == my_id:
				continue
			if not _remote_fleet_orders.has(ipid):
				continue
			var uname: String = str(GameManager.players[pid].get("username", "Player"))
			var oid: int = int(_remote_fleet_orders[ipid])
			var oname: String = _WingmanController.ORDER_NAMES[oid] if oid >= 0 and oid < _WingmanController.ORDER_COUNT else "?"
			ally_lines.append("%s: %s" % [uname, oname])
		if not ally_lines.is_empty():
			var ay: float = y + 44.0
			draw_string(font, Vector2(x, ay), "Allies — fleet order:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.75, 0.95, 0.85))
			for li in range(ally_lines.size()):
				draw_string(font, Vector2(x, ay + 12.0 + float(li) * 12.0), ally_lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.82, 0.98, 0.9))
