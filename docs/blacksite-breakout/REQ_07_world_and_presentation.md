# REQ_07: World and Presentation
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines the visual aesthetic, HUD layout, VFX systems, audio design, and how the facility "feels" to the player. Presentation is critical to establishing tension and communicating game state.

---

## 1. Visual Style

### 1.1 Isometric Facility Aesthetic
**Overall tone:** Sterile, clinical facility → chaotic, corrupted breach.

**Early sectors (1–2):**
- Clean concrete and steel surfaces; geometric precision.
- Fluorescent lighting (cool blue-white).
- Order and containment visible (locked doors, sealed walls, surveillance cameras).
- Color palette: Cool grays, steels, sharp whites.

**Late sectors (4–5):**
- Damage visible (cracked glass, sparking conduits, biological spreading).
- Lighting flickering, emergency red tints appearing.
- Containment failure evident (vents damaged, biohazard spreading, structural compromises).
- Color palette: Warm oranges, reds, blacks; surfaces increasingly organic.

**Visual transition:** As alarm escalates, facility tints toward red; warning lights activate; environmental degradation increases.

### 1.2 Tile Art & Collage Style
- **Tile size:** 32×32 pixel tiles (4x scale = 128×128 on-screen for clarity).
- **Art style:** Hand-drawn isometric sprites with anti-aliasing.
- **Shading:** 2.5D isometric shading (top-left light source, slight shadow edges).
- **Consistency:** All entities and environment use matching isometric angle and shading model.

### 1.3 Entity Visual Language

Each entity has a distinct silhouette and color scheme, enabling instant visual parsing in co-op:

#### Replicator (Infiltrator)
- **Silhouette:** Angular, geometric limbs; metallic sheen.
- **Primary color:** Chrome silver (RGB: 192, 192, 192).
- **Secondary color:** Dark metallic gray (RGB: 80, 80, 80).
- **Aura:** Shimmer effect (refraction distortion) when moving.
- **Size:** Medium (similar to human).
- **Visual quirk:** Visible circuitry/circuit-board pattern on body.

#### Fungus Strain (Scout)
- **Silhouette:** Bulbous, sprawling; organic, flowing.
- **Primary color:** Deep green (RGB: 34, 139, 34).
- **Secondary color:** Amber/gold (RGB: 218, 165, 32).
- **Aura:** Spore particles trailing during movement; mycelium trails glow faintly.
- **Size:** Medium-large.
- **Visual quirk:** Visible mycelium network under skin/surface; pulsing glow.

#### CRISPR Anomaly (Chris)
- **Silhouette:** Humanoid but unstable; limbs shift and flicker.
- **Primary color:** Iridescent shifting (RGB cycles: 200, 0, 200 → 0, 200, 200 → 200, 200, 0).
- **Secondary color:** Bioluminescent highlights (RGB: 0, 255, 127).
- **Aura:** Mutation shimmer; occasional biological pulses.
- **Size:** Medium.
- **Visual quirk:** Visible mutation plates on arms/shoulders; unstable outline.

#### Rogue AI Construct (Hacker)
- **Silhouette:** Angular, geometric; digital/robotic.
- **Primary color:** Electric blue (RGB: 0, 150, 255).
- **Secondary color:** Cyan (RGB: 0, 255, 255).
- **Aura:** Glitch trails; pixelated edges; code-stream visual effect.
- **Size:** Medium.
- **Visual quirk:** Visible code/digital text on body; screen-like face area.

### 1.4 Facility Environment

**Floor textures:**
- **Corridor:** Steel grating with shadow detail.
- **Lab:** Polished concrete with equipment housings.
- **Storage:** Painted steel with stacked crates.
- **Server room:** Raised floor with cable routing.

**Wall details:**
- Concrete with embedded steel reinforcement.
- Surveillance camera mounts at ceiling intersections.
- Emergency warning labels and hazard stripes.
- Air vents and conduit runs.

**Lighting:**
- Fluorescent ceiling fixtures casting bright, uniform light.
- Emergency lighting (red beacons) on high-alert.
- Shadow areas under equipment creating stealth zones.
- Glowing monitors/screens in server rooms.

---

## 2. HUD & UI Layout

### 2.1 Health & Status Bar
**Position:** Top-left corner of screen.
**Content:**
- Current entity class icon (small sprite, 32×32).
- Health bar (green → yellow → red as health decreases).
- Health text: "45 / 100 HP".
- Status effects (if any): small icons below health bar (poisoned, slowed, etc.).

**Behavior:**
- Updates in real-time as entity takes damage.
- Bar flashes red briefly when damage taken.
- Downed state shows overlay: "DOWNED - PRESS [INTERACT] TO REVIVE".

### 2.2 Ability Cooldown Display
**Position:** Bottom-right corner of screen (ability wheel).
**Layout:** 4 circular icons arranged in a diamond:
```
        [Ability 1]
        (LB/Q)
           ▲
           │
[Ability 2]◄─┤─► [Ultimate]
(RB/R)       │    (LT/T)
           │
        [Passive]
        (Y/Space)
```

**Visual feedback per ability:**
- **Ready:** Icon bright, color-saturated.
- **Cooldown:** Icon dimmed, circular progress bar around icon (depletes as cooldown expires).
- **Executing:** Icon briefly flashes white (ability activation feedback).

**Cooldown text:** Shows time remaining in center of icon (e.g., "5s" for 5 seconds remaining).

**GDScript - Ability UI:**
```gdscript
class_name AbilityUI
extends CanvasLayer

@export var ability_icons: Array[Texture2D] = []
@export var ability_cooldown_color: Color = Color(0.3, 0.3, 0.3)
@export var ability_ready_color: Color = Color(1.0, 1.0, 1.0)

var ability_panels: Array[Panel] = []
var cooldown_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]
var ability_durations: Array[float] = [5.0, 12.0, 0.0, 50.0]  # Passive has no cooldown

func _ready() -> void:
	setup_ability_panels()

func setup_ability_panels() -> void:
	var positions = [Vector2(400, 200), Vector2(300, 350), Vector2(500, 350), Vector2(400, 500)]
	for i in range(4):
		var panel = Panel.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ability_panels.append(panel)
		add_child(panel)

func update_cooldown(ability_index: int, remaining: float) -> void:
	cooldown_timers[ability_index] = remaining
	var panel = ability_panels[ability_index]

	if remaining > 0.0:
		panel.modulate = ability_cooldown_color
		# Draw progress ring
		queue_redraw()
	else:
		panel.modulate = ability_ready_color

func _draw() -> void:
	for i in range(4):
		var timer = cooldown_timers[i]
		if timer > 0.0 and timer <= ability_durations[i]:
			var progress = 1.0 - (timer / ability_durations[i])
			draw_arc(ability_panels[i].global_position, 20, 0, TAU * progress, 20, Color.WHITE, 2.0)
			draw_string(ThemeDB.default_font, ability_panels[i].global_position, str(int(timer)))
```

### 2.3 Alarm Level Meter
**Position:** Top-right corner of screen.
**Display:** Horizontal bar with five segments:
```
ALARM: [  |  |▓▓|▓▓|▓▓]
       QUIET   LOCAL  LOCKDOWN  FACILITY
```

**Color coding:**
- **QUIET:** Green (RGB: 0, 200, 0).
- **LOCAL_ALERT:** Yellow (RGB: 200, 200, 0).
- **SECTOR_LOCKDOWN:** Orange (RGB: 255, 165, 0).
- **FACILITY_ALERT:** Red (RGB: 255, 0, 0), pulsing.

**Text label:** Shows current alarm level as text (e.g., "SECTOR LOCKDOWN").

### 2.4 Fog-of-War Minimap
**Position:** Bottom-left corner of screen (toggleable on/off with X / "Map View").
**Size:** 200×200 pixel overlay (quarter-screen in map view mode).
**Content:**
- Sector layout (walls, doors, corridors shown).
- Explored areas visible; unexplored areas dark/hidden.
- Entity positions: colored dots matching entity colors.
- Guard positions: red dots (only visible if seen or detected).
- Mycelium nodes (Fungus Strain): glowing green dots with connecting lines.
- Alarm origin (recent threat): pulsing red marker.

**Update frequency:** Real-time (refreshes each frame as entities move).

**GDScript - Minimap:**
```gdscript
class_name MinimapUI
extends Control

@export var minimap_scale: float = 0.5
@export var sector_width: float = 1000.0
@export var sector_height: float = 1000.0

var entity_manager: Node
var guard_manager: Node
var sector_map: TileMap

func _ready() -> void:
	entity_manager = get_tree().root.find_child("EntityManager", true, false)
	guard_manager = get_tree().root.find_child("GuardManager", true, false)
	sector_map = get_tree().root.find_child("SectorMap", true, false)

func _draw() -> void:
	# Draw sector background
	draw_rect(Rect2(0, 0, size.x, size.y), Color.BLACK)

	# Draw explored tiles
	var revealed_tiles = sector_map.get_revealed_area()
	for tile in revealed_tiles:
		var minimap_pos = world_to_minimap(sector_map.map_to_local(tile))
		draw_rect(Rect2(minimap_pos, Vector2(5, 5)), Color.GRAY)

	# Draw entity dots
	for entity in entity_manager.get_all_entities():
		var minimap_pos = world_to_minimap(entity.global_position)
		draw_circle(minimap_pos, 5, get_entity_color(entity))

	# Draw guard dots
	for guard in guard_manager.get_all_guards():
		var minimap_pos = world_to_minimap(guard.global_position)
		draw_circle(minimap_pos, 4, Color.RED)

func world_to_minimap(world_pos: Vector2) -> Vector2:
	return (world_pos / Vector2(sector_width, sector_height)) * size

func get_entity_color(entity: EntityCharacter) -> Color:
	match entity.entity_type:
		EntityCharacter.EntityType.REPLICATOR: return Color(0.75, 0.75, 0.75)
		EntityCharacter.EntityType.FUNGUS_STRAIN: return Color(0.13, 0.54, 0.13)
		EntityCharacter.EntityType.CRISPR: return Color(0.78, 0.31, 0.78)
		EntityCharacter.EntityType.ROGUE_AI: return Color(0.0, 0.59, 1.0)
		_: return Color.WHITE
```

### 2.5 Interaction Prompt
**Position:** Bottom-center of screen (above ability wheel).
**Content:** Text label showing interact button and action.
**Examples:**
- "[E] Open Door"
- "[A] Read Terminal"
- "[E] Pick Up Keycard"
- "[E] Revive Ally"

**Behavior:**
- Appears when entity within 100 units of interactable.
- Disappears when entity moves away.
- Color changes based on interactable type (green for safe, yellow for alarmed, red for dangerous).

### 2.6 Downed Entity Indicator
When an ally entity is downed:
- **Minimap:** Downed entity dot pulses/flashes (animation).
- **HUD text:** "ALLY DOWNED at [location] - Press [E] to revive" appears on-screen.
- **Revive prompt:** When near downed ally, interaction prompt changes to show revive action.
- **Revive progress:** Circular progress bar appears above downed entity while revive in progress.

---

## 3. Visual Effects (VFX) Systems

### 3.1 Ability Effects
Each entity ability has distinctive VFX:

**Replicator:**
- **Assimilate:** Object dissolves into glowing silver particles (shimmering mist).
- **Replicant Decoy:** Clone appears with brief shimmer; light trails as it moves.
- **Rapid Replication:** Metallic shattering effect; multiple burst trails; unit spawns with glitch animation.

**Fungus Strain:**
- **Spore Cloud:** Amber/green cloud particles; vision inside cloud reduced (screen becomes foggy with spore overlay).
- **Mycelium Node:** Green glowing circle appears on ground; pulsing aura; connecting line between nodes.
- **Cordyceps Override:** Guard's eyes glow amber; mycelium veins visible under skin; temporary color shift toward green.

**CRISPR (Chris):**
- **Mutate Form:** Biological shimmer; limbs briefly elongate/contract; skin ripples with color shift.
- **Acid Secretion:** Green/amber acidic droplets spray; corrosion effect on hit surface (material dissolves).
- **Unstable Mutation:** Entity swells; bioluminescent energy pulses; acid aura around body; grotesque mutation animation.

**Rogue AI:**
- **Facility Data Access:** Brief screen glitch; facility overlay appears (patrol paths, camera cones visible); blue code-stream visual effect.
- **Hack Terminal:** Digital intrusion VFX; terminal screen flickers; code-stream flows from entity to terminal.
- **Machine Possession:** Entity becomes transparent/glitchy; machine glows blue; digital code visible.
- **Cascade Hack:** Facility-wide blue wave effect; all screens flicker; code-stream spreads across visible systems.

### 3.2 Guard Detection & Alert VFX
- **Detection cone:** Yellow cone appears briefly when guard spots entity (1 second flash).
- **Alert:** Screen shake (0.2 second, 5-unit shake radius).
- **Alarm escalation:** Red tint increases; emergency lights activate (animated red beacons).

### 3.3 Alarm State Visual Feedback
As alarm escalates:
- **QUIET:** Normal screen colors, no tint.
- **LOCAL_ALERT:** Slight yellow tint (5% overlay).
- **SECTOR_LOCKDOWN:** Orange tint (15% overlay); emergency red beacons visible and rotating.
- **FACILITY_ALERT:** Heavy red tint (30% overlay); beacons pulsing frantically; screen flickers occasionally.

**GDScript - Alarm Visual Feedback:**
```gdscript
class_name AlarmVisualFeedback
extends CanvasLayer

@export var alarm_system: AlarmSystem
@export var color_normal: Color = Color.WHITE
@export var color_local: Color = Color(1.0, 1.0, 0.8)
@export var color_lockdown: Color = Color(1.0, 0.8, 0.6)
@export var color_facility: Color = Color(1.0, 0.5, 0.5)

var color_rect: ColorRect
var beacon_light: Light2D

func _ready() -> void:
	color_rect = ColorRect.new()
	color_rect.anchor_right = 1.0
	color_rect.anchor_bottom = 1.0
	add_child(color_rect)

	beacon_light = Light2D.new()
	beacon_light.color = Color.RED
	add_child(beacon_light)

	alarm_system.level_changed.connect(_on_alarm_level_changed)

func _on_alarm_level_changed(new_level: int) -> void:
	match new_level:
		AlarmSystem.AlarmLevel.QUIET:
			color_rect.color = color_normal
			beacon_light.energy = 0.0
		AlarmSystem.AlarmLevel.LOCAL_ALERT:
			color_rect.color = color_local
			beacon_light.energy = 0.5
			beacon_light.enabled = true
		AlarmSystem.AlarmLevel.SECTOR_LOCKDOWN:
			color_rect.color = color_lockdown
			beacon_light.energy = 1.0
		AlarmSystem.AlarmLevel.FACILITY_ALERT:
			color_rect.color = color_facility
			beacon_light.energy = 1.5
			start_pulsing_beacon()

func start_pulsing_beacon() -> void:
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(beacon_light, "energy", 2.0, 0.3)
	tween.tween_property(beacon_light, "energy", 1.0, 0.3)
```

---

## 4. Audio Design

### 4.1 Ambient Soundscapes
**Quiet state:** Low-frequency facility hum (60 Hz baseline), distant machinery sounds, air circulation noise.
**Local alert:** Siren pulse begins (repeating 2-second pulse), radio chatter (guard communications).
**Sector lockdown:** Continuous alarm loop (different tone from local alert, more urgent), intense radio chatter, occasional mechanical clunks.
**Facility alert:** Loud alarm blare (high-frequency screech), overlapping radio channels, facility-wide PA system announcements.

**Music Manager Integration:**
- Alarm escalation triggers MusicManager to adjust intensity/speed parameters.
- QUIET: intensity = 1.15, speed = 0.80.
- LOCAL_ALERT: intensity = 1.25, speed = 0.95.
- SECTOR_LOCKDOWN: intensity = 1.35, speed = 1.10.
- FACILITY_ALERT: intensity = 1.45, speed = 1.20.

### 4.2 Entity Ability SFX
- **Replicator assimilate:** Metallic tearing sound, shimmer/chime effect.
- **Replicator decoy:** Glitchy duplicate sound, electronic whine.
- **Fungus spore cloud:** Organic whoosh, spore particle swarm hiss.
- **Fungus mycelium node:** Wet organic growth sound, pulsing tone.
- **Chris mutate:** Biological transformation screech, bone/muscle cracking.
- **Chris acid secretion:** Acidic sizzle, droplet splash.
- **Rogue AI hack:** Digital intrusion tone (ascending beep sequence), glitchy computer sounds.
- **Rogue AI machine possession:** Power-down/up electronic sound, digital whoosh.

### 4.3 Guard & Alert SFX
- **Guard detection:** Brief alert tone (ascending whistle), guard radio chatter ("Contact!").
- **Guard footsteps:** Heavy boot steps (metal grating), variable based on guard type.
- **Guard ranged attack:** Laser/energy weapon sound (sci-fi themed).
- **Alarm escalation:** Siren wail (progressively more intense with each escalation).

### 4.4 Environmental SFX
- **Door opening/closing:** Pneumatic hiss, mechanical click.
- **Terminal interaction:** Soft beep, keyboard click sounds.
- **Vent entrance/exit:** Metal grating noise, air rush.
- **Damage/sparks:** Electrical crackling, impact sound.

---

## 5. Screen Shake & Impact Feedback

### 5.1 Shake Magnitudes
| Event | Duration | Magnitude | Frequency |
|---|---|---|---|
| Guard alert | 0.2s | 5 units | Immediate |
| Alarm escalation | 0.3s | 8 units | Single |
| Ability activation (powerful) | 0.15s | 3 units | Impact moment |
| Facility wide alert | 0.5s | 10 units | Sustained |
| Entity hit/damage taken | 0.1s | 2 units | Impact |

**GDScript - Screen Shake:**
```gdscript
class_name ScreenShake
extends Node

var camera: Camera2D

func shake(duration: float, magnitude: float) -> void:
	var elapsed = 0.0
	while elapsed < duration:
		elapsed += 0.016  # ~60 FPS
		var offset = Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude))
		camera.offset = offset
		await get_tree().process_frame
	camera.offset = Vector2.ZERO
```

---

## 6. Downed Entity Visual State

When an entity is downed:
- **Body animation:** Entity enters prone state (lying down animation).
- **Opacity:** Entity becomes semi-transparent (50% alpha) to indicate incapacity.
- **Revive marker:** Glowing white/blue circle appears above entity (pulsing).
- **HUD indicator:** Downed entity appears on minimap with pulsing dot.
- **Revive prompt:** "PRESS [E] TO REVIVE" appears when ally adjacent.

**Revive animation:**
- Reviving entity kneels beside downed ally.
- Progress bar fills over 3 seconds.
- On completion: downed entity returns to standing; health restores to 50%.

---

## 7. Surveillance Camera Presentation

### 7.1 Visual Design
- **Model:** Rotating dome camera mounted on wall/ceiling.
- **Detection cone:** Bright yellow cone visible when camera operational.
- **Disabled state:** Camera stops rotating; cone disappears; red "X" appears on camera.

### 7.2 Camera Feedback
When camera detects entity:
- **Visual:** Detection cone briefly flashes red.
- **Audio:** Short beep/alert tone.
- **HUD:** Minimap shows camera alert location.

---

## 8. Accessibility Considerations

### 8.1 Colorblind Modes
- **Deuteranopia (red-green):** HUD alarm meter changes to blue/yellow; entity colors adjusted.
- **Protanopia (red-green):** Similar blue/yellow adjustment.
- **Tritanopia (blue-yellow):** Red/cyan used instead.

### 8.2 Audio-Visual Parity
- All audio cues have visual equivalents:
  - Siren sound → red warning light pulsing.
  - Guard alert sound → screen shake + visual alert indicator.
  - Ability SFX → ability icon flashes + VFX plays.

### 8.3 High-Contrast Mode
- Text labels increase font size (18pt → 24pt).
- HUD elements gain black outlines for visibility.
- Color saturation increases for alarm meter and ability icons.

---

## 9. Implementation Notes

### 9.1 Particle System Performance
- VFX pooled and reused (no dynamic particle creation).
- Particle count capped at 200 max on-screen simultaneously.
- Particle shaders use simple gradient/additive blending (minimal GPU overhead).

### 9.2 Audio Layer Management
- SoundManager node manages 16 concurrent audio channels.
- Ambient loops (facility hum, siren) always active (2 channels).
- Ability SFX queued on available channels (up to 8 overlapping).
- Alarm SFX prioritized; others cut if channel limit reached.

### 9.3 UI Canvas Layers
Multiple CanvasLayers enable proper depth ordering:
- **Layer 0 (World):** Sector map, entities, guards, interactables.
- **Layer 1 (Effects):** VFX particles, screen shake effects.
- **Layer 2 (HUD):** Health bar, ability icons, alarm meter, minimap.
- **Layer 3 (Popups):** Interaction prompts, downed indicators, notifications.

---

## 10. Related Documents
- REQ_02: Game State Machine (alarm escalation visual cues).
- REQ_03: Entity Classes and Abilities (ability VFX details).
- REQ_04: Movement and Interaction (interaction prompt HUD).
- REQ_06: Guard AI and Alarm System (detection visual feedback).

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
