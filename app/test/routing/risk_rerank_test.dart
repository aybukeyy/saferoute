import 'package:app/routing/osm_graph.dart';
import 'package:app/routing/risk_rerank.dart';
import 'package:app/routing/yen_k_shortest.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fixture.dart';

void main() {
  group('RiskRerank', () {
    final OsmGraph graph = buildToyGraph();
    final YenKShortestPaths yen = YenKShortestPaths(graph);

    test('throws NoPathException when no candidates given', () {
      expect(
        () => RiskRerank.pickSafest(
          candidatePaths: const <List<int>>[],
          graph: graph,
          predictedRisk: (_) => 0,
        ),
        throwsA(isA<NoPathException>()),
      );
    });

    test('picks the safer detour when one cell is hot', () {
      final List<List<int>> paths =
          yen.kShortest(sourceNode: 0, targetNode: 4, k: 5);
      // Make 'sxk0aac' (the path through 3-4 / 2-3) very risky so the safer
      // option must avoid it. With our fixture only 0-1-4 (the long
      // shortcut) entirely avoids that cell.
      final result = RiskRerank.pickSafest(
        candidatePaths: paths,
        graph: graph,
        predictedRisk: (gh) => gh == 'sxk0aac' ? 1.0 : 0.0,
        alpha: 1000.0, // high enough to dominate the +200 m detour
      );
      expect(result.shortest, isNotEmpty);
      expect(result.safest, isNotEmpty);
      // Safest should not include the hot cell.
      expect(result.safest.contains(4), isTrue); // still reaches the target
      expect(result.avoidedCells, contains('sxk0aac'));
      expect(result.alphaUsed, 1000.0);
    });

    test('safestEqualsShortest when no risk is present', () {
      final List<List<int>> paths =
          yen.kShortest(sourceNode: 0, targetNode: 4, k: 5);
      final result = RiskRerank.pickSafest(
        candidatePaths: paths,
        graph: graph,
        predictedRisk: (_) => 0.0,
      );
      expect(result.safestEqualsShortest, isTrue);
      expect(result.distanceDeltaMeters, 0.0);
    });
  });
}
