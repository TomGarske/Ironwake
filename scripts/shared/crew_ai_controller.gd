## Autonomous crew AI: manages crew station allocation based on ship state.
## Runs each frame on any ship (player or AI) — no manual override.
## Priority: fire > flood > hull damage > reload guns > balanced idle.
class_name CrewAiController
extends RefCounted

const _CrewController := preload("res://scripts/shared/crew_controller.gd")
const _DamageStateController := preload("res://scripts/shared/damage_state_controller.gd")

## Station indices: 0=GUNS_PORT, 1=GUNS_STBD, 2=RIGGING, 3=HELM, 4=REPAIR


## Compute and apply the optimal crew allocation for a ship.
## Call once per frame with the ship's dictionary.
static func tick(ship_dict: Dictionary) -> void:
	var crew: Variant = ship_dict.get("crew")
	if crew == null:
		return

	var max_hp: float = float(ship_dict.get("hull_hits_max", 14.0))
	var hp: float = float(ship_dict.get("health", max_hp))
	var hp_frac: float = hp / maxf(0.01, max_hp)

	var dmg_state: Variant = ship_dict.get("damage_state")
	var has_fire: bool = dmg_state != null and dmg_state.is_on_fire()
	var has_flood: bool = dmg_state != null and dmg_state.flood_level > 0.15
	var heavy_flood: bool = dmg_state != null and dmg_state.flood_level > 0.40
	var needs_repair: bool = hp_frac < 0.5
	var critical: bool = hp_frac < 0.25

	# Check battery states: are any batteries reloading / ready to fire?
	var port_bat: Variant = ship_dict.get("battery_port")
	var stbd_bat: Variant = ship_dict.get("battery_stbd")
	var port_needs_crew: bool = _battery_wants_crew(port_bat)
	var stbd_needs_crew: bool = _battery_wants_crew(stbd_bat)

	# Determine allocation: [GUNS_PORT, GUNS_STBD, RIGGING, HELM, REPAIR]
	var alloc: Array[int] = _compute_allocation(
		has_fire, has_flood, heavy_flood, needs_repair, critical,
		port_needs_crew, stbd_needs_crew
	)

	crew.move_toward_allocation(alloc)


## Returns true if a battery is in a state where more crew speeds things up.
static func _battery_wants_crew(bat: Variant) -> bool:
	if bat == null:
		return false
	# RELOADING, AIMING, READY all benefit from gun crew.
	# DISABLED and IDLE don't.
	var state: int = int(bat.state)
	return state != 0 and state != 5  # 0=IDLE, 5=DISABLED


## Compute the target crew allocation based on priorities.
static func _compute_allocation(
		has_fire: bool, has_flood: bool, heavy_flood: bool,
		needs_repair: bool, critical: bool,
		port_needs_crew: bool, stbd_needs_crew: bool
	) -> Array[int]:
	# Priority 1: Dual emergency — fire AND flood.
	if has_fire and heavy_flood:
		return [1, 1, 1, 1, 16]  # All hands to damage control.
	if has_fire and has_flood:
		return [2, 2, 2, 2, 12]

	# Priority 2: Single emergency.
	if has_fire:
		return [2, 2, 2, 2, 12]
	if heavy_flood:
		return [2, 2, 1, 2, 13]
	if has_flood:
		return [3, 3, 2, 2, 10]

	# Priority 3: Hull critical — heavy repair focus.
	if critical:
		return [2, 2, 2, 2, 12]
	if needs_repair:
		return [3, 3, 3, 3, 8]

	# Priority 4: Combat — crew guns that need it.
	if port_needs_crew and stbd_needs_crew:
		return [5, 5, 3, 4, 3]
	if port_needs_crew:
		return [7, 3, 3, 4, 3]
	if stbd_needs_crew:
		return [3, 7, 3, 4, 3]

	# Priority 5: Idle — balanced distribution.
	return [4, 4, 4, 4, 4]
