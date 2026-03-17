# REQ-05: Roguelike Progression
**Chrimera: Bioforge Run**

## Overview
Chrimera uses **permadeath-with-meta-progression** roguelike structure. Each run is a self-contained escape attempt; failure results in a new run from the start. However, progress persists in the form of **meta-upgrades** (unlocked scientist archetypes, increased lives pool, additional tool slots) and **daily challenge seeds** that offer fixed-seed playthroughs for leaderboard competition.

---

## Run Structure

### Run Composition
- **Levels per run:** 3–5 levels (randomized count per run seed).
- **Level selection:** Fixed pool of hand-crafted and procedurally-varied levels. Order is randomized based on run seed (all players in cooperative multiplayer share the same seed).
- **Difficulty escalation:** Each level increases entity spawn rate, variety, and contamination density.
- **Duration:** Typical run (1 player): 15–30 minutes. (4 players with teamwork can finish in 12–20 minutes.)

### Level Sequence Example

```
Run 1:
├─ Level 1 (Research Lab A) – 2 entity types, 8 spawns, low contamination
├─ Level 2 (Storage Vault B) – 3 entity types, 12 spawns, medium contamination
├─ Level 3 (Server Room C) – 4 entity types, 18 spawns, high contamination
├─ Level 4 (Containment Breach) – 5 entity types, 24 spawns, critical contamination
└─ Exit (surface)

Run 2 (different seed):
├─ Level 1 (Server Room A) – different arrangement
├─ Level 2 (Biohazard Zone B)
├─ Level 3 (Lab Sector C)
└─ Exit (surface)
```

---

## Between-Level Progression Moments

### Upgrade/Tool Selection Screen

After completing a level (except the final level), players see:

```
┌─────────────────────────────────────┐
│       LEVEL COMPLETE                │
│   15 enemies slain, 2 minutes       │
│     Lives pool: 3/3                 │
├─────────────────────────────────────┤
│  Choose one upgrade for next level:  │
├─────────────────────────────────────┤
│  [1] NEW TOOL: Grapple Spike        │
│      Mobility: swing 3m, reach high │
│      platforms                      │
│                                     │
│  [2] ARCHETYPE UPGRADE: Virologist  │
│      Next tool cooldowns -15%       │
│                                     │
│  [3] RESOURCE: +1 Life              │
│      Increase pool to 4/4           │
├─────────────────────────────────────┤
│   Press A/D to select, Y to confirm │
│   Auto-advance in 15 seconds...      │
└─────────────────────────────────────┘
```

### Upgrade Categories

| Category | Effect | Example |
|----------|--------|---------|
| **New Tool** | Add a random tool to the available pool (not immediately equipped, picked up during level). | "Grapple Spike," "EMP Grenade," "Sonic Emitter." |
| **Archetype Ability** | Unlock or enhance an archetype bonus (applies to current and future runs). | "Virologist: tool cooldown -15%," "Engineer: EMP damage +20%." |
| **Resource Bonus** | Increase starting lives, tool slots, or consumable count. | "+1 Starting Life," "Tool Slot #3 Unlocked." |
| **Meta-Progression** | One-time unlock that carries forward. | "Unlock Chimera Host encounter in future runs." |

### Selection Mechanics
- **Duration:** 15 seconds per screen.
- **Auto-advance:** If no selection within 15s, the first option (top) is selected.
- **Default Fallback:** If all options are unavailable (rare), grant "+1 Life."
- **Cooperative:** All players see the same three options and vote (majority rules). If no consensus after 12s, top option wins.

---

## Permadeath and Meta-Progression

### Run Failure
When the shared lives pool reaches 0 and a player dies:
1. **Immediate state:** RUN_FAILED (see REQ-02).
2. **Results screen:** Shows run stats (time, kills, tools used, furthest level).
3. **Meta-progression application:** Any unlocks earned during the run (even failed runs) are applied.
4. **Leaderboard:** Run time and kill count posted to SteamManager leaderboard (marked as failed).

### Persistent Meta-Progression

Meta-progression is stored in a local persistent file and synchronized via SteamManager cloud save:

```gdscript
class_name MetaProgressionState
extends Resource

# Persistent data across all runs
var unlocked_archetypes: Array[String] = []
var lives_pool_bonus: int = 0          # increments in +1 steps
var tool_slot_unlock_level: int = 2    # 2 (default), 3 (unlocked), etc.
var discovered_tools: Array[String] = []
var total_runs_completed: int = 0
var total_kills: int = 0
var playtime_seconds: int = 0

# Milestone thresholds
var milestone_kills_for_archetype: int = 50
var milestone_runs_for_lives: int = 3
var milestone_kills_for_tool_slot: int = 100

func save_to_disk():
    var save_path = "user://chrimera_meta.tres"
    ResourceSaver.save(self, save_path)

func load_from_disk():
    var save_path = "user://chrimera_meta.tres"
    if ResourceLoader.exists(save_path):
        var loaded = ResourceLoader.load(save_path)
        unlocked_archetypes = loaded.unlocked_archetypes
        # ... copy all fields
        return true
    return false

func apply_run_completion(run_kills: int, levels_completed: int):
    total_kills += run_kills
    total_runs_completed += 1

    # Check milestones
    if total_kills >= milestone_kills_for_archetype:
        unlock_next_archetype()

    if total_runs_completed >= milestone_runs_for_lives:
        increase_lives_pool()

    save_to_disk()
```

---

## Scientist Archetypes

### Archetype System
Each run, before entering the first level, the player (or a cooperative group) selects a **Scientist Archetype**. This archetype grants passive bonuses and unlocks tool-specific upgrades. Archetypes persist and unlock via meta-progression.

### Starting Archetypes (Unlocked at Game Start)

#### 1. Virologist
- **Identity:** Biology specialist. Favors chemical and biological tools.
- **Passive Bonus:** Tool cooldowns -10%.
- **Tool Bonus:** Acidic Compound, Toxin Injector, Stasis Gel deal +15% damage.
- **Unlock:** Available from start.

#### 2. Engineer
- **Identity:** Tech specialist. Favors EMP and electronic tools.
- **Passive Bonus:** Electronic doors open +50% faster. Contamination zones deal -20% damage (filter tech).
- **Tool Bonus:** EMP Grenade radius +1m. Keycard Cracker unlimited uses.
- **Unlock:** Available from start.

#### 3. Security
- **Identity:** Combat-trained. Favors kinetic and defensive tools.
- **Passive Bonus:** Melee damage +10 (instead of 5). Health +5 (6 starting instead of 1).
- **Tool Bonus:** Sonic Emitter cooldown -3s. Barrier Foam duration +3s.
- **Unlock:** Unlocked after 50 total kills (meta-progression).

#### 4. Lab Director
- **Identity:** Leader. Favors team bonuses and coordination.
- **Passive Bonus:** Nearby allies gain +15% speed and cooldown reduction (extends proximity range to 4m).
- **Tool Bonus:** Scanner reveals all entity types and health. Stabilization Serum applies to nearby allies too.
- **Unlock:** Unlocked after 3 run completions (meta-progression).

#### 5. Escape Artist (Elite, Post-Game Unlock)
- **Identity:** Specialist in evasion and utility.
- **Passive Bonus:** Movement speed +15%. Slide cooldown -50% (0.5s).
- **Tool Bonus:** Lateral Thruster gains +1 charge (4 total). Grapple Spike cable extends to 5m.
- **Unlock:** Unlocked after defeating Chimera Host or 10 completed runs (meta-progression).

### Archetype Selection per Run
```gdscript
func select_archetype_for_run(archetype_name: String) -> Archetype:
    if archetype_name in meta_progression.unlocked_archetypes:
        return archetypes[archetype_name]
    else:
        # Default to first available
        return archetypes["Virologist"]
```

---

## Lives Pool and Difficulty Scaling

### Starting Lives
- **Default:** 3 lives per run.
- **Per +1 Meta-Unlock:** Additional life unlocked every 3 completed runs (up to max 6 lives).
- **Cooperative Modifier:** If 2+ players, lives pool starts at +1 (4 lives instead of 3). This accounts for the increased chaos of multiplayer.

### Entity Density Scaling
Each level's entity count is determined by:
```
base_entity_count = [8, 12, 18, 24, 32][level_index]
difficulty_multiplier = 1.0 + (meta_progression.total_runs_completed * 0.05)
player_count_multiplier = 1.0 + (player_count - 1) * 0.3

final_entity_count = ceil(
    base_entity_count * difficulty_multiplier * player_count_multiplier
)
```

Example: Level 3, 2 players, 5 completed runs:
```
18 * (1.0 + 0.25) * (1.0 + 0.3) = 18 * 1.25 * 1.3 = 29 entities
```

---

## Run Seed System (Cooperative Multiplayer)

### Synchronized Procedural Generation
All players in a cooperative multiplayer run share the same **run seed**. This ensures:
- Same level order
- Same entity spawns
- Same tool pickup locations
- Same contamination zone patterns
- Deterministic leaderboard fairness

```gdscript
class RunSeed:
    var seed_value: int
    var level_order: Array[String]
    var level_configs: Array[LevelConfig]  # entity count, tool spawn, etc.

    func _init(base_seed: int):
        seed_value = base_seed
        randomize_with_seed(seed_value)
        generate_level_order()

    func generate_level_order():
        var level_pool = ["lab_a", "lab_b", "storage_vault", "server_room", "containment_breach"]
        level_order = []
        var run_length = randi_range(3, 5)
        for i in range(run_length):
            var level = level_pool[randi() % level_pool.size()]
            level_order.append(level)
            level_pool.erase(level)  # Don't repeat
            if level_pool.is_empty():
                level_pool = ["lab_a", "lab_b", "storage_vault", "server_room", "containment_breach"]
```

### Seed Generation
- **Standard Run:** Seed = hash(player_count + current_timestamp + meta_progression.runs_completed).
- **Daily Challenge:** Seed = fixed value per day (e.g., 20260315 for March 15, 2026). Same seed for all players worldwide on that day.

---

## Daily Challenge Runs

### Daily Challenge Rules
- **Schedule:** New challenge every 24 hours at 00:00 UTC.
- **Fixed Seed:** All players compete using the same seed (same level order, spawns, tool pickups).
- **Leaderboard:** Time and kill count posted to a global leaderboard (SteamManager integration).
- **Rewards:** Top 100 get cosmetic rewards or in-game currency (future content).
- **Difficulty:** "Challenge" difficulty (entity count +20%, contamination spread faster).

### Daily Challenge UI
```
┌──────────────────────────────────┐
│     DAILY CHALLENGE               │
│   March 15, 2026 (Seed: 20260315) │
├──────────────────────────────────┤
│  Leaderboard:                     │
│  1. PlayerA – 8:42, 156 kills    │
│  2. PlayerB – 9:03, 149 kills    │
│  3. PlayerC – 9:15, 143 kills    │
│  ...                              │
├──────────────────────────────────┤
│  [START DAILY CHALLENGE]           │
│  [VIEW MY BEST RUN]                │
└──────────────────────────────────┘
```

---

## MVP Build Meta-Progression

For MVP (minimum viable product), meta-progression is **stubbed** with minimal unlocks:

### MVP Meta Unlocks
- **Archetype 1 Unlock:** After first run completion, unlock "Engineer" archetype (in addition to starting "Virologist").
- **Lives Pool +1:** After 2 completed runs, starting lives increase from 3 to 4.
- **Tool Slot #3:** Deferred (post-MVP). Tool slots remain at 2 for MVP.
- **Tool Discovery:** MVP tools remain fixed (3 starting tools + 5 mid-run discovery options). No infinite pool.

### MVP Persistence
- Meta state saved to `user://chrimera_meta_mvp.tres` (simple Resource file).
- No cloud sync during MVP (added post-MVP when SteamManager integration is full).

---

## Escalation Timeline per Level

### Entity Spawn Escalation
Entity spawning follows a three-phase progression within each level:

| Phase | Duration | Spawn Rate | Entity Types | Purpose |
|-------|----------|------------|--------------|---------|
| **Exploration** | 0–60s (level 1), 0–45s (level 2+) | 1 entity per 10s | Crawlers, Lurkers (1–2 types) | Safe navigation window. |
| **Pressure** | 60–120s | 1 entity per 7s | Add Spreaders, Amalgams | Escalation warning. |
| **Crisis** | 120s+ | 1 entity per 5s | All types active, Chimera Host possible | Maximum pressure, exit imperative. |

### Contamination Spread per Level

```
Level 1: 10% per minute
Level 2: 15% per minute
Level 3: 20% per minute
Level 4: 25% per minute
Final:   30% per minute

Total facility contamination = sum of all levels + (player count * 5%)
```

---

## Testing Checkpoints (MVP)

- [ ] First run completion unlocks second archetype.
- [ ] Upgrade screen displays 3 options after level 1.
- [ ] Selection auto-advances after 15s.
- [ ] Meta-progression file saves and loads correctly.
- [ ] Second run shows increased entity count (difficulty scaling).
- [ ] Cooperative run sync: both players see same level order and entity spawns.

---

## Implementation Notes

1. **Run Seed Determinism:** Use `randomize_with_seed()` before any procedural generation; each system consumes seeds in deterministic order.
2. **Meta-Progression Threshold:** Milestones should be tuned by playtesting. Initial guesses: 50 kills for archetype, 3 runs for lives, 100 kills for tool slot.
3. **Daily Challenge Time Window:** Use a cron-like trigger in GameManager to detect day boundary and refresh daily seed.
4. **Leaderboard Sync:** SteamManager handles upload/download. RunController should emit `run_completed` signal with stats when run finishes.
5. **Difficulty Cap:** Avoid runaway difficulty scaling. Cap multiplier at 2.0x even if player has 100 completed runs.

---

## Next Steps
- **REQ-06:** CRISPR entity AI (behavior trees, spawn patterns).
- **REQ-07:** Levels and presentation (tilemap structure, VFX, contamination shader).
