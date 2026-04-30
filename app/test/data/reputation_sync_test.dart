import 'dart:async';

import 'package:app/data/local_db.dart';
import 'package:app/data/reports_repository.dart';
import 'package:app/data/reputation_sync.dart';
import 'package:app/data/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReputationSync', () {
    test('initial UIDs from local DB open subscriptions and call updateReputation',
        () async {
      final db = _FakeLocalDb(uids: ['alice', 'bob']);
      final sync = _FakeSyncService();
      final repo = _FakeReportsRepository();

      sync.controllers['alice'] = StreamController<double>.broadcast();
      sync.controllers['bob'] = StreamController<double>.broadcast();

      final svc = ReputationSync(
        db: db,
        sync: sync,
        reports: repo,
        currentUid: 'local-only',
      );
      await svc.start();
      await _settle();

      expect(sync.subscribed, containsAll(['alice', 'bob']));

      sync.controllers['alice']!.add(1.3);
      sync.controllers['bob']!.add(0.9);
      await _settle();

      expect(db.updates, contains(('alice', 1.3)));
      expect(db.updates, contains(('bob', 0.9)));

      await svc.dispose();
    });

    test('current device UID is subscribed even when not in local DB',
        () async {
      final db = _FakeLocalDb(uids: const []);
      final sync = _FakeSyncService();
      final repo = _FakeReportsRepository();
      sync.controllers['me'] = StreamController<double>.broadcast();

      final svc = ReputationSync(
        db: db,
        sync: sync,
        reports: repo,
        currentUid: 'me',
      );
      await svc.start();
      await _settle();

      expect(sync.subscribed, ['me']);

      sync.controllers['me']!.add(0.5);
      await _settle();
      expect(db.updates, [('me', 0.5)]);

      await svc.dispose();
    });

    test('local-only currentUid is not subscribed', () async {
      final db = _FakeLocalDb(uids: const []);
      final sync = _FakeSyncService();
      final repo = _FakeReportsRepository();

      final svc = ReputationSync(
        db: db,
        sync: sync,
        reports: repo,
        currentUid: 'local-only',
      );
      await svc.start();
      await _settle();

      expect(sync.subscribed, isEmpty);

      await svc.dispose();
    });

    test('new UID via discovery stream opens new subscription, no duplicates',
        () async {
      final db = _FakeLocalDb(uids: ['alice']);
      final sync = _FakeSyncService();
      final repo = _FakeReportsRepository();
      sync.controllers['alice'] = StreamController<double>.broadcast();
      sync.controllers['carol'] = StreamController<double>.broadcast();

      final svc = ReputationSync(
        db: db,
        sync: sync,
        reports: repo,
        currentUid: 'local-only',
      );
      await svc.start();
      await _settle();

      expect(sync.subscribed, ['alice']);

      repo.uidController.add('carol');
      await _settle();
      expect(sync.subscribed, ['alice', 'carol']);

      // Re-discovering an existing UID must not re-subscribe.
      repo.uidController.add('alice');
      repo.uidController.add('carol');
      await _settle();
      expect(sync.subscribed, ['alice', 'carol']);

      sync.controllers['carol']!.add(1.1);
      await _settle();
      expect(db.updates, [('carol', 1.1)]);

      await svc.dispose();
    });

    test('emitted value 0.5 forwards to LocalDb.updateReputation', () async {
      final db = _FakeLocalDb(uids: ['x']);
      final sync = _FakeSyncService();
      final repo = _FakeReportsRepository();
      sync.controllers['x'] = StreamController<double>.broadcast();

      final svc = ReputationSync(
        db: db,
        sync: sync,
        reports: repo,
        currentUid: 'local-only',
      );
      await svc.start();
      await _settle();

      sync.controllers['x']!.add(0.5);
      await _settle();

      expect(db.updates, [('x', 0.5)]);

      await svc.dispose();
    });

    test('dispose cancels all subscriptions', () async {
      final db = _FakeLocalDb(uids: ['a', 'b']);
      final sync = _FakeSyncService();
      final repo = _FakeReportsRepository();
      sync.controllers['a'] = StreamController<double>.broadcast();
      sync.controllers['b'] = StreamController<double>.broadcast();

      final svc = ReputationSync(
        db: db,
        sync: sync,
        reports: repo,
        currentUid: 'local-only',
      );
      await svc.start();
      await _settle();

      await svc.dispose();

      sync.controllers['a']!.add(0.7);
      sync.controllers['b']!.add(0.7);
      repo.uidController.add('c');
      await _settle();

      expect(db.updates, isEmpty);
      // Discovery after dispose is a no-op.
      expect(sync.subscribed, ['a', 'b']);
    });
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeLocalDb implements LocalDb {
  _FakeLocalDb({required List<String> uids}) : _uids = List.of(uids);

  final List<String> _uids;
  final List<(String, double)> updates = [];

  @override
  Future<List<String>> allUserUids() async => List.of(_uids);

  @override
  Future<void> updateReputation(String uid, double value) async {
    updates.add((uid, value));
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}

class _FakeSyncService implements SyncService {
  final Map<String, StreamController<double>> controllers = {};
  final List<String> subscribed = [];

  @override
  Stream<double> watchReputation(String uid) {
    subscribed.add(uid);
    final c = controllers.putIfAbsent(
      uid,
      () => StreamController<double>.broadcast(),
    );
    return c.stream;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}

class _FakeReportsRepository implements ReportsRepository {
  final StreamController<String> uidController =
      StreamController<String>.broadcast();

  @override
  Stream<String> watchDiscoveredUids() => uidController.stream;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}
