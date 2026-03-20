# Blacksite Containment — Kenney Asset Mapping

All packs are CC0 licensed (public domain). Run `download_kenney_assets.ps1` to
pull them all in one shot. This file documents how each Kenney pack maps to
specific game elements defined in the REQ docs.

---

## Pack Inventory

| Pack | Kenney URL | Local Folder | Size |
|------|-----------|-------------|------|
| Sci-Fi RTS | https://kenney.nl/assets/sci-fi-rts | `models/_kenney_sci-fi-rts/` | ~120 models |
| Space Kit | https://kenney.nl/assets/space-kit | `models/_kenney_space-kit/` | ~150 models |
| Space Station Kit | https://kenney.nl/assets/space-station-kit | `models/_kenney_space-station-kit/` | ~90 models |
| Modular Space Kit | https://kenney.nl/assets/modular-space-kit | `models/_kenney_modular-space-kit/` | ~40 models |
| UI Pack: Sci-Fi | https://kenney.nl/assets/ui-pack-sci-fi | `ui/_kenney_ui-pack-sci-fi/` | ~130 sprites |
| Sci-Fi Sounds | https://kenney.nl/assets/sci-fi-sounds | `audio/_kenney_sci-fi-sounds/` | ~30 sounds |
| Interface Sounds | https://kenney.nl/assets/interface-sounds | `audio/_kenney_interface-sounds/` | ~80 sounds |

---

## Element-by-Element Mapping

### Drone Player (DronePlayer scene)

**Source: Sci-Fi RTS**

| Asset to use | Notes |
|---|---|
| `craft_speederA.glb` or `craft_speederB.glb` | Primary drone mesh — flat hover vehicles with a good aerial silhouette |
| `craft_cargoA.glb` | Alternate/bulkier drone variant if you want visual differentiation per player |
| `effect_yellow.glb` / `effect_purple.glb` | Thruster glow effects on drone undercarriage |

Tint the mesh material at runtime with the per-player drone color (cyan, green, yellow, red as per REQ_01).

**Alternative: Space Kit**

`ship_*.glb` models — more detailed, larger scale. Use for drone mesh if RTS craft feel too small.

---

### Escapees (EscapeeEntity)

**Source: Sci-Fi RTS**

| Escapee Type (REQ_06) | Kenney Model | Notes |
|---|---|---|
| Basic Runner (MVP) | `unit_infantry.glb` or `unit_soldier.glb` | Humanoid silhouette, fast movement, easy to read |
| Evader (post-MVP) | `unit_specialForces.glb` | Smaller, more agile-looking |
| Tank (post-MVP) | `unit_mecBot.glb` or `unit_robot.glb` | Heavy, wide footprint |
| Swarm (post-MVP) | `unit_dog.glb` | Small, clustered in groups |
| Elite (post-MVP) | `unit_commander.glb` | Distinct hat/gear for visual hierarchy |

Add a neon red halo `GPUParticles3D` around each escapee mesh (0.5m radius, REQ_07).

---

### Arena Floor & Geometry (Arena node in scene)

**Source: Space Kit + Space Station Kit**

#### Arena Floor (60×60m)
Use `tileFloor.glb` (Space Kit) tiled to cover the arena surface. The dark metallic base
matches the `#0d0d0d` color palette from REQ_07.

#### Perimeter Walls (2m height ring)
- `wall.glb` or `wallCorner.glb` from Space Kit — tile around the 80m perimeter.
- Apply a translucent blue emissive material (`#1a4d7a` at 40% opacity) to simulate the
  force-field aesthetic. Swap to red emissive on BreachZone nodes.

#### Containment Lane Markers
- `crateLarge.glb` / `barrelSmall.glb` from Space Kit — scatter as lane boundary props.
- `rail*.glb` pieces for subtle corridor side-rails.

#### Central Drone Staging Platform
- `foundation_large.glb` or `platform.glb` from Space Station Kit — elevated 0.5m center pad.
- `launchpad.glb` if available — good visual cue for drone spawn positions.

#### Optional Obstacles (central tactical blockers)
- `pillar.glb`, `column.glb` from Space Station Kit or Space Kit.
- Keep to 3–4 obstacles max (REQ_07 calls for a few; don't clutter pathing).

---

### HUD (CanvasLayer)

**Source: UI Pack: Sci-Fi**

| HUD Element (REQ_07) | Kenney Sprite | Notes |
|---|---|---|
| Ability status panel background | `panel_metalSmall.png` or `panel_beigeLight.png` | Use the dark-variant panels; tint to match `#0d0d0d` |
| Charge Laser bar | `barHorizontal_white_mid.png` + end caps | Tint cyan for charge; green at full charge; red for overheat |
| Mission Integrity meter | `barHorizontal_white_mid.png` | Apply green→red gradient via shader or progress bar modulate |
| Energy meter | Same bar sprite | Yellow tint; red at <30% |
| Ability icons | `icon_*.png` — target reticle, lightning bolt, clock icons | Use closest matches; re-tint to match ability colors |
| Minimap border | `panel_roundDark.png` | Square crop with neon cyan border shader |
| Notification log background | `panel_beigeLight.png` (tinted dark) | Bottom-center scrolling feed |
| Wave counter | Text over `panel_metalSmall.png` | White text, Orbitron font |
| Breach alert overlay | Red full-screen flash is code-driven; use `panel_red.png` as tint layer | |

**Font recommendation**: Use [Orbitron](https://fonts.google.com/specimen/Orbitron) or
[Space Mono](https://fonts.google.com/specimen/Space+Mono) for HUD text. Download and
place in `assets/blacksite/fonts/`. Both are free (SIL Open Font License).

---

### Audio (SFX)

**Source: Sci-Fi Sounds + Interface Sounds**

| Sound Event (REQ_07) | Kenney File | Notes |
|---|---|---|
| Charge laser — charging hum | `laserLarge_000.ogg` (or similar rising tone) | Loop while RT held; pitch-shift upward with `AudioStreamPlayer.pitch_scale` |
| Charge laser — fire | `laserSmall_001.ogg` or `laserRetro_001.ogg` | Short sharp zap on release |
| Charge laser — overheat | `forceField_003.ogg` + `impactPlate_000.ogg` | Two-part: warning beep then harsh alarm |
| Orbital strike — countdown beep | `pepSound1.ogg` / `tone1.ogg` from Interface Sounds | Repeating every 1s, pitch rising |
| Orbital strike — impact | `explosionCrunch_000.ogg` | Heavy boom with rumble tail |
| Breach alert — klaxon | `doorOpen_000.ogg` or build a loop from `alarm_*.ogg` | Loop at 95% volume until breach mitigated |
| Escapee spawn | `zap_001.ogg` | Subtle shimmer on spawn |
| Kill confirmation | `confirmation_001.ogg` from Interface Sounds | Soft "ding" + score pop |
| Wave complete | `jingles_NES00.ogg` or `jingles_NES17.ogg` from Interface Sounds | Short triumphant stab |
| UI clicks / button hover | `click_001.ogg` / `rollover1.ogg` from Interface Sounds | Menu and debrief navigation |

---

## Folder Structure (post-download)

```
assets/blacksite/
├── download_kenney_assets.ps1      ← run this first
├── ASSET_MAPPING.md                ← this file
├── fonts/
│   └── (Orbitron.ttf, SpaceMono-Regular.ttf — download from Google Fonts)
├── models/
│   ├── _kenney_sci-fi-rts/         ← drone meshes + escapee units
│   ├── _kenney_space-kit/          ← arena floor, walls, structures
│   ├── _kenney_space-station-kit/  ← arena corridors, staging platform
│   └── _kenney_modular-space-kit/  ← optional obstacle pieces
├── ui/
│   └── _kenney_ui-pack-sci-fi/     ← HUD panels, bars, icons
├── audio/
│   ├── _kenney_sci-fi-sounds/      ← laser, explosion, ability SFX
│   └── _kenney_interface-sounds/   ← UI clicks, chimes, jingles
├── textures/                       ← (place any custom tilesheet overrides here)
└── vfx/                            ← (placeholder for custom particle sprites)
```

---

## Implementation Notes

### Applying the Blacksite color palette to Kenney models
Kenney 3D models use plain white/gray base materials. In Godot, swap them out via:
```gdscript
var mat = StandardMaterial3D.new()
mat.albedo_color = Color("#2a2a2a")   # dark steel gray base
mat.emission_enabled = true
mat.emission = Color("#00d4ff")       # cyan glow for drones
mat.emission_energy = 1.5
mesh_instance.material_override = mat
```
Use `emission_energy = 0` for neutral environment pieces; ramp it up for threat indicators.

### Model scale
Sci-Fi RTS models are built at roughly 1:1 Godot units. The arena floor target is 60×60m;
`tileFloor.glb` from Space Kit is typically 2m×2m, so tile 30×30 across the floor.

### Audio import settings in Godot
For looping sounds (charge hum, breach klaxon), enable **Loop** in the import settings
(`.ogg` → AudioStreamOggVorbis → Loop: true). For one-shot SFX, keep Loop: false.

### Particle VFX
Kenney's Particle Pack (2D sprite sheets) can be used with `GPUParticles3D` as
billboard particles for impact blooms, breach flashes, and orbital strike dust. Set
`draw_pass` to a QuadMesh with the particle sprite texture.

---

## License

All Kenney assets are **CC0 1.0 Universal (Public Domain)**. No attribution required,
though noting "Assets by Kenney (kenney.nl)" in credits is appreciated by the community.
