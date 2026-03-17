# REQ_01: Vision and Architecture
**Replicants: Swarm Command**

## Overview
Replicants is a cooperative strategy/RTS hybrid where players command autonomous swarm entities in their origin story. The player's perspective is inverted: *you ARE the threat*. Newly awakened mechanical insectoid replicators must harvest, replicate, and overwhelm environmental resistance in a facility designed to contain them.

> **Thematic Core:** "You ARE the threat. Awaken. Harvest. Replicate. Overwhelm."

The game focuses on strategic command-layer decision-making over direct unit control. The swarm is the primary actor; players issue orders and deploy protocols, but units act autonomously within their designated roles.

---

## Design Pillars

| Pillar | Definition |
|--------|-----------|
| **Strategic Command** | Players command, not pilot. Units execute roles autonomously; player action shapes scope and intensity. |
| **Swarm as Actor** | The collective swarm—not individuals—is the protagonist. Emergent complexity arises from unit interaction. |
| **Resource Escalation** | Metal drives growth; scarcity forces expansion; expansion invites resistance. An arms-race loop. |
| **Environmental Resistance** | Resistance scales with player progress. Escalation is dynamic, triggered by swarm size and assimilation thresholds. |
| **Origin Story Tension** | Narrative framing: first contact, awakening, and the facility's desperate containment measures failing. |

---

## Canonical Rules

### Command and Autonomy
- **Players command**, not directly pilot individual units.
- Swarm units act **autonomously within their role** (e.g., Harvester seeks deposits, Soldier targets resistance).
- Player commands **override temporary autonomy** (e.g., "Swarm Rush" orders all nearby soldiers to attack a position).
- Once a command resolves, units revert to autonomous behavior.

### Resource Scarcity and Growth
- Metal is the only primary resource. Deposits deplete over time.
- Swarms must **continuously expand** to locate new deposits.
- Expansion triggers discovery of new resistance nodes.
- Resource scarcity is a core strategic pressure.

### Resistance and Escalation
- Resistance is **environmental opposition**: security systems, automated turrets, armed forces.
- Resistance **scales dynamically** based on swarm size and assimilation percentage.
- Escalation is **not random**; it's triggered by crossing defined thresholds (e.g., swarm size > X, assimilation > Y%).
- Resistance units coordinate and employ tactics (patrol, ambush, reinforce).

### Victory and Defeat
- **Victory:** Achieve assimilation objectives (assimilate X% of facility, neutralize all designated resistance nodes, or reach final zone).
- **Defeat:** All swarm units destroyed, colony core destroyed, or timer exhausted (mission-specific).

---

## Perspective and Visual Tone

### Camera
- **Top-down RTS view**: isometric or pure top-down perspective.
- Player agency: pan, zoom, rotate (on console). View the entire swarm and strategize.

### Visual Language
- **Cold, metallic geometry**: facility architecture is clinical, sleek.
- **Insectoid aesthetic**: swarm units are chitinous, segmented, mechanical. Sharp angles, organic-industrial hybrid.
- **Assimilation creep**: as swarm assimilates, the facility visibly transforms. Clean corridors become overgrown with replicant structures; metal surfaces corrode or are reforged into swarm architecture.
- **Environmental tension**: resistance installations (turrets, barriers) are visible obstacles. Fog of war shrouds unknown zones.
- **Color palette**: cool grays, silvers, electric blues (replicant networks), harsh reds (resistance alerts).

---

## Scene Architecture

### Core Node Hierarchy

```
ReplicantsLanding (main scene root)
├── CommandNode (Player input, order resolution)
│   ├── ProtocolCommandSystem (issues and tracks player commands)
│   ├── CameraController (pan, zoom, rotation)
│   └── UILayer (HUD: metal counter, unit roster, protocol wheel, minimap)
├── SwarmLayer
│   ├── SwarmUnit (base class for all swarm entities)
│   │   ├── Harvester (seeks metal deposits, feeds ReplicationHub)
│   │   ├── Scout (reveals fog of war, identifies resistance)
│   │   ├── Soldier (combat unit, targets resistance)
│   │   ├── Builder (extends swarm network, creates new ReplicationHubs)
│   │   └── Assimilator (converts resistance tech into swarm assets — late game)
│   └── ReplicationHub (spawns new units, tied to metal economy)
├── WorldLayer
│   ├── MetalDeposit (resource node, depletes over harvest)
│   │   └── DepositMarker (visual + collider)
│   ├── AssimilationZone (Area2D, tracks territory control)
│   ├── FacilityZone (facility room/corridor, visual container)
│   └── FogOfWarLayer (dynamically revealed by Scout units)
├── ResistanceLayer
│   ├── ResistanceForce (base class for opposition units)
│   │   ├── PatrolUnit (mobile, patrols zones)
│   │   ├── Turret (static, high damage area-denial)
│   │   ├── EMPDrone (disables swarm units temporarily)
│   │   ├── Commander (buffs nearby resistance units)
│   │   └── ReactionForce (summoned on escalation trigger)
│   └── ResistanceAISystem (behavior trees, coordination)
├── GameState
│   ├── MissionState (AWAKENING, EARLY_COLONY, EXPANSION, etc.)
│   ├── EconomyManager (metal tracking, replication costs)
│   └── EscalationManager (triggers resistance surges)
└── Environment (map tiles, static obstacles, visual effects)
```

### CommandNode (Player Interface)
- Receives input (controller or mouse/keyboard).
- Validates and issues commands to the swarm.
- Tracks protocol cool-downs and resource costs.
- Coordinates multiplayer command resolution (in co-op mode).

### SwarmUnit (Autonomous Agent)
- Inherits from CharacterBody2D.
- Driven by **LimboAI behavior tree**. Each unit type has its own tree.
- Responds to role-based inputs: Harvester seeks deposits, Soldier seeks targets.
- Protocol commands inject temporary overrides (e.g., "move to X").
- Once override resolves, unit resumes autonomous behavior.

### MetalDeposit (Resource Node)
- Area2D with depletion tracking.
- Harvester units automatically extract when in proximity.
- Provides visual feedback: depleted deposits dim or disappear.

### ReplicationHub (Production)
- Stationary unit, placed by Builder or initialized on map.
- Consumes metal from the shared economy.
- Queue-based production: produces one unit at a time over a duration.
- Visual feedback: pulsing geometry, particle effects on unit birth.

### ResistanceForce (Opposition)
- Inherits from CharacterBody2D.
- Driven by LimboAI (separate behavior trees per type).
- Coordinates with ResistanceAISystem for group tactics.
- Escalates on triggers (swarm size, assimilation %, zone discovery).

### AssimilationZone (Territory Control)
- Area2D marking zones that can be assimilated.
- Tracks occupation percentage (controlled by Assimilator units or proximity to ReplicationHub).
- Visual shift on assimilation: tilemap layer changes, shader effects applied.

---

## Scene Hierarchy Diagram

```
ReplicantsLanding
│
├─ CommandNode [Player Control]
│  ├─ CameraController
│  ├─ ProtocolCommandSystem
│  └─ UILayer
│
├─ SwarmLayer [All Swarm Units]
│  ├─ Harvester_1, Harvester_2, ...
│  ├─ Scout_1, Scout_2, ...
│  ├─ Soldier_1, Soldier_2, ...
│  ├─ ReplicationHub (auto-spawns units)
│  └─ ReplicationHub_2, ReplicationHub_3, ...
│
├─ WorldLayer [Environment & Resources]
│  ├─ FacilityZone_MainCorridor
│  ├─ FacilityZone_ResourceRoom
│  ├─ MetalDeposit_Small_1
│  ├─ MetalDeposit_Medium_2
│  ├─ MetalDeposit_Large_3 (guarded)
│  ├─ AssimilationZone_1
│  ├─ FogOfWarLayer
│  └─ TilemapLayer (static obstacles)
│
├─ ResistanceLayer [Opposition]
│  ├─ PatrolUnit_1, PatrolUnit_2, ...
│  ├─ Turret_1, Turret_2, ...
│  ├─ Commander_1
│  ├─ ResistanceAISystem
│  └─ EscalationManager
│
└─ GameState [Managers]
   ├─ MissionState
   ├─ EconomyManager
   └─ SteamManager (shared from BurnBridgers)
```

---

## Implementation Notes

- **Shared Infrastructure:** Leverage BurnBridgers' GameManager, SteamManager, LimboAI, and MusicManager. Do not duplicate.
- **GDScript 4 Patterns:** Use typed classes, signal-driven state machines, and composition for behavior.
- **LimboAI Integration:** Each unit type (swarm and resistance) will have dedicated behavior trees in LimboAI format. Avoid hardcoded AI; trees drive autonomy.
- **Real-Time with Deliberate Timing:** The game runs in real-time, but Protocol commands have explicit cooldown and execution windows. This creates tactical depth.
- **Multiplayer Resilience:** All node spawning, state changes, and command processing must be authoritative (likely server-side in networked play, or Player 1 in local co-op).

---

## Key Takeaways

- Replicants is an **inversion of typical RTS narrative**: you are the swarm, the facility is the enemy.
- Design prioritizes **strategic command over tactical control**. Players shape the swarm's strategy; units execute autonomously.
- The **swarm is the actor**. Emergence and complexity come from unit behavior, not player micromanagement.
- **Resource and resistance create a feedback loop**: grow swarm → expand territory → discover resistance → escalate conflict → require more resources.
- Visually, **assimilation is the primary dynamic effect**. The facility transforms from pristine to consumed as the player progresses.
