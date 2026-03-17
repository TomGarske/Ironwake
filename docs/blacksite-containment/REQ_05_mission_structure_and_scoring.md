# REQ_05: Mission Structure and Scoring
**Waves, Difficulty Scaling, and Debrief**

## Mission Overview

A mission is a series of **waves** of escalating difficulty. Each wave spawns a set number of escapees of various types; players must destroy them before breaches occur. The mission ends when all waves are cleared (success) or the facility's containment integrity reaches zero (failure).

---

## Wave Structure

**Wave Composition** (data-driven via JSON/resource):

```json
{
  "wave_1": {
    "name": "Initial Assessment",
    "duration_seconds": 60,
    "escapee_count": 20,
    "composition": {
      "basic_runner": 20,
      "evader": 0,
      "tank": 0,
      "swarm": 0,
      "elite": 0
    },
    "spawn_rate": 0.333,
    "difficulty_multiplier": 1.0,
    "elite_chance": 0.0
  },
  "wave_2": {
    "name": "Escalation",
    "duration_seconds": 45,
    "escapee_count": 30,
    "composition": {
      "basic_runner": 20,
      "evader": 8,
      "tank": 0,
      "swarm": 2,
      "elite": 0
    },
    "spawn_rate": 0.667,
    "difficulty_multiplier": 1.15,
    "elite_chance": 0.05
  },
  "wave_3": {
    "name": "Critical Breach",
    "duration_seconds": 40,
    "escapee_count": 40,
    "composition": {
      "basic_runner": 20,
      "evader": 10,
      "tank": 3,
      "swarm": 5,
      "elite": 2
    },
    "spawn_rate": 1.0,
    "difficulty_multiplier": 1.35,
    "elite_chance": 0.10
  }
}
```

**Wave Mechanics**:
1. Wave begins; escapees spawn at intervals matching `spawn_rate`.
2. Players destroy escapees as they arrive.
3. Wave ends when all escapees in the queue are spawned AND all living escapees are destroyed.
4. Brief 2-second grace period (no new spawns), then next wave begins or mission ends.

**Difficulty Scaling Per Wave**:
- `difficulty_multiplier`: Scales all escapee stats (health, speed, damage dealt by them if they attack players). 1.0 baseline.
- `elite_chance`: Probability (0–1) that each spawned escapee is "elite" (see REQ_06 for elite traits).
- `spawn_rate`: Escalates over waves to create increasing pressure.

---

## Scoring System

### Core Score Components

**1. Breach Prevention Score** (per wave):
- **Formula**: `100 points * (1.0 - breach_count / baseline_breach_tolerance)`
- **Baseline Tolerance**: 1 breach per 10 escapees. If wave has 20 escapees, tolerance is 2 breaches before score penalty.
- **Example**: Wave 1 has 20 escapees (tolerance = 2 breaches). If 0 breaches occur, 100 points awarded. If 1 breach, 100 * (1 - 1/2) = 50 points. If 2 breaches, 0 points.

**2. Kill Count Bonus**:
- **Formula**: `escapees_destroyed * 10 + (perfect_accuracy_bonus * 25)`
- **Perfect Accuracy Bonus**: +25 per wave if 0 overheats occurred during wave (charge laser discipline).
- **Example**: Destroy 25 escapees with 0 overheats: 250 + 25 = 275 points.

**3. Time Bonus** (per wave):
- **Formula**: `max(0, (wave_time_remaining / wave_total_time) * 100)`
- **Logic**: If wave takes 30 seconds of a 60-second window, remaining time is 30 seconds → 50% bonus.
- **Example**: Complete wave in 40s of 60s window: (20 / 60) * 100 = 33 points.

**4. Cooperation Bonus** (shared across team):
- **Assist Tracking**: When drone A damages escapee and drone B finishes it, drone B gets +15 points (assist bonus).
- **Revive Bonus** (future mechanic, deferred): +50 points if teammate picked up after going down.
- **Orbital Strike Coordination**: +20 points bonus if orbital strike hits 3+ escapees in single blast (encouraging group tactics).
- **Example**: 4-player team with 3 assists and 1 coordinated orbital strike: +60 + 20 = +80 bonus points total.

### Score Calculation Formula

```gdscript
# ScoreCalculator.gd (excerpt)
class_name ScoreCalculator
extends Node

var total_score: int = 0
var wave_scores: Array[int] = []

func calculate_wave_score(wave_index: int, wave_data: Dictionary, game_state: Dictionary) -> int:
	var breach_count = game_state.breaches_this_wave
	var escapees_destroyed = game_state.escapees_destroyed
	var overheats = game_state.player_overheats
	var time_remaining = game_state.wave_time_remaining
	var assists = game_state.player_assists
	var orbital_hits = game_state.orbital_strike_hits

	# Breach prevention
	var tolerance = int(wave_data.escapee_count / 10.0)
	var breach_score = int(100.0 * max(0, 1.0 - float(breach_count) / tolerance))

	# Kill count
	var accuracy_bonus = 25 if overheats == 0 else 0
	var kill_score = escapees_destroyed * 10 + accuracy_bonus

	# Time bonus
	var time_ratio = float(time_remaining) / wave_data.duration_seconds
	var time_score = int(time_ratio * 100)

	# Cooperation bonus
	var assist_bonus = assists * 15
	var orbital_bonus = 20 if orbital_hits >= 3 else 0

	var wave_total = breach_score + kill_score + time_score + assist_bonus + orbital_bonus
	total_score += wave_total
	wave_scores.append(wave_total)

	return wave_total
```

### Final Mission Score

**Multipliers Applied at Mission End**:
- **Difficulty Multiplier**: If played on higher difficulty (if difficulty selection exists), final score * 1.2.
- **Team Size Scaling**: Solo: * 1.0. 2-3 players: * 0.95 (balanced for smaller team). 4 players: * 1.0. 5+ players: * 0.9 (score spread across more players).

**Final Score Display**:
```
=== MISSION DEBRIEF ===
Wave 1: 350 points
Wave 2: 425 points
Wave 3: 510 points
Breach Prevention: -50 (1 breach)
Cooperation Bonus: +60
SUBTOTAL: 1,295 points
Team Size Multiplier (4 players): x1.0
FINAL SCORE: 1,295 points
```

---

## Mission Integrity System

**Overview**: A shared meter representing the facility's containment integrity. Each breach reduces integrity; if integrity reaches zero, mission fails.

**Mechanics**:

| Metric | Value | Notes |
|--------|-------|-------|
| Max Integrity | 100 points | Starting level |
| Breach Cost | 25 points | Per breach event |
| Tolerance per Wave | ceil(escapee_count / 10) | e.g., Wave 1 (20 escapees) allows 2 breaches |
| Failure Threshold | 0 points | Mission ends in failure |

**Breach Event**: When an escapee reaches the perimeter breach zone:
1. The escapee is removed from arena.
2. Integrity meter decreases by 25 points.
3. Klaxon alarm sounds; red screen flash (brief).
4. All drones receive notification: "BREACH EVENT - Integrity: 75%".
5. Game continues if integrity > 0; otherwise, mission failed.

**Example Scenario** (4-player, 3-wave mission):
- Wave 1: 3 breaches occur (cost: 75 points). Integrity = 25.
- Wave 2: 1 breach occurs (cost: 25 points). Integrity = 0.
- **Mission Failed**: Game transitions to DEBRIEF showing "Containment Breached".

---

## End States

### Mission Complete (Success)

**Conditions**:
- All waves cleared (escapees spawned and destroyed).
- Integrity > 0 (no critical containment failure).

**Debrief Display**:
- "Mission Successful" header (green).
- Wave-by-wave score breakdown.
- Total score calculation with multipliers.
- Top performers highlighted (e.g., "Most Kills: Player A").
- Statistics: total escapees destroyed, total breaches prevented, total assists.

### Partial Breach (Compromised Success)

**Conditions**:
- All waves cleared.
- Integrity > 0 but reduced due to breaches (e.g., integrity = 40%).

**Debrief Display**:
- "Mission Complete - Partial Containment Loss" header (yellow).
- Integrity status shown prominently.
- Score calculation includes integrity multiplier penalty (see below).

### Mission Failed (Critical Breach)

**Conditions**:
- Integrity reduced to 0 before all waves cleared.

**Debrief Display**:
- "Mission Failed - Containment Breached" header (red).
- Final wave progress (e.g., "3/40 escapees destroyed in Wave 3").
- Integrity loss summary.
- Score calculated as 0 (or minimal mercy points for time survived).

---

## Debrief Screen

Displayed after mission end (success or failure).

**Layout** (CanvasLayer HUD):

```
┌─────────────────────────────────────────────┐
│ BLACKSITE CONTAINMENT - MISSION DEBRIEF      │
├─────────────────────────────────────────────┤
│ Status: MISSION SUCCESSFUL                  │
│ Integrity Maintained: 60%                    │
│                                              │
│ ┌─ Wave 1: Initial Assessment ───────────┐  │
│ │ Escapees Destroyed: 20/20              │  │
│ │ Score: 350 points                      │  │
│ │ Breaches: 0                            │  │
│ └────────────────────────────────────────┘  │
│                                              │
│ ┌─ Wave 2: Escalation ──────────────────┐  │
│ │ Escapees Destroyed: 30/30              │  │
│ │ Score: 425 points                      │  │
│ │ Breaches: 1                            │  │
│ └────────────────────────────────────────┘  │
│                                              │
│ ┌─ Wave 3: Critical Breach ──────────────┐  │
│ │ Escapees Destroyed: 40/40              │  │
│ │ Score: 510 points                      │  │
│ │ Breaches: 0                            │  │
│ └────────────────────────────────────────┘  │
│                                              │
│ ┌─ Team Stats ───────────────────────────┐  │
│ │ Top Killer: Player_A (45 kills)       │  │
│ │ Most Assists: Player_C (8 assists)    │  │
│ │ Accuracy (no overheats): 100%         │  │
│ └────────────────────────────────────────┘  │
│                                              │
│ FINAL SCORE: 1,285 points                   │
│                                              │
│ [NEXT MISSION]  [RETURN TO LOBBY]           │
└─────────────────────────────────────────────┘
```

**Data Displayed**:
1. **Mission Status**: Success/Failure/Partial (color-coded).
2. **Integrity Remaining**: Bar + percentage.
3. **Per-Wave Breakdown**: Escapees, score, breaches.
4. **Team Statistics**:
   - Total escapees destroyed (sum).
   - Total breaches (sum).
   - Cooperation metrics (assists, revives if enabled).
   - Accuracy (overheats avoided).
5. **Final Score**: Large, prominent display.
6. **Next Actions**: "Next Mission" or "Return to Lobby" buttons.

---

## Difficulty Scaling by Player Count

The game adjusts wave parameters based on player count:

| Player Count | Spawn Rate Multiplier | Health Multiplier | Breach Tolerance | Notes |
|--------------|----------------------|--------------------|-------------------|-------|
| 1            | 0.7x                 | 0.8x              | +1 (lenient)     | Solo challenge |
| 2–3          | 0.85x                | 0.9x              | +0                | Small team |
| 4            | 1.0x                 | 1.0x              | +0                | Baseline |
| 5–6          | 1.3x                 | 1.2x              | -1 (strict)      | Large team |
| 7–8          | 1.6x                 | 1.5x              | -1 (strict)      | Full squad |

**Rationale**: Solo and small teams spawn fewer, weaker escapees to keep the experience fun. Larger teams face more density and tougher enemies to maintain challenge.

---

## Cooperative Mechanics

### Assist System

**Definition**: An assist is recorded when drone A damages an escapee and drone B (or the same drone after a time gap) delivers the final blow to destroy it.

**Reward**: +15 points per assist.

**Implementation**:
```gdscript
# EscapeeEntity.gd (excerpt)
var last_damage_sources: Array[String] = []  # Drone names in order of damage
var total_damage: float = 0.0

func take_damage(damage: float, source_drone_id: String) -> void:
	if source_drone_id not in last_damage_sources:
		last_damage_sources.append(source_drone_id)
	total_damage += damage
	if health <= 0:
		destroy()

func destroy() -> void:
	# First source gets kill credit
	if last_damage_sources.size() > 0:
		record_kill(last_damage_sources[0])
	# All others get assist credit
	for i in range(1, last_damage_sources.size()):
		record_assist(last_damage_sources[i])
```

### Orbital Strike Coordination Bonus

**Definition**: If a single orbital strike hits 3 or more escapees, all drones contributing to that strike (by damaging the targets before the strike) get a +20 bonus.

**Mechanics**: Track escapee health before strike; compare health after. If 3+ escapees damaged, distribute bonus to nearby drones.

---

## Testing Scenarios

| Scenario | Wave 1 | Wave 2 | Expected Outcome |
|----------|--------|--------|------------------|
| Perfect (0 breaches, full speed, 0 overheats) | 100 + 50 + 50 = 200 | 150 + 75 + 75 = 300 | High score, success |
| Sloppy (2 breaches, overheats) | 50 + 30 + 20 = 100 | 0 + 25 + 0 = 25 | Low score, success |
| Catastrophic (4 breaches) | Integrity at 0 | — | Mission failed |
| Solo 1-player | Wave difficulty 0.7x, health 0.8x | — | Balanced solo challenge |
| 8-player squad | Wave difficulty 1.6x, health 1.5x | — | Hard squad challenge |

---

**Implementation Notes:**
- All wave data is stored in a JSON file or Godot resource; edit without touching code.
- Score calculations happen on the host and are broadcast to all clients after mission end.
- Debrief screen persists for 10 seconds before auto-advancing (with "Next Mission" or "Quit" input); don't force-close immediately.
- Consider adding "High Score" tracking and leaderboard integration (future feature, deferred to post-MVP).
