import 'package:app/routing/osm_graph.dart';
import 'package:app/routing/yen_k_shortest.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fixture.dart';

void main() {
  group('YenKShortestPaths', () {
    final OsmGraph graph = buildToyGraph();
    final YenKShortestPaths yen = YenKShortestPaths(graph);

    test('returns up to K unique paths sorted ascending by length', () {
      final List<List<int>> paths = yen.kShortest(
        sourceNode: 0,
        targetNode: 4,
        k: 3,
      );
      expect(paths, isNotEmpty);
      // Distinct.
      final Set<String> sigs = paths.map((p) => p.join(',')).toSet();
      expect(sigs.length, paths.length);
      // Each path is loopless (no repeated node).
      for (final p in paths) {
        expect(p.toSet().length, p.length);
      }
      // Lengths non-decreasing (allow tiny float slack for haversine ties).
      double prev = -1;
      for (final p in paths) {
        final double len = graph.pathLengthMeters(p);
        expect(len, greaterThanOrEqualTo(prev - 1e-6));
        prev = len;
      }
    });

    test('K=1 returns just the base shortest path', () {
      final List<List<int>> paths = yen.kShortest(
        sourceNode: 0,
        targetNode: 4,
        k: 1,
      );
      expect(paths.length, 1);
      expect(paths.first.first, 0);
      expect(paths.first.last, 4);
    });

    test('returns empty list when no path exists', () {
      // Build a tiny disconnected graph: nodes 0, 1 with no edges.
      final OsmGraph empty = OsmGraph(
        nodes: const [],
        edges: const [],
        adjacency: const {},
        geohashIndex: const {},
      );
      final List<List<int>> paths =
          YenKShortestPaths(empty).kShortest(sourceNode: 0, targetNode: 0, k: 3);
      // sourceNode/targetNode are out of range → astar returns []; Yen mirrors.
      expect(paths, isEmpty);
    });
  });
}
