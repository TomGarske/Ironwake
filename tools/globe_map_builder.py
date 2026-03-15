"""
globe_map_builder.py — Natural Earth GeoJSON → 1024×512 globe texture PNG
Run once:  python tools/globe_map_builder.py
Output:    assets/maps/globe.png

Dependencies: shapely>=2.0, numpy
  pip install shapely numpy
"""

import os
import struct
import sys
import urllib.request
import zlib

# ── Config ────────────────────────────────────────────────────────────────────
IMG_W, IMG_H = 1024, 512
NE_LAND_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_land.geojson"
)
NE_GLACIER_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_glaciated_areas.geojson"
)
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "maps", "globe.png",
)

# ── Terrain type constants ─────────────────────────────────────────────────────
T_DEEP_OCEAN = 0  # > 20 pixels from land
T_OCEAN      = 1  # 8–20 pixels from land
T_SHALLOW    = 2  # 1–7 pixels from land
T_COAST      = 3  # land edge (eroded away)
T_LAND       = 4  # interior land
T_ICE        = 5  # glacier / polar cap

# ── Terrain RGB colours ────────────────────────────────────────────────────────
COLORS = {
    T_DEEP_OCEAN: (15,  40,  80),   # #0F2850 abyssal navy
    T_OCEAN:      (30,  80,  145),  # #1E5091 open shipping lanes
    T_SHALLOW:    (55,  130, 185),  # #3782B9 continental shelf
    T_COAST:      (194, 178, 128),  # #C2B280 sandy coastline
    T_LAND:       (100, 130, 75),   # #64824B olive-green continent
    T_ICE:        (230, 240, 248),  # #E6F0F8 polar white-blue
}

INF = 10 ** 9


# ── Dependency check ───────────────────────────────────────────────────────────
try:
    import numpy as np
    from shapely import contains_xy
    from shapely.geometry import shape
    from shapely.ops import unary_union
except ImportError:
    sys.exit("ERROR: shapely>=2.0 and numpy required — run: pip install shapely numpy")


# ── Step 1: Download GeoJSON ───────────────────────────────────────────────────
def _download_json(url: str, label: str) -> list:
    print(f"Downloading {label} …")
    with urllib.request.urlopen(url) as resp:
        raw = resp.read()
    print(f"  {len(raw):,} bytes")
    import json
    return json.loads(raw)["features"]


# ── Step 2: Build Shapely geometry unions ─────────────────────────────────────
def _build_union(features):
    polys = []
    for feat in features:
        try:
            geom = shape(feat["geometry"])
            if not geom.is_empty:
                polys.append(geom)
        except Exception:
            pass
    return unary_union(polys)


# ── Step 3: Rasterize via contains_xy ─────────────────────────────────────────
def _rasterize(union_geom, lon_grid, lat_grid, W, H) -> "np.ndarray":
    print("  rasterizing …")
    return contains_xy(union_geom, lon_grid.ravel(), lat_grid.ravel()).reshape(H, W)


# ── Step 4: Vectorized Manhattan distance transform ───────────────────────────
def _distance_transform(is_land: "np.ndarray", H: int, W: int) -> "np.ndarray":
    print("Computing distance transform …")
    dist = np.where(is_land, 0, INF).astype(np.int32)

    # Forward sweeps (top→bottom, left→right)
    for ty in range(1, H):
        dist[ty] = np.minimum(dist[ty], dist[ty - 1] + 1)
    for tx in range(1, W):
        dist[:, tx] = np.minimum(dist[:, tx], dist[:, tx - 1] + 1)

    # Backward sweeps (bottom→top, right→left)
    for ty in range(H - 2, -1, -1):
        dist[ty] = np.minimum(dist[ty], dist[ty + 1] + 1)
    for tx in range(W - 2, -1, -1):
        dist[:, tx] = np.minimum(dist[:, tx], dist[:, tx + 1] + 1)

    return dist


# ── Step 5: Classify pixels ───────────────────────────────────────────────────
def _classify(is_land, is_ice, dist, H, W) -> "np.ndarray":
    print("Classifying pixels …")

    # Erode land 1px (4-neighbour AND) → coastal fringe
    land_eroded = (
        is_land
        & np.roll(is_land,  1, axis=0)
        & np.roll(is_land, -1, axis=0)
        & np.roll(is_land,  1, axis=1)
        & np.roll(is_land, -1, axis=1)
    )
    is_coast = is_land & ~land_eroded  # pixels eroded away = coastal ring

    terrain = np.empty((H, W), dtype=np.uint8)
    terrain[:] = T_DEEP_OCEAN         # default: > 20 px from land

    terrain[dist <= 20] = T_OCEAN     # 8–20 → ocean (overwrite deep)
    terrain[dist < 8]   = T_SHALLOW   # 1–7  → shallow (overwrite ocean)
    terrain[is_coast]   = T_COAST     # land edge ring
    terrain[land_eroded] = T_LAND     # interior land
    terrain[is_ice]     = T_ICE       # overrides everything

    return terrain


# ── Step 6: Render to RGB array ───────────────────────────────────────────────
def _render_rgb(terrain, H, W) -> "np.ndarray":
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    for t_type, color in COLORS.items():
        mask = terrain == t_type
        rgb[mask] = color
    return rgb


# ── Step 7: Write PNG (stdlib only — no Pillow) ───────────────────────────────
def write_png(path: str, rgb: "np.ndarray", W: int, H: int) -> None:
    def _chunk(chunk_type: bytes, data: bytes) -> bytes:
        length = struct.pack(">I", len(data))
        body   = chunk_type + data
        crc    = struct.pack(">I", zlib.crc32(body) & 0xFFFF_FFFF)
        return length + body + crc

    # IHDR: width, height, bit depth=8, colour type=2 (RGB), ...
    ihdr_data = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)

    # Raw image data: prepend filter byte 0 (None) to each row
    raw_rows = b"".join(
        b"\x00" + bytes(rgb[y].tobytes()) for y in range(H)
    )
    idat_data = zlib.compress(raw_rows, level=6)

    signature = b"\x89PNG\r\n\x1a\n"
    content = (
        signature
        + _chunk(b"IHDR", ihdr_data)
        + _chunk(b"IDAT", idat_data)
        + _chunk(b"IEND", b"")
    )

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(content)
    print(f"Written: {path}  ({os.path.getsize(path):,} bytes)")


# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    W, H = IMG_W, IMG_H

    # 1. Download
    land_features    = _download_json(NE_LAND_URL,    "ne_50m_land")
    glacier_features = _download_json(NE_GLACIER_URL, "ne_50m_glaciated_areas")

    # 2. Build unions
    print("Building land union …")
    all_land = _build_union(land_features)
    print("Building glacier union …")
    all_glaciers = _build_union(glacier_features)

    # 3. Build pixel coordinate grids (lon/lat centres)
    print(f"Building {W}×{H} pixel coordinate grids …")
    xs = (np.arange(W) + 0.5) / W * 360.0 - 180.0   # lon: −180 → +180
    ys = 90.0 - (np.arange(H) + 0.5) / H * 180.0    # lat: +90 → −90
    lon_grid, lat_grid = np.meshgrid(xs, ys)

    # 4. Rasterize land and glacier masks
    print("Rasterizing land mask …")
    is_land    = _rasterize(all_land,    lon_grid, lat_grid, W, H)
    print("Rasterizing glacier mask …")
    is_glacier = _rasterize(all_glaciers, lon_grid, lat_grid, W, H)

    # 5. Polar ice
    is_polar = (lat_grid > 70.0) | (lat_grid < -60.0)
    is_ice   = is_glacier | (is_land & is_polar)

    # 6. Distance transform
    dist = _distance_transform(is_land, H, W)

    # 7. Classify
    terrain = _classify(is_land, is_ice, dist, H, W)

    # 8. Count & report
    for t_type, label in [
        (T_DEEP_OCEAN, "T_DEEP_OCEAN"),
        (T_OCEAN,      "T_OCEAN"),
        (T_SHALLOW,    "T_SHALLOW"),
        (T_COAST,      "T_COAST"),
        (T_LAND,       "T_LAND"),
        (T_ICE,        "T_ICE"),
    ]:
        print(f"  {label}: {int(np.sum(terrain == t_type)):,}")

    # 9. Render + write
    rgb = _render_rgb(terrain, H, W)
    write_png(OUTPUT_PATH, rgb, W, H)
    print("Done.")


if __name__ == "__main__":
    main()
