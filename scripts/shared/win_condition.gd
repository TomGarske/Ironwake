## Pluggable win-condition base class.
## Subclasses override `check()` to implement PVP, PVE elimination, etc.
class_name WinCondition
extends RefCounted


## Return value from check():
##   -2  = match still in progress
##   -1  = draw
##   0+  = player-index of winner
const PLAYING: int = -2
const DRAW: int = -1


## Called each frame (or after a kill) by the arena.
## Must return PLAYING, DRAW, or a winner index.
func check(_players: Array, _scoreboard: Dictionary, _match_timer: float) -> int:
	return PLAYING


# ─────────────────────────────────────────────────────────────────────────────
# PVP: first to KILL_TARGET kills, or most kills at MATCH_TIME_LIMIT.
# ─────────────────────────────────────────────────────────────────────────────
class PvpKillWin extends WinCondition:
	var kill_target: int = 10
	var match_time_limit: float = 300.0

	func check(players: Array, scoreboard: Dictionary, match_timer: float) -> int:
		# Kill target
		for i in range(players.size()):
			var pid: int = int(players[i].get("peer_id", i))
			var kills: int = int(scoreboard.get(pid, {}).get("kills", 0))
			if kills >= kill_target:
				return i
		# Time limit
		if match_timer >= match_time_limit:
			var top_kills: int = -1
			var top_indices: Array[int] = []
			for i in range(players.size()):
				var pid: int = int(players[i].get("peer_id", i))
				var kills: int = int(scoreboard.get(pid, {}).get("kills", 0))
				if kills > top_kills:
					top_kills = kills
					top_indices = [i]
				elif kills == top_kills:
					top_indices.append(i)
			if top_indices.size() == 1:
				return top_indices[0]
			return DRAW
		return PLAYING


# ─────────────────────────────────────────────────────────────────────────────
# PVE Elimination: a fleet loses when more than half its ships are sunk.
# Winner is the team whose enemies got eliminated.
# ─────────────────────────────────────────────────────────────────────────────
class PveEliminationWin extends WinCondition:
	## FleetRegistry reference — must be set before first check().
	var fleet_registry: FleetRegistry = null
	## Fraction of fleet that must be sunk to trigger rout (default >50%).
	var elimination_threshold: float = 0.5

	func check(players: Array, _scoreboard: Dictionary, _match_timer: float) -> int:
		if fleet_registry == null or not fleet_registry.has_fleets():
			return PLAYING
		# Check each fleet: if alive count <= floor(size * (1 - threshold)), that fleet is eliminated.
		var eliminated_teams: Dictionary = {}  # team -> true
		for fid in fleet_registry.get_fleet_ids():
			var total: int = fleet_registry.get_fleet_size(fid)
			if total <= 0:
				continue
			var alive: int = fleet_registry.get_fleet_alive_count(fid, players)
			var min_alive: int = ceili(float(total) * (1.0 - elimination_threshold))
			if alive <= min_alive:
				var team: int = fleet_registry.get_team(fleet_registry._fleets[fid]["ship_indices"][0]) if not fleet_registry._fleets[fid]["ship_indices"].is_empty() else -1
				eliminated_teams[team] = true
		if eliminated_teams.is_empty():
			return PLAYING
		# Find winning team: the team that is NOT eliminated.
		# For a two-team game, the surviving team wins.
		var all_teams: Dictionary = {}
		for fid in fleet_registry.get_fleet_ids():
			var fleet_data: Dictionary = fleet_registry._fleets.get(fid, {})
			var team: int = int(fleet_data.get("team", -1))
			if team >= 0:
				all_teams[team] = true
		var surviving_teams: Array = []
		for team in all_teams.keys():
			if not eliminated_teams.has(team):
				surviving_teams.append(team)
		if surviving_teams.size() == 1:
			# Return the first ship index of the surviving team as winner.
			var winning_team: int = int(surviving_teams[0])
			for fid in fleet_registry.get_fleet_ids():
				var fleet_data: Dictionary = fleet_registry._fleets.get(fid, {})
				if int(fleet_data.get("team", -1)) == winning_team:
					var indices: Array = fleet_data.get("ship_indices", [])
					if not indices.is_empty():
						return int(indices[0])
			return 0
		if surviving_teams.is_empty():
			return DRAW
		return PLAYING
