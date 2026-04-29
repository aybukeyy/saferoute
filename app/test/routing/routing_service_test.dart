// Smoke test for `RoutingService` graceful-fallback path. We pass a
// non-existent OSM graph asset path and assert the service still boots and
// returns a straight-line `RouteResult` instead of throwing.
//
// The full happy-path (with a real graph) is covered indirectly by the
// astar / yen / risk_rerank tests — bundling a real `road_graph.bin`
// fixture into the test harness would balloon the test asset size and is
// already exercised end-to-end on device.

import 'package:app/data/local_db.dart';
import 'package:app/data/reports_repository.dart';
import 'package:app/data/risk_engine.dart';
import 'package:app/data/sync_service.dart';
import 'package:app/ai/gemma_service.dart';
import 'package:app/routing/routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoutingService graceful fallback', () {
    test('boots without an OSM graph asset and returns a straight line',
        () async {
      // Disabled SyncService so ReportsRepository init is real but offline.
      final sync = await SyncService.tryInitialize();
      final db = LocalDb(fileName: 'routing_service_test.db');
      final risk = RiskEngine(db);
      final reports = ReportsRepository(db: db, sync: sync, risk: risk);
      final gemma = GemmaService();

      final svc = await RoutingService.bootstrap(
        riskEngine: risk,
        reports: reports,
        gemma: gemma,
        graphAssetPath: 'assets/_does_not_exist.bin',
      );

      expect(svc.hasGraph, isFalse,
          reason: 'asset is missing → should fall back');

      final from = const LatLng(41.0451, 28.9912);
      final to = const LatLng(41.0420, 29.0050);
      final result = await svc.findRoutes(
        from: from,
        to: to,
        time: DateTime.utc(2026, 4, 26, 14),
      );

      expect(result.shortestPath, equals(<LatLng>[from, to]));
      expect(result.safestPath, equals(<LatLng>[from, to]));
      expect(result.avoidedCells, isEmpty);
      expect(result.explanationCard.distanceDeltaMeters, 0.0);
      expect(
        result.explanationCard.gemmaSummary,
        contains('OSM graph not yet loaded'),
      );

      await gemma.dispose();
    });
  });
}
