// UI-side Riverpod providers for the features layer.
//
// IMPORTANT — these are *interfaces + safe stubs* the UI consumes. The
// Integration agent overrides every provider in this file via
// `ProviderScope.overrides` in main.dart with the production
// LocationService / ReportsRepository / RiskEngine / RoutingService /
// SyncService implementations once those modules land.
//
// The stubs are wired to a deterministic in-memory fixture so the widgets
// boot, animate, and pass widget tests without any of the data/ai/routing
// agents having shipped yet. They are NOT meant for production behaviour —
// every provider here is a `Provider` (sync) returning either a real
// instance or a typed fixture; nothing here touches Firebase, sqflite, or
// flutter_gemma.
//
// When a real module lands, the integration agent does:
//   ProviderScope(
//     overrides: [
//       locationServiceProvider.overrideWithValue(realLocationService),
//       reportsRepositoryProvider.overrideWithValue(realReportsRepository),
//       ...
//     ],
//     child: SafeRouteApp(),
//   );

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../ai/gemma_service.dart';
import '../core/geohash.dart';
import '../models/report.dart';
import '../models/route_result.dart';

/// Bounding box used by heatmap and cell-pulse listeners. Mirrors what the
/// SyncService and RiskEngine signatures will accept.
class BoundingBox {
  const BoundingBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  @override
  bool operator ==(Object other) =>
      other is BoundingBox &&
      other.south == south &&
      other.west == west &&
      other.north == north &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);
}

/// One pulse event — the sync stream emits these whenever a cell flips
/// from unseen to seen, or a fresh report touches it.
class CellPulse {
  const CellPulse({required this.geohash7, required this.score});

  final String geohash7;
  final double score;
}

// ---------------------------------------------------------------------------
// Service interfaces the UI consumes.
//
// The real classes live in lib/data/, lib/core/, lib/routing/. The fixtures
// below match the public surface the UI needs without forcing a dependency
// on those modules' generated code (which may not exist yet at build time
// when the integration agent is wiring overrides).
// ---------------------------------------------------------------------------

abstract class LocationServiceLike {
  Stream<LatLng> watchPosition();
  Future<LatLng> currentPosition();
}

abstract class ReportsRepositoryLike {
  Future<Report> submitReport({
    required String text,
    required LatLng at,
    String? photoLocalPath,
    String? photoUrl,
  });
  Future<List<Report>> recentReports({int limit = 50});
  Future<List<Report>> reportsInCell(String geohash7);
}

abstract class RiskEngineLike {
  /// `predicted_risk` per cell, normalized to [0, 1].
  Map<String, double> heatmap(BoundingBox bbox, DateTime now);

  /// Multipliers — these appear verbatim in the Layer-3 explanation.
  double timeFactor(DateTime t);
  double surgeFactor(String geohash7, DateTime t);
}

abstract class RoutingServiceLike {
  Future<RouteResult> findRoutes({
    required LatLng from,
    required LatLng to,
    required DateTime time,
  });
}

abstract class SyncServiceLike {
  Stream<CellPulse> watchCells(BoundingBox bbox);
  Future<String> ensureAnonymousAuth();
}

// ---------------------------------------------------------------------------
// Providers. Defaults wire to the in-memory fixture below — Integration
// agent overrides these with the real services.
// ---------------------------------------------------------------------------

final locationServiceProvider = Provider<LocationServiceLike>((ref) {
  return _FixtureLocationService();
});

final reportsRepositoryProvider = Provider<ReportsRepositoryLike>((ref) {
  return _FixtureReportsRepository();
});

final riskEngineProvider = Provider<RiskEngineLike>((ref) {
  return _FixtureRiskEngine();
});

final routingServiceProvider = Provider<RoutingServiceLike>((ref) {
  return _FixtureRoutingService();
});

final syncServiceProvider = Provider<SyncServiceLike>((ref) {
  return _FixtureSyncService();
});

/// Streams the user's current GPS position. UI uses this for the "you are
/// here" marker and to pre-fill the report sheet's location chip.
final currentLocationProvider = StreamProvider<LatLng>((ref) {
  return ref.watch(locationServiceProvider).watchPosition();
});

/// Stable per-device UID issued by Firebase Anonymous Auth. UI uses it for
/// rate-limit display + to attribute reports.
final currentUserUidProvider = FutureProvider<String>((ref) {
  return ref.watch(syncServiceProvider).ensureAnonymousAuth();
});

/// Bumped by the real heatmap adapter every time a fresh snapshot lands in
/// its cache. `heatmapDataProvider` watches this so the UI rebuilds without
/// the adapter having to invalidate `heatmapDataProvider` itself (which
/// triggers a CircularDependencyError because the adapter is one of the
/// family's transitive dependencies).
class HeatmapRefreshTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final heatmapRefreshTickProvider =
    NotifierProvider<HeatmapRefreshTick, int>(HeatmapRefreshTick.new);

/// Heatmap data for the visible bbox. The UI keeps the bbox stable within a
/// camera idle window so this provider doesn't recompute on every gesture
/// frame.
final heatmapDataProvider =
    Provider.family<Map<String, double>, BoundingBox>((ref, bbox) {
  // Force a rebuild whenever the adapter's background fetch completes.
  ref.watch(heatmapRefreshTickProvider);
  final engine = ref.watch(riskEngineProvider);
  return engine.heatmap(bbox, DateTime.now());
});

/// Stream of cell pulse events for the visible bbox. The map's pulse
/// animator subscribes to this.
final cellPulseStreamProvider =
    StreamProvider.family<CellPulse, BoundingBox>((ref, bbox) {
  return ref.watch(syncServiceProvider).watchCells(bbox);
});

/// Reports inside a single cell — drives the Layer-2 "tap on cell" sheet.
final reportsInCellProvider =
    FutureProvider.family<List<Report>, String>((ref, geohash7) {
  return ref.watch(reportsRepositoryProvider).reportsInCell(geohash7);
});

/// Mode-2 Gemma 4 E4B area summary for a single cell. Drives the header in
/// `CellReportsSheet`. The 5-minute TTL lives inside `GemmaService`.
final cellAreaSummaryProvider =
    FutureProvider.family<String, String>((ref, geohash7) async {
  final reports = await ref.watch(reportsInCellProvider(geohash7).future);
  final now = DateTime.now();
  final isNight = now.hour >= 22 || now.hour < 5;
  return ref.watch(gemmaServiceProvider).summarizeCell(
        geohash7: geohash7,
        recentReports: reports,
        isNight: isNight,
      );
});

/// Recent reports list for the feed screen.
final recentReportsProvider = FutureProvider<List<Report>>((ref) {
  return ref.watch(reportsRepositoryProvider).recentReports(limit: 50);
});

/// Route lookup. Family key is `(from, to, timeBucket)`. The time bucket
/// rounds down to the minute so identical inputs share a result.
class RouteQuery {
  const RouteQuery({
    required this.from,
    required this.to,
    required this.time,
  });

  final LatLng from;
  final LatLng to;
  final DateTime time;

  @override
  bool operator ==(Object other) {
    return other is RouteQuery &&
        other.from.latitude == from.latitude &&
        other.from.longitude == from.longitude &&
        other.to.latitude == to.latitude &&
        other.to.longitude == to.longitude &&
        other.time.millisecondsSinceEpoch ~/ 60000 ==
            time.millisecondsSinceEpoch ~/ 60000;
  }

  @override
  int get hashCode => Object.hash(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
        time.millisecondsSinceEpoch ~/ 60000,
      );
}

final routeResultProvider =
    FutureProvider.family<RouteResult, RouteQuery>((ref, q) {
  return ref.watch(routingServiceProvider).findRoutes(
        from: q.from,
        to: q.to,
        time: q.time,
      );
});

// ---------------------------------------------------------------------------
// Fixtures — purely UI-development scaffolding. Integration agent replaces.
// ---------------------------------------------------------------------------

const LatLng _kFixtureCenter = LatLng(41.0082, 28.9784); // Sultanahmet, IST.

class _FixtureLocationService implements LocationServiceLike {
  @override
  Stream<LatLng> watchPosition() async* {
    yield _kFixtureCenter;
  }

  @override
  Future<LatLng> currentPosition() async => _kFixtureCenter;
}

class _FixtureReportsRepository implements ReportsRepositoryLike {
  final List<Report> _store = _seedReports();

  @override
  Future<Report> submitReport({
    required String text,
    required LatLng at,
    String? photoLocalPath,
    String? photoUrl,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now();
    final report = Report(
      id: 'fx-${now.microsecondsSinceEpoch}',
      uid: 'fixture-uid',
      text: text,
      lat: at.latitude,
      lng: at.longitude,
      geohash7: Geohash.encode(at.latitude, at.longitude),
      occurredAt: now,
      status: ReportStatus.pending,
      createdAt: now,
      photoLocalPath: photoLocalPath,
      photoUrl: photoUrl,
    );
    _store.insert(0, report);
    return report;
  }

  @override
  Future<List<Report>> recentReports({int limit = 50}) async {
    return List.unmodifiable(_store.take(limit));
  }

  @override
  Future<List<Report>> reportsInCell(String geohash7) async {
    return _store.where((r) => r.geohash7 == geohash7).toList(growable: false);
  }
}

class _FixtureRiskEngine implements RiskEngineLike {
  @override
  Map<String, double> heatmap(BoundingBox bbox, DateTime now) {
    final cells = Geohash.cellsInBoundingBox(
      minLat: bbox.south,
      maxLat: bbox.north,
      minLng: bbox.west,
      maxLng: bbox.east,
    );
    // Deterministic gradient: cells "closer" to the centre get a higher
    // score so the demo always has something visible.
    final centerLat = (bbox.south + bbox.north) / 2;
    final centerLng = (bbox.west + bbox.east) / 2;
    final span = (bbox.north - bbox.south).abs() +
        (bbox.east - bbox.west).abs();
    final out = <String, double>{};
    for (final c in cells) {
      final b = Geohash.bounds(c);
      final cLat = (b.minLat + b.maxLat) / 2;
      final cLng = (b.minLng + b.maxLng) / 2;
      final d = ((cLat - centerLat).abs() + (cLng - centerLng).abs());
      final score = (1.0 - (d / (span / 2 + 1e-9))).clamp(0.0, 1.0).toDouble();
      if (score > 0.05) {
        out[c] = score;
      }
    }
    return out;
  }

  @override
  double timeFactor(DateTime t) {
    final h = t.hour;
    final isNight = h >= 22 || h < 5;
    return isNight ? 1.5 : 1.0;
  }

  @override
  double surgeFactor(String geohash7, DateTime t) {
    // Fixture: middling surge so the explanation card has a non-trivial value.
    return 2.0;
  }
}

class _FixtureRoutingService implements RoutingServiceLike {
  @override
  Future<RouteResult> findRoutes({
    required LatLng from,
    required LatLng to,
    required DateTime time,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Shortest = straight-ish line (3 points).
    final shortest = <LatLng>[
      from,
      LatLng(
        (from.latitude * 0.5 + to.latitude * 0.5),
        (from.longitude * 0.5 + to.longitude * 0.5),
      ),
      to,
    ];

    // Safest = arc that swings north of midpoint to "avoid" a hot cell.
    final midLat = (from.latitude + to.latitude) / 2;
    final midLng = (from.longitude + to.longitude) / 2;
    final arcLat = midLat + (to.longitude - from.longitude).abs() * 0.4;
    final safest = <LatLng>[
      from,
      LatLng(
        (from.latitude * 0.7 + arcLat * 0.3),
        (from.longitude * 0.7 + midLng * 0.3),
      ),
      LatLng(arcLat, midLng),
      LatLng(
        (to.latitude * 0.7 + arcLat * 0.3),
        (to.longitude * 0.7 + midLng * 0.3),
      ),
      to,
    ];

    final avoidedCellHash = Geohash.encode(midLat, midLng);

    return RouteResult(
      shortestPath: shortest,
      safestPath: safest,
      avoidedCells: [avoidedCellHash],
      explanationCard: RouteExplanation(
        avoidedCellSummaries: {
          avoidedCellHash: '3 reports tonight',
        },
        nightMultiplier: 1.5,
        surgeMultiplier: 2.0,
        distanceDeltaMeters: 180,
        timeDeltaSeconds: 120,
        gemmaSummary:
            'This route detours around a small cluster of recent harassment '
            'reports near the park entrance.',
      ),
    );
  }
}

class _FixtureSyncService implements SyncServiceLike {
  @override
  Stream<CellPulse> watchCells(BoundingBox bbox) async* {
    // Emit nothing in the fixture so the map doesn't fake-pulse during dev.
    // The integration override delivers real Firestore events.
  }

  @override
  Future<String> ensureAnonymousAuth() async => 'fixture-uid';
}

List<Report> _seedReports() {
  final now = DateTime.now();
  String hash(double lat, double lng) => Geohash.encode(lat, lng);
  Report mk(int i, String text, ReportCategory cat, RiskLevel lvl) {
    final lat = _kFixtureCenter.latitude + (i.isOdd ? 0.0008 : -0.0006);
    final lng = _kFixtureCenter.longitude + (i.isOdd ? -0.0011 : 0.0009);
    final occurred = now.subtract(Duration(minutes: 15 * i + 3));
    return Report(
      id: 'seed-$i',
      uid: 'seed-uid',
      text: text,
      lat: lat,
      lng: lng,
      geohash7: hash(lat, lng),
      occurredAt: occurred,
      category: cat,
      riskLevel: lvl,
      confidence: 0.78,
      explanation:
          'Fixture explanation — a brief, neutral reading produced by Gemma 4 E2B.',
      status: ReportStatus.classified,
      synced: false,
      createdAt: occurred,
    );
  }

  return <Report>[
    mk(1, 'Two men were following a woman near the park entrance.',
        ReportCategory.harassment, RiskLevel.medium),
    mk(2, 'Phone snatched off a table at a cafe.',
        ReportCategory.theft, RiskLevel.medium),
    mk(3, 'Loud argument between strangers, no weapons.',
        ReportCategory.suspiciousActivity, RiskLevel.low),
  ];
}
