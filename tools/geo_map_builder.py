"""
geo_map_builder.py — Caribbean GeoJSON → tile grid
Run once:  python tools/geo_map_builder.py
Output:    assets/maps/caribbean.json

Dependencies: shapely, numpy
  pip install shapely numpy
"""

import json
import os
import sys
import urllib.request

# ── Config ────────────────────────────────────────────────────────────────────
GEOJSON_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_10m_land.geojson"
)
BBOX_LON_MIN, BBOX_LON_MAX = -100.0, -55.0
BBOX_LAT_MIN, BBOX_LAT_MAX =   -5.0,  35.0
GRID_W, GRID_H = 256, 228
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "maps", "caribbean.json",
)

# Tile type constants (must match IsoTerrainRenderer)
T_DEEP  = 0
T_WATER = 1
T_SAND  = 2

# ── Step 1: Download GeoJSON ───────────────────────────────────────────────────
print("Downloading Natural Earth land GeoJSON …")
with urllib.request.urlopen(GEOJSON_URL) as resp:
    raw = resp.read()
print(f"  downloaded {len(raw):,} bytes")

geojson = json.loads(raw)

# ── Step 2: Build land union clipped to Caribbean bbox ───────────────────────
try:
    from shapely.geometry import shape, box
    from shapely.ops import unary_union
except ImportError:
    sys.exit("ERROR: shapely not installed — run: pip install shapely numpy")

caribbean_box = box(BBOX_LON_MIN, BBOX_LAT_MIN, BBOX_LON_MAX, BBOX_LAT_MAX)
land_polys = []
for feature in geojson["features"]:
    try:
        geom = shape(feature["geometry"])
        clipped = geom.intersection(caribbean_box)
        if not clipped.is_empty:
            land_polys.append(clipped)
    except Exception:
        pass

print(f"  {len(land_polys)} land features intersect Caribbean bbox")
all_land = unary_union(land_polys)
print("  unary_union complete")

# ── Step 3 + 4: Classify tiles ───────────────────────────────────────────────
import numpy as np
from shapely.geometry import Point

print(f"Classifying {GRID_W}×{GRID_H} tiles …")
is_land = np.zeros((GRID_H, GRID_W), dtype=bool)

for ty in range(GRID_H):
    if ty % 16 == 0:
        print(f"  row {ty}/{GRID_H}")
    for tx in range(GRID_W):
        lon = BBOX_LON_MIN + (tx + 0.5) / GRID_W * (BBOX_LON_MAX - BBOX_LON_MIN)
        lat = BBOX_LAT_MAX - (ty + 0.5) / GRID_H * (BBOX_LAT_MAX - BBOX_LAT_MIN)
        if Point(lon, lat).within(all_land):
            is_land[ty, tx] = True

# ── Step 5: Manhattan distance transform → tile depth ────────────────────────
print("Computing distance transform …")

INF = 10 ** 9
dist = np.full((GRID_H, GRID_W), INF, dtype=np.int32)
dist[is_land] = 0

# Forward sweeps
for ty in range(GRID_H):
    for tx in range(GRID_W):
        if is_land[ty, tx]:
            dist[ty, tx] = 0
            continue
        best = INF
        if ty > 0:
            best = min(best, dist[ty - 1, tx] + 1)
        if tx > 0:
            best = min(best, dist[ty, tx - 1] + 1)
        dist[ty, tx] = best

for ty in range(GRID_H - 1, -1, -1):
    for tx in range(GRID_W - 1, -1, -1):
        if is_land[ty, tx]:
            continue
        best = dist[ty, tx]
        if ty < GRID_H - 1:
            best = min(best, dist[ty + 1, tx] + 1)
        if tx < GRID_W - 1:
            best = min(best, dist[ty, tx + 1] + 1)
        dist[ty, tx] = best

# Backward sweeps (ensure all 4 directions)
for ty in range(GRID_H):
    for tx in range(GRID_W):
        if is_land[ty, tx]:
            continue
        best = dist[ty, tx]
        if ty > 0:
            best = min(best, dist[ty - 1, tx] + 1)
        if tx > 0:
            best = min(best, dist[ty, tx - 1] + 1)
        dist[ty, tx] = best

for ty in range(GRID_H - 1, -1, -1):
    for tx in range(GRID_W - 1, -1, -1):
        if is_land[ty, tx]:
            continue
        best = dist[ty, tx]
        if ty < GRID_H - 1:
            best = min(best, dist[ty + 1, tx] + 1)
        if tx < GRID_W - 1:
            best = min(best, dist[ty, tx + 1] + 1)
        dist[ty, tx] = best

tiles_flat = []
for ty in range(GRID_H):
    for tx in range(GRID_W):
        d = int(dist[ty, tx])
        if d == 0:
            tiles_flat.append(T_SAND)
        elif d <= 3:
            tiles_flat.append(T_WATER)
        else:
            tiles_flat.append(T_DEEP)

# ── Step 6: Spawn selection ───────────────────────────────────────────────────
print("Selecting spawn points …")

ZONE_COLS, ZONE_ROWS = 4, 2
spawns = []

for zr in range(ZONE_ROWS):
    for zc in range(ZONE_COLS):
        # Centre of this zone
        cx = int((zc + 0.5) * GRID_W / ZONE_COLS)
        cy = int((zr + 0.5) * GRID_H / ZONE_ROWS)

        # Spiral outward until T_DEEP found
        found = None
        for radius in range(0, max(GRID_W, GRID_H)):
            for dx in range(-radius, radius + 1):
                for dy in range(-radius, radius + 1):
                    if abs(dx) != radius and abs(dy) != radius:
                        continue
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < GRID_W and 0 <= ny < GRID_H:
                        if tiles_flat[ny * GRID_W + nx] == T_DEEP:
                            found = [nx, ny]
                            break
                if found:
                    break
            if found:
                break
        if found:
            spawns.append(found)
        else:
            spawns.append([cx, cy])

print(f"  spawns: {spawns}")

# ── Step 7: Write JSON ────────────────────────────────────────────────────────
output = {
    "width":  GRID_W,
    "height": GRID_H,
    "tiles":  tiles_flat,
    "spawns": spawns,
}

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
with open(OUTPUT_PATH, "w") as f:
    json.dump(output, f, separators=(",", ":"))

print(f"Written: {OUTPUT_PATH}")
print(f"  tiles array length: {len(tiles_flat)} (expected {GRID_W * GRID_H})")
print(f"  spawns: {len(spawns)} entries")
land_count = tiles_flat.count(T_SAND)
water_count = tiles_flat.count(T_WATER)
deep_count  = tiles_flat.count(T_DEEP)
print(f"  T_SAND={land_count}, T_WATER={water_count}, T_DEEP={deep_count}")
