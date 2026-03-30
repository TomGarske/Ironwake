## Sail FSM: stepped propulsion intent + smoothed deployment (req-sail-fsm).
## Input is discrete: call raise_step() / lower_step() on W/S (or bindings). Call process() each frame.
## Exposes target_sail_level (from enum), current_sail_level (interpolated).
class_name SailController
extends RefCounted

enum SailState {
	STOP,
	QUARTER,
	HALF,
	FULL,
}

var sail_state: SailState = SailState.STOP

var sail_raise_rate: float = 0.5
var sail_lower_rate: float = 0.55
## At FULL deployment and current_sail_level 1.0, target_speed equals max_speed (when mapped linearly).
var max_speed: float = 5.0
## When current_sail_level is below this, motion layer applies extra coast drag (req-sail-fsm §6.3).
var coast_drag_threshold: float = 0.1

var current_sail_level: float = 0.0

## Component damage: 0.0 = pristine, 1.0 = rigging destroyed.
## Reduces effective sail deployment and raise rate.
var damage: float = 0.0

## Damage per cannonball hit to rigging (upper hull hits).
const DAMAGE_PER_HIT: float = 0.12
## At full damage, sails deliver this fraction of their normal thrust.
const MIN_EFFICIENCY: float = 0.15
## Raise rate penalty at full damage (sails are shredded — hard to set).
const DAMAGED_RAISE_MULT: float = 0.3


## Effective sail level after damage penalty.
func get_effective_sail_level() -> float:
	var efficiency: float = lerpf(1.0, MIN_EFFICIENCY, damage)
	return current_sail_level * efficiency


func get_target_sail_level() -> float:
	match sail_state:
		SailState.STOP:
			return 0.0
		SailState.QUARTER:
			return 0.25
		SailState.HALF:
			return 0.5
		SailState.FULL:
			return 1.0
	return 0.0


func get_target_speed() -> float:
	return max_speed * get_effective_sail_level()


func process(delta: float) -> void:
	var target: float = get_target_sail_level()
	var raise_rate_eff: float = sail_raise_rate * lerpf(1.0, DAMAGED_RAISE_MULT, damage)
	var rate: float = raise_rate_eff if current_sail_level < target else sail_lower_rate
	current_sail_level = move_toward(current_sail_level, target, rate * delta)


func apply_hit() -> void:
	damage = clampf(damage + DAMAGE_PER_HIT, 0.0, 1.0)


func reset_damage() -> void:
	damage = 0.0


func raise_step() -> void:
	match sail_state:
		SailState.STOP:
			sail_state = SailState.QUARTER
		SailState.QUARTER:
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
			sail_state = SailState.QUARTER
		SailState.QUARTER:
			sail_state = SailState.STOP
		SailState.STOP:
			pass


func get_display_name() -> String:
	var base: String
	match sail_state:
		SailState.STOP:
			base = "Stop"
		SailState.QUARTER:
			base = "Quarter"
		SailState.HALF:
			base = "Half"
		SailState.FULL:
			base = "Full"
		_:
			base = "—"
	if damage > 0.05:
		return "%s (-%d%%)" % [base, int(damage * 100.0)]
	return base
