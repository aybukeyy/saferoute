// Latency bench — accuracy is NOT measured here. Pure performance profiling
// for the WRITEUP §6 table.
//
// Phases (in order, sharing one process so hot-swap cost is realistic):
//   1. E2B cold-start — first warm-up after process boot.
//   2. E2B per-call   — 100 sequential classify calls on the same prompt.
//   3. E4B cold-start — first warm-up; this measurement INCLUDES the hot-swap
//                       cost (closing E2B, loading E4B) because that is the
//                       cost the production app actually pays.
//   4. E4B per-call   — 30 sequential summarize calls on the same input.
//   5. Hot-swap cycle — classify → summarize → classify, three times. The
//                       middle "back to E2B" warm-up is what we report as the
//                       isolated swap cost (E4B was already loaded once).
//
// Output: CSV with one row per call (`phase`, `iteration`, `latency_ms`) plus
// stdout summary blocks per phase.

import 'dart:io' show File;

import 'package:app/ai/gemma_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../eval/src/harness.dart';

const String _benchText =
    'Around 11pm two men approached me near Akaretler and demanded my phone.';
const double _benchLat = 41.0451;
const double _benchLng = 28.9912;
final DateTime _benchOccurredAt = DateTime.utc(2026, 4, 25, 20, 0);

const int _e2bIterations = 100;
const int _e4bIterations = 30;
const int _hotSwapCycles = 3;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late GemmaService service;

  setUpAll(() async {
    service = GemmaService();
  });

  tearDownAll(() async {
    await service.dispose();
  });

  testWidgets('Latency bench — cold-start, per-call, hot-swap',
      (tester) async {
    final csvRows = <List<dynamic>>[];

    // -- 1. E2B cold-start ------------------------------------------------
    debugLog(banner('E2B cold-start'));
    final e2bCold = Stopwatch()..start();
    await service.warmUpE2B();
    e2bCold.stop();
    debugLog('E2B cold-start: ${e2bCold.elapsedMilliseconds} ms');
    csvRows.add(['cold_start_e2b', 0, e2bCold.elapsedMilliseconds]);

    // -- 2. E2B per-call --------------------------------------------------
    debugLog(banner('E2B per-call ($_e2bIterations iterations)'));
    final e2bSamples = <int>[];
    for (int i = 0; i < _e2bIterations; i++) {
      final sw = Stopwatch()..start();
      await service.classify(
        text: _benchText,
        lat: _benchLat,
        lng: _benchLng,
        occurredAt: _benchOccurredAt,
      );
      sw.stop();
      e2bSamples.add(sw.elapsedMilliseconds);
      csvRows.add(['per_call_e2b', i, sw.elapsedMilliseconds]);
      if (i % 10 == 0) {
        debugLog('e2b iteration $i: ${sw.elapsedMilliseconds} ms');
      }
    }
    final e2bStats = LatencyStats.fromSamples(e2bSamples);
    debugLog('E2B per-call: ${e2bStats.toLogLine()}');

    // -- 3. E4B cold-start (includes hot-swap) ----------------------------
    debugLog(banner('E4B cold-start (with hot-swap from E2B)'));
    final e4bCold = Stopwatch()..start();
    await service.warmUpE4B();
    e4bCold.stop();
    debugLog('E4B cold-start (incl. swap): ${e4bCold.elapsedMilliseconds} ms');
    csvRows.add(['cold_start_e4b_with_swap', 0, e4bCold.elapsedMilliseconds]);

    // -- 4. E4B per-call --------------------------------------------------
    debugLog(banner('E4B per-call ($_e4bIterations iterations)'));
    final e4bSamples = <int>[];
    for (int i = 0; i < _e4bIterations; i++) {
      // Empty report list keeps each call cheap and deterministic — the
      // production summary cache would short-circuit identical inputs, but
      // we want to measure the engine, not the cache.
      final sw = Stopwatch()..start();
      await service.summarizeCell(
        // Vary the cell key per iteration so the 5-min cache misses every time.
        geohash7: 'sxk9pq${i.toString().padLeft(2, '0')}',
        recentReports: const [],
        isNight: true,
      );
      sw.stop();
      e4bSamples.add(sw.elapsedMilliseconds);
      csvRows.add(['per_call_e4b', i, sw.elapsedMilliseconds]);
      if (i % 5 == 0) {
        debugLog('e4b iteration $i: ${sw.elapsedMilliseconds} ms');
      }
    }
    final e4bStats = LatencyStats.fromSamples(e4bSamples);
    debugLog('E4B per-call: ${e4bStats.toLogLine()}');

    // -- 5. Hot-swap cycle ------------------------------------------------
    // Cycle: classify (E2B) → summarize (E4B) → classify (E2B). The classify
    // call after summarize forces a swap *back* to E2B; that's the cost we
    // want to isolate. We discard the call latency itself and only record
    // the warm-up overhead by stopping the stopwatch before the first session
    // body runs — but `flutter_gemma` doesn't expose that hook, so we
    // approximate by recording the full classify latency and subtracting the
    // E2B per-call median measured above.
    debugLog(banner('Hot-swap cycle ($_hotSwapCycles cycles)'));
    final swapToE2BSamples = <int>[];
    final swapToE4BSamples = <int>[];
    for (int cycle = 0; cycle < _hotSwapCycles; cycle++) {
      // Classify (no swap if already on E2B; record anyway).
      final sw1 = Stopwatch()..start();
      await service.classify(
        text: _benchText,
        lat: _benchLat,
        lng: _benchLng,
        occurredAt: _benchOccurredAt,
      );
      sw1.stop();
      csvRows.add(['hotswap_classify', cycle, sw1.elapsedMilliseconds]);

      // Summarize (swap E2B→E4B).
      final sw2 = Stopwatch()..start();
      await service.summarizeCell(
        geohash7: 'sxk9pqs$cycle',
        recentReports: const [],
        isNight: false,
      );
      sw2.stop();
      final swapToE4BCost = (sw2.elapsedMilliseconds - e4bStats.median)
          .clamp(0, sw2.elapsedMilliseconds);
      swapToE4BSamples.add(swapToE4BCost);
      csvRows.add(['hotswap_summarize', cycle, sw2.elapsedMilliseconds]);
      csvRows.add(['hotswap_swap_e2b_to_e4b', cycle, swapToE4BCost]);

      // Classify again (swap E4B→E2B).
      final sw3 = Stopwatch()..start();
      await service.classify(
        text: _benchText,
        lat: _benchLat,
        lng: _benchLng,
        occurredAt: _benchOccurredAt,
      );
      sw3.stop();
      final swapToE2BCost = (sw3.elapsedMilliseconds - e2bStats.median)
          .clamp(0, sw3.elapsedMilliseconds);
      swapToE2BSamples.add(swapToE2BCost);
      csvRows.add(['hotswap_classify_back', cycle, sw3.elapsedMilliseconds]);
      csvRows.add(['hotswap_swap_e4b_to_e2b', cycle, swapToE2BCost]);

      debugLog(
          'cycle $cycle: classify ${sw1.elapsedMilliseconds} → summarize ${sw2.elapsedMilliseconds} (~${swapToE4BCost}ms swap) → classify ${sw3.elapsedMilliseconds} (~${swapToE2BCost}ms swap)');
    }

    final swapToE2B = LatencyStats.fromSamples(swapToE2BSamples);
    final swapToE4B = LatencyStats.fromSamples(swapToE4BSamples);
    debugLog('Approx swap E4B→E2B cost: ${swapToE2B.toLogLine()}');
    debugLog('Approx swap E2B→E4B cost: ${swapToE4B.toLogLine()}');

    // -- WRITEUP §6 paste-lines -------------------------------------------
    debugLog('-- WRITEUP §6 row (E2B latency) --');
    debugLog(writeupSummaryLine(
      model: 'Gemma 4 E2B',
      coldStartLabel: 'cold-start',
      coldStartMs: e2bCold.elapsedMilliseconds,
      perCall: e2bStats,
      accuracyLabel: 'see mode1_accuracy_test',
    ));
    debugLog('-- WRITEUP §6 row (E4B latency) --');
    debugLog(writeupSummaryLine(
      model: 'Gemma 4 E4B',
      coldStartLabel: 'cold-start (incl. hot-swap)',
      coldStartMs: e4bCold.elapsedMilliseconds,
      perCall: e4bStats,
      accuracyLabel: 'see mode2_summary_test',
    ));

    // -- CSV --------------------------------------------------------------
    final outDir = (await getApplicationDocumentsDirectory()).path;
    final csvPath = OutputDir.timestampedFile(outDir, 'latency', 'csv');
    await writeCsv(
      path: csvPath,
      header: const ['phase', 'iteration', 'latency_ms'],
      rows: csvRows,
    );
    debugLog('CSV written: $csvPath');
    expect(await File(csvPath).exists(), isTrue);

    // No accuracy assertions in this test — bench only.
    // Sanity: at least one E2B sample must be under the global 5s budget,
    // otherwise something is structurally wrong (e.g. CPU throttling).
    expect(e2bStats.median, lessThan(5000),
        reason:
            'E2B median ${e2bStats.median} ms exceeds the 5s end-to-end budget — investigate device thermals.');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

// ignore: avoid_print
void debugLog(String msg) => print('[latency_bench] $msg');
