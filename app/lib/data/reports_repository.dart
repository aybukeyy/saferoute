// Owns report lifecycle: PENDING -> CLASSIFIED. Coordinates LocalDb,
// GemmaService, RiskEngine, and SyncService. See IMPLEMENTATION.md §2.
//
// The contract: `submitReport` is fire-and-forget for the UI — it writes a
// PENDING row synchronously and returns. The AI classification path runs
// elsewhere (driven by the GemmaService agent) and calls back into
// `updateClassification` once the model has spoken.
//
// Per-UID rate limiting is enforced here because the SQLite history is the
// honest count (a user can clear cache, but Firestore rules will catch that).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/geohash.dart';
import '../core/result.dart';
import '../models/classification.dart';
import '../models/report.dart';
import '../models/risk_cell.dart';
import 'local_db.dart';
import 'risk_engine.dart';
import 'sync_service.dart';

/// Errors surfaced by [ReportsRepository.submitReport].
sealed class SubmitReportError {
  const SubmitReportError();
}

/// Per-UID rate limit: 5/hour or 20/day exceeded. See ARCHITECTURE.md §9.
class RateLimitError extends SubmitReportError {
  final int hourCount;
  final int dayCount;
  final int hourLimit;
  final int dayLimit;
  const RateLimitError({
    required this.hourCount,
    required this.dayCount,
    required this.hourLimit,
    required this.dayLimit,
  });

  @override
  String toString() =>
      'RateLimitError(hour=$hourCount/$hourLimit, day=$dayCount/$dayLimit)';
}

/// Wraps an unexpected exception (DB failure, etc.).
class UnexpectedSubmitError extends SubmitReportError {
  final Object cause;
  final StackTrace stackTrace;
  const UnexpectedSubmitError(this.cause, this.stackTrace);

  @override
  String toString() => 'UnexpectedSubmitError($cause)';
}

class ReportsRepository {
  final LocalDb _db;
  final SyncService _sync;
  final RiskEngine _risk;
  final Uuid _uuid;

  /// Streams that emit `Report` updates per id, used by `watchReport`. Closed
  /// once a row reaches a terminal status (CLASSIFIED or REJECTED).
  final Map<String, StreamController<Report>> _watchers = {};

  /// Broadcast stream of newly-inserted PENDING rows. Drives the
  /// classification worker.
  final StreamController<Report> _pendingController =
      StreamController<Report>.broadcast();

  ReportsRepository({
    required LocalDb db,
    required SyncService sync,
    required RiskEngine risk,
    Uuid? uuid,
  })  : _db = db,
        _sync = sync,
        _risk = risk,
        _uuid = uuid ?? const Uuid();

  /// Hard rate-limit caps. ARCHITECTURE.md §9.
  static const int hourLimit = 5;
  static const int dayLimit = 20;

  /// Writes a PENDING row to SQLite immediately and mirrors it to Firestore.
  /// The AI classifier reads PENDING rows out-of-band and calls
  /// [updateClassification] when done.
  ///
  /// Returns [RateLimitError] if the per-UID hourly or daily quota is hit
  /// (counts are taken from local SQLite — Firestore Security Rules backstop
  /// this for adversarial clients).
  Future<Result<Report, SubmitReportError>> submitReport({
    required String text,
    required LatLng at,
    required DateTime occurredAt,
    required String uid,
  }) async {
    try {
      // 1) Rate-limit check.
      final db = await _db.db;
      final now = DateTime.now().toUtc();
      final hourMs =
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final dayMs =
          now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
      final hourRow = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM reports WHERE uid = ? AND created_at >= ?',
        [uid, hourMs],
      );
      final dayRow = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM reports WHERE uid = ? AND created_at >= ?',
        [uid, dayMs],
      );
      final hourCount = hourRow.first['c'] as int;
      final dayCount = dayRow.first['c'] as int;
      if (hourCount >= hourLimit || dayCount >= dayLimit) {
        return Err(RateLimitError(
          hourCount: hourCount,
          dayCount: dayCount,
          hourLimit: hourLimit,
          dayLimit: dayLimit,
        ));
      }

      // 2) Ensure the user row exists (FK target). Idempotent upsert.
      await db.insert(
        'users',
        {
          'uid': uid,
          'reputation': 1.0,
          'created_at': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // 3) Build + persist the PENDING report.
      final report = Report(
        id: _uuid.v4(),
        uid: uid,
        text: text,
        lat: at.latitude,
        lng: at.longitude,
        geohash7: Geohash.encode(at.latitude, at.longitude, precision: 7),
        occurredAt: occurredAt,
        status: ReportStatus.pending,
        synced: false,
        createdAt: now,
      );
      await db.insert('reports', _reportToRow(report));

      // 4) Mirror immediately so other devices see PENDING dot. If sync is
      //    disabled, this is a no-op.
      unawaited(_sync.mirrorReport(report));

      // 5) Notify any in-flight `watchReport` callers + the pending worker.
      _emit(report);
      if (!_pendingController.isClosed) {
        _pendingController.add(report);
      }

      return Ok(report);
    } catch (e, st) {
      return Err(UnexpectedSubmitError(e, st));
    }
  }

  /// Emits the current row, then any subsequent updates pushed through
  /// [updateClassification]. Closes once status reaches CLASSIFIED or
  /// REJECTED to avoid leaking subscribers.
  Stream<Report> watchReport(String id) {
    final controller = _watchers.putIfAbsent(
      id,
      () => StreamController<Report>.broadcast(),
    );
    // Seed with current row if available.
    () async {
      final row = await _findById(id);
      if (row != null) controller.add(row);
    }();
    return controller.stream;
  }

  /// Newly-inserted PENDING reports. Subscribed to by the classification
  /// worker; existing PENDING rows on disk are surfaced via [pendingReports].
  Stream<Report> watchPending() => _pendingController.stream;

  /// All reports currently in PENDING status, oldest first so the worker
  /// drains them in submission order on boot.
  Future<List<Report>> pendingReports() async {
    final db = await _db.db;
    final rows = await db.query(
      'reports',
      where: 'status = ?',
      whereArgs: [_statusWire(ReportStatus.pending)],
      orderBy: 'created_at ASC',
    );
    return rows.map(_reportFromRow).toList(growable: false);
  }

  /// Most recent reports across all users, newest first.
  Future<List<Report>> recentReports({int limit = 50}) async {
    final db = await _db.db;
    final rows = await db.query(
      'reports',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_reportFromRow).toList(growable: false);
  }

  /// Reports inside a single geohash-7 cell, optionally constrained by age.
  /// Newest first.
  Future<List<Report>> reportsInCell(
    String geohash7, {
    Duration? maxAge,
  }) async {
    final db = await _db.db;
    final args = <Object?>[geohash7];
    var where = 'geohash7 = ?';
    if (maxAge != null) {
      where = '$where AND occurred_at >= ?';
      args.add(
        DateTime.now().toUtc().subtract(maxAge).millisecondsSinceEpoch,
      );
    }
    final rows = await db.query(
      'reports',
      where: where,
      whereArgs: args,
      orderBy: 'occurred_at DESC',
    );
    return rows.map(_reportFromRow).toList(growable: false);
  }

  /// Promotes a row from PENDING to CLASSIFIED (or REJECTED if the parser
  /// flagged review). Recomputes the affected cell and mirrors both rows.
  Future<void> updateClassification(String id, Classification c) async {
    final db = await _db.db;
    final status =
        c.needsReview ? ReportStatus.rejected : ReportStatus.classified;
    await db.update(
      'reports',
      {
        'category': _categoryWire(c.category),
        'risk_level': _riskLevelWire(c.riskLevel),
        'confidence': c.confidence,
        'explanation': c.explanation,
        'status': _statusWire(status),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final updated = await _findById(id);
    if (updated == null) return;

    // Recompute cell only if we successfully classified — REJECTED rows do
    // not contribute (filtered in the SQL).
    if (status == ReportStatus.classified) {
      final now = DateTime.now().toUtc();
      await _risk.recomputeCell(updated.geohash7, now);
      final cellRow = await _findCell(updated.geohash7);
      if (cellRow != null) {
        unawaited(_sync.mirrorRiskCell(cellRow));
      }
    }

    unawaited(_sync.mirrorReport(updated));
    _emit(updated);
    _maybeCloseWatcher(updated);
  }

  /// Records that classification threw before producing a [Classification].
  /// FAILED rows are terminal — they never re-enter the worker queue and are
  /// not mirrored to Firestore.
  Future<void> markClassificationFailed(String id) async {
    final db = await _db.db;
    await db.update(
      'reports',
      {'status': _statusWire(ReportStatus.failed)},
      where: 'id = ?',
      whereArgs: [id],
    );
    final updated = await _findById(id);
    if (updated == null) return;
    _emit(updated);
    _maybeCloseWatcher(updated);
  }

  /// Marks a row's `synced` flag — currently set opportunistically by the
  /// sync layer when a write commits remotely. Surface for tests / future
  /// retry logic.
  Future<void> markSynced(String id) async {
    final db = await _db.db;
    await db.update(
      'reports',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Report?> _findById(String id) async {
    final db = await _db.db;
    final rows = await db.query(
      'reports',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _reportFromRow(rows.first);
  }

  Future<RiskCell?> _findCell(String geohash7) async {
    final db = await _db.db;
    final rows = await db.query(
      'risk_cells',
      where: 'geohash7 = ?',
      whereArgs: [geohash7],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return RiskCell(
      geohash7: r['geohash7'] as String,
      score: (r['score'] as num).toDouble(),
      topCategory: _decodeCategory(r['top_category'] as String?),
      reportCount: r['report_count'] as int,
      summary: r['summary'] as String?,
      summaryAt: r['summary_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              r['summary_at'] as int,
              isUtc: true,
            ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        r['updated_at'] as int,
        isUtc: true,
      ),
    );
  }

  void _emit(Report r) {
    final controller = _watchers[r.id];
    if (controller == null || controller.isClosed) return;
    controller.add(r);
  }

  void _maybeCloseWatcher(Report r) {
    if (r.status == ReportStatus.pending) return;
    final controller = _watchers.remove(r.id);
    controller?.close();
  }
}

// ---------------------------------------------------------------------------
// Row <-> model converters. Lift to a sibling file if a third caller appears.
// ---------------------------------------------------------------------------

Map<String, Object?> _reportToRow(Report r) => {
      'id': r.id,
      'uid': r.uid,
      'text': r.text,
      'lat': r.lat,
      'lng': r.lng,
      'geohash7': r.geohash7,
      'occurred_at': r.occurredAt.millisecondsSinceEpoch,
      'category': _categoryWire(r.category),
      'risk_level': _riskLevelWire(r.riskLevel),
      'confidence': r.confidence,
      'explanation': r.explanation,
      'status': _statusWire(r.status),
      'synced': r.synced ? 1 : 0,
      'created_at': r.createdAt.millisecondsSinceEpoch,
    };

Report _reportFromRow(Map<String, Object?> r) => Report(
      id: r['id'] as String,
      uid: r['uid'] as String,
      text: r['text'] as String,
      lat: (r['lat'] as num).toDouble(),
      lng: (r['lng'] as num).toDouble(),
      geohash7: r['geohash7'] as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        r['occurred_at'] as int,
        isUtc: true,
      ),
      category: _decodeCategory(r['category'] as String?),
      riskLevel: _decodeRiskLevel(r['risk_level'] as String?),
      confidence: (r['confidence'] as num?)?.toDouble(),
      explanation: r['explanation'] as String?,
      status: _decodeStatus(r['status'] as String?) ?? ReportStatus.pending,
      synced: ((r['synced'] as int?) ?? 0) != 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        r['created_at'] as int,
        isUtc: true,
      ),
    );

String? _categoryWire(ReportCategory? c) => switch (c) {
      ReportCategory.violence => 'violence',
      ReportCategory.theft => 'theft',
      ReportCategory.harassment => 'harassment',
      ReportCategory.suspiciousActivity => 'suspicious_activity',
      ReportCategory.vandalism => 'vandalism',
      ReportCategory.other => 'other',
      null => null,
    };

ReportCategory? _decodeCategory(String? raw) {
  if (raw == null) return null;
  for (final c in ReportCategory.values) {
    if (_categoryWire(c) == raw) return c;
  }
  return null;
}

String? _riskLevelWire(RiskLevel? l) => switch (l) {
      RiskLevel.low => 'low',
      RiskLevel.medium => 'medium',
      RiskLevel.high => 'high',
      null => null,
    };

RiskLevel? _decodeRiskLevel(String? raw) {
  if (raw == null) return null;
  for (final l in RiskLevel.values) {
    if (_riskLevelWire(l) == raw) return l;
  }
  return null;
}

String _statusWire(ReportStatus s) => switch (s) {
      ReportStatus.pending => 'PENDING',
      ReportStatus.classified => 'CLASSIFIED',
      ReportStatus.rejected => 'REJECTED',
      ReportStatus.failed => 'FAILED',
    };

ReportStatus? _decodeStatus(String? raw) {
  switch (raw) {
    case 'PENDING':
      return ReportStatus.pending;
    case 'CLASSIFIED':
      return ReportStatus.classified;
    case 'REJECTED':
      return ReportStatus.rejected;
    case 'FAILED':
      return ReportStatus.failed;
    default:
      return null;
  }
}

/// Async because [SyncService] init is async. Repositories that need this
/// should consume it through `ref.watch(reportsRepositoryProvider.future)`
/// or wait on the sync provider first.
final reportsRepositoryProvider = FutureProvider<ReportsRepository>((ref) async {
  final sync = await ref.watch(syncServiceProvider.future);
  return ReportsRepository(
    db: ref.watch(localDbProvider),
    sync: sync,
    risk: ref.watch(riskEngineProvider),
  );
});
