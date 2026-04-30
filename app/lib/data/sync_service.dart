// Firestore mirror with offline persistence. Anonymous Auth UID is the spam
// unit. Real-time listener emits cell pulse events. See ARCHITECTURE.md §2.4
// and §8 + IMPLEMENTATION.md §5.
//
// Graceful degradation: Firebase init can fail (no firebase_options.dart at
// dev time) — in that case every public method becomes a no-op and the app
// still works in local-only mode. The user sees the local heatmap; pulse
// updates from other devices simply never fire. We log loudly once so the
// developer notices.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/geohash.dart';
import '../firebase_options.dart';
import '../models/report.dart';
import '../models/risk_cell.dart';
import 'risk_engine.dart';

/// A pulse-flagged cell update emitted by [SyncService.watchCells]. The UI
/// uses [pulse] to decide whether to play the grey→orange→red animation.
class RiskCellUpdate {
  final RiskCell cell;
  final bool pulse;
  const RiskCellUpdate({required this.cell, required this.pulse});
}

/// Wraps Firestore + Anonymous Auth. Construct via [SyncService.tryInitialize]
/// — it returns a no-op fake when Firebase isn't configured so callers can
/// stay unconditional.
class SyncService {
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final bool _enabled;

  SyncService._({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required bool enabled,
  })  : _firestore = firestore,
        _auth = auth,
        _enabled = enabled;

  /// True when Firebase initialized successfully and writes/reads are live.
  bool get isEnabled => _enabled;

  /// Best-effort init. Calls `Firebase.initializeApp()` if no app is already
  /// registered, enables Firestore offline persistence, and returns a live
  /// SyncService. On any failure (missing options, web/native mismatch, etc.)
  /// returns a disabled SyncService that no-ops every call.
  static Future<SyncService> tryInitialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final firestore = FirebaseFirestore.instance;
      // Idempotent — sqflite-style. Wrapped in try because some platforms
      // throw if settings are touched after the first read.
      try {
        firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (e) {
        debugPrint('SyncService: settings already applied ($e)');
      }
      return SyncService._(
        firestore: firestore,
        auth: FirebaseAuth.instance,
        enabled: true,
      );
    } catch (e, st) {
      debugPrint(
        'SyncService: Firestore not configured — sync disabled. ($e)\n$st',
      );
      return SyncService._(enabled: false);
    }
  }

  /// Returns a stable per-device UID. If anonymous auth fails, falls back to
  /// the special string `local-only` — repositories use that as the user
  /// row's primary key when sync is disabled.
  Future<String> ensureAnonymousAuth() async {
    if (!_enabled || _auth == null) return 'local-only';
    final existing = _auth.currentUser;
    if (existing != null) return existing.uid;
    try {
      final cred = await _auth.signInAnonymously();
      return cred.user?.uid ?? 'local-only';
    } catch (e) {
      debugPrint('SyncService: anonymous auth failed ($e); using local-only.');
      return 'local-only';
    }
  }

  /// Mirrors a single report doc. Always sets `pulse: true` so other devices'
  /// listeners trigger the animation; we don't bother clearing pulse later
  /// (acceptable hack for the hackathon).
  Future<void> mirrorReport(Report r) async {
    if (!_enabled || _firestore == null) return;
    try {
      await _firestore.collection('reports').doc(r.id).set(<String, dynamic>{
        'uid': r.uid,
        'text': r.text,
        'lat': r.lat,
        'lng': r.lng,
        'geohash7': r.geohash7,
        'occurredAt': Timestamp.fromDate(r.occurredAt),
        'category': _categoryWire(r.category),
        'riskLevel': _riskLevelWire(r.riskLevel),
        'confidence': r.confidence,
        'explanation': r.explanation,
        'status': _statusWire(r.status),
        'createdAt': Timestamp.fromDate(r.createdAt),
        'pulse': true,
      });
    } catch (e) {
      debugPrint('SyncService.mirrorReport: $e');
    }
  }

  /// Mirrors a recomputed risk_cell row. Always sets `pulse: true`.
  Future<void> mirrorRiskCell(RiskCell c) async {
    if (!_enabled || _firestore == null) return;
    try {
      await _firestore
          .collection('risk_cells')
          .doc(c.geohash7)
          .set(<String, dynamic>{
        'score': c.score,
        'topCategory': _categoryWire(c.topCategory),
        'reportCount': c.reportCount,
        'summary': c.summary,
        'summaryAt': c.summaryAt == null ? null : Timestamp.fromDate(c.summaryAt!),
        'updatedAt': Timestamp.fromDate(c.updatedAt),
        'pulse': true,
      });
    } catch (e) {
      debugPrint('SyncService.mirrorRiskCell: $e');
    }
  }

  /// Streams every risk_cell whose geohash7 falls in [bbox]. Uses Firestore's
  /// lexicographic range query on the docId, scoped to the inclusive prefix
  /// range derived from the bounding box corner cells.
  ///
  /// Caveat: the bbox-derived range can over-fetch (geohash lex order is not
  /// strictly geographic). We post-filter in Dart to drop strays. This is
  /// fine at hackathon scale — a few hundred docs at most.
  Stream<RiskCellUpdate> watchCells(BoundingBox bbox) {
    if (!_enabled || _firestore == null) {
      return const Stream<RiskCellUpdate>.empty();
    }
    final cells = Geohash.cellsInBoundingBox(
      minLat: bbox.minLat,
      maxLat: bbox.maxLat,
      minLng: bbox.minLng,
      maxLng: bbox.maxLng,
    );
    if (cells.isEmpty) return const Stream<RiskCellUpdate>.empty();

    cells.sort();
    final lower = cells.first;
    // High-end of geohash sort — append `~` (above z) to make it inclusive.
    final upper = '${cells.last}~';

    final query = _firestore
        .collection('risk_cells')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: lower)
        .where(FieldPath.documentId, isLessThanOrEqualTo: upper);

    final inSet = cells.toSet();

    return query.snapshots().asyncExpand((snap) async* {
      for (final change in snap.docChanges) {
        final doc = change.doc;
        if (!inSet.contains(doc.id)) continue; // strict bbox filter
        final cell = _riskCellFromDoc(doc);
        if (cell == null) continue;
        final pulse = (doc.data()?['pulse'] as bool?) ?? false;
        yield RiskCellUpdate(cell: cell, pulse: pulse);
      }
    });
  }

  /// Streams the user's reputation. Emits 1.0 when sync is disabled or the
  /// doc doesn't exist yet.
  Stream<double> watchReputation(String uid) {
    if (!_enabled || _firestore == null || uid == 'local-only') {
      return Stream<double>.value(1.0);
    }
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return 1.0;
      final v = data['reputation'];
      if (v is num) return v.toDouble();
      return 1.0;
    });
  }
}

RiskCell? _riskCellFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  if (data == null) return null;
  try {
    return RiskCell(
      geohash7: doc.id,
      score: (data['score'] as num?)?.toDouble() ?? 0.0,
      topCategory: _decodeCategory(data['topCategory'] as String?),
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      summary: data['summary'] as String?,
      summaryAt: (data['summaryAt'] as Timestamp?)?.toDate(),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now().toUtc(),
    );
  } catch (e) {
    debugPrint('SyncService: malformed risk_cell ${doc.id}: $e');
    return null;
  }
}

ReportCategory? _decodeCategory(String? raw) {
  if (raw == null) return null;
  for (final c in ReportCategory.values) {
    if (_categoryWire(c) == raw) return c;
  }
  return null;
}

String? _categoryWire(ReportCategory? c) => switch (c) {
      ReportCategory.violence => 'violence',
      ReportCategory.theft => 'theft',
      ReportCategory.harassment => 'harassment',
      ReportCategory.suspiciousActivity => 'suspicious_activity',
      ReportCategory.vandalism => 'vandalism',
      ReportCategory.other => 'other',
      null => null,
    };

String? _riskLevelWire(RiskLevel? l) => switch (l) {
      RiskLevel.low => 'low',
      RiskLevel.medium => 'medium',
      RiskLevel.high => 'high',
      null => null,
    };

String _statusWire(ReportStatus s) => switch (s) {
      ReportStatus.pending => 'PENDING',
      ReportStatus.classified => 'CLASSIFIED',
      ReportStatus.rejected => 'REJECTED',
      ReportStatus.failed => 'FAILED',
    };

/// Riverpod provider — async because Firebase init is async. The UI shows a
/// boot splash while this resolves.
final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  return SyncService.tryInitialize();
});
