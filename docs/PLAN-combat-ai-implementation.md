# Implementation Plan — Combat Evaluator, AI Bot, Local Sim

**Date:** 2026-03-29
**Covers:** req-combat-loop-v1.md, req-ai-naval-bot-v1.md, req-local-sim-v1.md

---

## Architecture Context

The current codebase uses a **dictionary-per-ship** model inside a flat `_players` array on the arena node. Ships are NOT scene-tree Node2D objects — they're dictionary entries with `wx`, `wy`, `dir`, `health`, `alive`, plus attached RefCounted controllers (`sail`, `helm`, `motion`, `battery_port`, `battery_stbd`, `battery_bow`, `battery_stern`).

All physics integration happens inside `_tick_player()` on `blacksite_containment_arena.gd`. Player input is read directly in that method. The AI must plug into this same loop — it cannot use `global_position` or scene-tree patterns like the demo LimboAI tasks do.

**Key constants from existing code (these take precedence over req doc defaults):**

| Parameter | Code Value | Req Doc Default |
|-----------|-----------|-----------------|
| CLOSE_RANGE | 120.0 | 90.0 |
| OPTIMAL_RANGE | 250.0 | 180.0 |
| MAX_CANNON_RANGE | 450.0 | 280.0 |
| BROADSIDE_HALF_ARC_DEG | 45.0 | 45.0 |
| RELOAD_TIME_SEC | 18.0 | 18.0 |
| MAX_SPEED | 11.5 | 9.0 |

The engagement band system must be calibrated to the code's actual ranges, not the req doc's placeholder defaults.

---

## Task 1: NavalCombatEvaluator.gd

**File:** `scripts/shared/naval_combat_evaluator.gd`
**Type:** New file, RefCounted class
**Depends on:** naval_combat_constants.gd, battery_controller.gd

### What It Does

A pure-function evaluator class with no state. Takes ship data as arguments, returns scores. Any caller (AI, debug HUD, future player UI) can use it.

### Step 1.1 — Engagement Band Evaluation

Create band definitions calibrated to the code's actual ranges:

```
too_close:       < 120.0   (matches NC.CLOSE_RANGE)
preferred:       180.0 – 320.0  (centered on NC.OPTIMAL_RANGE = 250)
too_far:         > 320.0
max_practical:   > 450.0   (matches NC.MAX_CANNON_RANGE)
```

Implement `evaluate_range_band(distance: float) -> Dictionary` returning:
- `band`: enum (TOO_CLOSE, PREFERRED, TOO_FAR, BEYOND_MAX)
- `range_score`: 0.0–1.0 (peaks in preferred band, falls off in both directions)

Add hysteresis buffer (15 units) at each boundary to prevent oscillation.

### Step 1.2 — Modular Broadside Quality Scorer

Replace the existing single-factor `broadside_quality()` in naval_combat_constants.gd with a full evaluator. Keep the old function for backward compat but add the new one here.

Implement `evaluate_broadside(args: Dictionary) -> Dictionary` taking:
- `ship_pos: Vector2`
- `ship_dir: Vector2` (heading)
- `target_pos: Vector2`
- `angular_velocity: float`
- `current_speed: float`
- `port_battery: BatteryController`
- `stbd_battery: BatteryController`

**Sub-scores (each 0.0–1.0):**

1. **beam_alignment_score** — Uses existing `NC.broadside_quality()` logic. Angle from bow to target, peak at 90° (beam). Compute for both port and starboard.

2. **range_score** — From Step 1.1. Peak in preferred band, smooth falloff.

3. **stability_score** — Penalty for angular velocity. Full score when `abs(angular_velocity) < 0.02 rad/s`, drops linearly to 0.3 at `abs(angular_velocity) > 0.15 rad/s`. Also penalize high speed slightly (using `NC.HIGH_SPEED_THRESHOLD`).

4. **battery_ready_score** — Hard gate. 1.0 if the battery on the relevant side is in IDLE or READY state (loaded). 0.0 if RELOADING or FIRING.

5. **arc_valid_score** — Hard gate. 1.0 if target is within the battery's firing arc (use `BatteryController.is_target_valid()` or equivalent geometry check). 0.0 otherwise.

**Combination formula:**
```
quality = beam_alignment * 0.4 + range_score * 0.25 + stability * 0.2 + speed_penalty * 0.15
quality *= battery_ready_score   # hard gate
quality *= arc_valid_score       # hard gate
```

**Return dictionary:**
- `quality_port: float` (0.0–1.0)
- `quality_stbd: float` (0.0–1.0)
- `best_quality: float`
- `best_side: String` ("port", "starboard", "none")
- `block_reasons: Array[String]` (e.g., "port_reloading", "target_outside_arc", "turning_too_hard")

### Step 1.3 — Geometry Helpers

Add static helper functions:
- `bearing_to_target(ship_pos, ship_dir, target_pos) -> float` — returns signed angle in degrees
- `target_side(ship_pos, ship_dir, target_pos) -> String` — "port" or "starboard"
- `relative_velocity(ship_vel, target_vel) -> Vector2` — closing/opening rate

### Step 1.4 — Firing Thresholds as Exported Constants

Add to the class or to `naval_combat_constants.gd`:
```
BROADSIDE_FIRE_THRESHOLD = 0.75
BROADSIDE_SOFT_THRESHOLD = 0.60
FIRE_REACTION_DELAY_MIN = 0.25
FIRE_REACTION_DELAY_MAX = 0.60
FIRE_STABILITY_TIME = 0.50
```

### Validation

- Unit test: create two ship dictionaries at known positions/headings, call evaluator, verify scores match expected ranges.
- Visual test: wire debug HUD to show quality scores for the player's own ship (quick sanity check before AI is built).

---

## Task 2: NavalBotController.gd + LimboAI Behavior Tree

**Files:**
- `scripts/shared/naval_bot_controller.gd` — new, RefCounted
- `ai/naval/tasks/*.gd` — new BT task scripts
- `ai/naval/trees/naval_duel_bt.tres` — new behavior tree resource

**Depends on:** Task 1 (NavalCombatEvaluator), all existing controllers

### Critical Architecture Decision

The existing LimboAI demo tasks assume `agent` is a Node2D with `global_position` and `move()`. Our ships are dictionary entries, not nodes. Two approaches:

**Option A (Recommended): Thin wrapper node.**
Create a `BotShipAgent` Node2D that lives in the scene tree, holds a reference to the ship dictionary, and syncs `global_position` from `dict.wx/wy` each frame. BT tasks read from this node. The controller writes intents back to the dictionary's controllers (sail, helm, battery).

**Option B: Direct dictionary access via blackboard.**
Skip the Node2D agent entirely. Put the ship dictionary on the blackboard. BT tasks read `blackboard.get_var("ship_dict")` directly. Downside: can't use LimboAI's built-in `agent` property.

**Go with Option A** — it's cleaner for LimboAI integration and lets us use the agent pattern consistently.

### Step 2.1 — BotShipAgent Node

`scripts/shared/bot_ship_agent.gd` — extends Node2D:
- Holds `ship_dict: Dictionary` reference
- `_process()`: syncs `global_position = Vector2(ship_dict.wx, ship_dict.wy)` and `rotation = ship_dict.dir.angle()`
- Exposes convenience getters: `get_speed()`, `get_heading()`, `get_helm()`, `get_sail()`, `get_battery_port()`, `get_battery_stbd()`, etc.

### Step 2.2 — NavalBotController

`scripts/shared/naval_bot_controller.gd` — the brain that wires everything:
- Owns a `BTPlayer` node (LimboAI's tree runner)
- Creates and configures the blackboard
- Holds a reference to `NavalCombatEvaluator`
- Each frame: reads BT output intents from blackboard, applies them to the ship's controllers

**Control output mapping:**
```
blackboard["desired_speed_state"] → sail.raise_step() / sail.lower_step()
blackboard["desired_turn_direction"] → helm.process_steer(delta, left, right)
blackboard["fire_port_intent"] → set fire_just_pressed on port battery
blackboard["fire_stbd_intent"] → set fire_just_pressed on stbd battery
```

The controller must NOT directly set `wx/wy`, `dir`, `move_speed`, or `angular_velocity`. It sets sail state and wheel input; the arena's existing physics integration does the rest. This matches req-master-architecture.md Design Rule 2.

### Step 2.3 — Blackboard Setup

Initialize all variables from req-ai-naval-bot-v1.md Section 5. The `BT_UpdateCombatContext` task refreshes them each tick.

### Step 2.4 — BT Tasks (in dependency order)

Each task extends `BTAction` or `BTCondition`. All live in `ai/naval/tasks/`.

**1. BT_UpdateCombatContext.gd** (BTAction)
- Reads ship dict + target dict from blackboard
- Calls NavalCombatEvaluator for broadside quality + range band
- Writes all computed values to blackboard
- Always returns SUCCESS

**2. BT_IsTooClose.gd** (BTCondition)
- Returns SUCCESS if `blackboard["too_close"] == true`

**3. BT_HasGoodBroadsideShot.gd** (BTCondition)
- Returns SUCCESS if `blackboard["best_broadside_quality"] >= BROADSIDE_FIRE_THRESHOLD`
- Also checks `fire_stability_timer >= FIRE_STABILITY_TIME` (quality has been above threshold long enough)
- Also checks `recently_fired == false`

**4. BT_FireBestBroadside.gd** (BTAction)
- Reads `best_broadside_side` from blackboard
- Waits for reaction delay (random between 0.25–0.60s)
- Sets fire intent on the appropriate battery
- Sets `recently_fired = true`, `currently_repositioning = true`
- Returns SUCCESS after firing

**5. BT_RepositionAfterShot.gd** (BTAction)
- Commits to a turn direction (away from target if too close, through if at range)
- Sets `desired_turn_direction` on blackboard
- Runs for `reposition_duration` (3.5–5.0s randomized)
- Sets `currently_repositioning = false` when done
- Returns RUNNING while repositioning, SUCCESS when done

**6. BT_BreakAway.gd** (BTAction)
- Turn away from target aggressively
- Set sail to HALF or FULL to increase separation
- Returns RUNNING until outside `minimum_safe_range + hysteresis`

**7. BT_MaintainRange.gd** (BTAction)
- Small speed adjustments to stay in preferred band
- If drifting too close: reduce sail slightly, steer to open distance
- If drifting too far: increase sail slightly
- Returns RUNNING (continuous)

**8. BT_EstablishBroadside.gd** (BTAction)
- Calculate which side (port/stbd) has better geometry
- Steer to bring target toward beam
- Prefer loaded side
- Returns RUNNING until beam alignment score > 0.6, then SUCCESS

**9. BT_ApproachWithOffset.gd** (BTAction)
- Close distance from long range
- Add 15–30° offset to approach angle (not pure head-on)
- Set sail to FULL
- Returns RUNNING until in preferred range

**10. BT_RecoverIfStuck.gd** (BTAction)
- Checks `stuck_timer` (position unchanged for 2.5+ seconds)
- Commits to one random turn direction for 2s
- Sets sail to at least HALF
- Returns RUNNING during recovery

### Step 2.5 — Anti-Jitter State (inside NavalBotController)

Track these timers in the controller, expose to blackboard:

```gdscript
var turn_commit_timer: float = 0.0      # cannot reverse turn direction
var turn_commit_direction: float = 0.0   # locked turn input
var side_switch_cooldown_timer: float = 0.0
var fire_stability_timer: float = 0.0    # how long quality has been above threshold
var maneuver_lock_timer: float = 0.0     # minimum time in current BT branch
var post_fire_lockout_timer: float = 0.0
```

Decrement each frame. BT tasks check these before acting.

### Step 2.6 — Behavior Tree Structure (naval_duel_bt.tres)

Build as a `.tres` resource using LimboAI's editor or programmatically:

```
BTSelector (root)
├── BTSequence "validate"
│   ├── BT_UpdateCombatContext
│   └── BTSucceeder (always pass)
├── BT_RecoverIfStuck
├── BTSequence "breakaway"
│   ├── BT_IsTooClose
│   └── BT_BreakAway
├── BTSequence "fire_opportunity"
│   ├── BT_HasGoodBroadsideShot
│   └── BT_FireBestBroadside
├── BTSequence "reposition"
│   ├── BTCondition: currently_repositioning == true
│   └── BT_RepositionAfterShot
├── BTSequence "maintain_range"
│   ├── BTCondition: in_preferred_range == true
│   └── BT_MaintainRange
├── BTSequence "align_broadside"
│   ├── BTCondition: NOT too_far
│   └── BT_EstablishBroadside
├── BT_ApproachWithOffset
└── BT_MaintainRange (fallback hold pattern)
```

### Step 2.7 — Integration with Arena Tick Loop

In `blacksite_containment_arena.gd`, add a `_tick_bot(p: Dictionary, delta: float)` method that:
1. Calls `NavalBotController.update(delta)` — runs the BT, produces intents
2. Reads intents from the controller
3. Applies helm input: `helm.process_steer(delta, left_strength, right_strength)` based on `desired_turn_direction`
4. Applies sail changes: `sail.raise_step()` / `sail.lower_step()` based on `desired_speed_state`
5. Runs the same physics integration as `_tick_player()` (heading rotation, speed update, position update)
6. Processes battery frames with fire intents from the controller

**Refactoring opportunity:** Extract the physics portion of `_tick_player()` (lines ~373–505) into a shared `_tick_ship_physics(p, delta, steer_l, steer_r, fire_just_pressed)` method that both `_tick_player()` and `_tick_bot()` call. This avoids duplicating ~130 lines of physics code.

### Validation

- Spawn bot via Task 3, observe it approach and attempt broadside passes
- Check debug HUD (Task 3 adds this) for jitter: turn direction changes, side flips, quality oscillation
- Verify bot fires only when broadside score > threshold
- Verify bot repositions after each volley

---

## Task 3: LocalSimController + Bot Spawning

**File:** `scripts/shared/local_sim_controller.gd` — implemented
**Depends on:** Task 2 (NavalBotController)

### Step 3.1 — LocalSimController.gd

A lightweight **RefCounted** helper invoked by the arena during spawn.

```gdscript
class_name LocalSimController
extends RefCounted

var local_sim_enabled: bool = true
var spawn_distance_min: float = 220.0
var spawn_distance_max: float = 320.0
```

Method: `create_bot_entry(player_dict: Dictionary, bot_index: int = 0) -> Dictionary`

- Uses the player’s **wx/wy** as the center of an **axis-aligned square**. With mean distance `dist = (spawn_distance_min + spawn_distance_max) / 2`, half-side `s = dist / √2` places each corner **~dist** from the player.
- **Corner order** (world X/Y): `(+,+)`, `(−,+)`, `(−,−)`, `(+,−)`; `bot_index` picks the corner (wraps with `posmod`).
- **Heading:** bot faces **toward the player** with small random yaw jitter (`randf_range(-0.2, 0.2)` radians), not a fixed bearing-offset parameter.
- Position is **clamped** to map bounds.
- Returns a ship dict with `is_bot = true`, unique negative `peer_id`, palette, and label. **`NavalBotController` is attached in the arena** (`_init_bot_controllers`), not inside this helper.

### Step 3.2 — Arena Integration

In `blacksite_containment_arena.gd`:

1. `@export var local_sim_enabled: bool = true` and `@export_range(1, 4) var local_sim_bot_count: int = 3`.
2. After `_spawn_players()` in `_init_blacksite_movement_state()`, call `_spawn_local_sim_bot_if_needed()` when **offline** (`not multiplayer.has_multiplayer_peer()`), `local_sim_enabled`, and there is at least one human player.
3. Remove dummy offline P2 placeholders, then loop `bot_i in range(clampi(local_sim_bot_count, 1, 4))`, calling `sim.create_bot_entry(player_dict, bot_i)` per bot, appending each entry, then `_init_bot_controllers` (sail **HALF** at spawn, batteries, helm, motion; `auto_fire_enabled = false` where the BT drives fire).
4. In `_process`, after player tick, iterate `_players` and call `_tick_bot(p, delta)` for each `is_bot`.

### Step 3.3 — BotShipAgent Scene Tree Node

`BotShipAgent` is created as a child of the arena per bot; LimboAI’s `BTPlayer` attaches to it and syncs from the bot dict each frame.

### Step 3.4 — Detection: Local Sim vs Multiplayer

Primary gate: `not multiplayer.has_multiplayer_peer()`. Bots do not spawn in networked sessions.

### Validation

- Launch offline: **one player + N bots** (default **N = 3**), on a **square** around the player at **~220–320** mean range (see `req-local-sim-v1.md`).
- Each bot should face the player with jitter and begin maneuvering / firing per the BT.
- Match end rules unchanged when any ship is eliminated.

---

## Implementation Order

```
Step 1.1  Engagement band evaluation          (naval_combat_evaluator.gd)
Step 1.2  Broadside quality scorer            (naval_combat_evaluator.gd)
Step 1.3  Geometry helpers                    (naval_combat_evaluator.gd)
Step 1.4  Firing threshold constants          (naval_combat_constants.gd)
     ↓
Step 3.1  LocalSimController.gd              (can build spawn logic early)
Step 3.2  Arena spawn integration            (get a bot dict in _players)
     ↓
Step 2.1  BotShipAgent node                  (scene tree bridge)
Step 2.2  NavalBotController scaffold        (blackboard + intent output)
     ↓
Step 2.7  Arena _tick_bot + physics refactor (bot moves using same physics)
     ↓
Step 2.3  Blackboard setup
Step 2.4  BT tasks (in dependency order: context → conditions → actions)
Step 2.5  Anti-jitter timers
Step 2.6  Behavior tree resource
     ↓
Step 3.3  BotShipAgent wiring
Step 3.4  Local sim detection
     ↓
     Validate end-to-end
```

The key insight is that Step 3 (spawning) should be built early — even before the AI works — so there's a visible bot ship to test against. Initially it can just sit there as a target dummy. Then each BT task added in Step 2 gives it progressively more behavior.

---

## Risk Areas

1. **Dictionary-based ships vs LimboAI's Node2D agent pattern.** The BotShipAgent wrapper solves this but adds a sync layer. If position drift becomes an issue, the sync must happen at the top of each physics frame.

2. **Physics code duplication.** The `_tick_player()` method is ~200 lines mixing input reading with physics. Extracting shared physics into a helper is necessary but touches a large, working method. Do this carefully with before/after behavioral comparison.

3. **BT tree as .tres resource.** Building the tree in the LimboAI editor is ideal but requires the editor. Alternative: construct it programmatically in `NavalBotController._ready()`. Either works; the programmatic approach is more portable but harder to visualize.

4. **Engagement bands calibrated to code ranges, not req defaults.** The req doc says preferred_range_center = 180 but the code's OPTIMAL_RANGE = 250. Using the code's values per the conflict resolution policy, but this means the preferred band (180–320) is wider than the req intended (145–215). May need tuning.
