class_name IronwakeRamming
extends RefCounted
## Ramming (ship-to-ship collision) system extracted from IronwakeArena.
##
## Usage:
##   var ramming := IronwakeRamming.new()
##   ramming.init(self)          # pass the arena node
##   # Each physics tick on the server:
##   ramming.tick_ramming(delta)

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

# ---------------------------------------------------------------------------
# RAM constants
# ---------------------------------------------------------------------------

## Minimum closing speed (m/s) before any damage is applied.
const RAM_MIN_SPEED: float = 3.0
## Damage per m/s of closing velocity above the threshold.
## At 10 m/s closing speed: (10-3) * 0.49 ~ 3.4 hull hits to the target.
const RAM_DAMAGE_PER_MPS: float = 0.49
## The rammer takes this fraction of the damage they deal (reinforced bow).
const RAM_ATTACKER_DAMAGE_FRACTION: float = 0.25
## Bow/stern take half damage -- reinforced structure, ram beak at prow.
const RAM_BOW_STERN_DAMAGE_MULT: float = 0.5
## Speed bled from each ship on impact, proportional to closing velocity.
const RAM_SPEED_LOSS_MULT: float = 0.6
## Minimum time between collision checks for the same pair (prevents double-tick damage).
const RAM_COOLDOWN_SEC: float = 1.5
## Overlap distance (m) below which hulls are considered colliding.
## Ships have an elliptical footprint; this is the sum-of-radii threshold in the
## approach direction. Checked against the average half-width for side-on collisions.
const RAM_COLLISION_DIST: float = 12.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var arena: Node = null
var ram_cooldowns: Dictionary = {}

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

func init(arena_node: Node) -> void:
	arena = arena_node

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func tick_ramming(delta: float) -> void:
	# Decay cooldown timers.
	for key in ram_cooldowns.keys():
		ram_cooldowns[key] = maxf(0.0, float(ram_cooldowns[key]) - delta)
		if ram_cooldowns[key] <= 0.0:
			ram_cooldowns.erase(key)

	var players: Array = arena._players
	var n: int = players.size()
	if n < 2:
		return

	for i in range(n):
		var a: Dictionary = players[i]
		if not bool(a.get("alive", true)):
			continue
		for j in range(i + 1, n):
			var b: Dictionary = players[j]
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

			# Ellipse overlap check: each ship occupies an ellipse LENGTH x WIDTH.
			# Project the half-extents of each ship along the collision normal.
			var a_hull: Vector2 = Vector2(float(a.dir.x), float(a.dir.y)).normalized()
			var b_hull: Vector2 = Vector2(float(b.dir.x), float(b.dir.y)).normalized()
			var col_n: Vector2 = Vector2(nx, ny)

			# Ellipse half-extent along collision normal (Lame approximation).
			var a_fwd_dot: float = absf(a_hull.dot(col_n))
			var b_fwd_dot: float = absf(b_hull.dot(col_n))
			var a_half: float = lerpf(float(a.get("ship_width", NC.SHIP_WIDTH_UNITS)) * 0.5, float(a.get("ship_length", NC.SHIP_LENGTH_UNITS)) * 0.5, a_fwd_dot)
			var b_half: float = lerpf(float(b.get("ship_width", NC.SHIP_WIDTH_UNITS)) * 0.5, float(b.get("ship_length", NC.SHIP_LENGTH_UNITS)) * 0.5, b_fwd_dot)
			var threshold: float = a_half + b_half
			if dist > threshold:
				continue

			# Cooldown check.
			var pair_key: String = "%d_%d" % [i, j]
			if ram_cooldowns.get(pair_key, 0.0) > 0.0:
				continue
			ram_cooldowns[pair_key] = RAM_COOLDOWN_SEC

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

			# Asymmetric damage: the ship being rammed takes full damage,
			# the rammer takes a fraction. The "rammer" is whoever contributes
			# more closing velocity (i.e. is charging in faster).
			var a_share: float = maxf(0.0, a_vel_n) / maxf(0.001, closing)  # A's fraction of closing speed
			var b_share: float = maxf(0.0, b_vel_n) / maxf(0.001, closing)  # B's fraction

			# A takes damage from B's charge; B takes damage from A's charge.
			# The one doing the ramming (higher share) deals more but takes less.
			var a_receive: float = b_share + a_share * RAM_ATTACKER_DAMAGE_FRACTION
			var b_receive: float = a_share + b_share * RAM_ATTACKER_DAMAGE_FRACTION

			# Angle of impact on each hull -- bow/stern = half damage, beam = full.
			var a_bow_factor: float = absf(a_hull.dot(col_n))   # 1.0 = pure bow/stern, 0.0 = pure beam
			var b_bow_factor: float = absf(b_hull.dot(col_n))
			var a_mult: float = lerpf(1.0, RAM_BOW_STERN_DAMAGE_MULT, a_bow_factor)
			var b_mult: float = lerpf(1.0, RAM_BOW_STERN_DAMAGE_MULT, b_bow_factor)

			# Apply damage -- server authoritative; clients only see visual FX.
			var dmg_a: float = base_damage * a_receive * a_mult
			var dmg_b: float = base_damage * b_receive * b_mult
			if not arena.multiplayer.has_multiplayer_peer() or arena.multiplayer.is_server():
				apply_ram_damage(a, dmg_a, i, j)
				apply_ram_damage(b, dmg_b, j, i)
				if arena.multiplayer.has_multiplayer_peer():
					arena._rpc_apply_ram_damage.rpc(i, dmg_a, j, dmg_b)

			# Speed loss -- both ships lose momentum proportional to closing velocity.
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
			arena._splash_fx.append({"wx": cx, "wy": cy, "t": 0.0})



func apply_ram_damage(p: Dictionary, damage: float, idx: int, other_idx: int = -1) -> void:
	if not bool(p.get("alive", true)):
		return
	var new_health: float = maxf(float(p.health) - damage, 0.0)
	p.health = new_health
	# Ramming damages the helm -- collision shocks the tiller and rudder post.
	var helm_obj: Variant = p.get("helm")
	if helm_obj != null and damage > 0.5:
		helm_obj.apply_hit()
	# Ramming causes flooding — hull breach at the waterline.
	var ram_dmg_state: Variant = p.get("damage_state")
	if ram_dmg_state != null:
		ram_dmg_state.on_ram_hit()
	# Scoreboard: track ramming damage.
	var def_pid: int = int(p.get("peer_id", 0))
	if arena._scoreboard.has(def_pid):
		arena._scoreboard[def_pid]["damage_taken"] += damage
	if other_idx >= 0 and other_idx < arena._players.size():
		var atk_pid: int = int(arena._players[other_idx].get("peer_id", 0))
		if arena._scoreboard.has(atk_pid):
			arena._scoreboard[atk_pid]["damage_dealt"] += damage
	if new_health <= 0.0:
		p.alive = false
		p["respawn_timer"] = arena.RESPAWN_DELAY_SEC
		# Scoreboard: track ram kill/death.
		if arena._scoreboard.has(def_pid):
			arena._scoreboard[def_pid]["deaths"] += 1
		if other_idx >= 0 and other_idx < arena._players.size():
			var atk_pid2: int = int(arena._players[other_idx].get("peer_id", 0))
			if arena._scoreboard.has(atk_pid2):
				arena._scoreboard[atk_pid2]["kills"] += 1
		if bool(p.get("is_bot", false)):
			var bc: Variant = arena._get_bot_controller_for_index(idx)
			if bc != null:
				bc.notify_cannon_hit(-1)
	arena._hull_strike_fx.append({
		"wx": float(p.wx), "wy": float(p.wy),
		"h": NC.SHIP_DECK_HEIGHT_UNITS,
		"t": 0.0,
	})
	arena._sound.play_cannon_hit_sound()
	if not arena.multiplayer.has_multiplayer_peer() or arena.multiplayer.is_server():
		arena._check_win()
