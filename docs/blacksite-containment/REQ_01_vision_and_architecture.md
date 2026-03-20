# REQ_01: Vision and Architecture
**Blacksite Containment**

## Game Identity

Blacksite Containment is a cooperative, multiplayer drone defense action game set at a high-security sci-fi containment facility. Players pilot advanced hovering security drones assigned to containment duty, working together to intercept and eliminate escapees before they breach the perimeter. The game combines fast-paced aerial combat with strategic positioning and resource management, rewarding teamwork and split-second decision-making. Designed for 1–8 players in seamless cooperative multiplayer, Blacksite Containment emphasizes responsive controls, clarity of threat, and shared responsibility for facility security.

## Design Pillars

1. **Cooperative Clarity**: Every player sees the same threats at the same time. Shared threat detection, unified HUD information, and synchronized state ensure no player feels left out or unaware. The game is won together or not at all.

2. **Drone Mastery Through Simplicity**: Four core abilities create deep, emergent gameplay. Each ability is easy to learn (hold, tap, or toggle) but rewards mastery through charge timing, positioning, and teamwork synergy. No button bloat; every input feels necessary.

3. **Constant Forward Motion**: Patrols never pause. Escapees spawn dynamically; the threat is ever-present but not overwhelming. The game breathes with wave escalation, giving brief respites before danger increases. This tempo creates engagement without exhaustion.

4. **Sci-Fi Threat Aesthetics**: Neon threat indicators, surveillance-feed HUD, clinical facility environment, and synchronized audio-visual alarms create a visceral sense of high-stakes security work. The world feels dangerous and alive.

5. **Scalable Accessibility**: One player can survive solo; eight can coordinate sophisticated strategies. Difficulty scales smoothly with player count and wave progression. New players feel welcome; veterans find depth.

## Canonical Game Rules

- **Cooperative Only**: All players share objectives. No PVP, no competitive scoring (only cooperative bonuses).
- **No Friendly Fire**: Drone attacks cannot harm other drones. Orbital strikes and lasers pass through allies.
- **Shared Patrol Zones**: The containment arena is a unified space. Drones can occupy the same position (soft collision repulsion prevents clipping).
- **Drone Physics**: Drones float/hover freely in 3D space with no gravity. They respond instantly to movement input, move omnidirectionally, and can adjust altitude. They are not ground-bound.
- **One Perimeter**: All escapees target the same perimeter breach point (or multiple fixed breach zones). Breaches count against a shared mission integrity meter.
- **Host Authority**: The host (server) runs AI movement, collision, and damage calculations. Client drones send input and receive position/state updates.

## Player Count & Scalability

| Scenario        | Difficulty | Spawn Frequency | Elite Ratio | Notes                                      |
|-----------------|------------|-----------------|-------------|---------------------------------------------|
| 1 Player (Solo) | Baseline   | Moderate        | Low         | Fewer simultaneous escapees; forgiving timing |
| 2–3 Players     | Standard   | Moderate        | Low–Moderate | Balanced for small team coordination       |
| 4 Players       | Intended   | High            | Moderate    | Full team composition possible             |
| 5–8 Players     | Hard       | Very High       | High        | Requires strong coordination               |

## Visual Tone

**Sci-Fi Surveillance Aesthetic**: The arena resembles a high-security containment facility seen through surveillance feeds. Geometric architecture, clean lines, clinical lighting. Threat indicators (neon red) contrast sharply with neutral grays and blues.

**Clinical Blacksite Identity**: Branding consistent with the broader Blacksite universe (Blacksite Breakout, Chrimera). Sterile facility design, warning signage, visible containment infrastructure (force fields, barriers, armed gates).

**Neon Threat Indicators**: Active escapees glow with threat-colored halos. Breach zones pulse red when endangered. Drone UI elements use neon accents (cyan for data, red for danger, green for ready state).

## Godot Scene Architecture

```
blacksite_containment_arena (Node3D)
├── World
│   ├── Arena (StaticBody3D or fixed geometry)
│   │   ├── FloorPlane
│   │   ├── PerimeterWalls
│   │   ├── ContainmentLanes[] (Area3D + Path3D)
│   │   │   └── LaneCollider, LanePath
│   │   └── BreachZone (Area3D - trigger)
│   ├── SpawnManager (Node3D)
│   │   └── SpawnPoints[] (Marker3D)
│   └── Lighting & Skybox
├── Drones (Node3D)
│   ├── DronePlayer[] (CharacterBody3D)
│   │   ├── CollisionShape3D
│   │   ├── MeshInstance3D (drone model)
│   │   ├── DroneController (script)
│   │   ├── DroneAbilityManager (script)
│   │   └── DroneHUD (CanvasLayer for local player)
│   └── DroneManager (script - handles spawning, tracking)
├── Escapees (Node3D)
│   ├── EscapeeEntity[] (CharacterBody3D)
│   │   ├── CollisionShape3D
│   │   ├── MeshInstance3D
│   │   ├── NavigationAgent3D
│   │   ├── LimboAI BehaviorTree root
│   │   └── HealthComponent (script)
│   └── EscapeeManager (script - spawning, wave logic)
├── GameManager (singleton reference)
├── StateManager (script - LOBBY → BRIEFING → PATROL → etc.)
├── PerimeterDetector (Area3D + script)
├── MissionIntegrity (script - shared meter)
├── HUD (CanvasLayer)
│   ├── Minimap (viewport + script)
│   ├── SharedMeters (energy, integrity, wave count)
│   └── Alerts (breach notification layer)
└── Audio (MusicManager + SFXBus references)
```

## Key Node Classes

### DronePlayer (CharacterBody3D)
- **Physics**: Hovering character controller with no gravity, smooth velocity lerp, altitude tracking
- **Collision**: Soft repulsion from other drones and world geometry
- **Input Handling**: Receives movement, ability, and camera input; reports state to network
- **Position Authority**: Each drone owns its own position on client; host broadcasts updates

### EscapeeEntity (CharacterBody3D)
- **Navigation**: NavigationAgent3D toward perimeter breach point
- **Behavior**: LimboAI-driven state machine (SPAWNED → PATHING → ALERT → EVADING → BREACH_ATTEMPT)
- **Health**: Takes damage from laser and orbital strikes; destruction triggers event
- **Type System**: Inherits from base EscapeeEntity; subclasses define stats and behavior tweaks

### ContainmentLane (Area3D + Path3D)
- **Path**: Defines a lane route via Path3D follow geometry
- **Spawn Zone**: Area3D trigger where escapees spawn
- **Patrol Route**: Navigation hint for escapee pathfinding (not forced; escapees use NavigationMesh)
- **Visual Markers**: Lane boundaries visible in-world (subtle, clinical aesthetic)

### PerimeterBreach (Area3D + Script)
- **Trigger Zone**: Detects escapee entry
- **Consequence**: Signals mission integrity loss, plays breach alarm, notifies all drones
- **Visual Feedback**: Pulsing red zone, klaxon audio

---

**Implementation Notes:**
- All nodes should use Godot 4.1+ scripting (GDScript 2.0).
- The arena is 3D but gameplay is primarily top-down isometric view; confirm camera projection.
- Ensure PerimeterDetector and MissionIntegrity are accessible as global state (GameManager or singleton).
- Escapee spawning is data-driven: JSON or Godot resource files define wave compositions.
