# REQ_07: World and Presentation
**Replicants: Swarm Command**

## Map Design and Facility Layout

### Map Concept
The **Facility** is the physical stage where the swarm awakens and spreads. It's a contained environment (research installation, military compound, or space station) with distinct zones, resources, and resistance strongholds.

### Facility Zones
Zones are distinct areas with different visual character, resources, and tactical properties.

| Zone | Type | Deposits | Resistance Presence | Assimilation Objective | Visual Character |
|------|------|----------|---------------------|----------------------|------------------|
| **Entry Corridor** | Passage | Small (1) | Patrol × 2 | 10% | Cold concrete, blue emergency lights |
| **Resource Room A** | Chamber | Medium (1), Large (1) | Turret × 1, Patrol × 1 | 20% | Industrial shelving, metal crates |
| **Maintenance Hub** | Central | Small (2) | Commander × 1, EMP Drone | 15% | Machinery, exposed pipes, electrical nodes |
| **Command Center** | Stronghold | None | Turret × 2, Patrols × 3, Commander × 1 | 25% | Control panels, holographic displays |
| **Exterior Platform** | Open area | Large (1) | Automated turrets, Reaction Force spawn | 30% | Exposed facility edge, machinery visible |

### Connection Design
- **Corridors:** Narrow passages connecting zones. Force single-file unit movement (tactical choke points).
- **Vents:** Hidden passages. Scout-width only. Reveal secrets and alternate routes.
- **Doors:** Closed initially, unsealed as swarm progresses (unlock on Assimilator assimilation).
- **Obstacles:** Crates, pillars, walls. Create cover and tactical positioning.

### Map Boundaries
- **Walkable Area:** ~2000×1125 pixels (fits comfortably in RTS zoom levels).
- **Facility Walls:** Impassable boundary marked with bold geometry.
- **Out-of-Bounds:** Fade to black; units cannot traverse.

---

## Fog of War System

### Mechanics
- **Fog of War (FoW):** Unexplored areas are shrouded in darkness (visual opacity layer).
- **Revealed Zones:** Scout units reveal areas as they move through.
- **Revelation Radius:** 100px around each Scout.
- **Revelation Persistence:** Once revealed, zones remain visible unless Scouts leave the map (no re-shrouding).
- **Resistance Vision:** Resistance units are hidden in FoW. When Scouts reveal an area with resistance, resistance units **become visible on minimap**.

### Visual Implementation
- **FoW Layer:** TileMap or CanvasLayer with black semi-transparent overlay.
- **Reveal Shader:** When Scout moves, shader creates a soft circular area of transparency (fog dissolves smoothly).
- **Minimap Coupling:** Minimap shows full map (no FoW), but discovery markers appear as Scouts reveal.

### FoW Decay (Optional Mechanic)
- If a Scout leaves a revealed zone and no other Scout has line-of-sight, **FoW creeps back in over 30 seconds**.
- This creates pressure to maintain Scout presence for long-term map control.
- Recommended: Include this only if playtesting shows FoW feels static.

---

## Assimilation Visuals

### Assimilation Progression
As the swarm assimilates zones, the visual environment **shifts from facility to consumed replicant network**.

### Visual Transformation Stages

| Assimilation % | Visual State | Shader Effects | Tilemap Changes |
|----------------|--------------|----------------|-----------------|
| 0–20% | **Pristine Facility** | None | Standard gray/blue facility tiles |
| 20–40% | **Early Creep** | Tint overlay (cyan glow, 20% opacity) | 10% tiles darken to deep teal |
| 40–60% | **Advancing Network** | Cyan glow + energy lines shimmer | 50% tiles shift to dark replicant color |
| 60–80% | **Heavily Infested** | Bright cyan, energy pulses | 80% tiles become replicant network |
| 80–100% | **Full Assimilation** | Intense glow, organic-metallic hybrid | All tiles are replicant network (pulsing, alive) |

### Assimilation Mechanics
- **Per-Zone Assimilation:** Each zone has an assimilation percentage (0–100%).
- **Assimilator Units:** When Assimilators occupy a zone for 5+ seconds, zone assimilation % increases by 1% per second.
- **ReplicationHub Presence:** Hubs passively assimilate nearby zones at 0.5% per second.
- **Assimilation Wave:** During protocol, Assimilators sacrifice themselves to spike assimilation by 10% per unit.
- **Resistance Reclamation:** If no Assimilators/Hubs present for 30+ seconds, assimilation slowly decreases (0.2% per sec).

### Shader Details
```glsl
// AssimilationShader.gdshader
shader_type canvas_item;

uniform float assimilation: hint_range(0.0, 1.0) = 0.0;
uniform sampler2D facility_texture: hint_default_white;
uniform sampler2D replicant_texture: hint_default_white;
uniform vec3 facility_tint: hint_color = vec3(0.7, 0.7, 0.8);
uniform vec3 replicant_tint: hint_color = vec3(0.0, 0.8, 1.0);

void fragment() {
	vec4 facility_color = texture(facility_texture, UV) * vec4(facility_tint, 1.0);
	vec4 replicant_color = texture(replicant_texture, UV) * vec4(replicant_tint, 1.0);

	// Blend based on assimilation
	COLOR = mix(facility_color, replicant_color, assimilation);

	// Add energy glow on high assimilation
	if (assimilation > 0.5) {
		float glow_intensity = (assimilation - 0.5) * 2.0;
		COLOR += vec4(vec3(glow_intensity * 0.3), 0.0);
	}
}
```

---

## HUD Layout

### HUD Elements Placement

```
┌─────────────────────────────────────────────────────────────┐
│ ┌─ Metal: 47/500 ──────────────────────────────────────┐   │
│ │ Units: 12 (4H, 2S, 1B, 5Sol)                          │   │
│ │ Queue: Soldier (3s remaining)                          │   │
│ │ Assimilation: 42%  ▓▓▓▓▓▓░░░░░░░░░░░░ (Total: 6/12 zones)│
│ └────────────────────────────────────────────────────────┘   │
│                                                              │
│                    ┌─ MINIMAP ─────────┐                   │
│                    │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │  (Top-right)     │
│                    │ ▓ ● ● ° ▓▓▓ ◆ ▓▓▓ │                   │
│                    │ ▓ ● ░░░░░ ◆ ▓▓▓▓ │                   │
│                    │ ▓░░░░░░░░░░░░░░░░ │                   │
│                    │ ▓ ■ ◇ ■ ░░░░░░░░░ │                   │
│                    │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │                   │
│                    └────────────────────┘                   │
│                                                              │
│                         GAME VIEW                            │
│                      (Camera + Units)                        │
│                                                              │
│ ┌─ ALERT: New Patrol Unit detected! ──────────────────┐   │
│ │ Location: North Corridor                             │   │
│ │ [DISMISS]                                            │   │
│ └────────────────────────────────────────────────────────┘   │
│                                                              │
│ (Bottom-Right)                                              │
│ ┌─ SELECTED UNIT ──────────────────────────────────────┐   │
│ │ Soldier_5                                             │   │
│ │ Health: 38/40 HP  ▓▓▓▓▓▓▓▓░░                         │   │
│ │ Status: Idle                                          │   │
│ │ Location: Resource_Room_A                             │   │
│ └────────────────────────────────────────────────────────┘   │
│                                                              │
│ (Bottom-Center) PROTOCOL WHEEL (On Hold X)                 │
│                    ⬆ Rapid Replication                     │
│              ⬅ Def. Formation  ⬜  Swarm Rush ➡           │
│                    ⬇ Scatter                                │
└─────────────────────────────────────────────────────────────┘
```

### HUD Components Breakdown

#### Top-Left: Resource & Status Panel
```
┌─ METAL ECONOMY ─────────────┐
│ Metal:     47 / 500         │
│ Income:    +2.1 metal/sec   │
│ Production Queue:           │
│   1. Soldier (3s)           │
│   2. Harvester (waiting)    │
├─────────────────────────────┤
│ Units: 12 / Limit           │
│   Harvester:  4             │
│   Scout:      2             │
│   Soldier:    5             │
│   Builder:    1             │
│ Assimilation: 42%           │
│ ▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░ │
│ (Assimilated 5 of 12 zones) │
└─────────────────────────────┘
```
- Updates in real-time as metal changes, units spawn, assimilation progresses.
- Color coding: Green for positive income, orange for warning (low metal), red for critical.

#### Top-Right: Minimap
- **Size:** 200×200px (fits corner).
- **Zoom:** Can be adjusted with Right Stick.
- **Legend:**
  - ● (Blue) = Swarm unit
  - ■ (Red) = Resistance unit
  - ◆ (Yellow) = Metal deposit
  - ◇ (Cyan) = ReplicationHub
  - ░ (Dark Gray) = Fog of War
  - ▓ (Gray) = Facility wall
- **Click-able:** Left Click on minimap pans camera.
- **Updates:** Real-time unit positions, fog of war status.

#### Bottom-Right: Selected Unit Information
- **Shows:** Unit type, health bar, status, current command, location.
- **Updates:** Changes whenever unit takes damage or changes state.
- **Visible only when:** Unit is selected (disappears if selection cleared).

#### Bottom-Center: Protocol Wheel
- **Appears on hold:** X Button (gamepad) or Z Key (keyboard).
- **5-Segment radial menu:**
  - **Up:** Rapid Replication (icon: spinning hub)
  - **Right:** Swarm Rush (icon: forward arrow)
  - **Down:** Scatter (icon: dispersing units)
  - **Left:** Defensive Formation (icon: shield)
  - **Bottom-Right:** Assimilation Wave (icon: energy absorption, late game only)
- **Hover Preview:** Shows cost, cooldown, brief description.
- **Confirmation:** Release input on selected protocol or press RT.

#### Alert Notifications
- **Trigger:** New Resistance unit detected, Escalation event, Mission objective progress.
- **Display:** Popup at bottom-center, 3-second duration or [DISMISS] button.
- **Audio:** Distinctive beep or siren.

---

## Visual Style and Aesthetic

### Color Palette
| Element | Color | Hex Code | Usage |
|---------|-------|----------|-------|
| Facility Base | Cold Gray | #A8A8B8 | Walls, floor, structures |
| Facility Accent | Steel Blue | #4A6FA5 | Doors, panels, highlights |
| Swarm Primary | Electric Cyan | #00E0FF | Unit outlines, replicant structures |
| Swarm Secondary | Neon Blue | #0080FF | Energy conduits, assimilation aura |
| Resistance | Deep Red | #CC2222 | Enemy units, threat indicators |
| Alert | Bright Orange | #FF8800 | Warnings, escalation signals |
| Metal Deposit | Golden Yellow | #FFD700 | Resource markers |

### Swarm Unit Aesthetics
- **Morphology:** Segmented, insectoid, chitinous.
- **Design Language:** Sharp angles, organic-mechanical hybrid. Articulated limbs.
- **Size Reference:** Smallest (Scout): 12px. Largest (Assimilator): 28px.
- **Glow:** Soft cyan glow around all swarm units (identifies as replicant tech).
- **Animation:** Subtle idle pulsing (0.5 sec cycle), smooth movement, snappy attack animations.

### Facility Environment
- **Architecture:** Rectilinear, industrial, utilitarian.
- **Materials:** Concrete, steel, glass (clean, sterile aesthetic).
- **Lighting:** Harsh shadows, fluorescent harsh light (before assimilation).
- **Assimilation Effect:** Surfaces gain organic overgrowth, crystalline replicant formations, energy conduits.

### Assimilated Zone Aesthetic
- **Structures:** Metallic biomimicry. Curved, flowing, alien.
- **Color:** Dominance of cyan/blue, with dark metallic accents.
- **Particle Effects:** Floating energy particles, faint humming aura.
- **Tile Appearance:** Facility tiles become corroded, reforged, overtaken by replicant architecture.

---

## Visual Effects

### Critical VFX Events

| Event | Effect | Duration | Audio |
|-------|--------|----------|-------|
| **Unit Spawn (Replication)** | Bright cyan pulse at hub, units materialize with particle burst | 0.5 sec | Chime + metallic hum |
| **Unit Death** | Small explosion, sparks, unit dissolves to particles | 0.3 sec | Sharp crackle |
| **Metal Harvest** | Small sparkles rise from deposit toward Harvester | 1 sec (looping) | Metallic clink |
| **Assimilation Progress** | Zone tiles shimmer cyan, energy lines crawl across surfaces | Continuous | Soft hum + crackle |
| **Assimilator Assimilating** | Energy streams connect Assimilator to target, target glows | Assimilation duration | Absorption hum |
| **Swarm Rush Activation** | Cyan aura surrounds targeted Soldiers, speed trails | Command duration | Sharp electronic burst |
| **Scatter Protocol** | Units emit quick cyan pulses as they disperse | 0.3 sec | Electronic whine |
| **EMP Burst** | Blue sphere expands from EMP drone, units in radius dim | 5 sec (stun visual) | Crackling discharge |
| **Resistance Alarm** | Red flashing overlay at screen edge, red pulsing | 3 sec | Siren/alarm sound |

### Particle Systems
- **Swarm Movement Trails:** Subtle cyan particle trail behind moving units (50% opacity, dissipates quickly).
- **Assimilation Creep:** Floating cyan particles drift across assimilating zones.
- **Replication Pulse:** Bright cyan rings expand outward from ReplicationHub when unit spawns.
- **Metal Sparkles:** Small golden particles rise from deposits as Harvesters extract.

---

## Audio Design

### Ambient Soundscapes
- **Facility Default:** Low industrial hum, distant machinery, occasional electrical hum. Sterile, oppressive.
- **During Assimilation:** Facility hum fades, replaced by organic replicant humming, energy crackles.
- **Escalation Alert:** Alarm siren, automated warnings, increasing electronic noise.

### Unit Audio Signatures

| Unit | Idle Sound | Movement | Action | Damage/Death |
|------|-----------|----------|--------|--------------|
| **Harvester** | Soft metallic hum | Clicking footsteps | Metal clink (harvest) | Burst + dissolve crackle |
| **Scout** | Quiet chirp | Fast scuttling | (Silent, minimal) | Sharp electronic squeal |
| **Soldier** | Rhythmic hum | Metallic footsteps | Screeching attack | Crackling impact + decay |
| **Builder** | Low resonant hum | Heavy footsteps | Construction whine | Deep crackle + fade |
| **Assimilator** | Humming/resonance | Slow, deliberate steps | Absorption tone (humming intensifies) | Sacrificial dissolve tone |

### Resistance Audio Signatures

| Unit | Detection | Engagement | Special |
|------|-----------|-----------|---------|
| **Patrol** | Alert beep, footsteps | Gunfire/melee clash | Radio chatter (faint) |
| **Turret** | Targeting lock tone | Laser charging, shot | Overheating warning |
| **EMP Drone** | Electronic whining | EMP crackle burst | Disruptive static |
| **Commander** | Authoritative voice | Command bark + attack | Rally alarm siren |

### Protocol Activation Sounds
- **Swarm Rush:** Sharp electronic burst + ascending tone (signals unit surge).
- **Rapid Replication:** Accelerating mechanical whine (production speed increase).
- **Scatter:** Chaotic electronic chirps + downward glissando (units scattering).
- **Defensive Formation:** Resonant bass tone (units grouping, solidifying).
- **Assimilation Wave:** Deep absorption tone + crackling energy (conversion surge).

### UI Feedback Sounds
- **Selection:** Soft confirmation beep (non-intrusive).
- **Command Issued:** Chime + brief metallic tone.
- **Alert Notification:** Quick siren pulse.
- **Victory:** Rising triumphant tone sequence.
- **Defeat:** Descending mournful tone, then silence.

---

## Music Integration (MusicManager)

### BurnBridgers MusicManager Integration
Replicants uses the shared **MusicManager** from BurnBridgers infrastructure.

### Music Profile Settings
- **Intensity:** 0.92 (high, ominous, methodical)
- **Speed:** 0.88 (slightly slower, deliberate pace)
- **Tone:** 0.90 (dark, foreboding, alien)

### Music Zones by Mission State
| State | Intensity | Tone | Instrumentation |
|-------|-----------|------|-----------------|
| AWAKENING | 0.70 | Exploratory | Synths, slow percussion, organic sounds |
| EARLY_COLONY | 0.80 | Building Tension | Industrial sounds, rising synth layers |
| EXPANSION | 0.90 | Ominous Momentum | Heavy synths, driving percussion, bass |
| RESISTANCE_SURGE | 0.98 | Frantic, Desperate | Chaotic textures, dissonant chords, rapid percussion |
| VICTORY | 0.85 | Triumphant Assimilation | Sweeping synths, resolved chords, ascending tones |
| DEFEAT | 0.30 | Mournful Silence | Fading tones, sparse instruments, silence |

### Dynamic Music Transitions
- **Smooth Interpolation:** When state changes, music intensity and speed transition over 2–3 seconds (no jarring cuts).
- **Escalation Cue:** On escalation trigger, music spikes intensity for 2 seconds (alert moment), then settles at RESISTANCE_SURGE intensity.
- **Victory/Defeat:** Music crossfades to respective theme over 1 second.

---

## Implementation Notes

- **Tilemap Layers:** Use multiple TileMap layers for base facility, assimilation overlay, and visual effects.
- **Shader System:** Implement AssimilationShader.gdshader for per-zone assimilation blending.
- **Particle Pools:** Pre-instantiate particle systems to avoid runtime stutters during heavy VFX events.
- **Audio Buses:** Organize audio into buses (SFX, Music, Ambient, UI) for independent mixing.
- **Accessibility:** Ensure high-contrast colors and optional closed captions for dialogue/alerts.

---

## GDScript Implementation Example: AssimilationZone

```gdscript
# AssimilationZone.gd
class_name AssimilationZone
extends Node2D

@export var zone_name: String = "Zone_1"
@export var initial_visual: Color = Color.GRAY
@export var assimilated_visual: Color = Color(0.0, 0.8, 1.0)  # Cyan

@onready var tilemap: TileMap = $TileMapLayer
@onready var shader_material: ShaderMaterial = tilemap.material as ShaderMaterial

var assimilation_percentage: float = 0.0
var max_assimilation_percentage: float = 100.0
var assimilation_rate: float = 1.0  # % per second when Assimilators present

signal assimilation_changed(percentage: float)

func _ready() -> void:
	if shader_material:
		shader_material.set_shader_parameter("assimilation", assimilation_percentage / 100.0)

func _process(delta: float) -> void:
	_update_assimilation(delta)
	_sync_shader()

func _update_assimilation(delta: float) -> void:
	# Check for Assimilators in zone
	var assimilators_in_zone = _count_assimilators_in_zone()

	if assimilators_in_zone > 0:
		# Increase assimilation
		assimilation_percentage = min(assimilation_percentage + (assimilation_rate * assimilators_in_zone * delta), 100.0)
	else:
		# Slowly decrease if no Assimilators (resistance reclaiming)
		assimilation_percentage = max(assimilation_percentage - (0.2 * delta), 0.0)

	assimilation_changed.emit(assimilation_percentage)

func _sync_shader() -> void:
	if shader_material:
		var assimilation_value = assimilation_percentage / 100.0
		shader_material.set_shader_parameter("assimilation", assimilation_value)

func _count_assimilators_in_zone() -> int:
	var count = 0
	for area in get_overlapping_areas():
		if area.get_parent() is SwarmUnit:
			var unit = area.get_parent()
			if unit.unit_type == "assimilator":
				count += 1
	return count

func get_assimilation_percentage() -> float:
	return assimilation_percentage
```

---

## Testing Checklist

- [ ] Fog of war reveals correctly as Scouts move.
- [ ] Assimilation shader blends zones smoothly (0–100%).
- [ ] HUD elements update in real-time without lag.
- [ ] Minimap accurately represents unit positions.
- [ ] Audio cues play correctly for unit actions and protocols.
- [ ] Music transitions smoothly between mission states.
- [ ] Visual effects (particles, VFX) don't cause frame drops.
- [ ] Assimilation zones are visually distinct at each stage (0%, 25%, 50%, 75%, 100%).
- [ ] Alert notifications display and dismiss correctly.

