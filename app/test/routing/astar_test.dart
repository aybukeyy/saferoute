import 'package:app/routing/astar.dart';
import 'package:app/routing/osm_graph.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fixture.dart';

void main() {
  group('AStar', () {
    final OsmGraph graph = buildToyGraph();
    final AStar astar = AStar(graph);

    test('finds the shortest path between two reachable nodes', () {
      // Both 0-1-3-4 and 0-2-3-4 visit two ~10 m grid hops then one ~20 m
      // segment to node 4 so they tie around ~40 m. Either is acceptable;
      // we only assert the endpoints and the total length is "around 40 m".
      final List<int> path = astar.shortestPath(sourceNode: 0, targetNode: 4);
      expect(path.first, 0);
      expect(path.last, 4);
      expect(graph.pathLengthMeters(path), closeTo(40.0, 2.0));
    });

    test('returns single-node path when source == target', () {
      final List<int> path = astar.shortestPath(sourceNode: 2, targetNode: 2);
      expect(path, <int>[2]);
    });

    test('returns empty list when target node id is invalid', () {
      final List<int> path = astar.shortestPath(sourceNode: 0, targetNode: 99);
      expect(path, isEmpty);
    });

    test('respects a custom edge cost function', () {
      // Penalize edge 1 (0-2) heavily so the only sane path is 0-1-3-4.
      final List<int> path = astar.shortestPathCustom(
        sourceNode: 0,
        targetNode: 4,
        edgeCost: (Edge e) => e.id == 1 ? 1e9 : e.lengthMeters,
      );
      expect(path, <int>[0, 1, 3, 4]);
    });

    test('blocked edges force a detour', () {
      // Force the router to ignore edge 4 (3→4); only escape to 4 is via 1-4.
      final List<int> path = astar.shortestPathCustom(
        sourceNode: 0,
        targetNode: 4,
        edgeCost: defaultEdgeCost,
        blockedEdgeIds: <int>{4},
      );
      expect(path.first, 0);
      expect(path.last, 4);
      // Must traverse the long e5 shortcut 1→4 to reach node 4.
      expect(path.contains(1), isTrue);
    });
  });
}
