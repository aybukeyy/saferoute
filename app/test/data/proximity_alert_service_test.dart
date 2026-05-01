import 'dart:async';

import 'package:app/core/geohash.dart';
import 'package:app/core/location_service.dart';
import 'package:app/data/proximity_alert_service.dart';
import 'package:app/data/reports_repository.dart';
import 'package:app/data/risk_engine.dart';
import 'package:app/models/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Two coords whose geohash-7 cells differ. ~150m apart guarantees a
  // different precision-7 cell at this latitude.
  const highLat = 41.0082;
  const highLng = 28.9784;
  const lowLat = 41.0200;
  const lowLng = 28.9900;

  final highCell = Geohash.encode(highLat, highLng);
  final lowCell = Geohash.encode(lowLat, lowLng);

  group('ProximityAlertService', () {
    test('highCell != lowCell sanity', () {
      expect(highCell, isNot(lowCell));
    });

    test('crossing into a high-risk cell fires exactly one notification',
        () async {
      final loc = _FakeLocationService();
      final risk = _FakeRiskEngine(scores: {highCell: 0.9, lowCell: 0.1});
      final reports = _FakeReportsRepository(
        cellReports: {highCell: _mkReports(3, highCell)},
      );
      final notifier = _RecordingDispatcher();

      final svc = ProximityAlertService(
        location: loc,
        risk: risk,
        reports: reports,
        dispatcher: notifier.dispatch,
      );
      await svc.start();
      loc.emit(LatLng(highLat, highLng));
      await _settle();

      expect(notifier.calls, hasLength(1));
      expect(notifier.calls.first.body, contains('3 reports'));
      expect(notifier.calls.first.body, contains('Stay alert'));

      await svc.dispose();
    });

    test('staying in same high-risk cell does not re-fire', () async {
      final loc = _FakeLocationService();
      final risk = _FakeRiskEngine(scores: {highCell: 0.9});
      final reports = _FakeReportsRepository(
        cellReports: {highCell: _mkReports(2, highCell)},
      );
      final notifier = _RecordingDispatcher();

      final svc = ProximityAlertService(
        location: loc,
        risk: risk,
        reports: reports,
        dispatcher: notifier.dispatch,
      );
      await svc.start();
      loc.emit(LatLng(highLat, highLng));
      await _settle();
      loc.emit(LatLng(highLat, highLng));
      await _settle();
      loc.emit(LatLng(highLat, highLng));
      await _settle();

      expect(notifier.calls, hasLength(1));

      await svc.dispose();
    });

    test('crossing into a low-risk cell does not fire', () async {
      final loc = _FakeLocationService();
      final risk = _FakeRiskEngine(scores: {lowCell: 0.2, highCell: 0.7});
      final reports = _FakeReportsRepository(
        cellReports: {
          lowCell: _mkReports(1, lowCell),
          highCell: _mkReports(1, highCell),
        },
      );
      final notifier = _RecordingDispatcher();

      final svc = ProximityAlertService(
        location: loc,
        risk: risk,
        reports: reports,
        dispatcher: notifier.dispatch,
      );
      await svc.start();
      loc.emit(LatLng(lowLat, lowLng));
      await _settle();

      expect(notifier.calls, isEmpty);

      await svc.dispose();
    });

    test('cooldown: same high-risk cell within 5min suppressed; after 5min fires',
        () async {
      var nowVal = DateTime.utc(2026, 4, 30, 23, 0);
      final loc = _FakeLocationService();
      final risk = _FakeRiskEngine(scores: {highCell: 0.9, lowCell: 0.1});
      final reports = _FakeReportsRepository(
        cellReports: {
          highCell: _mkReports(1, highCell),
          lowCell: _mkReports(0, lowCell),
        },
      );
      final notifier = _RecordingDispatcher();

      final svc = ProximityAlertService(
        location: loc,
        risk: risk,
        reports: reports,
        dispatcher: notifier.dispatch,
        clock: () => nowVal,
      );
      await svc.start();

      loc.emit(LatLng(highLat, highLng));
      await _settle();
      expect(notifier.calls, hasLength(1));

      // Step out to the low-risk cell so re-entry is "crossing into" the high
      // cell again, not "staying in" it. Cooldown still applies.
      nowVal = nowVal.add(const Duration(minutes: 1));
      loc.emit(LatLng(lowLat, lowLng));
      await _settle();
      expect(notifier.calls, hasLength(1));

      // Re-cross within 5 min: cooldown blocks.
      nowVal = nowVal.add(const Duration(minutes: 2));
      loc.emit(LatLng(highLat, highLng));
      await _settle();
      expect(notifier.calls, hasLength(1));

      // Advance well past the cooldown and re-cross: fires again.
      nowVal = nowVal.add(const Duration(minutes: 6));
      loc.emit(LatLng(lowLat, lowLng));
      await _settle();
      nowVal = nowVal.add(const Duration(minutes: 1));
      loc.emit(LatLng(highLat, highLng));
      await _settle();
      expect(notifier.calls, hasLength(2));

      await svc.dispose();
    });

    test('dispose cancels subscription cleanly', () async {
      final loc = _FakeLocationService();
      final risk = _FakeRiskEngine(scores: {highCell: 0.9});
      final reports = _FakeReportsRepository(
        cellReports: {highCell: _mkReports(1, highCell)},
      );
      final notifier = _RecordingDispatcher();

      final svc = ProximityAlertService(
        location: loc,
        risk: risk,
        reports: reports,
        dispatcher: notifier.dispatch,
      );
      await svc.start();
      await svc.dispose();

      loc.emit(LatLng(highLat, highLng));
      await _settle();

      expect(notifier.calls, isEmpty);
      expect(loc.hasListener, isFalse);
    });
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<Report> _mkReports(int n, String cell) {
  final t = DateTime.utc(2026, 4, 30, 22, 0);
  return List.generate(
    n,
    (i) => Report(
      id: 'r$i-$cell',
      uid: 'u',
      text: 'r$i',
      lat: 0,
      lng: 0,
      geohash7: cell,
      occurredAt: t,
      status: ReportStatus.classified,
      createdAt: t,
    ),
  );
}

class _DispatchCall {
  _DispatchCall(this.id, this.title, this.body);
  final int id;
  final String title;
  final String body;
}

class _RecordingDispatcher {
  final List<_DispatchCall> calls = [];

  Future<void> dispatch({
    required int id,
    required String title,
    required String body,
  }) async {
    calls.add(_DispatchCall(id, title, body));
  }
}

class _FakeLocationService implements LocationService {
  final StreamController<LatLng> _controller =
      StreamController<LatLng>.broadcast();

  bool get hasListener => _controller.hasListener;

  void emit(LatLng pos) => _controller.add(pos);

  @override
  Stream<LatLng> watchPosition({Duration interval = const Duration(seconds: 5)}) =>
      _controller.stream;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}

class _FakeRiskEngine implements RiskEngine {
  _FakeRiskEngine({required this.scores});
  final Map<String, double> scores;

  @override
  Future<double> predictedRisk(String geohash7, DateTime now) async {
    return scores[geohash7] ?? 0.0;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository({required this.cellReports});
  final Map<String, List<Report>> cellReports;

  @override
  Future<List<Report>> reportsInCell(String geohash7, {Duration? maxAge}) async {
    return cellReports[geohash7] ?? const [];
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call ${invocation.memberName}');
}
