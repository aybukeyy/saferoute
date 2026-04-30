import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_db.dart';
import 'reports_repository.dart';
import 'sync_service.dart';

class ReputationSync {
  ReputationSync({
    required LocalDb db,
    required SyncService sync,
    required ReportsRepository reports,
    required String currentUid,
  })  : _db = db,
        _sync = sync,
        _reports = reports,
        _currentUid = currentUid;

  final LocalDb _db;
  final SyncService _sync;
  final ReportsRepository _reports;
  final String _currentUid;

  final Map<String, StreamSubscription<double>> _subs = {};
  StreamSubscription<String>? _discoverySub;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _discoverySub = _reports.watchDiscoveredUids().listen(_subscribe);

    _subscribe(_currentUid);

    final known = await _db.allUserUids();
    for (final uid in known) {
      _subscribe(uid);
    }
  }

  void _subscribe(String uid) {
    if (_disposed) return;
    if (uid.isEmpty || uid == 'local-only') return;
    if (_subs.containsKey(uid)) return;

    final sub = _sync.watchReputation(uid).listen(
      (value) {
        unawaited(_apply(uid, value));
      },
      onError: (Object e, StackTrace st) {
        debugPrint('[ReputationSync] $uid stream error: $e');
      },
    );
    _subs[uid] = sub;
  }

  Future<void> _apply(String uid, double value) async {
    if (_disposed) return;
    try {
      await _db.updateReputation(uid, value);
    } catch (e) {
      debugPrint('[ReputationSync] updateReputation($uid) failed: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _discoverySub?.cancel();
    _discoverySub = null;
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
