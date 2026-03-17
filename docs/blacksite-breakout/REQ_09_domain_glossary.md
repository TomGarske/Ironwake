# REQ_09: Domain Glossary
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines all game-specific terminology, mechanics, and concepts used throughout Blacksite Breakout documentation and codebase. Ensures consistent language and prevents ambiguity.

---

## A

### Action Recovery
The cooldown period after an entity uses an ability during which that ability cannot be re-used. Typical recovery times: 5–8 seconds for active abilities, 40–65 seconds for ultimates. See also: Cooldown, Ability.

### Alarm Level
The current state of the facility's alert system. Ranges from QUIET (no threat) to FACILITY_ALERT (full lockdown). Alarm levels determine guard behavior and facility-wide tint/audio cues. See also: Escalate Alarm, De-escalate Alarm.

### Alarm Escalation
The process by which alarm level increases in response to guard detection or noise threshold breach. Typically progresses: QUIET → LOCAL_ALERT → SECTOR_LOCKDOWN → FACILITY_ALERT. Can be triggered by: entity detected, noise accumulated, guard engagement, system sabotage. See also: Alarm Level.

### Assimilation
The Replicator's primary resource mechanic: consuming a nearby metal object to produce 1–2 new swarm units. Each metal source depletes permanently after use. Activated by moving a unit adjacent to a MetalObject and pressing the assimilate input. No cooldown — gated by metal availability. Related: Replicator, MetalObject, Swarm Unit.

---

## B

### Backup (Guard)
When a guard detects a threat, nearby guards are notified via facility comms and converge on the threat location. Multiple guards working together increase detection and combat effectiveness. See also: Guard Response, Communication.

---

## C

### Captured
State when a downed entity is apprehended by guards after remaining incapacitated for 60+ seconds. Captured entity is permanently removed from the run. Terminal condition: if all entities are captured, the run fails. See also: Downed, Revive, Run Failed.

### Cascade Hack
Rogue AI's ultimate ability (55-second cooldown): a networked system-wide hack that simultaneously disables all cameras and unlocks all doors in the current sector for 12 seconds. Does **not** trigger an alarm — the hack leaves no trace evidence, making it the cleanest mass-sabotage in the game. Ideal for coordinated team rushes through locked sectors. See also: Rogue AI Construct, Ultimate.

### Chimera Surge
Chris's ultimate ability (60-second cooldown): a full-body expression of all accumulated Chimera Traits simultaneously. For 8 seconds, every absorbed trait fires at maximum intensity — acid drips from surfaces, cryo pulses freeze nearby guards, metal grafts deflect bullets, mycorrhizal skin cloaks movement noise, interfacing passively overloads nearby electronics. On surge end, Chris does not enter exhaustion (unlike the old Unstable Mutation model). Chimera Surge requires at least 3 active traits to activate. See also: Chris (CRISPR Anomaly), Chimera Trait, Ultimate.

### Chimera Trait
A passive biological mutation absorbed by Chris through **environmental exposure** — not combat. Each trait is tied to a specific environment type or nearby entity. Chris passively accumulates exposure time while within range of a trait source; after the required threshold, the trait is permanently absorbed for the run. Max 5 traits active simultaneously. Trait sources and effects:
- **Chemical Lab** (120s exposure) → Acid Adaptation: passive acid drip (2 dmg/s to adjacent guards)
- **Cryo Zone** (90s exposure) → Cryo Conditioning: immune to cryo; brief freeze pulse on hit
- **Near Replicator** (60s exposure) → Metal Grafting: 20% damage reduction; bullets ricochet
- **Near Gus** (60s exposure) → Mycorrhizal Skin: zero footstep noise; cannot trigger pressure plates
- **Near Rogue AI** (60s exposure) → Interfacing: passively disrupts electronics within 80 units
- **Biohazard Zone** (100s exposure) → Hazard Resilience: immune to toxic gas and spores
- **Guard Combat** (sustained 45s) → Combat Conditioning: +15% move speed after taking a hit
- **Research Lab** (150s exposure) → Cognitive Amplification: reveals all interactables in 200-unit radius on minimap
Code: `ChimeraTrait` (Resource), `ChrisEntity.active_traits: Array[ChimeraTrait]`. See also: Chris (CRISPR Anomaly), Exposure Timer, Chimera Surge.

### Chris (CRISPR Anomaly)
One of four entity classes. Uses he/him pronouns. A single escaped CRISPR experiment who grows stronger through **environmental exposure** — not combat. Chris does not attack directly; he survives, explores, and adapts. The longer he explores the facility, the more dangerous he becomes. Abilities: Regeneration (passive: slow health regen when not taking damage), Trait Absorption (passive: accumulate Chimera Traits from environment), Acid Secretion (active: coat surface in acid, 4-second cooldown), Chimera Surge (ultimate: all traits fire simultaneously). Distinct from old Unstable Mutation design — Chris does not mutate in size; traits are subtle, functional, and cumulative. See also: Entity Class, Chimera Trait, Chimera Surge, Exposure Timer.

### Cordyceps Override
Gus's ultimate ability (65-second cooldown): Gus takes **direct full control** of up to 4 active Fungus Pawns simultaneously for 30 seconds. During override, those pawns become player-controlled (one per face button, or rotated via bumper). Guards see them as normal guards — no alarm triggered unless they observe the pawns doing something overtly hostile (firing, unlocking secure doors). When override expires, the controlled pawns revert to autonomous Fungus Pawn AI. **Does not escalate alarm on expiration** — the cordyceps release is biochemically quiet. See also: Gus (Fungus Strain), Fungus Pawn, Ultimate.

### Cooldown
The recovery time after an ability is used during which that ability cannot be activated again. Cooldowns are measured in seconds and displayed on the HUD. See also: Action Recovery, Ability.

---

## D

### De-escalate Alarm
The process by which alarm level decreases when no new threats are detected for a specified duration. Follows pattern: FACILITY_ALERT → SECTOR_LOCKDOWN → LOCAL_ALERT → QUIET. Can be manually triggered by sabotage (Rogue AI cascade hack). See also: Alarm Level, Escalate Alarm.

### Detection Cone
A visual/conceptual cone in front of a guard representing the angle and distance within which the guard can see. Typical cone: 90° angle, 200-unit range. Entities outside detection cone are not visible to guard. See also: Line of Sight, Guard, Noise Radius.

### Downed
State when an entity reaches 0 health and becomes incapacitated. Downed entity cannot move or act; appears prone and semi-transparent. Can be revived by an ally (3-second interaction) or will be captured after 60 seconds. See also: Incapacitated, Revive, Captured.

---

## E

### Encounter
A confrontation between entities and guards. Encounters occur when guards detect entities or entities deliberately engage guards. During encounters, guards switch to aggressive behavior; entities can attempt to flee or fight. See also: Guard, Engagement, Alert.

### Entity
A playable character controlled by a player. Four entity classes in full game: Replicator, Fungus Strain, CRISPR Anomaly, Rogue AI Construct. Each has distinct movement, abilities, and playstyle. See also: Entity Class, Ability.

### Entity Class
One of four asymmetric player character types. Defined by: lore, movement quirks, passive trait, active abilities, ultimate ability, cooperative synergies. **MVP includes all four classes**: Replicator, Gus (Fungus Strain), Chris (CRISPR Anomaly), Rogue AI Construct. Ultimates are deferred to post-MVP for Replicator and Chris; all core abilities are MVP-complete. See also: Entity, Asymmetric.

### Escalate Alarm
To increase the alarm level in response to a trigger (detection, noise, sabotage). Escalation is automatic and facility-wide; all players see alarm tint increase and audio cue intensifies. See also: Alarm Level, De-escalate.

### Exposure Timer
A per-trait float counter maintained by ChrisEntity tracking how long Chris has been within range of a given trait source. Increments each physics frame when Chris is within `trait_exposure_radius` (120 units) of a source. Resets to zero if Chris leaves range before threshold is met. Once threshold reached, the trait is permanently absorbed and the timer entry is removed.
Code: `ChrisEntity.exposure_timers: Dictionary` — keyed by `trait_type: String`, value is accumulated seconds. See also: Chimera Trait, Chris (CRISPR Anomaly).

---

## F

### Facility Alert
Highest alarm level (FACILITY_ALERT). Triggered by major breaches or sabotage. Duration: 90 seconds. Facility-wide red emergency tint, continuous alarm loop, response teams deployed across all sectors, all guards on high alert. See also: Alarm Level, Response Team.

### Fog of War
A mechanic that hides unexplored sector areas from the player's view. Fog is revealed as entities move and explore. Revealed areas persist in "last known state" (no live updates of hidden guards/items). Unexplored areas appear as opaque gray overlay. See also: Revelation, Explored Tile.

### Fungus Pawn
A guard or researcher who has been infected by Gus's Spore Cloud and converted into a zombie ally. Fungus Pawns retain the body and appearance of the original guard (including their uniform and weapon) but now serve Gus's team. Autonomous behavior: patrol near Mycelium Nodes, intercept guards investigating Gus, and draw guard attention away from other entities. Uninfected guards cannot tell a Fungus Pawn from a normal guard on sight — they look identical. Pawn becomes identifiable only on close inspection (visible fungal growths) or direct engagement. Max 4 active pawns (controlled by `GusEntity.active_pawns`). Pawns are destroyed if downed; Gus cannot create replacements beyond the cap. Code: `FungusPawn` (extends `ContainmentGuard`). See also: Gus (Fungus Strain), Spore Cloud, Cordyceps Override.

### Gus (Fungus Strain)
One of four entity classes. Uses they/them pronouns. Inspired by cordyceps fungal infection. Gus builds a **zombie army** by infecting guards and researchers with spore clouds — infected targets become Fungus Pawns acting in Gus's interest. Gus does not fight directly; Gus converts. Abilities: Silent Bloom (passive: zero noise, no motion sensors), Spore Cloud (active: infects guards → Fungus Pawns), Mycelium Node (active: teleport network usable by all allies), Cordyceps Override (ultimate: full direct control of a pawn). See also: Entity Class, Fungus Pawn, Spore Cloud, Mycelium Node.

---

## G

### Guard
Non-player character (NPC) representing facility security. Guards patrol, detect entities, and escalate alarms. Four guard types: Patrol Guard, Stationary Sentry, Response Team, Specialist. Behavior controlled by LimboAI behavior trees. See also: Containment Guard, NPC.

### Guard Patrol Route
A predetermined path that a Patrol Guard follows continuously. Route consists of waypoints; guard walks waypoint → waypoint → loop. Routes are procedurally generated per run but deterministic (same seed = same routes). See also: Patrol Guard, Waypoint.

---

## H

### Hack Terminal
Rogue AI's primary active ability (6-second cooldown, 2-second cast). Remotely accesses a terminal or camera system; can disable camera, unlock door, or trigger distraction. Hacking is instant but cast time is uninterruptible. See also: Rogue AI Construct, Terminal.

---

## I

### Incapacitated
State when an entity cannot act (downed, controlled, disabled). Incapacitated entities do not contribute to team threat detection; allies cannot be assisted while incapacitated except by revive. See also: Downed, Control, Disabled.

### Interactable
A world object that responds to player interaction (pressing interact button). Types: Door, Terminal, Vent, Item, Guard. Interactables have proximity zones; interact prompt appears when entity enters zone. See also: Interactable Object, Prompt.

### Interactable Object
A game object with interaction behavior. Base class: InteractableObject. Subtypes: Door, Terminal, Vent, Item, Guard. Each subtype has unique interaction logic and effects. See also: Interactable, Interaction.

---

## L

### Line of Sight (LOS)
The ability to see a target without obstruction. Guards use line-of-sight checks (raycast) to detect entities. Walls and obstacles block line of sight. Entities outside detection cone are not detected even if in line of sight. See also: Detection Cone, Guard, Noise Radius.

### Local Alert
Second alarm level (LOCAL_ALERT). Triggered by single guard investigation or entity detection. Duration: 45 seconds. Nearby guards increase alertness; patrol guards investigate noise; no facility-wide tint yet. See also: Alarm Level, Investigation.

---

## M

### Machine Possession
Rogue AI's active ability (14-second cooldown, 20-second duration). Uses **avatar-vacate model**: when Rogue AI possesses a machine, the android body is left standing in place (uncontrolled, vulnerable) and the player's perspective shifts to the possessed machine. On vacate (press ability again or duration expires), player instantly returns to the android body's last known position. Five possessable machine types:
1. **Security Drone** — flying; full facility mobility; fires stun bolt
2. **Turret** — stationary; 360° cover; guards cannot detect it as compromised until it fires on them
3. **Robot Arm** (lab) — limited range; can manipulate objects, open locked cabinets, blockade doors
4. **Cargo Loader** — slow but can carry a downed ally (free revive transport)
5. **Intercom Terminal** — no movement; broadcasts audio distraction to any sector location
Code: `RogueAIEntity.possess_machine()`, `RogueAIEntity.vacate_machine()`. See also: Rogue AI Construct, Possession.

### Metal Sense
Replicator's passive trait. All MetalObjects within 300 units are highlighted through walls on the minimap and in-world (faint orange outline visible through geometry). Activates automatically; no input required. Allows the Replicator player to plan assimilation routes before entering a room. Code: `ReplicatorSwarm._update_metal_radar()`. See also: Replicator, MetalObject, Assimilation.

### MetalObject
A world node representing a depletable metal resource the Replicator can assimilate. Examples: metal shelving units, generator housings, steel equipment racks, locked security doors (consuming them disables the door permanently). Each MetalObject has a boolean `is_depleted` flag; once consumed it is visually degraded and cannot be re-assimilated. Yield: 1–2 new Replicator units per assimilation. Code: `MetalObject` (base class); tagged in group `"metal_sources"`. See also: Replicator, Assimilation, Metal Sense.

### Mycelium Node
Gus's active ability (12-second cooldown per placement). Places a biological waypoint at Gus's current position. Any entity — including non-Gus teammates — can teleport between any two Mycelium Nodes instantly and silently by interacting with a node. Max 3 nodes active simultaneously; placing a fourth removes the oldest. Node visuals are subtle (small fungal growth) and not immediately identifiable to guards without close inspection. Code: `MyceliumNode` (InteractableObject subclass), `GusEntity.placed_nodes: Array[MyceliumNode]`. See also: Gus (Fungus Strain), Waypoint, Teleport.

---

## N

### Noise Radius
A metric tracking sound generated by entity actions. Noise sources include: movement (sprint = 40 units, walk = 10 units, crawl = 2 units), ability use (5–15 units), guard engagement (10 units). Guards within noise radius have probability to investigate proportional to accumulated noise. See also: Noise Detection, Accumulation.

---

## O

### Objective
A task that must be completed to progress a sector. Examples: retrieve keycard item, hack terminal, reach specific location, defeat key guard. Completing objective unlocks sector exit. See also: Sector, Exit, Progression.

### Overwhelming Replication
Replicator's ultimate ability (65-second cooldown, deferred post-MVP). For 20 seconds, Assimilation cooldown is removed entirely and the unit cap is lifted to 20. Every piece of metal in the sector — including walls, floor grates, equipment — becomes a valid assimilation target. Swarm floods the sector; guards are overwhelmed by sheer unit volume. On expiration, excess units above normal cap are removed (prioritizing the longest-surviving units). See also: Replicator, Assimilation, Swarm Unit, Ultimate.

---

## P

### Passive Trait
An always-active ability unique to each entity class. Examples: Replicator ignores metal barriers, Fungus Strain not detected by motion sensors, Chris regenerates health, Rogue AI sees guard routes. Passive traits define entity identity and enable unique playstyles. See also: Entity Class, Ability.

### Patrol Guard
Standard guard type. Walks assigned route, investigates noise, detects entities via line-of-sight, calls for backup. Responsive but not overpowering. Can be avoided via stealth or distraction. See also: Guard Type, Sentry, Response Team.

### Possession
Rogue AI's mechanic of controlling a machine body or temporarily overriding a guard's consciousness (via cordyceps). Entities can be possessed via Cordyceps Override; machines can be possessed via Machine Possession. See also: Rogue AI Construct, Control.

### Proximity Zone
An invisible Area2D around an interactable object. When an entity enters proximity zone, interaction prompt appears. Zone radius typically 50–100 units. See also: Interactable, Prompt, Area2D.

---

## R

### Replicator
One of four entity classes. Inspired by Stargate SG-1 Replicators. A direct RTS-lite swarm: the player controls a group of small mechanical spider-units simultaneously. Starts at 4 units; max 10. Loses units when hit; gains units by assimilating metal. Can split into two independently controlled groups (see Swarm Split). **Narrative connection:** the Replicator in Blacksite Breakout is the origin of the swarm in the Replicants game. Abilities: Metal Sense (passive), Assimilate (active), Swarm Rush (active), Overwhelming Replication (ultimate, deferred). Synergy: can ferry downed allies through vents. See also: Entity Class, Swarm Unit, Swarm Split, Assimilation.

### Revive
To restore an incapacitated (downed) entity to active state. Revive requires: adjacent ally, 3-second interaction, uninterrupted line-of-sight. On revive: entity regains 50% max health, stands up, re-enters play. See also: Downed, Incapacitated, Interaction.

### Rogue AI Construct
One of four entity classes. Digital consciousness inhabiting android bodies. Abilities: Facility Data Access (passive: see guard routes), Hack Terminal (active: disable cameras/unlock doors), Machine Possession (active: control machines), Cascade Hack (ultimate: disable all systems in sector). Movement: can possess machines for mobility. Synergy: hacking benefits entire team; possessed machines can carry allies. See also: Entity Class.

### Run
A single playthrough of the game, from start (Lobby) to end (Win/Loss). Run state persists across sectors; entity health and ability cooldowns carry over (resets on new sector). Runs end in victory (reach facility exit) or failure (all entities captured). See also: Sector, Win Condition, Lose Condition.

---

## S

### Sector
A contained portion of the facility (one floor or area). Players progress through 5 sectors per run. Each sector has: entry point, objectives, exit point, guards, items, obstacles. Sectors vary in difficulty (tier 1–5). See also: Run, Difficulty Tier, Procedural Generation.

### Sector Lockdown
Third alarm level (SECTOR_LOCKDOWN). Triggered by escalation from LOCAL_ALERT. Duration: 60 seconds. All guards in sector become active and aggressive; no longer patrol passively. Facility-wide orange tint; emergency alarm loop audio. See also: Alarm Level, Escalate Alarm.

### Sector Exit
A door or transition point leaving a sector. Entities must interact with sector exit to progress to next sector. Exit is typically locked until objective completed. Interacting with exit triggers SECTOR_EXIT_TRANSITION state. See also: Sector, Objective, Progression.

### Sentry
Advanced guard type. Stationary (does not move from post). High detection range (250 units, 120° cone). Cannot be distracted; immediately escalates alarm on detection. Positioned at key choke points (entry, objective, exit). See also: Guard Type, Patrol Guard, Response Team.

### Silent Bloom
Fungus Strain's passive trait. Entity does not trigger motion sensors or pressure plates. Guards may not detect movement via sensors alone; only via line-of-sight or noise radius. Enables silent traversal of sensor-protected areas. See also: Fungus Strain, Passive Trait, Detection.

### Specialist Guard
Advanced guard type deployed on high alarm levels (SECTOR_LOCKDOWN+). Each specialist is trained to counter a specific entity class (EMP vs. Rogue AI, bio-suit vs. Fungus, etc.). Higher stats and specific counter-abilities. See also: Guard Type, Response Team, Alarm Level.

### Spore Cloud
Gus's primary active ability (8-second cooldown, 5-second duration, 150-unit radius). Deploys a dispersal cloud of infectious cordyceps spores. **Dual effect:**
1. **Vision obscurance** — guards inside cannot see clearly; all entities inside have reduced visibility but can see allies clearly. Guards disoriented and slowed.
2. **Infection vector** — any guard who remains inside the cloud for 3+ continuous seconds becomes infected and converts to a Fungus Pawn (if pawn cap not reached). Researchers convert faster (1.5s). If pawn cap is full, additional guards are only disoriented, not converted.
Cloud dissipates naturally after 5 seconds. Code: `GusEntity.deploy_spore_cloud()`, `SporeCloudArea2D` — detects guard overlap, runs infection timer. See also: Gus (Fungus Strain), Fungus Pawn, Area Effect.

### Swarm Rush
Replicator's primary active ability (6-second cooldown). Commands all units in the active group to sprint toward a target location simultaneously. Units deal contact damage on impact (1 dmg per unit per hit, stacks). Effective for disabling a single guard; less effective in open spaces with multiple guards. Code: `ReplicatorSwarm.swarm_rush(target_position: Vector2)`. See also: Replicator, Swarm Unit.

### Swarm Split
A Replicator control mechanic activated by holding LB for 0.5 seconds. Divides the current swarm into two independently controllable groups (Group A: odd-indexed units, Group B: even-indexed units). While split: left stick controls Group A, right stick controls Group B. Press LB again to re-merge. Allows simultaneous multi-path infiltration or coordinating a pincer on a single guard. Code: `ReplicatorSwarm.split_swarm()`, `ReplicatorSwarm.merge_swarm()`, `ReplicatorSwarm.is_split: bool`. See also: Replicator, Swarm Unit.

### Swarm Unit
A single mechanical spider-unit that is part of the Replicator swarm. Each unit is an autonomous `CharacterBody2D` that follows the swarm's current movement target. Units share a single health pool expressed as unit count — losing a unit is the functional equivalent of taking damage. Units move semi-independently (slight spread formation); gap between units allows them to navigate around obstacles the swarm collectively would get stuck on. Smallest unit: ~30x30 pixels. Code: `ReplicatorUnit` (CharacterBody2D). See also: Replicator, Swarm Split, Assimilation.

---

## T

### Terminal
A hackable computer system or information display. Terminals have two types: (1) Informational—display text/data to player, (2) Hackable—can be hacked by Rogue AI to unlock doors, disable cameras, or trigger distractions. Hacking takes 2 seconds (uninterruptible). See also: Interactable, Hack Terminal.

### Threat Detection
The process by which guards identify entity presence. Two mechanisms: (1) Noise detection—entity sound triggers investigation, (2) Line-of-sight—entity visible in detection cone. Probability of detection depends on alarm level and guard type. See also: Noise Radius, Line of Sight, Detection Cone.

---

## U

### Ultimate Ability
A powerful, long-cooldown (40–65 second) ability unique to each entity class. Requires strategic timing. Current ultimates: Replicator → Overwhelming Replication (deferred post-MVP), Gus → Cordyceps Override, Chris → Chimera Surge (deferred post-MVP), Rogue AI → Cascade Hack. Ultimates create game-changing moments. See also: Ability, Action Recovery, Cooldown.

---

## V

### Vent
A ventilation duct accessible from multiple rooms. Vents enable rapid traversal but have entity-class restrictions: Replicator (after assimilation), Fungus Strain (2x speed), CRISPR (via mutation squeeze), Rogue AI (can hack to open/close). Vents connected across sector; entering one lists destinations. See also: Interactable, Traversal, Entity.

---

## W

### Waypoint
A marked navigation point in a patrol route or teleportation network (e.g., mycelium node). Guards walk waypoint → waypoint on patrols. Entities teleport between waypoints via Mycelium Nodes. Waypoints are procedurally placed per run. See also: Patrol Route, Mycelium Node, Navigation.

### Win Condition
The objective state that triggers victory. For Blacksite Breakout: entity (any of the four) reaches facility exit and interacts. Run completes, players return to lobby, victory stats displayed. See also: Lose Condition, Run, Facility Exit.

---

## X

*(No entries)*

---

## Y

*(No entries)*

---

## Z

### Zone (Shadow Zone)
A darker area on the facility map that provides visual cover. Entities in shadow zones are harder to spot by guards (detection distance reduced 50%). Shadow zones are created by lighting contrast (unlit corners, dark alcoves). See also: Stealth, Detection Cone, Line of Sight.

---

## Abbreviations & Acronyms

| Abbreviation | Full Term | Usage |
|---|---|---|
| **AI** | Artificial Intelligence | Refers to guard behavior or Rogue AI entity |
| **AOE** | Area of Effect | Ability that affects region (e.g., Spore Cloud) |
| **DPS** | Damage Per Second | Guard attack output metric |
| **HUD** | Heads-Up Display | On-screen UI (health bar, cooldowns, minimap) |
| **LOS** | Line of Sight | Guard detection mechanic |
| **MVP** | Minimum Viable Product | Core feature set; first playable build |
| **NPC** | Non-Player Character | Guard entity controlled by AI |
| **SFX** | Sound Effects | Audio feedback per ability/action |
| **UI** | User Interface | On-screen menus and HUD |
| **UX** | User Experience | Player interaction and feedback design |
| **VFX** | Visual Effects | Particle effects, screen distortions, animations |

---

## Cross-References by Category

### By Game State
- **LOBBY:** Player selection, co-op setup.
- **BRIEFING:** Objective overview, difficulty display.
- **SECTOR_EXPLORATION:** Main gameplay loop.
- **ENCOUNTER:** Guard engagement state.
- **ALARM_STATE:** Alert escalation sub-states.
- **SECTOR_EXIT_TRANSITION:** Loading between sectors.
- **FACILITY_EXIT:** Victory screen.
- **ALL_CAPTURED:** Failure screen.

### By Mechanic
- **Stealth:** Silent Bloom, Spore Cloud, Noise Radius, Line of Sight, Shadow Zone, Mycorrhizal Skin (Chimera Trait).
- **Traversal:** Vent, Mycelium Node, Machine Possession, Swarm Rush.
- **Detection:** Detection Cone, Noise Radius, Line of Sight, Threat Detection, Metal Sense.
- **Interaction:** Interactable, Terminal, Hack Terminal, Vent, MetalObject.
- **Cooperation:** Revive, Downed, Incapacitated, Mycelium Node, Machine Possession (cargo loader).
- **Progression:** Sector, Objective, Sector Exit, Run, Win Condition.
- **Resource/Growth:** Assimilation, MetalObject, Chimera Trait, Exposure Timer, Fungus Pawn.

### By Entity Class
- **Replicator:** Metal Sense, Assimilation, MetalObject, Swarm Unit, Swarm Split, Swarm Rush, Overwhelming Replication, Vent.
- **Gus (Fungus Strain):** Silent Bloom, Spore Cloud, Fungus Pawn, Mycelium Node, Cordyceps Override, Vent.
- **Chris (CRISPR Anomaly):** Chimera Trait, Exposure Timer, Acid Secretion, Chimera Surge.
- **Rogue AI:** Facility Data Access, Hack Terminal, Machine Possession, Cascade Hack.

---

## Notes on Terminology Consistency

When writing documentation or code comments, adhere to these conventions:
1. **Entity types:** Use: Replicator, Gus (not "Fungus Strain" in casual references), Chris (not "CRISPR Anomaly" in casual references), Rogue AI. Full class names (GusEntity, ChrisEntity, ReplicatorSwarm, RogueAIEntity) in code only.
2. **Alarm levels:** Uppercase (QUIET, LOCAL_ALERT, SECTOR_LOCKDOWN, FACILITY_ALERT).
3. **States:** Uppercase with underscores (DOWNED, INCAPACITATED, INVESTIGATING, ALERT).
4. **Abilities:** Title case (Assimilation, Spore Cloud, Hack Terminal).
5. **Distances:** Always in units (e.g., "150 units" not "150").
6. **Percentages:** Use % symbol (e.g., "50% health").
7. **Times:** Seconds (e.g., "5 seconds" or "5s" in UI).

---

## Document Version History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-03-15 | Initial glossary creation |
| 1.1 | 2026-03-15 | Entity redesign pass: added Fungus Pawn, Chimera Trait, Chimera Surge, Chris (CRISPR Anomaly), Swarm Unit, Swarm Split, Swarm Rush, Metal Sense, MetalObject, Overwhelming Replication, Exposure Timer; updated Cascade Hack (no FACILITY_ALERT), Cordyceps Override (4-pawn 30s direct control), Machine Possession (avatar-vacate, 5 machine types), Mycelium Node (renamed from Network, team teleport), Spore Cloud (infection vector), Entity Class (all 4 in MVP); removed Material Token (deprecated concept); updated cross-references |

---

**Document Version:** 1.1
**Last Updated:** 2026-03-15
**Status:** Active
