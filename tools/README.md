# tools/

Manual one-shot scripts for Safe Route. None of these run on the phone — they
prepare assets that get bundled into the Flutter app.

## extract_osm.py

Builds `app/assets/road_graph.bin`, the binary walkable road graph that the
on-device router (`app/lib/routing/`) uses. Run this once per demo region.

### 1. Install system dependencies

`pyosmium` needs the libosmium C++ library at runtime.

macOS (Homebrew):
```bash
brew install osmium-tool libosmium boost-build expat
```

Debian/Ubuntu:
```bash
sudo apt update
sudo apt install osmium-tool libosmium2-dev libboost-dev libexpat1-dev zlib1g-dev
```

### 2. Install Python dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r tools/requirements.txt
```

### 3. Download the source PBF

Pick the smallest Geofabrik regional extract that contains your demo bbox.
Examples:

| Region | Geofabrik URL |
|---|---|
| Turkey | https://download.geofabrik.de/europe/turkey-latest.osm.pbf |
| Türkiye (Istanbul subset) | included inside the country file |
| California, USA | https://download.geofabrik.de/north-america/us/california-latest.osm.pbf |

Save it somewhere outside the repo (these files are 100s of MB).

### 4. Run the extractor

```bash
python tools/extract_osm.py \
    --pbf ~/Downloads/turkey-latest.osm.pbf \
    --bbox 28.985,41.040,29.045,41.080 \
    --output app/assets/road_graph.bin
```

**bbox format:** `minLng,minLat,maxLng,maxLat` (longitude first — matches
`osmium extract`'s convention).

### Suggested demo bboxes (~5 km × 5 km each)

| Neighborhood | bbox (`minLng,minLat,maxLng,maxLat`) |
|---|---|
| Istanbul — Beşiktaş / Ortaköy | `28.985,41.040,29.045,41.080` |
| Istanbul — Kadıköy / Moda | `29.020,40.975,29.080,41.015` |
| Ankara — Çankaya / Kızılay | `32.835,39.895,32.895,39.935` |

Pick the one that gives the cleanest pedestrian network for your video shoot
(see `docs/planning/DEMO.md`). Re-run the script with a different bbox to
swap regions; only `app/assets/road_graph.bin` changes.

### What ends up in the binary

- All highways tagged walkable (footway, residential, secondary, …) — see
  `is_walkable()` in `extract_osm.py` for the full list. Motorways/trunks are
  excluded.
- Each edge stores its haversine length (meters) and the ordered set of
  geohash-7 cells its polyline crosses (sampled at ~50 m intervals). The
  router's risk re-rank uses that cell list directly.
- A reverse geohash → edge-id index lets the risk engine find which edges
  pass through a hot cell.

### Verifying the output

```bash
ls -lh app/assets/road_graph.bin
# Should be on the order of single-digit MB for a 5×5 km extract.
file app/assets/road_graph.bin
# Will report "data" — the file starts with the ASCII magic "RGRP".
```

A unit-level smoke test exists in `app/test/routing/`; run
`flutter test test/routing/` after regenerating the asset.
