# Sail FSM — Requirements Document

**Project:** Naval Game
**System:** Sail / Speed State Machine
**Engine:** Godot (GDScript)
**Date:** 2026-03-22
**Version:** 1.0

---

## 1. Purpose

The Sail FSM controls the ship's desired propulsion level. It does not move the ship directly. It produces a `target_sail_level` and derived `target_speed` that the motion layer consumes each frame.

This separation ensures that speed changes feel earned — the player sets intention, and the ship responds over time.

---

## 2. Inputs

| Input | Action |
|-------|--------|
| `W` (pressed) | Increase sail level one step |
| `S` (pressed) | Decrease sail level one step |

Inputs are discrete step events, not held values. One press = one state transition attempt.

---

## 3. Sail Level States

Sail level is represented as a stepped enum with three v1 states. Additional states are defined for future expansion but are out of scope for v1.

### V1 States

| State | `target_sail_level` | Description |
|-------|---------------------|-------------|
| `STOP` | `0.0` | Sails furled. No propulsion. |
| `QUARTER` | `0.25` | Quarter sail. Low speed, fine maneuvering. |
| `HALF` | `0.5` | Half sail deployed. Moderate speed. |
| `FULL` | `1.0` | Full sail deployed. Maximum speed. |

Four sail states are implemented in the Ironwake `SailController` (STOP, QUARTER, HALF, FULL).

**Spawn default (Ironwake arena):** Player and locally spawned bots start with **`SailState.HALF`** and **`current_sail_level = 0.5`** (“half mast”) after `_init_ironwake_movement_state()` / `_init_bot_controllers()`. The AI’s default desired sail state matches **HALF** so behavior does not immediately fight the spawn state.

### Future Expansion States (out of scope for v1)

- `BACK_SAIL` — reverse propulsion
- `BATTLE_SAIL` — combat-optimized deployment
- `FULL_WIND` — above full, situational bonus speed

---

## 4. Transition Table

| Current State | Input | Next State | Notes |
|---------------|-------|------------|-------|
| `STOP` | W | `QUARTER` | Begin raising sails |
| `QUARTER` | W | `HALF` | Continue raising |
| `HALF` | W | `FULL` | Continue raising |
| `FULL` | W | `FULL` | No change, already at max |
| `FULL` | S | `HALF` | Begin lowering sails |
| `HALF` | S | `QUARTER` | Continue lowering |
| `QUARTER` | S | `STOP` | Lower sails fully |
| `STOP` | S | `STOP` | No change, already stopped |

---

## 5. Continuous Variables

These values are updated every frame by `SailController`. They are distinct from the stepped state above.

| Variable | Type | Description |
|----------|------|-------------|
| `target_sail_level` | `float` [0.0–1.0] | Derived from current sail state enum |
| `current_sail_level` | `float` [0.0–1.0] | Smoothed value moving toward target |
| `target_speed` | `float` | `max_speed * current_sail_level` |

`current_sail_level` must never be directly set to `target_sail_level`. It must always interpolate using `sail_raise_rate` or `sail_lower_rate`.

---

## 6. Behavior Rules

### 6.1 Sail Deployment Delay

`current_sail_level` moves toward `target_sail_level` at different rates depending on direction:

- **Raising:** `current_sail_level += sail_raise_rate * delta`
- **Lowering:** `current_sail_level -= sail_lower_rate * delta`

This represents the physical time needed to raise or furl sails.

### 6.2 Speed Derivation

`target_speed` is always derived from `current_sail_level`, not `target_sail_level`:

```gdscript
target_speed = max_speed * current_sail_level
```

This means speed ramps up as sails actually deploy, not when the player presses W.

### 6.3 Coasting

When `target_sail_level` is reduced (S pressed), the ship must **not** brake immediately. The following rules apply:

- `current_speed` continues at its current value
- Passive water drag applies at all times
- An additional coasting drag multiplier applies when `current_sail_level` drops below `coast_drag_threshold`
- The ship should take several seconds to fully decelerate from `FULL` to rest with no sails

Coasting drag is handled by `ShipController`, not `SailController`. `SailController` only exposes `current_sail_level`.

---

## 7. Tuning Parameters

| Parameter | Recommended Starting Value | Notes |
|-----------|---------------------------|-------|
| `sail_raise_rate` | `0.35` – `0.6` per second | How fast sails deploy |
| `sail_lower_rate` | `0.4` – `0.7` per second | Can be faster than raising |
| `coast_drag_threshold` | `0.1` | Below this, apply extra drag |
| `max_speed` | TBD per ship class | Tune per vessel |

---

## 8. Outputs (consumed by ShipController)

| Output | Type | Description |
|--------|------|-------------|
| `target_sail_level` | float | Desired sail deployment [0.0–1.0] |
| `current_sail_level` | float | Actual current sail amount |
| `target_speed` | float | Speed the ship should be approaching |

---

## 9. Godot Implementation Notes

- Sail state enum should be defined in `SailController.gd`
- `current_sail_level` is a `@export` float for tuning in the Inspector
- Use `move_toward(current_sail_level, target_sail_level, rate * delta)` for smooth interpolation
- `SailController` does not reference `ShipController` directly; it exposes outputs via readable properties
- Input handling (`W`/`S`) should be processed in `_unhandled_input` or a dedicated input manager, not inside `SailController._process`

---

## 10. Out of Scope for V1

- Reverse sailing / back sail
- Wind direction affecting sail efficiency
- Mast damage affecting sail capacity
- Crew count modifying raise/lower rate
