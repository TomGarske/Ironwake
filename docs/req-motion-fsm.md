# Motion FSM — Requirements Document

**Project:** Naval Game
**System:** Ship Motion State Machine
**Engine:** Godot (GDScript)
**Date:** 2026-03-22
**Version:** 1.0

---

## 1. Purpose

The Motion FSM is the top-level reader of ship movement state. It does not drive motion directly — that is handled by the `ShipController` physics integrator. Instead, it classifies current movement into a named state that other systems (VFX, audio, camera, wake effects, UI) can hook into cleanly.

It also serves as the integration layer: `ShipController` reads from `SailController` and `HelmController`, computes actual velocity and heading, and updates the motion state accordingly.

---

## 2. Responsibilities

| Responsibility | Owner |
|----------------|-------|
| Setting `target_sail_level` and `target_speed` | `SailController` |
| Setting `wheel_position` and `rudder_angle` | `HelmController` |
| Computing `current_speed`, `angular_velocity`, `heading` | `ShipController` |
| Classifying current behavior into motion state | `MotionStateResolver` (inside `ShipController`) |

`MotionStateResolver` can be a method or inner class within `ShipController`.

---

## 3. Motion States

| State | Description |
|-------|-------------|
| `IDLE` | Ship is nearly stationary, no effective propulsion |
| `ACCELERATING` | Current speed is below target speed; engine/sails are pushing |
| `CRUISING` | Current speed is approximately at target speed |
| `COASTING` | Sails reduced or stopped, ship still carrying momentum |
| `DECELERATING` | Speed falling toward a lower target (active drag) |
| `TURNING` | Meaningful rudder and sufficient speed for effective turning |
| `TURNING_HARD` | High rudder angle at sufficient speed; speed penalty and visual effects active |

---

## 4. Transition Rules

These conditions are evaluated each frame. States are mutually exclusive; the first matching condition wins unless otherwise noted.

### 4.1 IDLE
**Enter when:**
- `current_speed < idle_speed_threshold`

**Exit when:**
- `target_speed > current_speed + accel_threshold` → enter `ACCELERATING`

### 4.2 ACCELERATING
**Enter when:**
- `target_speed > current_speed + accel_threshold`

**Exit when:**
- `abs(target_speed - current_speed) < cruise_threshold` → enter `CRUISING`
- `target_speed < current_speed` → enter `COASTING` or `DECELERATING`

### 4.3 CRUISING
**Enter when:**
- `abs(target_speed - current_speed) < cruise_threshold`

**Exit when:**
- `current_speed < target_speed - accel_threshold` → enter `ACCELERATING`
- `target_sail_level < current_sail_level` by more than coast_threshold → enter `COASTING`

### 4.4 COASTING
**Enter when:**
- `target_sail_level < current_sail_level` (sails being reduced)
- **AND** `current_speed > coast_speed_threshold`

The ship is still moving but no longer being driven. Passive drag applies.

**Exit when:**
- `current_speed < idle_speed_threshold` → enter `IDLE`
- `target_speed > current_speed + accel_threshold` → enter `ACCELERATING`

### 4.5 DECELERATING
**Enter when:**
- `target_speed < current_speed - decel_threshold`
- **AND** sails are not simply reducing (distinguishes active braking intent from coast)

In v1, this state is functionally similar to `COASTING` but has higher drag applied and may trigger distinct audio/VFX.

### 4.6 TURNING
**Enter when:**
- `abs(rudder_angle) > turn_threshold`
- **AND** `current_speed > min_turn_speed`

Turning is **additive** to other states. A ship can be `CRUISING` and `TURNING` simultaneously. In the implementation, turning is layered on top of the linear motion state.

**Exit when:**
- `abs(rudder_angle) < turn_threshold`
- **OR** `current_speed < min_turn_speed`

### 4.7 TURNING_HARD
**Enter when:**
- `abs(rudder_angle) > hard_turn_threshold` (e.g., > 0.7)
- **AND** `current_speed > min_turn_speed`

**Effects:**
- Stronger speed bleed (see Section 7.3)
- Wider wake VFX
- Heel/lean visual if implemented
- Audio cue change

**Exit when:**
- `abs(rudder_angle) < hard_turn_threshold`

---

## 5. Physics Integration (ShipController)

`ShipController` updates `current_speed` and `heading` each frame using these rules.

### 5.1 Speed Update

```gdscript
# Propulsion
if current_speed < target_speed:
    current_speed += acceleration_rate * delta
else:
    current_speed -= deceleration_rate * delta

# Passive drag (always applied)
current_speed -= passive_water_drag * delta

# Extra drag when sails are down
if current_sail_level < coast_drag_threshold:
    current_speed -= zero_sail_drag * delta

# Turning speed cost
current_speed -= abs(rudder_angle) * turning_speed_loss * delta

# Clamp
current_speed = clamp(current_speed, 0.0, max_speed)
```

### 5.2 Angular Velocity Update

```gdscript
speed_factor = clamp(current_speed / effective_turn_speed, 0.0, 1.0)
turn_strength = rudder_angle * speed_factor
angular_velocity += turn_strength * turn_acceleration * delta
angular_velocity *= turn_damping
heading += angular_velocity * delta
```

### 5.3 Turning Speed Penalty

Turning bleeds forward speed. The amount scales with rudder angle:

```gdscript
current_speed -= abs(rudder_angle) * turning_speed_loss * delta
```

For `TURNING_HARD`, this multiplier increases:

```gdscript
if abs(rudder_angle) > hard_turn_threshold:
    current_speed -= abs(rudder_angle) * hard_turn_speed_loss * delta
```

This makes aggressive turning feel grounded and tactically costly.

---

## 6. Key Design Rules

**Rule 1: Speed is never directly set.**
`current_speed` always moves toward `target_speed` through integration with drag and acceleration forces.

**Rule 2: Turning does not stop the ship.**
It slows it proportionally. A hard turn at full sail still makes forward progress.

**Rule 3: Rudder has no authority at near-zero speed.**
`speed_factor` zeroes out below `min_turn_speed`. Spinning in place is not possible.

**Rule 4: Coasting must feel generous.**
`passive_water_drag` should be low enough that the ship carries momentum for several seconds. Players should be able to coast into position tactically.

**Rule 5: The motion state is for output only.**
`IDLE`, `CRUISING`, etc. are never written by anything except `MotionStateResolver`. They are read by VFX, audio, camera, and UI systems.

---

## 7. Threshold and Tuning Parameters

| Parameter | Recommended Range | Description |
|-----------|-------------------|-------------|
| `idle_speed_threshold` | `0.5` – `2.0` | Speed below which ship is IDLE |
| `accel_threshold` | `1.0` – `3.0` | Gap between target/current to trigger ACCELERATING |
| `cruise_threshold` | `0.5` – `1.5` | Tolerance for CRUISING |
| `coast_speed_threshold` | `2.0` | Min speed for COASTING (vs just IDLE) |
| `decel_threshold` | `1.0` | Gap to trigger DECELERATING |
| `turn_threshold` | `0.1` | Min rudder angle for TURNING |
| `hard_turn_threshold` | `0.65` – `0.75` | Min rudder for TURNING_HARD |
| `min_turn_speed` | `10%` of max_speed | Min speed for rudder authority |
| `effective_turn_speed` | `50%` of max_speed | Speed at which full turn authority is reached |
| `acceleration_rate` | TBD per ship class | Forward acceleration force |
| `deceleration_rate` | TBD per ship class | Natural speed bleed when above target |
| `passive_water_drag` | Low | Always-on drag |
| `zero_sail_drag` | Medium | Extra drag with no sails |
| `turning_speed_loss` | Small | Speed cost per rudder unit |
| `hard_turn_speed_loss` | Medium | Extra speed cost during TURNING_HARD |
| `turn_acceleration` | TBD per class | Angular velocity gain rate |
| `turn_damping` | `0.85` – `0.95` | Angular momentum bleed per frame |

---

## 8. Outputs (consumed by other systems)

| Output | Type | Consumer |
|--------|------|----------|
| `motion_state` | enum | VFX, audio, camera, UI |
| `current_speed` | float | All systems |
| `angular_velocity` | float | Camera, VFX |
| `heading` | float (radians) | Rendering, AI, targeting |
| `is_turning` | bool | Weapon arc calculations, camera |
| `is_turning_hard` | bool | Wake VFX, audio, speed penalty |

---

## 9. Godot Implementation Notes

- `ShipController` is the root node; it owns `SailController` and `HelmController` as children
- Motion state is resolved in `_physics_process`, not `_process`, to stay in sync with physics
- `angular_velocity` and `heading` should use radians internally; convert to degrees only for display
- `is_turning` and `is_turning_hard` are convenience booleans derived from `abs(rudder_angle)` comparisons — cheaper to read than checking the full motion state enum
- Expose all threshold values as `@export` variables for in-editor tuning
- Motion state changes should emit a signal (`motion_state_changed`) so VFX/audio nodes can connect without polling

```gdscript
signal motion_state_changed(old_state: MotionState, new_state: MotionState)
```

---

## 10. Per-Class Behavioral Differences

The motion FSM logic is identical across ship classes. Class differences are expressed entirely through parameter values.

| Ship Class | Accel Rate | Decel Rate | Turn Accel | Turn Damping | Feel |
|------------|------------|------------|------------|--------------|------|
| Schooner | High | Low (long coast) | High | Low (drifty) | Fast, committal |
| Galley | Medium | Medium | High | Medium | Precise |
| Brig | Low | Medium | Low | High (stiff) | Heavy, slow |

---

## 11. Out of Scope for V1

- Wind force affecting propulsion efficiency
- Wave simulation affecting angular velocity
- Sail damage capping `max_speed`
- Rudder damage reducing `rudder_follow_rate`
- Reverse motion (`current_speed` below zero)
- Ship-to-ship collision response (basic ramming is now implemented with server-authoritative damage; advanced collision physics remain out of scope)
