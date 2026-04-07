## Ship class definitions — Schooner (fast/fragile), Brig (balanced), Galley (slow/tough).
## Each class returns a Dictionary of tuning constants consumed by the arena's
## _apply_naval_controllers_to_ship() during init and respawn.
class_name ShipClassConfig
extends Object

enum ShipClass { SCHOONER, BRIG, GALLEY }

const CLASS_COUNT: int = 3
const CLASS_NAMES: Array[String] = ["Schooner", "Brig", "Galley"]
const CLASS_DESCRIPTIONS: Array[String] = [
	"Fast & fragile — 6 crew, light guns, nimble helm.",
	"Balanced warship — 10 crew, standard broadside.",
	"Slow & tough — 16 crew, heavy broadside, thick hull.",
]
const DEFAULT_CLASS: int = ShipClass.BRIG


## Returns tuning dictionary for the given ship class.
static func get_config(ship_class: int) -> Dictionary:
	match ship_class:
		ShipClass.SCHOONER:
			return _schooner()
		ShipClass.BRIG:
			return _brig()
		ShipClass.GALLEY:
			return _galley()
	return _brig()


# ---------------------------------------------------------------------------
# Schooner — fast / fragile / 12 crew
# ---------------------------------------------------------------------------
static func _schooner() -> Dictionary:
	return {
		# Identity
		"ship_class": ShipClass.SCHOONER,
		"class_name": "Schooner",
		# Displacement budget (DU) — see NavalShipWeight; stock load should sit under this.
		"displacement_budget": 95.0,
		# Hull
		"hull_hits_max": 8.0,
		"hull_length_scale": 0.72,
		"hull_width_scale": 0.75,
		# Crew
		"crew_total": 6,
		# Sail
		"max_speed": 65.0,
		"sail_raise_rate": 0.25,
		"sail_lower_rate": 0.45,
		# Helm (player)
		"wheel_spin_accel": 2.8,
		"wheel_max_spin": 0.70,
		"wheel_friction": 2.8,
		"rudder_follow_rate": 0.65,
		# Battery
		"cannon_count": 8,
		"reload_time": 10.0,
		"fire_sequence_duration": 4.0,
		"battery_damage": 45.0,
		# Damage resistance
		"flood_resistance": 0.7,
	}


# ---------------------------------------------------------------------------
# Brig — balanced / 20 crew  (matches current defaults)
# ---------------------------------------------------------------------------
static func _brig() -> Dictionary:
	return {
		"ship_class": ShipClass.BRIG,
		"class_name": "Brig",
		"displacement_budget": 155.0,
		"hull_hits_max": 14.0,
		"hull_length_scale": 1.0,
		"hull_width_scale": 1.0,
		"crew_total": 10,
		"max_speed": 52.4,
		"sail_raise_rate": 0.15,
		"sail_lower_rate": 0.33,
		"wheel_spin_accel": 2.0,
		"wheel_max_spin": 0.55,
		"wheel_friction": 2.5,
		"rudder_follow_rate": 0.5,
		"cannon_count": 14,
		"reload_time": 14.0,
		"fire_sequence_duration": 6.5,
		"battery_damage": 75.0,
		"flood_resistance": 1.0,
	}


# ---------------------------------------------------------------------------
# Galley — slow / tough / 30 crew
# ---------------------------------------------------------------------------
static func _galley() -> Dictionary:
	return {
		"ship_class": ShipClass.GALLEY,
		"class_name": "Galley",
		"displacement_budget": 245.0,
		"hull_hits_max": 22.0,
		"hull_length_scale": 1.25,
		"hull_width_scale": 1.20,
		"crew_total": 16,
		"max_speed": 38.0,
		"sail_raise_rate": 0.10,
		"sail_lower_rate": 0.25,
		"wheel_spin_accel": 1.4,
		"wheel_max_spin": 0.40,
		"wheel_friction": 2.2,
		"rudder_follow_rate": 0.35,
		"cannon_count": 20,
		# Heavy ship: shorter ripple + faster cycle than old values — more bite, less waiting.
		"reload_time": 12.0,
		"fire_sequence_duration": 5.0,
		"battery_damage": 118.0,
		"flood_resistance": 1.4,
	}
