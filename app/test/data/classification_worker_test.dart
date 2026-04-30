import 'dart:async';

import 'package:app/ai/gemma_service.dart';
import 'package:app/data/classification_worker.dart';
import 'package:app/data/local_db.dart';
import 'package:app/data/reports_repository.dart';
import 'package:app/data/risk_engine.dart';
import 'package:app/data/sync_service.dart';
import 'package:app/models/classification.dart';
import 'package:app/models/report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClassificationWorker', () {
    test('happy path: classify → updateClassification with right args', () async {
      final report = _mkPending('r1');
      final fakeRepo = _FakeReportsRepository(pending: [report]);
      final classification = _mkClassification();
      final fakeGemma = _FakeGemmaService(result: classification);

      final worker = ClassificationWorker(
        reports: fakeRepo,
        gemma: fakeGemma,
      );
      await worker.start();
      await fakeRepo.idleFuture;

      expect(fakeGemma.calls, hasLength(1));
      expect(fakeGemma.calls.first.text, report.text);
      expect(fakeGemma.calls.first.lat, report.lat);
      expect(fakeGemma.calls.first.lng, report.lng);
      expect(fakeGemma.calls.first.occurredAt, report.occurredAt);

      expect(fakeRepo.updates, hasLength(1));
      expect(fakeRepo.updates.first.$1, 'r1');
      expect(fakeRepo.updates.first.$2, classification);
      expect(fakeRepo.failures, isEmpty);

      await worker.dispose();
    });

    test('classify throws → markClassificationFailed, no updateClassification',
        () async {
      final report = _mkPending('r-fail');
      final fakeRepo = _FakeReportsRepository(pending: [report]);
      final fakeGemma = _FakeGemmaService(error: StateError('inference broke'));

      final worker = ClassificationWorker(
        reports: fakeRepo,
        gemma: fakeGemma,
      );
      await worker.start();
      await fakeRepo.idleFuture;

      expect(fakeGemma.calls, hasLength(1));
      expect(fakeRepo.updates, isEmpty);
      expect(fakeRepo.failures, ['r-fail']);

      await worker.dispose();
    });

    test('two PENDING reports queued: processed in submission order', () async {
      final r1 = _mkPending('r1');
      final r2 = _mkPending('r2');
      final fakeRepo = _FakeReportsRepository(pending: [r1, r2]);
      final fakeGemma = _FakeGemmaService(result: _mkClassification());

      final worker = ClassificationWorker(
        reports: fakeRepo,
        gemma: fakeGemma,
      );
      await worker.start();
      await fakeRepo.idleFuture;

      expect(
        fakeGemma.calls.map((c) => c.text).toList(),
        [r1.text, r2.text],
      );
      expect(
        fakeRepo.updates.map((u) => u.$1).toList(),
        ['r1', 'r2'],
      );

      await worker.dispose();
    });
  });
}

Report _mkPending(String id) {
  final t = DateTime.utc(2026, 4, 30, 12, 0).add(Duration(seconds: id.hashCode));
  return Report(
    id: id,
    uid: 'tester',
    text: 'pending text $id',
    lat: 41.0,
    lng: 29.0,
    geohash7: 'sxk9rfm',
    occurredAt: t,
    status: ReportStatus.pending,
    createdAt: t,
  );
}

Classification _mkClassification() => const Classification(
      category: ReportCategory.harassment,
      riskLevel: RiskLevel.medium,
      timeSensitive: false,
      confidence: 0.7,
      explanation: 'fake',
    );

class _ClassifyCall {
  _ClassifyCall(this.text, this.lat, this.lng, this.occurredAt);
  final String text;
  final double lat;
  final double lng;
  final DateTime occurredAt;
}

class _FakeGemmaService implements GemmaService {
  _FakeGemmaService({this.result, this.error});
  final Classification? result;
  final Object? error;
  final List<_ClassifyCall> calls = [];

  @override
  Future<Classification> classify({
    required String text,
    required double lat,
    required double lng,
    required DateTime occurredAt,
  }) async {
    calls.add(_ClassifyCall(text, lat, lng, occurredAt));
    if (error != null) throw error!;
    return result!;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository({required List<Report> pending}) : _pending = pending;

  final List<Report> _pending;
  final StreamController<Report> _stream = StreamController<Report>.broadcast();
  final List<(String, Classification)> updates = [];
  final List<String> failures = [];

  /// Resolves once any pending DB ops the worker may issue have settled. We
  /// drive the queue with simple awaits in the worker, so a few microtask
  /// turns are enough to drain.
  Future<void> get idleFuture async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<List<Report>> pendingReports() async => List.of(_pending);

  @override
  Stream<Report> watchPending() => _stream.stream;

  @override
  Future<void> updateClassification(String id, Classification c) async {
    updates.add((id, c));
  }

  @override
  Future<void> markClassificationFailed(String id) async {
    failures.add(id);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}

// Unused — referenced only so the test imports stay honest if somebody
// expands the worker to take RiskEngine / SyncService directly.
// ignore: unused_element
typedef _Unused = (RiskEngine, SyncService, LocalDb);
