// Re-ranks candidate paths by length + alpha * sum(predicted_risk_along_path).
// See ARCHITECTURE.md §6.
//
// Inputs come from [YenKShortestPaths] (paths) and [RiskEngine.predictedRisk]
// (per-cell risk score in [0, 1]). The output identifies a "shortest" baseline
// (smallest physical length) and a "safest" pick (smallest length + α·risk),
// plus the set of cells the safest path skips relative to the shortest.

import 'osm_graph.dart';

/// Thrown when the re-rank cannot select a path because no candidates exist.
class NoPathException implements Exception {
  const NoPathException([this.message = 'No candidate paths to rerank.']);
  final String message;
  @override
  String toString() => 'NoPathException: $message';
}

/// Result of [RiskRerank.pickSafest]. `safest` and `shortest` are node-id
/// sequences over the [OsmGraph]; `avoidedCells` are geohash-7 cells that the
/// shortest path crosses but the safest one does not.
class RiskRerankResult {
  const RiskRerankResult({
    required this.safest,
    required this.shortest,
    required this.avoidedCells,
    required this.distanceDeltaMeters,
    required this.alphaUsed,
    required this.shortestLengthMeters,
    required this.safestLengthMeters,
    required this.safestRiskSum,
    required this.shortestRiskSum,
    required this.safestEqualsShortest,
  });

  final List<int> safest;
  final List<int> shortest;
  final List<String> avoidedCells;
  final double distanceDeltaMeters; // safest length − shortest length
  final double alphaUsed;

  final double shortestLengthMeters;
  final double safestLengthMeters;
  final double safestRiskSum;
  final double shortestRiskSum;

  /// True when the safest path is the shortest path (set-equal cells). UI uses
  /// this to render an "Safest = Shortest" badge instead of a fake trade-off.
  final bool safestEqualsShortest;
}

class RiskRerank {
  RiskRerank._();

  /// α (alpha) default. Cost is `length_m + α · Σ predicted_risk(cell)`.
  /// With α = 100 a fully-saturated risk cell (risk = 1.0) is "worth" a 100 m
  /// detour. Five risky cells along a path therefore justify ~500 m of extra
  /// walking — which matches the demo intuition of "we'll go around a hot
  /// block but not across town." Tunable via the debug menu (see
  /// ARCHITECTURE.md §6).
  static const double defaultAlpha = 100.0;

  /// Picks the safest path out of a set of A*/Yen candidates.
  ///
  /// `predictedRisk` is injected by the caller (typically `RiskEngine`) so the
  /// routing module stays free of any risk-engine dependency. It is called
  /// once per *unique* geohash-7 cell along each candidate path.
  static RiskRerankResult pickSafest({
    required List<List<int>> candidatePaths,
    required OsmGraph graph,
    required double Function(String geohash7) predictedRisk,
    double alpha = defaultAlpha,
  }) {
    if (candidatePaths.isEmpty) {
      throw const NoPathException();
    }

    // Deduplicate identical candidate paths up-front (Yen should already
    // produce unique sequences but defend against accidental duplication).
    final List<List<int>> paths = _dedupePaths(candidatePaths);

    // Score every candidate.
    final List<_Scored> scored = <_Scored>[];
    for (final List<int> p in paths) {
      final double length = graph.pathLengthMeters(p);
      final Set<String> cells = _cellsAlong(p, graph);
      double risk = 0;
      for (final String c in cells) {
        risk += predictedRisk(c);
      }
      final double cost = length + alpha * risk;
      scored.add(_Scored(
        path: p,
        length: length,
        cells: cells,
        risk: risk,
        cost: cost,
      ));
    }

    // Shortest = smallest physical length (tie-break: original order).
    _Scored shortest = scored.first;
    for (final _Scored s in scored) {
      if (s.length < shortest.length) shortest = s;
    }

    // Safest = smallest combined cost.
    _Scored safest = scored.first;
    for (final _Scored s in scored) {
      if (s.cost < safest.cost) safest = s;
    }

    final List<String> avoided = shortest.cells
        .difference(safest.cells)
        .toList(growable: false);

    final bool equal = _pathEquals(shortest.path, safest.path);

    return RiskRerankResult(
      safest: safest.path,
      shortest: shortest.path,
      avoidedCells: avoided,
      distanceDeltaMeters: safest.length - shortest.length,
      alphaUsed: alpha,
      shortestLengthMeters: shortest.length,
      safestLengthMeters: safest.length,
      safestRiskSum: safest.risk,
      shortestRiskSum: shortest.risk,
      safestEqualsShortest: equal,
    );
  }

  static Set<String> _cellsAlong(List<int> path, OsmGraph graph) {
    if (path.length < 2) return <String>{};
    final Set<String> out = <String>{};
    for (int i = 0; i + 1 < path.length; i++) {
      final int a = path[i];
      final int b = path[i + 1];
      final List<int> aEdges = graph.adjacency[a] ?? const <int>[];
      for (final int eid in aEdges) {
        final Edge e = graph.edges[eid];
        if (e.other(a) == b) {
          out.addAll(e.geohash7Sequence);
          break;
        }
      }
    }
    return out;
  }

  static List<List<int>> _dedupePaths(List<List<int>> paths) {
    final Set<String> seen = <String>{};
    final List<List<int>> out = <List<int>>[];
    for (final List<int> p in paths) {
      final String sig = p.join(',');
      if (seen.add(sig)) out.add(p);
    }
    return out;
  }

  static bool _pathEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _Scored {
  _Scored({
    required this.path,
    required this.length,
    required this.cells,
    required this.risk,
    required this.cost,
  });
  final List<int> path;
  final double length;
  final Set<String> cells;
  final double risk;
  final double cost;
}
