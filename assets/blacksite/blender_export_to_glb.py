"""
blender_export_to_glb.py
========================
Blacksite Containment — BlenderKit batch downloader + GLB exporter

USAGE (two ways):
  A) Blender Scripting tab: open this file, click Run Script.
  B) Command line (headless):
       blender --background --python path/to/blender_export_to_glb.py

PREREQUISITES:
  - Blender 4.x with the BlenderKit addon installed and signed in.
  - Run this from inside the BurnBridgers project folder, OR set
    OUTPUT_DIR below to an absolute path.

WHAT IT DOES:
  For each asset in ASSETS:
    1. Clears the scene.
    2. Downloads the asset from BlenderKit (requires internet + addon).
    3. Selects all imported objects.
    4. Exports them as a single .glb to OUTPUT_DIR.
  For each material in MATERIALS:
    1. Applies it to a 2m plane.
    2. Bakes albedo, roughness, metallic, and normal maps at BAKE_RESOLUTION.
    3. Saves PNGs to TEXTURE_OUTPUT_DIR.
"""

import bpy
import os
import sys
import time
import socket


def _wait_for_blenderkit_client(host="127.0.0.1", port=62485, timeout=30):
    """Block until the BlenderKit client is accepting connections, or raise."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=1):
                print(f"[blender_export] BlenderKit client ready on {host}:{port}")
                return
        except OSError:
            print(f"[blender_export] Waiting for BlenderKit client on port {port}...")
            time.sleep(1)
    raise RuntimeError(
        f"BlenderKit client did not start on port {port} within {timeout}s.\n"
        "Make sure the BlenderKit addon is enabled and you are signed in."
    )


_wait_for_blenderkit_client()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Resolve output dirs relative to this script's location
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR         = os.path.join(_SCRIPT_DIR, "models", "_blenderkit_exports")
TEXTURE_OUTPUT_DIR = os.path.join(_SCRIPT_DIR, "textures", "_blenderkit_bakes")
BAKE_RESOLUTION    = 2048   # px per side for texture bakes (2048 = 2K)

# ---------------------------------------------------------------------------
# Assets to download and export as GLB
# Each entry: output filename (no extension), BlenderKit asset_base_id, notes
# ---------------------------------------------------------------------------
ASSETS = [
    # --- Drones ---
    {
        "out":  "drone_military",
        "id":   "392ddba1-f9ed-41b3-9bfb-02b1c01de592",
        "note": "Primary DronePlayer mesh — Sci-fi military drone by Eleanie"
    },
    {
        "out":  "drone_scifi1",
        "id":   "893fca4d-d299-4884-a59b-82c9d61c7104",
        "note": "Alternate drone skin — Sci-Fi Drone 1 by Pastean Narcis Dan"
    },
    {
        "out":  "drone_scifi2",
        "id":   "066bfb32-0226-44fb-b282-801f21805826",
        "note": "Alternate drone skin — Sci fi drone"
    },
    # --- Escapees ---
    {
        "out":  "escapee_droid",
        "id":   "45ee98c2-d943-4cd8-bbc7-48e12c134040",
        "note": "Basic Runner — Sci-fi Droid Robot by 3DAssets Kit"
    },
    {
        "out":  "escapee_robot",
        "id":   "2643df84-14fc-4293-9708-c19528c005c6",
        "note": "Tank type — Sci-fi Robot by peeraphon (rigged, 2K textures)"
    },
    # --- Arena ---
    {
        "out":  "arena_floor_tile",
        "id":   "a7cef16b-ab3d-4ddb-9776-8467363ebf86",
        "note": "Arena floor — Corridor SciFi Floor Tile by Klo Works (PBR tileable)"
    },
    {
        "out":  "arena_corridor",
        "id":   "7e8ce7fe-855a-4af0-a48a-853b203b90bd",
        "note": "Containment lane strip — Sci fi Corridor by Yasin Gohary"
    },
    {
        "out":  "arena_staging_platform",
        "id":   "393e0556-34d7-40d3-8475-a805bc7352ff",
        "note": "Drone staging pad — Sci Fi Building with Interior by OuterSpaceSimon"
    },
    # --- Perimeter / Force Field ---
    {
        "out":  "perimeter_forcefield",
        "id":   "f214b442-ea72-47c9-a5b5-6db6bf9afef0",
        "note": "Perimeter wall — Force field fx by Pikademia (procedural)"
    },
    {
        "out":  "perimeter_forcefield_animated",
        "id":   "79360681-15ea-4a45-9c72-8d96bb07f373",
        "note": "BreachZone indicator — Force Field Animated by Matthew Ames"
    },
    {
        "out":  "breach_zone_portal",
        "id":   "0fdf7246-210e-4d88-9f75-23c8b2d9ff3c",
        "note": "Breach gateway — Blue Sci-Fi Portal Loop by Menghour Nhoek"
    },
]

# ---------------------------------------------------------------------------
# Materials to bake to textures
# Each entry: slug prefix for output files, BlenderKit asset_base_id
# ---------------------------------------------------------------------------
MATERIALS = [
    {
        "out":  "dark_scifi_wall",
        "id":   "28c75d32-33ae-43ab-a703-e998e0146a50",
        "note": "Perimeter walls / structural panels"
    },
    {
        "out":  "scifi_panel20",
        "id":   "c2fc9cab-4d81-4ff8-ac14-18250262cf40",
        "note": "Drone body (4K Substance Designer)"
    },
    {
        "out":  "dark_steel",
        "id":   "f170e0bf-f784-482e-86eb-1d7e307a22cc",
        "note": "Arena wall base / structural members"
    },
    {
        "out":  "scifi_wall_emissive",
        "id":   "8c8f39f0-0dac-4feb-a54b-bbe3f17f8bc6",
        "note": "Corridor side walls (emissive — swap purple to cyan in Godot)"
    },
    {
        "out":  "edge_emission_mask",
        "id":   "e429774b-6d15-4152-b347-862d1826a2c2",
        "note": "Escapee threat halo + drone glow (bake edge mask channel only)"
    },
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def ensure_dirs():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(TEXTURE_OUTPUT_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes) + list(bpy.data.materials) + list(bpy.data.lights) + list(bpy.data.cameras):
        try:
            bpy.data.meshes.remove(block) if hasattr(bpy.data, 'meshes') and block in bpy.data.meshes.values() else None
        except Exception:
            pass


def download_blenderkit_asset(asset_base_id, timeout=60):
    """Download a BlenderKit asset by base ID, polling until objects appear in scene."""
    try:
        before = set(o.name for o in bpy.context.scene.objects)
        result = bpy.ops.scene.blenderkit_download(asset_base_id=asset_base_id)
        print(f"    Operator result: {result}")
    except AttributeError:
        print(f"  [WARN] blenderkit_download operator not found. "
              f"Is the BlenderKit addon installed and active?")
        return False
    except Exception as e:
        print(f"  [WARN] Download failed: {e}")
        return False

    # Poll until new objects appear, calling the BlenderKit task pump each tick
    deadline = time.time() + timeout
    app_id = getattr(__builtins__, '_bk_app_id', None) or (lambda: None)()
    pump = getattr(__builtins__, '_bk_pump', None)
    while time.time() < deadline:
        time.sleep(0.5)
        if pump and app_id:
            pump(app_id)
        after = set(o.name for o in bpy.context.scene.objects)
        if after - before:
            print(f"    Objects appeared: {after - before}")
            return True
    print(f"  [WARN] Timeout waiting for asset {asset_base_id} to appear in scene.")
    return False


def export_selected_as_glb(filepath):
    """Export all scene objects as a single GLB."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_yup=True,               # Godot expects Y-up
        export_apply=True,             # Apply modifiers (important for array corridor)
        export_animations=True,        # Preserve any embedded animations
        export_morph=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
    )


def make_bake_plane():
    """Create a 2x2m plane as the bake target."""
    bpy.ops.mesh.primitive_plane_add(size=2)
    return bpy.context.active_object


def bake_material_to_textures(mat_out_prefix, resolution):
    """
    Bake albedo, roughness, metallic, and normal maps for all materials
    on selected objects. Saves PNGs to TEXTURE_OUTPUT_DIR.
    """
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 64  # Low for speed; raise to 256 for final bake

    bake_passes = [
        ('DIFFUSE',  f"{mat_out_prefix}_albedo.png",   {'use_pass_direct': False, 'use_pass_indirect': False, 'use_pass_color': True}),
        ('ROUGHNESS', f"{mat_out_prefix}_roughness.png", {}),
        ('GLOSSY',   f"{mat_out_prefix}_metallic.png",  {'use_pass_direct': False, 'use_pass_indirect': False, 'use_pass_color': True}),
        ('NORMAL',   f"{mat_out_prefix}_normal.png",    {}),
        ('EMIT',     f"{mat_out_prefix}_emission.png",  {}),
    ]

    obj = bpy.context.active_object
    if not obj or not obj.data.materials:
        print(f"  [WARN] No materials on object — skipping bake.")
        return

    for bake_type, filename, extra_kwargs in bake_passes:
        img = bpy.data.images.new(filename, width=resolution, height=resolution, float_buffer=True)
        img.file_format = 'PNG'
        img.filepath_raw = os.path.join(TEXTURE_OUTPUT_DIR, filename)

        # Add image texture node to each material for bake target
        for mat in obj.data.materials:
            if not mat or not mat.use_nodes:
                continue
            nodes = mat.node_tree.nodes
            img_node = nodes.new('ShaderNodeTexImage')
            img_node.image = img
            img_node.select = True
            nodes.active = img_node

        try:
            bpy.ops.object.bake(type=bake_type, **extra_kwargs)
            img.save()
            print(f"  Baked: {filename}")
        except Exception as e:
            print(f"  [WARN] Bake '{bake_type}' failed: {e}")
        finally:
            # Remove the temporary image texture node
            for mat in obj.data.materials:
                if not mat or not mat.use_nodes:
                    continue
                for node in list(mat.node_tree.nodes):
                    if node.type == 'TEX_IMAGE' and node.image == img:
                        mat.node_tree.nodes.remove(node)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run():
    ensure_dirs()

    print("\n" + "="*60)
    print("  Blacksite Containment — BlenderKit Exporter")
    print("="*60)

    # Check BlenderKit is available
    if not hasattr(bpy.ops, 'object') or not hasattr(bpy.ops.object, 'blenderkit_download'):
        print("\n[ERROR] BlenderKit addon operator not found.")
        print("  Please install and enable the BlenderKit addon, then re-run this script.")
        print("  Download: https://www.blenderkit.com/get-blenderkit/\n")
        # Continue anyway — the bake/export structure is still set up

    success_models = []
    failed_models  = []

    # --- Model assets ---
    print(f"\n[Models] Exporting {len(ASSETS)} assets to:\n  {OUTPUT_DIR}\n")
    for asset in ASSETS:
        out_path = os.path.join(OUTPUT_DIR, f"{asset['out']}.glb")
        print(f"  [{asset['out']}] {asset['note']}")

        if os.path.exists(out_path):
            print(f"    Skipping — already exported. Delete to re-export.")
            success_models.append(asset['out'])
            continue

        clear_scene()
        ok = download_blenderkit_asset(asset['id'])

        if not ok or len(bpy.context.scene.objects) == 0:
            print(f"    [FAIL] Nothing imported for {asset['id']}")
            failed_models.append(f"{asset['out']} ({asset['id']})")
            continue

        try:
            export_selected_as_glb(out_path)
            print(f"    Exported → {out_path}")
            success_models.append(asset['out'])
        except Exception as e:
            print(f"    [FAIL] Export error: {e}")
            failed_models.append(f"{asset['out']} — export error: {e}")

    # --- Material bakes ---
    print(f"\n[Materials] Baking {len(MATERIALS)} materials to:\n  {TEXTURE_OUTPUT_DIR}\n")
    success_mats = []
    failed_mats  = []

    for mat in MATERIALS:
        print(f"  [{mat['out']}] {mat['note']}")
        albedo_path = os.path.join(TEXTURE_OUTPUT_DIR, f"{mat['out']}_albedo.png")

        if os.path.exists(albedo_path):
            print(f"    Skipping — already baked.")
            success_mats.append(mat['out'])
            continue

        clear_scene()
        ok = download_blenderkit_asset(mat['id'])

        if not ok:
            failed_mats.append(f"{mat['out']} ({mat['id']})")
            continue

        plane = make_bake_plane()

        # Apply downloaded material to the plane
        # BlenderKit typically appends the material; find it by name or index
        downloaded_mats = [m for m in bpy.data.materials if m.name not in ('Dots Stroke',)]
        if downloaded_mats:
            plane.data.materials.clear()
            plane.data.materials.append(downloaded_mats[-1])
        else:
            print(f"    [WARN] No downloaded material found — bake may be blank.")

        try:
            bake_material_to_textures(mat['out'], BAKE_RESOLUTION)
            success_mats.append(mat['out'])
        except Exception as e:
            print(f"    [FAIL] Bake error: {e}")
            failed_mats.append(f"{mat['out']} — {e}")

    # --- Summary ---
    print("\n" + "="*60)
    print("  Summary")
    print("="*60)
    print(f"\nModels ({len(success_models)} ok, {len(failed_models)} failed):")
    for m in success_models:
        print(f"  + {m}")
    for m in failed_models:
        print(f"  - {m}")

    print(f"\nMaterials ({len(success_mats)} ok, {len(failed_mats)} failed):")
    for m in success_mats:
        print(f"  + {m}")
    for m in failed_mats:
        print(f"  - {m}")

    if failed_models or failed_mats:
        print("\nFor failed assets, download manually from the links in BLENDERKIT_ASSET_MAPPING.md")
        print("then File > Export > glTF 2.0 (.glb) to the _blenderkit_exports/ folder.")

    print(f"\nDone. GLBs → {OUTPUT_DIR}")
    print(f"Textures   → {TEXTURE_OUTPUT_DIR}\n")


run()
