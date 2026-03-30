## Single cannon battery FSM (req-battery-fsm).
class_name BatteryController
extends RefCounted

enum BatterySide {
	PORT,
	STARBOARD,
	FORWARD,
	AFT,
}

enum BatteryState {
	IDLE,
	AIMING,
	READY,
	FIRING,
	RELOADING,
	DISABLED,
}

enum FireMode {
	SALVO,
	RIPPLE,
}

signal battery_state_changed(side: BatterySide, new_state: BatteryState)
signal cannon_fired(side: BatterySide, shot_index: int)
signal volley_fired(side: BatterySide)
signal reload_started(side: BatterySide)
signal reload_complete(side: BatterySide)
signal battery_disabled(side: BatterySide)

var side: BatterySide = BatterySide.PORT
var cannon_count: int = 3
var state: BatteryState = BatteryState.IDLE
var fire_mode: FireMode = FireMode.RIPPLE
var reload_time: float = 2.8
var reload_timer: float = 0.0
var firing_arc_degrees: float = 50.0
var max_range: float = 14.0
var auto_fire_enabled: bool = false
## Continuous quoin: 0.0 → −5° depression, 1.0 → +10° elevation (linear).
## Used directly by CannonBallistics.initial_velocity(elevation_deg).
const ELEV_MIN_DEG: float = -3.0
const ELEV_MAX_DEG: float = 5.0
## Normalized `cannon_elevation` that yields 0° horizontal bore (default for new batteries).
const CANNON_ELEVATION_ZERO_DEG: float = (0.0 - ELEV_MIN_DEG) / (ELEV_MAX_DEG - ELEV_MIN_DEG)
var cannon_elevation: float = CANNON_ELEVATION_ZERO_DEG
## Quoin adjustment speed ramps from slow (precise) to fast the longer the input is held.
const ELEVATION_RATE_MIN: float = 0.04
const ELEVATION_RATE_MAX: float = 0.40
## Seconds of held input to reach full speed.
const ELEVATION_RAMP_TIME: float = 1.8
var _elevation_hold_time: float = 0.0
var battery_damage: float = 75.0
var fire_sequence_duration: float = 0.2
var shots_remaining_in_sequence: int = 0
var sequence_timer: float = 0.0


func get_ripple_interval() -> float:
	return fire_sequence_duration / float(maxi(1, cannon_count))


func _broadside_perp(hull_dir: Vector2) -> Vector2:
	match side:
		BatterySide.PORT:
			return hull_dir.rotated(PI * 0.5).normalized()
		BatterySide.STARBOARD:
			return hull_dir.rotated(-PI * 0.5).normalized()
		BatterySide.FORWARD:
			return hull_dir.normalized()
		BatterySide.AFT:
			return (-hull_dir).normalized()
	return hull_dir.rotated(-PI * 0.5).normalized()


func _target_on_correct_side(hull_dir: Vector2, aim_dir: Vector2) -> bool:
	var perp: Vector2 = _broadside_perp(hull_dir)
	return aim_dir.normalized().dot(perp) > 0.08


func _target_in_arc(hull_dir: Vector2, aim_dir: Vector2) -> bool:
	var perp: Vector2 = _broadside_perp(hull_dir)
	var a: Vector2 = aim_dir.normalized()
	if a.length_squared() < 0.01:
		return false
	var ang: float = acos(clampf(perp.dot(a), -1.0, 1.0))
	return ang <= deg_to_rad(firing_arc_degrees)


## target_distance_m: distance to resolved target in world units; used only when require_enemy_solution is true.
## When require_enemy_solution is false (manual fire with autofire off), arc/side still apply; range is ignored.
func is_target_valid(hull_dir: Vector2, aim_dir: Vector2, _ship_pos: Vector2, target_distance_m: float = -1.0, require_enemy_solution: bool = true) -> bool:
	if aim_dir.length_squared() < 0.0001:
		return false
	if not (_target_on_correct_side(hull_dir, aim_dir) and _target_in_arc(hull_dir, aim_dir)):
		return false
	if require_enemy_solution:
		if target_distance_m >= 0.0 and target_distance_m > max_range:
			return false
	return true


func _transition(new_s: BatteryState) -> void:
	if state == new_s:
		return
	state = new_s
	battery_state_changed.emit(side, new_s)
	if new_s == BatteryState.DISABLED:
		battery_disabled.emit(side)


func process_frame(delta: float, hull_dir: Vector2, aim_dir: Vector2, _ship_pos: Vector2, fire_just_pressed: bool, target_distance_m: float = -1.0) -> Array:
	var out: Array = []
	if state == BatteryState.DISABLED:
		return out

	if state == BatteryState.RELOADING:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reload_timer = 0.0
			reload_complete.emit(side)
			if aim_dir.length_squared() > 0.0001:
				_transition(BatteryState.AIMING)
			else:
				_transition(BatteryState.IDLE)
		return out

	if state == BatteryState.FIRING and fire_mode == FireMode.RIPPLE:
		_process_ripple(delta, out)
		return out

	# IDLE, AIMING, READY
	if aim_dir.length_squared() < 0.0001:
		_transition(BatteryState.IDLE)
		return out

	var need_enemy: bool = auto_fire_enabled
	if not is_target_valid(hull_dir, aim_dir, _ship_pos, target_distance_m, need_enemy):
		_transition(BatteryState.AIMING)
		return out

	_transition(BatteryState.READY)
	if fire_just_pressed or auto_fire_enabled:
		_enter_firing(out)
	return out


func _enter_firing(out: Array) -> void:
	if state != BatteryState.READY:
		return
	_transition(BatteryState.FIRING)
	if fire_mode == FireMode.SALVO:
		volley_fired.emit(side)
		var n: int = maxi(1, cannon_count)
		for i in range(n):
			out.append(float(i))
			cannon_fired.emit(side, i)
		reload_timer = reload_time
		reload_started.emit(side)
		_transition(BatteryState.RELOADING)
		return

	shots_remaining_in_sequence = cannon_count
	sequence_timer = 0.0
	out.append(0.0)
	cannon_fired.emit(side, 0)
	shots_remaining_in_sequence -= 1
	if shots_remaining_in_sequence <= 0:
		reload_timer = reload_time
		reload_started.emit(side)
		_transition(BatteryState.RELOADING)
	else:
		sequence_timer = get_ripple_interval()


func _process_ripple(delta: float, out: Array) -> void:
	sequence_timer -= delta
	if sequence_timer > 0.0:
		return
	if shots_remaining_in_sequence > 0:
		var idx: int = cannon_count - shots_remaining_in_sequence
		out.append(float(idx))
		cannon_fired.emit(side, idx)
		shots_remaining_in_sequence -= 1
		if shots_remaining_in_sequence <= 0:
			reload_timer = reload_time
			reload_started.emit(side)
			_transition(BatteryState.RELOADING)
		else:
			sequence_timer = get_ripple_interval()


func damage_per_shot_for_current_mode() -> float:
	# Salvo fires all guns in one frame; ripple staggers them — same total battery_damage per volley.
	return battery_damage / float(maxi(1, cannon_count))


func fire_mode_display() -> String:
	match fire_mode:
		FireMode.SALVO:
			return "Barrage"
		FireMode.RIPPLE:
			return "Ripple"
	return "—"


func reload_progress() -> float:
	if reload_time <= 0.0001:
		return 1.0
	if state == BatteryState.RELOADING:
		return clampf(1.0 - reload_timer / reload_time, 0.0, 1.0)
	return 1.0


func state_display() -> String:
	match state:
		BatteryState.IDLE:
			return "Idle"
		BatteryState.AIMING:
			return "Aiming"
		BatteryState.READY:
			return "Ready"
		BatteryState.FIRING:
			return "Firing"
		BatteryState.RELOADING:
			return "Reloading"
		BatteryState.DISABLED:
			return "Disabled"
	return "—"


func elevation_degrees() -> float:
	return lerpf(ELEV_MIN_DEG, ELEV_MAX_DEG, cannon_elevation)


func adjust_elevation(delta: float, direction: float) -> void:
	_elevation_hold_time += delta
	var t: float = clampf(_elevation_hold_time / ELEVATION_RAMP_TIME, 0.0, 1.0)
	var rate: float = lerpf(ELEVATION_RATE_MIN, ELEVATION_RATE_MAX, t * t)
	cannon_elevation = clampf(cannon_elevation + direction * rate * delta, 0.0, 1.0)


func reset_elevation_hold() -> void:
	_elevation_hold_time = 0.0


func elevation_label() -> String:
	var deg: float = elevation_degrees()
	var sign_str: String = "+" if deg >= 0.0 else ""
	return "%s%.1f°" % [sign_str, deg]


func side_label() -> String:
	match side:
		BatterySide.PORT:
			return "Port"
		BatterySide.STARBOARD:
			return "Starboard"
		BatterySide.FORWARD:
			return "Forward"
		BatterySide.AFT:
			return "Aft"
	return "—"
