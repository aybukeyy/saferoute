// Pure-Dart risk computation. predicted_risk = base * surge * time.
// See ARCHITECTURE.md §4 and §5 for formula source of truth.
//
// Every constant in this file is *public* by design — the Layer 3
// explanation UI cites them verbatim ("Risk = base × 1.5 (night) ×
// 2.0 (recent activity surge)"). Changing a number here changes the user-
// facing copy, so treat them like locked prompt strings.

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/report.dart';
import 'local_db.dart';

/// A geographic bounding box used to scope heatmap queries and Firestore
/// listeners. Lat ranges from -90..90, lng from -180..180. The demo region
/// fits well inside one quadrant so we don't handle antimeridian wrap.
class BoundingBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
}

/// Computes per-cell risk scores from raw reports. The engine is *stateless*
/// w.r.t. its instance — all data lives in SQLite, this class just queries
/// and applies the formula.
class RiskEngine {
  final LocalDb _db;
  RiskEngine(this._db);

  // ---------------------------------------------------------------------------
  // Public constants — Layer 3 explanation surfaces these verbatim.
  // ---------------------------------------------------------------------------

  /// Category multiplier in the base-risk sum.
  static const Map<ReportCategory, double> categoryWeight = {
    ReportCategory.violence: 1.0,
    ReportCategory.theft: 0.8,
    ReportCategory.harassment: 0.7,
    ReportCategory.suspiciousActivity: 0.5,
    ReportCategory.vandalism: 0.4,
    ReportCategory.other: 0.3,
  };

  /// Severity multiplier keyed off the model-emitted risk_level.
  static const Map<RiskLevel, double> severityWeight = {
    RiskLevel.low: 0.4,
    RiskLevel.medium: 0.7,
    RiskLevel.high: 1.0,
  };

  /// Reputation clamp range. UI shows the formula as `× clamp(reputation,
  /// 0.5, 1.5)`.
  static const double reputationMin = 0.5;
  static const double reputationMax = 1.5;

  /// Surge cap: `1 + min(2.0, recent_2h × 0.3)` — at most a 3× multiplier.
  static const double surgeMaxBoost = 2.0;
  static const double surgePerReport = 0.3;
  static const Duration surgeWindow = Duration(hours: 2);

  /// Night-time boost. Active when `22:00 ≤ hour < 05:00` local.
  static const double nightFactor = 1.5;
  static const double dayFactor = 1.0;
  static const int nightStartHour = 22;
  static const int nightEndHour = 5;

  /// Decay timescale: half-life of ~5 days under exp(-age_days / 7).
  static const Duration decayTimescale = Duration(days: 7);

  // ---------------------------------------------------------------------------
  // Pure functions — exported so widgets and tests can show / verify them.
  // ---------------------------------------------------------------------------

  /// `decay = exp(-age_days / 7)`. Negative ages are clamped to zero so a
  /// future-dated report (clock skew) doesn't blow up the score.
  static double decay(Duration age) {
    final hours = age.inHours.toDouble();
    final ageDays = (hours <= 0 ? 0.0 : hours) / 24.0;
    return math.exp(-ageDays / 7.0);
  }

  /// Clamps a stored reputation to the `[0.5, 1.5]` interval used in scoring.
  static double reputationFor(double rep) =>
      rep.clamp(reputationMin, reputationMax);

  /// `surge = 1 + min(2.0, recent_reports_2h × 0.3)`. 5 reports in 2 h →
  /// 2.5× boost.
  static double surgeFactor(int recent2h) =>
      1.0 + math.min(surgeMaxBoost, recent2h * surgePerReport);

  /// `time = 1.5 if 22:00 ≤ hour < 05:00 else 1.0`. Local clock — the UI
  /// shows "night weighting active after 22:00" and the user's phone clock
  /// is the source of truth.
  static double timeFactor(DateTime t) {
    final h = t.hour;
    return (h >= nightStartHour || h < nightEndHour) ? nightFactor : dayFactor;
  }

  // ---------------------------------------------------------------------------
  // DB-backed methods.
  // ---------------------------------------------------------------------------

  /// Σ category × severity × decay × reputation over every classified
  /// report in the cell. Pending and rejected reports do not contribute.
  Future<double> baseRisk(String geohash7, DateTime now) async {
    final db = await _db.db;
    final rows = await db.rawQuery('''
      SELECT r.category   AS category,
             r.risk_level AS risk_level,
             r.occurred_at AS occurred_at,
             COALESCE(u.reputation, 1.0) AS reputation
        FROM reports r
        LEFT JOIN users u ON u.uid = r.uid
       WHERE r.geohash7 = ?
         AND r.status   = 'CLASSIFIED'
    ''', [geohash7]);

    double sum = 0.0;
    for (final row in rows) {
      final cat = _decodeCategory(row['category'] as String?);
      final level = _decodeRiskLevel(row['risk_level'] as String?);
      if (cat == null || level == null) continue;

      final occurredAtMs = row['occurred_at'] as int;
      final occurredAt =
          DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true);
      final age = now.difference(occurredAt);

      final w = categoryWeight[cat] ?? 0.0;
      final s = severityWeight[level] ?? 0.0;
      final d = decay(age);
      final rep = reputationFor((row['reputation'] as num).toDouble());

      sum += w * s * d * rep;
    }
    return sum;
  }

  /// `predicted_risk = base × surge × time`. Surge looks at the trailing 2 h.
  Future<double> predictedRisk(String geohash7, DateTime now) async {
    final base = await baseRisk(geohash7, now);
    final recent2h = await _recentReportCount(
      geohash7,
      now: now,
      window: surgeWindow,
    );
    return base * surgeFactor(recent2h) * timeFactor(now);
  }

  /// Returns a `geohash7 → [0, 1]` map for cells that have at least one
  /// classified report inside [bbox]. Score is min-max normalized over the
  /// returned cells; if all scores are zero (no risk) every value is 0.
  Future<Map<String, double>> heatmap({
    required BoundingBox bbox,
    required DateTime now,
  }) async {
    final db = await _db.db;
    // Pull distinct cells within the bbox. We filter by lat/lng of the
    // contributing reports — close enough at precision 7 because a report's
    // lat/lng is always inside its own cell.
    final rows = await db.rawQuery('''
      SELECT DISTINCT geohash7
        FROM reports
       WHERE status = 'CLASSIFIED'
         AND lat BETWEEN ? AND ?
         AND lng BETWEEN ? AND ?
    ''', [bbox.minLat, bbox.maxLat, bbox.minLng, bbox.maxLng]);

    final raw = <String, double>{};
    for (final row in rows) {
      final cell = row['geohash7'] as String;
      raw[cell] = await predictedRisk(cell, now);
    }

    if (raw.isEmpty) return raw;
    final maxScore = raw.values.fold<double>(0.0, math.max);
    if (maxScore <= 0.0) {
      return {for (final k in raw.keys) k: 0.0};
    }
    return {for (final e in raw.entries) e.key: e.value / maxScore};
  }

  /// Recomputes the `risk_cells` row for [geohash7] from scratch. Called by
  /// [ReportsRepository] after each classification commits.
  Future<void> recomputeCell(String geohash7, DateTime now) async {
    final db = await _db.db;
    final base = await baseRisk(geohash7, now);
    final recent2h = await _recentReportCount(
      geohash7,
      now: now,
      window: surgeWindow,
    );
    final score = base * surgeFactor(recent2h) * timeFactor(now);

    final countRow = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM reports WHERE geohash7 = ? AND status = ?',
      [geohash7, 'CLASSIFIED'],
    );
    final reportCount = (countRow.first['c'] as int);

    final topRow = await db.rawQuery('''
      SELECT category, COUNT(*) AS c
        FROM reports
       WHERE geohash7 = ? AND status = 'CLASSIFIED' AND category IS NOT NULL
       GROUP BY category
       ORDER BY c DESC
       LIMIT 1
    ''', [geohash7]);
    final topCategory = topRow.isEmpty
        ? null
        : (topRow.first['category'] as String?);

    await db.insert(
      'risk_cells',
      {
        'geohash7': geohash7,
        'score': score,
        'top_category': topCategory,
        'report_count': reportCount,
        'updated_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _recentReportCount(
    String geohash7, {
    required DateTime now,
    required Duration window,
  }) async {
    final db = await _db.db;
    final fromMs = now.subtract(window).millisecondsSinceEpoch;
    final row = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
        FROM reports
       WHERE geohash7 = ?
         AND status = 'CLASSIFIED'
         AND occurred_at >= ?
      ''',
      [geohash7, fromMs],
    );
    return row.first['c'] as int;
  }
}

ReportCategory? _decodeCategory(String? raw) {
  if (raw == null) return null;
  for (final c in ReportCategory.values) {
    if (_categoryWire[c] == raw) return c;
  }
  return null;
}

RiskLevel? _decodeRiskLevel(String? raw) {
  if (raw == null) return null;
  for (final l in RiskLevel.values) {
    if (_riskLevelWire[l] == raw) return l;
  }
  return null;
}

const Map<ReportCategory, String> _categoryWire = {
  ReportCategory.violence: 'violence',
  ReportCategory.theft: 'theft',
  ReportCategory.harassment: 'harassment',
  ReportCategory.suspiciousActivity: 'suspicious_activity',
  ReportCategory.vandalism: 'vandalism',
  ReportCategory.other: 'other',
};

const Map<RiskLevel, String> _riskLevelWire = {
  RiskLevel.low: 'low',
  RiskLevel.medium: 'medium',
  RiskLevel.high: 'high',
};

/// Riverpod provider for [RiskEngine].
final riskEngineProvider = Provider<RiskEngine>((ref) {
  return RiskEngine(ref.watch(localDbProvider));
});
