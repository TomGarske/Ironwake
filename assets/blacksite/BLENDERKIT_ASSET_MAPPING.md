# Blacksite Containment — BlenderKit Asset Mapping

BlenderKit assets are higher-fidelity than Kenney and are used for the
**hero/visible** meshes and PBR materials that define the game's visual identity.
Kenney provides the scaffolding; BlenderKit provides the polish.

All assets listed here are **free** (confirmed via BlenderKit API). License
varies per asset — check the asset page. Most free BlenderKit assets are CC0
or CC-BY. See each link.

## How to import BlenderKit assets into Godot

1. Install the [BlenderKit addon](https://www.blenderkit.com/get-blenderkit/) in Blender.
2. Use `blender_export_to_glb.py` (in this folder) to batch-download and export
   everything to `models/_blenderkit_exports/`. Run it from Blender's scripting tab
   or via `blender --background --python blender_export_to_glb.py`.
3. In Godot, import the `.glb` files — Godot 4 reads GLTF2 natively.
4. For **materials**, apply them via the BlenderKit panel, bake albedo/roughness/
   metallic/normal maps to textures, then use those in Godot's `StandardMaterial3D`.
   The export script handles the bake step for you.

---

## Curated Asset List

### 🚁 Drone (DronePlayer mesh)

**Primary — use this one:**

| Asset | Author | BlenderKit ID | Link |
|---|---|---|---|
| Sci-fi military drone | Eleanie | `392ddba1-f9ed-41b3-9bfb-02b1c01de592` | [View](https://www.blenderkit.com/asset-gallery-detail/392ddba1-f9ed-41b3-9bfb-02b1c01de592/) |

Hardsurface military drone with a rotating turret — reads as a security asset
immediately. Flat enough profile to work well from an isometric camera angle.
Export turret as a separate mesh so it can rotate to face the aim direction in Godot.

**Alternate / player color variants:**

| Asset | Author | BlenderKit ID | Link |
|---|---|---|---|
| Sci-Fi Drone 1 | Pastean Narcis Dan | `893fca4d-d299-4884-a59b-82c9d61c7104` | [View](https://www.blenderkit.com/asset-gallery-detail/893fca4d-d299-4884-a59b-82c9d61c7104/) |
| Sci fi drone | — | `066bfb32-0226-44fb-b282-801f21805826` | [View](https://www.blenderkit.com/asset-gallery-detail/066bfb32-0226-44fb-b282-801f21805826/) |

Use the alternates for visual differentiation across the 4 player color slots
(apply per-player `albedo_color` tint in Godot at runtime; same mesh, different material instance).

---

### 🏃 Escapees

| Escapee Type | Asset | Author | BlenderKit ID | Link |
|---|---|---|---|---|
| Basic Runner (MVP) | Sci-fi Droid Robot | 3DAssets Kit | `45ee98c2-d943-4cd8-bbc7-48e12c134040` | [View](https://www.blenderkit.com/asset-gallery-detail/45ee98c2-d943-4cd8-bbc7-48e12c134040/) |
| Tank (post-MVP) | Sci-fi Robot | peeraphon viriyahirunpaiboon | `2643df84-14fc-4293-9708-c19528c005c6` | [View](https://www.blenderkit.com/asset-gallery-detail/2643df84-14fc-4293-9708-c19528c005c6/) |

The Sci-fi Droid Robot is tagged "air, fighter, droid, security, military" — it
reads as exactly what an escapee security unit should look like. The Sci-fi Robot is
rigged with 2K textures and has a heavier build, perfect for the Tank type's larger
collision shape.

**Implementation note**: Escapees need a red emissive halo (REQ_07). Apply the
**Edge Emission** material (see Materials section) to a slightly-scaled-up duplicate
mesh, set emission color `#ff1744`, and attach it as a child of the EscapeeEntity node.

---

### 🏗️ Arena Environment

#### Floor

| Asset | Author | BlenderKit ID | Link | Use |
|---|---|---|---|---|
| Corridor SciFi Floor Tile | Klo Works | `a7cef16b-ab3d-4ddb-9776-8467363ebf86` | [View](https://www.blenderkit.com/asset-gallery-detail/a7cef16b-ab3d-4ddb-9776-8467363ebf86/) | Tile across 60×60m arena floor; PBR, fully tileable |
| Black Metal Floor Pattern | Vaishakh Vinod | `7947de29-245b-4a0a-bb5d-55edc7528aaf` | [View](https://www.blenderkit.com/asset-gallery-detail/7947de29-245b-4a0a-bb5d-55edc7528aaf/) | Secondary floor zone variation; containment lane marking |

The SciFi Floor Tile is the primary — it has a trim/corridor motif that visually
defines lane boundaries when tiled with offset rows. Use the Black Metal Floor Pattern
in the central staging area to differentiate it from the combat zone.

#### Containment Lanes / Corridors

| Asset | Author | BlenderKit ID | Link |
|---|---|---|---|
| Sci fi Corridor | Yasin Gohary | `7e8ce7fe-855a-4af0-a48a-853b203b90bd` | [View](https://www.blenderkit.com/asset-gallery-detail/7e8ce7fe-855a-4af0-a48a-853b203b90bd/) |

Built with an array modifier — export as a flat strip and orient it along each of
the 4 containment lane Path3D nodes. Keep side walls low (~1m) so the drone camera
can see over them.

#### Staging Platform (drone spawn area)

| Asset | Author | BlenderKit ID | Link |
|---|---|---|---|
| Sci Fi Building with Interior | OuterSpaceSimon | `393e0556-34d7-40d3-8475-a805bc7352ff` | [View](https://www.blenderkit.com/asset-gallery-detail/393e0556-34d7-40d3-8475-a805bc7352ff/) |

Originally a moonbase building — use just the flat roof platform + exterior shell
as the drone staging pad. The airlock aesthetic fits the "blacksite" briefing area.
Discard the interior mesh to save polys; the camera never enters it.

---

### 🔴 Perimeter / Force Field

These are the most game-critical visual elements — the perimeter wall is what players
watch to measure threat.

| Asset | Author | BlenderKit ID | Link | Use |
|---|---|---|---|---|
| Force field fx | Pikademia | `f214b442-ea72-47c9-a5b5-6db6bf9afef0` | [View](https://www.blenderkit.com/asset-gallery-detail/f214b442-ea72-47c9-a5b5-6db6bf9afef0/) | **Primary perimeter wall** — procedural, scales to any length |
| Force Field - Animated | Matthew Ames | `79360681-15ea-4a45-9c72-8d96bb07f373` | [View](https://www.blenderkit.com/asset-gallery-detail/79360681-15ea-4a45-9c72-8d96bb07f373/) | **BreachZone indicator** — animated shield that pulses red on breach |
| Blue Sci-Fi Portal Loop Animation | Menghour Nhoek | `0fdf7246-210e-4d88-9f75-23c8b2d9ff3c` | [View](https://www.blenderkit.com/asset-gallery-detail/0fdf7246-210e-4d88-9f75-23c8b2d9ff3c/) | Breach zone gateway visual — looping blue → red swap on alert |

**Godot workflow for force field**: Export the `Force field fx` mesh, import as a
`MeshInstance3D`, and drive the `emission_energy` uniform via GDScript:

```gdscript
# In PerimeterBreach script
func _on_escapee_entered():
    force_field_mat.emission = Color("#ff1744")   # red
    force_field_mat.emission_energy = 3.0
    # tween back to calm blue after 2s
```

---

### 🎨 Materials

These are applied in Blender, baked to PBR texture maps, and imported into Godot
as image textures on `StandardMaterial3D`.

| Material | Author | BlenderKit ID | Link | Applied to |
|---|---|---|---|---|
| Dark sci-fi wall | Adhe e | `28c75d32-33ae-43ab-a703-e998e0146a50` | [View](https://www.blenderkit.com/asset-gallery-detail/28c75d32-33ae-43ab-a703-e998e0146a50/) | Perimeter walls, structural panels |
| Sci-Fi Panel 20 | Abdelrahman Mohamed | `c2fc9cab-4d81-4ff8-ac14-18250262cf40` | [View](https://www.blenderkit.com/asset-gallery-detail/c2fc9cab-4d81-4ff8-ac14-18250262cf40/) | Drone body (4K Substance Designer) |
| Dark Steel | Share Textures | `f170e0bf-f784-482e-86eb-1d7e307a22cc` | [View](https://www.blenderkit.com/asset-gallery-detail/f170e0bf-f784-482e-86eb-1d7e307a22cc/) | Arena wall base / structural members |
| Sci fi Wall | Share Textures | `8c8f39f0-0dac-4feb-a54b-bbe3f17f8bc6` | [View](https://www.blenderkit.com/asset-gallery-detail/8c8f39f0-0dac-4feb-a54b-bbe3f17f8bc6/) | Corridor side walls (swap purple → cyan emissive in Godot) |
| **Edge Emission** | Paco Salas | `e429774b-6d15-4152-b347-862d1826a2c2` | [View](https://www.blenderkit.com/asset-gallery-detail/e429774b-6d15-4152-b347-862d1826a2c2/) | **Escapee threat halo** + drone ready-state glow |
| Glow in Dark AO Shader | Paco Salas | `8af3c5dd-eb8c-44c3-8524-003976076288` | [View](https://www.blenderkit.com/asset-gallery-detail/8af3c5dd-eb8c-44c3-8524-003976076288/) | Drone barrel charge glow (AO-driven neon) |

**Edge Emission** is the standout — it highlights edges procedurally with a neon glow.
Use it at `#ff1744` on escapees and `#00d4ff` on drones. Since it's a Blender shader
node material, bake the edge mask to a texture for Godot, then drive emission color
from GDScript.

---

### 🌆 HDRI (Scene Lighting)

| Asset | Author | BlenderKit ID | Link | Notes |
|---|---|---|---|---|
| City street (night) | Ryder Booth | `6d882058-7aa3-4853-90fd-47a33ca1785e` | [View](https://www.blenderkit.com/asset-gallery-detail/6d882058-7aa3-4853-90fd-47a33ca1785e/) | Night urban HDRI for ambient lighting pass |

Use this HDRI in Blender when baking material textures to get accurate ambient light
on the dark metallic surfaces. In Godot, replace the HDRI with a `WorldEnvironment`
node using a solid dark ambient + directional "overhead fluorescent" light as per REQ_07.

---

## Folder Structure (post-export)

```
assets/blacksite/
├── BLENDERKIT_ASSET_MAPPING.md     ← this file
├── blender_export_to_glb.py        ← run in Blender to batch-export
├── models/
│   └── _blenderkit_exports/
│       ├── drone_military.glb          → DronePlayer MeshInstance3D
│       ├── drone_scifi1.glb            → alt drone skin
│       ├── drone_scifi2.glb            → alt drone skin
│       ├── escapee_droid.glb           → EscapeeRunner MeshInstance3D
│       ├── escapee_robot.glb           → EscapeeTank MeshInstance3D
│       ├── arena_floor_tile.glb        → tiled arena floor
│       ├── arena_corridor.glb          → containment lane strip
│       ├── arena_staging_platform.glb  → drone spawn pad
│       ├── perimeter_forcefield.glb    → perimeter wall mesh
│       └── breach_zone_portal.glb      → breach zone indicator
└── textures/
    └── _blenderkit_bakes/
        ├── mat_dark_scifi_wall_*.png   → albedo/rough/metal/normal
        ├── mat_scifi_panel20_*.png
        ├── mat_dark_steel_*.png
        ├── mat_scifi_floor_*.png
        └── mat_edge_emission_mask.png  → grayscale edge mask for Godot shader
```

---

## BlenderKit vs Kenney: Division of Labor

| Layer | Source | Reason |
|---|---|---|
| Drone mesh (hero) | **BlenderKit** | Needs hardsurface detail visible at isometric distance |
| Escapee meshes | **BlenderKit** | Character readability depends on silhouette fidelity |
| Force field / perimeter | **BlenderKit** | Animated shaders not available in Kenney's static meshes |
| PBR surface materials | **BlenderKit** | 4K Substance Designer quality for closeup drone/unit surfaces |
| Arena floor/wall scaffolding | **Kenney** | Fast to tile, performant, easy to set up in Godot |
| Arena modular structures | **Kenney** | Space Kit covers pillars, rails, covers at the right scale |
| HUD / UI | **Kenney** | UI Pack Sci-Fi is 2D; BlenderKit has no equivalent |
| Audio | **Kenney** | BlenderKit has no audio assets |
| HDRI lighting (bake only) | **BlenderKit** | Used in Blender for material baking; not shipped in game |
