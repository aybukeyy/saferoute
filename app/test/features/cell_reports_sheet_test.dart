import 'package:app/ai/gemma_service.dart';
import 'package:app/ai/model_storage.dart';
import 'package:app/features/explanation/explanation_card.dart';
import 'package:app/features/providers.dart';
import 'package:app/models/report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets(
      'CellReportsSheet renders the E4B area summary above the report list',
      (tester) async {
    const geohash = 'sxk9abc';
    const expectedSummary =
        'Cluster of three recent harassment reports near the park entrance.';

    final fakeGemma = _FakeGemmaService(summary: expectedSummary);
    final fakeRepo = _FakeReportsRepository(reports: [_seedReport(geohash)]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gemmaServiceProvider.overrideWithValue(fakeGemma),
          reportsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CellReportsSheet(geohash7: geohash)),
        ),
      ),
    );

    expect(find.text('Generating area summary…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text(expectedSummary), findsOneWidget);
    expect(find.text('Generating area summary…'), findsNothing);
    expect(fakeGemma.summarizeCalls, 1);
    expect(fakeGemma.lastReports, hasLength(1));
  });

  testWidgets('CellReportsSheet hides the header when summary fails',
      (tester) async {
    const geohash = 'sxk9abc';
    final fakeGemma = _FakeGemmaService.throwing();
    final fakeRepo = _FakeReportsRepository(reports: [_seedReport(geohash)]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gemmaServiceProvider.overrideWithValue(fakeGemma),
          reportsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CellReportsSheet(geohash7: geohash)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Generating area summary…'), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('Reports in this cell'), findsOneWidget);
  });
}

Report _seedReport(String geohash) {
  final t = DateTime(2025, 1, 1, 23, 0);
  return Report(
    id: 'r1',
    uid: 'u1',
    text: 'Two men following a woman near the park.',
    lat: 41.0,
    lng: 28.97,
    geohash7: geohash,
    occurredAt: t,
    category: ReportCategory.harassment,
    riskLevel: RiskLevel.medium,
    status: ReportStatus.classified,
    createdAt: t,
  );
}

class _FakeReportsRepository implements ReportsRepositoryLike {
  _FakeReportsRepository({required this.reports});

  final List<Report> reports;

  @override
  Future<Report> submitReport(
          {required String text, required LatLng at}) async =>
      throw UnimplementedError();

  @override
  Future<List<Report>> recentReports({int limit = 50}) async => reports;

  @override
  Future<List<Report>> reportsInCell(String geohash7) async =>
      reports.where((r) => r.geohash7 == geohash7).toList();
}

class _FakeGemmaService extends GemmaService {
  _FakeGemmaService({required String summary})
      : _summary = summary,
        _shouldThrow = false,
        super(storage: ModelStorage());

  _FakeGemmaService.throwing()
      : _summary = '',
        _shouldThrow = true,
        super(storage: ModelStorage());

  final String _summary;
  final bool _shouldThrow;
  int summarizeCalls = 0;
  List<Report> lastReports = const [];

  @override
  Future<String> summarizeCell({
    required String geohash7,
    required List<Report> recentReports,
    required bool isNight,
    int hours = 6,
  }) async {
    summarizeCalls += 1;
    lastReports = recentReports;
    if (_shouldThrow) {
      throw StateError('synthetic failure for test');
    }
    return _summary;
  }

  @override
  Future<void> dispose() async {}
}
