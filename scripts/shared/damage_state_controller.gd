## Advanced damage progression: fire, flooding, and ship integrity states.
## Attached per-ship alongside SailController, HelmController, CrewController.
##
## Fire: room-based when layout present, otherwise 8-zone fallback.
## Flooding: waterline hits create leaks, progressive water ingress, crew pumps.
## Integrity: derived from hull %, fire severity, flood level.
class_name DamageStateController
extends RefCounted

const _ShipRoom := preload("res://scripts/shared/ship_room.gd")
const _ShipLayout := preload("res://scripts/shared/ship_layout.gd")

# ---------------------------------------------------------------------------
# Integrity state machine
# ---------------------------------------------------------------------------
enum IntegrityState { OPERATIONAL, DAMAGED, CRITICAL, SINKING, DESTROYED }

const INTEGRITY_NAMES: Array[String] = [
	"Operational", "Damaged", "Critical", "Sinking", "Destroyed"
]
const INTEGRITY_COLORS: Array[Color] = [
	Color(0.3, 0.75, 0.4, 1.0),
	Color(0.85, 0.75, 0.2, 1.0),
	Color(0.9, 0.4, 0.15, 1.0),
	Color(0.85, 0.18, 0.12, 1.0),
	Color(0.3, 0.1, 0.1, 1.0),
]

# ---------------------------------------------------------------------------
# Fire constants
# ---------------------------------------------------------------------------
const ZONE_COUNT: int = 8
const FIRE_START_CHANCE_BASE: float = 0.10
const FIRE_START_CHANCE_DAMAGED_BONUS: float = 0.08
const FIRE_START_CHANCE_UPPER_BONUS: float = 0.06
const FIRE_GROWTH_RATE: float = 0.06
const FIRE_SPREAD_THRESHOLD: float = 0.35
const FIRE_SPREAD_RATE: float = 0.012
const FIRE_HULL_DAMAGE_RATE: float = 0.12
const FIRE_CREW_KILL_INTERVAL: float = 6.0
const FIRE_CREW_KILL_CHANCE: float = 0.15
const FIRE_FIGHT_RATE: float = 0.10
const FIRE_EXTINGUISH_THRESHOLD: float = 0.02
## Magazine explosion: fire in magazine room above this intensity detonates.
const MAGAZINE_EXPLOSION_THRESHOLD: float = 0.6
const MAGAZINE_EXPLOSION_HULL_DAMAGE: float = 8.0

# ---------------------------------------------------------------------------
# Flooding constants
# ---------------------------------------------------------------------------
const LEAK_PER_WATERLINE_HIT: float = 0.018
const LEAK_PER_RAM: float = 0.012
const LEAK_RATE_MAX: float = 0.15
const PUMP_RATE_PER_EFFICIENCY: float = 0.025
const FLOOD_SINK_THRESHOLD: float = 1.0
const FLOOD_SPEED_PENALTY: float = 0.45
const FLOOD_CREW_PENALTY: float = 0.30
const LEAK_DECAY_RATE: float = 0.002

# ---------------------------------------------------------------------------
# Integrity thresholds
# ---------------------------------------------------------------------------
const INTEGRITY_DAMAGED_THRESHOLD: float = 0.70
const INTEGRITY_CRITICAL_THRESHOLD: float = 0.35
const FIRE_CRITICAL_ZONE_COUNT: int = 4
const FLOOD_CRITICAL_THRESHOLD: float = 0.55

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var integrity: IntegrityState = IntegrityState.OPERATIONAL
var fire_zones: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var flood_level: float = 0.0
var leak_rate: float = 0.0
var flood_resistance: float = 1.0
var _fire_casualty_timer: float = 0.0
var _was_sinking: bool = false
## Room layout reference (optional — set by arena at init).
var layout: _ShipLayout = null
## Accumulated magazine explosion damage to deliver this frame.
var _magazine_explosion_pending: float = 0.0


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
	_magazine_explosion_pending = 0.0
	if layout != null:
		for room: _ShipRoom in layout.rooms:
			room.fire_intensity = 0.0
			room.flooded = false
			room.damage = 0.0


func attach_layout(p_layout: _ShipLayout) -> void:
	layout = p_layout


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func get_burning_zone_count() -> int:
	if layout != null:
		var room_count: int = 0
		for room: _ShipRoom in layout.rooms:
			if room.fire_intensity > FIRE_EXTINGUISH_THRESHOLD:
				room_count += 1
		return room_count
	var count: int = 0
	for f in fire_zones:
		if f > FIRE_EXTINGUISH_THRESHOLD:
			count += 1
	return count

func get_total_fire_intensity() -> float:
	if layout != null:
		var room_total: float = 0.0
		for room: _ShipRoom in layout.rooms:
			room_total += room.fire_intensity
		return room_total
	var total: float = 0.0
	for f in fire_zones:
		total += f
	return total

func is_flooding() -> bool:
	return flood_level > 0.01 or leak_rate > 0.001

func is_on_fire() -> bool:
	return get_burning_zone_count() > 0

func get_flood_speed_mult() -> float:
	return 1.0 - FLOOD_SPEED_PENALTY * clampf(flood_level, 0.0, 1.0)

func get_flood_crew_mult() -> float:
	return 1.0 - FLOOD_CREW_PENALTY * clampf(flood_level, 0.0, 1.0)

## Returns rooms currently on fire (empty if no layout).
func get_burning_rooms() -> Array:
	var result: Array = []
	if layout == null:
		return result
	for room: _ShipRoom in layout.rooms:
		if room.fire_intensity > FIRE_EXTINGUISH_THRESHOLD:
			result.append(room)
	return result

## Returns flooded rooms.
func get_flooded_rooms() -> Array:
	var result: Array = []
	if layout == null:
		return result
	for room: _ShipRoom in layout.rooms:
		if room.flooded:
			result.append(room)
	return result


# ---------------------------------------------------------------------------
# Damage events
# ---------------------------------------------------------------------------
func on_cannonball_hit(zone_index: int, hit_h: float, hull_frac: float) -> void:
	var fire_chance: float = FIRE_START_CHANCE_BASE
	if hull_frac < 0.5:
		fire_chance += FIRE_START_CHANCE_DAMAGED_BONUS
	if hit_h >= 3.5:
		fire_chance += FIRE_START_CHANCE_UPPER_BONUS

	if layout != null:
		# Map zone to room and apply fire + damage.
		var target_room: _ShipRoom = _zone_to_room(zone_index)
		if target_room != null:
			if randf() < fire_chance:
				target_room.fire_intensity = maxf(target_room.fire_intensity, 0.15)
			target_room.damage = clampf(target_room.damage + 0.05, 0.0, 1.0)
	# Always update legacy zones for sync.
	if zone_index >= 0 and zone_index < ZONE_COUNT:
		if randf() < fire_chance:
			fire_zones[zone_index] = maxf(fire_zones[zone_index], 0.15)

	if hit_h <= 1.8:
		var scaled_leak: float = LEAK_PER_WATERLINE_HIT / maxf(0.1, flood_resistance)
		leak_rate = minf(leak_rate + scaled_leak, LEAK_RATE_MAX)
		# Flood lower-deck rooms.
		if layout != null:
			_flood_lower_rooms()

func on_ram_hit() -> void:
	var scaled_leak: float = LEAK_PER_RAM / maxf(0.1, flood_resistance)
	leak_rate = minf(leak_rate + scaled_leak, LEAK_RATE_MAX)
	if layout != null:
		_flood_lower_rooms()


# ---------------------------------------------------------------------------
# Per-frame tick
# ---------------------------------------------------------------------------
func process(delta: float, repair_efficiency: float, crew_ref: Variant) -> float:
	var fire_hull_damage: float = 0.0
	var eff: float = maxf(0.0, repair_efficiency)
	_magazine_explosion_pending = 0.0

	var fire_active: bool = is_on_fire()
	var flood_active: bool = is_flooding()
	var fire_eff: float = 0.0
	var pump_eff: float = 0.0
	if fire_active and flood_active:
		fire_eff = eff * 0.6
		pump_eff = eff * 0.4
	elif fire_active:
		fire_eff = eff * 0.8
	elif flood_active:
		pump_eff = eff * 0.7

	if layout != null:
		fire_hull_damage = _tick_fires_room_based(delta, fire_eff, crew_ref)
	else:
		fire_hull_damage = _tick_fires(delta, fire_eff, crew_ref)

	_tick_flooding(delta, pump_eff)

	fire_hull_damage += _magazine_explosion_pending
	return fire_hull_damage


func update_integrity(hull_frac: float, alive: bool) -> void:
	if not alive:
		integrity = IntegrityState.SINKING
		return
	if hull_frac <= 0.0 or flood_level >= FLOOD_SINK_THRESHOLD:
		integrity = IntegrityState.SINKING
		return
	var burning: int = get_burning_zone_count()
	if hull_frac <= INTEGRITY_CRITICAL_THRESHOLD or burning >= FIRE_CRITICAL_ZONE_COUNT or flood_level >= FLOOD_CRITICAL_THRESHOLD:
		integrity = IntegrityState.CRITICAL
		return
	if hull_frac <= INTEGRITY_DAMAGED_THRESHOLD or burning >= 2 or flood_level >= 0.25:
		integrity = IntegrityState.DAMAGED
		return
	integrity = IntegrityState.OPERATIONAL


func get_remaining_repair_fraction() -> float:
	var fire_active: bool = is_on_fire()
	var flood_active: bool = is_flooding()
	if fire_active and flood_active:
		return 0.0
	if fire_active:
		return 0.2
	if flood_active:
		return 0.3
	return 1.0


# ---------------------------------------------------------------------------
# Room-based fire tick
# ---------------------------------------------------------------------------
func _tick_fires_room_based(delta: float, fire_eff: float, crew_ref: Variant) -> float:
	var hull_dmg: float = 0.0
	var burning_count: int = 0

	# Growth + spread via adjacency.
	for room: _ShipRoom in layout.rooms:
		if room.fire_intensity < FIRE_EXTINGUISH_THRESHOLD:
			continue
		burning_count += 1
		room.fire_intensity = minf(room.fire_intensity + FIRE_GROWTH_RATE * delta, 1.0)
		# Spread to adjacent rooms.
		if room.fire_intensity >= FIRE_SPREAD_THRESHOLD:
			var spread: float = FIRE_SPREAD_RATE * room.fire_intensity * delta
			for neighbor: _ShipRoom in room.adjacent_rooms:
				neighbor.fire_intensity = minf(neighbor.fire_intensity + spread, 1.0)
				if neighbor.fire_intensity < FIRE_EXTINGUISH_THRESHOLD and spread > 0.001:
					neighbor.fire_intensity = maxf(neighbor.fire_intensity, FIRE_EXTINGUISH_THRESHOLD + 0.01)

	# Crew fighting fires — distribute suppression across burning rooms.
	if burning_count > 0 and fire_eff > 0.001:
		var suppress_per_room: float = FIRE_FIGHT_RATE * fire_eff * delta / float(burning_count)
		for room: _ShipRoom in layout.rooms:
			if room.fire_intensity > FIRE_EXTINGUISH_THRESHOLD:
				# Crew in the room fight fire more effectively.
				var room_bonus: float = 1.0
				if room.crew_count > 0:
					room_bonus = 1.0 + float(room.crew_count) * 0.15
				room.fire_intensity = maxf(0.0, room.fire_intensity - suppress_per_room * room_bonus)

	# Hull damage from fire.
	for room: _ShipRoom in layout.rooms:
		if room.fire_intensity > FIRE_EXTINGUISH_THRESHOLD:
			hull_dmg += FIRE_HULL_DAMAGE_RATE * room.fire_intensity * delta
			# Magazine explosion check.
			if room.type == _ShipRoom.RoomType.MAGAZINE and room.fire_intensity >= MAGAZINE_EXPLOSION_THRESHOLD:
				_magazine_explosion_pending += MAGAZINE_EXPLOSION_HULL_DAMAGE
				room.fire_intensity = 0.0
				room.damage = 1.0

	# Fire crew casualties.
	if crew_ref != null and burning_count > 0:
		_fire_casualty_timer += delta
		if _fire_casualty_timer >= FIRE_CREW_KILL_INTERVAL:
			_fire_casualty_timer -= FIRE_CREW_KILL_INTERVAL
			for room: _ShipRoom in layout.rooms:
				if room.fire_intensity > FIRE_EXTINGUISH_THRESHOLD:
					if randf() < FIRE_CREW_KILL_CHANCE * room.fire_intensity:
						var zone_str: String = _room_to_crew_zone(room)
						crew_ref.apply_casualties(zone_str, 0.5)

	# Extinguish below threshold + sync to legacy zones.
	_sync_rooms_to_zones()
	return hull_dmg


# ---------------------------------------------------------------------------
# Legacy 8-zone fire tick (no layout)
# ---------------------------------------------------------------------------
func _tick_fires(delta: float, fire_eff: float, crew_ref: Variant) -> float:
	var hull_dmg: float = 0.0
	var new_zones: Array[float] = fire_zones.duplicate()
	for i in range(ZONE_COUNT):
		if fire_zones[i] < FIRE_EXTINGUISH_THRESHOLD:
			continue
		new_zones[i] = minf(new_zones[i] + FIRE_GROWTH_RATE * delta, 1.0)
		if fire_zones[i] >= FIRE_SPREAD_THRESHOLD:
			var spread: float = FIRE_SPREAD_RATE * fire_zones[i] * delta
			if i > 0:
				new_zones[i - 1] = maxf(new_zones[i - 1], minf(new_zones[i - 1] + spread, 1.0))
			if i < ZONE_COUNT - 1:
				new_zones[i + 1] = maxf(new_zones[i + 1], minf(new_zones[i + 1] + spread, 1.0))
	var burning_count: int = 0
	for f in new_zones:
		if f > FIRE_EXTINGUISH_THRESHOLD:
			burning_count += 1
	if burning_count > 0 and fire_eff > 0.001:
		var suppress_per_zone: float = FIRE_FIGHT_RATE * fire_eff * delta / float(burning_count)
		for i in range(ZONE_COUNT):
			if new_zones[i] > FIRE_EXTINGUISH_THRESHOLD:
				new_zones[i] = maxf(0.0, new_zones[i] - suppress_per_zone)
	for i in range(ZONE_COUNT):
		if new_zones[i] > FIRE_EXTINGUISH_THRESHOLD:
			hull_dmg += FIRE_HULL_DAMAGE_RATE * new_zones[i] * delta
	if crew_ref != null and burning_count > 0:
		_fire_casualty_timer += delta
		if _fire_casualty_timer >= FIRE_CREW_KILL_INTERVAL:
			_fire_casualty_timer -= FIRE_CREW_KILL_INTERVAL
			for i in range(ZONE_COUNT):
				if new_zones[i] > FIRE_EXTINGUISH_THRESHOLD:
					if randf() < FIRE_CREW_KILL_CHANCE * new_zones[i]:
						var zone: String = _zone_index_to_crew_zone(i)
						crew_ref.apply_casualties(zone, 0.5)
	for i in range(ZONE_COUNT):
		if new_zones[i] < FIRE_EXTINGUISH_THRESHOLD:
			new_zones[i] = 0.0
	fire_zones = new_zones
	return hull_dmg


# ---------------------------------------------------------------------------
# Flooding tick
# ---------------------------------------------------------------------------
func _tick_flooding(delta: float, pump_eff: float) -> void:
	leak_rate = maxf(0.0, leak_rate - LEAK_DECAY_RATE * delta)
	flood_level += leak_rate * delta
	if pump_eff > 0.001:
		var pump: float = PUMP_RATE_PER_EFFICIENCY * pump_eff * delta
		flood_level = maxf(0.0, flood_level - pump)
	flood_level = clampf(flood_level, 0.0, FLOOD_SINK_THRESHOLD)
	# Update room flood state.
	if layout != null:
		if flood_level > 0.3:
			for room: _ShipRoom in layout.rooms:
				if room.deck_level == _ShipRoom.DeckLevel.LOWER:
					room.flooded = true
				else:
					room.flooded = false
		elif flood_level > 0.01:
			for room: _ShipRoom in layout.rooms:
				room.flooded = false
			# Flood the lowest rooms first.
			for room2: _ShipRoom in layout.rooms:
				if room2.deck_level == _ShipRoom.DeckLevel.LOWER:
					room2.flooded = true
					break
		else:
			for room: _ShipRoom in layout.rooms:
				room.flooded = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _zone_index_to_crew_zone(zone_idx: int) -> String:
	if zone_idx <= 1:
		return "upper"
	if zone_idx >= 6:
		return "lower"
	return "mid"


static func hit_h_to_zone_index(hit_h: float) -> int:
	var h: float = clampf(hit_h, 0.06, 6.0)
	var t: float = (h - 0.06) / (6.0 - 0.06)
	var idx: int = int((1.0 - t) * float(ZONE_COUNT - 1) + 0.5)
	return clampi(idx, 0, ZONE_COUNT - 1)


## Map a zone index to the best matching room in the layout.
func _zone_to_room(zone_idx: int) -> _ShipRoom:
	if layout == null:
		return null
	# Zones 0-1: upper → rigging; 2-3: guns port; 4-5: guns stbd; 6: carpenter/helm; 7: helm
	var target_type: _ShipRoom.RoomType
	match zone_idx:
		0, 1:
			target_type = _ShipRoom.RoomType.RIGGING
		2, 3:
			target_type = _ShipRoom.RoomType.GUN_DECK_PORT
		4, 5:
			target_type = _ShipRoom.RoomType.GUN_DECK_STBD
		6:
			target_type = _ShipRoom.RoomType.CARPENTER
		7:
			target_type = _ShipRoom.RoomType.HELM
		_:
			target_type = _ShipRoom.RoomType.CARPENTER
	var room: _ShipRoom = layout.get_room(target_type)
	return room


## Map a room type to crew casualty zone string.
func _room_to_crew_zone(room: _ShipRoom) -> String:
	match room.type:
		_ShipRoom.RoomType.RIGGING:
			return "upper"
		_ShipRoom.RoomType.GUN_DECK_PORT, _ShipRoom.RoomType.GUN_DECK_STBD:
			return "mid"
		_ShipRoom.RoomType.HELM:
			return "lower"
	return "mid"


## Sync room fire intensities into legacy fire_zones for network encoding.
func _sync_rooms_to_zones() -> void:
	if layout == null:
		return
	# Zero out legacy zones and fill from rooms.
	for i in range(ZONE_COUNT):
		fire_zones[i] = 0.0
	for room: _ShipRoom in layout.rooms:
		if room.fire_intensity < FIRE_EXTINGUISH_THRESHOLD:
			room.fire_intensity = 0.0
			continue
		# Map room back to a zone index for sync.
		var zi: int = _room_to_zone_index(room)
		if zi >= 0 and zi < ZONE_COUNT:
			fire_zones[zi] = maxf(fire_zones[zi], room.fire_intensity)


func _room_to_zone_index(room: _ShipRoom) -> int:
	match room.type:
		_ShipRoom.RoomType.RIGGING:
			return 0
		_ShipRoom.RoomType.MAGAZINE:
			return 1
		_ShipRoom.RoomType.GUN_DECK_PORT:
			return 2
		_ShipRoom.RoomType.GUN_DECK_STBD:
			return 4
		_ShipRoom.RoomType.CARPENTER:
			return 5
		_ShipRoom.RoomType.PUMPS:
			return 6
		_ShipRoom.RoomType.HELM:
			return 7
	return 3  # mid/default


## Flood lower-deck rooms when waterline is breached.
func _flood_lower_rooms() -> void:
	if layout == null:
		return
	for room: _ShipRoom in layout.rooms:
		if room.deck_level == _ShipRoom.DeckLevel.LOWER:
			room.flooded = true


# ---------------------------------------------------------------------------
# Network sync
# ---------------------------------------------------------------------------
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

func encode_misc() -> int:
	var fl: int = clampi(int(flood_level * 1000.0), 0, 1023)
	var lr: int = clampi(int(leak_rate * 10000.0), 0, 4095)
	var is_val: int = clampi(int(integrity), 0, 7)
	return fl | (lr << 10) | (is_val << 22)

func decode_sync_ints(fa: int, fb: int, misc: int) -> void:
	for i in range(4):
		fire_zones[i] = float((fa >> (i * 8)) & 0xFF) / 255.0
		fire_zones[i + 4] = float((fb >> (i * 8)) & 0xFF) / 255.0
	flood_level = float(misc & 0x3FF) / 1000.0
	leak_rate = float((misc >> 10) & 0xFFF) / 10000.0
	integrity = ((misc >> 22) & 0x7) as IntegrityState
