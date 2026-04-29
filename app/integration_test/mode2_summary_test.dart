// Mode 2 (Gemma 4 E4B) area-summary rubric integration test.
//
// Pass criteria (PLAN.md §6):
//   * Area summary rubric pass ≥ 90%
//
// Latency target is softer for E4B (cached 5 min/cell in production), so we
// log it for the writeup but do NOT fail on it here.

import 'dart:io' show File;

import 'package:app/ai/gemma_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../eval/src/dataset.dart';
import '../eval/src/harness.dart';
import '../eval/src/mode2_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late GemmaService service;

  setUpAll(() async {
    service = GemmaService();
  });

  tearDownAll(() async {
    await service.dispose();
  });

  testWidgets('Mode 2 — E4B summary rubric on labeled cell cases',
      (tester) async {
    final raw = await rootBundle.loadString('eval/data/mode2_cases.json');
    final dataset = Mode2Dataset.fromJsonString(raw);
    expect(dataset.cases, hasLength(10),
        reason: 'mode2_cases.json must hold the locked 10 cases');

    // Cold start E4B (after warm-up the engine is warm; hot-swap cost is
    // measured separately in latency_bench_test.dart).
    final coldSw = Stopwatch()..start();
    await service.warmUpE4B();
    coldSw.stop();
    debugLog('E4B cold-start: ${coldSw.elapsedMilliseconds} ms');

    final runner = Mode2Runner(
      dataset: dataset,
      summarize: service.summarizeCell,
      onProgress: (i, n, c) =>
          debugLog('summarize ${i + 1}/$n  id=${c.id}  cell=${c.geohash7}'),
    );
    final outcome = await runner.run();

    debugLog(banner('Mode 2 — E4B Summary Rubric'));
    debugLog(
        'Rubric pass:        ${outcome.rubricPasses}/${outcome.totalCount}  ${pct(outcome.rubricPasses, outcome.totalCount)}');
    debugLog('Cold-start latency: ${coldSw.elapsedMilliseconds} ms');
    debugLog('Per-call latency:   ${outcome.perCallLatency.toLogLine()}');

    debugLog('-- WRITEUP §6 row (E4B) --');
    debugLog(writeupSummaryLine(
      model: 'Gemma 4 E4B',
      coldStartLabel: 'cold-start (post hot-swap)',
      coldStartMs: coldSw.elapsedMilliseconds,
      perCall: outcome.perCallLatency,
      accuracyLabel: 'rubric=${pct(outcome.rubricPasses, outcome.totalCount)}',
      rubricValue: pct(outcome.rubricPasses, outcome.totalCount),
    ));

    final outDir = (await getApplicationDocumentsDirectory()).path;
    final csvPath =
        OutputDir.timestampedFile(outDir, 'mode2_results', 'csv');
    await writeCsv(
      path: csvPath,
      header: Mode2CaseResult.csvHeader,
      rows:
          outcome.caseResults.map((r) => r.toCsvRow()).toList(growable: false),
    );
    debugLog('CSV written: $csvPath');
    expect(await File(csvPath).exists(), isTrue);

    expect(
      outcome.rubricAccuracy,
      greaterThanOrEqualTo(dataset.targetRubric),
      reason:
          'Mode 2 rubric ${pct(outcome.rubricPasses, outcome.totalCount)} '
          'below target ${(dataset.targetRubric * 100).toStringAsFixed(1)}%',
    );
    // Latency is logged but not asserted — see file header.
  }, timeout: const Timeout(Duration(minutes: 20)));
}

// ignore: avoid_print
void debugLog(String msg) => print('[mode2_eval] $msg');
