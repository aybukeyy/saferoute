// Pure-Dart A* on the bundled OsmGraph. Used both as a stand-alone shortest
// path finder and as the inner loop of Yen's K-shortest paths.
// See ARCHITECTURE.md §6.

import 'dart:collection';

import 'osm_graph.dart';
import 'priority_queue.dart';

/// Default edge cost: physical edge length in meters. Used for "shortest" path.
double defaultEdgeCost(Edge e) => e.lengthMeters;

/// A* shortest-path on an [OsmGraph]. The cost function and the set of
/// "blocked" edges/nodes are pluggable so Yen's algorithm can reuse the same
/// machinery without copying the graph.
class AStar {
  AStar(this.graph);

  final OsmGraph graph;

  /// Default API: physical-length shortest path.
  ///
  /// Returns the node-id sequence from [sourceNode] to [targetNode], inclusive.
  /// Returns an empty list when no path exists.
  List<int> shortestPath({
    required int sourceNode,
    required int targetNode,
  }) {
    return shortestPathCustom(
      sourceNode: sourceNode,
      targetNode: targetNode,
      edgeCost: defaultEdgeCost,
    );
  }

  /// A* with a custom edge-cost function. The heuristic is Haversine distance
  /// (in meters) to [targetNode], which is admissible whenever the cost
  /// function is bounded below by physical length — true for both the default
  /// length cost and the risk-weighted re-rank cost (length + α·risk ≥ length).
  ///
  /// [blockedEdgeIds] and [blockedNodeIds] let Yen's spur paths exclude
  /// individual edges/nodes without mutating the graph.
  List<int> shortestPathCustom({
    required int sourceNode,
    required int targetNode,
    required double Function(Edge) edgeCost,
    Set<int>? blockedEdgeIds,
    Set<int>? blockedNodeIds,
  }) {
    if (sourceNode < 0 || sourceNode >= graph.nodes.length) return <int>[];
    if (targetNode < 0 || targetNode >= graph.nodes.length) return <int>[];
    if (sourceNode == targetNode) return <int>[sourceNode];

    final Set<int> blockedEdges = blockedEdgeIds ?? const <int>{};
    final Set<int> blockedNodes = blockedNodeIds ?? const <int>{};

    final Map<int, double> gScore = <int, double>{sourceNode: 0.0};
    final Map<int, int> cameFrom = <int, int>{};
    final Set<int> closed = HashSet<int>();

    // Min-heap keyed on f = g + h.
    final MinHeap<_OpenEntry> open = MinHeap<_OpenEntry>(
      (a, b) => a.f.compareTo(b.f),
    );
    open.add(_OpenEntry(
      node: sourceNode,
      f: _heuristic(sourceNode, targetNode),
    ));

    while (open.isNotEmpty) {
      final _OpenEntry current = open.removeMin();
      final int node = current.node;

      if (node == targetNode) {
        return _reconstruct(cameFrom, node);
      }
      if (!closed.add(node)) continue; // already settled

      final double gCurrent = gScore[node] ?? double.infinity;
      final List<int> incident = graph.adjacency[node] ?? const <int>[];

      for (final int edgeId in incident) {
        if (blockedEdges.contains(edgeId)) continue;
        final Edge edge = graph.edges[edgeId];
        final int neighbor = edge.other(node);
        if (blockedNodes.contains(neighbor)) continue;
        if (closed.contains(neighbor)) continue;

        final double tentative = gCurrent + edgeCost(edge);
        final double existing = gScore[neighbor] ?? double.infinity;
        if (tentative < existing) {
          cameFrom[neighbor] = node;
          gScore[neighbor] = tentative;
          final double f = tentative + _heuristic(neighbor, targetNode);
          open.add(_OpenEntry(node: neighbor, f: f));
        }
      }
    }

    return <int>[]; // no path
  }

  double _heuristic(int from, int to) {
    return haversineMeters(graph.nodes[from], graph.nodes[to]);
  }

  List<int> _reconstruct(Map<int, int> cameFrom, int target) {
    final List<int> out = <int>[target];
    int cur = target;
    while (cameFrom.containsKey(cur)) {
      cur = cameFrom[cur]!;
      out.add(cur);
    }
    return out.reversed.toList(growable: false);
  }
}

class _OpenEntry {
  _OpenEntry({required this.node, required this.f});
  final int node;
  final double f;
}
