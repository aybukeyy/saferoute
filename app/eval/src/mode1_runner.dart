// Mode 1 (E2B classify) eval runner. Pure Dart, takes a callable so the same
// entry point works whether the test side wired in a real `GemmaService` or
// (in CI without weights) a fake.

import 'dart:async';

import 'package:app/ai/prompts.dart';
import 'package:app/models/classification.dart';

import 'dataset.dart';
import 'harness.dart';
import 'rubric.dart';

/// Signature compatible with `GemmaService.classify(...)` minus the named
/// params hassle — the integration test wraps the service to match this.
typedef ClassifyFn = Future<Classification> Function({
  required String text,
  required double lat,
  required double lng,
  required DateTime occurredAt,
});

class Mode1Outcome {
  final List<Mode1RowResult> rowResults;
  final LatencyStats perCallLatency;
  final int totalCount;
  final int categoryMatches;
  final int riskLevelMatches;
  final int bothMatches;
  final int rubricPasses;
  final int needsReviewCount;

  const Mode1Outcome({
    required this.rowResults,
    required this.perCallLatency,
    required this.totalCount,
    required this.categoryMatches,
    required this.riskLevelMatches,
    required this.bothMatches,
    required this.rubricPasses,
    required this.needsReviewCount,
  });

  double get categoryAccuracy =>
      totalCount == 0 ? 0.0 : categoryMatches / totalCount;
  double get riskLevelAccuracy =>
      totalCount == 0 ? 0.0 : riskLevelMatches / totalCount;
  double get bothAccuracy => totalCount == 0 ? 0.0 : bothMatches / totalCount;
  double get rubricAccuracy =>
      totalCount == 0 ? 0.0 : rubricPasses / totalCount;
}

class Mode1Runner {
  final Mode1Dataset dataset;
  final ClassifyFn classify;

  /// Optional progress hook: `(idx, total, row)` invoked before each call.
  final void Function(int index, int total, Mode1Row row)? onProgress;

  Mode1Runner({
    required this.dataset,
    required this.classify,
    this.onProgress,
  });

  Future<Mode1Outcome> run() async {
    final results = <Mode1RowResult>[];
    final latencies = <int>[];
    int categoryMatches = 0;
    int riskLevelMatches = 0;
    int bothMatches = 0;
    int rubricPasses = 0;
    int needsReview = 0;

    for (int i = 0; i < dataset.rows.length; i++) {
      final row = dataset.rows[i];
      onProgress?.call(i, dataset.rows.length, row);

      final sw = Stopwatch()..start();
      Classification result;
      try {
        result = await classify(
          text: row.text,
          lat: row.lat,
          lng: row.lng,
          occurredAt: row.occurredAt,
        );
      } catch (e) {
        // Treat as a failed call rather than aborting the whole eval — we
        // still want a CSV row recording what happened.
        sw.stop();
        results.add(Mode1RowResult(
          id: row.id,
          lang: row.lang,
          expectedCategory: row.expectedCategory,
          actualCategory: 'ERROR:$e',
          categoryMatch: false,
          expectedRiskLevel: row.expectedRiskLevel,
          actualRiskLevel: 'ERROR',
          riskLevelMatch: false,
          bothMatch: false,
          expectedTimeSensitive: row.expectedTimeSensitive,
          actualTimeSensitive: false,
          confidence: 0.0,
          needsReview: true,
          explanation: '',
          explanationWordCount: 0,
          rubricPass: false,
          rubricFailures: ['threwException'],
          latencyMs: sw.elapsedMilliseconds,
        ));
        latencies.add(sw.elapsedMilliseconds);
        continue;
      }
      sw.stop();
      latencies.add(sw.elapsedMilliseconds);

      final actualCategory = GemmaPrompts.wireCategory(result.category);
      final actualRiskLevel = GemmaPrompts.wireRiskLevel(result.riskLevel);
      final categoryMatch = actualCategory == row.expectedCategory;
      final riskLevelMatch = actualRiskLevel == row.expectedRiskLevel;
      final bothMatch = categoryMatch && riskLevelMatch;
      if (categoryMatch) categoryMatches++;
      if (riskLevelMatch) riskLevelMatches++;
      if (bothMatch) bothMatches++;
      if (result.needsReview) needsReview++;

      final rubric = checkMode1Explanation(result.explanation);
      if (rubric.pass) rubricPasses++;

      results.add(Mode1RowResult(
        id: row.id,
        lang: row.lang,
        expectedCategory: row.expectedCategory,
        actualCategory: actualCategory,
        categoryMatch: categoryMatch,
        expectedRiskLevel: row.expectedRiskLevel,
        actualRiskLevel: actualRiskLevel,
        riskLevelMatch: riskLevelMatch,
        bothMatch: bothMatch,
        expectedTimeSensitive: row.expectedTimeSensitive,
        actualTimeSensitive: result.timeSensitive,
        confidence: result.confidence,
        needsReview: result.needsReview,
        explanation: result.explanation,
        explanationWordCount: rubric.wordCount,
        rubricPass: rubric.pass,
        rubricFailures: rubric.failures,
        latencyMs: sw.elapsedMilliseconds,
      ));
    }

    return Mode1Outcome(
      rowResults: results,
      perCallLatency: LatencyStats.fromSamples(latencies),
      totalCount: dataset.rows.length,
      categoryMatches: categoryMatches,
      riskLevelMatches: riskLevelMatches,
      bothMatches: bothMatches,
      rubricPasses: rubricPasses,
      needsReviewCount: needsReview,
    );
  }
}
