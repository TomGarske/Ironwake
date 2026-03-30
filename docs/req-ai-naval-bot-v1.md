# AI Naval Bot — LimboAI Behavior Tree and Decision Logic Requirements

**Project:** Naval Game
**System:** Enemy AI / Bot Controller
**Engine:** Godot (GDScript) + LimboAI
**Date:** 2026-03-29
**Version:** 1.0

---

## 1. Purpose

This document specifies the enemy ship AI for the naval combat prototype. The bot must fight using broadside passes with deliberate pacing, using LimboAI as the behavior tree framework.

**Dependencies:**
- `req-combat-loop-v1.md` — broadside quality, engagement bands, pass rhythm, reposition
- `req-master-architecture.md` — ShipContext, controller architecture, design rules
- `req-battery-fsm.md` — battery states, fire modes
- `req-helm-fsm.md` — wheel/rudder control model
- `req-motion-fsm.md` — speed, turning
- `req-sail-fsm.md` — sail level states

---

## 2. LimboAI Integration

### 2.1 Dependency

LimboAI must be added as the AI framework for enemy ship behavior.

If the project does not already include it:

- Add LimboAI plugin
- Configure for Godot 4
- Create AI behavior tree assets in a clean project structure

### 2.2 Folder Structure

```text
res://ai/
  behavior_trees/
  tasks/
  conditions/
  decorators/
  controllers/
  debug/
```

---

## 3. Ship Control Interface

AI must use the same control pathways as the player, per `req-master-architecture.md` Design Rule 2 (state machines produce outputs, they do not move the ship).

AI outputs map to:

- Sail / throttle intent (via `SailController`)
- Steering / wheel intent (via `HelmController`)
- Fire port intent (via `BatteryController`)
- Fire starboard intent (via `BatteryController`)

Do not cheat by directly rotating heading, teleporting velocity, or forcing projectile hits.

---

## 4. Required Components

### 4.1 Scripts

- `NavalBotController.gd` — owns AI-facing control logic, updates blackboard inputs, receives outputs from BT tasks
- LimboAI behavior tree asset for duel AI
- Custom BT tasks and conditions as needed

### 4.2 Recommended BT Task Scripts

- `BT_UpdateCombatContext.gd`
- `BT_IsTooClose.gd`
- `BT_HasGoodBroadsideShot.gd`
- `BT_FireBestBroadside.gd`
- `BT_RepositionAfterShot.gd`
- `BT_MaintainRange.gd`
- `BT_EstablishBroadside.gd`
- `BT_ApproachWithOffset.gd`
- `BT_RecoverIfStuck.gd`

Naming can differ but must remain clear and consistent.

---

## 5. Blackboard Variables

At minimum, expose these on the LimboAI blackboard:

| Variable | Type | Description |
|----------|------|-------------|
| `self_ship` | Node | Reference to bot's ship node |
| `target_ship` | Node | Reference to target (player) ship |
| `distance_to_target` | float | World units |
| `target_direction` | Vector2 | Normalized direction to target |
| `target_bearing_degrees` | float | Bearing relative to ship heading |
| `target_on_port` | bool | Target is on port side |
| `target_on_starboard` | bool | Target is on starboard side |
| `current_speed` | float | From ShipContext |
| `current_turn_rate` | float | From ShipContext.angular_velocity |
| `port_loaded` | bool | Port battery in READY or IDLE+loaded state |
| `starboard_loaded` | bool | Starboard battery loaded state |
| `preferred_side` | enum | Port, starboard, or none |
| `broadside_quality_port` | float | Score from NavalCombatEvaluator |
| `broadside_quality_starboard` | float | Score from NavalCombatEvaluator |
| `best_broadside_quality` | float | Max of port/starboard |
| `best_broadside_side` | enum | Side with best score |
| `in_preferred_range` | bool | From engagement band evaluation |
| `too_close` | bool | Below minimum_safe_range |
| `too_far` | bool | Above preferred range |
| `currently_repositioning` | bool | In post-fire reposition phase |
| `recently_fired` | bool | Within post-fire lockout window |
| `stuck_timer` | float | Time without meaningful progress |
| `last_maneuver` | String | Debug label for current maneuver |
| `fire_block_reason` | String | Why firing is blocked (debug) |
| `desired_speed_state` | enum | STOP, HALF, FULL |
| `desired_turn_direction` | float | -1.0 to 1.0 wheel intent |
| `bot_enabled` | bool | Master toggle |

All important values must be updated each AI tick via `BT_UpdateCombatContext`.

---

## 6. Behavior Tree Structure

### 6.1 Top-Level Decision Priority

The top-level logic evaluates in this order:

1. Validate target / update combat context
2. Recover if invalid or stuck
3. Break away if too close
4. Fire if strong broadside opportunity exists
5. Reposition if recently fired or currently repositioning
6. Maintain preferred engagement band
7. Establish broadside alignment
8. Approach target if too far
9. Default controlled circling / holding pattern

### 6.2 Required Behavior Tree States

**AcquireTarget**
- Validate target exists
- In **local sim**, multiple bots may be present (default **3**); each bot’s controller targets the **player** ship (`target_dict` = player entry)
- Cache target references
- Fail gracefully if no target

**UpdateCombatContext**
- Compute all blackboard combat metrics
- Update distance, bearing, speed, broadside scores, range band flags
- Uses `NavalCombatEvaluator` from `req-combat-loop-v1.md`

**RecoverIfStuck**
- Detect lack of meaningful progress (position unchanged for `stuck_detection_time`)
- Reset maneuver intent
- Commit to one turn direction briefly
- Clear fire greed behavior
- Resume combat loop

**BreakAwayIfTooClose**
- If inside `minimum_safe_range`:
  - Prioritize separation
  - Choose turn direction that increases distance
  - Reduce nose-forward drift into target
  - Do not greed bad shots unless quality is exceptionally high

**FireBroadside**
- Select best side
- Ensure battery ready
- Ensure broadside score exceeds threshold (from `req-combat-loop-v1.md` Section 3.6)
- Require stability window before firing (`fire_stability_time`)
- Add small human-like reaction delay (`fire_reaction_delay_min` to `fire_reaction_delay_max`)
- Fire ripple broadside (default fire mode)
- Mark reposition state

**RepositionAfterShot**
- Commit to a brief arc maneuver
- Widen or turn through based on current range
- Avoid immediate side switching (respect `side_switch_cooldown`)
- Continue until reposition timer expires

**MaintainEngagementBand**
- If in preferred range: use small speed and turn corrections
- Avoid large oscillations
- Favor alignment over raw closure

**EstablishBroadside**
- Rotate ship so target approaches beam position
- Select port or starboard solution
- Prefer loaded side when practical
- Avoid rapid flipping between sides

**ApproachTarget**
- Close from long range
- Use offset approach angle (not pure head-on)
- Avoid nose chase when possible

**Hold / CircleFallback**
- If no immediate high-priority action: maintain stable movement
- Avoid stopping
- Keep target in usable geometry

---

## 7. Anti-Jitter Requirements

This is mandatory. AI must not:

- Alternate left/right steering every frame
- Oscillate throttle every frame
- Flip preferred broadside side too often
- Fire immediately when score barely crosses threshold

### 7.1 Required Mechanisms

| Mechanism | Default Value | Purpose |
|-----------|--------------|---------|
| Turn commitment window | `2.0` sec | Cannot reverse turn direction |
| Side preference cooldown | `1.5` sec | Cannot switch preferred broadside side |
| Fire stability requirement | `0.50` sec | Quality must hold above threshold before firing |
| Maneuver transition lock | `0.75` sec | Minimum time in a BT state before switching |
| Post-fire lockout | `0.50` sec | No firing immediately after a volley |
| Range hysteresis | `10–15` units | Buffer at band boundaries |

### 7.2 Tunable Parameters

```yaml
anti_jitter:
  turn_commit_duration: 2.0
  side_switch_cooldown: 1.5
  fire_stability_time: 0.50
  maneuver_transition_lock: 0.75

recovery:
  stuck_detection_time: 2.5
  stuck_progress_distance_epsilon: 5.0
```

All must be `@export` variables.

---

## 8. Acceptance Criteria

1. The bot attempts to fight using broadside passes, not nose-chasing.
2. The bot only fires when a shot appears reasonably earned (score above threshold).
3. The bot repositions after firing instead of hovering in place.
4. The bot tries to maintain preferred range and breaks off when too close.
5. The bot does not visibly jitter, spin, or spam state changes.
6. The architecture is modular enough to tune difficulty later.

---

## 9. Out of Scope

- Fleet coordination between multiple **enemy** ships (local sim may spawn several bots, but each runs an independent `NavalBotController` without squad tactics)
- Fleet coordination
- Advanced utility AI
- Morale / panic behavior
- Crew management affecting AI
- Wind-aware maneuvering
