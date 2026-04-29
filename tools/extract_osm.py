#!/usr/bin/env python3
"""
extract_osm.py — Build the bundled walkable road graph for Safe Route.

Pipeline:
  1. `osmium extract -b <bbox> <input.pbf> -o <tmp.pbf>` to slice the input.
  2. Walk the PBF, keep nodes/ways tagged as walkable highways.
  3. Build an undirected graph of LatLng nodes + length-weighted edges.
  4. Sample each edge polyline at ~50 m intervals, geohash-7 the samples,
     dedupe consecutive duplicates → ordered cell sequence.
  5. Write `RoadGraph` binary as documented in
     `app/lib/routing/osm_graph.dart`.

The output drops to `app/assets/road_graph.bin` by default, which Flutter
loads at app start via `OsmGraph.loadAsset`. See `tools/README.md` for the
manual download / install steps.

Usage:
  python tools/extract_osm.py \
      --pbf path/to/turkey-latest.osm.pbf \
      --bbox 28.985,41.040,29.045,41.080 \
      --output app/assets/road_graph.bin
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Tuple

# ---------------------------------------------------------------------------
# Walkable highway predicate
# ---------------------------------------------------------------------------

# Highways we include. We deliberately keep major roads (primary/secondary/
# tertiary) because urban pedestrians do walk along them; we only drop the
# motor-only categories (motorways/trunks). The list mirrors what OSRM's
# foot.lua considers walkable, minus controlled-access roads.
WALKABLE = {
    "footway",
    "path",
    "pedestrian",
    "steps",
    "living_street",
    "residential",
    "service",
    "track",
    "unclassified",
    "tertiary",
    "tertiary_link",
    "secondary",
    "secondary_link",
    "primary",
    "primary_link",
    "cycleway",
    "road",  # untagged "road" classification — better to keep than to drop.
}

# Hard exclusions — pedestrians may not walk these.
NOT_WALKABLE = {
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "bus_guideway",
    "raceway",
    "construction",
    "proposed",
    "no",
}


def is_walkable(highway_tag: str | None) -> bool:
    """True if the highway= value should produce walkable edges."""
    if not highway_tag:
        return False
    if highway_tag in NOT_WALKABLE:
        return False
    return highway_tag in WALKABLE


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in meters."""
    rl1 = math.radians(lat1)
    rl2 = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(rl1) * math.cos(rl2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def interpolate(lat1: float, lon1: float, lat2: float, lon2: float, t: float) -> Tuple[float, float]:
    """Linear interpolation between two LatLng (sufficient at <50 m spacing)."""
    return (lat1 + (lat2 - lat1) * t, lon1 + (lon2 - lon1) * t)


def sample_polyline(coords: List[Tuple[float, float]], spacing_m: float = 50.0) -> Iterable[Tuple[float, float]]:
    """Yield (lat, lng) points along a polyline at roughly `spacing_m` apart.

    Always yields the first vertex and the final vertex.
    """
    if not coords:
        return
    yield coords[0]
    if len(coords) == 1:
        return
    carry = 0.0
    for (a_lat, a_lng), (b_lat, b_lng) in zip(coords[:-1], coords[1:]):
        seg_len = haversine_m(a_lat, a_lng, b_lat, b_lng)
        if seg_len == 0:
            continue
        # First sample may need to be `spacing_m - carry` along the segment.
        d = spacing_m - carry
        while d < seg_len:
            t = d / seg_len
            yield interpolate(a_lat, a_lng, b_lat, b_lng, t)
            d += spacing_m
        carry = (carry + seg_len) % spacing_m
    yield coords[-1]


# ---------------------------------------------------------------------------
# Geohash-7 (base-32, no external dep needed for the encoder)
# ---------------------------------------------------------------------------

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"


def geohash7(lat: float, lng: float) -> str:
    """Encode (lat, lng) as a 7-character geohash."""
    return _encode_geohash(lat, lng, precision=7)


def _encode_geohash(lat: float, lng: float, precision: int = 7) -> str:
    lat_lo, lat_hi = -90.0, 90.0
    lng_lo, lng_hi = -180.0, 180.0
    bits = []
    even = True
    while len(bits) < precision * 5:
        if even:
            mid = (lng_lo + lng_hi) / 2
            if lng >= mid:
                bits.append(1)
                lng_lo = mid
            else:
                bits.append(0)
                lng_hi = mid
        else:
            mid = (lat_lo + lat_hi) / 2
            if lat >= mid:
                bits.append(1)
                lat_lo = mid
            else:
                bits.append(0)
                lat_hi = mid
        even = not even
    out = []
    for i in range(0, len(bits), 5):
        idx = (bits[i] << 4) | (bits[i + 1] << 3) | (bits[i + 2] << 2) | (bits[i + 3] << 1) | bits[i + 4]
        out.append(_BASE32[idx])
    return "".join(out)


# ---------------------------------------------------------------------------
# OSM extraction
# ---------------------------------------------------------------------------


@dataclass
class GraphBuilder:
    nodes: List[Tuple[float, float]] = field(default_factory=list)  # node id → (lat, lng)
    node_index: Dict[int, int] = field(default_factory=dict)  # OSM ref → local id
    edges: List[Tuple[int, int, float, List[str]]] = field(default_factory=list)
    geohash_index: Dict[str, List[int]] = field(default_factory=lambda: defaultdict(list))

    def get_or_add_node(self, osm_ref: int, lat: float, lng: float) -> int:
        local = self.node_index.get(osm_ref)
        if local is None:
            local = len(self.nodes)
            self.node_index[osm_ref] = local
            self.nodes.append((lat, lng))
        return local

    def add_edge(self, u: int, v: int, length_m: float, cells: List[str]) -> None:
        eid = len(self.edges)
        self.edges.append((u, v, length_m, cells))
        for c in cells:
            self.geohash_index[c].append(eid)


def run_osmium_extract(input_pbf: str, bbox: str, out_pbf: str) -> None:
    """Slice the input PBF to the requested bbox using `osmium`."""
    if shutil.which("osmium") is None:
        sys.exit(
            "ERROR: `osmium` CLI not found. Install osmium-tool "
            "(brew install osmium-tool / apt install osmium-tool)."
        )
    print(f"[extract] osmium extract -b {bbox} {input_pbf} -o {out_pbf}", flush=True)
    subprocess.run(
        ["osmium", "extract", "-b", bbox, input_pbf, "-o", out_pbf, "--overwrite"],
        check=True,
    )


def build_graph(pbf_path: str) -> GraphBuilder:
    try:
        import osmium  # type: ignore
    except ImportError:
        sys.exit(
            "ERROR: pyosmium not installed. `pip install -r tools/requirements.txt`."
        )

    builder = GraphBuilder()

    # Pyosmium 4.x uses SimpleHandler (older API) or replication-based handlers.
    # SimpleHandler is still the simplest for one-off extraction.
    class _Handler(osmium.SimpleHandler):  # type: ignore
        def __init__(self) -> None:
            super().__init__()
            self.kept_ways = 0
            self.skipped_ways = 0

        def way(self, w):  # noqa: N802 (osmium API)
            highway = w.tags.get("highway")
            if not is_walkable(highway):
                self.skipped_ways += 1
                return
            access = w.tags.get("access")
            foot = w.tags.get("foot")
            if access == "no" and foot not in {"yes", "designated", "permissive"}:
                self.skipped_ways += 1
                return

            coords: List[Tuple[float, float, int]] = []
            for n in w.nodes:
                if not n.location.valid():
                    continue
                coords.append((n.location.lat, n.location.lon, n.ref))
            if len(coords) < 2:
                return

            self.kept_ways += 1

            # Convert to local node ids.
            local_ids: List[int] = []
            for lat, lng, ref in coords:
                local_ids.append(builder.get_or_add_node(ref, lat, lng))

            # Each consecutive pair becomes an undirected edge.
            for i in range(len(coords) - 1):
                a_lat, a_lng, _ = coords[i]
                b_lat, b_lng, _ = coords[i + 1]
                length = haversine_m(a_lat, a_lng, b_lat, b_lng)
                if length <= 0:
                    continue
                cells: List[str] = []
                last = ""
                for lat, lng in sample_polyline(
                    [(a_lat, a_lng), (b_lat, b_lng)], spacing_m=50.0
                ):
                    gh = geohash7(lat, lng)
                    if gh != last:
                        cells.append(gh)
                        last = gh
                builder.add_edge(local_ids[i], local_ids[i + 1], length, cells)

    handler = _Handler()
    print(f"[extract] scanning {pbf_path} for walkable ways…", flush=True)
    handler.apply_file(pbf_path, locations=True)
    print(
        f"[extract] kept {handler.kept_ways} ways, skipped {handler.skipped_ways}; "
        f"{len(builder.nodes)} nodes / {len(builder.edges)} edges",
        flush=True,
    )
    return builder


# ---------------------------------------------------------------------------
# Binary serialization (matches osm_graph.dart)
# ---------------------------------------------------------------------------

MAGIC = b"RGRP"
VERSION = 1


def serialize(builder: GraphBuilder, out_path: str) -> None:
    parts: List[bytes] = []
    parts.append(MAGIC)
    parts.append(struct.pack("<H", VERSION))
    parts.append(struct.pack("<I", len(builder.nodes)))
    parts.append(struct.pack("<I", len(builder.edges)))

    # nodes
    for lat, lng in builder.nodes:
        parts.append(struct.pack("<dd", lat, lng))

    # edges
    for u, v, length, cells in builder.edges:
        if len(cells) > 255:
            cells = cells[:255]  # cellCount is u8; truncate pathological ways
        parts.append(struct.pack("<IIfB", u, v, float(length), len(cells)))
        for c in cells:
            parts.append(c.encode("ascii"))

    # geohash index
    parts.append(struct.pack("<I", len(builder.geohash_index)))
    for gh, refs in builder.geohash_index.items():
        if len(refs) > 65_535:
            refs = refs[:65_535]
        parts.append(gh.encode("ascii"))
        parts.append(struct.pack("<H", len(refs)))
        parts.append(struct.pack(f"<{len(refs)}I", *refs))

    blob = b"".join(parts)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(blob)
    print(
        f"[extract] wrote {out_path} ({len(blob) / 1024 / 1024:.2f} MiB)",
        flush=True,
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--pbf", required=True, help="Path to a Geofabrik OSM PBF file.")
    p.add_argument(
        "--bbox",
        required=True,
        help="minLng,minLat,maxLng,maxLat (e.g. 28.985,41.040,29.045,41.080).",
    )
    p.add_argument(
        "--output",
        default="app/assets/road_graph.bin",
        help="Path to the output binary (default: app/assets/road_graph.bin).",
    )
    p.add_argument(
        "--keep-tmp",
        action="store_true",
        help="Keep the intermediate sliced PBF for debugging.",
    )
    args = p.parse_args()

    # Validate bbox shape.
    try:
        parts = [float(x) for x in args.bbox.split(",")]
        if len(parts) != 4:
            raise ValueError
        min_lng, min_lat, max_lng, max_lat = parts
        if not (-180 <= min_lng < max_lng <= 180 and -90 <= min_lat < max_lat <= 90):
            raise ValueError
    except ValueError:
        sys.exit("ERROR: --bbox must be 'minLng,minLat,maxLng,maxLat' with min < max.")

    if not os.path.isfile(args.pbf):
        sys.exit(f"ERROR: --pbf file not found: {args.pbf}")

    with tempfile.TemporaryDirectory(prefix="saferoute_extract_") as tmp:
        sliced = os.path.join(tmp, "region.pbf")
        run_osmium_extract(args.pbf, args.bbox, sliced)
        if args.keep_tmp:
            kept = os.path.join(os.path.dirname(args.output) or ".", "region_extract.pbf")
            shutil.copyfile(sliced, kept)
            print(f"[extract] kept intermediate slice: {kept}", flush=True)
        builder = build_graph(sliced)
        if not builder.edges:
            sys.exit("ERROR: no walkable edges found inside the bbox. Is your bbox correct?")
        serialize(builder, args.output)


if __name__ == "__main__":
    main()
