## Advanced damage progression: fire, flooding, and ship integrity states.
## Attached per-ship alongside SailController, HelmController, CrewController.
##
## Fire: zone-based (8 hull zones), spreads to adjacent zones, fought by crew.
## Flooding: waterline hits create leaks, progressive water ingress, crew pumps.
## Integrity: derived from hull %, fire severity, flood level.
class_name DamageStateController
extends RefCounted

# ---------------------------------------------------------------------------
# Integrity state machine
# ---------------------------------------------------------------------------
enum IntegrityState { OPERATIONAL, DAMAGED, CRITICAL, SINKING, DESTROYED }

const INTEGRITY_NAMES: Array[String] = [
	"Operational", "Damaged", "Critical", "Sinking", "Destroyed"
]
const INTEGRITY_COLORS: Array[Color] = [
	Color(0.3, 0.75, 0.4, 1.0),   # green
	Color(0.85, 0.75, 0.2, 1.0),  # yellow
	Color(0.9, 0.4, 0.15, 1.0),   # orange
	Color(0.85, 0.18, 0.12, 1.0), # red
	Color(0.3, 0.1, 0.1, 1.0),    # dark red
]

# ---------------------------------------------------------------------------
# Fire constants
# ---------------------------------------------------------------------------
const ZONE_COUNT: int = 8
## Chance per cannonball to ignite the hit zone.
const FIRE_START_CHANCE_BASE: float = 0.10
## Bonus ignition chance when hull < 50%.
const FIRE_START_CHANCE_DAMAGED_BONUS: float = 0.08
## Upper-hull hits are more likely to start fires (heated shot hitting rigging/tar).
const FIRE_START_CHANCE_UPPER_BONUS: float = 0.06
## Fire intensity growth per second (uncontested — crew not fighting it).
const FIRE_GROWTH_RATE: float = 0.06
## Fire spreads to adjacent zones when source zone intensity exceeds this.
const FIRE_SPREAD_THRESHOLD: float = 0.35
## Rate at which fire spreads to adjacent zones (per second per source intensity).
const FIRE_SPREAD_RATE: float = 0.012
## Hull damage per second per zone from active fire (fire_intensity * rate).
const FIRE_HULL_DAMAGE_RATE: float = 0.12
## Seconds between crew casualty rolls from fire (per burning zone).
const FIRE_CREW_KILL_INTERVAL: float = 6.0
## Chance to kill a crew member per fire casualty roll.
const FIRE_CREW_KILL_CHANCE: float = 0.15
## Crew firefighting suppression rate per unit of repair efficiency.
const FIRE_FIGHT_RATE: float = 0.10
## Below this intensity a fire is considered extinguished.
const FIRE_EXTINGUISH_THRESHOLD: float = 0.02

# ---------------------------------------------------------------------------
# Flooding constants
# ---------------------------------------------------------------------------
## Leak rate added per waterline hit (cumulative).
const LEAK_PER_WATERLINE_HIT: float = 0.018
## Leak rate added per ram impact.
const LEAK_PER_RAM: float = 0.012
## Maximum leak rate (hull is riddled with holes).
const LEAK_RATE_MAX: float = 0.15
## Crew pump rate per unit of repair efficiency (per second).
const PUMP_RATE_PER_EFFICIENCY: float = 0.025
## Flood level at which the ship auto-sinks (hull integrity irrelevant).
const FLOOD_SINK_THRESHOLD: float = 1.0
## Speed penalty multiplier at full flood: effective_speed *= (1 - penalty * flood).
const FLOOD_SPEED_PENALTY: float = 0.45
## Crew efficiency penalty at high flood (water on gun deck).
const FLOOD_CREW_PENALTY: float = 0.30
## Leak rate natural decay (wood swells, temporary plugs).
const LEAK_DECAY_RATE: float = 0.002

# ---------------------------------------------------------------------------
# Integrity thresholds (based on hull fraction)
# ---------------------------------------------------------------------------
const INTEGRITY_DAMAGED_THRESHOLD: float = 0.70
const INTEGRITY_CRITICAL_THRESHOLD: float = 0.35
## Fire/flood can escalate integrity even if hull is still OK.
const FIRE_CRITICAL_ZONE_COUNT: int = 4
const FLOOD_CRITICAL_THRESHOLD: float = 0.55

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var integrity: IntegrityState = IntegrityState.OPERATIONAL
## Per-zone fire intensity: 0.0 = clear, 1.0 = fully ablaze.
var fire_zones: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## Cumulative flood level: 0.0 = dry, 1.0 = sinking.
var flood_level: float = 0.0
## Water ingress rate (per second). Increases with each waterline hit.
var leak_rate: float = 0.0
## Per-class flood resistance multiplier (larger hulls resist flooding).
var flood_resistance: float = 1.0
## Timer for fire crew casualties (rolls once per interval per burning zone).
var _fire_casualty_timer: float = 0.0
## Tracks whether ship was sinking last frame (for state transition detection).
var _was_sinking: bool = false


# ---------------------------------------------------------------------------
# Init / Reset
# ---------------------------------------------------------------------------
func reset() -> void:
	integrity = IntegrityState.OPERATIONAL
	for i in range(ZONE_COUNT):
		fire_zones[i] = 0.0
	flood_level = 0.0
	leak_rate = 0.0
	_fire_casualty_timer = 0.0
	_was_sinking = false


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func get_burning_zone_count() -> int:
	var count: int = 0
	for f in fire_zones:
		if f > FIRE_EXTINGUISH_THRESHOLD:
			count += 1
	return count

func get_total_fire_intensity() -> float:
	var total: float = 0.0
	for f in fire_zones:
		total += f
	return total

func is_flooding() -> bool:
	return flood_level > 0.01 or leak_rate > 0.001

func is_on_fire() -> bool:
	return get_burning_zone_count() > 0

## Speed multiplier from flooding (1.0 = no penalty, lower = slower).
func get_flood_speed_mult() -> float:
	return 1.0 - FLOOD_SPEED_PENALTY * clampf(flood_level, 0.0, 1.0)

## Crew efficiency multiplier from flooding (water on decks hampers crew).
func get_flood_crew_mult() -> float:
	return 1.0 - FLOOD_CREW_PENALTY * clampf(flood_level, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Damage events (called when hits land)
# ---------------------------------------------------------------------------
## Called when a cannonball hits. May start a fire in the hit zone.
## zone_index: 0-7 corresponding to hull zones (bow-to-stern).
## hit_h: projectile impact height (used to determine fire/flood).
## hull_frac: current hull health fraction (0-1).
func on_cannonball_hit(zone_index: int, hit_h: float, hull_frac: float) -> void:
	# --- Fire ignition ---
	var fire_chance: float = FIRE_START_CHANCE_BASE
	if hull_frac < 0.5:
		fire_chance += FIRE_START_CHANCE_DAMAGED_BONUS
	if hit_h >= 3.5:
		fire_chance += FIRE_START_CHANCE_UPPER_BONUS
	if zone_index >= 0 and zone_index < ZONE_COUNT:
		if randf() < fire_chance:
			fire_zones[zone_index] = maxf(fire_zones[zone_index], 0.15)

	# --- Flooding from waterline hits (scaled by hull flood resistance) ---
	if hit_h <= 1.8:
		var scaled_leak: float = LEAK_PER_WATERLINE_HIT / maxf(0.1, flood_resistance)
		leak_rate = minf(leak_rate + scaled_leak, LEAK_RATE_MAX)

## Called on ram impact — causes flooding (scaled by hull flood resistance).
func on_ram_hit() -> void:
	var scaled_leak: float = LEAK_PER_RAM / maxf(0.1, flood_resistance)
	leak_rate = minf(leak_rate + scaled_leak, LEAK_RATE_MAX)


# ---------------------------------------------------------------------------
# Per-frame tick
# ---------------------------------------------------------------------------
## Main update. Returns hull damage dealt this frame by fire.
## repair_efficiency: crew REPAIR station efficiency (0-~1.15).
## crew_ref: CrewController for casualty application. May be null.
func process(delta: float, repair_efficiency: float, crew_ref: Variant) -> float:
	var fire_hull_damage: float = 0.0
	var eff: float = maxf(0.0, repair_efficiency)

	# --- Proportion repair effort among active hazards ---
	var fire_active: bool = is_on_fire()
	var flood_active: bool = is_flooding()
	var fire_eff: float = 0.0
	var pump_eff: float = 0.0
	# Fire gets priority, then flooding, then normal repair (handled externally).
	if fire_active and flood_active:
		fire_eff = eff * 0.6
		pump_eff = eff * 0.4
	elif fire_active:
		fire_eff = eff * 0.8
	elif flood_active:
		pump_eff = eff * 0.7

	# --- Tick fires ---
	fire_hull_damage = _tick_fires(delta, fire_eff, crew_ref)

	# --- Tick flooding ---
	_tick_flooding(delta, pump_eff)

	return fire_hull_damage


## Update integrity state based on hull fraction + fire + flood.
func update_integrity(hull_frac: float, alive: bool) -> void:
	if not alive:
		integrity = IntegrityState.SINKING
		return
	if hull_frac <= 0.0 or flood_level >= FLOOD_SINK_THRESHOLD:
		integrity = IntegrityState.SINKING
		return
	var burning: int = get_burning_zone_count()
	# Critical: low hull, severe fire, or heavy flooding.
	if hull_frac <= INTEGRITY_CRITICAL_THRESHOLD or burning >= FIRE_CRITICAL_ZONE_COUNT or flood_level >= FLOOD_CRITICAL_THRESHOLD:
		integrity = IntegrityState.CRITICAL
		return
	if hull_frac <= INTEGRITY_DAMAGED_THRESHOLD or burning >= 2 or flood_level >= 0.25:
		integrity = IntegrityState.DAMAGED
		return
	integrity = IntegrityState.OPERATIONAL


## Returns fraction of repair efficiency NOT consumed by fire/flood
## (available for hull/component repair).
func get_remaining_repair_fraction() -> float:
	var fire_active: bool = is_on_fire()
	var flood_active: bool = is_flooding()
	if fire_active and flood_active:
		return 0.0  # All repair effort on fire + flood
	if fire_active:
		return 0.2  # 80% on fire, 20% left
	if flood_active:
		return 0.3  # 70% on flood, 30% left
	return 1.0  # All available for repair


# ---------------------------------------------------------------------------
# Fire tick
# ---------------------------------------------------------------------------
func _tick_fires(delta: float, fire_eff: float, crew_ref: Variant) -> float:
	var hull_dmg: float = 0.0

	# Growth + spread.
	var new_zones: Array[float] = fire_zones.duplicate()
	for i in range(ZONE_COUNT):
		if fire_zones[i] < FIRE_EXTINGUISH_THRESHOLD:
			continue
		# Fire grows.
		new_zones[i] = minf(new_zones[i] + FIRE_GROWTH_RATE * delta, 1.0)
		# Fire spreads to adjacent zones.
		if fire_zones[i] >= FIRE_SPREAD_THRESHOLD:
			var spread: float = FIRE_SPREAD_RATE * fire_zones[i] * delta
			if i > 0:
				new_zones[i - 1] = maxf(new_zones[i - 1], minf(new_zones[i - 1] + spread, 1.0))
			if i < ZONE_COUNT - 1:
				new_zones[i + 1] = maxf(new_zones[i + 1], minf(new_zones[i + 1] + spread, 1.0))

	# Crew fighting fires — distribute suppression evenly across burning zones.
	var burning_count: int = 0
	for f in new_zones:
		if f > FIRE_EXTINGUISH_THRESHOLD:
			burning_count += 1
	if burning_count > 0 and fire_eff > 0.001:
		var suppress_per_zone: float = FIRE_FIGHT_RATE * fire_eff * delta / float(burning_count)
		for i in range(ZONE_COUNT):
			if new_zones[i] > FIRE_EXTINGUISH_THRESHOLD:
				new_zones[i] = maxf(0.0, new_zones[i] - suppress_per_zone)

	# Apply fire damage to hull.
	for i in range(ZONE_COUNT):
		if new_zones[i] > FIRE_EXTINGUISH_THRESHOLD:
			hull_dmg += FIRE_HULL_DAMAGE_RATE * new_zones[i] * delta

	# Fire crew casualties.
	if crew_ref != null and burning_count > 0:
		_fire_casualty_timer += delta
		if _fire_casualty_timer >= FIRE_CREW_KILL_INTERVAL:
			_fire_casualty_timer -= FIRE_CREW_KILL_INTERVAL
			for i in range(ZONE_COUNT):
				if new_zones[i] > FIRE_EXTINGUISH_THRESHOLD:
					if randf() < FIRE_CREW_KILL_CHANCE * new_zones[i]:
						var zone: String = _zone_index_to_crew_zone(i)
						crew_ref.apply_casualties(zone, 0.5)

	# Extinguish fires below threshold.
	for i in range(ZONE_COUNT):
		if new_zones[i] < FIRE_EXTINGUISH_THRESHOLD:
			new_zones[i] = 0.0
	fire_zones = new_zones
	return hull_dmg


# ---------------------------------------------------------------------------
# Flooding tick
# ---------------------------------------------------------------------------
func _tick_flooding(delta: float, pump_eff: float) -> void:
	# Natural leak decay (wood swells, debris plugs holes).
	leak_rate = maxf(0.0, leak_rate - LEAK_DECAY_RATE * delta)
	# Water ingress.
	flood_level += leak_rate * delta
	# Crew pumping.
	if pump_eff > 0.001:
		var pump: float = PUMP_RATE_PER_EFFICIENCY * pump_eff * delta
		flood_level = maxf(0.0, flood_level - pump)
	flood_level = clampf(flood_level, 0.0, FLOOD_SINK_THRESHOLD)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
## Map zone index (0-7) to crew casualty zone string.
func _zone_index_to_crew_zone(zone_idx: int) -> String:
	# Zones 0-1: upper (bowsprit, bow — rigging)
	# Zones 2-5: mid (gun decks)
	# Zones 6-7: lower (quarter, stern — helm)
	if zone_idx <= 1:
		return "upper"
	if zone_idx >= 6:
		return "lower"
	return "mid"


## Map hit_h to zone index (0=bowsprit .. 7=stern).
## Height alone doesn't determine fore/aft; caller should use projectile
## impact position relative to ship. This is a reasonable approximation
## based on height bands when positional data isn't available.
static func hit_h_to_zone_index(hit_h: float) -> int:
	# Low hits → waterline/stern area, high hits → upper/bow area.
	# Distribute across 8 zones based on height within the hull band.
	var h: float = clampf(hit_h, 0.06, 6.0)
	var t: float = (h - 0.06) / (6.0 - 0.06)  # 0 = waterline, 1 = top
	# Invert: high hits = bow (zone 0), low hits = stern (zone 7).
	var idx: int = int((1.0 - t) * float(ZONE_COUNT - 1) + 0.5)
	return clampi(idx, 0, ZONE_COUNT - 1)


# ---------------------------------------------------------------------------
# Network sync
# ---------------------------------------------------------------------------
## Pack fire zones into 2 ints (4 zones * 8 bits each = 32 bits per int).
func encode_fire_a() -> int:
	var v: int = 0
	for i in range(4):
		v |= (clampi(int(fire_zones[i] * 255.0), 0, 255) << (i * 8))
	return v

func encode_fire_b() -> int:
	var v: int = 0
	for i in range(4):
		v |= (clampi(int(fire_zones[i + 4] * 255.0), 0, 255) << (i * 8))
	return v

## Pack flood_level (10 bits, 0-1000), leak_rate (12 bits, 0-4095), integrity (3 bits).
func encode_misc() -> int:
	var fl: int = clampi(int(flood_level * 1000.0), 0, 1023)
	var lr: int = clampi(int(leak_rate * 10000.0), 0, 4095)
	var is_val: int = clampi(int(integrity), 0, 7)
	return fl | (lr << 10) | (is_val << 22)

## Unpack from 3 ints (fa, fb, misc).
func decode_sync_ints(fa: int, fb: int, misc: int) -> void:
	for i in range(4):
		fire_zones[i] = float((fa >> (i * 8)) & 0xFF) / 255.0
		fire_zones[i + 4] = float((fb >> (i * 8)) & 0xFF) / 255.0
	flood_level = float(misc & 0x3FF) / 1000.0
	leak_rate = float((misc >> 10) & 0xFFF) / 10000.0
	integrity = ((misc >> 22) & 0x7) as IntegrityState
