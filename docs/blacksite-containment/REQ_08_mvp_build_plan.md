# REQ_08: MVP Build Plan
**Scope, Phases, and Deferred Features**

## MVP Goal Statement

Prove that the core loop (patrol + charge laser + escapee destruction) is fun and engaging with 1–4 players in a playable demo. Deliverable: a single containment lane mission with 3 waves, responsive drone controls, a working charge laser, basic escapee AI (Runner type), wave progression, and score calculation. Target: playable in 2–3 weeks of focused development.

---

## MVP Scope (Must-Have)

### Features

- **Drone Movement**: Full 3D hover physics, smooth acceleration, omnidirectional input via controller.
- **Charge Laser**: Hold-to-charge mechanism (1 second full charge), fire on release, damage output varies by charge level, overheat system with cooldown.
- **Containment Arena**: One complete lane, perimeter breach zone, spawn points, navigation mesh.
- **Escapee AI**: Basic Runner type only (direct path to breach, no evasion), behavior-tree-driven pathfinding, health/destruction.
- **Wave System**: 3 waves of increasing difficulty; wave spawning, tracking, progression to next wave.
- **Mission States**: LOBBY → BRIEFING → PATROL → ALERT (optional, may simplify to direct breach detection) → BREACH_ATTEMPT → MISSION_COMPLETE / MISSION_FAILED → DEBRIEF.
- **HUD (Minimal)**: Charge laser bar, energy meter, team status (player count), mission integrity meter, minimap (basic viewport), wave counter, kill count.
- **Audio**: Basic charge hum, fire sound, breach klaxon, wave transition chime. No full music profile (use placeholder).
- **Scoring**: Kill count + breach prevention score, displayed in debrief.
- **Multiplayer (Local + Online)**: 1–4 players, host-authoritative movement sync, RPC-based damage registration.

### NOT Included in MVP

- Orbital Strike (ability).
- Burst Speed Maneuver (ability).
- Framerate Control / Bullet Time (ability).
- Evader, Tank, Swarm, Elite escapee types.
- Multiple containment lanes (only 1 lane spawns escapees).
- Cooperative bonuses (assists, orbital coordination).
- Full debrief screen (basic score display only).
- Advanced graphics (scan-line overlay, advanced particles).
- Difficulty selector / scaling for >4 players.
- AFK detection.
- Full music reactivity profile.

---

## Deferred Feature Backlog

| Feature | Reason | Post-MVP Phase |
|---------|--------|-----------------|
| Orbital Strike | Complex targeting UX; can iterate on laser first | Phase 4: Polish |
| Burst Speed | Feels less critical than charge laser; test solo first | Phase 4: Polish |
| Framerate Control | Cool but non-essential; defers complexity | Phase 5: Advanced Abilities |
| Elite Escapees | Requires design iteration; vanilla types sufficient for testing | Phase 3: AI Expansion |
| 5–8 Player Scaling | Test 4-player baseline first; scale up later | Phase 6: Scale |
| Advanced HUD | Minimap functional but minimal; advanced UI post-MVP | Phase 5: Polish+ |
| Difficulty Settings | Test single difficulty (default 4-player) | Phase 4: Options |
| Leaderboard / Stats | Out of scope; storage/backend future work | Post-Launch |

---

## Build Phases

### Phase 1: Foundation (Days 1–2)
**Goal**: Scene structure, basic GameManager hooks, input setup.

**Tasks**:
- [ ] Create scene file `blacksite_containment_arena.tscn` with basic arena geometry (floor, walls, perimeter).
- [ ] Set up GameManager reference (existing SHARED_01 integration).
- [ ] Create MissionStateManager (script) with enum states and basic transition logic.
- [ ] Define input actions (Move, Charge Laser, Pause) in InputMap.
- [ ] Create DronePlayer scene (CharacterBody3D with basic mesh, collision) and instantiate 1–4 player drones.
- [ ] Test scene loads without errors; players can be toggled on/off.

**Checkpoint**: Scene loads, GameManager accessible, input map defined, 4 drone entities spawnable.

**Deferred**: Escapee spawning, scoring, music integration.

---

### Phase 2: Drone Controls (Days 3–4)
**Goal**: Responsive movement and camera follow.

**Tasks**:
- [ ] Implement DroneController (CharacterBody3D hovering physics, no gravity).
  - Left stick input → horizontal velocity.
  - Up/Down input → altitude control.
  - Smooth velocity interpolation (0.2s accel, 0.85 friction).
- [ ] Implement DroneCamera (fixed isometric follow, 12m back, 8m up, -45° pitch).
  - Smooth position lerp.
  - Look-at drone center.
- [ ] Test drone response:
  - No input lag.
  - Smooth acceleration and deceleration.
  - Camera doesn't clip into drone or arena.
  - Soft repulsion prevents drone clipping (rough version: raycast repulsion).

**Checkpoint**: Drone moves responsively; camera follows smoothly. 4 drones can move without clipping each other or arena.

**Deferred**: Dash mechanic, advanced collision.

---

### Phase 3: Charge Laser (Days 5–7)
**Goal**: Full laser system with visual and audio feedback.

**Tasks**:
- [ ] Implement DroneAbilityManager (script).
  - RT hold input tracking (charge_start_time).
  - Charge ratio calculation (elapsed time / 1.0s).
  - Fire on release: hitscan raycast, damage based on charge ratio (25/65/100 HP per level).
  - Overheat on >1.0s hold: force fire + 2s cooldown.
- [ ] Implement charging visual feedback.
  - Drone barrel glow (cyan, intensity scales with charge).
  - HUD charge bar (0–100%, color: cyan → green → red).
  - Full charge indicator (green "Ready" text).
- [ ] Implement firing visual/audio.
  - Laser beam VFX (cyan ray, brief duration).
  - Impact bloom (orange particle burst at hit point).
  - Fire sound (laser zap SFX).
  - Overheat sound (alarm beeps + harsh tone).
- [ ] RPC infrastructure: `_request_escapee_damage()` from client → host; `_apply_damage_vfx()` broadcast to all.
- [ ] Test laser:
  - Charge timing feels tight (1.0s full).
  - Overheat triggers on >1.0s hold; prevents further charging for 2s.
  - Damage scales visibly with charge level.
  - VFX and audio sync properly.

**Checkpoint**: Laser fully functional with feedback. Multiple drones can fire without interference.

**Deferred**: Orbital strike, burst speed, advanced ability interactions.

---

### Phase 4: Escapee AI (Days 8–10)
**Goal**: One escapee type (Basic Runner) with pathfinding and destruction.

**Tasks**:
- [ ] Create EscapeeEntity base class (CharacterBody3D).
  - Health component (health: 50, max_health: 50).
  - NavigationAgent3D child for pathfinding.
  - `take_damage(damage: float, source_drone_id: String)` method.
  - `destroy()` method (emit signal, queue_free).
- [ ] Create EscapeeRunner subclass.
  - Base stats: health 50, speed 15 m/s, size 1.0.
  - Simple behavior tree: move toward breach at constant speed.
- [ ] Implement EscapeeManager (Node, spawner logic).
  - Spawn point marker definitions in arena.
  - Wave configuration (JSON or GDScript resource): Wave 1 (20 runners over 60s), Wave 2 (25 runners over 45s), Wave 3 (30 runners over 40s).
  - Frame-based spawn timer: emit one escapee every X frames based on spawn_rate.
  - Track spawned escapees; trigger wave_complete when all spawned and destroyed.
- [ ] Implement PerimeterBreach detector (Area3D).
  - On escapee entry: signal breach, reduce mission integrity by 25, remove escapee.
- [ ] Test escapee:
  - Runners spawn at correct intervals.
  - Pathfinding works (avoid walls, reach breach).
  - Laser hits kill them (health → 0 → destruction signal).
  - Breach detection works (escapee in zone → integrity loss, escapee removed).
  - Waves progress correctly.

**Checkpoint**: Single runner type fully playable. Wave 1 spawns 20, Wave 2 spawns 25, Wave 3 spawns 30. Drones can destroy runners and prevent breaches.

**Deferred**: Evader/Tank/Swarm types, elite variants, damage resistance, swarm flocking.

---

### Phase 5: Wave System & Mission Flow (Days 11–12)
**Goal**: Full mission progression from BRIEFING to DEBRIEF.

**Tasks**:
- [ ] Enhance MissionStateManager (enum-based or simple node tree).
  - States: LOBBY, BRIEFING, PATROL, ALERT (optional, may simplify), BREACH_ATTEMPT, MISSION_COMPLETE, MISSION_FAILED, DEBRIEF.
  - Transitions and signal emissions per REQ_02.
  - Timer logic (e.g., 3s briefing, 30s chase timer if ALERT is included).
- [ ] Implement MissionIntegrity component.
  - Starting value: 100 points.
  - Breach cost: 25 points per event.
  - Check integrity == 0 → trigger MISSION_FAILED.
- [ ] Implement ScoreCalculator (REQ_05 formula).
  - Per-wave score: breach prevention, kill count, time bonus (simplified: just kill count * 10 for MVP).
  - Wave totals + final score displayed in debrief.
- [ ] Implement basic Debrief screen (CanvasLayer overlay).
  - Display: mission status (success/failed), final score, kills, breaches.
  - "Next Mission" and "Return to Lobby" buttons (just reload scene or return to menu).
- [ ] Link wave completion → next wave or mission end.
  - Wave 3 complete → MISSION_COMPLETE (if integrity > 0).
- [ ] Test mission flow:
  - Start mission → briefing plays → wave 1 spawns → drones fight → wave complete → wave 2 starts → ... → mission ends → debrief displays score.

**Checkpoint**: Full mission loop playable end-to-end. Debrief shows score. Integrity system works (breaches reduce meter, 0 = mission failed).

**Deferred**: Full state machine, ALERT escalation, AFK handling, advanced state transitions.

---

### Phase 6: HUD & Polish (Days 13–15)
**Goal**: Functional HUD, visual clarity, audio polish.

**Tasks**:
- [ ] Implement HUD (CanvasLayer overlay).
  - Charge laser bar (cyan bar, 0–100%, "Ready" text when full).
  - Overheat meter (red, shows cooldown countdown).
  - Team status (player names + kill count, simple vertical list).
  - Mission integrity bar (green to red gradient, %).
  - Wave counter ("Wave 2 / 3", escapee count "15 remaining").
  - Kill feed / notifications (text log, 3–5 recent events).
  - Minimap (simple viewport rendering arena from top, dots for drones + escapees).
- [ ] Polish drone VFX.
  - Charge barrel glow (subtle cyan glow on drone mesh, scales with charge).
  - Laser beam (cyan line renderer or particle trail from drone to impact).
  - Impact bloom (orange particles at hit point, brief duration).
  - Overheat red glow (brief screen flash or drone tint).
- [ ] Polish audio.
  - Charge hum (looping synth tone, pitch rises from 200Hz to 800Hz over 1s).
  - Fire zap (short laser sound, ~50ms).
  - Overheat alarm (three beeps, ascending pitch).
  - Breach klaxon (loud alarm, repeating tone).
  - Wave complete chime (short triumphant note).
  - Mission complete stab (uplifting musical chord).
- [ ] Test HUD clarity:
  - All meters readable at 1080p and 4K.
  - Minimap updates smoothly (60fps).
  - Notifications don't overlap or spam.
  - VFX visible but not distracting.
  - Audio mix balanced (no clipping, all sounds audible).

**Checkpoint**: HUD fully functional and readable. VFX and audio enhance gameplay without performance impact. Mission is visually and aurally polished.

**Deferred**: Advanced UI (difficulty selector, settings), scan-line overlay, advanced particles.

---

## Testing Matrix (MVP Validation)

### Functional Tests

| Test | Expected Result | Status |
|------|-----------------|--------|
| Load arena scene | Scene loads, no errors | — |
| 1 player spawns | Drone appears at staging area, can move | — |
| 4 players spawn | All 4 drones spawn without clipping | — |
| Charge laser fires | Laser visible, damage applied to escapee, escapee health reduced | — |
| Escapee destroyed | Escapee health = 0, destruction VFX plays, score increments | — |
| Wave progression | Wave 1 complete → Wave 2 starts automatically | — |
| Breach detection | Escapee in perimeter zone → integrity loss, escapee removed | — |
| Mission complete | Wave 3 done, integrity > 0 → success debrief | — |
| Mission failed | Integrity = 0 → failed debrief | — |
| Multiplayer sync | Remote drone positions smooth, no teleporting | — |
| Damage RPC | Client damage request → host validates → broadcast VFX | — |

### Balance Tests (Post-Functional)

| Test | Goal | Tuning Variable |
|------|------|-----------------|
| Solo difficulty | 1 player can clear 3 waves, ~5 breaches | Spawn rate, escapee health |
| 4-player difficulty | 4 players clear 3 waves with 0–2 breaches | Spawn rate, escapee health |
| Laser damage feels good | Full charge kills Basic Runner in 1 hit | Damage values per charge level |
| Charge timing feels tight | 1.0s to full charge is intuitive, not too fast/slow | CHARGE_TIME constant |
| Overheat penalty is punishing | 2s cooldown discourages spam | OVERHEAT_COOLDOWN constant |
| Pacing is engaging | Waves escalate naturally; no dead time or overwhelming pressure | Wave spawn_rate, difficulty_multiplier |

### Polish Tests (Pre-Launch)

| Test | Goal | Notes |
|------|------|-------|
| 60fps maintained | No frame drops during 4-player, max escapees | Profile with DevTools |
| Audio mix balanced | Music not drowning SFX, klaxon demands attention but not painful | Adjust SFX volumes |
| VFX readable | Laser impact, breach flash, all effects visible and clear | Optimize particle counts if needed |
| HUD legible | All text readable at 1080p and 4K, colors clear | Font size, contrast testing |
| No network jank | Local + online play smooth, <100ms latency acceptable | Test on target network conditions |

---

## Success Criteria

**Minimum Viable Product is "Done" when:**

1. ✓ Drone controls are responsive (input feels immediate, no frame lag).
2. ✓ Charge laser is fun (feedback is satisfying; charging and firing feels rewarding).
3. ✓ Escapees spawn, move, and can be destroyed (Runner AI works).
4. ✓ Full mission loop playable (BRIEFING → PATROL → DEBRIEF, ~5–7 minutes per mission).
5. ✓ Multiplayer works (1–4 players, host-authoritative, smooth sync).
6. ✓ Scoring and debrief functional (final score displays, no crashes).
7. ✓ 60fps performance maintained (no stuttering during max action).
8. ✓ Audio/visual feedback clear (drones, players, and testers report "feels good").

**Out-of-Scope Failures** (acceptable for MVP, addressed post-launch):
- Orbital strike, burst speed, framerate control not implemented.
- Only 1 escapee type (Basic Runner).
- Single containment lane (not multiple).
- No difficulty selector, no 5–8 player balancing.
- Minimal debrief (basic score, no detailed breakdown).
- No leaderboard, no cosmetics, no progression.

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Pathfinding fails (escapees stuck) | Pre-bake NavigationMesh early; test with temp placeholder escapee. If issues, fall back to simple movement (beeline to breach point, no obstacles). |
| Network sync jittery | Use delta compression for positions; sync every 2 frames (33ms). If still laggy, increase interpolation window (0.1s smooth lerp). |
| Laser overheat confusing | Make overheat visual **very obvious** (red glow, screen tint, loud alarm). Playtest with non-developers; iterate if feedback suggests confusion. |
| 4-player too hard/easy | Balance difficulty multipliers during Phase 5 testing. If too hard, reduce spawn_rate. If too easy, increase escapee health. |
| Performance regression | Profile weekly; cap max escapees at 50 if needed. Use object pooling if spawn/destroy overhead detected. |
| Time overrun | Strict scope adherence: defer orbital, burst, framerate control immediately. Focus on laser + wave loop. |

---

## Timeline Summary

```
Week 1:
  Days 1–2:  Phase 1 (Foundation)
  Days 3–4:  Phase 2 (Drone Controls)
  Days 5–7:  Phase 3 (Charge Laser)

Week 2:
  Days 8–10: Phase 4 (Escapee AI)
  Days 11–12: Phase 5 (Wave System)
  Days 13–15: Phase 6 (HUD & Polish)

Target: MVP ready by end of Week 2 (Day 15).
Buffer: Days 16+ reserved for bug fixes, balance tuning, and unforeseen integration issues.
```

---

**Implementation Notes:**
- Code versioning: commit after each phase checkpoint. Tag `mvp-phase-1`, `mvp-phase-2`, etc.
- Playtesting: internal milestone at end of each phase (5–10 min gameplay). Gather feedback, iterate.
- Asset pipeline: all art/audio use existing BurnBridgers library (SHARED_01). No custom asset creation unless essential.
- Documentation: keep REQ docs in sync with implementation; tag breaking changes in commit messages.
