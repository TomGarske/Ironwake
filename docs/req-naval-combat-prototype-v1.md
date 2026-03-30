# Naval Combat Prototype — Core Gameplay Requirements (v1.0)

## 1. Design Objectives

**Primary Goal**  
Deliver **deliberate, position-driven naval combat** with:

- High readability
- Predictable motion
- Meaningful maneuvering
- Low cognitive overload

**Player Model**

- 1 player = 1 ship
- No fleet coordination (future phase)
- Focus on **mastery of movement + firing alignment**

---

## 2. World Scale Definition

### 2.1 Tile System

| Parameter                 | Value                                |
| ------------------------- | ------------------------------------ |
| Tile size                 | **10 × 10 world units**              |
| Grid usage                | Logical only (not rendered)          |
| Camera view (recommended) | **30 × 20 tiles (~300 × 200 units)** |

### Rationale

- Provides **coarse spatial reasoning**
- Keeps combat ranges within **10–40 tile distances**
- Aligns well with ship scale

### 2.2 Ship Scale

| Parameter           | Value                     |
| ------------------- | ------------------------- |
| Ship length         | **6 tiles (60 units)**    |
| Ship width          | **2 tiles (20 units)**    |
| Collision footprint | Elliptical (centered)     |
| Cannon positions    | Port / Starboard mid-body |

> **Ironwake implementation:** Based on a 74-gun third rate (HMS Bellona): `SHIP_LENGTH_UNITS = 52.0` (168 ft), `SHIP_WIDTH_UNITS = 14.5` (47 ft). 1 world unit = 1 meter.

### Interpretation

- Ships occupy meaningful space (not point objects)
- Turning and positioning feel **intentional and constrained**

### 2.3 Map Size (Prototype)

| Parameter               | Value                                   |
| ----------------------- | --------------------------------------- |
| Map size                | **200 × 200 tiles (2000 × 2000 units)** |
| Engagement visibility   | 10–30 tiles typical                     |
| Max engagement distance | ~40–45 tiles                            |

> **Ironwake implementation:** Map size increased to **800 × 800 tiles (8000 × 8000 units)** to accommodate the larger ship scale and realistic ballistic ranges (see `naval_combat_constants.gd`).

---

## 3. Movement System Requirements

### 3.1 Speed Model

| State                 | Value                             |
| --------------------- | --------------------------------- |
| Minimum speed (drift) | **2.5 units/sec (~0.25 tiles/sec)** |
| Cruise speed          | **6 units/sec (~0.6 tiles/sec)** |
| Maximum speed         | **9 units/sec (~0.9 tiles/sec)** |

> **Ironwake implementation note:** After map-scale and ballistics tuning, the implemented speeds are higher: `MIN_SPEED_DRIFT = 2.0`, `QUARTER_SPEED = 9.0`, `CRUISE_SPEED = 16.0`, `MAX_SPEED = 27.5` game units/sec (see `naval_combat_constants.gd`). At the display scale of `_KNOTS_PER_GAME_UNIT = 0.4727`, max speed reads as ~13 knots (HMS Bellona, 74-gun third rate). 1 world unit = 1 meter.

### 3.2 Acceleration / Deceleration

| Parameter                 | Value         |
| ------------------------- | ------------- |
| Acceleration (0 → max)    | **14 seconds** |
| Deceleration (sails down) | **18 seconds** |
| Passive drift             | Always present |

> **Ironwake implementation:** `ACCEL_TIME_ZERO_TO_MAX = 10.0` sec, `DECEL_TIME_SAILS_DOWN = 22.0` sec, `SAILS_DOWN_DRIFT_SPEED = 0.0` (ship comes to full stop once momentum decays).

### Requirements

- Speed changes must feel **gradual and weighty**
- No instant velocity changes

### 3.3 Turning Model

#### Turn Rate by Speed

| Speed State  | Turn Rate   |
| ------------ | ----------- |
| Low speed    | **12°/sec** |
| Cruise speed | **6°/sec** |
| Max speed    | **3°/sec**  |

#### Turn Mechanics

| Parameter                   | Value                               |
| --------------------------- | ----------------------------------- |
| Turn input model            | Wheel-based (not instant direction) |
| Turn inertia delay          | **~2.5 seconds**                    |
| Direction change constraint | Must pass through center            |
| High-speed penalty          | Reduced responsiveness              |

### Requirements

- Turning must enforce **commitment**
- Ships should **overshoot if poorly aligned**
- No snapping or pivoting in place

---

## 4. Combat System Requirements

### 4.1 Engagement Ranges

| Range Type             | Distance                        |
| ---------------------- | ------------------------------- |
| Close range            | **<100 units (~10 tiles)**      |
| Effective combat range | **~180 units (optimal)**        |
| Maximum range          | **300 units (~30 tiles)**       |

### 4.2 Accuracy Model (Realistic, No Artificial Falloff)

- No arbitrary damage falloff
- Accuracy decreases due to:
  - Distance
  - Ship movement
  - Target movement
  - Firing angle alignment

### Requirement

> Damage is binary: **hit = full damage**, miss = zero  
> Only accuracy degrades—not damage output

### 4.3 Firing Arcs

| Parameter     | Value                 |
| ------------- | --------------------- |
| Broadside arc | **~90° per side**     |
| Dead zones    | Forward + aft         |
| Firing sides  | Port / Starboard only |

### Requirement

- Player must **position ship laterally**
- No forward-facing primary weapons

### 4.4 Reload System

| Parameter    | Value          |
| ------------ | -------------- |
| Reload time  | **18 seconds** |
| Firing modes | Salvo / Ripple |
| Reload state | Per side       |

### 4.5 Engagement Timing

| Metric                  | Value                     |
| ----------------------- | ------------------------- |
| Time to align broadside | **3–6 seconds**           |
| Time in firing range    | **25–40 seconds typical** |
| Time between volleys    | **~12 seconds**           |

### Requirement

Combat loop must be:

1. Maneuver
2. Align
3. Fire
4. Reposition

---

## 5. Pacing Requirements

### 5.1 Reaction Window

| Parameter              | Value           |
| ---------------------- | --------------- |
| Player reaction window | **3–5 seconds** |

### Requirement

- No event should require <1 second reaction
- Movement + combat must be **anticipatory, not reactive**

### 5.2 Engagement Flow

| Phase                  | Duration      |
| ---------------------- | ------------- |
| Approach               | ~15 seconds across screen  |
| Engagement             | 25–40 seconds |
| Disengage / reposition | 5–15 seconds  |

---

## 6. Camera & Readability Constraints

| Parameter      | Value                                |
| -------------- | ------------------------------------ |
| Camera zoom    | Shows **20–40 tiles width**          |
| Ship on screen | 1–3 ships visible                    |
| UI requirement | Clear facing + firing arc indicators |

---

## 7. Physics & Feel Requirements

### 7.1 Momentum

- Ships must:
  - Continue moving when input stops
  - Resist rapid direction change
  - Drift when sails are reduced

### 7.2 Collision

| Parameter      | Requirement             |
| -------------- | ----------------------- |
| Ship collision | Soft (glancing)         |
| Hard stop      | Avoid (no instant halt) |
| Ramming        | Implemented — server-authoritative damage on hull contact |

---

## 8. Success Criteria (Validation Metrics)

Prototype is successful if:

### Movement

- Player can predict ship position **2–3 seconds ahead**

### Combat

- Player can intentionally line up broadsides (not random)

### Engagement

- Battles last **15–30 seconds**, not <5 seconds

### Feel

- Ships feel:

  - Heavy
  - Committed
  - Controllable

---

## 9. Explicit Non-Goals (v1)

- No fleet control
- No wind simulation (optional later)
- No damage falloff curves
- ~~No advanced ballistics modeling~~ — Now implemented: `CannonBallistics` with real muzzle velocity (410 m/s), gravity, and elevation-based launch vectors
- No crew management

---

## 10. Implementation Notes (Godot-Oriented)

- Use **kinematic or custom physics**, not full rigidbody chaos
- Movement = velocity vector + heading vector (decoupled)
- Turn rate scaled by current speed
- Cannon fire = projectile arcs OR simplified ray with travel time

---

## Bottom Line

This spec creates:

- **Deliberate naval dueling**
- Strong positional gameplay
- Enough pacing to later scale into **fleet control without redesign**

---

## Next step (recommended)

**Weapon system + projectile model (hit probability vs simulation)** — defines whether combat feels *skillful vs random*.
