# Helm FSM — Requirements Document

**Project:** Naval Game
**System:** Helm / Turning State Machine
**Engine:** Godot (GDScript)
**Date:** 2026-03-22
**Version:** 1.0

---

## 1. Purpose

The Helm FSM controls the ship's steering wheel. It does not rotate the ship directly. It produces a `wheel_position` and derived `rudder_angle` that the motion layer uses to compute angular acceleration.

The defining behavioral rule is: **the player controls a physical wheel, not a yaw command.** If the wheel is turned hard right and the player wants to go left, they must steer back through center before the ship can turn the other way.

This creates commitment, physicality, and countersteering behavior without requiring complex physics simulation.

---

## 2. Inputs

| Input | Action |
|-------|--------|
| Hold `A` | Move wheel toward `-1.0` (left) |
| Hold `D` | Move wheel toward `+1.0` (right) |
| Release both | Wheel drifts back toward `0.0` (soft auto-center) |

`A` and `D` are held-input values read each frame, not discrete events.

---

## 3. Wheel Position

`wheel_position` is a continuous `float` in the range `[-1.0, 1.0]`.

| Value | Meaning |
|-------|---------|
| `-1.0` | Full left |
| `0.0` | Centered (no rudder) |
| `+1.0` | Full right |

`wheel_position` is the primary state variable for this system. Conceptual states (below) are derived from it, not stored separately.

---

## 4. Conceptual States

These states are inferred from `wheel_position` and current input. They do not need to be stored as an explicit enum, but are useful for documentation, VFX hooks, audio, and debugging.

| State | Condition |
|-------|-----------|
| `CENTER` | `abs(wheel_position) < center_threshold` |
| `LEFT` | `wheel_position < -center_threshold` and not changing |
| `RIGHT` | `wheel_position > center_threshold` and not changing |
| `TURNING_LEFT` | `wheel_position` decreasing (A held) |
| `TURNING_RIGHT` | `wheel_position` increasing (D held) |
| `RECENTERING` | No input, `wheel_position` moving toward 0 |

`center_threshold` is a small deadzone value (e.g., `0.05`) to avoid jitter near center.

---

## 5. Transition Logic

### 5.1 Active Input

When `A` is held:
```gdscript
wheel_position = move_toward(wheel_position, -1.0, wheel_turn_rate * delta)
```

When `D` is held:
```gdscript
wheel_position = move_toward(wheel_position, 1.0, wheel_turn_rate * delta)
```

The `move_toward` function means:
- If wheel is at `+0.8` and A is pressed, it moves `+0.8 → +0.6 → +0.3 → 0.0 → -0.3 → ...`
- It does **not** snap to the opposite extreme
- The player must hold A long enough to cross center before left turning begins

This is the core behavioral requirement: **crossing center is mandatory**.

### 5.2 No Input (Auto-Center)

When neither A nor D is held:
```gdscript
wheel_position = move_toward(wheel_position, 0.0, wheel_return_rate * delta)
```

`wheel_return_rate` must be **slower** than `wheel_turn_rate`. Active steering is faster than passive return.

### 5.3 Opposite Direction Override

No special logic is needed. Because `move_toward` is used for both directions, pressing the opposite input simply continues the smooth traversal through whatever current `wheel_position` value exists. There is no snap, no mode switch, and no special case.

---

## 6. Rudder Angle

`rudder_angle` is a smoothed secondary value that follows `wheel_position`. It represents the physical lag between turning the wheel and the rudder actually responding.

```gdscript
rudder_angle = move_toward(rudder_angle, wheel_position, rudder_follow_rate * delta)
```

`rudder_angle` is what the motion layer reads to compute turn force. `wheel_position` is never passed directly to the turn calculation.

| Variable | Description |
|----------|-------------|
| `wheel_position` | What the player intends |
| `rudder_angle` | What the ship is currently responding to |

---

## 7. Turn Force Derivation

`rudder_angle` drives turning, but turn effectiveness must scale with ship speed. This is handled by `ShipController`, not `HelmController`, but the relationship is documented here for clarity.

```gdscript
speed_factor = clamp(current_speed / effective_turn_speed, 0.0, 1.0)
turn_strength = rudder_angle * speed_factor
angular_velocity += turn_strength * turn_acceleration * delta
angular_velocity *= turn_damping
rotation += angular_velocity * delta
```

Behavioral consequences:
- At very low speed, rudder has little effect (the ship barely turns)
- At moderate speed, full steering authority
- At high speed, turning is strong but bleeds forward speed

---

## 8. Tuning Parameters

| Parameter | Recommended Starting Value | Notes |
|-----------|---------------------------|-------|
| `wheel_turn_rate` | `1.5` – `2.5` units/sec | Active steering speed (conceptual) |
| `wheel_return_rate` | `0.75` – `1.5` units/sec | Must be less than turn rate (conceptual) |
| `rudder_follow_rate` | `1.0` – `2.0` units/sec | Rudder lag behind wheel |
| `center_threshold` | `0.05` | Deadzone for CENTER state detection |
| `turn_acceleration` | TBD per ship class | Angular response rate |
| `turn_damping` | `0.85` – `0.95` per frame | Angular momentum bleed |

### 8.1 Ironwake Implementation — Acceleration-Based Wheel Model

The Ironwake `HelmController` replaces the simple `wheel_turn_rate` / `wheel_return_rate` model above with a momentum-based system using velocity and acceleration:

| Parameter | HelmController Default | Player Override (Arena) | Notes |
|-----------|----------------------|------------------------|-------|
| `wheel_spin_accel` | `1.4` | `1.2` | How fast input accelerates the wheel (norm/sec^2) |
| `wheel_max_spin` | `0.45` | `0.45` | Terminal wheel velocity under continuous input (norm/sec) |
| `wheel_friction` | `3.0` | `2.5` | Friction deceleration when input is released (norm/sec^2) |
| `rudder_follow_rate` | `0.275` | `0.35` | Rudder chases wheel at this rate (norm/sec) |

The wheel now has velocity (`wheel_velocity`) that accelerates toward `wheel_max_spin` under input and decelerates via `wheel_friction` on release, with exponential spring return toward center. Counter-steer damping slows reversal when the wheel is displaced past the opposing side.

Key tuning principle: **active input must feel faster than release**. If return rate equals turn rate, the wheel feels artificial. The asymmetry is what creates the sense of weight.

---

## 9. Auto-Center Design Choice

The v1 design uses **soft auto-centering on release**:

- Release A/D → wheel drifts back toward 0 at `wheel_return_rate`
- This is more accessible than a "wheel stays where left" simulation approach
- The ship will continue a slight turn until `rudder_angle` also settles near zero

The alternative (wheel holds position on release) is available as a future toggle but is not the v1 default. It would be appropriate for a higher-simulation mode.

---

## 10. Outputs (consumed by ShipController)

| Output | Type | Description |
|--------|------|-------------|
| `wheel_position` | float [-1.0, 1.0] | Current wheel value |
| `rudder_angle` | float [-1.0, 1.0] | Smoothed rudder response |
| `helm_state` | enum (inferred) | Conceptual state for FX/debug hooks |

---

## 11. Godot Implementation Notes

- `HelmController` is a standalone node or component on the ship scene
- `wheel_position` and `rudder_angle` are plain `float` properties
- Use `Input.is_action_pressed("steer_left")` / `Input.is_action_pressed("steer_right")` inside `_physics_process`
- Do not use `_input` or `_unhandled_input` for held steering; frame-consistent reads are required
- Conceptual state (for VFX/audio) can be derived via a `get_helm_state()` helper that returns an enum based on current values
- Per-class tuning: expose `wheel_turn_rate` and `wheel_return_rate` as `@export` variables so different ship classes can configure their helm feel

---

## 12. Per-Class Behavioral Differences

Different ship classes modify `wheel_turn_rate` and `rudder_follow_rate` to change feel — the FSM logic itself is identical.

| Ship Class | `wheel_turn_rate` | `rudder_follow_rate` | Feel |
|------------|-------------------|----------------------|------|
| Schooner | High | High | Snappy, responsive |
| Galley | High | Medium | Precise, controlled |
| Brig | Low | Low | Heavy, committed |

---

## 13. Out of Scope for V1

- Wind affecting steering effectiveness
- Rudder damage modifying `rudder_follow_rate`
- Crew state reducing helm responsiveness
- Joystick / analog input support (can be added by mapping analog axis to `wheel_turn_rate` multiplier)
