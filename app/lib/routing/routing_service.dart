// Top-level routing orchestration. Wires the OSM graph + A*/Yen K-shortest
// + RiskEngine cell scores + Gemma 4 E4B per-cell summaries into a single
// `RouteResult` payload that `RouteDetailScreen` renders.
//
// Designed to **boot gracefully** even when the bundled OSM graph asset is
// missing (the user may not have run `tools/extract_osm.py` yet — see
// docs/planning/MANUAL_SETUP.md §3). In that case `findRoutes` falls back to
// a straight-line "shortest = safest" RouteResult so the app stays usable
// for taking reports + browsing the heatmap.
//
// Source-of-truth docs:
//   - docs/planning/IMPLEMENTATION.md §6 (folder structure) and §8 (flow)
//   - docs/planning/ARCHITECTURE.md     §3 (data flow B), §6 (routing)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../ai/gemma_service.dart';
import '../data/reports_repository.dart';
import '../data/risk_engine.dart';
import '../models/report.dart';
import '../models/route_result.dart';
import 'osm_graph.dart';
import 'risk_rerank.dart';
import 'yen_k_shortest.dart';

/// Thrown when no path exists between two arbitrary `LatLng`s in the loaded
/// graph. The orchestrator turns this into a graceful straight-line fallback
/// instead of bubbling up to the UI.
class NoPathBetweenException implements Exception {
  const NoPathBetweenException(this.from, this.to);
  final LatLng from;
  final LatLng to;

  @override
  String toString() => 'NoPathBetweenException(from=$from, to=$to)';
}

/// Pure orchestration service. Holds the loaded `OsmGraph` (or null if the
/// asset wasn't bundled) and synthesizes a `RouteResult` per request.
class RoutingService {
  RoutingService._({
    required OsmGraph? graph,
    required RiskEngine riskEngine,
    required ReportsRepository reports,
    required GemmaService gemma,
    bool useGemmaSummaries = true,
  })  : _graph = graph,
        _riskEngine = riskEngine,
        _reports = reports,
        _gemma = gemma,
        _useGemmaSummaries = useGemmaSummaries;

  final OsmGraph? _graph;
  final RiskEngine _riskEngine;
  final ReportsRepository _reports;
  final GemmaService _gemma;
  final bool _useGemmaSummaries;

  /// True when the bundled OSM graph loaded successfully — `findRoutes` will
  /// run real A*/Yen routing. False ⇒ straight-line fallback.
  bool get hasGraph => _graph != null;

  /// Loads the OSM graph asset and returns a ready-to-use service. Catches
  /// asset-missing / parse failures and returns a service in fallback mode
  /// so the app boot doesn't abort if the user hasn't run extract_osm.py
  /// yet.
  static Future<RoutingService> bootstrap({
    required RiskEngine riskEngine,
    required ReportsRepository reports,
    required GemmaService gemma,
    String graphAssetPath = 'assets/road_graph.bin',
    bool useGemmaSummaries = true,
  }) async {
    OsmGraph? graph;
    try {
      graph = await OsmGraph.loadAsset(graphAssetPath);
      debugPrint(
          '[RoutingService] OSM graph loaded: ${graph.nodes.length} nodes, '
          '${graph.edges.length} edges');
    } catch (e, st) {
      debugPrint(
          '[RoutingService] OSM graph asset "$graphAssetPath" not loaded — '
          'falling back to straight-line routing. ($e)\n$st');
      graph = null;
    }

    return RoutingService._(
      graph: graph,
      riskEngine: riskEngine,
      reports: reports,
      gemma: gemma,
      useGemmaSummaries: useGemmaSummaries,
    );
  }

  /// Plan two routes (shortest + safest) and a Layer-1 explanation card.
  ///
  /// Behaviour:
  ///  - If the OSM graph is missing → straight-line both routes, empty
  ///    avoided cells, neutral explanation.
  ///  - Otherwise → Yen K-shortest on physical length, then risk re-rank,
  ///    then optional Gemma 4 E4B summaries for top avoided cells.
  Future<RouteResult> findRoutes({
    required LatLng from,
    required LatLng to,
    required DateTime time,
  }) async {
    final graph = _graph;
    if (graph == null) {
      return _straightLineFallback(
        from: from,
        to: to,
        time: time,
        reason: 'Routing unavailable — bundled OSM graph not yet loaded.',
      );
    }

    final src = graph.nearestNode(from);
    final dst = graph.nearestNode(to);

    final yen = YenKShortestPaths(graph);
    final candidates = yen.kShortest(
      sourceNode: src,
      targetNode: dst,
      k: 15,
    );

    if (candidates.isEmpty) {
      // The graph loaded but the two endpoints are disconnected — surface a
      // straight line so the UI still has something to render.
      debugPrint('[RoutingService] no path between $from and $to; '
          'falling back to straight line.');
      return _straightLineFallback(
        from: from,
        to: to,
        time: time,
        reason: 'No walkable path between origin and destination in the '
            'bundled graph.',
      );
    }

    // Step 1 — collect every unique geohash-7 cell touched by any candidate.
    final allCells = <String>{};
    for (final path in candidates) {
      for (int i = 0; i + 1 < path.length; i++) {
        final a = path[i];
        final b = path[i + 1];
        final aEdges = graph.adjacency[a] ?? const <int>[];
        for (final eid in aEdges) {
          final e = graph.edges[eid];
          if (e.other(a) == b) {
            allCells.addAll(e.geohash7Sequence);
            break;
          }
        }
      }
    }

    // Step 2 — pre-compute predictedRisk for every cell (RiskEngine is async,
    // RiskRerank wants a sync function — cache pattern).
    final riskCache = <String, double>{};
    for (final cell in allCells) {
      try {
        riskCache[cell] = await _riskEngine.predictedRisk(cell, time);
      } catch (e) {
        // Risk lookup failures should never abort routing — treat as zero.
        debugPrint('[RoutingService] predictedRisk($cell) threw: $e');
        riskCache[cell] = 0.0;
      }
    }

    // Step 3 — re-rank. Demo için alpha'yı default 100'den 250'ye çıkardık —
    // chokepoint cell skorları (3+ rapor × surge × time) çoğu zaman 5+ değer
    // alır, alpha=100 ile sadece 500m detour mantıklı görünür; 250 ile ~1.2km
    // detour bile justify olur ve safe rota görünür şekilde dolanır.
    final rerank = RiskRerank.pickSafest(
      candidatePaths: candidates,
      graph: graph,
      predictedRisk: (gh) => riskCache[gh] ?? 0.0,
      alpha: 250.0,
    );

    // Step 4 — Layer-1 Gemma E4B summaries for top-N avoided cells. Capped
    // at 3 to keep latency in the demo under control. Failures are logged
    // and swallowed.
    final summaries = <String, String>{};
    if (_useGemmaSummaries && rerank.avoidedCells.isNotEmpty) {
      final topCells = rerank.avoidedCells.take(3).toList(growable: false);
      final isNight = RiskEngine.timeFactor(time) > 1.0;
      for (final cell in topCells) {
        try {
          final reports = await _reports.reportsInCell(
            cell,
            maxAge: const Duration(hours: 24),
          );
          if (reports.isEmpty) continue;
          final summary = await _gemma.summarizeCell(
            geohash7: cell,
            recentReports: reports,
            isNight: isNight,
          );
          summaries[cell] = summary;
        } catch (e) {
          debugPrint(
              '[RoutingService] Gemma summary failed for $cell: $e');
        }
      }
    }

    // Step 5 — build the on-screen surge multiplier (max across avoided
    // cells so the chip shows the worst-case the user is being protected
    // from). Default to 1.0 when there are no avoided cells.
    double surgeMultiplier = 1.0;
    for (final cell in rerank.avoidedCells) {
      try {
        final s = await _surgeFactorForCell(cell, time);
        if (s > surgeMultiplier) surgeMultiplier = s;
      } catch (_) {
        // ignore
      }
    }

    // Step 6 — assemble the polylines and explanation.
    final shortestLatLngs = graph.nodesToPolyline(rerank.shortest);
    final safestLatLngs = graph.nodesToPolyline(rerank.safest);

    // Walking pace ~1.4 m/s ≈ 5 km/h (DEMO copy).
    const walkingMps = 1.4;
    final timeDeltaSeconds = (rerank.distanceDeltaMeters / walkingMps).round();

    final explanation = RouteExplanation(
      avoidedCellSummaries: summaries,
      nightMultiplier: RiskEngine.timeFactor(time),
      surgeMultiplier: surgeMultiplier,
      distanceDeltaMeters: rerank.distanceDeltaMeters,
      timeDeltaSeconds: timeDeltaSeconds,
      gemmaSummary: summaries.values.isNotEmpty ? summaries.values.first : null,
    );

    return RouteResult(
      shortestPath: shortestLatLngs,
      safestPath: safestLatLngs,
      avoidedCells: rerank.avoidedCells,
      explanationCard: explanation,
    );
  }

  /// Approximates a per-cell surge factor by counting recent classified
  /// reports in the trailing 2-hour window. Mirrors `RiskEngine.surgeFactor`
  /// without re-implementing its internal SQL.
  Future<double> _surgeFactorForCell(String geohash7, DateTime now) async {
    final reports = await _reports.reportsInCell(
      geohash7,
      maxAge: RiskEngine.surgeWindow,
    );
    final classified = reports
        .where((r) => r.status == ReportStatus.classified)
        .length;
    return RiskEngine.surgeFactor(classified);
  }

  RouteResult _straightLineFallback({
    required LatLng from,
    required LatLng to,
    required DateTime time,
    required String reason,
  }) {
    return RouteResult(
      shortestPath: <LatLng>[from, to],
      safestPath: <LatLng>[from, to],
      avoidedCells: const <String>[],
      explanationCard: RouteExplanation(
        avoidedCellSummaries: const <String, String>{},
        nightMultiplier: RiskEngine.timeFactor(time),
        surgeMultiplier: 1.0,
        distanceDeltaMeters: 0.0,
        timeDeltaSeconds: 0,
        gemmaSummary: reason,
      ),
    );
  }
}
