// Tiny synthetic graph used by routing/* tests. We hand-build an OsmGraph
// instance instead of going through the binary loader so tests don't need
// rootBundle / Flutter bindings.

import 'package:app/routing/osm_graph.dart';
import 'package:latlong2/latlong.dart';

/// Builds a 5-node demo graph. Coordinates and edge lengths are kept
/// haversine-consistent so the A* heuristic stays admissible (otherwise A*
/// can return a sub-optimal path on this micro-graph).
///
///   (0)---e0---(1)
///    |          |
///    e1         e2
///    |          |
///   (2)---e3---(3)---e4---(4)
///                |
///                +---------(via long shortcut e5: 1→4)
///
/// Edge weights, in meters, mirror the haversine distances between the chosen
/// LatLng pairs. The "shortcut" edge `e5` (1→4) is intentionally longer so
/// alternative-path enumeration can rank it last.
OsmGraph buildToyGraph() {
  // Spread nodes ~10m apart on a tiny grid near (0,0). Using the equator
  // keeps lat ≈ lng meters-per-degree similar so haversine and the picture
  // above stay easy to read.
  const double dLat = 0.00009; // ≈ 10 m latitudinally
  const double dLng = 0.00009; // ≈ 10 m longitudinally near the equator

  final List<LatLng> nodes = <LatLng>[
    const LatLng(0.0, 0.0),                 // 0
    const LatLng(0.0, dLng),                // 1  (10m east of 0)
    const LatLng(-dLat, 0.0),               // 2  (10m south of 0)
    const LatLng(-dLat, dLng),              // 3  (10m south of 1)
    const LatLng(-dLat - 0.00018, dLng),    // 4  (~30m south of 1)
  ];

  // Compute lengths from the actual coordinates so the A* heuristic
  // (haversine-to-target) is admissible w.r.t. each edge cost.
  double len(int a, int b) => haversineMeters(nodes[a], nodes[b]);

  final List<Edge> edges = <Edge>[
    Edge(id: 0, u: 0, v: 1, lengthMeters: len(0, 1), geohash7Sequence: const ['sxk0aaa', 'sxk0aab']),
    Edge(id: 1, u: 0, v: 2, lengthMeters: len(0, 2), geohash7Sequence: const ['sxk0aaa']),
    Edge(id: 2, u: 1, v: 3, lengthMeters: len(1, 3), geohash7Sequence: const ['sxk0aab']),
    Edge(id: 3, u: 2, v: 3, lengthMeters: len(2, 3), geohash7Sequence: const ['sxk0aac']),
    Edge(id: 4, u: 3, v: 4, lengthMeters: len(3, 4), geohash7Sequence: const ['sxk0aac']),
    // Long "shortcut" 1→4: 10× the haversine to keep it admissible but
    // unattractive vs the 1-3-4 detour (~30 m).
    Edge(id: 5, u: 1, v: 4, lengthMeters: 10 * len(1, 4), geohash7Sequence: const ['sxk0aab', 'sxk0aad']),
  ];

  final Map<int, List<int>> adj = <int, List<int>>{};
  for (final Edge e in edges) {
    (adj[e.u] ??= <int>[]).add(e.id);
    (adj[e.v] ??= <int>[]).add(e.id);
  }

  final Map<String, List<int>> ghIndex = <String, List<int>>{};
  for (final Edge e in edges) {
    for (final String c in e.geohash7Sequence) {
      (ghIndex[c] ??= <int>[]).add(e.id);
    }
  }

  return OsmGraph(
    nodes: nodes,
    edges: edges,
    adjacency: adj,
    geohashIndex: ghIndex,
  );
}
