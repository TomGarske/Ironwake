# Combat Loop — Broadside Quality, Engagement Bands, and Pass Rhythm Requirements

**Project:** Naval Game
**System:** Combat Decision Loop
**Engine:** Godot (GDScript)
**Date:** 2026-03-29
**Version:** 1.0

---

## 1. Purpose

This document specifies the combat decision loop layer that sits above the existing movement, helm, sail, and battery systems. It adds broadside quality scoring, engagement band logic, and pass-based combat rhythm.

**Dependencies:**
- `req-naval-combat-prototype-v1.md` — world scale, engagement ranges, combat timing
- `req-weapons-layer-v1.md` — projectile model, accuracy, fire modes
- `req-battery-fsm.md` — battery states, fire sequences, reload
- `req-helm-fsm.md` — wheel/rudder model
- `req-motion-fsm.md` — speed, turning, motion states
- `req-master-architecture.md` — ShipContext, controller architecture

**Conflict Resolution:** Where this document specifies values that overlap with existing req docs, the existing req doc values take precedence. This document adds new systems only.

---

## 2. Design Intent

Combat should produce a readable loop:

1. Approach target
2. Establish favorable range
3. Rotate into broadside alignment
4. Fire when shot quality is good
5. Reposition while reloading
6. Re-engage on the next pass

The implementation must reward positioning over twitch reactions, avoid jittery behavior, avoid random firing, make misses understandable, and support future extension to multiple ships.

---

## 3. Broadside Quality System

### 3.1 Purpose

A deterministic shot quality model that evaluates how good a broadside opportunity is. This score is used by AI firing decisions, player debug display, tuning, and future UI indicators.

### 3.2 Inputs

The score must include at minimum:

- Distance to target
- Angle of target relative to ship heading
- Whether target is on port or starboard side
- Current ship turn rate (from `ShipContext.angular_velocity`)
- Current ship speed (from `ShipContext.current_speed`)
- Target relative movement
- Relevant battery loaded state (from `BatteryController`)
- Whether target is within firing arc (from `BatteryController.firing_arc_degrees`)
- Optional line-of-fire obstruction check if easy to support

### 3.3 Scoring Intent

A good shot scores highly when:

- Target is near the ship's beam (perpendicular to heading)
- Target is within effective range
- Ship is not turning hard
- Relevant side battery is loaded
- Geometry is stable

A bad shot scores poorly when:

- Target is near bow or stern
- Ship is turning hard
- Target is out of effective range
- Battery is reloading
- Shot would require extreme correction

### 3.4 Required Output

- Numeric score: `0.0` to `1.0`
- Preferred firing side: `port`, `starboard`, or `none`
- Reason flags or diagnostics for low-quality scores

### 3.5 Scoring Formula Structure

Implement a modular scoring function with these components:

- `beam_alignment_score` — how close the target is to the beam axis
- `range_score` — quality based on distance relative to engagement bands
- `stability_score` — penalty for high turn rate
- `battery_ready_score` — hard gate: 0.0 if battery not loaded, 1.0 if loaded
- `arc_valid_score` — hard gate: 0.0 if target outside firing arc, 1.0 if inside

Combine using weighted multiplication or weighted average.

**Initial bias:**

- Beam alignment is the most important factor
- Battery readiness and arc validity are hard gates (score zeroes if not met)
- Turning penalty should matter significantly

### 3.6 Firing Thresholds

| Threshold | Value | Meaning |
|-----------|-------|---------|
| Strong opportunity | `>= 0.75` | Fire confidently |
| Acceptable if stable | `0.55 – 0.74` | Fire if geometry holds |
| Do not fire | `< 0.55` | Wait for better alignment |

These must be exported / tunable variables.

### 3.7 Implementation

Create `NavalCombatEvaluator.gd` containing:

- Broadside quality scoring
- Engagement band evaluation
- Helper geometry methods (bearing calculation, side detection, arc checks)

This evaluator reads from `ShipContext` and `BatteryController` but does not own them.

---

## 4. Engagement Band System

### 4.1 Purpose

Combat spacing should be deliberate and readable. Engagement bands define soft range zones that influence AI behavior and broadside quality scoring.

**Note:** `req-naval-combat-prototype-v1.md` Section 4.1 defines the canonical engagement ranges. The bands below must align with those values.

### 4.2 Required Bands

| Band | Range | Behavior |
|------|-------|----------|
| Too Close | `< 90 units` | Prioritize separation / breakaway |
| Preferred | `145 – 215 units` | Maintain with mild corrections, prioritize broadside setup |
| Too Far | `> 215 units` | Close distance deliberately |
| Max Practical | `> 280 units` | Strongly discourage firing |

### 4.3 Tunable Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `minimum_safe_range` | `90.0` | Below this, breakaway logic triggers |
| `preferred_range_center` | `180.0` | Aligns with `req-naval-combat-prototype-v1.md` optimal range |
| `preferred_range_tolerance` | `35.0` | Creates 145–215 band |
| `maximum_practical_range` | `280.0` | Beyond this, shots are impractical |

All must be `@export` variables.

### 4.4 Behavior by Band

**Too Close:**
- Prioritize separation / breakaway logic
- Avoid nose-to-nose drift
- Do not greed bad shots unless quality is exceptionally high

**Preferred:**
- Maintain band with mild corrections
- Prioritize broadside setup
- Small speed and turn adjustments only

**Too Far:**
- Close distance deliberately
- Avoid overcommitting into point-blank range

### 4.5 Anti-Jitter

Implement hysteresis so transitions between range bands do not oscillate rapidly. Use a buffer zone at each boundary (e.g., 10–15 units of hysteresis).

---

## 5. Pass / Combat Rhythm System

### 5.1 Purpose

Combat should feel like a sequence of passes, not random drifting or continuous circling.

### 5.2 Definition

A pass is a maneuver phase where the ship tries to bring one broadside to bear during a limited firing window.

### 5.3 Pass Phases

| Phase | Duration Target | Description |
|-------|----------------|-------------|
| Setup | 4–8 seconds | Approach and establish broadside angle |
| Firing window | 1–3 seconds | Broadside quality is high, fire |
| Post-fire reposition | 3–6 seconds | Arc away or turn through for next pass |

### 5.4 Implementation Guidance

This can be represented either as an explicit maneuver state machine or implicitly through behavior tree state selection plus cooldowns. Either approach is acceptable, but the result must be readable in debug output.

---

## 6. Post-Fire Reposition System

### 6.1 Purpose

After firing, the ship should not hover indecisively near the same line. It must commit to repositioning.

### 6.2 Required Behavior

After firing:

- Enter a reposition state
- Commit to a turn direction for a short period
- Either arc outward or turn through depending on current range
- Avoid trying to instantly fire opposite battery unless geometry is unusually clean

### 6.3 Tunable Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `reposition_duration_min` | `3.5` sec | Minimum reposition time |
| `reposition_duration_max` | `5.0` sec | Maximum reposition time |
| `side_switch_cooldown` | `1.5` sec | Delay before allowing opposite battery fire |
| `post_fire_lockout` | `0.5` sec | Short lockout immediately after firing |

---

## 7. Initial Tuning Values Summary

All values below are starting points, not final balance.

```yaml
combat:
  minimum_safe_range: 90.0
  preferred_range_center: 180.0
  preferred_range_tolerance: 35.0
  maximum_practical_range: 280.0

firing:
  broadside_fire_threshold: 0.75
  broadside_soft_threshold: 0.60
  fire_reaction_delay_min: 0.25
  fire_reaction_delay_max: 0.60
  fire_stability_time: 0.50

maneuver:
  reposition_duration_min: 3.5
  reposition_duration_max: 5.0
  side_switch_cooldown: 1.5
  post_fire_lockout: 0.5
```

---

## 8. Out of Scope

- Wind simulation
- Multiple enemy ships / fleet coordination
- Morale systems
- Crew management
- Advanced utility AI
- Cheating AI aim assistance beyond deterministic heuristics
