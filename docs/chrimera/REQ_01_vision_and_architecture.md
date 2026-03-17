# REQ-01: Vision and Architecture
**Chrimera: Bioforge Run**

## Overview
Chrimera is a 1–4 player cooperative side-scrolling roguelike set in Underground Area 51 during a catastrophic CRISPR outbreak. Players take the role of scientists trapped in a research complex with containment protocols failing. The core loop is *escape by completing consecutive levels while maintaining resource discipline and team cohesion*. Experimental tools must be improvised from found items; no loadouts exist pre-run.

**Core Identity:** *Scientists running for their lives through a CRISPR-contaminated black site.*

---

## Design Pillars

| Pillar | Description |
|--------|-------------|
| **Roguelike Tension** | Permadeath with meta-progression. Each run feels finite; escalating entity density forces pacing decisions. |
| **Cooperative Escape Pressure** | No individual respawn mid-level; shared lives pool creates mutual dependency. Downed players must be rescued or the run fails. |
| **Experimental Tool Improvisation** | Tools are discovered during runs, not pre-selected. Forced adaptation keeps playstyle dynamic and unpredictable. |
| **Horror-Adjacent Atmosphere** | Biological mutation, failing containment, facility decay. Dread without jump-scares; slow environmental storytelling. |
| **Escalating Threat Density** | Each level adds entity variety and spawn rate. Progression feels like the outbreak is *winning*. |

---

## Core Rules

### Run Completion
- **Sequence:** Players must complete levels in a fixed sequence (level 1 → level 2 → ... → level N) to escape.
- **No mid-level respawn:** Downed players cannot respawn until the level is exited (via recovery by teammates or failure).
- **Level exit:** Each level contains one mandatory exit trigger. Reaching it advances to the next level (or completes the run if final).

### Lives and Death
- **Shared lives pool:** All players share one pool of lives (default: 3 lives per run).
- **Downed state:** When a player loses health to zero, they enter the *Downed* state (revivable for ~8 seconds by teammate proximity interaction).
- **Death:** If revive timer expires or entire team is downed, the player is removed from the run (body despawns).
- **Run failure:** When all lives are exhausted, the run ends in failure. Meta-progression unlocks still apply.

### Threat Escalation
- **Per-level density:** Entity count and variety increase each level.
- **Entity spread:** Spreader-type entities leave contamination zones that persist and force area denial.
- **Environmental pressure:** Facility degradation is visual/audio only (not direct damage) but reinforces atmosphere.

### Tool System
- **Pickup-only:** Experimental tools are found during levels, never granted at run start.
- **Tool slots:** Players can hold 2 active tools and swap on new pickup.
- **Consumable vs. cooldown:** Tools are either consumable (single use, dropped from pickup) or cooldown-based (multi-use with recharge).
- **Synergy:** Some tools amplify when used in combination (e.g., stasis gel + teammate melee attack).

---

## Visual and Audio Tone

### Environment
- **Setting:** Underground brutalist concrete, sterile laboratory corridors, emergency lighting (red/amber flicker).
- **Progression:** Facility starts intact; each level shows deeper contamination (visual shader overlays, biological discoloration, structural compromise).
- **Lighting:** Hard shadows, maintenance lights, bio-luminescent contamination glow (unsettling blue-green).
- **Decay:** Cracked walls, failed containment seals, warning placards, data servers offline.

### Entity Presentation
- **Design:** CRISPR chimeras are grotesque but partially recognizable (humanoid base with biological mutations).
- **Animation:** Jerky, asymmetrical movement. Fast predators twitch; large ones lumber with weight.
- **Sound:** Wet, organic vocalizations; wet impacts; electrical discharge (for variants).

### Audio Profile
- **Music:** Intensity=1.20, Speed=1.15, Tone=1.08 (MusicManager profile). Urgent, driving, escalating with entity density.
- **Ambience:** Facility hum, distant dripping water, alarm chirps (periodic, not constant), contamination hiss.
- **Tool SFX:** Distinct audio per tool type (hiss for chemical, buzz for EMP, whoosh for mobility).

---

## Godot 2D Scene Architecture

### Core Scene Nodes
The game uses a hierarchical structure compatible with Godot 4 side-scroller best practices:

```
LevelSegment (Node2D) [root per level]
├─ TileMap (TileMap) [terrain, platform layout]
├─ Hazards (Node2D) [contamination zones, falling hazards]
│  └─ ContaminationZone (Area2D) [damage-over-time zone]
├─ Entities (Node2D) [CRISPR entities]
│  ├─ CRISPREntity (CharacterBody2D base) [Crawler, Lurker, etc.]
├─ Players (Node2D) [local player instances]
│  ├─ PlayerCharacter (CharacterBody2D)
│  │  ├─ CollisionShape2D [body hitbox]
│  │  ├─ Sprite2D [scientist model]
│  │  ├─ AnimationPlayer [walk, jump, slide, tool-use]
│  │  ├─ ToolSlotManager (Node) [holds active ExperimentalTool references]
│  │  └─ State [CharacterStateMachine or similar]
├─ Items (Node2D) [pickups]
│  ├─ ExperimentalToolPickup (Area2D)
│  ├─ PickupBase (Area2D) [consumables, ammo]
├─ Structures (Node2D)
│  ├─ ExitTrigger (Area2D) [level completion trigger]
│  ├─ SafeRoom (Area2D) [visual safe zone, brief respite]
└─ Effects (CanvasLayer) [VFX, screen-space overlays]
```

### Key Component Classes

| Class | Purpose | Base | Notes |
|-------|---------|------|-------|
| `PlayerCharacter` | 1P avatar, movement/action input | CharacterBody2D | Inherits from shared GameManager player base. |
| `CRISPREntity` | Enemy creature | CharacterBody2D | LimboAI behavior tree drives decision loop. |
| `ExperimentalTool` | Tool definition and behavior | Resource | Subclassed per tool type; instantiated into ToolSlotManager. |
| `ContaminationZone` | Hazard area | Area2D | Damage-over-time; visual shader overlay. |
| `ExitTrigger` | Level completion | Area2D | Signals level complete when all players enter. |
| `LevelSegment` | Encapsulates one playable area | Node2D | Procedurally instantiated or hand-crafted. |

---

## Scene Hierarchy Diagram

```
GameManager (autoload, shared infrastructure)
│
└─ ChimeraGame (Node) [run state machine, lives pool]
    ├─ Lobby (CanvasLayer) [main menu, ready UI]
    ├─ RunController (Node) [coordinates levels, escalation]
    │  └─ LevelSegment (Node2D) [current active level]
    │     ├─ TileMap
    │     ├─ Players
    │     │  ├─ PlayerCharacter (P1)
    │     │  ├─ PlayerCharacter (P2)
    │     │  └─ ...
    │     ├─ Entities
    │     │  ├─ CRISPREntity (Crawler_01)
    │     │  ├─ CRISPREntity (Lurker_01)
    │     │  └─ ...
    │     ├─ Items
    │     ├─ Hazards
    │     └─ Effects
    └─ UI (CanvasLayer) [run-level HUD, lives counter, cooldowns]
```

---

## Integration with Shared Infrastructure

- **GameManager:** Provides player instance pooling, SteamManager bridging, game state (is paused, run active, etc).
- **SteamManager:** Handles peer networking for cooperative multiplayer. ChimeraGame listens to peer_joined/disconnected signals.
- **LimboAI:** Drives all CRISPR entity decision-making. No GDScript logic trees; all behavior is tree-based.
- **MusicManager:** Receives escalation events (entity count, player alert state) and adjusts intensity/speed/tone in real-time.

---

## Design Constraints

1. **No respawn mid-level:** Players who die cannot re-enter until level exit.
2. **Permadeath by default:** Downed players who are not revived become dead permanently.
3. **Tool rarity:** No tool duplication (if one player picks up a tool, others see it as taken; fresh instances on next level).
4. **Facility is one-way:** No backtracking; forward progression only.
5. **All AI is server-authoritative** in multiplayer (RunController decides entity actions; clients receive snapshots).

---

## Next Steps
- **REQ-02:** Game state machine (run lifecycle, level transitions, death/down system).
- **REQ-03:** Player abilities and experimental tools (tool categories, mechanics, synergies).
- **REQ-04:** Player movement and controls (input map, physics, camera, cooperative bounds).
