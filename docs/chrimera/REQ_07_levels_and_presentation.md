# REQ-07: Levels and Presentation
**Chrimera: Bioforge Run**

## Overview
Chrimera levels are **tilemap-based 2D side-scrolling segments** with procedurally-varied room layouts and fixed critical paths. Each level has a distinct visual identity reflecting its function within the facility (lab, storage, server room, etc.). Contamination is visible as a spreading overlay, degrading the environment as the outbreak worsens.

---

## Level Structure

### Core Components

```
LevelSegment (Node2D per level instance)
├─ TileMap (TileMap) [terrain, platforms, walls]
├─ NavigationRegion2D (optional, for AI pathing)
├─ RoomContainer (Node2D) [logical room grouping]
│  ├─ Room_01 (Node2D)
│  │  ├─ Hazards (Area2D spawns contamination zones)
│  │  ├─ Entities (spawn points for AI)
│  │  ├─ Items (tool pickups, resources)
│  │  └─ Structures (doors, locks, non-collidable deco)
│  ├─ Room_02 (Node2D)
│  └─ Room_N (Node2D)
├─ ExitTrigger (Area2D) [level completion zone]
└─ Effects (CanvasLayer) [visual overlays, contamination shader]
```

### Room Types

| Type | Purpose | Layout | Entities | Loot |
|------|---------|--------|----------|------|
| **Corridor** | Path between rooms | Linear, narrow (4m wide, 8m long). Few platforms. | Crawlers, occasional Lurker | Common tools |
| **Lab Chamber** | Large open space | Wide (6m+), multi-level platforms. Terminal/desk deco. | Mixed (Crawlers, Spreader) | Uncommon tools, medical supplies |
| **Storage Vault** | Warehouse-like | Tall (4+ platforms), racks of shelving. | Heavy spawns (Amalgam, Crawlers) | Rare tools (high value) |
| **Server Room** | Electronic facility | Narrow aisles, tall servers. Electronic doors/locks. | Tech-heavy spawns (Lurkers, EMP-resistant) | Tech tools (Scanner, Keycard Cracker) |
| **Contamination Zone** | Hazard area | Small, toxic, bio-overgrown. Visual overlay heavy. | Spreaders | Rare loot (risk/reward) |
| **Safe Room** | Respite | Small, sealed, furniture. No entities. | None | Cosmetic items only |

---

## Procedural Variation System

### Fixed Critical Path
Each run's level sequence is seeded and deterministic, but room arrangement varies:

```
Level 1 (Research Lab A):
├─ [Fixed] Entrance Corridor
├─ [Fixed] Lab Chamber (contains exit)
└─ [Procedural] 2–3 branch rooms (optional shortcuts, extra loot)

Level 2 (Storage Vault B):
├─ [Fixed] Entrance Corridor
├─ [Procedural] 2–3 vault rooms (randomized platform layout)
└─ [Fixed] Exit Corridor

Level 3+ (Mixed):
├─ [Fixed] Entrance
├─ [Procedural] Room pool shuffled (lab, vault, server, corridor variants)
└─ [Fixed] Exit
```

### Procedural Room Generation
Rooms are not generated on-the-fly; rather, they are **selected from a pre-authored pool** and arranged using a seed:

```gdscript
class LevelGenerator:
    var run_seed: int
    var level_pool: Array[String] = [
        "res://scenes/game/chrimera/levels/lab_chamber_01.tscn",
        "res://scenes/game/chrimera/levels/lab_chamber_02.tscn",
        "res://scenes/game/chrimera/levels/vault_room_01.tscn",
        "res://scenes/game/chrimera/levels/server_room_01.tscn",
        "res://scenes/game/chrimera/levels/corridor_01.tscn",
        "res://scenes/game/chrimera/levels/corridor_02.tscn",
        "res://scenes/game/chrimera/levels/contamination_zone_01.tscn",
    ]

    func generate_level(level_number: int) -> LevelSegment:
        randomize_with_seed(run_seed + level_number)

        var room_sequence = []
        var fixed_entry = level_pool[0]
        var fixed_exit = level_pool[1]

        room_sequence.append(load(fixed_entry))

        # Add 2–3 procedural rooms
        var procedural_count = randi_range(2, 3)
        for i in range(procedural_count):
            var room_idx = randi_range(2, level_pool.size() - 1)
            room_sequence.append(load(level_pool[room_idx]))

        room_sequence.append(load(fixed_exit))

        # Instantiate and connect
        var level = LevelSegment.new()
        for room_path in room_sequence:
            level.add_room(room_path)

        return level
```

---

## Visual Presentation

### Environment Aesthetic

#### Level 1–2: Intact Facility
- **Palette:** Grays (concrete, steel), white (lab), blues (emergency lighting).
- **Lighting:** Hard shadows, overhead fluorescents (flicker occasionally).
- **Textures:** Clean tile floors, smooth walls, intact equipment.
- **Deco:** Shelving, workstations, terminals (non-interactive), locked doors, warning signs.

#### Level 3–4: Degrading Facility
- **Palette:** Grays + browns (rust, oxidation), reds (alarms), sickly greens (contamination glow).
- **Lighting:** Failing fluorescents (strobing), red emergency lights on full-time.
- **Textures:** Cracks in concrete, corroded metal, broken equipment, exposed wiring.
- **Deco:** Collapsed shelving, overturned furniture, biological growths, warning placards torn.

#### Final Level: Critical Contamination
- **Palette:** Dominated by sickly blues and greens, blacks (void contamination).
- **Lighting:** Mostly red emergency lights + bio-luminescent glow.
- **Textures:** Heavy decay, biological overgrowth, structural compromise visible.
- **Deco:** Severe hazard markings, containment seals failed, biomass spreading.

### Contamination Visual Overlay

Contamination is rendered as a **shader-based overlay** that increases in opacity per level:

```glsl
// Fragment shader for contamination overlay (CanvasLayer)
shader_type canvas_item;

uniform float contamination_level: hint_range(0.0, 1.0) = 0.0;
uniform sampler2D noise_texture: hint_default_white;
uniform vec3 contamination_color = vec3(0.2, 0.8, 0.3);  // sickly green

void fragment() {
    vec4 screen_sample = SCREEN_TEXTURE;
    vec4 noise_sample = texture(noise_texture, UV + TIME * 0.1);

    // Blend contamination color with screen
    vec3 contaminated = mix(
        screen_sample.rgb,
        contamination_color,
        contamination_level * 0.3
    );

    // Add noise turbulence
    contaminated += (noise_sample.rgb - 0.5) * contamination_level * 0.1;

    // Vignette effect at high contamination
    float vignette = 1.0 - (contamination_level * 0.4);
    contaminated *= vignette;

    COLOR = vec4(contaminated, screen_sample.a);
}
```

### Contamination Zone Visual
When a Spreader entity contaminates an area, a local 3m-radius overlay appears:

```
[Contamination Zone]
├─ Area2D (collision shape: CircleShape2D radius 3m)
├─ Shader (radial gradient, sickly green-blue)
├─ ParticleEffect2D (slow-moving spore particles)
└─ AudioStreamPlayer2D (wet hissing SFX)
```

---

## HUD and Screen Layout

### Run-Level HUD

```
┌─────────────────────────────────────────────────────────────┐
│  Lives: ❤️  ❤️  ❤️     Level 2 / 4     Contamination: ███░░░░░ 35%  │
├─────────────────────────────────────────────────────────────┤
│  Slot 1: [Grapple Spike] ─────── Ready                      │
│  Slot 2: [Speed Serum] ░░░░░░░░ (6.2s cooldown)            │
│                                                             │
│  [P1] PlayerName: ❤❤❤❤ HP  [P2] PlayerName: ❤❤❤ HP       │
│                                                             │
│  [↓ EXIT THIS WAY] ────────────────────→ [100m to exit]     │
└─────────────────────────────────────────────────────────────┘
```

### HUD Elements

| Element | Position | Function |
|---------|----------|----------|
| **Lives Pool** | Top-left | Shows remaining shared lives as hearts. Red flash at ≤1. |
| **Level Counter** | Top-center | "Level 2/4" — current and total levels. |
| **Contamination Meter** | Top-right | Percentage and bar. Increases per level and Spreader activity. |
| **Tool Slots** | Left side | Icon + cooldown radial. Red overlay if consumable is empty. |
| **Player Status Bars** | Bottom-left | HP and name for each active player. Color-coded (red=critical, yellow=hurt). |
| **Exit Direction Indicator** | Bottom-right | Arrow pointing toward level exit + distance in meters. Hidden until exit found. |

### Cosmetic HUD Elements
- **Health numbers:** Optional, toggleable.
- **Damage pop-ups:** "+8 DMG" float up from hits (cosmetic only).
- **Threat indicator:** Pulsing red border when entity within 3m.

---

## VFX and Particle Effects

### Tool VFX

| Tool | Effect |
|------|--------|
| **Grapple Spike** | Blue electrical arc tracing cable path. |
| **Speed Serum** | Green aura around player for 8s. Motion blur trails. |
| **Lateral Thruster** | Orange jet trails, wind effect around player. |
| **Acidic Compound** | Yellow-green liquid arc. Puddle on impact + corroding animation. |
| **EMP Grenade** | Blue/white shockwave burst. All lights flicker. Electronic hum SFX. |
| **Sonic Emitter** | Concentric circular shockwave (purple). Sound wave visualization. |
| **Barrier Foam** | White/gray foam expands quickly, solidifies. Particle spray on creation. |
| **Stasis Gel** | Cyan sphere expands, freezes affected entities in place. |
| **Stabilization Serum** | Blue shield shimmer around player for 15s. |

### Entity VFX

| Entity | Effect |
|--------|--------|
| **Crawler (death)** | Biological matter burst outward (splatter). Brief glow fadeout. |
| **Lurker (ambush telegraph)** | Eyes glow bright red. Visible sound waves emanate outward. |
| **Spreader (contamination)** | Green-blue mist trails from body. Droplet particles. |
| **Amalgam (attack)** | Heavy impact dust cloud. Screen slight knockback shake. |
| **Chimera Host (blink)** | Teleport flash (white burst at start + arrival point). |
| **Chimera Host (projectile vomit)** | Acid spit arc + sizzle on impact. |

### Environmental VFX

- **Facility decay:** Cracks spread visually over time (non-interactive, aesthetic).
- **Alarms:** Red light pulsing at level entry during escalation.
- **Emergency sprinklers:** Water spray in safe rooms (no collision, visual only).
- **Bio-growth:** Spreading vines/tendrils on walls (escalating per level, mostly static deco).

---

## Audio Integration

### Music Profile (MusicManager)
```gdscript
# Per level, escalation adjusts real-time:
var music_profile = {
    "intensity": 1.20,     # urgency level
    "speed": 1.15,         # tempo modifier
    "tone": 1.08,          # harmonic intensity
}

# Per-phase adjustment (within level):
# Phase 1 (Exploration): base profile
# Phase 2 (Pressure): intensity += 0.2, speed += 0.05
# Phase 3 (Crisis): intensity += 0.4, speed += 0.1
```

### Ambience Layer
- **Facility hum:** Low-frequency oscillating tone (99 Hz loop).
- **Distant dripping:** Random water drops (every 3–8s).
- **Alarm chirps:** Every 20s, brief high-pitched beep (non-threatening context).
- **Contamination hiss:** Quiet, continuous white noise when contamination > 30%.

### Entity SFX

| Entity | Sounds |
|--------|--------|
| **Crawler** | Low growl (idle), hiss (alert), wet impact (melee), death shriek (quick). |
| **Lurker** | Wet breathing (idle), eerie moan (ambush telegraph), high-pitched shriek (attack). |
| **Spreader** | Constant oozing/dripping, wet splatter on ground, hiss (attack). |
| **Amalgam** | Deep rumbling (movement), heavy thud (attack), crunch (death). |
| **Chimera Host** | Human-like groaning (distorted), electric zap (blink), wet retch (projectile). |

### Tool SFX

- **Grapple Spike:** Metallic zip sound (cable retracting), impact dink.
- **Speed Serum:** Chemical injection hiss, body swoosh (speed audio effect).
- **EMP Grenade:** Electronic warble (charging), harsh buzz (detonation), electrical zap.
- **Sonic Emitter:** Rising tone, sharp pulse burst, vibration hum.
- **Acidic Compound:** Liquid splatter, sizzling burn, corrosion crackle.

---

## Camera Effects

### Screen Shake
Applied on certain events:

| Event | Intensity | Duration |
|-------|-----------|----------|
| **Player hit (minor)** | 0.2 | 0.1s |
| **Amalgam attack** | 0.5 | 0.2s |
| **EMP Grenade detonate** | 0.8 | 0.3s |
| **Contamination zone expand** | 0.3 | 0.15s |

---

## MVP Level Implementation

For MVP, use **one hand-crafted level** (research lab segment) with:
- Entry corridor (3 Crawlers intro)
- Central chamber (1 Lurker, tool pickups)
- Exit corridor (final Crawler wave)
- Total playable area: ~12m × 8m
- Estimated playtime: 3–5 minutes solo, 2–3 minutes with 2 players

### MVP Level Structure (Pseudocode)
```gdscript
# res://scenes/game/chrimera/levels/mvp_research_lab.tscn
LevelSegment
├─ TileMap
│  ├─ Platform_1 (ground floor, 0–6m)
│  ├─ Platform_2 (elevated, 6–10m)
│  └─ Corridor_Exit (sloped up, 10–12m)
├─ RoomContainer
│  ├─ Room_Entry (4m wide, 2 Crawler spawns)
│  ├─ Room_Main (8m wide, 1 Lurker, 3 tool pickups, 4 Crawler spawns)
│  └─ Room_Exit (3m wide, 1m exit door)
└─ ExitTrigger (Area2D at room_exit end)
```

---

## Testing Checkpoints

- [ ] Tilemap renders correctly; collision works (players can walk, jump off platforms).
- [ ] Contamination overlay shader applies and increases opacity per level.
- [ ] HUD displays lives, tool cooldowns, contamination level, exit direction.
- [ ] Entity death SFX plays; bodies disappear after 2s.
- [ ] Tool VFX visible and matches description (grapple arc, EMP burst, etc.).
- [ ] Music intensity increases during Crisis phase (audible tempo/intensity change).
- [ ] Facility ambience (hum, drips) plays and loops correctly.
- [ ] Screen shake applies on impacts (Amalgam, EMP, etc.).
- [ ] MVP level plays through in ~5 minutes with intended difficulty curve.

---

## Implementation Notes

1. **TileMap:** Use Godot's TileMap node with a custom tileset (16px or 32px per tile). Layer collision shapes in TileMap via physics layer.
2. **CanvasLayer for Overlays:** All contamination/HUD overlays go on CanvasLayer nodes with z_index above gameplay layers.
3. **Shader Compilation:** Test contamination shader on target platforms (some devices may have limited shader support).
4. **Audio Streaming:** Ambience tracks (hum, drips) should be **Ogg Vorbis** files loaded as AudioStreamPlayer2D or AudioStreamPlayer.
5. **Room Pooling:** For MVP, hand-author 3–5 room scenes. Post-MVP, expand pool to 15+ variants.

---

## Next Steps
- **REQ-08:** MVP build plan (phased development, testing checkpoints).
- **REQ-09:** Domain glossary (precise definitions for all key terms).
