## Cooperative PVE scoreboard: team-level stats with performance rating.
## All kills are team kills — no individual kill credit / kill-stealing.
class_name PveScoreboard
extends RefCounted

enum Rating { S, A, B, C, D }
const RATING_NAMES: Array[String] = ["S", "A", "B", "C", "D"]
const RATING_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.15, 1.0),   # S — gold
	Color(0.3, 0.85, 0.4, 1.0),    # A — green
	Color(0.4, 0.7, 1.0, 1.0),     # B — blue
	Color(0.75, 0.65, 0.55, 1.0),  # C — brown
	Color(0.55, 0.45, 0.40, 1.0),  # D — dark
]

## Team stats (accumulated during match).
var team_damage_dealt: float = 0.0
var team_ships_sunk: int = 0
var team_shots_fired: int = 0
var team_shots_hit: int = 0
var fleet_ships_lost: int = 0
var fleet_ships_total: int = 5
var match_duration: float = 0.0
## Per-player contributions: peer_id -> {damage, sunk, accuracy}.
var player_contributions: Dictionary = {}


func reset(total_fleet_ships: int = 5) -> void:
	team_damage_dealt = 0.0
	team_ships_sunk = 0
	team_shots_fired = 0
	team_shots_hit = 0
	fleet_ships_lost = 0
	fleet_ships_total = total_fleet_ships
	match_duration = 0.0
	player_contributions.clear()


## Call each frame to track match time.
func tick(delta: float) -> void:
	match_duration += delta


## Record a ship kill (enemy sunk by our team).
func record_kill() -> void:
	team_ships_sunk += 1


## Record shots fired/hit from the base scoreboard data.
func sync_from_scoreboard(scoreboard: Dictionary, player_fleet_peer_ids: Array[int]) -> void:
	team_damage_dealt = 0.0
	team_shots_fired = 0
	team_shots_hit = 0
	for pid in player_fleet_peer_ids:
		var entry: Dictionary = scoreboard.get(pid, {})
		var dmg: float = float(entry.get("damage_dealt", 0.0))
		var fired: int = int(entry.get("shots_fired", 0))
		var hit: int = int(entry.get("shots_hit", 0))
		team_damage_dealt += dmg
		team_shots_fired += fired
		team_shots_hit += hit
		player_contributions[pid] = {
			"damage": dmg,
			"shots_fired": fired,
			"shots_hit": hit,
		}


## Fleet health fraction: how much of the player fleet survived.
func fleet_health_fraction() -> float:
	if fleet_ships_total <= 0:
		return 0.0
	return float(fleet_ships_total - fleet_ships_lost) / float(fleet_ships_total)


## Team accuracy percentage.
func accuracy_percent() -> float:
	if team_shots_fired <= 0:
		return 0.0
	return float(team_shots_hit) / float(team_shots_fired) * 100.0


## Compute performance rating based on fleet health + clear time.
func compute_rating() -> int:
	var hp_frac: float = fleet_health_fraction()
	var time_score: float = 1.0
	# Bonus for fast clears (under 3 minutes = 180s).
	if match_duration < 120.0:
		time_score = 1.2
	elif match_duration < 180.0:
		time_score = 1.1
	elif match_duration > 360.0:
		time_score = 0.8
	elif match_duration > 480.0:
		time_score = 0.6

	var composite: float = hp_frac * time_score

	if composite >= 0.95:
		return Rating.S
	elif composite >= 0.75:
		return Rating.A
	elif composite >= 0.50:
		return Rating.B
	elif composite >= 0.25:
		return Rating.C
	return Rating.D


func rating_name() -> String:
	return RATING_NAMES[compute_rating()]


func rating_color() -> Color:
	return RATING_COLORS[compute_rating()]


## Format match time as M:SS.
func format_time() -> String:
	var total_s: int = int(floor(match_duration))
	var mins: int = int(floor(float(total_s) / 60.0))
	var secs: int = total_s - mins * 60
	return "%d:%02d" % [mins, secs]
