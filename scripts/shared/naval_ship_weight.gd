## Abstract displacement / load model for Ironwake ship classes.
## Uses class config (guns, crew, hull, shot weight proxy) plus a nominal magazine.
## Units are arbitrary "displacement units" (DU) for balance and UI — not historical tonnes.
class_name NavalShipWeight
extends Object

const DAMAGE_REFERENCE: float = 75.0
## Single gun + carriage + tackle (scales slightly with caliber proxy).
const WEIGHT_PER_GUN_MOUNT: float = 2.8
## Provisions, water, personal kit per sailor.
const WEIGHT_CREW_MEMBER: float = 0.12
## One round (ball + powder) scaled by caliber; counted per gun for a nominal magazine.
const WEIGHT_PER_ROUND: float = 0.035
## Rounds carried per gun for weight accounting (gameplay reload is abstract / unlimited).
const DEFAULT_ROUNDS_PER_GUN: int = 36
## Structural mass proxy from hull integrity points.
const WEIGHT_PER_HULL_POINT: float = 1.1


## Heavier `battery_damage` ⇒ slightly heavier tubes and shot for displacement math.
static func _caliber_mass_multiplier(battery_damage: float) -> float:
	var d: float = maxf(1.0, battery_damage)
	return pow(d / DAMAGE_REFERENCE, 0.35)


## Build a displacement breakdown from a ShipClassConfig-style dictionary.
static func compute(cfg: Dictionary) -> Dictionary:
	var cannons_per_side: int = maxi(1, int(cfg.get("cannon_count", 14)))
	var total_guns: int = cannons_per_side * 2
	var crew_n: int = maxi(0, int(cfg.get("crew_total", 20)))
	var hull_pts: float = maxf(0.0, float(cfg.get("hull_hits_max", 14.0)))
	var bat_dmg: float = float(cfg.get("battery_damage", 75.0))
	var cal: float = _caliber_mass_multiplier(bat_dmg)

	var w_arm: float = float(total_guns) * WEIGHT_PER_GUN_MOUNT * cal
	var w_crew: float = float(crew_n) * WEIGHT_CREW_MEMBER
	var w_ammo: float = float(total_guns * DEFAULT_ROUNDS_PER_GUN) * WEIGHT_PER_ROUND * cal
	var w_hull: float = hull_pts * WEIGHT_PER_HULL_POINT
	var total: float = w_arm + w_crew + w_ammo + w_hull

	var budget: float = float(cfg.get("displacement_budget", 1.0e9))
	if budget <= 0.0:
		budget = 1.0e9
	var over: bool = total > budget + 0.001

	return {
		"total": total,
		"armament": w_arm,
		"crew_and_stores": w_crew,
		"ammunition": w_ammo,
		"hull_structure": w_hull,
		"budget": budget,
		"over_budget": over,
		"fraction_of_budget": total / budget,
		"total_guns": total_guns,
		"rounds_per_gun": DEFAULT_ROUNDS_PER_GUN,
	}
