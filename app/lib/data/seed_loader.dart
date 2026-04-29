// First-launch demo seed.
//
// On a fresh install the local SQLite store is empty — the heatmap is blank
// and the route demo has no risk to detour around. This loader populates a
// curated set of synthetic reports clustered around the demo region's hot
// zones (Akaretler / Beşiktaş İskele / Yıldız Park edge) so the very first
// boot of the app already shows a meaningful heatmap.
//
// Idempotent: it only runs when `reports` table is empty, so subsequent
// boots are no-ops. After load it recomputes risk_cells for every cell that
// received a seed report so the heatmap painter has something to render.
//
// The seed contents live in `assets/seed_reports.json` (JSON), not in Dart,
// so the demo region can be re-targeted by editing one file (paired with
// `tools/extract_osm.py --bbox`).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/geohash.dart';
import 'local_db.dart';
import 'risk_engine.dart';

class SeedLoader {
  SeedLoader._();

  /// If the `reports` table is empty, parse `assets/seed_reports.json` and
  /// insert each row directly. After insertion, recompute `risk_cells` for
  /// every distinct geohash-7 touched.
  ///
  /// Failures (asset missing, JSON malformed, DB error) are logged and
  /// swallowed — first-launch seeding is best-effort.
  static Future<void> seedIfFirstLaunch({
    required LocalDb localDb,
    required RiskEngine riskEngine,
    required String defaultUid,
    String assetPath = 'assets/seed_reports.json',
  }) async {
    try {
      final db = await localDb.db;
      final existing = await db.rawQuery('SELECT COUNT(*) AS c FROM reports');
      final count = (existing.first['c'] as int?) ?? 0;
      if (count > 0) {
        debugPrint('[SeedLoader] reports table already has $count rows; skipping.');
        return;
      }

      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final reports = (decoded['reports'] as List?) ?? const [];
      if (reports.isEmpty) {
        debugPrint('[SeedLoader] $assetPath has no reports; nothing to seed.');
        return;
      }

      // Make sure the seed UID has a `users` row — FK target.
      await db.insert(
        'users',
        {
          'uid': defaultUid,
          'reputation': 1.0,
          'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      const uuid = Uuid();
      final now = DateTime.now().toUtc();
      final touchedCells = <String>{};

      await db.transaction((txn) async {
        for (final entry in reports) {
          final r = entry as Map<String, dynamic>;
          final lat = (r['lat'] as num).toDouble();
          final lng = (r['lng'] as num).toDouble();
          final occurredAt = DateTime.parse(r['occurredAt'] as String).toUtc();
          final geohash7 = Geohash.encode(lat, lng, precision: 7);
          touchedCells.add(geohash7);

          await txn.insert('reports', {
            'id': uuid.v4(),
            'uid': defaultUid,
            'text': r['text'] as String,
            'lat': lat,
            'lng': lng,
            'geohash7': geohash7,
            'occurred_at': occurredAt.millisecondsSinceEpoch,
            'category': r['category'] as String?,
            'risk_level': r['riskLevel'] as String?,
            'confidence': 0.85,
            'explanation': r['explanation'] as String?,
            'status': 'CLASSIFIED',
            'synced': 0,
            'created_at': now.millisecondsSinceEpoch,
          });
        }
      });

      // Recompute risk_cells outside the transaction — RiskEngine.recomputeCell
      // opens its own write to the same DB connection.
      for (final cell in touchedCells) {
        try {
          await riskEngine.recomputeCell(cell, now);
        } catch (e) {
          debugPrint('[SeedLoader] recomputeCell($cell) failed: $e');
        }
      }

      debugPrint(
          '[SeedLoader] inserted ${reports.length} seed reports across '
          '${touchedCells.length} cells.');
    } catch (e, st) {
      debugPrint('[SeedLoader] failed: $e\n$st');
    }
  }
}
