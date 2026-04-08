## Fleet/team registry: single source of truth for friend-or-foe across the codebase.
## Default behaviour (no fleets registered) treats every ship as hostile to every
## other — preserving PVP semantics unchanged.
class_name FleetRegistry
extends RefCounted


## fleet_id -> { ship_indices: Array[int], team: int, color: Color }
var _fleets: Dictionary = {}
## Quick reverse lookup: player_index -> fleet_id (-1 = unregistered)
var _index_to_fleet: Dictionary = {}


func clear() -> void:
	_fleets.clear()
	_index_to_fleet.clear()


## Register a fleet.  `team` groups multiple fleets on the same side (e.g. all
## player fleets share team 0; all enemy fleets share team 1).
func register_fleet(fleet_id: int, ship_indices: Array[int], team: int, color: Color = Color.WHITE) -> void:
	_fleets[fleet_id] = {
		"ship_indices": ship_indices.duplicate(),
		"team": team,
		"color": color,
	}
	for idx in ship_indices:
		_index_to_fleet[idx] = fleet_id


## Remove a ship index from its fleet (e.g. when sunk and removed from play).
func remove_ship(ship_index: int) -> void:
	var fid: int = int(_index_to_fleet.get(ship_index, -1))
	if fid == -1:
		return
	var fleet: Dictionary = _fleets.get(fid, {})
	var indices: Array = fleet.get("ship_indices", [])
	indices.erase(ship_index)
	_index_to_fleet.erase(ship_index)


## Returns the fleet_id a ship belongs to, or -1 if unregistered.
func get_fleet_id(ship_index: int) -> int:
	return int(_index_to_fleet.get(ship_index, -1))


## Returns the team number for a ship, or -1 if unregistered.
func get_team(ship_index: int) -> int:
	var fid: int = get_fleet_id(ship_index)
	if fid == -1:
		return -1
	return int(_fleets.get(fid, {}).get("team", -1))


## True when both ships are on the same team.  If either is unregistered
## (no fleet assigned) this returns **false** — unregistered ships are hostile
## to everyone, which preserves legacy PVP where no fleets exist.
func are_allies(idx_a: int, idx_b: int) -> bool:
	var team_a: int = get_team(idx_a)
	var team_b: int = get_team(idx_b)
	if team_a == -1 or team_b == -1:
		return false
	return team_a == team_b


## Returns indices of all ships hostile to `ship_index`.
## If no fleet is registered for the ship, returns all OTHER indices from the
## provided `all_indices` array (PVP fallback).
func get_enemies_of(ship_index: int, all_indices: Array[int]) -> Array[int]:
	var my_team: int = get_team(ship_index)
	var enemies: Array[int] = []
	for idx in all_indices:
		if idx == ship_index:
			continue
		if my_team == -1:
			# Unregistered: everyone else is hostile.
			enemies.append(idx)
		elif get_team(idx) != my_team:
			enemies.append(idx)
	return enemies


## Count of alive ships in a fleet (caller passes the players array so the
## registry stays decoupled from arena internals).
func get_fleet_alive_count(fleet_id: int, players: Array) -> int:
	var fleet: Dictionary = _fleets.get(fleet_id, {})
	var indices: Array = fleet.get("ship_indices", [])
	var alive: int = 0
	for idx in indices:
		if idx >= 0 and idx < players.size():
			if bool(players[idx].get("alive", true)):
				alive += 1
	return alive


## Total ships originally in the fleet.
func get_fleet_size(fleet_id: int) -> int:
	return int(_fleets.get(fleet_id, {}).get("ship_indices", []).size())


## All registered fleet IDs.
func get_fleet_ids() -> Array:
	return _fleets.keys()


## Convenience: true when fleets have been registered (PVE mode).
func has_fleets() -> bool:
	return not _fleets.is_empty()
