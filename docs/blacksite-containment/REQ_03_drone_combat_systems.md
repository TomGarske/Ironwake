# REQ_03: Drone Combat Systems
**Abilities, Damage, and Resource Management**

## Overview

Drones have four core combat abilities plus a heat/energy system. All abilities are balance-tested for 1–4 player baseline (scaled up for higher player counts). Damage calculations are server-authoritative; clients show immediate feedback but the host validates hit and applies damage.

## Ability 1: Directional Charge Laser

**Purpose**: Primary sustained-damage tool; requires prediction and positioning.

**Input**: Hold Right Trigger (RT) to charge; release to fire. Holding beyond full charge triggers overheat penalty.

**Charge Mechanics**:
- **Charge Time**: 1.0 second to full charge from release
- **Charge Levels**:
  - 0–0.33s: Weak (25% damage)
  - 0.33–0.67s: Medium (65% damage)
  - 0.67–1.0s: Full (100% damage)
  - >1.0s: **Overheat threshold** (automatic fire/release, 2-second cooldown penalty begins)

**Firing**:
- **Type**: Hitscan beam fired in drone's facing direction (controlled by right stick aim)
- **Range**: 50 meters (tunable per balance pass)
- **Width**: 1-meter diameter cylinder (generous hit detection)
- **Damage per Shot**:
  - Weak hit: 25 damage
  - Medium hit: 65 damage
  - Full hit: 100 damage
  - Critical (hit in 0.1-second window of release): 125 damage
- **Fire Rate**: Can fire once per charge cycle; no automatic repeating unless held through overheat
- **Damage Type**: "laser" (escapees may have resistances; see escapee definitions in REQ_06)

**Visual Feedback**:
- **Charging**: Drone cockpit glow increases; laser barrel glows bright cyan
- **Full Charge**: Bright flash, ready-to-fire indicator on HUD (green dot)
- **Fire**: Cyan beam trails across screen with impact bloom at target
- **Overheat**: Red warning glow; overheat gauge visible on HUD, fills to red during hold

**Audio Feedback**:
- **Charging Hum**: Increasing pitch, crescendos at full charge
- **Fire**: Sharp laser snap/zap sound
- **Overheat**: Warning beep, then harsh alarm if release triggers overheat penalty

**Overheat System**:
- If held beyond 1.0s, the charge laser **automatically fires** (full damage) and enters a 2-second cooldown.
- During cooldown, RT input is ignored; charge laser unavailable.
- HUD shows cooldown timer counting down.
- Overheat count (for statistics) increments; multiple overheats may indicate skill issue or panic (used for telemetry).

**Server Implementation**:
```gdscript
# DroneAbilityManager.gd (excerpt)
class_name DroneAbilityManager
extends Node

var charge_start_time: float = -1.0
var is_overheat_cooldown: bool = false
var overheat_cooldown_remaining: float = 0.0
const CHARGE_TIME: float = 1.0
const OVERHEAT_COOLDOWN: float = 2.0
const LASER_RANGE: float = 50.0
const LASER_DAMAGE_FULL: float = 100.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_charge_laser"):
		charge_start_time = Time.get_ticks_msec() / 1000.0
	elif event.is_action_released("ability_charge_laser"):
		if is_overheat_cooldown:
			return
		var charge_duration = (Time.get_ticks_msec() / 1000.0) - charge_start_time
		if charge_duration > CHARGE_TIME:
			fire_laser_full()
			trigger_overheat()
		else:
			var charge_ratio = clamp(charge_duration / CHARGE_TIME, 0.0, 1.0)
			fire_laser(charge_ratio)

func fire_laser(charge_ratio: float) -> void:
	var damage = LASER_DAMAGE_FULL * charge_ratio
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		owner.global_position,
		owner.global_position + owner.global_transform.basis.z * LASER_RANGE
	)
	var result = space_state.intersect_ray(query)
	if result:
		var hit_node = result.collider
		if hit_node.is_in_group("escapee"):
			hit_node.take_damage(damage, "laser")
			rpc_unreliable("_damage_vfx", result.position)

@rpc("call_local")
func _damage_vfx(impact_pos: Vector3) -> void:
	# Instantiate beam and impact VFX
	pass

func trigger_overheat() -> void:
	is_overheat_cooldown = true
	overheat_cooldown_remaining = OVERHEAT_COOLDOWN
	emit_signal("overheat_triggered")

func _process(delta: float) -> void:
	if is_overheat_cooldown:
		overheat_cooldown_remaining -= delta
		if overheat_cooldown_remaining <= 0.0:
			is_overheat_cooldown = false
```

---

## Ability 2: Orbital Strike Call-in

**Purpose**: Tactical area-denial tool; requires coordinate input and timing; limited uses.

**Input**: Press Right Bumper (RB) to activate targeting mode.

**Targeting**:
- **Mode**: After RB press, drone enters targeting mode (movement allowed, other abilities disabled).
- **Reticle**: Large circular targeting reticle (8-meter radius, visible to all players) appears at drone's forward aim point, 10 meters ahead.
- **Adjustment**: Reticle follows drone movement; player can fine-tune aim via right stick.
- **Confirmation**: Press RB again to call strike at reticle center.

**Strike Behavior**:
- **Delay**: 2–3 seconds between call and impact (telegraphed to all players).
- **Impact Radius**: 8 meters diameter (full damage in center, falloff at edges).
- **Damage**: 200 damage in center, scales to 50 damage at edges (linear falloff).
- **Effect**: Targets all escapees in radius; ignores drone friendlies (no friendly fire).
- **Visual**: Incoming strike indicator (pulsing red zone) visible to all players during delay.

**Resource Limitation**:
- **Base Uses**: 2 uses per mission (resets on mission end).
- **Cooldown**: 20-second recharge per use (after impact, next strike available in 20s; stackable up to 2).
- **Alternative (if playtesting favors cooldown over charges)**: Single recharge on 30-second cooldown (choose one model at balance checkpoint).

**Visual Feedback**:
- **Targeting Mode**: HUD overlay shows reticle; right stick adjusts aim; RB button glows orange.
- **Called**: Targeting reticle blinks red and locks to ground plane.
- **Incoming**: Pulsing red zone expands from reticle; warning audio plays.
- **Impact**: Explosive bloom VFX, screen shake for all players, orange fire effect at impact point.

**Audio Feedback**:
- **Targeting Activate**: Soft beep; computer voice "Orbital strike ready".
- **Called**: Rising alarm tone; "Strike incoming in 3... 2... 1...".
- **Impact**: Heavy boom; all drones feel tactile rumble (if controller has haptics).

**Server Implementation**:
```gdscript
# DroneAbilityManager.gd (orbital strike excerpt)
var orbital_strike_uses: int = 2
var orbital_strike_cooldown_remaining: float = 0.0
var orbital_targeting_active: bool = false
var orbital_target_pos: Vector3 = Vector3.ZERO
const ORBITAL_STRIKE_COOLDOWN: float = 20.0
const ORBITAL_STRIKE_DELAY: float = 2.5
const ORBITAL_RADIUS: float = 8.0
const ORBITAL_CENTER_DAMAGE: float = 200.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_orbital_strike"):
		if orbital_strike_uses > 0 and orbital_strike_cooldown_remaining <= 0.0:
			if not orbital_targeting_active:
				orbital_targeting_active = true
				emit_signal("orbital_targeting_started")
			else:
				call_orbital_strike()
	elif event.is_action_released("ability_orbital_strike"):
		if orbital_targeting_active and not event.is_pressed():
			# Reticle continues tracking; awaiting confirmation
			pass

func call_orbital_strike() -> void:
	orbital_target_pos = owner.global_position + owner.global_transform.basis.z * 10.0
	orbital_targeting_active = false
	orbital_strike_uses -= 1
	orbital_strike_cooldown_remaining = ORBITAL_STRIKE_COOLDOWN
	rpc("_orbital_impact_delayed", orbital_target_pos)

@rpc("call_local")
func _orbital_impact_delayed(impact_pos: Vector3) -> void:
	await get_tree().create_timer(ORBITAL_STRIKE_DELAY).timeout
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D()
	query.shape = SphereShape3D.new()
	query.shape.radius = ORBITAL_RADIUS
	query.transform.origin = impact_pos
	var results = space_state.intersect_shape(query)
	for result in results:
		if result.collider.is_in_group("escapee"):
			var distance = impact_pos.distance_to(result.collider.global_position)
			var damage = lerp(ORBITAL_CENTER_DAMAGE, 50.0, distance / ORBITAL_RADIUS)
			result.collider.take_damage(damage, "orbital")
	rpc_unreliable("_orbital_vfx", impact_pos)

@rpc("call_local")
func _orbital_vfx(impact_pos: Vector3) -> void:
	# Explosion, screen shake, audio boom
	pass
```

---

## Ability 3: Burst Speed Maneuver

**Purpose**: Evasion, repositioning, and skill-based escapes; brief invincibility.

**Input**: Press Left Bumper (LB).

**Activation**:
- **Instant Boost**: Drone dashes in the direction of current movement input (or forward if no input).
- **Distance**: 15-meter dash in ~0.3 seconds (85 km/h equivalent).
- **Invincibility Window**: 0.3-second duration; drone cannot be hit during dash.
- **Interrupts Charge Laser**: If RT is held, charge laser release is canceled; must re-initiate charge after burst.

**Resource**:
- **Cooldown**: 8-second recharge (shared with framerate control energy pool; see below).

**Visual Feedback**:
- **Trail Effect**: Blue trailing particle effect along dash path.
- **Speed Glow**: Drone briefly brightens; motion blur effect.
- **HUD Indicator**: LB button highlights green during dash.

**Audio Feedback**:
- **Activation**: Sharp "whoosh" sound, increasing in pitch.
- **Landing**: Brief mechanical chime confirming invincibility end.

**Server Implementation**:
```gdscript
# DroneAbilityManager.gd (burst speed excerpt)
var burst_cooldown_remaining: float = 0.0
const BURST_DISTANCE: float = 15.0
const BURST_DURATION: float = 0.3
const BURST_COOLDOWN: float = 8.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_burst_speed"):
		if burst_cooldown_remaining <= 0.0:
			activate_burst()

func activate_burst() -> void:
	var direction = owner.velocity.normalized()
	if direction.length() < 0.1:
		direction = owner.global_transform.basis.z
	var target_pos = owner.global_position + direction * BURST_DISTANCE
	burst_cooldown_remaining = BURST_COOLDOWN
	owner.invincible = true
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(owner, "global_position", target_pos, BURST_DURATION)
	await tween.finished
	owner.invincible = false
	emit_signal("burst_complete")
	rpc_unreliable("_burst_vfx", owner.global_position)

@rpc("call_local")
func _burst_vfx(end_pos: Vector3) -> void:
	# Trail and landing effects
	pass
```

---

## Ability 4: Framerate Control (Bullet Time)

**Purpose**: Tactical slow-motion awareness; helps with dodging and precision; single-player perception shift.

**Input**: Press Left Trigger (LT) to activate.

**Effect**:
- **Time Scale**: Game time slows to 30% of normal (0.3x) for the activating drone's perception only.
- **Scope**: Only the drone player receives the slowdown effect on their local client. Other players see the drone move normally in real time (no desync; the drone's velocity is not actually changed, only the client's time scale).
- **Duration**: 5 seconds of subjective slow-motion time (equivalent to ~1.67 seconds real time).
- **Resource**: Consumes from shared energy pool (see Energy System below).

**Resource**:
- **Energy Pool**: 100 points shared across framerate control and orbital strike.
- **Framerate Control Cost**: 60 energy per activation.
- **Cooldown Between Uses**: 6 seconds (prevents spam).
- **Energy Regeneration**: +10 energy per second during normal patrol (passive regen).

**Visual Feedback**:
- **Activation**: Screen desaturates slightly (blue-shift for sci-fi effect); HUD flashes cyan.
- **Duration Indicator**: Circular countdown timer on HUD.
- **Other Drones**: Other players see the activating drone's effect glow (brief cyan pulse) but time is normal for them.

**Audio Feedback**:
- **Activation**: Electronic "whirr" sound, pitch lowers (matching time distortion).
- **During Effect**: Ambient audio slightly muffled, synth drones deepen.
- **Deactivation**: High-pitched "ping" as perception normalizes.

**Implementation Note**: This is a **client-side perception effect**. The server does not slow game time; the affected drone's client locally scales `Engine.time_scale` down and back up. All physics and movement remain synchronized via the network.

```gdscript
# DroneAbilityManager.gd (framerate control excerpt)
var energy: float = 100.0
var max_energy: float = 100.0
var framerate_control_cooldown_remaining: float = 0.0
const FRAMERATE_CONTROL_COST: float = 60.0
const FRAMERATE_CONTROL_DURATION: float = 5.0
const FRAMERATE_CONTROL_COOLDOWN: float = 6.0
const FRAMERATE_CONTROL_TIME_SCALE: float = 0.3
const ENERGY_REGEN_RATE: float = 10.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_framerate_control"):
		if energy >= FRAMERATE_CONTROL_COST and framerate_control_cooldown_remaining <= 0.0:
			activate_framerate_control()

func activate_framerate_control() -> void:
	energy -= FRAMERATE_CONTROL_COST
	framerate_control_cooldown_remaining = FRAMERATE_CONTROL_COOLDOWN
	if is_local_player:
		Engine.time_scale = FRAMERATE_CONTROL_TIME_SCALE
		await get_tree().create_timer(FRAMERATE_CONTROL_DURATION).timeout
		Engine.time_scale = 1.0
	rpc_unreliable("_framerate_control_vfx")

@rpc("call_local")
func _framerate_control_vfx() -> void:
	# Desaturation, cyan glow, synth audio
	pass

func _process(delta: float) -> void:
	# Regen energy passively
	if energy < max_energy:
		energy += ENERGY_REGEN_RATE * delta
		energy = clamp(energy, 0.0, max_energy)
	# Decrement cooldowns
	if burst_cooldown_remaining > 0.0:
		burst_cooldown_remaining -= delta
	if framerate_control_cooldown_remaining > 0.0:
		framerate_control_cooldown_remaining -= delta
	if orbital_strike_cooldown_remaining > 0.0:
		orbital_strike_cooldown_remaining -= delta
```

---

## Damage System

**Hit Registration**:
- **Authority**: Host validates all damage. Client sends `_request_damage(escapee_id, damage_amount, damage_type)` RPC; host checks line-of-sight, range, and escapee health.
- **Escapee Health**: Each escapee has a `health: float` and `max_health: float`.
- **Damage Application**: Host deducts damage from health; if health <= 0, escalate to death logic (see REQ_06).
- **Feedback**: Host broadcasts `_apply_damage_vfx(hit_position, damage_amount)` to all clients for audio-visual feedback.

**Damage Types**:
- `"laser"`: Hitscan beam damage (no splash, single target)
- `"orbital"`: Area damage (splash radius, can hit multiple escapees)
- Future: `"kinetic"` (collision), `"energy"` (special), etc.

**Escapee Resistances** (optional, per REQ_06 escapee type):
- Some escapees may have damage resistances (e.g., Tank escapees take 80% damage from laser, 100% from orbital).
- Define in escapee configuration JSON/resource.

**No Friendly Fire**: Laser and orbital strikes deal 0 damage to drones. Drones are immune.

---

## Energy System

Energy is a shared resource supporting orbital strike and framerate control.

| Resource | Max | Regen Rate | Costs |
|----------|-----|-----------|-------|
| Energy   | 100 | +10/sec   | Orbital Strike: 0 (uses charges instead); Framerate Control: 60 per use |

*Note*: Orbital strike uses a **charge-based system** (2 uses per mission), not energy. Framerate control uses energy and has a 6-second cooldown between uses.

---

## Summary Table: Ability Tuning

| Ability           | Input | Charge Time | Cooldown | Resource | Damage | Use Case |
|-------------------|-------|-------------|----------|----------|--------|----------|
| Charge Laser      | Hold RT | 1.0s | 2s (overheat) | None | 25–100 | Primary sustained damage |
| Orbital Strike    | RB (targeting) | N/A | 20s | 2 uses/mission | 200 center | Area denial, grouped targets |
| Burst Speed       | LB | Instant | 8s | None | 0 (evasion) | Reposition, evade |
| Framerate Control | LT | Instant | 6s | 60 energy | 0 (perception) | Tactical awareness, precision |

---

**Implementation Notes:**
- All damage calculations happen on the host; clients show VFX optimistically but await server confirmation.
- Use `@rpc()` with `"call_local"` for VFX to ensure all clients (including the attacker) see effects simultaneously.
- Ability cooldown/energy state is synced to all clients every 0.2 seconds via `_sync_drone_state()` RPC to prevent desyncs.
- Test ability interaction: e.g., burst during charge laser should cancel charge and require restart.
- Consider ability buffering: e.g., if player presses LB during RT release, queue the burst for next available frame.
