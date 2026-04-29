// Yen's K-shortest loopless paths on top of [AStar]. We only ever ask for a
// handful of alternatives (default K=5) which the risk re-rank then scores.
//
// Reference: Wikipedia, "Yen's algorithm". This implementation follows the
// classic pseudocode using a candidate min-heap (B) and an accepted list (A).

import 'dart:collection';

import 'astar.dart';
import 'osm_graph.dart';
import 'priority_queue.dart';

class YenKShortestPaths {
  YenKShortestPaths(this.graph) : _astar = AStar(graph);

  final OsmGraph graph;
  final AStar _astar;

  /// Returns up to [k] shortest loopless paths from [sourceNode] to
  /// [targetNode], sorted ascending by total physical length.
  ///
  /// Returns `[]` if even the base shortest path does not exist.
  List<List<int>> kShortest({
    required int sourceNode,
    required int targetNode,
    int k = 5,
  }) {
    if (k <= 0) return <List<int>>[];

    final List<int> base = _astar.shortestPath(
      sourceNode: sourceNode,
      targetNode: targetNode,
    );
    if (base.isEmpty) return <List<int>>[];

    final List<List<int>> accepted = <List<int>>[base];
    if (k == 1) return accepted;

    // Candidate min-heap, keyed by total length.
    final MinHeap<_Candidate> candidates = MinHeap<_Candidate>(
      (a, b) => a.cost.compareTo(b.cost),
    );

    // Track candidate path signatures to avoid pushing duplicates.
    final Set<String> candidateSeen = HashSet<String>();
    final Set<String> acceptedSigs = HashSet<String>()..add(_signature(base));

    for (int i = 1; i < k; i++) {
      final List<int> previous = accepted.last;

      // For each node in `previous` (except the last), generate a spur.
      for (int spurIndex = 0; spurIndex < previous.length - 1; spurIndex++) {
        final int spurNode = previous[spurIndex];
        final List<int> rootPath = previous.sublist(0, spurIndex + 1);

        // Block edges that share the same root prefix in any accepted path —
        // this is what forces Yen to enumerate distinct alternatives.
        final Set<int> blockedEdges = HashSet<int>();
        for (final List<int> p in accepted) {
          if (p.length <= spurIndex + 1) continue;
          bool sameRoot = true;
          for (int j = 0; j <= spurIndex; j++) {
            if (p[j] != rootPath[j]) {
              sameRoot = false;
              break;
            }
          }
          if (sameRoot) {
            final int? eid = _edgeIdBetween(p[spurIndex], p[spurIndex + 1]);
            if (eid != null) blockedEdges.add(eid);
          }
        }

        // Block all root-path nodes except the spur node itself, so the spur
        // path cannot loop back through the prefix.
        final Set<int> blockedNodes = HashSet<int>();
        for (int j = 0; j < rootPath.length - 1; j++) {
          blockedNodes.add(rootPath[j]);
        }

        final List<int> spurPath = _astar.shortestPathCustom(
          sourceNode: spurNode,
          targetNode: targetNode,
          edgeCost: defaultEdgeCost,
          blockedEdgeIds: blockedEdges,
          blockedNodeIds: blockedNodes,
        );

        if (spurPath.isEmpty) continue;

        // Stitch root + spur (drop the duplicated spur node).
        final List<int> totalPath = <int>[
          ...rootPath,
          ...spurPath.skip(1),
        ];
        final String sig = _signature(totalPath);
        if (acceptedSigs.contains(sig)) continue;
        if (!candidateSeen.add(sig)) continue;

        final double cost = graph.pathLengthMeters(totalPath);
        candidates.add(_Candidate(path: totalPath, cost: cost));
      }

      if (candidates.isEmpty) break;
      final _Candidate next = candidates.removeMin();
      accepted.add(next.path);
      acceptedSigs.add(_signature(next.path));
    }

    return accepted;
  }

  int? _edgeIdBetween(int a, int b) {
    final List<int> aEdges = graph.adjacency[a] ?? const <int>[];
    for (final int eid in aEdges) {
      final Edge e = graph.edges[eid];
      if (e.other(a) == b) return eid;
    }
    return null;
  }

  static String _signature(List<int> path) => path.join(',');
}

class _Candidate {
  _Candidate({required this.path, required this.cost});
  final List<int> path;
  final double cost;
}
