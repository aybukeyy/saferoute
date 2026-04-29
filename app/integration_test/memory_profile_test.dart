// Memory profile — RSS sampling around 100 sequential E2B classify calls.
//
// What this measures:
//   * Process RSS (resident set size) before warm-up, after warm-up, and
//     every 10 classify calls.
//
// What this does NOT measure:
//   * Peak GPU memory (LiteRT-internal, not exposed via Dart).
//   * Native heap allocations attributable to flutter_gemma vs the rest of
//     the app — this is "whole-process RSS" only.
//   * Battery — that requires Android Battery Historian; see
//     `app/eval/README.md §6` for the manual procedure.
//
// On Android, `ProcessInfo.currentRss` is reported in bytes (per
// `dart:io` docs). On iOS the same field works. On platforms where it is
// unavailable / zero, the test logs a warning and writes 0 — the CSV is still
// produced so the writeup can note "RSS unavailable on this platform".

import 'dart:io' show File, ProcessInfo;

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

const int _classifyIterations = 100;
const int _sampleEvery = 10;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late GemmaService service;

  setUpAll(() async {
    service = GemmaService();
  });

  tearDownAll(() async {
    await service.dispose();
  });

  testWidgets('Memory — RSS around $_classifyIterations classify calls',
      (tester) async {
    final samples = <List<dynamic>>[];

    final preWarm = _rssMb();
    samples.add(['pre_warmup', 0, preWarm]);
    debugLog('pre-warmup RSS: ${preWarm.toStringAsFixed(1)} MB');

    await service.warmUpE2B();
    final postWarm = _rssMb();
    samples.add(['post_warmup', 0, postWarm]);
    debugLog('post-warmup RSS: ${postWarm.toStringAsFixed(1)} MB '
        '(Δ ${(postWarm - preWarm).toStringAsFixed(1)} MB)');

    for (int i = 0; i < _classifyIterations; i++) {
      await service.classify(
        text: _benchText,
        lat: _benchLat,
        lng: _benchLng,
        occurredAt: _benchOccurredAt,
      );
      if (i == 0 || (i + 1) % _sampleEvery == 0) {
        final rss = _rssMb();
        samples.add(['classify', i + 1, rss]);
        debugLog('after ${i + 1} calls: ${rss.toStringAsFixed(1)} MB');
      }
    }

    final finalRss = _rssMb();
    samples.add(['post_run', _classifyIterations, finalRss]);

    debugLog(banner('Memory profile summary'));
    debugLog('pre-warmup:   ${preWarm.toStringAsFixed(1)} MB');
    debugLog('post-warmup:  ${postWarm.toStringAsFixed(1)} MB');
    debugLog('post-run:     ${finalRss.toStringAsFixed(1)} MB');
    debugLog(
        'warm-up cost: ${(postWarm - preWarm).toStringAsFixed(1)} MB');
    debugLog(
        'run drift:    ${(finalRss - postWarm).toStringAsFixed(1)} MB');
    if (preWarm <= 0) {
      debugLog(
          'WARN: ProcessInfo.currentRss reported 0 — likely unavailable on this platform; '
          'CSV will record zeros. See test file header.');
    }

    final outDir = (await getApplicationDocumentsDirectory()).path;
    final csvPath = OutputDir.timestampedFile(outDir, 'memory', 'csv');
    await writeCsv(
      path: csvPath,
      header: const ['phase', 'call_index', 'rss_mb'],
      rows: samples,
    );
    debugLog('CSV written: $csvPath');
    expect(await File(csvPath).exists(), isTrue);

    // Soft sanity: no test-side assertion on RSS magnitudes — Pixel-7-class
    // numbers will be re-baselined in Week 3 and fed into WRITEUP §6.
    // We only require that we collected ≥ 12 samples (pre + post + 10 mid +
    // post_run) so the CSV is informative.
    expect(samples.length, greaterThanOrEqualTo(12));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

double _rssMb() {
  final bytes = ProcessInfo.currentRss;
  if (bytes <= 0) return 0.0;
  return bytes / (1024.0 * 1024.0);
}

// ignore: avoid_print
void debugLog(String msg) => print('[memory_profile] $msg');
