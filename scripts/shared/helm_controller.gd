## Helm / wheel FSM (req-helm-fsm). Produces wheel_position and smoothed rudder_angle for the motion layer.
## Call process_steer() each frame with left/right strengths in [0,1] (keyboard = 1.0 when held).
class_name HelmController
extends RefCounted

enum HelmState {
	CENTER,
	LEFT,
	RIGHT,
	TURNING_LEFT,
	TURNING_RIGHT,
	RECENTERING,
}

var wheel_position: float = 0.0
var rudder_angle: float = 0.0

## req-helm-fsm §8: active steering faster than passive return (turn > return).
var wheel_turn_rate: float = 2.2
var wheel_return_rate: float = 1.0
var rudder_follow_rate: float = 1.5
var center_threshold: float = 0.05

var _wheel_at_tick_start: float = 0.0
var _had_steering_input: bool = false
var _steer_left: bool = false
var _steer_right: bool = false


func process_steer(delta: float, left_strength: float, right_strength: float) -> void:
	_wheel_at_tick_start = wheel_position
	var l: float = clampf(left_strength, 0.0, 1.0)
	var r: float = clampf(right_strength, 0.0, 1.0)
	var dominant: float = absf(l - r)
	var active: bool = dominant > 0.02
	_had_steering_input = active
	_steer_left = active and l > r
	_steer_right = active and r > l
	if active:
		if l > r:
			wheel_position = move_toward(wheel_position, -1.0, wheel_turn_rate * l * delta)
		else:
			wheel_position = move_toward(wheel_position, 1.0, wheel_turn_rate * r * delta)
	else:
		wheel_position = move_toward(wheel_position, 0.0, wheel_return_rate * delta)

	rudder_angle = move_toward(rudder_angle, wheel_position, rudder_follow_rate * delta)


func get_helm_state() -> HelmState:
	var w: float = wheel_position
	var dw: float = w - _wheel_at_tick_start
	var eps: float = 0.0001
	if absf(w) < center_threshold:
		return HelmState.CENTER

	if _had_steering_input:
		if _steer_left:
			if dw < -eps:
				return HelmState.TURNING_LEFT
			if w < -center_threshold:
				return HelmState.LEFT
			if w > center_threshold:
				return HelmState.TURNING_LEFT
		elif _steer_right:
			if dw > eps:
				return HelmState.TURNING_RIGHT
			if w > center_threshold:
				return HelmState.RIGHT
			if w < -center_threshold:
				return HelmState.TURNING_RIGHT
	else:
		if absf(dw) > eps:
			return HelmState.RECENTERING
		if w < -center_threshold:
			return HelmState.LEFT
		if w > center_threshold:
			return HelmState.RIGHT
	return HelmState.CENTER


func get_rudder_label() -> String:
	var pct: int = int(clampf(absf(rudder_angle), 0.0, 1.0) * 100.0)
	if pct < 3:
		return "Rudder mid"
	if rudder_angle < 0.0:
		return "Port %d%%" % pct
	return "Stbd %d%%" % pct


func get_helm_state_enum_name() -> String:
	match get_helm_state():
		HelmState.CENTER:
			return "CENTER"
		HelmState.LEFT:
			return "LEFT"
		HelmState.RIGHT:
			return "RIGHT"
		HelmState.TURNING_LEFT:
			return "TURNING_LEFT"
		HelmState.TURNING_RIGHT:
			return "TURNING_RIGHT"
		HelmState.RECENTERING:
			return "RECENTERING"
	return "—"


func get_helm_state_label() -> String:
	match get_helm_state():
		HelmState.CENTER:
			return "Center"
		HelmState.LEFT:
			return "Port"
		HelmState.RIGHT:
			return "Starboard"
		HelmState.TURNING_LEFT:
			return "Wheel ←"
		HelmState.TURNING_RIGHT:
			return "Wheel →"
		HelmState.RECENTERING:
			return "Ease helm"
	return "—"
