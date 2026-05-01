// sqflite wrapper. Owns DB open/close/migrations. Schema source of truth:
// docs/planning/IMPLEMENTATION.md §4.
//
// LocalDb is the persistence boundary for the *whole* app. Repositories and
// the RiskEngine call into it; nothing else should call sqflite directly.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Bumping this constant runs the migration ladder in [_runMigrations].
/// Keep migrations additive and idempotent so a partial upgrade is safe.
const int kLocalDbSchemaVersion = 2;

/// Async-singleton wrapper around the local SQLite database.
///
/// Call [init] once on app startup, then access [db] from anywhere. The
/// underlying sqflite [Database] handle is reused across the app lifetime.
class LocalDb {
  LocalDb({String fileName = 'safe_route.db'}) : _fileName = fileName;

  final String _fileName;
  Database? _db;
  Completer<Database>? _opening;

  /// Opens the DB if not already open and returns the live handle. Safe to
  /// call concurrently — the first caller wins, followers await the same
  /// future.
  Future<Database> get db async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;
    _opening = Completer<Database>();
    try {
      final database = await _open();
      _db = database;
      _opening!.complete(database);
      return database;
    } catch (e, st) {
      _opening!.completeError(e, st);
      _opening = null;
      rethrow;
    }
  }

  /// Eagerly opens the DB. Useful at app startup so the first repository call
  /// doesn't pay the open cost.
  Future<void> init() async {
    await db;
  }

  /// Returns every UID currently present in the `users` table.
  Future<List<String>> allUserUids() async {
    final database = await db;
    final rows = await database.query('users', columns: ['uid']);
    return rows.map((r) => r['uid'] as String).toList(growable: false);
  }

  /// Upserts the reputation column for [uid]. If the row doesn't exist yet
  /// (a remote UID we discovered before any of their reports landed) it's
  /// inserted with the given reputation.
  Future<void> updateReputation(String uid, double value) async {
    final database = await db;
    final updated = await database.update(
      'users',
      {'reputation': value},
      where: 'uid = ?',
      whereArgs: [uid],
    );
    if (updated == 0) {
      await database.insert(
        'users',
        {
          'uid': uid,
          'reputation': value,
          'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Closes the connection. Mostly used in tests; production code lets the
  /// DB live until the process dies.
  Future<void> close() async {
    final handle = _db;
    _db = null;
    _opening = null;
    if (handle != null) {
      await handle.close();
    }
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    return openDatabase(
      path,
      version: kLocalDbSchemaVersion,
      onConfigure: (db) async {
        // sqflite disables FK enforcement by default; we rely on it for the
        // reports.uid → users.uid relationship.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchemaV1(db);
      },
      onUpgrade: (db, from, to) async {
        await _runMigrations(db, from: from, to: to);
      },
    );
  }

  /// Creates the v1 schema. Mirror of IMPLEMENTATION.md §4 — keep in sync.
  static Future<void> _createSchemaV1(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        uid          TEXT PRIMARY KEY,
        reputation   REAL NOT NULL DEFAULT 1.0,
        created_at   INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE reports (
        id                TEXT PRIMARY KEY,
        uid               TEXT REFERENCES users(uid),
        text              TEXT NOT NULL,
        lat               REAL NOT NULL,
        lng               REAL NOT NULL,
        geohash7          TEXT NOT NULL,
        occurred_at       INTEGER NOT NULL,
        category          TEXT,
        risk_level        TEXT,
        confidence        REAL,
        explanation       TEXT,
        status            TEXT NOT NULL DEFAULT 'PENDING',
        synced            INTEGER NOT NULL DEFAULT 0,
        created_at        INTEGER NOT NULL,
        photo_local_path  TEXT,
        photo_url         TEXT,
        vision_summary    TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX reports_geohash_idx ON reports(geohash7)',
    );
    await db.execute(
      'CREATE INDEX reports_time_idx ON reports(occurred_at DESC)',
    );

    await db.execute('''
      CREATE TABLE risk_cells (
        geohash7        TEXT PRIMARY KEY,
        score           REAL NOT NULL,
        top_category    TEXT,
        report_count    INTEGER NOT NULL,
        summary         TEXT,
        summary_at      INTEGER,
        updated_at      INTEGER NOT NULL
      )
    ''');
  }

  /// Linear migration runner — apply each step in order, never skip. Add new
  /// `case` arms when bumping [kLocalDbSchemaVersion]. v1 is the only schema
  /// today, so any onUpgrade invocation is a programmer error.
  static Future<void> _runMigrations(
    Database db, {
    required int from,
    required int to,
  }) async {
    for (var v = from + 1; v <= to; v++) {
      await _applyMigration(db, v);
    }
  }

  static Future<void> _applyMigration(Database db, int version) async {
    if (version == 2) {
      await db.execute(
        'ALTER TABLE reports ADD COLUMN photo_local_path TEXT',
      );
      await db.execute(
        'ALTER TABLE reports ADD COLUMN photo_url TEXT',
      );
      await db.execute(
        'ALTER TABLE reports ADD COLUMN vision_summary TEXT',
      );
      return;
    }
    throw StateError('No migration registered for v$version');
  }
}

/// Riverpod provider — held for the lifetime of the app.
final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb();
  ref.onDispose(db.close);
  return db;
});
