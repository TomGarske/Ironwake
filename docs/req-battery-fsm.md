# Cannon Battery FSM — Requirements Document

**Project:** Naval Game
**System:** Weapon Battery State Machine
**Engine:** Godot (GDScript)
**Date:** 2026-03-22
**Version:** 1.0

---

## 1. Purpose

The Battery FSM manages the state of a single cannon battery (a group of cannons on one side of a ship). It controls targeting readiness, firing sequences, and reloading. It does not simulate individual cannons — each battery is treated as a single unit with a configurable cannon count.

Ships may have multiple batteries (e.g., port and starboard). Each battery runs its own independent FSM instance.

---

## 2. Battery States

| State | Description |
|-------|-------------|
| `IDLE` | No valid target exists. Battery is inactive. |
| `AIMING` | Target exists but is not yet in arc or range. Battery is tracking. |
| `READY` | Target is in arc, in range, and battery is loaded. Can fire. |
| `FIRING` | Battery is executing a fire sequence (salvo or ripple). |
| `RELOADING` | Fire sequence complete. Waiting for `reload_timer`. |
| `DISABLED` | Battery is non-functional due to damage. Cannot fire. |

---

## 3. Transition Table

| From | To | Condition |
|------|----|-----------|
| `IDLE` | `AIMING` | Target assigned and exists |
| `AIMING` | `IDLE` | Target lost |
| `AIMING` | `READY` | Target in arc AND target in range |
| `READY` | `AIMING` | Target leaves arc or range |
| `READY` | `FIRING` | Fire input received (player or autofire) |
| `FIRING` | `RELOADING` | Fire sequence complete (see Section 5) |
| `RELOADING` | `AIMING` | `reload_timer <= 0` AND target exists |
| `RELOADING` | `IDLE` | `reload_timer <= 0` AND no target |
| `ANY` | `DISABLED` | Battery HP reaches zero / damage event |
| `DISABLED` | `IDLE` | Repair complete (future system) |

---

## 4. Battery Data Model

These are the fields owned by each `BatteryController` instance.

### Core Fields

| Field | Type | Description |
|-------|------|-------------|
| `side` | enum (`PORT`, `STARBOARD`, `FORWARD`, `AFT`) | Which side of the ship |
| `cannon_count` | int | Number of cannons in this battery |
| `weapon_type` | enum | Cannon size/type (e.g., `LIGHT`, `MEDIUM`, `HEAVY`) |
| `ammo_type` | enum | Current load (e.g., `ROUND_SHOT`, `CHAIN_SHOT`, `GRAPESHOT`) |
| `state` | enum | Current battery state |
| `fire_mode` | enum (`SALVO`, `RIPPLE`) | Current firing mode |
| `reload_time` | float | Seconds to reload after a full fire sequence |
| `reload_timer` | float | Current countdown |
| `firing_arc_degrees` | float | Half-angle of valid fire arc from ship side normal |
| `max_range` | float | Maximum effective range in world units |
| `auto_fire_enabled` | bool | Whether battery fires automatically when READY |
| `cannon_elevation` | float [0.0–1.0] | Quoin: **0 → −5°**, **1 → +10°** depression/elevation; **~0.333 → 0°** (see `elevation_degrees()`) |
| `ELEV_MIN_DEG` / `ELEV_MAX_DEG` | const | **−5°** / **+10°** — barrel limits used by ballistics (`CannonBallistics.initial_velocity` receives `elevation_degrees()`) |

### Ripple-Only Fields

| Field | Type | Description |
|-------|------|-------------|
| `fire_sequence_duration` | float | Total time for all cannons to fire in ripple mode |
| `shots_remaining_in_sequence` | int | How many cannons still need to fire |
| `sequence_timer` | float | Countdown between individual cannon shots |

`ripple_interval` is derived, not stored:

```gdscript
var ripple_interval: float:
    get: return fire_sequence_duration / cannon_count
```

---

## 5. Fire Modes

Fire mode is a configuration value on the battery. It is not a separate state machine — it changes behavior **inside the `FIRING` state**.

### 5.1 SALVO

All cannons fire simultaneously.

**On enter FIRING (salvo):**
```gdscript
fire_all_cannons()      # emit volley signal / apply damage
reload_timer = reload_time
state = RELOADING
```

The battery transitions to `RELOADING` immediately after firing. `FIRING` is a one-frame state in salvo mode.

**Feel:** Powerful, punchy, decisive. Classic broadside. Strong burst, longer cooldown.

### 5.2 RIPPLE

Cannons fire one by one over `fire_sequence_duration`.

**On enter FIRING (ripple):**
```gdscript
shots_remaining_in_sequence = cannon_count
sequence_timer = 0.0
# state remains FIRING
```

**During FIRING (ripple) — each frame:**
```gdscript
sequence_timer -= delta
if sequence_timer <= 0.0 and shots_remaining_in_sequence > 0:
    fire_one_ripple_shot()
    shots_remaining_in_sequence -= 1
    sequence_timer = ripple_interval

if shots_remaining_in_sequence <= 0:
    reload_timer = reload_time
    state = RELOADING
```

**Feel:** Controlled, rolling thunder, better visual pacing. Same or slightly lower total damage than salvo. More forgiving for hit consistency.

### 5.3 Damage Model

For v1, both modes deal the same total damage per full sequence. Ripple distributes this across `cannon_count` mini-shots.

| Mode | Damage Per Event | Events | Total Damage |
|------|-----------------|--------|--------------|
| Salvo | `battery_damage` | 1 | `battery_damage` |
| Ripple | `battery_damage / cannon_count` | `cannon_count` | `battery_damage` |

This keeps balance symmetric for v1. After playtesting, Option B (salvo = higher burst, ripple = slightly lower total) can be tuned via a `ripple_damage_factor` multiplier.

---

## 6. Targeting Requirements

The battery transitions from `AIMING` to `READY` only when all three conditions are true:

```gdscript
func is_target_valid() -> bool:
    return (
        target_exists
        and target_on_correct_side()
        and target_in_arc()
        and target_in_range()
    )
```

### 6.1 Target on Correct Side

A port battery cannot fire at targets on the starboard side, and vice versa. This is checked by computing the bearing from the ship to the target and comparing it to the battery's side.

### 6.2 Target in Arc

`firing_arc_degrees` defines a half-angle cone from the perpendicular of the battery's side. A typical broadside battery might have a `firing_arc_degrees` of `45°` (90° total firing cone).

### 6.3 Target in Range

```gdscript
distance_to_target <= max_range
```

Minimum range is not enforced in v1 but is reserved as a future parameter.

---

## 7. Autofire

When `auto_fire_enabled = true`, the battery fires automatically upon entering `READY`:

```gdscript
if state == READY and auto_fire_enabled:
    state = FIRING
    # execute fire mode logic
```

Autofire is the default behavior for AI-controlled ships. Player ships may expose this as a toggle.

---

## 8. Signals

Battery state changes and firing events should emit signals for VFX, audio, and UI systems to consume.

```gdscript
signal battery_state_changed(battery: BatteryController, new_state: BatteryState)
signal cannon_fired(battery: BatteryController, shot_index: int)   # ripple: per shot
signal volley_fired(battery: BatteryController)                     # salvo: full volley
signal reload_started(battery: BatteryController)
signal reload_complete(battery: BatteryController)
signal battery_disabled(battery: BatteryController)
```

---

## 9. Pseudocode — Full State Update

```gdscript
func _physics_process(delta: float) -> void:
    if state == DISABLED:
        return

    if state == RELOADING:
        reload_timer -= delta
        if reload_timer <= 0.0:
            state = AIMING if target_exists else IDLE
        return

    if not target_exists:
        state = IDLE
        return

    # Target exists
    if is_target_valid():
        state = READY
        if fire_pressed or auto_fire_enabled:
            _enter_firing()
    else:
        state = AIMING

func _enter_firing() -> void:
    state = FIRING
    if fire_mode == SALVO:
        volley_fired.emit(self)
        reload_timer = reload_time
        state = RELOADING
    elif fire_mode == RIPPLE:
        shots_remaining_in_sequence = cannon_count
        sequence_timer = 0.0

func _process_ripple(delta: float) -> void:
    if state != FIRING or fire_mode != RIPPLE:
        return
    sequence_timer -= delta
    if sequence_timer <= 0.0 and shots_remaining_in_sequence > 0:
        cannon_fired.emit(self, cannon_count - shots_remaining_in_sequence)
        shots_remaining_in_sequence -= 1
        sequence_timer = ripple_interval
    if shots_remaining_in_sequence <= 0:
        reload_timer = reload_time
        state = RELOADING
        reload_started.emit(self)
```

---

## 10. Tuning Parameters

| Parameter | Recommended Starting Value | Notes |
|-----------|---------------------------|-------|
| `reload_time` | `6.0` – `12.0` seconds | Tune per weapon class |
| `fire_sequence_duration` | `1.0` – `1.5` seconds | For ripple across all cannons |
| `firing_arc_degrees` | `45.0` (half-angle, 90° total) | Standard broadside |
| `max_range` | TBD per weapon type | World units |
| `cannon_count` | `4` – `12` per battery | Tune per ship class |

Example ripple timing (6 cannons, 1.2 sec duration):
- `ripple_interval = 1.2 / 6 = 0.2 sec`
- First cannon fires at frame entry, last fires at 1.0 sec, reload begins at 1.2 sec

---

## 11. Godot Implementation Notes

- Each battery is a `BatteryController` node attached to the ship scene
- Multiple batteries (port, starboard) are independent nodes with shared config data
- `BatteryController` reads targeting data from a shared `CombatTarget` node or resource
- `fire_pressed` should be routed through a `WeaponInputController` that maps player input to the correct battery based on context
- State transitions emit signals; downstream systems (VFX, audio) connect to signals — they never poll `state` directly
- `fire_mode` can be toggled at runtime; changing mode mid-reload is permitted but takes effect on the next fire sequence

---

## 12. Out of Scope for V1

- Individual cannon simulation (position, cooldown, aim)
- Ammunition inventory / resupply
- Chain shot, grapeshot mechanics (ammo type field is reserved)
- Board-to-board range detection (future)
- Battery damage HP (DISABLED state trigger is reserved for damage system integration)
- Per-gun traverse animation and non-uniform battery elevation (single quoin value per battery drives ballistics today)

**Note:** Continuous **quoin elevation (−5°…+10°)** **is** in scope for v1 Blacksite; it affects projectile **initial velocity** via `CannonBallistics`, not a separate fudge multiplier on `vz` only.
