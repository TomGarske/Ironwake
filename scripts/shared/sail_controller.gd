## Sail FSM: stepped propulsion intent + smoothed deployment (req-sail-fsm).
## Input is discrete: call raise_step() / lower_step() on W/S (or bindings). Call process() each frame.
## Exposes target_sail_level (from enum), current_sail_level (interpolated), and target_speed = max_speed * current_sail_level.
class_name SailController
extends RefCounted

enum SailState {
	STOP,
	HALF,
	FULL,
}

var sail_state: SailState = SailState.STOP

var sail_raise_rate: float = 0.5
var sail_lower_rate: float = 0.55
## At FULL deployment and current_sail_level 1.0, target_speed equals max_speed.
var max_speed: float = 5.0
## When current_sail_level is below this, motion layer applies extra coast drag (req-sail-fsm §6.3).
var coast_drag_threshold: float = 0.1

var current_sail_level: float = 0.0


func get_target_sail_level() -> float:
	match sail_state:
		SailState.STOP:
			return 0.0
		SailState.HALF:
			return 0.5
		SailState.FULL:
			return 1.0
	return 0.0


func get_target_speed() -> float:
	return max_speed * current_sail_level


func process(delta: float) -> void:
	var target: float = get_target_sail_level()
	var rate: float = sail_raise_rate if current_sail_level < target else sail_lower_rate
	current_sail_level = move_toward(current_sail_level, target, rate * delta)


func raise_step() -> void:
	match sail_state:
		SailState.STOP:
			sail_state = SailState.HALF
		SailState.HALF:
			sail_state = SailState.FULL
		SailState.FULL:
			pass


func lower_step() -> void:
	match sail_state:
		SailState.FULL:
			sail_state = SailState.HALF
		SailState.HALF:
			sail_state = SailState.STOP
		SailState.STOP:
			pass


func get_display_name() -> String:
	match sail_state:
		SailState.STOP:
			return "Stop"
		SailState.HALF:
			return "Half"
		SailState.FULL:
			return "Full"
	return "—"
