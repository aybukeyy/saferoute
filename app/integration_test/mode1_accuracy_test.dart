// Mode 1 (Gemma 4 E2B) accuracy + explanation rubric integration test.
//
// Runs on a real device — `flutter test integration_test/mode1_accuracy_test.dart`.
// See app/eval/README.md for the full run-book and prerequisites.
//
// Pass criteria (PLAN.md §6):
//   * Category accuracy        ≥ 85%
//   * Risk-level accuracy      ≥ 85%
//   * Explanation rubric pass  ≥ 90%
//   * End-to-end per-call      < 5000 ms median
//
// Thresholds are NOT hard-coded here — they are read from `mode1_dataset.json`
// (`targetAccuracy`, `targetRubric`, `targetLatencyMs`). That keeps the eval
// reproducible against a versioned dataset rather than against drifting
// constants in test files.

import 'dart:io' show File;

import 'package:app/ai/gemma_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../eval/src/dataset.dart';
import '../eval/src/harness.dart';
import '../eval/src/mode1_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late GemmaService service;

  setUpAll(() async {
    service = GemmaService();
  });

  tearDownAll(() async {
    await service.dispose();
  });

  testWidgets('Mode 1 — E2B accuracy + rubric on labeled dataset',
      (tester) async {
    // -- Load dataset -------------------------------------------------------
    final raw = await rootBundle.loadString('eval/data/mode1_dataset.json');
    final dataset = Mode1Dataset.fromJsonString(raw);
    expect(dataset.rows, hasLength(30),
        reason: 'mode1_dataset.json must hold the locked 30 rows');

    // -- Cold start ---------------------------------------------------------
    final coldSw = Stopwatch()..start();
    await service.warmUpE2B();
    coldSw.stop();
    debugLog('E2B cold-start: ${coldSw.elapsedMilliseconds} ms');

    // -- Run ---------------------------------------------------------------
    final runner = Mode1Runner(
      dataset: dataset,
      classify: service.classify,
      onProgress: (i, n, row) =>
          debugLog('classify ${i + 1}/$n  id=${row.id}  lang=${row.lang}'),
    );
    final outcome = await runner.run();

    // -- Stdout summary ----------------------------------------------------
    debugLog(banner('Mode 1 — E2B Accuracy + Rubric'));
    debugLog(
        'Category accuracy:   ${outcome.categoryMatches}/${outcome.totalCount}  ${pct(outcome.categoryMatches, outcome.totalCount)}');
    debugLog(
        'RiskLevel accuracy:  ${outcome.riskLevelMatches}/${outcome.totalCount}  ${pct(outcome.riskLevelMatches, outcome.totalCount)}');
    debugLog(
        'Both correct:        ${outcome.bothMatches}/${outcome.totalCount}  ${pct(outcome.bothMatches, outcome.totalCount)}');
    debugLog(
        'Explanation rubric:  ${outcome.rubricPasses}/${outcome.totalCount}  ${pct(outcome.rubricPasses, outcome.totalCount)}');
    debugLog('NeedsReview count:   ${outcome.needsReviewCount}');
    debugLog('Cold-start latency:  ${coldSw.elapsedMilliseconds} ms');
    debugLog('Per-call latency:    ${outcome.perCallLatency.toLogLine()}');

    // -- WRITEUP §6 paste-line --------------------------------------------
    debugLog('-- WRITEUP §6 row (E2B) --');
    debugLog(writeupSummaryLine(
      model: 'Gemma 4 E2B',
      coldStartLabel: 'cold-start',
      coldStartMs: coldSw.elapsedMilliseconds,
      perCall: outcome.perCallLatency,
      accuracyLabel:
          'cat=${pct(outcome.categoryMatches, outcome.totalCount)}, risk=${pct(outcome.riskLevelMatches, outcome.totalCount)}',
      accuracyValue:
          '${pct(outcome.bothMatches, outcome.totalCount)} (both)',
      rubricValue: pct(outcome.rubricPasses, outcome.totalCount),
    ));

    // -- CSV ---------------------------------------------------------------
    final outDir = (await getApplicationDocumentsDirectory()).path;
    final csvPath = OutputDir.timestampedFile(
      outDir,
      'mode1_results',
      'csv',
    );
    await writeCsv(
      path: csvPath,
      header: Mode1RowResult.csvHeader,
      rows: outcome.rowResults.map((r) => r.toCsvRow()).toList(growable: false),
    );
    debugLog(
        'CSV written: $csvPath  (pull with `adb pull` — see eval/README.md §5)');
    expect(await File(csvPath).exists(), isTrue);

    // -- Assertions --------------------------------------------------------
    // We assert against thresholds from the dataset so this code stays
    // honest if Week-3 numbers prompt a re-baseline.
    expect(
      outcome.categoryAccuracy,
      greaterThanOrEqualTo(dataset.targetAccuracy),
      reason:
          'Category accuracy ${pct(outcome.categoryMatches, outcome.totalCount)} '
          'below target ${(dataset.targetAccuracy * 100).toStringAsFixed(1)}%',
    );
    expect(
      outcome.riskLevelAccuracy,
      greaterThanOrEqualTo(dataset.targetAccuracy),
      reason:
          'RiskLevel accuracy ${pct(outcome.riskLevelMatches, outcome.totalCount)} '
          'below target ${(dataset.targetAccuracy * 100).toStringAsFixed(1)}%',
    );
    expect(
      outcome.rubricAccuracy,
      greaterThanOrEqualTo(dataset.targetRubric),
      reason:
          'Explanation rubric ${pct(outcome.rubricPasses, outcome.totalCount)} '
          'below target ${(dataset.targetRubric * 100).toStringAsFixed(1)}%',
    );
    expect(
      outcome.perCallLatency.median,
      lessThan(dataset.targetLatencyMs),
      reason:
          'Median per-call latency ${outcome.perCallLatency.median} ms '
          '≥ target ${dataset.targetLatencyMs} ms',
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// Centralised log so `flutter test` capture is consistent. Using `print` for
/// integration tests is intentional: the result is what the harness
/// surfaces in its stdout — the eval CSV is the authoritative artefact.
// ignore: avoid_print
void debugLog(String msg) => print('[mode1_eval] $msg');
