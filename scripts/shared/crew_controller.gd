## FTL-style crew management: allocate crew across ship stations to modify performance.
## Each station has an efficiency curve based on crew count vs. optimal staffing.
## Crew can die from combat damage and be reassigned between stations in real-time.
class_name CrewController
extends RefCounted

enum Station { GUNS_PORT, GUNS_STBD, RIGGING, HELM, REPAIR }

const STATION_COUNT: int = 5
const STATION_NAMES: Array[String] = ["Guns Port", "Guns Stbd", "Rigging", "Helm", "Repair"]
const STATION_KEYS: Array[String] = ["1", "2", "3", "4", "5"]

## Optimal crew per station — at this count, efficiency = 1.0 (no change from baseline).
const OPTIMAL_CREW: int = 4
## Default starting allocation (balanced across all 5 stations).
const DEFAULT_ALLOCATION: Array[int] = [4, 4, 4, 4, 4]
const DEFAULT_TOTAL: int = 20

## Repair tuning.
const BASE_REPAIR_RATE: float = 0.04
const HULL_REPAIR_MULT: float = 0.5
const COMPONENT_REPAIR_MULT: float = 0.08
## Hull health threshold below which repair prioritizes hull over components.
const HULL_PRIORITY_THRESHOLD: float = 0.5

## Casualty tuning.
const BASE_KILL_CHANCE: float = 0.20
const COLLATERAL_REPAIR_MULT: float = 0.30

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var max_crew: int = DEFAULT_TOTAL
var total_crew: int = DEFAULT_TOTAL
var station_crew: Array[int] = [4, 4, 4, 4, 4]
## Currently selected station in the overlay UI (-1 = none).
var selected_station: int = -1


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------
func reset(crew_count: int = DEFAULT_TOTAL) -> void:
	max_crew = crew_count
	total_crew = crew_count
	selected_station = -1
	# Distribute evenly, remainder to Repair.
	@warning_ignore("integer_division")
	var per_station: int = crew_count / STATION_COUNT
	var remainder: int = crew_count % STATION_COUNT
	for i in range(STATION_COUNT):
		station_crew[i] = per_station
	# Give remainder to Repair (last station).
	station_crew[Station.REPAIR] += remainder


# ---------------------------------------------------------------------------
# Efficiency
# ---------------------------------------------------------------------------
## Returns 0.0–~1.15 based on crew count vs optimal staffing.
## 0 crew = 0.0 (unmanned), optimal crew = 1.0, overstaffed = up to ~1.15.
func get_station_efficiency(station: Station) -> float:
	var count: int = station_crew[station]
	if count <= 0:
		return 0.0
	var ratio: float = float(count) / float(OPTIMAL_CREW)
	if ratio <= 1.0:
		# Quadratic ramp: fast gains for first few crew, diminishing near optimal.
		return 1.0 - (1.0 - ratio) * (1.0 - ratio)
	else:
		# Mild overstaffing bonus, soft-capped at ~1.15.
		return 1.0 + 0.15 * (1.0 - exp(-(ratio - 1.0)))


# ---------------------------------------------------------------------------
# Crew Transfer
# ---------------------------------------------------------------------------
## Add crew to a station by pulling from the most-staffed other station.
func add_crew_to_station(station: int, count: int = 1) -> void:
	for _i in range(count):
		var source: int = _most_staffed_station_except(station)
		if source < 0 or station_crew[source] <= 0:
			return
		station_crew[source] -= 1
		station_crew[station] += 1


## Remove crew from a station and send to the least-staffed other station.
func remove_crew_from_station(station: int, count: int = 1) -> void:
	for _i in range(count):
		if station_crew[station] <= 0:
			return
		var target: int = _least_staffed_station_except(station)
		if target < 0:
			return
		station_crew[station] -= 1
		station_crew[target] += 1


func _most_staffed_station_except(exclude: int) -> int:
	var best: int = -1
	var best_count: int = -1
	for i in range(STATION_COUNT):
		if i == exclude:
			continue
		if station_crew[i] > best_count:
			best_count = station_crew[i]
			best = i
	return best


func _least_staffed_station_except(exclude: int) -> int:
	var best: int = -1
	var best_count: int = 999
	for i in range(STATION_COUNT):
		if i == exclude:
			continue
		if station_crew[i] < best_count:
			best_count = station_crew[i]
			best = i
	return best


## Bot helper: move one crew toward a target allocation per call.
func move_toward_allocation(target: Array[int]) -> void:
	if target.size() != STATION_COUNT:
		return
	# Find the station most over-target and most under-target.
	var over_idx: int = -1
	var over_delta: int = 0
	var under_idx: int = -1
	var under_delta: int = 0
	for i in range(STATION_COUNT):
		var diff: int = station_crew[i] - target[i]
		if diff > over_delta:
			over_delta = diff
			over_idx = i
		if diff < -under_delta or under_idx < 0:
			if diff < 0:
				under_delta = -diff
				under_idx = i
	if over_idx >= 0 and under_idx >= 0 and station_crew[over_idx] > 0:
		station_crew[over_idx] -= 1
		station_crew[under_idx] += 1


# ---------------------------------------------------------------------------
# Casualties
# ---------------------------------------------------------------------------
## Apply crew casualties based on hit zone. Returns number killed.
## zone: "upper" (sail area), "mid" (gun deck), "lower" (helm/waterline)
func apply_casualties(zone: String, damage: float) -> int:
	var kill_chance: float = BASE_KILL_CHANCE + maxf(0.0, damage - 1.0) * 0.1
	var killed: int = 0

	# Primary station casualties based on zone.
	var primary: Array[int] = _stations_for_zone(zone)
	for station_idx in primary:
		if station_crew[station_idx] > 0 and randf() < kill_chance:
			station_crew[station_idx] -= 1
			total_crew -= 1
			killed += 1

	# Collateral: small chance to kill Repair crew (below decks).
	if station_crew[Station.REPAIR] > 0 and randf() < kill_chance * COLLATERAL_REPAIR_MULT:
		station_crew[Station.REPAIR] -= 1
		total_crew -= 1
		killed += 1

	return killed


func _stations_for_zone(zone: String) -> Array[int]:
	match zone:
		"upper":
			return [Station.RIGGING]
		"mid":
			# Randomly hit port or starboard gun crew.
			if randf() < 0.5:
				return [Station.GUNS_PORT]
			else:
				return [Station.GUNS_STBD]
		"lower":
			return [Station.HELM]
	return []


# ---------------------------------------------------------------------------
# Repair
# ---------------------------------------------------------------------------
## Slowly restore hull health and component damage based on Repair crew efficiency.
## When fire/flooding is active, the DamageStateController consumes a fraction
## of repair effort; the remainder is available here for hull/component repair.
func process_repair(delta: float, ship_dict: Dictionary, max_hull_hp: float) -> void:
	var eff: float = get_station_efficiency(Station.REPAIR)
	if eff <= 0.001:
		return
	# If damage state controller is present, it may consume repair effort.
	var dmg_state: Variant = ship_dict.get("damage_state")
	var repair_frac: float = 1.0
	if dmg_state != null:
		repair_frac = dmg_state.get_remaining_repair_fraction()
	var repair_rate: float = eff * repair_frac * BASE_REPAIR_RATE * delta
	if repair_rate <= 0.0001:
		return

	# Priority 1: Hull health if below threshold.
	var health: float = float(ship_dict.get("health", max_hull_hp))
	if health < max_hull_hp * HULL_PRIORITY_THRESHOLD:
		var hull_repair: float = repair_rate * HULL_REPAIR_MULT
		ship_dict["health"] = minf(health + hull_repair, max_hull_hp)
		return

	# Priority 2: Most-damaged component.
	var sail = ship_dict.get("sail")
	var helm = ship_dict.get("helm")
	var sail_dmg: float = sail.damage if sail != null else 0.0
	var helm_dmg: float = helm.damage if helm != null else 0.0
	if sail_dmg > helm_dmg and sail_dmg > 0.01:
		sail.damage = maxf(0.0, sail.damage - repair_rate * COMPONENT_REPAIR_MULT)
	elif helm_dmg > 0.01:
		helm.damage = maxf(0.0, helm.damage - repair_rate * COMPONENT_REPAIR_MULT)
	elif health < max_hull_hp:
		# Components fine, repair hull if not full.
		ship_dict["health"] = minf(health + repair_rate * HULL_REPAIR_MULT, max_hull_hp)


# ---------------------------------------------------------------------------
# Network Sync
# ---------------------------------------------------------------------------
## Pack crew state into a single int (30 bits: 5 stations × 5 bits + total × 5 bits).
func encode_sync() -> int:
	var v: int = 0
	for i in range(STATION_COUNT):
		v |= (clampi(station_crew[i], 0, 31) << (i * 5))
	v |= (clampi(total_crew, 0, 31) << 25)
	return v


## Unpack crew state from a synced int.
func decode_sync(v: int) -> void:
	for i in range(STATION_COUNT):
		station_crew[i] = (v >> (i * 5)) & 0x1F
	total_crew = (v >> 25) & 0x1F
