# REQ_08: MVP Build Plan
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines the minimum viable product (MVP) scope, phased build plan, testing checkpoints, and feature prioritization. The MVP proves core mechanics (asymmetric escape, cooperative play) with minimal scope.

---

## 1. MVP Goal & Scope

### 1.1 MVP Goal Statement
Prove that **all four asymmetric entities create meaningfully different playstyles** and that cooperative escape with tactical decision-making is fun and rewarding with 1–4 players, demonstrating:
- Each entity class feels mechanically distinct — not cosmetically different.
- At least two entity pairings produce emergent cooperative strategies.
- Tactical decision-making (stealth vs. aggression, ability timing, resource management) impacts outcomes.
- A single hand-crafted sector is enough to validate the core loop.

### 1.2 MVP Feature List

#### Must-Have (Core Loop)
- [ ] **All 4 playable entity classes:** Replicator (RTS-lite swarm), Gus/Fungus Strain (infection), Chris/CRISPR (chimera accumulation), Rogue AI (hacking/possession).
- [ ] Isometric movement (click-to-move or directional input).
- [ ] Replicator swarm: direct control of units, split mechanic, assimilate metal.
- [ ] Gus: spore cloud infection, fungus pawn autonomous AI, mycelium nodes.
- [ ] Chris: environmental exposure timer, 2 starter traits (lab + combat), visual mutation feedback.
- [ ] Rogue AI: hack terminal (2 options), data intercept passive, machine possession (1 machine type).
- [ ] 3 interactable types (Door + Terminal + Metal Object for Replicator).
- [ ] 1 guard type (Patrol Guard with basic AI).
- [ ] Noise detection system (guards respond to noise).
- [ ] Alarm escalation: QUIET → LOCAL_ALERT → SECTOR_LOCKDOWN.
- [ ] 1 hand-crafted sector with metal sources, fungal zones, networked terminals, lab area for Chris.
- [ ] Entity win condition (reach sector exit).
- [ ] Downed/revive system (entity incapacity, ally rescue).
- [ ] Basic HUD per entity (health, ability cooldowns, swarm unit count for Replicator, pawn count for Gus, trait progress for Chris, possession state for Rogue AI).

#### Deferred (Post-MVP)
- Procedural generation (room templates, randomized layouts).
- Full alarm chain (FACILITY_ALERT level).
- Advanced guard types (Sentry, Response Team, Specialist).
- Full ability sets (MVP = 2 active + passive per entity; Ultimate deferred).
- Multiple sectors (MVP = 1 sector).
- Advanced VFX (particle pools, screen shake).
- Full audio (ambient loops, detailed SFX per ability).
- Co-op multiplayer networking (MVP = local co-op or single-player).
- Chris full trait table (MVP = 2 traits; full 8-trait table post-MVP).
- Rogue AI machine possession full machine roster (MVP = 1 machine type).

---

## 2. Entity Class Scope (MVP)

All four entities implemented at MVP. Ultimates deferred for all. Two active abilities + passive per entity.

### 2.1 Rogue AI Construct
**MVP Abilities:**
- **Passive:** Data Intercept (reveal guard patrol routes for 15 seconds every 20 seconds).
- **Active 1:** Hack Terminal (disable camera OR unlock door; 6-second cooldown).
- **Active 2:** Machine Possession — 1 machine type only (maintenance vehicle: transport downed ally); 20-second cooldown.
- **Ultimate:** Cascade Hack — deferred.

### 2.2 Gus (Fungus Strain)
**MVP Abilities:**
- **Passive:** Silent Bloom (no motion sensor detection; zero noise generation).
- **Active 1:** Spore Cloud (infects guards → converts to Fungus Pawns after 5 seconds; 8-second cooldown).
- **Active 2:** Mycelium Node (place up to 3 nodes; teleport between them; nodes usable by allies; 15-second cooldown).
- **Ultimate:** Cordyceps Override — deferred.

### 2.3 Chris (CRISPR Anomaly)
**MVP Abilities:**
- **Passive:** Chimera Absorption (gain traits from environmental exposure; MVP implements 2 trait types: Lab exposure → Acid Adaptation, Combat exposure → Combat Conditioning).
- **Active 1:** Mutate Form (squeeze through small gaps; 10-second cooldown).
- **Active 2:** Acid Secretion (dissolves doors, corrodes guard armor, floor hazard; 15-second cooldown).
- **Ultimate:** Chimera Surge — deferred (requires 2+ traits, which MVP can reach).

### 2.4 Replicator
**MVP Abilities:**
- **Passive:** Metal Sense (highlights nearby metal objects and vent routes on HUD).
- **Active 1:** Assimilate (consume adjacent metal object → produce 1–2 new units; no cooldown, metal-gated).
- **Active 2:** Swarm Rush (all units in active group sprint to target position at 2.5× speed; 12-second cooldown).
- **Split mechanic:** LB hold → split swarm into two groups; WASD/stick each group independently.
- **Ultimate:** Overwhelming Replication — deferred.

---

## 3. Sector Design (MVP)

### 3.1 Hand-Crafted Tutorial Sector
**Name:** "Containment Lab" (introductory difficulty).

**Layout:**
```
[Entry]────→[Guard Post]────→[Lab]────→[Exit]
                │                │
                └──[Storage]─────┘
                     (Optional)

         Size: ~1000×800 pixels
```

**Rooms:**
1. **Entry:** Spawn zone; empty; 1 guard nearby (not immediately threatening).
2. **Guard Post:** Observation desk; 1 Patrol Guard on route; 1 locked door (requires hack).
3. **Lab:** Main chamber; equipment; Objective: retrieve keycard item; 1 Patrol Guard on route.
4. **Storage:** Optional shortcut; supplies; 1 Medkit item.
5. **Exit:** Sector exit; accessible after keycard retrieved.

**Interactables:**
- 3 doors (1 unlocked, 1 locked/alarmed, 1 automatic sensor-based).
- 2 terminals (1 hackable, 1 information-only).
- 2 items (keycard [objective], medkit).
- 2 guards (both Patrol type, different routes).

**Difficulty:** Easy; guards are slow to react; noise threshold high; multiple safe approaches.

---

## 4. Six-Phase Build Plan

### Phase 1: Foundation (Week 1–2)
**Goal:** Establish project structure, basic scene hierarchy, input handling.

**Tasks:**
- [ ] Create Godot 4 project with BurnBridgers integration (GameManager, SteamManager boilerplate).
- [ ] Set up scene hierarchy (Root → SectorMap → EntityManager → GuardManager → UILayer).
- [ ] Implement EntityCharacter base class (movement, health, downed state).
- [ ] Implement basic input handling (WASD, mouse click-to-move, ability buttons).
- [ ] Create placeholder entity sprites (simple geometric shapes, distinct colors).
- [ ] Implement pathfinding via NavigationAgent2D (click-to-move functionality).
- [ ] Add basic HUD (health bar, text labels for state).

**Testing checkpoint:**
- Player can move entity via WASD and click-to-move.
- Entity health decreases on input test command.
- Entity enters downed state when health ≤ 0.
- Basic HUD updates in real-time.

---

### Phase 2: Isometric Movement & Camera (Week 2–3)
**Goal:** Establish isometric perspective, smooth camera follow, input parity.

**Tasks:**
- [ ] Set camera to isometric angle (45° overhead, fixed rotation).
- [ ] Implement camera follow (smooth lerp, lag = 0.1 seconds).
- [ ] Test movement in isometric space (diagonal movement smooth and natural).
- [ ] Implement zoom levels (0.7x, 1.0x, 1.5x via mouse wheel).
- [ ] Add map view toggle (X / "Map View" button switches to overhead map).
- [ ] Implement entity animation (walk cycle synced to movement direction).
- [ ] Test controller input parity (both gamepad and keyboard feel responsive).

**Testing checkpoint:**
- Movement feels responsive in all 8 directions.
- Camera follows smoothly without lag.
- Isometric perspective is clear and unambiguous.
- Map view works; minimap displays correctly.

---

### Phase 3: All Four Entity Classes (Week 3–6)
**Goal:** Implement core mechanics for all four entity classes. This is the largest phase — plan accordingly.

**Tasks — Shared Foundation First:**
- [ ] Ability resource system (BaseAbility class, cooldown management, execution state).
- [ ] Entity ability controller (manages ability states, executes on input).
- [ ] Ability feedback (icon state changes, cooldown text, VFX triggers).
- [ ] Entity selection / switching for local co-op.

**Rogue AI:**
- [ ] Data Intercept passive — auto-trigger every 20s; reveal guard patrol routes 15s.
- [ ] Hack Terminal — select terminal in range; choose action (disable camera / unlock door); 6s cooldown.
- [ ] Machine Possession — vacate avatar; possess maintenance vehicle; avatar left stationary.
- [ ] Avatar ejection on damage during possession.
- [ ] VFX: blue code-stream on hack; possession shimmer on avatar vacate.

**Gus (Fungus Strain):**
- [ ] Silent Bloom passive — zero noise generation; no motion sensor triggers.
- [ ] Spore Cloud — targeted area cloud; 5s infection conversion delay; Fungus Pawn spawns from guard.
- [ ] FungusPawn class: simple LimboAI tree (move toward nearest uninfected guard, attack, idle-block).
- [ ] Mycelium Node — place at position; store list of nodes; teleport self (and allow ally interaction).
- [ ] Max 3 nodes; oldest node removed when 4th placed.
- [ ] VFX: green particle cloud for spore; mycelium trail on Gus movement.

**Chris (CRISPR):**
- [ ] ChimeraTrait Resource class with trait_type, required_exposure_time, apply_to_entity().
- [ ] Exposure proximity check in _physics_process; timer per trait_type in Dictionary.
- [ ] 2 trait sources in MVP sector: lab area (Acid Adaptation) and guard encounter zone (Combat Conditioning).
- [ ] Visual mutation feedback on trait absorbed (swap sprite layer or tint shift).
- [ ] Mutate Form — squeeze through gap collision (toggle collision shape width).
- [ ] Acid Secretion — dissolve door lock (5s contact), corrode guard armor, place floor hazard.

**Replicator:**
- [ ] ReplicatorUnit class: individual CharacterBody2D; small, geometric; moves toward group target.
- [ ] ReplicatorSwarm controller: manages unit Array; issues group move commands.
- [ ] Split mechanic: LB hold → split_group_a / split_group_b; dual stick input while split.
- [ ] Assimilate: raycast to adjacent MetalObject; deplete + spawn 1–2 units.
- [ ] MetalObject class: depletes on assimilation; not respawnable.
- [ ] Swarm Rush: set all units to high-speed move toward target; 12s cooldown.
- [ ] Unit destroyed on hit; swarm downed at 0 units.

**Testing checkpoint:**
- All four entities can be selected and moved in the test sector.
- Rogue AI: hack terminal changes door/camera state; data intercept reveals routes; possession works.
- Gus: spore cloud converts a guard to FungusPawn; pawn acts autonomously; mycelium teleport works.
- Chris: absorbs 1 trait by standing in lab area; acid dissolves a door; mutate form fits through gap.
- Replicator: assimilate a metal object, gain units; split swarm and move groups independently; swarm downed at 0.
- All ability cooldowns render correctly on HUD.

---

### Phase 4: Guard AI & Detection (Week 5–6)
**Goal:** Implement Patrol Guard with basic threat detection and response.

**Tasks:**
- [ ] Implement ContainmentGuard class (CharacterBody2D, navigation-based movement).
- [ ] Implement patrol route system (guard walks waypoint → waypoint → loop).
- [ ] Implement noise detection (guard hears loud sounds, investigates).
- [ ] Implement line-of-sight detection (guard sees entities in cone, raises alert).
- [ ] Implement guard states: IDLE, PATROL, INVESTIGATE, ALERT, ENGAGE.
- [ ] Implement basic LimboAI behavior tree (Patrol → Investigate → Alert flow).
- [ ] Guard calls for backup when alert (nearby guards converge).
- [ ] Guard engagement: walks toward entity, attempts to force incapacity.
- [ ] VFX: detection cone briefly flashes when guard spots entity.
- [ ] SFX: alert tone plays on detection.

**Testing checkpoint:**
- Guard patrols assigned route smoothly.
- Guard responds to loud noise (sprint movement) by investigating.
- Guard spots entity via line-of-sight and enters alert state.
- Guard converges on entity when alerted (multiple guards coordinate).
- Guard ceases engagement if entity escapes sight for 5+ seconds.
- Guard pathfinding avoids obstacles.

---

### Phase 5: Sector Design & Interactables (Week 6–7)
**Goal:** Design and implement the tutorial sector with all interactable types.

**Tasks:**
- [ ] Create hand-crafted Tutorial Sector tilemap (rooms, walls, collisions).
- [ ] Implement interactable door types (unlocked, locked, alarmed, automatic).
- [ ] Implement interactable terminal (hackable by Rogue AI; displayable text).
- [ ] Implement item pickup system (keycard, medkit).
- [ ] Implement sector entry zone (entity spawn location).
- [ ] Implement sector exit zone (win condition trigger).
- [ ] Implement objective system (retrieve keycard, update HUD).
- [ ] Bake navigation mesh for pathfinding.
- [ ] Place 2 patrol guards in sector; assign patrol routes.
- [ ] Adjust difficulty (guard alertness, noise sensitivity, medkit availability).

**Testing checkpoint:**
- Sector loads without errors.
- Player spawns at entry; can move to all rooms.
- Locked door cannot be entered; can be hacked by Rogue AI.
- Terminal can be hacked; effect is visible.
- Keycard item can be picked up; objective updates on pickup.
- Guards patrol assigned routes and respond to player actions.
- Reaching exit zone with keycard triggers win condition.

---

### Phase 6: Polish & Testing (Week 7–8)
**Goal:** Integrate all systems, test end-to-end, refine balance and feel.

**Tasks:**
- [ ] Implement complete HUD (health bar, ability cooldowns, alarm meter, minimap).
- [ ] Add downed/revive interaction (one entity can revive another).
- [ ] Implement alarm state machine (QUIET → LOCAL_ALERT → SECTOR_LOCKDOWN levels).
- [ ] Visual feedback on alarm escalation (screen tint, alarm text, siren sound).
- [ ] Test co-op switching (local 2-player on same keyboard/controller).
- [ ] Tune guard reaction times, movement speeds, detection ranges.
- [ ] Balance ability cooldowns and effectiveness.
- [ ] Test all interactable types in sector.
- [ ] Playtest full run: 5 full games, document issues.
- [ ] Fix high-priority bugs (crashes, progression blocks).
- [ ] Optimize performance (profile frame rate, particle count, AI updates).

**Testing checkpoint:**
- Full end-to-end run (Lobby → Sector → Win) works without crashes.
- Two players can play together, switching between entities.
- Alarm escalation feels tense and fair.
- Downed/revive mechanic works as intended.
- All interactables function correctly.
- Frame rate stable at 60 FPS.

---

## 5. Testing Checkpoints Summary

| Phase | Checkpoint | Pass Criteria |
|---|---|---|
| 1 | Movement & HUD | Player moves, health updates, downed state works. |
| 2 | Isometric Perspective | Movement natural; camera smooth; perspective clear. |
| 3 | Entity Abilities | Both entities' active abilities execute and affect world state. |
| 4 | Guard AI | Guards patrol, detect, respond; coordinate behavior. |
| 5 | Sector Interactables | All interactable types work; win condition triggers. |
| 6 | End-to-End | Full game loop playable; co-op works; no crashes. |

---

## 6. Success Metrics (MVP)

After Phase 6, MVP is successful if:
- [ ] Game runs without crashes for 30+ minutes of continuous play.
- [ ] Two players can cooperatively clear the tutorial sector in 15–20 minutes.
- [ ] Guard AI is responsive and challenging (guards catch careless players; stealthy play succeeds).
- [ ] Both entity classes feel mechanically distinct; abilities are fun to use.
- [ ] Playtester feedback is positive (feel is engaging; mechanics are clear; no frustration).

---

## 7. Deferred Features (Post-MVP)

### 7.1 Phase 7: Full Ability Sets & Ultimates
- Implement all four Ultimate abilities (Overwhelming Replication, Cordyceps Override, Chimera Surge, Cascade Hack).
- Implement Replicator vent-ferrying of downed allies.
- Implement full Chris trait table (all 8 trait types, full sector coverage).
- Implement Rogue AI full machine possession roster (turret, camera, PA system, door mechanism).
- Balance all 4 classes against each other across multiple sector configurations.

### 7.2 Phase 8: Procedural Generation
- Implement room template system.
- Implement sector generator (assemble rooms, guard placement, item distribution).
- Implement fog of war system.
- Test 10+ procedurally generated sectors for completability.

### 7.3 Phase 9: Advanced Alarm System
- Add FACILITY_ALERT level.
- Implement Response Teams.
- Implement Specialist guards.
- Implement guard communication sabotage (Rogue AI cascade hack).

### 7.4 Phase 10: Multi-Sector Campaign
- Implement sector progression (5 sectors, increasing difficulty).
- Implement run persistence (health/cooldowns carry over).
- Implement difficulty modifiers (iron mode, hardcore, speedrun).

### 7.5 Phase 11: Co-op Networking
- Implement GameManager co-op broadcasting (if not already integrated).
- Test remote co-op (2–4 players over network).
- Synchronize procedural generation across clients.

### 7.6 Phase 12: Full Audio & VFX
- Implement detailed SFX per ability.
- Implement particle effects (pooled, optimized).
- Implement screen shake system.
- Integrate MusicManager for dynamic audio.

---

## 8. Risk Mitigation

### 8.1 High-Risk Areas
| Risk | Mitigation | Checkpoint |
|---|---|---|
| Isometric perspective feels awkward | Early playtesting (Phase 2); consider alternative angles if needed | Phase 2 |
| Guard AI unbalanced (too easy/hard) | Detailed telemetry (how often guards catch players); adjust detection ranges | Phase 4 |
| Abilities not fun/impactful | Playtester feedback; increase visual/audio feedback if needed | Phase 3 |
| Co-op networking complexity | Start local-only for MVP; defer online multiplayer | Phase 6 |
| Performance issues at scale | Profile early; optimize pathfinding, particle systems | Phase 5–6 |

### 8.2 Contingency Plans
- **If Phase falls behind schedule:** Reduce map size, remove non-critical interactables, defer balance polish.
- **If guard AI too complex:** Simplify to state machine (remove LimboAI dependency for MVP).
- **If co-op difficult:** Support single-player first; local co-op optional feature.

---

## 9. Deliverables Per Phase

### Phase 1 Deliverables
- Executable build (Godot project).
- Entity movement works; HUD displays health.

### Phase 2 Deliverables
- Isometric camera integrated; smooth movement.
- Map view toggle functional.

### Phase 3 Deliverables
- Rogue AI hack ability fully functional.
- Fungus Strain spore cloud fully functional.
- Ability cooldown UI working.

### Phase 4 Deliverables
- Patrol Guard NPC with full behavior tree.
- Detection system (noise + LOS) working.
- Guard-entity interaction (engagement, incapacity).

### Phase 5 Deliverables
- Tutorial sector fully designed and playable.
- All interactable types working in sector.
- Objective system integrated.

### Phase 6 Deliverables
- **Final MVP build:** Playable game (Lobby → Sector → Win/Loss).
- Design documentation complete.
- Playtest report with feedback.

---

## 10. Related Documents
- REQ_01: Vision and Architecture (detailed node structure).
- REQ_02: Game State Machine (states referenced in Phase 6).
- REQ_03: Entity Classes and Abilities (MVP abilities defined here).
- REQ_04: Movement and Interaction (input mapping, interaction system).
- REQ_05: Procedural Map Generation (deferred to Phase 8).
- REQ_06: Guard AI and Alarm System (Phase 4 implementation).

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
