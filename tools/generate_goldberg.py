#!/usr/bin/env python3
"""Generate a GP(M,0) Goldberg polyhedron edge map (4096x2048 equirectangular PNG).

Run from the repo root:
    python tools/generate_goldberg.py            # default M=32, Earth grid
    python tools/generate_goldberg.py --m 15 --prefix moon_  # M=15, Moon grid

Output: assets/maps/{prefix}goldberg_edges.png
        assets/data/{prefix}goldberg_data.json
"""

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
_parser = argparse.ArgumentParser(description="Generate Goldberg polyhedron assets")
_parser.add_argument("--m",      type=int, default=32,  dest="m_val",
                     help="Subdivision frequency (default 32)")
_parser.add_argument("--prefix", type=str, default="",   dest="prefix",
                     help="Output filename prefix, e.g. 'moon_'")
_args = _parser.parse_args()

# ---------------------------------------------------------------------------
# Constants (derived from CLI)
# ---------------------------------------------------------------------------
M = _args.m_val
PREFIX = _args.prefix
T = M * M
EXPECTED_FACES    = 10 * T + 2
EXPECTED_PENTS    = 12
EXPECTED_HEXES    = 10 * T - 10
EXPECTED_EDGES    = 30 * T

RENDER_W = 8192
RENDER_H = 4096
OUT_W    = 4096
OUT_H    = 2048
LINE_W   = 4     # pixels at render resolution → 2px effective after downsample


# ---------------------------------------------------------------------------
# Step 1 — Icosahedron
# ---------------------------------------------------------------------------
PHI = (1.0 + math.sqrt(5.0)) / 2.0

def _norm(v):
    x, y, z = v
    n = math.sqrt(x*x + y*y + z*z)
    return (x/n, y/n, z/n)

ICO_VERTS_RAW = [
    ( 0,  1,  PHI), ( 0, -1,  PHI), ( 0,  1, -PHI), ( 0, -1, -PHI),
    ( 1,  PHI,  0), (-1,  PHI,  0), ( 1, -PHI,  0), (-1, -PHI,  0),
    ( PHI,  0,  1), (-PHI,  0,  1), ( PHI,  0, -1), (-PHI,  0, -1),
]
ICO_VERTS = [_norm(v) for v in ICO_VERTS_RAW]

ICO_FACES = [
    (0,1,8),(0,8,4),(0,4,5),(0,5,9),(0,9,1),
    (1,6,8),(8,6,10),(8,10,4),(4,10,2),(4,2,5),
    (5,2,11),(5,11,9),(9,11,7),(9,7,1),(1,7,6),
    (3,6,7),(3,7,11),(3,11,2),(3,2,10),(3,10,6),
]


# ---------------------------------------------------------------------------
# Step 2 — Class-I geodesic subdivision at frequency M
# ---------------------------------------------------------------------------
def _key(v, decimals=6):
    """Round-trip safe dict key for a unit-sphere vertex."""
    return (round(v[0], decimals), round(v[1], decimals), round(v[2], decimals))

def subdivide_icosahedron(m):
    """Return (verts list, faces list of index-triples)."""
    vert_index = {}   # key → global index
    verts      = []
    faces      = []

    def get_or_add(v):
        k = _key(v)
        if k not in vert_index:
            vert_index[k] = len(verts)
            verts.append(v)
        return vert_index[k]

    for (ai, bi, ci) in ICO_FACES:
        A, B, C = ICO_VERTS[ai], ICO_VERTS[bi], ICO_VERTS[ci]
        # Build local grid of indices for this face
        local = {}
        for i in range(m + 1):
            for j in range(m + 1 - i):
                k = m - i - j
                x = (A[0]*k + B[0]*i + C[0]*j) / m
                y = (A[1]*k + B[1]*i + C[1]*j) / m
                z = (A[2]*k + B[2]*i + C[2]*j) / m
                p = _norm((x, y, z))
                local[(i, j)] = get_or_add(p)
        # Emit triangles
        for i in range(m):
            for j in range(m - i):
                a = local[(i,   j  )]
                b = local[(i+1, j  )]
                c = local[(i,   j+1)]
                faces.append((a, b, c))
                if i + j + 1 < m:
                    d = local[(i+1, j+1)]
                    faces.append((b, d, c))

    return verts, faces


# ---------------------------------------------------------------------------
# Step 3 — Dual = Goldberg polyhedron faces
# ---------------------------------------------------------------------------
def build_dual(verts, faces):
    """
    Returns (goldberg_faces, edges) where:
      goldberg_faces  — list of ordered lists of sphere-point tuples (the polygon vertices)
      edges           — set of frozenset({fa, fb}) face-index pairs sharing an edge
    """
    # Map each geodesic vertex → list of triangle indices containing it
    vert_to_tris = defaultdict(list)
    for fi, (a, b, c) in enumerate(faces):
        vert_to_tris[a].append(fi)
        vert_to_tris[b].append(fi)
        vert_to_tris[c].append(fi)

    # Triangle centroid on unit sphere
    def tri_centroid(fi):
        a, b, c = faces[fi]
        va, vb, vc = verts[a], verts[b], verts[c]
        cx = (va[0] + vb[0] + vc[0]) / 3.0
        cy = (va[1] + vb[1] + vc[1]) / 3.0
        cz = (va[2] + vb[2] + vc[2]) / 3.0
        return _norm((cx, cy, cz))

    centroids = [tri_centroid(fi) for fi in range(len(faces))]

    # For each geodesic vertex, build its Goldberg face (polygon of centroids)
    goldberg_faces = []
    for vi in range(len(verts)):
        tri_list = vert_to_tris[vi]
        # Sort triangles in cyclic angular order around the vertex
        vx, vy, vz = verts[vi]
        # Build two tangent vectors spanning the plane perpendicular to v.
        # Try Y-axis first; fall back to X-axis if nearly parallel to v.
        for ref in ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)):
            dot = ref[0]*vx + ref[1]*vy + ref[2]*vz
            tx, ty, tz = ref[0]-dot*vx, ref[1]-dot*vy, ref[2]-dot*vz
            if tx*tx + ty*ty + tz*tz > 1e-12:
                break
        t1 = _norm((tx, ty, tz))
        # t2 = v × t1
        t2 = (vy*t1[2]-vz*t1[1], vz*t1[0]-vx*t1[2], vx*t1[1]-vy*t1[0])

        def angle_of(fi):
            cx, cy, cz = centroids[fi]
            dx, dy, dz = cx-vx, cy-vy, cz-vz
            u = dx*t1[0]+dy*t1[1]+dz*t1[2]
            w = dx*t2[0]+dy*t2[1]+dz*t2[2]
            return math.atan2(w, u)

        sorted_tris = sorted(tri_list, key=angle_of)
        poly = [centroids[fi] for fi in sorted_tris]
        goldberg_faces.append(poly)

    # Build edge set: two Goldberg faces share an edge iff they share exactly
    # one geodesic triangle in their polygon vertex lists.
    # Equivalently, for each geodesic triangle, its 3 vertices define 3 pairs
    # of Goldberg faces — but we want the dual edge connecting centroid(fi) to
    # centroid(fj) for each pair of geodesic triangles sharing a geodesic edge.
    # Build from geodesic edge → the two triangles that border it.
    edge_to_tris = defaultdict(list)
    for fi, (a, b, c) in enumerate(faces):
        for e in (frozenset((a, b)), frozenset((b, c)), frozenset((a, c))):
            edge_to_tris[e].append(fi)

    dual_edges = set()
    for geo_edge, tri_pair in edge_to_tris.items():
        if len(tri_pair) == 2:
            fa, fb = tri_pair
            dual_edges.add(frozenset((fa, fb)))

    return goldberg_faces, centroids, dual_edges


# ---------------------------------------------------------------------------
# Step 4 — Equirectangular rendering
# ---------------------------------------------------------------------------
def to_lonlat(v):
    x, y, z = v
    lon = math.atan2(y, x)          # -π … +π
    lat = math.asin(max(-1.0, min(1.0, z)))  # -π/2 … +π/2
    return lon, lat

def to_pixel(lon, lat, W, H):
    px = (lon + math.pi) / (2.0 * math.pi) * W
    py = (math.pi / 2.0 - lat) / math.pi * H
    return px, py

N_SEGS = 8   # arc subdivisions per edge — keeps lines geodesic in the projection

def _draw_segment(draw, lon_a, lat_a, lon_b, lat_b, W, H, w):
    """Draw one straight segment, splitting at the antimeridian if needed."""
    if abs(lon_a - lon_b) > math.pi:
        lon_b_w = lon_b + (2 * math.pi if lon_a > lon_b else -2 * math.pi)
        if lon_b_w != lon_a:
            t = (math.pi * math.copysign(1, lon_a) - lon_a) / (lon_b_w - lon_a)
        else:
            t = 0.5
        t = max(0.0, min(1.0, t))
        lat_m = lat_a + t * (lat_b - lat_a)
        edge = math.pi * math.copysign(1, lon_a)
        draw.line([to_pixel(lon_a, lat_a, W, H), to_pixel(edge,  lat_m, W, H)],
                  fill=(255, 255, 255, 255), width=w)
        draw.line([to_pixel(-edge, lat_m, W, H), to_pixel(lon_b, lat_b, W, H)],
                  fill=(255, 255, 255, 255), width=w)
    else:
        draw.line([to_pixel(lon_a, lat_a, W, H), to_pixel(lon_b, lat_b, W, H)],
                  fill=(255, 255, 255, 255), width=w)

def draw_edge(draw, ca, cb, W, H, line_w):
    # Skip edges where both endpoints are within 1° of a pole
    _, lat_a = to_lonlat(ca)
    _, lat_b = to_lonlat(cb)
    if abs(lat_a) > math.radians(89) and abs(lat_b) > math.radians(89):
        return

    # Subdivide along the sphere arc so each sub-segment is projected correctly
    pts = [
        _norm((ca[0]*(1-t)+cb[0]*t, ca[1]*(1-t)+cb[1]*t, ca[2]*(1-t)+cb[2]*t))
        for t in (i / N_SEGS for i in range(N_SEGS + 1))
    ]

    for i in range(N_SEGS):
        lon_a, lat_a = to_lonlat(pts[i])
        lon_b, lat_b = to_lonlat(pts[i + 1])
        _draw_segment(draw, lon_a, lat_a, lon_b, lat_b, W, H, line_w)


def render(centroids, dual_edges, out_path: Path):
    img  = Image.new("RGBA", (RENDER_W, RENDER_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cent_list = list(centroids)   # index matches triangle index
    for edge in dual_edges:
        fa, fb = tuple(edge)
        draw_edge(draw, cent_list[fa], cent_list[fb], RENDER_W, RENDER_H, LINE_W)

    img = img.resize((OUT_W, OUT_H), Image.LANCZOS)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(str(out_path))
    print(f"Saved {out_path}  ({OUT_W}×{OUT_H} RGBA)")


# ---------------------------------------------------------------------------
# Step 5 — JSON nav data export
# ---------------------------------------------------------------------------
def export_json(verts, goldberg_faces, geo_faces, out_path: Path):
    """Export per-face centroid, neighbour list, and polygon vertices.

    Goldberg face i corresponds to geodesic vertex i.  Two Goldberg faces are
    neighbours iff their geodesic vertices share a geodesic edge, i.e. they
    both appear in the same geodesic triangle.
    """
    adjacency: dict[int, set[int]] = defaultdict(set)
    for (a, b, c) in geo_faces:
        adjacency[a].add(b); adjacency[a].add(c)
        adjacency[b].add(a); adjacency[b].add(c)
        adjacency[c].add(a); adjacency[c].add(b)
    adjacency_lists = {k: sorted(v) for k, v in adjacency.items()}

    faces_data = []
    for i in range(len(goldberg_faces)):
        cx, cy, cz = verts[i]
        faces_data.append({
            "c": [round(cx, 6), round(cy, 6), round(cz, 6)],
            "n": adjacency_lists.get(i, []),
            "p": [[round(x, 6), round(y, 6), round(z, 6)]
                  for x, y, z in goldberg_faces[i]],
        })

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(str(out_path), "w") as f:
        json.dump({"faces": faces_data}, f, separators=(",", ":"))
    print(f"Saved {out_path}  ({len(faces_data)} faces)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f"GP({M},0) geodesic subdivision… (prefix='{PREFIX}')")
    verts, faces = subdivide_icosahedron(M)
    print(f"  Geodesic verts: {len(verts)}  (expected {EXPECTED_FACES})")
    print(f"  Geodesic faces: {len(faces)}  (expected {20 * T})")

    print("Building dual (Goldberg faces)…")
    goldberg_faces, centroids, dual_edges = build_dual(verts, faces)

    pent_count = sum(1 for f in goldberg_faces if len(f) == 5)
    hex_count  = sum(1 for f in goldberg_faces if len(f) == 6)
    other      = sum(1 for f in goldberg_faces if len(f) not in (5, 6))

    print(f"  Goldberg faces: {len(goldberg_faces)}")
    print(f"  Pentagons:      {pent_count}")
    print(f"  Hexagons:       {hex_count}")
    print(f"  Other:          {other}")
    print(f"  Dual edges:     {len(dual_edges)}")

    errors = []
    if len(goldberg_faces) != EXPECTED_FACES:
        errors.append(f"face count {len(goldberg_faces)} != {EXPECTED_FACES}")
    if pent_count != EXPECTED_PENTS:
        errors.append(f"pentagon count {pent_count} != {EXPECTED_PENTS}")
    if hex_count != EXPECTED_HEXES:
        errors.append(f"hexagon count {hex_count} != {EXPECTED_HEXES}")
    if len(dual_edges) != EXPECTED_EDGES:
        errors.append(f"edge count {len(dual_edges)} != {EXPECTED_EDGES}")
    if errors:
        sys.exit("FAIL: " + "; ".join(errors))

    print(f"OK: {len(goldberg_faces)} faces ({pent_count} pentagons, {hex_count} hexagons), {len(dual_edges)} edges")

    out_path = Path(__file__).parent.parent / "assets" / "maps" / f"{PREFIX}goldberg_edges.png"
    print(f"Rendering equirectangular map → {out_path}")
    render(centroids, dual_edges, out_path)

    json_path = Path(__file__).parent.parent / "assets" / "data" / f"{PREFIX}goldberg_data.json"
    print(f"Exporting nav data → {json_path}")
    export_json(verts, goldberg_faces, faces, json_path)

    print("Done.")


if __name__ == "__main__":
    main()
