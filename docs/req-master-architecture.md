# Naval Combat Prototype — Master State Architecture

**Project:** Naval Game
**Document:** System Overview + Ship Class Taxonomy
**Engine:** Godot (GDScript)
**Date:** 2026-03-22
**Version:** 1.0

---

## 1. Purpose

This document defines the complete state system architecture for the naval combat prototype and the ship class taxonomy that feeds into it. Individual systems are specified in their own requirement documents. This document covers how they relate, what the recommended build priority is, and how ship classes differentiate through shared systems rather than separate ones.

---

## 2. Ship Class Taxonomy

Three ship classes form the v1 roster. Each maps to a distinct gameplay archetype. All classes share the same state machine systems — they differ only through configuration values and which optional sub-states are enabled.

### 2.1 Schooner — Speed / Precision Class

**Role:** Fast attack, scouting, kiting

**Characteristics:**
- High acceleration and top speed
- Tight turning radius, low inertia
- Light armament (fewer cannons per battery)
- Long coasting momentum (low drag)

**V1 Ship Types:**

| Type | Description |
|------|-------------|
| Light Schooner | Scout variant. Minimal guns, extended visibility. |
| Raider Schooner | Slightly heavier guns. Hit-and-run optimized. |
| Interceptor Schooner | Fastest variant. Anti-pursuit role. |

**State System Modifiers:**
- `wheel_turn_rate`: HIGH
- `acceleration_rate`: HIGH
- `passive_water_drag`: LOW (generous coast)
- `turn_acceleration`: HIGH
- Battery: single battery per side, fast reload

---

### 2.2 Galley — Control / Tactical Class

**Role:** Maneuver control, close-range dominance, independent of wind

**Characteristics:**
- Oar + sail hybrid — can enter `ROWING` sub-state
- Strong forward-facing armament
- High maneuverability
- Moderate armor

**V1 Ship Types:**

| Type | Description |
|------|-------------|
| Light Galley | High maneuverability, weak armor. |
| War Galley | Reinforced hull, heavy forward cannons. |
| Boarding Galley | Close combat optimized. (Boarding mechanics: future scope.) |

**State System Modifiers:**
- `wheel_turn_rate`: HIGH
- `rudder_follow_rate`: MEDIUM
- `acceleration_rate`: MEDIUM
- Battery: forward-arc battery; targeting requires target in forward cone

**Unique Sub-State — ROWING:**
- Available within `NavigationState`
- Speed is constant regardless of `current_sail_level`
- Ignores wind (future system)
- Depletes stamina/resource (future system)
- Enabled only for Galley class ships

---

### 2.3 Brig — Power / Line Combat Class

**Role:** Broadside combat, durability, sustained engagement

**Characteristics:**
- Two masts (square rig)
- Slow acceleration, high inertia
- Strong port and starboard broadsides
- Heavy hull

**V1 Ship Types:**

| Type | Description |
|------|-------------|
| Light Brig | Balanced entry ship. |
| War Brig | Strong broadsides, slower turning. |
| Heavy Brig | Tank archetype, maximum cannon count. |

**State System Modifiers:**
- `wheel_turn_rate`: LOW
- `turn_acceleration`: LOW
- `turn_damping`: HIGH (stiff angular momentum)
- `acceleration_rate`: LOW
- Battery: independent PORT and STARBOARD batteries; both support SALVO and RIPPLE fire modes

---

### 2.4 Per-Class Parameter Summary

| Parameter | Schooner | Galley | Brig |
|-----------|----------|--------|------|
| `acceleration_rate` | HIGH | MEDIUM | LOW |
| `passive_water_drag` | LOW | MEDIUM | MEDIUM |
| `wheel_turn_rate` | HIGH | HIGH | LOW |
| `rudder_follow_rate` | HIGH | MEDIUM | LOW |
| `turn_acceleration` | HIGH | HIGH | LOW |
| `turn_damping` | LOW | MEDIUM | HIGH |
| `cannon_count` (per battery) | LOW (2–4) | MEDIUM (4–6) | HIGH (6–12) |
| `reload_time` | SHORT | MEDIUM | LONG |
| ROWING sub-state | No | Yes | No |
| Forward-arc battery | No | Yes | No |
| Broadside batteries | Yes | No | Yes |
| SALVO + RIPPLE modes | Optional | No | Yes |

---

## 3. Full State System List

The complete prototype is built from the following state systems. Each system runs independently but shares a context object with the others.

### Tier 1 — Core Prototype (Must-Have)

| System | Document | Purpose |
|--------|----------|---------|
| Sail FSM | `req-sail-fsm.md` | Controls propulsion target and sail deployment |
| Helm FSM | `req-helm-fsm.md` | Controls wheel position and rudder angle |
| Motion FSM | `req-motion-fsm.md` | Integrates speed/heading; classifies motion state |
| Battery FSM | `req-battery-fsm.md` | Manages cannon targeting, firing, and reload |
| Ship Integrity | *(future doc)* | Hull HP thresholds: Operational → Sinking → Destroyed |
| Damage Zones | *(future doc)* | Per-zone states: hull sections, masts, rudder, gun decks |
| Flooding | *(future doc)* | Staged sinking: Dry → Leaking → Flooding → Foundering |
| Rigging Condition | *(future doc)* | Whether sails can physically respond to sail FSM commands |
| Targeting Solution | *(future doc)* | Arc, range, bearing checks; drives Battery FSM transitions |
| Match State | *(future doc)* | LoadIn → CombatActive → Victory/Defeat → Restart |

### Tier 2 — High Value

| System | Purpose | Status |
|--------|---------|--------|
| Repair / Recovery FSM | Crew assignment for hull, rigging, weapon, flood repair | Future |
| Crew / Station Readiness | Reload speed modifiers, manning penalties | Future |
| AI Captain FSM | Patrol → Approach → Broadside → Evade → Disengage (see `req-ai-naval-bot-v1.md`) | **Implemented** — `NavalBotController` + LimboAI BT |
| Combat Evaluator | Broadside quality scoring, engagement bands (see `req-combat-loop-v1.md`) | **Implemented** — `NavalCombatEvaluator` |
| Local Sim Controller | Bot spawning for local testing (see `req-local-sim-v1.md`) | **Implemented** — `LocalSimController` |
| Combat Debug | HUD, draw overlays, logging (see `req-debug-combat-v1.md`) | **Implemented** — arena debug draw |
| Camera State | Follow → CombatBroadside → AimMode → CinematicImpact | Partial |
| Scoreboard | Per-player kills, deaths, shots_fired, shots_hit, damage_dealt, damage_taken (Tab key) | **Implemented** |
| Multiplayer Sync | SteamMultiplayerPeer, host-authority, 15-field naval state RPC | **Implemented** |
| Ramming | Server-authoritative hull contact damage with cooldowns | **Implemented** |
| Respawn | Server-authoritative ship respawn after destruction | **Implemented** |

### Tier 3 — Polish / Depth

| System | Purpose |
|--------|---------|
| Fire / Burn FSM | Per-zone fire spreading; sail/deck/hull damage over time |
| UI Alert State | Drives HUD warnings: TakingWater, FireOnDeck, RudderDamaged |
| Morale / Panic | Crew efficiency degradation under sustained damage |

---

## 4. State System Architecture

All state systems are coordinated through a shared `ShipContext` resource. This prevents direct dependencies between systems and makes individual systems testable in isolation.

```
Ship (root node)
├── ShipContext          ← shared data resource
│
├── SailController       ← reads input, outputs target_sail_level / current_sail_level
├── HelmController       ← reads input, outputs wheel_position / rudder_angle
├── ShipController       ← reads Sail + Helm, integrates physics, classifies motion state
│
├── BatteryController (Port)
├── BatteryController (Starboard)   ← each reads ShipContext for target data
│
├── IntegrityController  ← reads damage events, maintains hull state
├── FloodingController   ← reads hull breach events, advances flood state
├── RiggingController    ← reads damage events, caps SailController output
│
└── MatchController      ← manages game loop state, enables/disables other systems
```

### 4.1 ShipContext Fields

`ShipContext` is a shared `Resource` (or `Node`) that all controllers read from and write their outputs to. No controller directly references another controller.

```gdscript
# Motion
var current_speed: float
var target_speed: float
var heading: float
var angular_velocity: float
var motion_state: MotionState

# Sail
var current_sail_level: float
var target_sail_level: float

# Helm
var wheel_position: float
var rudder_angle: float

# Combat
var has_target: bool
var target_node: Node
var target_distance: float
var target_bearing: float

# Integrity
var hull_integrity_state: HullState
var flooding_state: FloodingState
var rigging_state: RiggingState
```

---

## 5. Design Rules

**Rule 1: One canonical state machine. Parameters differentiate ship classes.**
Do not create separate state machine code per ship class. Every ship runs the same FSMs. Class feel comes from tuning values and which optional sub-states are active.

**Rule 2: State machines produce outputs. They do not move the ship.**
`SailController` produces `target_sail_level`. `HelmController` produces `rudder_angle`. `ShipController` does the integration. This separation keeps each system testable.

**Rule 3: Downstream systems read signals, not state.**
VFX, audio, UI, and camera systems connect to signals emitted on state transitions. They never poll `state` in `_process`.

**Rule 4: Damage affects parameters, not state logic.**
A damaged mast doesn't change how the Sail FSM works — it lowers the cap on `current_sail_level`. A damaged rudder doesn't change the Helm FSM — it lowers `rudder_follow_rate`. This keeps combat consequence clean and predictable.

**Rule 5: The match state gate-controls all other systems.**
During `LoadIn` and `Restart`, input is disabled and controllers do not process. `MatchController` enables subsystems at `EngagementStart`.

---

## 6. Prototype Success Criteria

The prototype is "real" when it can answer all of these questions:

| Question | System Required |
|----------|----------------|
| Can the ship move naturally with weight and inertia? | Sail FSM + Helm FSM + Motion FSM |
| Can it aim and fire with readable broadside logic? | Battery FSM + Targeting Solution |
| Can different parts of the ship be damaged independently? | Damage Zones |
| Can the ship become slower and less maneuverable from damage? | Rigging + Rudder damage → parameter modifiers |
| Can the ship sink in a staged, readable way? | Integrity + Flooding |
| Can the player understand what's wrong and what to do? | UI Alert State |
| Can an enemy fight back? | AI Captain FSM |
| Does the game have a start and end? | Match State |

---

## 7. V1 Build Order

Recommended implementation sequence for reaching first playable:

1. `SailController` + `HelmController` + `ShipController` — basic movement
2. `BatteryController` (Brig, port/starboard, salvo only) — basic firing
3. `MotionStateResolver` — classify motion for VFX hooks
4. Add RIPPLE fire mode to battery
5. `MatchController` (minimal: Ready → Combat → End)
6. `TargetingSolutionController` — arc/range checks feeding Battery FSM
7. `IntegrityController` (HP thresholds only, no zones yet)
8. `FloodingController` (linear progression only)
9. `RiggingController` (cap on max sail level)
10. `DamageZoneController` (per-zone states, feed modifiers into above)
11. Basic `AIController` (Approach + Broadside loop)
12. `CameraStateController`

---

## 8. Document Index

| Document | System |
|----------|--------|
| `req-sail-fsm.md` | Sail / Speed State Machine |
| `req-helm-fsm.md` | Helm / Turning State Machine |
| `req-motion-fsm.md` | Ship Motion State Machine |
| `req-battery-fsm.md` | Cannon Battery State Machine |
| `req-master-architecture.md` | This document |
| `req-combat-loop-v1.md` | Broadside Quality, Engagement Bands, Pass Rhythm |
| `req-ai-naval-bot-v1.md` | LimboAI Bot Controller and Behavior Tree |
| `req-local-sim-v1.md` | Local Simulation Bot Spawning |
| `req-debug-combat-v1.md` | Combat Debug Visualization and Telemetry |
| *(future)* `req-integrity.md` | Ship Hull Integrity |
| *(future)* `req-damage-zones.md` | Per-Zone Damage States |
| *(future)* `req-flooding.md` | Flooding / Buoyancy State |
| *(future)* `req-rigging.md` | Sail / Rigging Condition |
| *(future)* `req-targeting.md` | Combat Targeting Solution |
| *(future)* `req-repair.md` | Repair / Recovery FSM |
| *(future)* `req-ai.md` | AI Captain State Machine |
| *(future)* `req-match.md` | Match / Encounter State |
| *(future)* `req-camera.md` | Camera State Machine |
