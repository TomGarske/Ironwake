# REQ_08: MVP Build Plan
**Replicants: Swarm Command**

## MVP Goal and Scope

**Primary Goal:** Prove that the harvest → replicate → overwhelm loop is **mechanically satisfying and strategically engaging** with 1–2 cooperative players.

**Success Criteria:**
- Core loop (harvest metal → produce units → use units to overcome resistance) is playable end-to-end.
- Swarm feels autonomous and responsive to player commands.
- Escalation creates meaningful challenge progression.
- Cooperative play is seamless and rewarding.

---

## Must-Have Features (MVP Scope)

### Core Mechanics
- [ ] **Camera Pan & Zoom:** WASD/arrow keys for panning, scroll wheel for zoom.
- [ ] **Unit Selection:** Single select, box select, select-all.
- [ ] **Unit Movement & Commands:** Left-click/RT to move units to cursor location.
- [ ] **Metal Harvesting:** Harvester units extract from deposits automatically (no manual activation).
- [ ] **Replication:** ReplicationHub queue-based production (manual placement or map-spawned).
- [ ] **Basic Swarm Units:**
  - Harvester (gather metal).
  - Soldier (combat unit).
  - (Scout, Builder, Assimilator are deferred.)
- [ ] **Resistance Units (2 types):**
  - Patrol Unit (mobile, engages swarm).
  - Turret (static, area-denial).
- [ ] **Protocol Command (1 type):**
  - Swarm Rush (select soldiers, rush to target location).
- [ ] **Assimilation Tracking:** Track % of facility assimilated; display on HUD.
- [ ] **Victory Condition:** Assimilate 50% of one map zone.
- [ ] **Defeat Condition:** All swarm units destroyed OR timer expires (10 minutes).

### World & Presentation
- [ ] **One Facility Zone:** Single focused map area (e.g., Entry Corridor + Resource Room).
- [ ] **Metal Deposits:** 2–3 small/medium deposits (no depletion for MVP; static resources).
- [ ] **Fog of War:** Basic fog layer; revealed by Scout patrol or map trigger (simplified, not full Scout mechanic).
- [ ] **Assimilation Visuals:** Zone shader that dims/brightens based on assimilation % (basic color shift).
- [ ] **HUD:** Metal counter, unit count, assimilation progress bar, simple minimap.
- [ ] **Audio:** Basic ambient hum, harvest clink, attack sounds, protocol activation.

### Multiplayer (Local Co-op)
- [ ] **Shared Metal Pool:** Both players draw from same metal, both can queue units.
- [ ] **Shared Objectives:** Single victory/defeat condition shared across both players.
- [ ] **Independent Cameras (Optional for MVP):** Each player has own camera view OR shared camera with PiP.
- [ ] **Command Sync:** Commands execute in FIFO order, no conflicts.

---

## Deferred Features (Post-MVP)

### Unit Roster (Full)
- Scout units (fog of war reveal, speed).
- Builder units (place new hubs, extend network).
- Assimilator units (convert enemy structures to metal).

### Protocol Roster (Full)
- Rapid Replication.
- Scatter.
- Defensive Formation.
- Assimilation Wave.

### Resistance Units (Full)
- EMP Drone.
- Commander (buffs, rally calls).
- Reaction Forces.

### Environmental Features
- **Fog of War (Full):** Complete implementation with Scout reveal mechanics.
- **Assimilation Shader (Full):** Complete color/energy transformation effects.
- **Multi-Zone Map:** Full facility layout with 5+ zones.
- **Dynamic Escalation:** Difficulty spikes triggered by thresholds.
- **Resistance Coordination:** Flanking, group defense, Rally Calls.

### Difficulty & Progression
- Easy/Normal/Hard difficulty levels (MVP = Normal only).
- Tutorial/Briefing sequence (MVP = minimal, in-game only).

### Advanced Systems
- **Custom Difficulty Settings:** Tweak spawn rates, costs, detection ranges.
- **Leaderboards & Stats Tracking:** Kill counts, efficiency metrics.
- **Mission Replay/Progression:** Chapter-based campaign structure.

---

## 6-Phase Build Plan

### Phase 1: Foundation (1 week)
**Goal:** Core architecture, asset pipeline, game state management.

**Deliverables:**
- [ ] Godot 4 project structure for Replicants (scenes/, ai/, assets/).
- [ ] GameManager integration (shared from BurnBridgers).
- [ ] MissionState machine (LOBBY → AWAKENING → EARLY_COLONY → ASSIMILATION_COMPLETE/COLONY_DESTROYED).
- [ ] Basic scene root (ReplicantsLanding.tscn) with node hierarchy.
- [ ] MetalEconomy system (track/spend metal).
- [ ] SwarmUnit base class (CharacterBody2D, health, behavior).
- [ ] ResistanceUnit base class.
- [ ] Placeholder assets (colored squares for units, zones).

**Checkpoint:**
- [ ] Game can start, transition between states, display HUD with metal counter.

---

### Phase 2: Camera & Input (1 week)
**Goal:** Player interaction, RTS controls, command issuance.

**Deliverables:**
- [ ] CameraController (pan WASD, zoom scroll wheel, bounds checking).
- [ ] InputHandler (map gamepad/keyboard to game actions).
- [ ] Unit Selection System (single, box, select-all).
- [ ] Command Issuance (click-to-move, context actions).
- [ ] Protocol Command System (Swarm Rush: select soldiers, target location, execute).
- [ ] HUD displays (metal, units, protocol wheel placeholder).
- [ ] Minimap (basic, not interactive).

**Checkpoint:**
- [ ] Player can pan camera, select units, issue move commands.
- [ ] Protocol wheel appears on hold, protocols can be triggered (no effect yet).

---

### Phase 3: Swarm Units (1.5 weeks)
**Goal:** Swarm unit mechanics, autonomous behavior, production.

**Deliverables:**
- [ ] **Harvester Unit:**
  - Seek metal deposits.
  - Enter deposit and extract (1 metal/sec).
  - Auto-return to idle if deposit depleted or commanded away.
- [ ] **Soldier Unit:**
  - Idle patrol behavior.
  - Detect resistance units (150px range).
  - Engage melee combat (6 damage, 1 attack/sec).
  - Retreat if outnumbered.
- [ ] **ReplicationHub:**
  - Queue-based production (FIFO).
  - Costs: Harvester 8, Soldier 12 (fixed for MVP).
  - Production time: 6 seconds per unit.
  - Spawn units at hub location.
- [ ] **LimboAI Behavior Trees:**
  - Harvester tree (seek → approach → extract).
  - Soldier tree (patrol → detect → engage → retreat).
- [ ] **Swarm Rush Protocol:**
  - Select nearby soldiers within 80px.
  - Move soldiers to target location at 2× speed.
  - Attack resistance units for 10 seconds.
  - Resume autonomy.

**Checkpoint:**
- [ ] Harvesters extract metal, metal counter increments.
- [ ] Soldiers spawn via queue, engage Patrol Units, can be commanded via Swarm Rush.

---

### Phase 4: Economy (1 week)
**Goal:** Resource management, production queue, economic pressure.

**Deliverables:**
- [ ] **MetalDeposit Nodes:**
  - 3 deposits on map (Small, Medium, Small).
  - Static (no depletion for MVP).
  - Harvester units automatically extract.
- [ ] **Production Queue:**
  - Queue up to 5 units per hub.
  - Deduct metal upfront.
  - Wait for sufficient metal if queue exceeds available balance.
- [ ] **Economic Feedback:**
  - Display metal/sec income on HUD.
  - Show next production unit + time remaining.
  - Alert if economy stalls (0 metal, production paused).
- [ ] **Difficulty Scaling (Basic):**
  - Reduce starting metal to 50 (create early pressure).
  - Increase unit costs in later game phases (EXPANSION: +50% cost).

**Checkpoint:**
- [ ] Players can sustain 2–3 Harvesters + 4–6 Soldiers production loop.
- [ ] Economy feels tight but manageable (goal: medium playtime = 5 mins to reach 50% assimilation).

---

### Phase 5: Resistance AI (1.5 weeks)
**Goal:** Opposition forces, escalation, basic coordination.

**Deliverables:**
- [ ] **Patrol Unit AI (LimboAI):**
  - Patrol assigned waypoints.
  - Detect swarm units (150px range).
  - Engage melee (6 damage, 1 attack/sec).
  - Retreat if health < 20%.
  - 2 Patrol Units on initial map, 1 extra on escalation.
- [ ] **Turret AI (LimboAI):**
  - Static position, cannot move.
  - Fire at nearest swarm unit within 120px (1 shot/1.5 sec).
  - 15 damage per shot (area denial, high threat).
  - 1 Turret guarding high-value deposit.
- [ ] **ResistanceAISystem:**
  - Register/track all resistance units.
  - Broadcast detection signals to nearby allies.
  - (Full coordination deferred; basic signals only for MVP.)
- [ ] **Escalation Trigger:**
  - When swarm size > 15, trigger RESISTANCE_SURGE.
  - Spawn 1 additional Patrol Unit + 1 additional Turret.
  - (Commander + Reaction Force deferred.)

**Checkpoint:**
- [ ] Patrol Units patrol, detect, and engage swarm.
- [ ] Turrets fire and create danger zones.
- [ ] Escalation spawns new resistance units.

---

### Phase 6: MVP Polish (1 week)
**Goal:** Integration, balance, visual feedback, end-to-end playtesting.

**Deliverables:**
- [ ] **Assimilation System:**
  - Track % of facility assimilated (simple % counter, not per-zone).
  - Victory condition: 50% assimilation + defeat all resistance OR survive timer.
  - Assimilation increments as swarm controls area (proximity-based, simple).
- [ ] **HUD Polish:**
  - Metal counter (current/income).
  - Unit roster (count per type).
  - Assimilation progress bar.
  - Minimap with unit positions.
  - Protocol wheel (refined visuals).
  - Alerts (new resistance detected, escalation triggered).
- [ ] **Visual Feedback:**
  - Unit selection outline (blue).
  - Damage flash (red).
  - Protocol activation aura (cyan).
  - Assimilation zone color shift (gray → cyan overlay).
- [ ] **Audio Integration:**
  - Ambient hum (facility baseline).
  - Harvest clink (Harvester extracting).
  - Attack sounds (soldier & turret combat).
  - Protocol activation tone.
  - Victory/defeat music cue.
- [ ] **Multiplayer Sync (Local Co-op):**
  - Shared metal pool synchronized.
  - Both players can queue units (FIFO command resolution).
  - Shared victory/defeat condition.
  - (Network replication deferred.)
- [ ] **Playtesting & Balance:**
  - Playtest solo and co-op (target 8–12 minutes per playthrough).
  - Adjust unit costs, harvest rates, resistance spawn timing.
  - Verify victory is achievable but requires strategy (not trivial).
  - Tune difficulty: easy if passive, medium if player keeps units alive, hard if player loses momentum.

**Checkpoint:**
- [ ] End-to-end playable mission (LOBBY → ASSIMILATION_COMPLETE or COLONY_DESTROYED).
- [ ] Victory achievable in 10–15 minutes with competent play.
- [ ] Cooperative play is seamless (no desync, shared economy works).
- [ ] Swarm feels responsive and autonomous.

---

## Checkpoint Validation Criteria

### Phase 1 Checkpoint
- [ ] Game initializes without errors.
- [ ] State machine transitions work (console logs confirm state changes).
- [ ] MetalEconomy tracks metal balance correctly.

### Phase 2 Checkpoint
- [ ] Camera pans and zooms smoothly.
- [ ] Units can be selected individually and in groups.
- [ ] Commands move units to cursor location.
- [ ] Swarm Rush protocol can be triggered (even if no effect yet).

### Phase 3 Checkpoint
- [ ] Harvesters extract metal from deposits (metal counter increments).
- [ ] Soldiers spawn and patrol autonomously.
- [ ] Soldiers engage Patrol Units in combat.
- [ ] Swarm Rush moves soldiers to target and they attack.

### Phase 4 Checkpoint
- [ ] Production queue processes units in order.
- [ ] Metal is deducted on queue, not on spawn.
- [ ] Queue waits if insufficient metal.
- [ ] Economy sustains 5–8 unit swarm without collapse.

### Phase 5 Checkpoint
- [ ] Patrol Units move along waypoints and engage swarm on detection.
- [ ] Turrets fire and deal meaningful damage.
- [ ] Escalation spawns new resistance units when threshold crossed.
- [ ] Swarm can destroy resistance units (not impossible, but challenging).

### Phase 6 Checkpoint
- [ ] Single playthrough completes (victory or defeat).
- [ ] Assimilation % displayed and increments as swarm controls area.
- [ ] All HUD elements update correctly in real-time.
- [ ] Multiplayer: both players contribute to shared metal, both can trigger protocols.
- [ ] Audio plays without distortion or lag.
- [ ] Victory/defeat screens display correctly.

---

## Testing Focus per Phase

### Phase 1–2 Testing
- Core initialization and architecture.
- No gameplay yet; focus on systems integration.

### Phase 3–4 Testing
- Unit behavior and autonomy.
- Economy sustainability.
- **Metrics:** Time to produce 5 soldiers with 2 harvesters (target: 30–40 seconds).

### Phase 5 Testing
- Resistance difficulty.
- Escalation triggering.
- **Metrics:** Can player defeat initial Patrol + Turret combo with 8 soldiers? (Should be challenging but possible.)

### Phase 6 Testing
- **Full playthroughs:** 3–5 complete runs (goal: 8–12 mins per run).
- **Balance:** Adjust costs and spawn rates until victory feels earned.
- **Co-op:** Verify shared economy and command sync work seamlessly.
- **Accessibility:** Check HUD readability, audio clarity, control responsiveness.

---

## Post-MVP Roadmap (High-Level)

### Post-MVP Phase A: Unit Roster Expansion (2 weeks)
- Scout units (fog of war reveal).
- Builder units (place hubs, expand network).
- Assimilator units (late-game conversion mechanic).
- Full behavior trees per unit type.

### Post-MVP Phase B: Protocol Expansion (1 week)
- Rapid Replication, Scatter, Defensive Formation, Assimilation Wave.
- Cooldown tracking and UI display.
- Protocol stacking/conflict resolution refinement.

### Post-MVP Phase C: Resistance Expansion (2 weeks)
- EMP Drones (disable units temporarily).
- Commander units (buff aura, rally calls).
- Reaction Force spawning logic.
- Flanking and group coordination tactics.

### Post-MVP Phase D: World Expansion (2 weeks)
- Multi-zone facility layout (5+ zones).
- Per-zone assimilation tracking.
- Fog of war full implementation (Scout reveal mechanics).
- Assimilation shader (full color/energy transformation).

### Post-MVP Phase E: Difficulty & Progression (1 week)
- Easy/Normal/Hard difficulty settings.
- Tutorial sequence.
- Escalation surges (dynamic difficulty spikes).

---

## Resource Estimates (MVP Timeline)

| Phase | Duration | FTE | Milestones |
|-------|----------|-----|-----------|
| 1: Foundation | 1 week | 1 | Core architecture, state machine, base classes |
| 2: Camera & Input | 1 week | 1 | RTS controls, selection, commands |
| 3: Swarm Units | 1.5 weeks | 1 | Harvester, Soldier, autonomy, production |
| 4: Economy | 1 week | 1 | Deposits, queue, cost balancing |
| 5: Resistance AI | 1.5 weeks | 1 | Patrol, Turret, escalation, basic AI |
| 6: Polish & Test | 1 week | 1 | Integration, balance, multiplayer sync, playtesting |
| **Total MVP** | **7 weeks** | **1** | **Playable end-to-end mission** |

---

## Success Metrics (MVP)

- [ ] **Playability:** Full mission can be completed (victory or defeat) in 1 session (8–15 mins).
- [ ] **Engagement:** Players report the harvest → replicate → overwhelm loop feels rewarding and strategic.
- [ ] **Difficulty Balance:** Victory is achievable but requires competent play (micro + macro decisions).
- [ ] **Multiplayer:** Co-op mode works without desync; shared economy creates cooperation incentives.
- [ ] **Performance:** Runs at 60 FPS with 20–30 units + resistance on screen.
- [ ] **Polish:** HUD is readable, audio is clear, visuals are cohesive (no jarring mismatches).

---

## Risks and Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| **Unit autonomy feels unintuitive** | Medium | High | Early playtesting; adjust AI behavior trees based on feedback. |
| **Economy pressure too tight** | Medium | High | Playtesting; scale deposit yields and production times. |
| **Resistance escalation triggers unclear** | Low | Medium | Clear HUD alerts when escalation occurs. |
| **Multiplayer desync** | Low | High | Implement server-authoritative command processing early (Phase 2). |
| **Performance bottleneck (particle VFX)** | Medium | Medium | Optimize particle pool early; use instancing sparingly in MVP. |
| **Feature creep extends timeline** | High | High | **Strict scope discipline:** Anything not in "Must-Have" goes to Post-MVP. |

---

## Notes

- **GDScript Conventions:** Use typed classes, signal-driven architecture, composition over inheritance.
- **Modularity:** Each major system (economy, input, AI) should be independently testable.
- **Documentation:** Update REQ docs as implementation reveals design gaps.
- **Version Control:** Commit at end of each phase with stable, playable state.

