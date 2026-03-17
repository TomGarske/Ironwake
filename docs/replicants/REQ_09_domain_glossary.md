# REQ_09: Domain Glossary
**Replicants: Swarm Command**

---

## Core Game Concepts

### Replicant
A **self-replicating mechanical entity** of insectoid design. Replicants are the player's units—autonomous agents that harvest resources and assimilate facility structures. Inspired by the Replicators from Stargate SG-1, but grounded in a facility-bound survival premise. Players **ARE** the replicants in this narrative.

**Related:** Swarm, Colony, Assimilation.

---

### Swarm
The **collective entity** of all player-controlled Replicant units operating as a single strategic force. The swarm is the protagonist; individual units are subordinate actors. Swarm behavior is emergent—driven by unit autonomy and player-issued commands.

**Example:** "The swarm has grown to 20 units; it's time to push deeper into the facility."

**Related:** Replicant, Unit, Autonomous Behavior.

---

### Harvester
A **Replicant unit type** specialized in resource gathering. Harvesters seek metal deposits, enter them, and extract metal at a constant rate (1 metal/sec). Metal is immediately added to the shared economy. Harvesters are fragile but essential to economic sustainability.

**Stats:** Speed 80 px/sec, Health 20 HP, Damage N/A (non-combat).

**Related:** Metal, MetalDeposit, ReplicationHub.

---

### Scout
A **Replicant unit type** specialized in reconnaissance. Scouts are fast and reveal fog of war as they move through the facility. They identify resistance positions and mark new resources. Scouts are extremely fragile and unsuitable for direct combat.

**Stats:** Speed 150 px/sec, Health 5 HP, Damage N/A (non-combat).

**Related:** Fog of War, Detection, Resistance.

---

### Soldier
A **Replicant unit type** specialized in combat. Soldiers engage and destroy resistance units through melee attacks. They form the primary offensive force of the swarm. Soldiers are moderately durable and respond well to Protocol commands.

**Stats:** Speed 110 px/sec, Health 40 HP, Damage 8/hit, Attack Range 30px.

**Related:** Swarm Rush, Combat, Resistance.

---

### Builder
A **Replicant unit type** specialized in infrastructure expansion. Builders place new ReplicationHubs in designated locations, extending the swarm's production network and territorial control. Builders are slower but more durable than Harvesters.

**Stats:** Speed 90 px/sec, Health 35 HP, Damage N/A (non-combat).

**Related:** ReplicationHub, Network, Expansion.

---

### Assimilator
A **Replicant unit type** specialized in conversion (late-game). Assimilators absorb Resistance structures (Turrets, bases, tech) and convert them into swarm resources (metal). Assimilators are the swarm's most durable units and create a secondary economy during RESISTANCE_SURGE.

**Stats:** Speed 100 px/sec, Health 50 HP, Damage N/A (conversion-based).

**Related:** Assimilation, Assimilation Wave, Metal.

---

## Resource and Economy

### Metal
The **primary resource** in Replicants. Metal is harvested from deposits, spent on replication, and earned through assimilation. Metal is the only quantifiable resource; scarcity drives strategy.

**Sources:** Harvester extraction, Assimilator conversion.

**Sinks:** Replication (unit production), Protocol commands (Rapid Replication).

**Economy:** Spend on growth to expand territory; expand to discover resources and resistance.

**Related:** Harvester, MetalDeposit, Replication.

---

### MetalDeposit
A **facility resource node** containing extractable metal. Deposits are scattered across the map and vary by size (Small: 40 metal, Medium: 100, Large: 250). Harvesters automatically extract when in proximity. Deposits deplete over time.

**Types:**
- **Small:** Fast depletion, lightly guarded or unguarded.
- **Medium:** Moderate yield, possibly guarded.
- **Large:** High-value, heavily guarded by Resistance.

**Related:** Harvester, Metal, Economy.

---

### Replication
The **process of producing new Replicant units** at a ReplicationHub using metal from the shared economy. Replication is queue-based; multiple units can be queued and are produced in order (FIFO). Production time is fixed per unit (6 seconds base).

**Queue:** FIFO system, max 5 units queued per hub.

**Cost Scaling:** Costs increase per mission phase (AWAKENING < EARLY_COLONY < EXPANSION < RESISTANCE_SURGE).

**Related:** ReplicationHub, Metal, Protocol Command (Rapid Replication).

---

### ReplicationHub
A **stationary production facility** operated by the swarm. Hubs consume metal and produce new Replicant units. Hubs can be placed by Builder units or initialized on the map. Multiple hubs can operate in parallel, accelerating production.

**Placement:** Builder units place hubs on designated terrain.

**Production:** Queue up to 5 units per hub; FIFO processing.

**Range:** Passively assimilates nearby zones (0.5% per sec).

**Related:** Replication, Builder, Assimilation.

---

## Swarm Behavior and Command

### Protocol Command
A **high-level strategic directive** issued by the player to the swarm. Protocols override unit autonomy temporarily and create tactical effects (movement, combat concentration, defensive positioning). Protocols have cooldowns and resource costs.

**Types:**
1. **Swarm Rush:** Direct soldiers to attack a location.
2. **Rapid Replication:** Double production speed (15 sec, costs 20 metal).
3. **Scatter:** Disperse units to avoid area attacks.
4. **Defensive Formation:** Units group and hold position.
5. **Assimilation Wave:** Assimilators sacrifice to rapidly convert enemy structures.

**Activation:** Protocol wheel (hold input) or quick-select (D-Pad / number keys).

**Related:** Swarm, Autonomy, Command Layer.

---

### Swarm Rush
A **Protocol command** that concentrates soldier firepower on a single target location or resistance unit. Soldiers move at 2× speed to the target and attack for 10 seconds, then resume autonomous behavior.

**Cost:** Free.

**Cooldown:** 20 seconds.

**Effect:** All nearby Soldiers (within 80px) are targeted. Soldiers move and engage enemies at location for 10 seconds.

**Use Case:** Concentrate force on Turrets or Commanders; break through defensive lines.

**Related:** Protocol Command, Soldier.

---

### Rapid Replication
A **Protocol command** that temporarily accelerates unit production at all ReplicationHubs. Production speed doubles for 15 seconds, allowing rapid swarm scaling.

**Cost:** 20 metal.

**Cooldown:** 45 seconds.

**Effect:** All queued units produce at 2× speed (3 seconds per unit instead of 6).

**Use Case:** Bulk-produce Soldiers in response to escalation; scale swarm quickly when resources are abundant.

**Related:** Protocol Command, Replication.

---

### Scatter
A **Protocol command** that disperses nearby units in random directions to avoid area attacks (EMP bursts, Turret sweeps). Units occupy scattered positions for 8 seconds, then resume autonomy.

**Cost:** Free.

**Cooldown:** 8 seconds (very fast).

**Effect:** Units within 120px disperse 60–80px in random directions; hold scattered positions for 8 seconds.

**Use Case:** Emergency defensive panic button; avoid EMP disables or concentrated area damage.

**Related:** Protocol Command, Defensive.

---

### Defensive Formation
A **Protocol command** that groups nearby units into a cohesive defensive cluster at a designated position. Units take 30% reduced damage from ranged attacks while holding formation.

**Cost:** Free.

**Cooldown:** 25 seconds.

**Effect:** Units move to designated holding position and form loose cluster (16–24px spacing); 30% damage reduction applied while holding.

**Use Case:** Protect ReplicationHubs or chokepoints; regroup before assault.

**Related:** Protocol Command, Defense.

---

### Assimilation Wave
A **Protocol command** (late game, RESISTANCE_SURGE+) that directs all Assimilators to charge forward and sacrifice themselves converting enemy structures at high speed.

**Cost:** 1 Assimilator per target (unit is sacrificed).

**Cooldown:** 30 seconds.

**Effect:** Assimilators move forward; each assimilates a structure at 10 metal/sec (2–3 sec per target), then sacrifices itself (dissolves).

**Use Case:** Breach heavily fortified positions; convert enemy defenses into metal income; push deep into resistant territory.

**Related:** Protocol Command, Assimilator, Assimilation.

---

### Autonomous Behavior
The **default behavioral state** of Replicant units. Each unit type follows a role-driven behavior tree (LimboAI):
- **Harvester:** Seek deposits → approach → extract.
- **Scout:** Patrol → reveal fog → alert to threats.
- **Soldier:** Patrol → detect enemy → engage → retreat if outnumbered.
- **Builder:** Idle → await placement command → construct.
- **Assimilator:** Idle → patrol → detect structure → assimilate.

Units resume autonomous behavior after Protocol command duration expires or objective is reached.

**Related:** Command Override, Protocol Command, Swarm.

---

### Command Layer
The **player interface** for directing the swarm. The command layer issues strategic directives (Swarm Rush, Rapid Replication) that override unit autonomy temporarily. The layer is distinct from unit-level tactical control; players command strategy, not micro-manage individuals.

**Contrast:** Traditional RTS (direct control of individual units) vs. Replicants (strategic command of swarm roles).

**Related:** Protocol Command, Autonomous Behavior.

---

## Assimilation and Resistance

### Assimilation
The **process of converting facility territory and structures into swarm-controlled assets**. Assimilation occurs when Assimilators or ReplicationHubs occupy zones for extended periods. Visually, assimilated zones transform from facility aesthetic (gray/blue) to replicant aesthetic (cyan/metallic).

**Mechanics:**
- **Per-Zone:** Each facility zone tracks assimilation % (0–100%).
- **Passive:** ReplicationHubs assimilate at 0.5% per sec.
- **Active:** Assimilators assimilate at 1% per sec.
- **Protocol:** Assimilation Wave spikes assimilation at 10% per sacrificed unit.

**Victory Linkage:** Assimilation % is primary victory metric (reach 50%+ to win).

**Related:** AssimilationZone, Replicant Spread.

---

### AssimilationZone
A **game world node** representing a distinct facility area that can be assimilated. Each zone tracks assimilation percentage, applies shader-based visual transformation, and counts toward overall facility assimilation progress.

**Properties:**
- Assigned coordinates and boundaries.
- Assimilation percentage (0–100%).
- Visual transformation (facility → replicant).
- Objective contribution (e.g., zone worth 10–30% of facility).

**Related:** Assimilation, World Design.

---

### Resistance
The **environmental opposition** to the swarm—security systems, automated turrets, military personnel designed to contain replicants. Resistance is not player-controlled; it's server-authoritative AI.

**Components:**
- **Patrol Units:** Mobile, roaming guardians.
- **Turrets:** Static, area-denial.
- **EMP Drones:** Disruptors (stun swarm units).
- **Commanders:** Force multipliers (buff other resistance units).
- **Reaction Forces:** Reinforcements spawned on escalation.

**Goal:** Eliminate or avoid Resistance to progress assimilation.

**Related:** ResistanceAI, Escalation, Opposition.

---

### Resistance Surge
The **RESISTANCE_SURGE mission state** triggered when swarm size > 20 units or assimilation > 30%. The facility's automated defenses escalate dramatically: Commanders activate, EMP Drones deploy, Reaction Forces are called in continuously.

**Duration:** ~5–8 minutes (intense phase).

**Objective:** Neutralize all Commanders + maintain assimilation > 45% for 2 minutes.

**Pressure:** Metal income drops 30% (harvesting disrupted); costs spike 100%.

**Strategy Shift:** Economy becomes scarce; Assimilation (conversion) becomes primary metal income.

**Related:** Escalation, Mission State.

---

### Escalation
The **dynamic difficulty spike** triggered when player progress crosses thresholds (swarm size, assimilation %). Escalation spawns new Resistance units and transitions mission state.

**Triggers:**
- Swarm size > 20 → RESISTANCE_SURGE.
- Assimilation > 30% → RESISTANCE_SURGE.
- Swarm enters new zone → Local reinforcements (+1–2 Patrol Units).
- Assimilator starts assimilating structure → Emergency response (+1 Commander, +2 Patrols).

**Effect:** Difficulty increases gradually, then surges at major thresholds.

**Related:** Resistance Surge, Dynamic Difficulty.

---

### Fog of War
The **visual layer obscuring unexplored facility areas**. Fog of War shrouds unknown zones (dark overlay). Scout units reveal areas within their detection radius. Once revealed, zones remain visible (no re-shrouding).

**Mechanics:**
- **Initial State:** Entire facility shrouded except starting area.
- **Reveal:** Scouts reveal 100px radius around themselves.
- **Persistence:** Revealed areas remain visible indefinitely.
- **Resistance Vision:** Resistance units hidden in FoW until revealed.

**Related:** Scout, Exploration, Map Knowledge.

---

## Mission and Game States

### Awakening Phase
The **AWAKENING mission state** where the swarm first becomes conscious. This is a tutorial-style level introducing core mechanics (harvest, replicate, engage resistance). Awakening is brief (2–3 minutes) and heavily guided.

**Units:** Single Harvester + Soldier provided.

**Objective:** Harvest → produce soldier → defeat patrol unit.

**Pressure:** Minimal. Single large metal deposit, one patrol unit.

**Progression:** Automatic → EARLY_COLONY on completion.

**Related:** Mission State, Tutorial.

---

### Colony Core
The **central replication nexus** of the swarm (advanced concept, not in MVP). The Colony Core is the swarm's heart; if destroyed, the swarm loses. Cores must be defended and can produce units independently.

**Status:** Post-MVP feature; MVP uses a shared MetalEconomy instead.

**Related:** Replication, Swarm Vulnerability.

---

## Combat and Threat

### EMP (Electromagnetic Pulse)
A **disruptive effect** deployed by EMP Drones. EMP bursts disable all Replicant units within 80px radius for 5 seconds (units cannot move or attack). EMP is a tactical threat forcing swarm dispersal or retreat.

**Duration:** 5 seconds (stun).

**Cooldown:** 15 seconds (EMP Drone recharge).

**Counterplay:** Scatter protocol (disperse units before EMP fires).

**Related:** EMP Drone, Disrupt.

---

### Priority Target
A **designation system** for AI targeting** indicating high-value enemy units. Turrets prioritize Assimilators > Soldiers > Harvesters. Patrol Units prioritize Commanders > Turrets > individual swarm units. Strategic positioning of units affects threat distribution.

**Related:** AI Targeting, Combat Priority.

---

## Multiplayer and Cooperation

### Shared Metal Pool
In **multiplayer (co-op) mode**, all players draw from and contribute to a **single metal economy**. Metal harvested by Player A is available to Player B; unit production by Player A consumes from the shared pool.

**Benefit:** Forces cooperation and shared decision-making on resource allocation.

**Tracking:** Per-player contribution metrics recorded for end-game stats.

**Related:** Multiplayer, Economy.

---

## Visual and Audio Language

### Assimilation Creep
The **visual spread of replicant influence** across facility zones. As assimilation % increases, zones visually transform: gray concrete becomes cyan metallic, machinery corrodes and reforms, structures sprout energy conduits. Creep is continuous and organic-looking.

**Implementation:** Shader-based blending, particle effects, tilemap layer transitions.

**Related:** Assimilation, Visual Feedback.

---

### MusicManager Integration
**Replicants** uses the **shared MusicManager** from BurnBridgers infrastructure to dynamically adjust music intensity, speed, and tone based on mission state and gameplay pressure.

**Profile:** Intensity 0.92, Speed 0.88, Tone 0.90 (ominous, methodical, growing).

**State Coupling:** Music transitions from exploratory (AWAKENING) to ominous (EXPANSION) to frantic (RESISTANCE_SURGE).

**Related:** BurnBridgers Shared Infrastructure, Audio.

---

## Narrative and Thematic

### Origin Story
**Replicants** is the **origin story** of how the replicant threat began. Narrative perspective is inverted: players ARE the threat, newly awakened. The facility is the stage for first contact, and the player's mission defines the replicants' purpose and capability.

**Tension:** Facility was designed to contain replicants; players must overcome containment systems to prove viability.

**Related:** Narrative, Player Agency.

---

### Insectoid Aesthetic
The **visual and behavioral design language** of the swarm. Replicants are chitinous, segmented, and mechanically organic. Movement is decisive and precise. Attacks are coordinated and efficient. The swarm acts with hive-like coherence.

**Inspiration:** Insects (ants, termites, locust swarms) filtered through mechanical sci-fi (Terminator, Starcraft).

**Related:** Visual Design, Unit Design.

---

## Infrastructure and Architecture

### LimboAI
The **behavior tree system** used by BurnBridgers to drive AI behavior. Replicants uses LimboAI for unit autonomy (both swarm and resistance units). Behavior trees are modular, reusable, and testable.

**Integration:** Each unit type has a dedicated .tres behavior tree file.

**Related:** Autonomous Behavior, AI Architecture.

---

### BurnBridgers Shared Infrastructure
**Replicants** leverages the shared systems from the BurnBridgers project:
- **GameManager:** Game state, scene transitions, save/load.
- **SteamManager:** Online features, achievements, leaderboards.
- **LimboAI:** Behavior tree engine for AI.
- **MusicManager:** Dynamic music system.

**Principle:** Do not duplicate. Replicants-specific code only extends or uses these systems.

**Related:** Architecture, Integration.

---

## Abbreviations and Shorthand

| Abbreviation | Full Term | Context |
|--------------|-----------|---------|
| **MVP** | Minimum Viable Product | Scope: core mechanics only, 7-week build. |
| **RTS** | Real-Time Strategy | Genre reference: Starcraft, Company of Heroes. |
| **FoW** | Fog of War | Vision mechanic: unexplored areas shrouded. |
| **LimboAI** | (AI framework) | Behavior tree system for autonomous units. |
| **VFX** | Visual Effects | Particles, shaders, animation feedback. |
| **HUD** | Heads-Up Display | UI elements: metal counter, minimap, alerts. |
| **FIFO** | First-In-First-Out | Queue processing: production queue order. |

---

## Cross-References

- **World Design:** REQ_07 (world layout, zones, assimilation visuals).
- **Swarm Mechanics:** REQ_03 (unit types, protocols, autonomy).
- **Resistance AI:** REQ_06 (opposition unit types, escalation, coordination).
- **Resource Economy:** REQ_05 (metal, deposits, costs, income).
- **Game States:** REQ_02 (mission progression, victory/defeat conditions).
- **Input & Controls:** REQ_04 (command issuance, camera, protocol activation).

---

## Notes

- Terms are organized by conceptual domain (Resources, Swarm, Resistance, etc.).
- Definitions include **related terms** to show concept interconnections.
- **Status tags** (MVP, Post-MVP, Advanced) indicate implementation timing.
- Abbreviations and shorthand are listed for quick reference in code and documentation.

