# REQ-09: Domain Glossary
**Chrimera: Bioforge Run**

## Overview
This glossary defines key terms and concepts used throughout Chrimera requirements and design documentation. Precise definitions prevent ambiguity and ensure clear communication across team members.

---

## Core Gameplay Terms

### Run
**Definition:** One complete attempt to escape the facility, from entering the first level to either exiting the final level (success) or exhausting the shared lives pool (failure).

**Context:** A run is the smallest temporal unit of Chrimera's progression. Each run is independent, though meta-progression unlocks carry between runs.

**Example:** "That was a great run; we made it to level 4 before losing all lives."

---

### Level
**Definition:** One continuous playable area within the facility, bounded by entry and exit triggers. Players must complete all levels in sequence to escape.

**Context:** Levels are the building blocks of a run. Each level increases threat density and contamination. Typically 3–5 levels per run.

**Synonyms:** Stage, Sector, Zone (facility-specific), Segment.

**Example:** "Level 2 has a Spreader and more Crawlers than Level 1."

---

### Shared Lives Pool
**Definition:** A single, shared resource of "lives" available to all players in a cooperative run. When any player dies permanently (downed timer expires), the pool decrements by 1. When the pool reaches 0, the entire run fails.

**Context:** This mechanic enforces mutual dependency. A single player cannot hoard lives; the team must work together to survive.

**Default Value:** 2–3 lives per run (configurable, higher for cooperative play).

**Example:** "We had 3 lives. Two players died and revived twice, then on the third death, we had no lives left. Run failed."

---

### Downed
**Definition:** A temporary incapacitated state entered when a player's health reaches 0. A downed player is immobilized (semi-transparent, cannot move or act) but can be revived by a nearby teammate (within 2m, interaction held for 1s) within 8 seconds. If the revive timer expires, the player enters the Dead state and the shared lives pool decrements.

**Contrast with Dead:** Downed is reversible; Dead is permanent (until next run).

**Example:** "I'm downed! Revive me quickly!" (vs. "I'm dead; that's one life gone.")

---

### Dead
**Definition:** A permanent removal of a player from the current run. A player becomes Dead when:
1. Their downed timer expires (8 seconds without revive), OR
2. They are downed while the shared lives pool is already at 0.

When Dead, the player is removed from the level entirely (body despawns); they cannot respawn or rejoin until the next run starts.

**Context:** Death is final for the run. Unlike downed, there is no recovery mechanic.

**Example:** "All three of us got downed at once. Two revived, but one timed out and died. Lives: 2→1."

---

### Tool Slot
**Definition:** An inventory slot that holds one active Experimental Tool. A player has a default of 2 tool slots (upgradeable to 3 via meta-progression).

**Context:** Tools are swapped on pickup. A tool slot can be empty, occupied, on cooldown, or consumable (with charges remaining).

**Mechanics:**
- If both slots are full and a new tool is picked up, the player must choose to drop one tool or discard the new tool.
- Tools are NOT lost when a player dies (the tool respawns as a pickup at the death location).
- Tools do NOT persist between levels (leaving a level means abandoning held tools).

**Example:** "Slot 1 has Grapple Spike (ready), Slot 2 has Acidic Compound (2 charges left)."

---

### Experimental Tool
**Definition:** A discovered, single-use or cooldown-based utility item found during a run. Tools are not pre-selected; they are discovered as pickups during levels. Tools enable improvisation and playstyle adaptation.

**Types:**
- **Mobility:** Grapple Spike, Speed Serum, Lateral Thruster.
- **Offensive:** Acidic Compound, EMP Grenade, Sonic Emitter, Toxin Injector.
- **Defensive:** Barrier Foam, Stasis Gel, Med-Kit, Stabilization Serum.
- **Utility:** Scanner, Keycard Cracker, Contamination Filter.

**Base Properties:**
- **Name, Description, Icon.**
- **Tool Type** (Mobility, Offensive, Defensive, Utility).
- **Rarity** (Common, Uncommon, Rare, Elite).
- **Consumable or Cooldown-Based:** Consumable tools (e.g., Acidic Compound) have limited charges; cooldown-based tools (e.g., Scanner) recharge after use.

**Context:** The core novelty of Chrimera is that tools are improvised from pickups, not chosen beforehand. This forces players to adapt and creates variety.

**Example:** "I found a Stasis Gel; now I can freeze that Lurker while my teammate attacks."

---

### Contamination Zone
**Definition:** A localized area of biohazard created by a Spreader entity. It is a circular region (typically 3m radius) that persists for 20 seconds after the Spreader leaves. Any player inside a contamination zone takes 1 HP damage per second.

**Visuals:** Sickly green-blue overlay with particle effects and hissing audio.

**Mechanics:**
- Damage is continuous (1 HP/s), not per-frame; it accumulates predictably.
- Contamination zones can overlap; damage stacks.
- Zones persist even after the Spreader that created them is killed.
- Players can move through zones to reach resources or exits, at the cost of sustained damage.

**Context:** Contamination zones are environmental hazards that force players to make risk/reward decisions (take damage or find alternate routes).

**Example:** "The Spreader left a contamination zone blocking the exit. We have two choices: run through and take 10 HP of damage, or find the alternate path (which has more Crawlers)."

---

### Outbreak
**Definition:** The catastrophic failure of biohazard containment in the underground Area 51 facility. The outbreak refers to the uncontrolled spread of CRISPR-mutated entities throughout the complex.

**Setting Context:** The outbreak is the premise that drives the game's narrative and mechanics. Facility degradation, entity density escalation, and contamination spread are all results of the outbreak progressing.

**Not Gameplay:**The outbreak is a narrative/setting concept, not a directly-controlled game mechanic (though its visual/mechanical progression is visible).

**Example:** "The outbreak is spreading faster than we can escape; Level 3 has twice as many entities as Level 1."

---

### CRISPR Entity
**Definition:** Any hostile creature spawned by the CRISPR outbreak. These are mutated beings, some originally human, some entirely novel biological chimeras. All CRISPR entities are AI-driven enemies.

**Types (within MVP):**
- **Crawler:** Basic swarm threat.
- **Lurker:** Ambush predator.
- **(Post-MVP)** Spreader, Amalgam, Chimera Host, and others.

**Context:** CRISPR entities are the primary threat in Chrimera. Their escalating spawn rate, diversity, and behavior complexity drive the game's difficulty curve.

**Example:** "That Lurker is dangerous; it nearly one-shot me with an 8-damage burst."

---

### Chimera Host
**Definition:** An elite CRISPR entity that was originally a human scientist before mutation. Chimera Hosts are rare, unpredictable, and highly dangerous.

**Characteristics:**
- Medium-high health (40 HP).
- Intelligent, erratic behavior (blinks, projectile attacks, grab mechanic).
- Special loot drop (Rare-tier tool).
- **Meta-progression unlock:** Defeating a Chimera Host for the first time unlocks a special archetype or reward.

**Context:** Chimera Hosts are endgame threats that test mastery of tools and teamwork. They are rare (spawn late in runs, often in final levels).

**Example:** "The Chimera Host teleported behind us. I threw an EMP Grenade while my teammate revived the downed player."

---

### Archetype
**Definition:** A scientist class or specialization that grants passive bonuses and tool-specific enhancements. Archetypes are selected at run start and carry for the entire run.

**Available Archetypes (MVP):**
- **Virologist:** Biology specialist. Tool cooldowns -10%. Chemical/biological tools +15% damage.
- **Engineer:** Tech specialist. Electronic doors open -50% faster. Contamination zones -20% damage.

**Post-MVP Archetypes:**
- **Security:** Combat-trained. Melee damage +10. Sonic Emitter cooldown -3s.
- **Lab Director:** Leader. Nearby allies +15% speed, -10% cooldowns. Team bonuses.
- **Escape Artist:** Evasion specialist. Speed +15%. Slide cooldown -50%.

**Context:** Archetypes enable playstyle differentiation and reward meta-progression. Choosing an archetype is a strategic decision that affects tool effectiveness and survival strategy.

**Example:** "I unlocked Engineer, so now I can open locked doors instantly. That shortcut saves us 2 minutes per run."

---

### Meta-Progression
**Definition:** Permanent unlocks and statistics that persist across multiple runs. Meta-progression allows players to gradually unlock new archetypes, increase starting lives, and discover new tools.

**Examples:**
- Unlocking a new archetype after 50 total kills.
- Increasing starting lives from 2 to 3 after 3 completed runs.
- Adding a third tool slot after 100 kills.

**Context:** Meta-progression provides long-term progression goals and makes permadeath feel less punishing (losses still contribute to unlocks).

**Persistence:** Stored locally (user file) and synchronized via SteamManager cloud save (post-MVP).

**Example:** "I've now beaten 5 runs. I unlocked Engineer and increased my lives pool to 3. My next run will feel easier."

---

### Exit Trigger
**Definition:** An Area2D node placed at the end of a level that detects when all players have entered its bounds. Touching the exit trigger completes the level and advances to the next level (or run completion if final).

**Mechanics:**
- The exit is the only way to progress to the next level.
- All players must reach the exit (for multiplayer runs, or solo player for single-player).
- Upon exit, the level despawns; tools left behind are lost.

**Context:** The exit trigger is the win condition for a level and creates a spatial objective.

**Example:** "I see the exit glowing at the end of the corridor. Let's run for it before the Amalgam blocks our path."

---

### Escalation
**Definition:** The gradual increase in threat density, entity variety, and contamination spread as a run progresses. Escalation occurs both within a level (Exploration → Pressure → Crisis phases) and across levels (each level harder than the last).

**Mechanisms:**
- **Within-level escalation:** Entity spawn rate increases, new entity types unlock (Lurker at 60s, Spreader at 120s, etc.).
- **Cross-level escalation:** Level 1 has 8 entities, Level 3 has 18 entities, etc.
- **Difficulty scaling:** Total enemy count increases with player count and meta-progression (player experience).

**Context:** Escalation creates a pacing curve that starts calm and ends in crisis, mirroring the narrative of a failing containment.

**Example:** "At the start of Level 2, it was just Crawlers. By minute 2, Lurkers showed up. By minute 3, a Spreader appeared and we were in full Crisis mode."

---

### Cooperative Proximity
**Definition:** A mechanic that grants bonuses when players are within 3m (6 tiles) of each other:
- **Movement speed:** +10% (8.0 m/s → 8.8 m/s).
- **Tool cooldowns:** -10% (5s → 4.5s).
- **Downed timer extension:** +2s (8s → 10s revive window).

**Reverse Penalty:** If players exceed 15m separation, a visual warning (red vignette) appears and a soft pull activates (separated player gains +2 m/s toward group for 2s).

**Context:** This mechanic encourages teamwork and punishes lone-wolfing, fitting the cooperative escape narrative.

**Example:** "Stay close! When we're together, tool cooldowns are 10% faster. That Scanner recharge will be almost instant."

---

### Procedure
**Definition:** (In context of procedural generation) The process of selecting and arranging pre-authored level rooms using a deterministic seed to create variation while maintaining fairness.

**Contrast:** Chrimera does NOT randomly generate tilemap geometry. Instead, it selects from a pool of hand-crafted rooms and arranges them based on a seed.

**Example:** "This run's seed placed the Vault room before the Server room, so we faced more heavy entities early."

---

### Multiplayer Synchronization (Net Play)
**Definition:** The technical process of keeping game state consistent across all players in a cooperative session. Server-authoritative AI means the host runs all entity decision logic; clients receive position and action snapshots every 0.1 seconds.

**Snapshot:** A data packet containing entity position, velocity, animation state, and attack status.

**Context:** In Chrimera, all AI decisions are made on the host. Clients are followers, ensuring no desyncs or cheating.

**Example:** "The Lurker appears to be in the same position for both players because we receive snapshots every 0.1s."

---

## UI and Systems Terms

### Run Seed
**Definition:** A unique identifier (integer) that determines the procedural arrangement of a run: level order, entity spawn points, tool pickup locations, and contamination patterns.

**Scope:**
- **Standard runs:** Seed is generated per run (hash of time, player count, meta-progression state).
- **Daily challenges:** Seed is fixed per day (e.g., 20260315 for March 15, 2026) globally, allowing all players to compete on the same configuration.

**Example:** "Seed 12345 gave us lab_chamber → vault → server_room in that order."

---

### Difficulty Scaling
**Definition:** The automatic adjustment of entity spawn rates, speed, and damage based on:
- Player count (more players = harder difficulty).
- Player meta-progression experience (more runs completed = harder enemies).
- Difficulty setting selected (Normal, Hard, Challenge).

**Formula Example:**
```
entity_count = base_count * (1 + difficulty_modifier) * (1 + player_count_modifier)
```

**Context:** Scaling ensures runs remain challenging as players unlock more archetype bonuses.

**Example:** "In my 10th run, I noticed Crawlers were spawning faster than my first run. That's difficulty scaling based on my experience."

---

### Leaderboard
**Definition:** A persistent online ranking of player run statistics (time, kills, damage taken) shared globally via SteamManager. Daily challenges have a separate leaderboard reset every 24 hours.

**Context:** Leaderboards provide competitive motivation and social proof of skill.

**Example:** "I finished the daily challenge in 4:30 and I'm ranked #47 globally today."

---

## Technical Terms

### CharacterBody2D
**Definition:** Godot's 2D physics-driven character node. It includes built-in collision response, gravity simulation, and the `move_and_slide()` method for smooth platformer movement.

**Context:** PlayerCharacter and CRISPREntity both extend CharacterBody2D.

---

### LimboAI
**Definition:** A lightweight behavior tree framework for Godot used to drive NPC and entity AI. It uses a tree of nodes (Selector, Sequence, Condition, Task) to make decisions hierarchically.

**Context:** All CRISPR entity behavior is defined as LimboAI behavior trees, not imperative GDScript logic.

---

### Server-Authoritative
**Definition:** In multiplayer, the host (server) makes all authoritative decisions (entity behavior, state transitions, damage resolution). Clients receive snapshots but do not independently decide AI behavior.

**Contrast with Client-Side Prediction:** In Chrimera, all AI is server-side; clients are followers.

**Context:** This prevents cheating and desyncs in multiplayer.

---

### State Machine
**Definition:** A system that manages discrete game states (LOBBY, RUN_START, EXPLORING, LEVEL_EXIT, RUN_COMPLETE) and transitions between them based on conditions.

**Context:** Chrimera has a run-level state machine and a per-level state machine.

---

### TileMap
**Definition:** Godot's node for rendering a grid of repeated 2D tile images. Used for level terrain, platforms, walls, and decorative elements.

**Context:** All Chrimera levels are built using TileMap with a custom tileset.

---

## Narrative/Setting Terms

### Area 51 Underground Facility
**Definition:** The fictional location where Chrimera is set. A secret research complex conducting biological experiments, including CRISPR gene-editing research, located underground.

**Related:** Blacksite Breakout (another BurnBridgers game) shares the same setting but features different entities and storylines.

---

### CRISPR Outbreak
**Definition:** (See "Outbreak" above.) The narrative premise that uncontrolled CRISPR mutation has spread throughout the facility, creating chimeric entities and forcing scientists to escape.

---

### Scientist Player Role
**Definition:** The player character is one of the researchers trapped in the facility. Scientists are not soldiers; they rely on improvised tools and intelligence to escape rather than military weaponry.

**Context:** This role flavors the tool library (biological, technical, utility-focused) and the narrative tension (underdogs, not heroes).

---

## Design Philosophy Terms

### Roguelike Tension
**Definition:** The emotional experience of high-stakes decision-making in permadeath contexts. Each run feels important because failure is permanent (though meta-progression softens the blow).

**Context:** Chrimera aspires to create roguelike tension through escalating entity density and the shared lives pool.

---

### Tool Improvisation
**Definition:** The core novelty of Chrimera: players discover tools during runs rather than pre-selecting them. This forces adaptation and creates emergent playstyles.

**Contrast:** Traditional loadout systems (pick tools before run starts) remove the improvisation element.

---

### Cooperative Pressure
**Definition:** The emotional tension created by interdependency. When players share lives and must revive each other, success feels collaborative and failure feels mutual.

**Example:** "Knowing my teammate will lose a life if I die makes me play more carefully."

---

## Appendix: Related BurnBridgers Concepts

### GameManager
**Definition:** A shared autoload node managing cross-game systems (player pooling, pause state, SteamManager bridging, audio output).

**Scope in Chrimera:** Chrimera listens to GameManager signals but does not extend its behavior significantly.

---

### SteamManager
**Definition:** A Steamworks integration layer handling multiplayer networking, cloud saves, leaderboards, and achievements.

**Scope in Chrimera:** Chrimera uses SteamManager for multiplayer and meta-progression cloud sync (post-MVP).

---

### MusicManager
**Definition:** A dynamic music system that adjusts track intensity, speed, and tone based on game state (entity density, alert level, escalation phase).

**Scope in Chrimera:** MusicManager receives escalation events from RunController and adjusts music profile (intensity=1.20, speed=1.15, tone=1.08) accordingly.

---

## End of Glossary

This glossary should be referenced whenever ambiguity arises. Updates should be made if new terms are introduced or definitions require clarification.
