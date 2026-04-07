## FTL-style crew management: allocate crew across ship rooms to modify performance.
## Rooms aggregate into legacy stations for backward-compat with helm/sail/battery controllers.
## Crew can die from combat damage and be reassigned between rooms in real-time.
class_name CrewController
extends RefCounted

const _ShipRoom := preload("res://scripts/shared/ship_room.gd")
const _ShipLayout := preload("res://scripts/shared/ship_layout.gd")
const _CrewAgent := preload("res://scripts/shared/crew_agent.gd")

## Legacy station enum — still used by helm/sail/battery multipliers.
enum Station { GUNS_PORT, GUNS_STBD, RIGGING, HELM, REPAIR }

const STATION_COUNT: int = 5
const STATION_NAMES: Array[String] = ["Guns Port", "Guns Stbd", "Rigging", "Helm", "Repair"]
const STATION_KEYS: Array[String] = ["1", "2", "3", "4", "5"]

const OPTIMAL_CREW: int = 4

## Repair tuning.
const BASE_REPAIR_RATE: float = 0.04
const HULL_REPAIR_MULT: float = 0.5
const COMPONENT_REPAIR_MULT: float = 0.08
const HULL_PRIORITY_THRESHOLD: float = 0.5

## Casualty tuning.
const BASE_KILL_CHANCE: float = 0.20
const COLLATERAL_REPAIR_MULT: float = 0.30

# ── mapping: RoomType -> legacy Station ──
const _ROOM_TO_STATION: Dictionary = {
	_ShipRoom.RoomType.HELM:              Station.HELM,
	_ShipRoom.RoomType.GUN_DECK_PORT:     Station.GUNS_PORT,
	_ShipRoom.RoomType.GUN_DECK_STBD:     Station.GUNS_STBD,
	_ShipRoom.RoomType.RIGGING:           Station.RIGGING,
	_ShipRoom.RoomType.CARPENTER:         Station.REPAIR,
	_ShipRoom.RoomType.PUMPS:             Station.REPAIR,
	_ShipRoom.RoomType.MAGAZINE:          Station.GUNS_PORT,
	_ShipRoom.RoomType.GALLEY_KITCHEN:    -1,
	_ShipRoom.RoomType.CREW_QUARTERS:     -1,
	_ShipRoom.RoomType.BRIG_JAIL:         -1,
	_ShipRoom.RoomType.SICKBAY:           -1,
	_ShipRoom.RoomType.OFFICERS_QUARTERS: -1,
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var max_crew: int = 20
var total_crew: int = 20
## Currently selected room in the overlay UI (-1 = none).
var selected_room: int = -1
## Room graph — set via attach_layout().
var layout: _ShipLayout = null
## Individual crew agents (one per live crew member + prisoners).
var agents: Array = []  # Array[CrewAgent]
## Prisoner count (subset of agents with Loyalty.PRISONER or PRESSED).
var prisoner_count: int = 0
## Next agent ID counter.
var _next_agent_id: int = 0

## Legacy station_crew array — derived from rooms each frame for backward compat.
var station_crew: Array[int] = [4, 4, 4, 4, 4]
## Alias kept for old overlay code.
var selected_station: int:
	get:
		return selected_room
	set(v):
		selected_room = v


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------
func reset(crew_count: int = 20) -> void:
	max_crew = crew_count
	total_crew = crew_count
	selected_room = -1
	agents.clear()
	prisoner_count = 0
	_next_agent_id = 0
	if layout != null:
		layout.reset_all()
		_distribute_crew_evenly(crew_count)
		_spawn_agents_from_rooms()
		_sync_station_crew()
	else:
		@warning_ignore("integer_division")
		var per_station: int = crew_count / STATION_COUNT
		var remainder: int = crew_count % STATION_COUNT
		for i in range(STATION_COUNT):
			station_crew[i] = per_station
		station_crew[Station.REPAIR] += remainder


func attach_layout(p_layout: _ShipLayout) -> void:
	layout = p_layout


## Spread crew across all rooms proportional to capacity.
func _distribute_crew_evenly(crew_count: int) -> void:
	if layout == null:
		return
	var total_cap: int = layout.total_capacity()
	if total_cap <= 0:
		return
	var remaining: int = crew_count
	for room: _ShipRoom in layout.rooms:
		@warning_ignore("integer_division")
		var share: int = mini(room.max_crew, int(float(crew_count) * float(room.max_crew) / float(total_cap)))
		room.crew_count = share
		remaining -= share
	# Distribute leftovers to rooms with spare capacity.
	for room: _ShipRoom in layout.rooms:
		if remaining <= 0:
			break
		var space: int = room.max_crew - room.crew_count
		if space > 0:
			var add: int = mini(space, remaining)
			room.crew_count += add
			remaining -= add


## Create one CrewAgent per crew member placed in rooms.
func _spawn_agents_from_rooms() -> void:
	agents.clear()
	_next_agent_id = 0
	if layout == null:
		return
	for room: _ShipRoom in layout.rooms:
		for _i in range(room.crew_count):
			var agent := _CrewAgent.new(room, _CrewAgent.Loyalty.LOYAL)
			agent.agent_id = _next_agent_id
			_next_agent_id += 1
			agents.append(agent)


## Tick all crew agents (movement + loyalty). Call once per physics frame.
func process_agents(delta: float, in_combat: bool) -> void:
	for agent in agents:
		var a: _CrewAgent = agent as _CrewAgent
		if not a.is_alive():
			continue
		if a.is_moving():
			a.process_movement(delta)
		a.process_loyalty(delta, in_combat)
	_count_prisoners()
	_sync_station_crew()


## Order all agents in `from_room` to move to `to_room`, up to `count`.
func order_crew_move(from_room: _ShipRoom, to_room: _ShipRoom, count: int = 1) -> int:
	var moved: int = 0
	for agent in agents:
		if moved >= count:
			break
		var a: _CrewAgent = agent as _CrewAgent
		if not a.is_alive() or a.is_moving():
			continue
		if a.current_room != from_room:
			continue
		if a.loyalty == _CrewAgent.Loyalty.PRISONER:
			continue
		if a.begin_move_to(to_room):
			moved += 1
	return moved


## Add captured crew as prisoners. Requires a BRIG_JAIL room with capacity.
func add_prisoners(count: int) -> int:
	if layout == null:
		return 0
	var brig: _ShipRoom = layout.get_room(_ShipRoom.RoomType.BRIG_JAIL)
	if brig == null:
		return 0
	var added: int = 0
	for _i in range(count):
		if brig.crew_count >= brig.max_crew:
			break
		var agent := _CrewAgent.new(brig, _CrewAgent.Loyalty.PRISONER)
		agent.agent_id = _next_agent_id
		_next_agent_id += 1
		agents.append(agent)
		brig.crew_count += 1
		total_crew += 1
		added += 1
	_count_prisoners()
	_sync_station_crew()
	return added


func _count_prisoners() -> void:
	prisoner_count = 0
	for agent in agents:
		var a: _CrewAgent = agent as _CrewAgent
		if a.is_alive() and a.loyalty != _CrewAgent.Loyalty.LOYAL:
			prisoner_count += 1


## Get agents currently in a specific room.
func get_agents_in_room(room: _ShipRoom) -> Array:
	var result: Array = []
	for agent in agents:
		var a: _CrewAgent = agent as _CrewAgent
		if a.is_alive() and not a.is_moving() and a.current_room == room:
			result.append(a)
	return result


## Get agents currently in transit.
func get_moving_agents() -> Array:
	var result: Array = []
	for agent in agents:
		var a: _CrewAgent = agent as _CrewAgent
		if a.is_alive() and a.is_moving():
			result.append(a)
	return result


## Rebuild legacy station_crew from room crew counts.
func _sync_station_crew() -> void:
	for i in range(STATION_COUNT):
		station_crew[i] = 0
	if layout == null:
		return
	for room: _ShipRoom in layout.rooms:
		var station: int = _ROOM_TO_STATION.get(room.type, -1)
		if station >= 0 and station < STATION_COUNT:
			station_crew[station] += room.crew_count


# ---------------------------------------------------------------------------
# Efficiency
# ---------------------------------------------------------------------------
## Legacy API: returns 0.0–~1.15 aggregate efficiency for a station.
## Aggregates all rooms mapped to this station.
func get_station_efficiency(station: Station) -> float:
	if layout == null:
		return _efficiency_curve(station_crew[station])
	var total_count: int = 0
	var total_optimal: int = 0
	for room: _ShipRoom in layout.rooms:
		var s: int = _ROOM_TO_STATION.get(room.type, -1)
		if s == station:
			total_count += room.crew_count
			total_optimal += room.max_crew
	if total_optimal <= 0:
		return 0.0
	return _efficiency_curve_ratio(float(total_count) / float(total_optimal))


## Room-level efficiency (delegates to ShipRoom.get_efficiency).
func get_room_efficiency(room: _ShipRoom) -> float:
	if room == null:
		return 0.0
	return room.get_efficiency()


## Core efficiency curve, input is crew_count.
func _efficiency_curve(count: int) -> float:
	if count <= 0:
		return 0.0
	var ratio: float = float(count) / float(OPTIMAL_CREW)
	return _efficiency_curve_ratio(ratio)


static func _efficiency_curve_ratio(ratio: float) -> float:
	if ratio <= 0.0:
		return 0.0
	if ratio <= 1.0:
		return 1.0 - (1.0 - ratio) * (1.0 - ratio)
	return 1.0 + 0.15 * (1.0 - exp(-(ratio - 1.0)))


# ---------------------------------------------------------------------------
# Crew Transfer (room-based)
# ---------------------------------------------------------------------------
## Move crew from one room to another. Returns actual count moved.
func transfer_crew(from_room: _ShipRoom, to_room: _ShipRoom, count: int = 1) -> int:
	if from_room == null or to_room == null:
		return 0
	var moved: int = 0
	for _i in range(count):
		if from_room.crew_count <= 0:
			break
		if to_room.crew_count >= to_room.max_crew:
			break
		from_room.crew_count -= 1
		to_room.crew_count += 1
		moved += 1
	_sync_station_crew()
	return moved


## Legacy: add crew to a station by pulling from the most-staffed other station.
func add_crew_to_station(station: int, count: int = 1) -> void:
	if layout != null:
		_room_based_add(station, count)
		return
	for _i in range(count):
		var source: int = _most_staffed_station_except(station)
		if source < 0 or station_crew[source] <= 0:
			return
		station_crew[source] -= 1
		station_crew[station] += 1


## Legacy: remove crew from a station and send to the least-staffed other station.
func remove_crew_from_station(station: int, count: int = 1) -> void:
	if layout != null:
		_room_based_remove(station, count)
		return
	for _i in range(count):
		if station_crew[station] <= 0:
			return
		var target: int = _least_staffed_station_except(station)
		if target < 0:
			return
		station_crew[station] -= 1
		station_crew[target] += 1


func _room_based_add(station: int, count: int) -> void:
	var target_rooms: Array[_ShipRoom] = _rooms_for_station(station)
	if target_rooms.is_empty():
		return
	# Find the target room with most spare capacity.
	var best_target: _ShipRoom = target_rooms[0]
	for r: _ShipRoom in target_rooms:
		if (r.max_crew - r.crew_count) > (best_target.max_crew - best_target.crew_count):
			best_target = r
	# Find source room (most-staffed, not mapped to this station).
	for _i in range(count):
		if best_target.crew_count >= best_target.max_crew:
			break
		var source: _ShipRoom = _most_staffed_room_not_in(target_rooms)
		if source == null or source.crew_count <= 0:
			break
		source.crew_count -= 1
		best_target.crew_count += 1
	_sync_station_crew()


func _room_based_remove(station: int, count: int) -> void:
	var source_rooms: Array[_ShipRoom] = _rooms_for_station(station)
	if source_rooms.is_empty():
		return
	# Find the source room with most crew.
	var best_source: _ShipRoom = source_rooms[0]
	for r: _ShipRoom in source_rooms:
		if r.crew_count > best_source.crew_count:
			best_source = r
	# Find target room (least-staffed, not mapped to this station).
	for _i in range(count):
		if best_source.crew_count <= 0:
			break
		var target: _ShipRoom = _least_staffed_room_not_in(source_rooms)
		if target == null:
			break
		if target.crew_count >= target.max_crew:
			break
		best_source.crew_count -= 1
		target.crew_count += 1
	_sync_station_crew()


func _rooms_for_station(station: int) -> Array[_ShipRoom]:
	var result: Array[_ShipRoom] = []
	if layout == null:
		return result
	for room: _ShipRoom in layout.rooms:
		if _ROOM_TO_STATION.get(room.type, -1) == station:
			result.append(room)
	return result


func _most_staffed_room_not_in(exclude: Array[_ShipRoom]) -> _ShipRoom:
	var best: _ShipRoom = null
	var best_count: int = -1
	if layout == null:
		return null
	for room: _ShipRoom in layout.rooms:
		if room in exclude:
			continue
		if room.crew_count > best_count:
			best_count = room.crew_count
			best = room
	return best


func _least_staffed_room_not_in(exclude: Array[_ShipRoom]) -> _ShipRoom:
	var best: _ShipRoom = null
	var best_count: int = 999
	if layout == null:
		return null
	for room: _ShipRoom in layout.rooms:
		if room in exclude:
			continue
		if room.crew_count < best_count and room.crew_count < room.max_crew:
			best_count = room.crew_count
			best = room
	return best


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
		if layout != null:
			_room_based_remove(over_idx, 1)
			_room_based_add(under_idx, 1)
		else:
			station_crew[over_idx] -= 1
			station_crew[under_idx] += 1


# ---------------------------------------------------------------------------
# Casualties
# ---------------------------------------------------------------------------
func apply_casualties(zone: String, damage_val: float) -> int:
	var kill_chance: float = BASE_KILL_CHANCE + maxf(0.0, damage_val - 1.0) * 0.1
	var killed: int = 0

	if layout != null and not agents.is_empty():
		var target_rooms: Array[_ShipRoom] = _rooms_for_zone(zone)
		for room: _ShipRoom in target_rooms:
			if randf() < kill_chance:
				killed += _kill_agent_in_room(room)
		# Collateral on repair rooms.
		for room: _ShipRoom in layout.rooms:
			if room.type == _ShipRoom.RoomType.CARPENTER or room.type == _ShipRoom.RoomType.PUMPS:
				if randf() < kill_chance * COLLATERAL_REPAIR_MULT:
					killed += _kill_agent_in_room(room)
		_sync_station_crew()
	elif layout != null:
		var target_rooms2: Array[_ShipRoom] = _rooms_for_zone(zone)
		for room: _ShipRoom in target_rooms2:
			if room.crew_count > 0 and randf() < kill_chance:
				room.crew_count -= 1
				total_crew -= 1
				killed += 1
		for room2: _ShipRoom in layout.rooms:
			if room2.type == _ShipRoom.RoomType.CARPENTER or room2.type == _ShipRoom.RoomType.PUMPS:
				if room2.crew_count > 0 and randf() < kill_chance * COLLATERAL_REPAIR_MULT:
					room2.crew_count -= 1
					total_crew -= 1
					killed += 1
		_sync_station_crew()
	else:
		var primary: Array[int] = _stations_for_zone(zone)
		for station_idx in primary:
			if station_crew[station_idx] > 0 and randf() < kill_chance:
				station_crew[station_idx] -= 1
				total_crew -= 1
				killed += 1
		if station_crew[Station.REPAIR] > 0 and randf() < kill_chance * COLLATERAL_REPAIR_MULT:
			station_crew[Station.REPAIR] -= 1
			total_crew -= 1
			killed += 1
	return killed


## Kill one agent in the given room. Returns 1 if killed, 0 otherwise.
func _kill_agent_in_room(room: _ShipRoom) -> int:
	for agent in agents:
		var a: _CrewAgent = agent as _CrewAgent
		if a.is_alive() and not a.is_moving() and a.current_room == room:
			a.kill()
			total_crew -= 1
			return 1
	return 0


func _rooms_for_zone(zone: String) -> Array[_ShipRoom]:
	var result: Array[_ShipRoom] = []
	if layout == null:
		return result
	match zone:
		"upper":
			for room: _ShipRoom in layout.rooms:
				if room.type == _ShipRoom.RoomType.RIGGING:
					result.append(room)
		"mid":
			for room: _ShipRoom in layout.rooms:
				if room.type == _ShipRoom.RoomType.GUN_DECK_PORT or room.type == _ShipRoom.RoomType.GUN_DECK_STBD:
					result.append(room)
		"lower":
			for room: _ShipRoom in layout.rooms:
				if room.type == _ShipRoom.RoomType.HELM:
					result.append(room)
	return result


func _stations_for_zone(zone: String) -> Array[int]:
	match zone:
		"upper":
			return [Station.RIGGING]
		"mid":
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
func process_repair(delta: float, ship_dict: Dictionary, max_hull_hp: float) -> void:
	var eff: float = get_station_efficiency(Station.REPAIR)
	if eff <= 0.001:
		return
	var dmg_state: Variant = ship_dict.get("damage_state")
	var repair_frac: float = 1.0
	if dmg_state != null:
		repair_frac = dmg_state.get_remaining_repair_fraction()
	var repair_rate: float = eff * repair_frac * BASE_REPAIR_RATE * delta
	if repair_rate <= 0.0001:
		return

	var health: float = float(ship_dict.get("health", max_hull_hp))
	if health < max_hull_hp * HULL_PRIORITY_THRESHOLD:
		var hull_repair: float = repair_rate * HULL_REPAIR_MULT
		ship_dict["health"] = minf(health + hull_repair, max_hull_hp)
		return

	var sail = ship_dict.get("sail")
	var helm = ship_dict.get("helm")
	var sail_dmg: float = sail.damage if sail != null else 0.0
	var helm_dmg: float = helm.damage if helm != null else 0.0

	# Also repair room damage if layout is present.
	var worst_room: _ShipRoom = null
	var worst_room_dmg: float = 0.0
	if layout != null:
		for room: _ShipRoom in layout.rooms:
			if room.damage > worst_room_dmg:
				worst_room_dmg = room.damage
				worst_room = room

	if sail_dmg > helm_dmg and sail_dmg > worst_room_dmg and sail_dmg > 0.01:
		sail.damage = maxf(0.0, sail.damage - repair_rate * COMPONENT_REPAIR_MULT)
	elif helm_dmg > worst_room_dmg and helm_dmg > 0.01:
		helm.damage = maxf(0.0, helm.damage - repair_rate * COMPONENT_REPAIR_MULT)
	elif worst_room != null and worst_room_dmg > 0.01:
		worst_room.damage = maxf(0.0, worst_room.damage - repair_rate * COMPONENT_REPAIR_MULT)
	elif health < max_hull_hp:
		ship_dict["health"] = minf(health + repair_rate * HULL_REPAIR_MULT, max_hull_hp)


# ---------------------------------------------------------------------------
# Network Sync
# ---------------------------------------------------------------------------
func encode_sync() -> int:
	_sync_station_crew()
	var v: int = 0
	for i in range(STATION_COUNT):
		v |= (clampi(station_crew[i], 0, 31) << (i * 5))
	v |= (clampi(total_crew, 0, 31) << 25)
	return v


func decode_sync(v: int) -> void:
	for i in range(STATION_COUNT):
		station_crew[i] = (v >> (i * 5)) & 0x1F
	total_crew = (v >> 25) & 0x1F
