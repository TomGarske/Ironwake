## Classifies linear motion + turning flags (req-motion-fsm). Does not integrate physics — arena applies forces then calls resolve.
class_name MotionStateResolver
extends RefCounted

enum LinearMotionState {
	IDLE,
	ACCELERATING,
	CRUISING,
	COASTING,
	DECELERATING,
}

var idle_speed_threshold: float = 0.35
var accel_threshold: float = 0.45
var cruise_threshold: float = 0.4
var coast_speed_threshold: float = 0.3
var decel_threshold: float = 0.45
## When target sail is below current by more than this, coasting can apply (req §4.4).
var coast_sail_gap_threshold: float = 0.06
var turn_threshold: float = 0.1
var hard_turn_threshold: float = 0.7
## Rudder authority floor (fraction of max_speed).
var min_turn_speed_fraction: float = 0.1
var max_speed_ref: float = 5.0


func get_min_turn_speed() -> float:
	return max_speed_ref * min_turn_speed_fraction


func resolve_linear(current_speed: float, target_speed: float, target_sail_level: float, current_sail_level: float) -> LinearMotionState:
	# First-match priority tuned for gameplay (req-motion-fsm §4).
	if current_speed < idle_speed_threshold:
		if target_speed > current_speed + accel_threshold * 0.5:
			return LinearMotionState.ACCELERATING
		return LinearMotionState.IDLE

	if target_speed > current_speed + accel_threshold:
		return LinearMotionState.ACCELERATING

	if target_sail_level < current_sail_level - coast_sail_gap_threshold and current_speed > coast_speed_threshold:
		return LinearMotionState.COASTING

	if target_speed < current_speed - decel_threshold:
		return LinearMotionState.DECELERATING

	if absf(target_speed - current_speed) < cruise_threshold:
		return LinearMotionState.CRUISING

	if current_speed < idle_speed_threshold:
		return LinearMotionState.IDLE

	if target_speed < current_speed:
		return LinearMotionState.DECELERATING
	return LinearMotionState.ACCELERATING


func compute_turn_flags(current_speed: float, rudder_angle: float) -> Dictionary:
	var mins: float = get_min_turn_speed()
	var sp: float = absf(rudder_angle)
	var hard: bool = sp > hard_turn_threshold and current_speed > mins
	var turn: bool = sp > turn_threshold and current_speed > mins
	return {"is_turning": turn, "is_turning_hard": hard}


func linear_state_to_string(s: LinearMotionState) -> String:
	match s:
		LinearMotionState.IDLE:
			return "Idle"
		LinearMotionState.ACCELERATING:
			return "Accelerating"
		LinearMotionState.CRUISING:
			return "Cruising"
		LinearMotionState.COASTING:
			return "Coasting"
		LinearMotionState.DECELERATING:
			return "Decelerating"
	return "—"


func format_motion_summary(linear: LinearMotionState, is_turning: bool, is_turning_hard: bool) -> String:
	var base: String = linear_state_to_string(linear)
	if is_turning_hard:
		return "%s · Hard turn" % base
	if is_turning:
		return "%s · Turning" % base
	return base
