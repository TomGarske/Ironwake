extends Node2D

## Isometric arena — placeholder art, up to 4 players.
##
## Controls (every player, on their own machine):
##   Arrow keys: move · Space: attack · Escape: main menu

# ── Isometric constants ────────────────────────────────────────────────────────
const TILE_W        := 64.0   # diamond width in screen pixels
const TILE_H        := 32.0   # diamond height in screen pixels
const CHUNK_SIZE    := 16     # tiles per chunk side
const RENDER_MARGIN := 2      # extra tile buffer outside visible screen edge

# ── Palette ───────────────────────────────────────────────────────────────────
const _C_SKY := Color(0.06, 0.07, 0.12)

# ── Terrain types ─────────────────────────────────────────────────────────────
const T_DEEP   := 0   # deep ocean
const T_WATER  := 1   # shallow water
const T_SAND   := 2   # beach / desert
const T_GRASS  := 3   # grassland
const T_FOREST := 4   # forest
const T_MTN    := 5   # mountain
const T_SNOW   := 6   # snow peak

# [face color, south-edge shadow] per terrain type
const _TC: Array = [
	[Color(0.05, 0.12, 0.44), Color(0.02, 0.06, 0.26)],  # deep water
	[Color(0.12, 0.28, 0.68), Color(0.07, 0.16, 0.42)],  # shallow water
	[Color(0.74, 0.68, 0.46), Color(0.46, 0.40, 0.24)],  # sand
	[Color(0.22, 0.50, 0.16), Color(0.10, 0.26, 0.07)],  # grass
	[Color(0.10, 0.30, 0.10), Color(0.05, 0.16, 0.05)],  # forest
	[Color(0.48, 0.46, 0.42), Color(0.26, 0.24, 0.20)],  # mountain
	[Color(0.82, 0.84, 0.88), Color(0.58, 0.60, 0.64)],  # snow
]

# Player palettes — [primary, highlight]
const _PALETTES: Array = [
	[Color(0.22, 0.46, 1.00), Color(0.65, 0.82, 1.00)],  # blue
	[Color(1.00, 0.18, 0.12), Color(1.00, 0.58, 0.42)],  # red
	[Color(0.14, 0.76, 0.32), Color(0.52, 1.00, 0.60)],  # green
	[Color(0.92, 0.72, 0.06), Color(1.00, 0.92, 0.44)],  # gold
]

# ── Physics / combat ──────────────────────────────────────────────────────────
const SPEED      := 5.0    # world units / sec
const ATK_DUR    := 0.45
const HIT_START  := 0.30
const HIT_END    := 0.72
const ATK_RANGE  := 1.9    # world units
const DMG        := 25.0
const MAX_HP     := 100.0
const END_DELAY  := 3.0

# ── Input (single shared set — each peer only controls their own character) ────
const _KEYS    := {l = KEY_LEFT, r = KEY_RIGHT, u = KEY_UP, d = KEY_DOWN, a = KEY_SPACE}
const _ACTIONS := {left = "ia_l", right = "ia_r", up = "ia_u", down = "ia_d", atk = "ia_a"}

# ── State ─────────────────────────────────────────────────────────────────────
var _players:   Array = []
var _my_index:  int   = 0    # which player in _players this peer controls
var _winner:    int   = -2   # -2 = playing, -1 = draw, 0+ = index of winner
var _end_timer: float = 0.0
var _origin:    Vector2      # screen position of world (0, 0) — updated each draw

# ── World / chunk state ───────────────────────────────────────────────────────
## Chunk map: Vector2i(cx, cy) → PackedByteArray of CHUNK_SIZE*CHUNK_SIZE terrain types.
## All peers generate the same terrain from the shared seed via _init_world_seed RPC.
var _chunks:     Dictionary    = {}
var _elev_noise: FastNoiseLite = null
var _warp_noise: FastNoiseLite = null
var _moist_noise: FastNoiseLite = null

# ── Spawn positions (world units) ─────────────────────────────────────────────
const _SPAWNS: Array = [
	Vector2(2.0,  2.0),
	Vector2(10.0, 10.0),
	Vector2(10.0,  2.0),
	Vector2(2.0,  10.0),
]

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_register_inputs()
	_origin = get_viewport_rect().size * 0.5
	_spawn_players()
	if multiplayer.has_multiplayer_peer():
		# Host picks the seed and broadcasts it; clients wait for the RPC.
		if multiplayer.is_server():
			_init_world_seed.rpc(randi())
	else:
		_init_world_seed(randi())   # offline: generate immediately
	queue_redraw()

# ── World seed — RPC ensures every peer uses the same noise ───────────────────
@rpc("authority", "call_local", "reliable")
func _init_world_seed(seed_val: int) -> void:
	_elev_noise = FastNoiseLite.new()
	_elev_noise.seed               = seed_val
	_elev_noise.noise_type         = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elev_noise.frequency          = 0.06
	_elev_noise.fractal_type       = FastNoiseLite.FRACTAL_FBM
	_elev_noise.fractal_octaves    = 5
	_elev_noise.fractal_lacunarity = 2.0
	_elev_noise.fractal_gain       = 0.50

	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed       = seed_val + 1
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp_noise.frequency  = 0.12

	_moist_noise = FastNoiseLite.new()
	_moist_noise.seed       = seed_val + 2
	_moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moist_noise.frequency  = 0.09

	_chunks.clear()
	queue_redraw()

# ── Chunk generation ──────────────────────────────────────────────────────────
func _ensure_chunk(cx: int, cy: int) -> void:
	var key := Vector2i(cx, cy)
	if _chunks.has(key) or _elev_noise == null:
		return

	# Sample a 1-tile-padded region so CA smoothing has correct border values.
	const PAD := 1
	const SZ  := CHUNK_SIZE + 2 * PAD
	var raw: Array = []
	for i in range(SZ):
		raw.append([])
		for j in range(SZ):
			var wx: float = float(cx * CHUNK_SIZE + i - PAD)
			var wy: float = float(cy * CHUNK_SIZE + j - PAD)
			var dwx: float = wx + _warp_noise.get_noise_2d(wx, wy) * 4.0
			var dwy: float = wy + _warp_noise.get_noise_2d(wx + 100.0, wy + 100.0) * 4.0
			raw[i].append(_elev_noise.get_noise_2d(dwx, dwy))

	# Two-pass cellular automata smoothing
	for _pass in range(2):
		var sm: Array = []
		for i in range(SZ):
			sm.append([])
			for j in range(SZ):
				var sum: float = 0.0
				var cnt: int   = 0
				for oi in range(-1, 2):
					for oj in range(-1, 2):
						var ni: int = i + oi
						var nj: int = j + oj
						if ni >= 0 and ni < SZ and nj >= 0 and nj < SZ:
							var w: float = 0.5 if (oi != 0 and oj != 0) else 1.0
							sum += float(raw[ni][nj]) * w
							cnt += 1 if oi == 0 or oj == 0 else 0
				sm[i].append(sum / float(maxi(cnt, 1)))
		raw = sm

	# Classify the inner CHUNK_SIZE × CHUNK_SIZE tiles and store as bytes
	var data := PackedByteArray()
	data.resize(CHUNK_SIZE * CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		for j in range(CHUNK_SIZE):
			var e: float = float(raw[i + PAD][j + PAD])
			var wx: float = float(cx * CHUNK_SIZE + i)
			var wy: float = float(cy * CHUNK_SIZE + j)
			var m: float = _moist_noise.get_noise_2d(wx, wy)
			var t: int
			if   e < -0.30: t = T_DEEP
			elif e < -0.05: t = T_WATER
			elif e <  0.10: t = T_SAND
			elif e <  0.35: t = T_FOREST if m > 0.10 else T_GRASS
			elif e <  0.55: t = T_MTN
			else:            t = T_SNOW
			data[i * CHUNK_SIZE + j] = t
	_chunks[key] = data

func _get_tile(tx: int, ty: int) -> int:
	var cx: int = floori(float(tx) / CHUNK_SIZE)
	var cy: int = floori(float(ty) / CHUNK_SIZE)
	_ensure_chunk(cx, cy)
	var key := Vector2i(cx, cy)
	if not _chunks.has(key):
		return T_GRASS   # noise not ready yet (client waiting for seed RPC)
	var lx: int = tx - cx * CHUNK_SIZE
	var ly: int = ty - cy * CHUNK_SIZE
	return _chunks[key][lx * CHUNK_SIZE + ly]

# ── Coordinate helpers ────────────────────────────────────────────────────────
func _w2s(wx: float, wy: float) -> Vector2:
	return _origin + Vector2((wx - wy) * TILE_W * 0.5, (wx + wy) * TILE_H * 0.5)

## Convert a world-space direction vector to a normalised screen-space direction.
func _dir_screen(dx: float, dy: float) -> Vector2:
	var v := Vector2((dx - dy) * TILE_W * 0.5, (dx + dy) * TILE_H * 0.5)
	return v.normalized() if v.length_squared() > 0.001 else Vector2.DOWN

# ── Input registration ────────────────────────────────────────────────────────
func _register_inputs() -> void:
	var pairs := {
		_ACTIONS.left:  _KEYS.l,
		_ACTIONS.right: _KEYS.r,
		_ACTIONS.up:    _KEYS.u,
		_ACTIONS.down:  _KEYS.d,
		_ACTIONS.atk:   _KEYS.a,
	}
	for action: String in pairs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.keycode = pairs[action]
		InputMap.action_add_event(action, ev)

# ── Player spawning ───────────────────────────────────────────────────────────
func _spawn_players() -> void:
	var peer_ids: Array[int] = []
	var labels: Array[String] = []

	# Build roster from active multiplayer peer IDs so every client resolves
	# ownership the same way, even if GameManager player metadata lags behind.
	if multiplayer.has_multiplayer_peer():
		peer_ids.append(multiplayer.get_unique_id())
		peer_ids.append_array(multiplayer.get_peers())
		peer_ids.sort()
		for pid in peer_ids:
			var fallback_name: String = "Player %d" % pid
			if GameManager.players.has(pid):
				labels.append(str(GameManager.players[pid].get("username", fallback_name)))
			else:
				labels.append(fallback_name)
	else:
		# Offline: two placeholder slots; this peer controls index 0
		peer_ids = [1, 2]
		labels   = ["P1", "P2"]

	var count: int = mini(peer_ids.size(), _PALETTES.size())
	var my_peer_id: int = multiplayer.get_unique_id()
	_my_index = 0
	for i in range(count):
		if peer_ids[i] == my_peer_id:
			_my_index = i
			break

	for i in range(count):
		var start: Vector2 = _SPAWNS[i]
		_players.append({
			peer_id    = peer_ids[i],
			wx         = start.x,
			wy         = start.y,
			dir        = Vector2(1.0, 0.0) if i == 0 else Vector2(-1.0, 0.0),
			health     = MAX_HP,
			alive      = true,
			atk_time   = 0.0,
			hit_landed = false,
			palette    = _PALETTES[i],
			label      = labels[i],
			walk_time  = 0.0,
			moving     = false,
		})

# ── Game loop ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	if _winner != -2:
		_end_timer += delta
		if _end_timer >= END_DELAY:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		queue_redraw()
		return

	# Only tick and send input for the character this peer owns
	_tick_player(_players[_my_index], delta)
	_broadcast_my_state()
	_resolve_collisions()
	for i in range(_players.size()):
		for j in range(_players.size()):
			if i != j:
				_check_hit(_players[i], _players[j])
	_check_win()
	queue_redraw()

# ── Per-player update (local peer only) ───────────────────────────────────────
func _tick_player(p: Dictionary, delta: float) -> void:
	if not p.alive:
		return

	var move := Vector2.ZERO
	if Input.is_action_pressed(_ACTIONS.left):  move.x -= 1.0
	if Input.is_action_pressed(_ACTIONS.right): move.x += 1.0
	if Input.is_action_pressed(_ACTIONS.up):    move.y -= 1.0
	if Input.is_action_pressed(_ACTIONS.down):  move.y += 1.0

	if move.length_squared() > 0.0:
		move         = move.normalized()
		p.wx        += move.x * SPEED * delta
		p.wy        += move.y * SPEED * delta
		p.dir        = move
		p.moving     = true
		p.walk_time += delta
	else:
		p.moving = false

	if Input.is_action_just_pressed(_ACTIONS.atk) and p.atk_time <= 0.0:
		p.atk_time   = ATK_DUR
		p.hit_landed = false
	p.atk_time = maxf(p.atk_time - delta, 0.0)

# ── State broadcast ────────────────────────────────────────────────────────────
func _broadcast_my_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var p: Dictionary = _players[_my_index]
	_receive_player_state.rpc(
		int(p.peer_id),
		float(p.wx), float(p.wy),
		float(p.dir.x), float(p.dir.y),
		float(p.atk_time), float(p.health),
		bool(p.alive), bool(p.moving), float(p.walk_time)
	)

@rpc("any_peer", "unreliable")
func _receive_player_state(
		peer_id: int,
		wx: float, wy: float,
		dir_x: float, dir_y: float,
		atk_time: float, health: float,
		alive: bool, moving: bool, walk_time: float) -> void:
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
	p.health    = health
	p.alive     = alive
	p.moving    = moving
	p.walk_time = walk_time

func _find_player_index_by_peer_id(peer_id: int) -> int:
	for i in range(_players.size()):
		if int(_players[i].get("peer_id", -1)) == peer_id:
			return i
	return -1

# ── Collision — keep players apart ────────────────────────────────────────────
func _resolve_collisions() -> void:
	const MIN_DIST := 0.85
	for i in range(_players.size()):
		for j in range(i + 1, _players.size()):
			var p_i: Dictionary = _players[i]
			var p_j: Dictionary = _players[j]
			var dx: float = float(p_j.wx) - float(p_i.wx)
			var dy: float = float(p_j.wy) - float(p_i.wy)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < MIN_DIST and dist > 0.001:
				var push: float = (MIN_DIST - dist) * 0.5
				var nx: float = dx / dist
				var ny: float = dy / dist
				p_i.wx = float(p_i.wx) - nx * push
				p_i.wy = float(p_i.wy) - ny * push
				p_j.wx = float(p_j.wx) + nx * push
				p_j.wy = float(p_j.wy) + ny * push

# ── Hit detection ─────────────────────────────────────────────────────────────
func _check_hit(attacker: Dictionary, defender: Dictionary) -> void:
	if not attacker.alive or attacker.atk_time <= 0.0 or attacker.hit_landed:
		return
	if not defender.alive:
		return
	var phase: float = 1.0 - attacker.atk_time / ATK_DUR
	if phase < HIT_START or phase > HIT_END:
		return
	var dx: float = defender.wx - attacker.wx
	var dy: float = defender.wy - attacker.wy
	var dist := sqrt(dx * dx + dy * dy)
	if dist > ATK_RANGE:
		return
	if attacker.dir.dot(Vector2(dx, dy).normalized()) < 0.25:
		return
	attacker.hit_landed = true
	defender.health = maxf(defender.health - DMG, 0.0)
	if defender.health <= 0.0:
		defender.alive = false

# ── Win condition ─────────────────────────────────────────────────────────────
func _check_win() -> void:
	if _winner != -2:
		return
	var alive_count := 0
	var last_alive  := -1
	for i in range(_players.size()):
		if _players[i].alive:
			alive_count += 1
			last_alive   = i
	if alive_count == 0:
		_winner = -1
	elif alive_count == 1:
		_winner = last_alive

# ── Draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size

	# Camera: keep the local player centred on screen every frame
	var me: Dictionary = _players[_my_index]
	_origin = vp * 0.5 - Vector2((me.wx - me.wy) * TILE_W * 0.5, (me.wx + me.wy) * TILE_H * 0.5)

	draw_rect(Rect2(Vector2.ZERO, vp), _C_SKY)
	_draw_tiles(vp)

	# Y-sort: players with lower (wx+wy) are further from camera — draw first
	var sorted := _players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.wx + a.wy) < (b.wx + b.wy))
	for p in sorted:
		_draw_player(p)

	_draw_hud(vp)
	if _winner != -2:
		_draw_win_screen(vp)

# ── Tile drawing ──────────────────────────────────────────────────────────────
func _draw_tiles(vp: Vector2) -> void:
	# Inverse-project the four screen corners into tile space to find the exact
	# range of tiles that can be visible.  Avoids drawing off-screen tiles.
	# screen = _origin + Vector2((tx-ty)*hw, (tx+ty)*hh)
	# → u = tx-ty = (screen.x - _origin.x) / hw
	# → v = tx+ty = (screen.y - _origin.y) / hh
	# → tx = (u+v)/2   ty = (v-u)/2
	var hw := TILE_W * 0.5
	var hh := TILE_H * 0.5
	var tx_min := 999999
	var tx_max := -999999
	var ty_min := 999999
	var ty_max := -999999
	for corner in [Vector2.ZERO, Vector2(vp.x, 0.0), Vector2(0.0, vp.y), vp]:
		var u: float = (corner.x - _origin.x) / hw
		var v: float = (corner.y - _origin.y) / hh
		tx_min = mini(tx_min, floori((u + v) * 0.5) - RENDER_MARGIN)
		tx_max = maxi(tx_max, ceili((u + v) * 0.5) + RENDER_MARGIN)
		ty_min = mini(ty_min, floori((v - u) * 0.5) - RENDER_MARGIN)
		ty_max = maxi(ty_max, ceili((v - u) * 0.5) + RENDER_MARGIN)

	# Pre-generate all chunks that overlap the visible tile range
	var cx_min: int = floori(float(tx_min) / CHUNK_SIZE)
	var cx_max: int = ceili(float(tx_max)  / CHUNK_SIZE)
	var cy_min: int = floori(float(ty_min) / CHUNK_SIZE)
	var cy_max: int = ceili(float(ty_max)  / CHUNK_SIZE)
	for cx in range(cx_min, cx_max + 1):
		for cy in range(cy_min, cy_max + 1):
			_ensure_chunk(cx, cy)

	# Draw in diagonal order for correct painter's-algorithm depth
	var d_min: int = tx_min + ty_min
	var d_max: int = tx_max + ty_max
	for diag in range(d_min, d_max + 1):
		var tx_lo: int = maxi(tx_min, diag - ty_max)
		var tx_hi: int = mini(tx_max, diag - ty_min)
		for tx in range(tx_lo, tx_hi + 1):
			_draw_tile(tx, diag - tx)

func _draw_tile(tx: int, ty: int) -> void:
	var top := _w2s(tx + 0.5, float(ty))
	var rgt := _w2s(float(tx + 1), ty + 0.5)
	var bot := _w2s(tx + 0.5, float(ty + 1))
	var lft := _w2s(float(tx), ty + 0.5)

	var tt: int   = _get_tile(tx, ty)
	var tc: Array = _TC[tt]
	var face: Color
	if tt == T_DEEP or tt == T_WATER:
		face = tc[0].lightened(0.06) if (tx + ty) % 2 == 0 else tc[0]
	elif tt == T_GRASS or tt == T_FOREST:
		face = tc[0] if (tx + ty) % 2 == 0 else tc[0].lightened(0.04)
	else:
		face = tc[0]

	draw_polygon(PackedVector2Array([top, rgt, bot, lft]), PackedColorArray([face]))
	draw_line(lft, bot, tc[1], 1.2)
	draw_line(rgt, bot, tc[1], 1.2)

# ── Character drawing ─────────────────────────────────────────────────────────
func _draw_player(p: Dictionary) -> void:
	var sp := _w2s(p.wx, p.wy)
	var pa: Color = p.palette[0]
	var pb: Color = p.palette[1]
	var dim := Color(pa.r * 0.45, pa.g * 0.45, pa.b * 0.45)

	# Ground shadow — squashed circle
	draw_set_transform(sp + Vector2(0.0, 3.0), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, 15.0, Color(0.0, 0.0, 0.0, 0.40))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not p.alive:
		draw_line(sp + Vector2(-9.0, -9.0), sp + Vector2(9.0, 9.0), Color(0.7, 0.1, 0.1, 0.9), 3.5)
		draw_line(sp + Vector2(9.0, -9.0),  sp + Vector2(-9.0, 9.0), Color(0.7, 0.1, 0.1, 0.9), 3.5)
		return

	# Walk bob
	var bob: float = sin(p.walk_time * 9.0) * 3.5 if p.moving else 0.0

	# Legs
	draw_rect(Rect2(sp.x - 8.0, sp.y - 18.0 + bob,  7.0, 18.0), dim)
	draw_rect(Rect2(sp.x + 1.0, sp.y - 18.0 - bob,  7.0, 18.0), dim)

	# Body
	draw_rect(Rect2(sp.x - 9.0, sp.y - 42.0, 18.0, 26.0), pa)
	# Body shading
	draw_rect(Rect2(sp.x - 9.0, sp.y - 42.0,  4.0, 26.0), pb)   # left highlight
	draw_rect(Rect2(sp.x - 9.0, sp.y - 42.0, 18.0,  3.0), pb)   # top highlight
	draw_rect(Rect2(sp.x + 5.0, sp.y - 19.0,  4.0,  3.0), pb)   # belt detail

	# Head
	draw_circle(sp + Vector2(0.0, -51.0), 10.0, pb)
	draw_circle(sp + Vector2(0.0, -51.0), 10.0, Color(0.0, 0.0, 0.0, 0.18), false, 1.5)
	# Face dot (shows which direction player faces)
	var fwd := _dir_screen(p.dir.x, p.dir.y) * 4.5
	draw_circle(sp + Vector2(fwd.x, -51.0 + fwd.y * 0.5), 2.5, Color(0.0, 0.0, 0.0, 0.35))

	# Weapon / attack
	if p.atk_time > 0.0:
		var t: float = 1.0 - float(p.atk_time) / ATK_DUR
		var ds   := _dir_screen(p.dir.x, p.dir.y)
		var perp := Vector2(-ds.y, ds.x)
		var angle: float = lerp(-0.9, 0.9, t)
		var arm  := sp + ds * 9.0 + Vector2(0.0, -32.0)
		var tip  := arm + (ds * cos(angle) + perp * sin(angle)) * 30.0
		# Weapon trail
		var trail := arm + (ds * cos(angle * 0.5) + perp * sin(angle * 0.5)) * 22.0
		draw_line(arm, trail, Color(pa.r, pa.g, pa.b, 0.30), 8.0)
		# Blade
		draw_line(arm, tip, Color(0.65, 0.60, 0.22), 3.5)
		draw_circle(tip, 3.5, Color(0.88, 0.82, 0.30))
	else:
		# Idle arm stubs
		var ds := _dir_screen(p.dir.x, p.dir.y)
		draw_line(sp + Vector2(0.0, -38.0),
				  sp + Vector2(0.0, -38.0) + ds * 8.0 + Vector2(0.0, 4.0),
				  dim, 5.0)

	# Name tag above head
	var font := ThemeDB.fallback_font
	draw_string(font, sp + Vector2(0.0, -66.0), p.label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 1.0, 1.0, 0.88))

# ── HUD ───────────────────────────────────────────────────────────────────────
func _draw_hud(vp: Vector2) -> void:
	var font    := ThemeDB.fallback_font
	var bar_h   := 20.0
	var bar_w   := minf(vp.x * 0.20, 200.0)
	var pad     := 14.0
	var spacing := bar_w + pad

	for i in range(_players.size()):
		var p: Dictionary = _players[i]
		var bx := pad + i * spacing
		var by := pad
		var fill := bar_w * clampf(p.health / MAX_HP, 0.0, 1.0)
		var col: Color = p.palette[0]

		# Background
		draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.08, 0.08, 0.08, 0.85))
		# Fill
		if p.alive and fill > 0.0:
			draw_rect(Rect2(bx, by, fill, bar_h), col)
		# Border
		draw_rect(Rect2(bx, by, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.55), false, 1.5)
		# Label
		draw_string(font, Vector2(bx + 5.0, by + bar_h - 5.0),
				"%s  %d" % [p.label, int(maxf(p.health, 0.0))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_win_screen(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.58))
	var font := ThemeDB.fallback_font
	var cx   := vp.x * 0.5
	var cy   := vp.y * 0.44

	var msg: String
	if _winner == -1:
		msg = "DRAW!"
	else:
		msg = "%s WINS!" % _players[_winner].label

	draw_string(font, Vector2(cx, cy), msg,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 52, Color(1.0, 0.88, 0.12))

	var remaining := ceili(END_DELAY - _end_timer)
	draw_string(font, Vector2(cx, cy + 62.0),
			"Returning to menu in %d..." % remaining,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(0.8, 0.8, 0.8))
