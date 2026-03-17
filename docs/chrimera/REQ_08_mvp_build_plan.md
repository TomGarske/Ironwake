# REQ-08: MVP Build Plan
**Chrimera: Bioforge Run**

## Overview
The MVP (Minimum Viable Product) goal is to **prove the core run-and-escape loop is fun** with 1–2 players, focusing on movement, tool improvisation, and cooperative tension. This document breaks down the MVP scope, must-have features, deferred features, and a 6-phase build plan with testing checkpoints.

---

## MVP Scope and Goals

### What MVP Must Prove
1. **Movement feels responsive and fun:** Jump, slide, and platforming are tight and satisfying.
2. **Tool improvisation is engaging:** Players adapt to found tools, not pre-selected loadouts.
3. **Threat escalation creates pacing:** Starting safe, ending in crisis feels natural.
4. **Cooperation creates tension:** Shared lives pool and downed revives matter emotionally.
5. **One complete run is winnable:** Players can finish the escape in 3–5 minutes (1 player) or 2–3 minutes (2 players).

### MVP Success Criteria
- [ ] Single player completes a run in 3–5 minutes.
- [ ] Two players cooperatively complete a run in 2–3 minutes.
- [ ] No game-breaking bugs or soft-locks.
- [ ] Movement feels responsive (sub-50ms input latency).
- [ ] Tool swaps and interactions are intuitive.
- [ ] Threat escalation is visible (more entities, more variety per level).

---

## Must-Have Features (MVP Core)

### Character and Movement
- **PlayerCharacter scene** (CharacterBody2D with Sprite2D, CollisionShape2D).
- **Base movement actions:** Move left/right (keyboard + controller), jump with variable height, slide with cooldown.
- **Animation states:** Idle, Run, Jump, Fall, Slide (at least 5 clips).
- **Input bindings:** WASD + Space (keyboard), left stick + A button (controller).
- **Physics:** Gravity, coyote time (0.1s), jump buffer (0.15s), slide i-frames (0.2s).
- **No wall-cling:** Deferred feature.

### Tool System (Minimal)
- **ExperimentalTool base class** (Resource subclass).
- **2 tool slots** (no upgrading to 3 in MVP).
- **3 starting tools** (one per category):
  - **Mobility:** Grapple Spike (swing 3m, reach elevated platform).
  - **Offensive:** Acidic Compound (arc projectile, 20 damage, consumable).
  - **Utility:** Scanner (reveal entities for 8s, cooldown 15s).
- **Tool pickup interaction:** Y button picks up, displays on HUD, can swap by picking up new tool.
- **No cooldown UI:** Just text "Ready" or "X.Xs cooldown" on HUD.

### Entities (AI)
- **2 entity types only:**
  - **Crawler:** Basic swarm, low health (10 HP), low damage (2 HP), chase behavior. Spawn 1–2 at a time.
  - **Lurker:** Ambush threat, medium health (15 HP), high burst (8 HP), 1s telegraph. Spawn 1 per room.
- **No Spreader, Amalgam, or Chimera Host in MVP.**
- **Simple LimboAI behavior trees:** Chase if player in 6m, else idle. Telegraph on Lurker attack.
- **Entity death:** Vanish with simple particle effect.

### Level (MVP Specific)
- **One hand-crafted level:** Research lab (12m × 8m).
  - Entry corridor (narrow, 2 Crawlers spawn).
  - Central chamber (wide, 1 Lurker + tool pickups).
  - Exit corridor (sloped, final Crawler wave).
  - Total playable time: 3–5 minutes.
- **TileMap:** Simple gray/blue color palette. No decay or contamination overlay.
- **Exit trigger:** Area2D at end of exit corridor. Player touches → level complete.

### State Machine (Simplified)
- **LOBBY:** Select player count (1 or 2), press Start.
- **RUN_START:** Initialize lives (2 for MVP), load level.
- **EXPLORING:** Players navigate, find tools, discover exit.
- **THREAT_ENCOUNTER:** Crawlers/Lurkers spawn, escalation phase.
- **LEVEL_EXIT:** Immediate level complete (no mid-level between-screen).
- **RUN_COMPLETE:** Show "You Escaped!" and run stats.
- **RUN_FAILED:** All lives exhausted, show "Run Failed."

### Lives and Downed System
- **Shared lives pool:** 2 lives per run (MVP simplified from standard 3).
- **Downed state:** Player health ≤ 0 → downed (can be revived by ally pressing Y within 2m for 1s).
- **Downed timer:** 8 seconds. If not revived, lives pool decrements by 1 and player is removed.
- **HUD display:** Two hearts (❤❤) for lives. Red flash at last life.

### Multiplayer (Cooperative, Local or Network)
- **1–2 players:** Split control or screen share in local coop. Network support via SteamManager (no splitscreen UI).
- **Player spawning:** Both spawn at level entrance.
- **Camera:** Follow both players; zoom out to frame both (simple orthographic zoom).
- **Shared lives:** One pool, visible to both.
- **Tool sync:** Each player has independent tool slots; tools are unique instances.

### Meta-Progression (Stub)
- **First completion:** Unlock "Engineer" archetype (bonus: electronic doors open -50% time).
- **Lives pool increase:** After 2 completed runs, starting lives increase to 3.
- **Persistence:** Save to `user://chrimera_meta_mvp.tres` (simple Resource file). No cloud sync.

### UI and HUD
- **Lobby screen:** "1 Player" vs "2 Player" buttons. "Start Run" button.
- **In-game HUD:**
  - Lives display (hearts, top-left).
  - Tool slots display (icon + text, left side).
  - Exit direction indicator (bottom-right, arrow + distance).
  - Contamination meter (top-right, simple bar, non-functional in MVP).
- **Level complete screen:** "Level Complete! [Stats]" with "Continue" button.
- **Run complete screen:** "Run Complete! You Escaped! [Stats]" with "Play Again" button.
- **Run failed screen:** "Run Failed! [Stats]" with "Retry" button.

### Audio (Minimal)
- **Music:** Generic placeholder loop (or MusicManager with single track, no intensity scaling).
- **Ambience:** Quiet facility hum (looping sine wave, ~100 Hz).
- **SFX:** Jump sound, tool use sound (simple beep), entity death sound.
- **No music scaling per difficulty.** Fixed music intensity for MVP.

---

## Deferred Features (Post-MVP)

### Full Tool Library
- **Not in MVP:** EMP Grenade, Sonic Emitter, Barrier Foam, Stasis Gel, Lateral Thruster, Speed Serum, Stabilization Serum, Med-Kit, Keycard Cracker, Contamination Filter, Toxin Injector.
- **Deferred reason:** Each tool adds animation, VFX, and behavior tree complexity. MVP prioritizes core loop.

### All Entity Types
- **Deferred:** Spreader (contamination zones), Amalgam (tank), Chimera Host (elite).
- **Deferred reason:** LimboAI trees for each type, VFX, special abilities.

### Procedural Level Generation
- **MVP:** One hand-crafted level repeated (boring but functional).
- **Deferred:** Full procedural room pool with seed-based layout. Requires 10–15 hand-authored room scenes.

### Contamination Spread System
- **Deferred:** Spreader entity, contamination zones (Area2D), shader overlay, damage-over-time.
- **Deferred reason:** Visual shader, zone physics, UI updates.

### Archetype System (Full)
- **MVP:** Archetype selection exists but only "Virologist" (default) and "Engineer" (after 1 run) are available. No stat bonuses applied.
- **Deferred:** Security, Lab Director, Escape Artist archetypes + their bonuses.

### Daily Challenge Runs
- **Deferred:** Fixed-seed leaderboard runs. Requires leaderboard UI integration.

### Wall-Cling / Ledge Grab
- **Deferred:** Optional platforming enhancement. Not critical to core loop.

### Cosmetic Upgrades
- **Deferred:** Cosmetic skins, animations, environment variations.

---

## 6-Phase Build Plan

### Phase 1: Foundation (1–2 weeks)
**Goal:** Core infrastructure, player scene, tilemap level.

#### Deliverables
- [x] Project structure (scenes/, assets/, scripts/ folders organized).
- [x] PlayerCharacter scene (CharacterBody2D, sprite, collision).
- [x] Basic movement (left/right, jump, coyote time, jump buffer).
- [x] Simple tilemap level (12m × 8m, platforms, collision).
- [x] Input bindings (WASD + Space, controller analog).
- [x] GameManager integration stub (game state, pause logic).

#### Testing Checkpoints
- [ ] Player moves left/right smoothly.
- [ ] Jump has variable height (0.3s–1.0s hold).
- [ ] Coyote time allows jump 0.1s after ground leave.
- [ ] Jump buffer allows input 0.15s before landing.
- [ ] Player can walk on tilemap, land on platforms.
- [ ] No clipping or physics glitches.

---

### Phase 2: Character Movement and Animation (1–2 weeks)
**Goal:** Full movement polish, animations, camera.

#### Deliverables
- [x] Animation player (Idle, Run, Jump, Fall, Slide).
- [x] Slide mechanic (cooldown, i-frames, hitbox reduction).
- [x] Camera follow (orthographic, lookahead in facing direction).
- [x] Multiplayer camera (frame both players, zoom out).
- [x] Crouch animation (optional for MVP, can stub).
- [x] Melee attack animation (0.3s swing, movement locked).

#### Testing Checkpoints
- [ ] Run animation plays when moving.
- [ ] Jump animation plays, transitions to fall mid-air.
- [ ] Slide animation plays, reduces hitbox height by 50%.
- [ ] Slide grants 0.2s i-frames (invulnerable feedback visible).
- [ ] Slide cooldown enforced (1s between slides).
- [ ] Camera stays centered on player with 2m lookahead.
- [ ] Two-player camera frames both, zooms out if spread > 8m.
- [ ] Melee animation locks movement for 0.3s.

---

### Phase 3: Tool System (1–2 weeks)
**Goal:** Tool pickup, slot management, basic tool effects.

#### Deliverables
- [x] ExperimentalTool base class (Resource, use() method).
- [x] ToolSlotManager (holds 2 active tools, handles swap).
- [x] ToolPickup scene (Area2D, detection, icon display).
- [x] Tool implementations (Grapple Spike, Acidic Compound, Scanner).
- [x] Tool HUD display (icons, cooldown text, active slot highlight).
- [x] Tool interaction (Y button picks up, swaps on new pickup).

#### Testing Checkpoints
- [ ] Pickup area displays tool icon on approach.
- [ ] Y button picks up tool into slot 1.
- [ ] Slot 1 is now active; HUD shows icon.
- [ ] Picking up second tool fills slot 2.
- [ ] Picking up third tool prompts swap (or auto-replaces based on game rules).
- [ ] RT (slot 1) and LT (slot 2) activate tools.
- [ ] Grapple Spike fires and swings player toward anchor.
- [ ] Acidic Compound throws arc projectile.
- [ ] Scanner reveals entity positions on minimap/UI.
- [ ] Cooldown text updates (e.g., "5.2s cooldown").
- [ ] Tool is consumed (Acidic Compound) or enters cooldown (Scanner).

---

### Phase 4: Entity AI and Encounters (2 weeks)
**Goal:** Crawler and Lurker behavior trees, spawning, threat.

#### Deliverables
- [x] CRISPREntity base class (CharacterBody2D, health, state).
- [x] Crawler behavior tree (chase if detected, idle/patrol, attack).
- [x] Lurker behavior tree (ambush telegraph, burst attack).
- [x] Entity spawner (timed waves, spawn points in level).
- [x] Entity death (health ≤ 0 → death state, despawn after 2s).
- [x] Damage and knockback (apply damage on hit, knockback velocity).
- [x] Downed system (player health ≤ 0 → downed, revive timer).
- [x] Lives pool (shared, decrements on death, reaches 0 → RUN_FAILED).

#### Testing Checkpoints
- [ ] Crawler spawns at designated point, idles in patrol.
- [ ] Crawler detects player in 6m range.
- [ ] Crawler chases player, attacks when in melee range (1m).
- [ ] Crawler attack deals 2 HP damage.
- [ ] Lurker spawns, hides in corner (idle pose).
- [ ] Lurker detects player in 10m range.
- [ ] Lurker performs 1s telegraph (visible animation/sound).
- [ ] Lurker attacks after telegraph, deals 8 HP damage.
- [ ] Player health displays on HUD, decreases on hit.
- [ ] Player dies (health ≤ 0), enters downed state (semi-transparent, immobile).
- [ ] Downed player can be revived by ally pressing Y (within 2m, 1s hold).
- [ ] Revived player regains 50% health.
- [ ] Downed timer expires after 8s → permanent death, lives pool -1.
- [ ] Lives pool displays as hearts. On last life, red flash warning.
- [ ] All lives exhausted → RUN_FAILED state.

---

### Phase 5: Level Structure and State Machine (1–2 weeks)
**Goal:** Level transitions, run state machine, UI screens.

#### Deliverables
- [x] LevelSegment scene (tilemap, rooms, entity spawners, exit trigger).
- [x] RunController (manages level progression, lives pool, state transitions).
- [x] Run state machine (LOBBY → RUN_START → EXPLORING → LEVEL_EXIT → RUN_COMPLETE).
- [x] Lobby screen (player count selection, ready check, Start button).
- [x] Level complete screen (stats, Continue button).
- [x] Run complete screen (escaped!, stats, Play Again button).
- [x] Run failed screen (failed stats, Retry button).
- [x] In-game HUD (lives, tools, exit indicator, contamination stub).
- [x] Meta-progression save/load (file I/O, archetype unlock).

#### Testing Checkpoints
- [ ] Lobby displays correctly, accepts player count input.
- [ ] Pressing Start initializes lives (2) and loads level.
- [ ] Level spawns entities on schedule.
- [ ] Player navigates and finds exit trigger.
- [ ] Touching exit trigger transitions to level complete screen.
- [ ] Level complete screen shows run stats (time, kills, damage taken).
- [ ] Continue button advances to RUN_COMPLETE (or next level if applicable).
- [ ] RUN_COMPLETE screen shows "Escaped!" + stats.
- [ ] Pressing Play Again returns to Lobby.
- [ ] RUN_FAILED screen shows on lives depletion.
- [ ] Meta state saves to file after run completion.
- [ ] Loading game restores meta state (archetype unlocks, lives bonus).

---

### Phase 6: Polish, Testing, and MVP Release (1–2 weeks)
**Goal:** Bug fixes, balance tuning, performance optimization, documentation.

#### Deliverables
- [x] Placeholder audio (jump SFX, entity SFX, facility hum).
- [x] VFX polish (tool effects, entity death, hit feedback).
- [x] Balance tuning (entity damage, spawn rates, tool cooldowns).
- [x] Controller input smoothing (deadzone calibration, button hold detection).
- [x] Multiplayer testing (network stability, state sync, peer disconnect handling).
- [x] Bug fixes (clipping, soft-locks, audio glitches).
- [x] Performance optimization (entity pooling, tilemap batching, shader compilation).
- [x] Documentation (README, quick-start guide).

#### Testing Checkpoints
- [ ] Single player completes level in 3–5 minutes.
- [ ] Two players cooperatively complete level in 2–3 minutes.
- [ ] No crashes or soft-locks during 10 consecutive runs.
- [ ] Network connection stable; player disconnect handled gracefully.
- [ ] Frame rate stable (60 FPS target).
- [ ] No visual clipping or physics glitches.
- [ ] All audio plays correctly (no missing SFX).
- [ ] Controller input responsive (< 50ms latency).
- [ ] Tool effects visible and match descriptions.
- [ ] All menu screens navigate correctly.

---

## Risk Mitigation

### High-Risk Areas
| Risk | Mitigation |
|------|-----------|
| **Networking unstable** | Test multiplayer early (Phase 4). Use SteamManager stubs if needed. |
| **LimboAI integration unclear** | Prototype simple behavior tree in Phase 1. Reference Godot docs. |
| **Tilemap performance** | Use tilemap physics layers; avoid per-pixel collision. Test with 200+ entities. |
| **Scope creep** | Freeze feature list; defer post-MVP. Track tasks with TODO comments. |
| **Audio latency** | Pre-load all SFX in Phase 5. Test on target platform. |

---

## Success Metrics

### MVP Release Checklist
- [ ] All Phase 1–6 deliverables completed.
- [ ] All testing checkpoints pass.
- [ ] Single-player run finishes in 3–5 minutes.
- [ ] Two-player run finishes in 2–3 minutes with 80%+ win rate (in playtesting).
- [ ] No game-breaking bugs.
- [ ] Documentation complete (README, control guide).
- [ ] Built executable provided for playtesting.

---

## Post-MVP Roadmap

### Phase 7: Full Tool Library (2–3 weeks)
- Implement all 11 tools (10 post-MVP + 1 Grapple Spike from MVP).
- Animate tool usage (impact frames, projectile arcs).
- Design tool synergies and test combinations.

### Phase 8: Complete Entity Set (2–3 weeks)
- Implement Spreader (contamination zones, persistence).
- Implement Amalgam (tank mechanics, armor).
- Implement Chimera Host (elite abilities, loot).

### Phase 9: Procedural Level Generation (3–4 weeks)
- Author 15+ hand-crafted room scenes.
- Implement seed-based room ordering.
- Test procedural variation for replayability.

### Phase 10: Visual Polish (2–3 weeks)
- Environment decay per level (cracks, rust, bio-growth).
- Contamination overlay shader (active, intensity scaling).
- Improved VFX and particle effects per tool/entity.

### Phase 11: Full Archetype System (1–2 weeks)
- Unlock all archetypes via milestones.
- Apply stat bonuses per archetype.
- Balance archetype progression.

### Phase 12: Leaderboard and Daily Challenges (1–2 weeks)
- Leaderboard UI integration.
- Daily challenge seed generation.
- Cloud sync for meta-progression.

---

## Handoff Document

At MVP completion, provide:
1. **Built executable** (Windows, macOS, Linux).
2. **This document** (REQ-08) + all 8 REQ docs.
3. **README** (quick-start, controls, known issues).
4. **Playtest feedback form** (for community feedback).
5. **Codebase snapshot** (git tag, clean history).

---

## Next Steps
- Begin Phase 1: Foundation setup.
- Confirm team availability and milestones.
- Set up daily stand-ups or weekly progress reviews.
