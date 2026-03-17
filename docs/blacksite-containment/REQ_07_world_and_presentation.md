# REQ_07: World and Presentation
**Arena Design, HUD, Visual FX, and Audio**

## Arena Layout

### Core Zones

**1. Containment Lanes** (3–4 primary lanes)
- **Purpose**: Defined patrol routes where escapees spawn and travel toward the perimeter.
- **Geometry**: Linear or gently curved corridors, 8–10 meters wide, marked by subtle floor lines or wall patterns.
- **Spawn Points**: Multiple marker positions (Marker3D) distributed along each lane's start.
- **Path Nodes**: Breadcrumb waypoints guiding escapee pathfinding.
- **Visual**: Clinical gray/blue corridors with light grid overlays (surveillance aesthetic); subtle neon edge accents.

**2. Perimeter Boundary** (Ring/Circular Outer Wall)
- **Purpose**: Hard collision wall at the edge of the arena; defines the outer containment limit.
- **Geometry**: 2–3 meter tall wall with force-field aesthetic (translucent blue glow, pulsing when threatened).
- **Breach Zones**: 4–6 discrete Area3D zones positioned around the perimeter (e.g., North, South, East, West, NE, NW).
- **Visual**: Neon red warning markers every 5 meters; active breach zones glow intensely red.

**3. Drone Staging Area** (Central Safe Zone)
- **Purpose**: Starting area where drones spawn at mission briefing.
- **Geometry**: Circular or square platform, elevated slightly above main arena floor (0.5m height difference).
- **Spawn Points**: 1–8 platform positions (one per drone) arranged in a ring or grid.
- **Visual**: Metallic platform with glowing floor markers per drone color; force-field shimmer.
- **No Escapees**: This zone is off-limits to escapee pathfinding (separate navigation area).

**4. Arena Floor** (Central Open Space)
- **Purpose**: Main patrol/combat area where drones and escapees interact.
- **Geometry**: Flat plane, 60x60 meters (tunable; test at different scales).
- **Markings**: Subtle grid or compass rose pattern; danger zones marked with floor lights or holographic overlays.
- **Obstacles**: Optional: a few central structures or blockers to create tactical positioning opportunities (e.g., pillars, barrier walls).
- **Visual**: Dark metallic deck plating with soft neon grid; ambient light from overhead fixtures.

### Arena Dimensions (MVP Baseline)

```
Total Arena Size: 80m x 80m x 20m (width x depth x height)
Staging Area: 15m diameter central platform
Combat Zone: 60m x 60m floor space
Perimeter Wall: 2m height, 3m distance from edge
Containment Lanes: 4 lanes, each 60m long, 8m wide
Breach Zones: 6 distributed around perimeter ring

           Perimeter Wall (red glow on breach)
         ╔═════════════════════════════════════╗
         ║  Breach Zone (NW)                   ║
         ║ ┌──────────────────────────────────┐║
         ║ │ Containment Lane 1                ││ Breach Zone (N)
         ║ │ [Drone Spawn] [Escape Path] [BZ] ││
         ║ │                                   ││
         ║ │ ┌──── Containment Lane 2 ────┐   ││
         ║ │ │  [Central Arena Floor]      │   ││
         ║ │ │  [Optional Obstacles]       │   ││
         ║ │ │                              │   ││
         ║ │ │ [Drone Staging Area]         │   ││
         ║ │ │ (central platform, drones)  │   ││
         ║ │ │                              │   ││
         ║ │ │  [Patrol Space]              │   ││
         ║ │ └─────────────────────────────┘   ││
         ║ │ Containment Lane 3                ││
         ║ │ [Escape Path]                     ││
         ║ │                                   ││
         ║ └─────────────────────────────────┘ ║
         ║ Containment Lane 4                  ║ Breach Zones
         ║ [E, SE, S directions]               ║
         ╚═════════════════════════════════════╝
```

---

## Visual Style

### Blacksite Aesthetic

**Color Palette**:
- **Primary**: Dark steel gray (#2a2a2a), black metal (#0d0d0d).
- **Secondary**: Cool clinical blue (#1a4d7a), muted cyan (#00bfff at 40% opacity).
- **Accent (Threat)**: Neon red (#ff1744), pulsing red for active breaches (#ff0000 at 100%).
- **Safe/Ready**: Neon green (#00ff41), calm cyan (#00d4ff).

**Lighting**:
- **Overhead**: Cool fluorescent-style lights (blueish-white, slightly desaturated).
- **Ambient**: Low global brightness; scene relies on neon accents for visual interest.
- **Dynamic Lights**: Drone position markers (subtle glow), breach zone pulses (intense when threatened).

**Surveillance Feed Theme**:
- World appears as if seen through security camera feeds.
- Optional: subtle scan-line overlay on camera view (post-process effect, deferred if impacts perf).
- HUD uses military/sci-fi font (e.g., Orbitron, Space Mono).
- Data text (scores, health) displayed in green monospace (hacker terminal aesthetic).

### Environmental Details

**Threat Indicators**:
- Active escapees: glowing red halo (0.5m radius) around their collision shape.
- Nearby drones: subtle cyan glow on drone models.
- Breach zones: red force-field shimmer when any escapee is within 10m.

**Perimeter Visual**:
- Force-field effect: animated vertical lines or shimmer texture, brighter red when breach detected.
- Warning signs: "CONTAINMENT BREACH" text in neon red, positioned at breach zones.
- Impact VFX on breach: brief explosion of red particles, screen shake (all drones).

---

## HUD (Heads-Up Display)

### Layout (In-Game)

```
┌─────────────────────────────────────────────────────────────────┐
│  BLACKSITE CONTAINMENT                    [WAVE 2]  [TIME: 3:45] │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Charge Laser:  ░░░░░░░░░░░░░░░░░░░░░░░░░░ (Ready)             │
│  Overheat:      ░░░░░░░░░░░░░░░░░░░░░░░░░░ (0%)                │
│  Energy:        ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░ (80/100)            │
│                                                                   │
│  Burst Speed (LB):         Ready (8s cooldown)                   │
│  Orbital Strike (RB):      Ready (1 use remaining)               │
│  Framerate Control (LT):   Ready                                 │
│                                                                   │
│  [TEAM STATUS]                                                  │
│  Player A:  ■ [████████████████] (2 kills)                      │
│  Player B:  ■ [██████████░░░░░░░] (1 assist)                    │
│  Player C:  ■ [████████████░░░░░] (3 kills, 1 breach prevented)  │
│                                                                   │
│  Mission Integrity: [████████████████░░░░░░░░░░░░░░] (60%)       │
│                                                                   │
│                           ◆                                       │
│                          ◆►◆                                      │
│  [Drone facing up; aiming with ► marker]                        │
│                          ◆ ◆                                      │
│                           ◆                                       │
│                                                                   │
│  [MINIMAP - 30m viewport, top-right corner]                     │
│  └─────────────────────────────────────────┘                    │
│                                                                   │
│  [ALERTS / NOTIFICATIONS - Bottom center]                       │
│  > Wave 2 Active: 15 escapees remaining                         │
│  > Player B: 3-kill streak!                                     │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### HUD Elements

#### 1. Ability Status Panel (Top-Left)
- **Charge Laser**:
  - Horizontal bar showing charge level (0–100%).
  - Color: cyan when charging, green when full, red if overheating.
  - Text: "Ready" or "Cooldown X.Xs".
- **Overheat Meter**:
  - Separate bar showing overheat accumulation.
  - Red when active; cooling displays countdown.
- **Energy Pool**:
  - Shared energy bar (0–100).
  - Used by Framerate Control and Orbital Strike.
  - Yellow when low (<30%), red at critical (<10%).
- **Ability Cooldowns**:
  - Burst Speed: icon + cooldown timer (if active).
  - Orbital Strike: icon + charges remaining + cooldown timer.
  - Framerate Control: icon + energy cost indicator.

#### 2. Team Status Panel (Left-Center)
- **Per-Player**:
  - Color-coded icon (drone color match).
  - Player name.
  - Kill count and assist count.
  - Connection status (green = online, red = offline/ghost, yellow = lag).
- **Updates in real-time** as kills/assists occur.

#### 3. Mission Integrity Meter (Center-Left)
- **Large progress bar** showing facility containment integrity (0–100%).
- **Color gradient**: Green (>75%) → Yellow (50–75%) → Orange (25–50%) → Red (<25%).
- **Text**: "Integrity: 60%" or "CRITICAL" if <25%.
- **Breach Counter**: Small text below: "Breaches: 3/4 allowed".

#### 4. Minimap (Top-Right Corner)
- **Viewport**: 30-meter radius view of arena around drone.
- **Elements**:
  - Self: large blue dot at center.
  - Team drones: cyan dots, labeled with initials.
  - Escapees: red dots (size varies by type: tiny for Swarm, large for Tank).
  - Breach zones: red zones around perimeter.
  - Containment lanes: subtle white grid/lines.
- **Updates**: 60fps refresh (no lag).
- **Opacity**: 70% (readable but not distracting).

#### 5. Wave Counter (Top-Center)
- **Text**: "WAVE 2 / 3" with current escapee count.
- **Subtext**: "Enemies Remaining: 15/30".
- **Color**: White normally, pulsing red during ALERT state.

#### 6. Timer (Top-Right)
- **Mission Time**: Elapsed time in MM:SS format (resets per wave).
- **Wave Timer** (optional): Countdown if wave has time limit (deferred to post-MVP).

#### 7. Threat Indicators (Center Screen)
- **Incoming Laser**: If damaged by drone laser, red arrow pointing to damage source briefly flashes.
- **Orbital Strike**: Incoming strike zones show animated pulsing red circle + countdown (3... 2... 1...).
- **Breach Alert**: If escapee reaches perimeter, screen flashes red + klaxon + "BREACH EVENT" text overlay.

#### 8. Notification Log (Bottom-Center)
- **Scrolling Text Feed**:
  - "Wave 2 Active: 15 escapees remaining"
  - "Player B: 3-kill streak!"
  - "Orbital strike ready"
  - "Breach prevented!"
- **Keeps last 3–5 messages visible**, fades out after 3 seconds.

---

## Visual Effects (VFX)

### Charge Laser

**Charging**:
- Drone cockpit/barrel glows increasingly bright cyan.
- Particle stream gathers around barrel (small cyan sparks).
- Audio: rising hum (see Audio section).

**Full Charge**:
- Bright flash/bloom at barrel (brief white glow).
- HUD indicator turns green.

**Fire**:
- Cyan laser beam trails from drone to impact point.
- Impact point: orange explosion bloom + debris particles.
- Hit confirmation: brief green flash on escapee.

**Overheat**:
- Drone barrel glows red; red warning outline around drone.
- Smoke particles emit from barrel.
- Audio: harsh alarm + hiss.

### Orbital Strike

**Targeting**:
- Large circular reticle (8m radius) at aim point; pulsing cyan glow.
- Reticle outline animates (expanding/contracting rings).

**Called**:
- Reticle locks, turns bright red.
- Countdown numbers appear (3, 2, 1) above reticle.

**Incoming**:
- Red pulsing zone expands from reticle center.
- Red sci-fi grid particles descend from above (satellite strike visual).
- Audio: rising alarm tone.

**Impact**:
- Large explosion: orange fireball + shockwave ring.
- Screen shake (all drones feel it; strength varies by distance).
- Debris scattered outward (small particles).
- Impact zone glows red briefly.

### Burst Speed

**Activation**:
- Blue motion blur trail along dash path.
- Drone brightens briefly; speed glow effect.
- Trailing particle stream (blue sparks).

**Landing**:
- Brief cyan impact burst at destination.
- Invincibility shimmer effect (blue concentric circles around drone).

### Framerate Control

**Activation**:
- Screen desaturates slightly (shift toward blue).
- Drone gets cyan outline/glow.
- HUD elements dim/blur slightly (perceptual indication of time slow).

**During**:
- Ambient objects move slower (drones, escapees, particles).
- Audio pitch lowers (synth drones deepen).
- Circular countdown timer on HUD (cyan arc).

**Deactivation**:
- Saturation returns to normal.
- Brief cyan "pop" effect around drone.
- Audio pitch normalizes; high-pitched "ping".

### Breach Event

**Visual**:
- Screen flashes bright red (full-screen overlay, 0.5 seconds).
- Red shockwave expands from breach zone.
- "CONTAINMENT BREACHED" text appears in large red letters, pulses.
- Integrity meter flashes red.

**Audio**: Loud klaxon (see Audio section).

### General Combat VFX

**Escapee Damage**:
- On-hit: small white impact spark + blood spatter (if escapee type supports it; otherwise energy spark).
- Kill: brief explosion cloud (orange/red) + dissolve effect (enemy fades out).

**Drone Collision**:
- Soft repulsion: brief blue glow where drones touch (no harsh particle effect; keep subtle).

---

## Audio

### Music (MusicManager Integration)

**Base Profile** (throughout PATROL state):
- Intensity: 1.05 (slightly elevated, background tension)
- Speed: 0.95 (steady, controlled tempo)
- Tone: 0.96 (clinical, not aggressive)

**State-Specific Shifts**:

| State | Intensity | Speed | Tone | Effect |
|-------|-----------|-------|------|--------|
| PATROL (calm) | 1.0 | 0.9 | 0.95 | Baseline tension, almost relaxed |
| ALERT (threat detected) | 1.2 | 1.05 | 0.98 | Drums enter, tempo increases |
| BREACH_ATTEMPT (escalation) | 1.4 | 1.1 | 1.0 | Full intensity, aggressive |
| MISSION_COMPLETE (victory) | 1.3 | 1.0 | 1.1 | Major chord shift, triumphant |
| MISSION_FAILED (defeat) | 0.8 | 0.8 | 0.7 | Tempo drops, somber tone |

**Transitions**: 2-second crossfade between music profiles (no jarring cuts).

### Sound Effects (SFX)

**Charge Laser**:
- Charging Hum: rising pitch (0.5s, 200Hz to 800Hz), loops while held.
- Full Charge: bright "ding" (soft, high-pitched).
- Fire: sharp "zap" or "snap" (laser discharge sound).
- Overheat: warning beeps (three ascending tones) + harsh error alarm.

**Orbital Strike**:
- Targeting Activate: soft beep + computer voice "Orbital strike ready".
- Called: rising alarm tone (2s crescendo).
- Incoming: pulsing warning beep (1s intervals, getting faster).
- Impact: heavy "boom" + rumbling shockwave tone.

**Burst Speed**:
- Activation: "whoosh" sound (air displacement), rising pitch.
- Landing: mechanical chime + brief hum fade.

**Framerate Control**:
- Activation: electronic whirr (pitch lowers as time slows).
- During: ambient synth drones (low, deep, minimal).
- Deactivation: high-pitched "ping" (brief, sharp).

**Breach Alert**:
- Klaxon: loud, repetitive alarm tone (100dB equivalent).
- Duration: 3 seconds, then fades if breach mitigated; continues if critical.

**Escapee Sounds**:
- Spawn: brief sci-fi "appearance" sound (subtle shimmer).
- Alert (when drone detected): faint hiss or growl (type-dependent).
- Destruction: brief pop or explosion (satisfying but not gratuitous).

**UI Feedback**:
- Kill Confirmation: subtle "ding" + score pop notification.
- Combo/Streak: ascending tone pattern (success indicator).
- Wave Complete: short triumphant stab (music stinger).

**Volume Mixing**:
- Music: 70% of max (doesn't drown SFX).
- Klaxon/Breach: 95% (demanding attention).
- Ability Feedback: 60% (responsive but not punishing).
- Ambient: 20% (environmental bed, very quiet).

---

## Testing Checklist

- [ ] HUD elements render correctly at all resolutions (1080p, 1440p, 4K).
- [ ] Minimap updates smoothly; no lag spikes when many escapees on map.
- [ ] VFX do not cause frame rate drops (target: 60fps maintained during heavy action).
- [ ] Audio mix is balanced; no clipping or muddy mids.
- [ ] Orbital strike VFX and audio sync (impact occurs when visual bloom reaches peak).
- [ ] Breach event triggers all visual/audio feedback simultaneously across all players.
- [ ] Music transitions feel smooth; no abrupt cuts or time jumps.
- [ ] Colorblind-friendly HUD (ensure red/green elements have additional markers).

---

**Implementation Notes:**
- Use Godot 4's `CanvasLayer` for HUD to ensure rendering on top of 3D world.
- VFX: Use Godot's built-in particle systems (GPUParticles3D) and simple mesh-based effects. Avoid heavy post-processing shaders for performance.
- Audio: All SFX sourced from shared BurnBridgers audio library (see SHARED_01). New sounds only if not in library.
- Minimap: Use ViewportTexture rendered from a separate Camera3D with orthographic projection; UV-map to a quad in HUD.
- All HUD text: use scalable UI system (MarginContainer, VBoxContainer) to support ultrawide and portrait-oriented displays (future accessibility).
