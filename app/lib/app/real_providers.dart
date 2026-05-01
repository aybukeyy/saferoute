// Bridges the **real** data / AI / routing implementations to the **`*Like`
// interfaces** the UI screens consume from `lib/features/providers.dart`.
//
// Why adapters and not `implements`?
//
// The data/ai/routing modules were written with their own provider names and
// concrete API surfaces (e.g. `ReportsRepository.submitReport` returns a
// `Result<>` and requires `uid` + `occurredAt`; the UI's `submitReport` only
// hands in `text` + `at`). Editing every real class to match the UI
// interface would force a major refactor across modules. Wrapping each real
// service in a thin `_Adapter implements XLike` shim keeps the production
// code paths untouched.
//
// Wired up in `lib/main.dart` via `ProviderContainer(overrides: [...])`.
//
// Source-of-truth doc: docs/planning/IMPLEMENTATION.md §6 + §8.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../ai/gemma_service.dart';
import '../ai/model_storage.dart';
import '../core/location_service.dart';
import '../core/result.dart';
import '../data/local_db.dart';
import '../data/reports_repository.dart' as data;
import '../data/proximity_alert_service.dart';
import '../data/reputation_sync.dart';
import '../data/risk_engine.dart' as data;
import '../data/sync_service.dart' as data;
import '../features/providers.dart' as ui;
import '../models/report.dart';
import '../models/route_result.dart';
import '../routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Pinned UID provider — overridden in main() with the result of
// SyncService.ensureAnonymousAuth(). UI-side `currentUserUidProvider` resolves
// off this so the report submission flow always has a uid to attribute writes
// to without re-running anonymous auth on every tap.
// ---------------------------------------------------------------------------

final currentUserUidValueProvider = Provider<String>((ref) {
  // Default placeholder so widget tests pass without a Firebase init step.
  // main() overrides this with the live value from `SyncService`.
  return 'local-only';
});

// ---------------------------------------------------------------------------
// Real-service providers. Each returns a concrete data/ai/routing instance.
// The *Like-interface providers below wrap them in adapters.
// ---------------------------------------------------------------------------

final realLocationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final realSyncServiceProvider = FutureProvider<data.SyncService>((ref) async {
  return data.SyncService.tryInitialize();
});

final realRiskEngineProvider = Provider<data.RiskEngine>((ref) {
  final db = ref.watch(localDbProvider);
  return data.RiskEngine(db);
});

final realReportsRepositoryProvider =
    FutureProvider<data.ReportsRepository>((ref) async {
  final sync = await ref.watch(realSyncServiceProvider.future);
  return data.ReportsRepository(
    db: ref.watch(localDbProvider),
    sync: sync,
    risk: ref.watch(realRiskEngineProvider),
  );
});

final realGemmaServiceProvider = Provider<GemmaService>((ref) {
  final storage = ref.watch(modelStorageProvider);
  final service = GemmaService(storage: storage);
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final realReputationSyncProvider =
    FutureProvider<ReputationSync>((ref) async {
  final sync = await ref.watch(realSyncServiceProvider.future);
  final reports = await ref.watch(realReportsRepositoryProvider.future);
  final svc = ReputationSync(
    db: ref.watch(localDbProvider),
    sync: sync,
    reports: reports,
    currentUid: ref.watch(currentUserUidValueProvider),
  );
  await svc.start();
  ref.onDispose(() => unawaited(svc.dispose()));
  return svc;
});

/// Overridden in `main()` after `flutter_local_notifications` is initialized.
/// Default no-op so widget tests don't trigger native plugin code.
final proximityNotificationDispatcherProvider =
    Provider<NotificationDispatcher>((ref) {
  return ({required int id, required String title, required String body}) async {
    debugPrint('[proximity] (no-op dispatcher) $title — $body');
  };
});

final realProximityAlertServiceProvider =
    FutureProvider<ProximityAlertService>((ref) async {
  final reports = await ref.watch(realReportsRepositoryProvider.future);
  final svc = ProximityAlertService(
    location: ref.watch(realLocationServiceProvider),
    risk: ref.watch(realRiskEngineProvider),
    reports: reports,
    dispatcher: ref.watch(proximityNotificationDispatcherProvider),
  );
  await svc.start();
  ref.onDispose(() => unawaited(svc.dispose()));
  return svc;
});

final realRoutingServiceProvider =
    FutureProvider<RoutingService>((ref) async {
  final risk = ref.watch(realRiskEngineProvider);
  final reports = await ref.watch(realReportsRepositoryProvider.future);
  final gemma = ref.watch(realGemmaServiceProvider);
  return RoutingService.bootstrap(
    riskEngine: risk,
    reports: reports,
    gemma: gemma,
  );
});

// ---------------------------------------------------------------------------
// Adapters bridging real services → `*Like` interfaces.
// ---------------------------------------------------------------------------

class _LocationServiceAdapter implements ui.LocationServiceLike {
  _LocationServiceAdapter(this._inner);
  final LocationService _inner;

  @override
  Stream<LatLng> watchPosition() => _inner.watchPosition();

  @override
  Future<LatLng> currentPosition() => _inner.currentPosition();
}

class _ReportsRepositoryAdapter implements ui.ReportsRepositoryLike {
  _ReportsRepositoryAdapter(this._inner, this._uid);
  final data.ReportsRepository _inner;
  final String _uid;

  @override
  Future<Report> submitReport({
    required String text,
    required LatLng at,
    String? photoLocalPath,
  }) async {
    final res = await _inner.submitReport(
      text: text,
      at: at,
      occurredAt: DateTime.now().toUtc(),
      uid: _uid,
      photoLocalPath: photoLocalPath,
    );
    return switch (res) {
      Ok(value: final r) => r,
      Err(error: final e) => throw _SubmitReportException(e),
    };
  }

  @override
  Future<List<Report>> recentReports({int limit = 50}) =>
      _inner.recentReports(limit: limit);

  @override
  Future<List<Report>> reportsInCell(String geohash7) =>
      _inner.reportsInCell(geohash7);
}

/// Thrown by [_ReportsRepositoryAdapter.submitReport] when the underlying
/// `ReportsRepository` returns an `Err`. The UI's `_humaniseError` already
/// pattern-matches on the message ("rate", "limit", "location") so we keep
/// the toString readable.
class _SubmitReportException implements Exception {
  _SubmitReportException(this.error);
  final data.SubmitReportError error;

  @override
  String toString() => switch (error) {
        data.RateLimitError() => 'Rate limit exceeded — $error',
        data.UnexpectedSubmitError(cause: final c) => 'Submission failed: $c',
      };
}

/// Caches the most recent heatmap snapshot so the UI's *sync*
/// `RiskEngineLike.heatmap` call has something to return immediately. The
/// background fetch refreshes the cache and invalidates the
/// `realHeatmapRefreshTickProvider`, which forces the family provider to
/// recompute and pick up new values.
class _RiskEngineAdapter implements ui.RiskEngineLike {
  _RiskEngineAdapter(this._inner, this._ref);
  final data.RiskEngine _inner;
  final Ref _ref;

  // bbox-keyed cache of the latest heatmap snapshot.
  static final _cache = <ui.BoundingBox, Map<String, double>>{};
  // Per-bbox guard so we only have one in-flight fetch at a time.
  static final _inFlight = <ui.BoundingBox, Future<void>>{};

  @override
  Map<String, double> heatmap(ui.BoundingBox bbox, DateTime now) {
    // Kick a background refresh; return whatever we cached last.
    _kickRefresh(bbox, now);
    return _cache[bbox] ?? const <String, double>{};
  }

  void _kickRefresh(ui.BoundingBox bbox, DateTime now) {
    if (_inFlight.containsKey(bbox)) {
      debugPrint('[_RiskEngineAdapter] kick skipped (in flight) '
          'S=${bbox.south.toStringAsFixed(3)} N=${bbox.north.toStringAsFixed(3)} '
          'W=${bbox.west.toStringAsFixed(3)} E=${bbox.east.toStringAsFixed(3)}');
      return;
    }
    debugPrint('[_RiskEngineAdapter] kick START '
        'S=${bbox.south.toStringAsFixed(3)} N=${bbox.north.toStringAsFixed(3)} '
        'W=${bbox.west.toStringAsFixed(3)} E=${bbox.east.toStringAsFixed(3)}');
    final future = () async {
      try {
        final snapshot = await _inner.heatmap(
          bbox: data.BoundingBox(
            minLat: bbox.south,
            maxLat: bbox.north,
            minLng: bbox.west,
            maxLng: bbox.east,
          ),
          now: now,
        );
        _cache[bbox] = snapshot;
        debugPrint('[_RiskEngineAdapter] kick DONE: ${snapshot.length} cells; '
            'cache size now ${_cache.length}');
        // Defer invalidate so we're outside the provider's build cycle —
        // direct invalidate from inside it triggers CircularDependencyError.
        Future.microtask(() {
          try {
            _ref.invalidate(ui.heatmapDataProvider(bbox));
            debugPrint('[_RiskEngineAdapter] invalidated heatmapDataProvider');
          } catch (e) {
            debugPrint('[_RiskEngineAdapter] invalidate failed: $e');
          }
        });
      } catch (e, st) {
        debugPrint('[_RiskEngineAdapter] heatmap fetch failed: $e\n$st');
      } finally {
        _inFlight.remove(bbox);
      }
    }();
    _inFlight[bbox] = future;
  }

  @override
  double timeFactor(DateTime t) => data.RiskEngine.timeFactor(t);

  @override
  double surgeFactor(String geohash7, DateTime t) {
    // The synchronous-by-contract UI surge factor doesn't have a reliable
    // path to the DB count; we conservatively return 1.0 here. The Layer 1
    // explanation card consumes per-cell surge from `RouteExplanation`,
    // which is computed in `RoutingService` with the real per-cell count.
    return 1.0;
  }
}

class _RoutingServiceAdapter implements ui.RoutingServiceLike {
  _RoutingServiceAdapter(this._inner);
  final RoutingService _inner;

  @override
  Future<RouteResult> findRoutes({
    required LatLng from,
    required LatLng to,
    required DateTime time,
  }) =>
      _inner.findRoutes(from: from, to: to, time: time);
}

class _SyncServiceAdapter implements ui.SyncServiceLike {
  _SyncServiceAdapter(this._inner);
  final data.SyncService _inner;

  @override
  Stream<ui.CellPulse> watchCells(ui.BoundingBox bbox) {
    return _inner
        .watchCells(data.BoundingBox(
          minLat: bbox.south,
          maxLat: bbox.north,
          minLng: bbox.west,
          maxLng: bbox.east,
        ))
        .where((u) => u.pulse)
        .map((u) => ui.CellPulse(geohash7: u.cell.geohash7, score: u.cell.score));
  }

  @override
  Future<String> ensureAnonymousAuth() => _inner.ensureAnonymousAuth();
}

// ---------------------------------------------------------------------------
// `*Like` provider overrides — these are what `main.dart` slots into the
// `ProviderContainer.overrides` list. Each watches its `real*Provider`
// counterpart and returns the adapter shim.
// ---------------------------------------------------------------------------

final realLocationServiceLikeProvider = Provider<ui.LocationServiceLike>((ref) {
  return _LocationServiceAdapter(ref.watch(realLocationServiceProvider));
});

/// Adapter for the UI's `reportsRepositoryProvider`. This is `Provider<…>`
/// (sync, returning the *Like) and bridges to the async real repo by gating
/// behind `realReportsRepositoryProvider.future`. Until the real repo
/// resolves we hand back a "warming up" stub that throws a friendly error if
/// the user taps Submit before init completes — in practice the boot path
/// always completes long before the user can press the button.
final realReportsRepositoryLikeProvider =
    Provider<ui.ReportsRepositoryLike>((ref) {
  final asyncRepo = ref.watch(realReportsRepositoryProvider);
  final uid = ref.watch(currentUserUidValueProvider);
  return asyncRepo.maybeWhen(
    data: (repo) => _ReportsRepositoryAdapter(repo, uid),
    orElse: () => _WarmingUpReportsRepository(),
  );
});

final realRiskEngineLikeProvider = Provider<ui.RiskEngineLike>((ref) {
  return _RiskEngineAdapter(ref.watch(realRiskEngineProvider), ref);
});

final realRoutingServiceLikeProvider =
    Provider<ui.RoutingServiceLike>((ref) {
  final asyncSvc = ref.watch(realRoutingServiceProvider);
  return asyncSvc.maybeWhen(
    data: (svc) => _RoutingServiceAdapter(svc),
    orElse: () => _WarmingUpRoutingService(),
  );
});

final realSyncServiceLikeProvider = Provider<ui.SyncServiceLike>((ref) {
  final asyncSvc = ref.watch(realSyncServiceProvider);
  return asyncSvc.maybeWhen(
    data: (svc) => _SyncServiceAdapter(svc),
    orElse: () => _WarmingUpSyncService(),
  );
});

// ---------------------------------------------------------------------------
// Stubs returned while async dependencies are still resolving. These keep
// the synchronous *Like contract honest without crashing the UI on first
// frame.
// ---------------------------------------------------------------------------

class _WarmingUpReportsRepository implements ui.ReportsRepositoryLike {
  @override
  Future<Report> submitReport({
    required String text,
    required LatLng at,
    String? photoLocalPath,
  }) {
    throw StateError('Reports repository still warming up — try again.');
  }

  @override
  Future<List<Report>> recentReports({int limit = 50}) async => const [];

  @override
  Future<List<Report>> reportsInCell(String geohash7) async => const [];
}

class _WarmingUpRoutingService implements ui.RoutingServiceLike {
  @override
  Future<RouteResult> findRoutes({
    required LatLng from,
    required LatLng to,
    required DateTime time,
  }) async {
    throw StateError('Routing service still warming up — try again.');
  }
}

class _WarmingUpSyncService implements ui.SyncServiceLike {
  @override
  Stream<ui.CellPulse> watchCells(ui.BoundingBox bbox) =>
      const Stream<ui.CellPulse>.empty();

  @override
  Future<String> ensureAnonymousAuth() async => 'local-only';
}
