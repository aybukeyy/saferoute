// Mode 2 (E4B summarizeCell) eval runner. Same callable-injection pattern as
// the Mode 1 runner so test and standalone code share one implementation.

import 'dart:async';

import 'package:app/models/report.dart';

import 'dataset.dart';
import 'harness.dart';
import 'rubric.dart';

/// Signature compatible with `GemmaService.summarizeCell` — wrapper functions
/// in the test side reduce the named-parameter surface to this.
typedef SummarizeFn = Future<String> Function({
  required String geohash7,
  required List<Report> recentReports,
  required bool isNight,
  int hours,
});

class Mode2Outcome {
  final List<Mode2CaseResult> caseResults;
  final LatencyStats perCallLatency;
  final int totalCount;
  final int rubricPasses;

  const Mode2Outcome({
    required this.caseResults,
    required this.perCallLatency,
    required this.totalCount,
    required this.rubricPasses,
  });

  double get rubricAccuracy =>
      totalCount == 0 ? 0.0 : rubricPasses / totalCount;
}

class Mode2Runner {
  final Mode2Dataset dataset;
  final SummarizeFn summarize;
  final void Function(int index, int total, Mode2Case c)? onProgress;

  Mode2Runner({
    required this.dataset,
    required this.summarize,
    this.onProgress,
  });

  Future<Mode2Outcome> run() async {
    final results = <Mode2CaseResult>[];
    final latencies = <int>[];
    int rubricPasses = 0;

    for (int i = 0; i < dataset.cases.length; i++) {
      final c = dataset.cases[i];
      onProgress?.call(i, dataset.cases.length, c);

      // Build synthetic Report objects from the tuple list. The summariser
      // only reads `text`, `category`, `riskLevel` (per prompts.dart
      // summarizeUser) so the other fields are filled with safe stubs.
      final reports = c.reports
          .map(
            (t) => Report(
              id: 'eval-${c.id}-${t.text.hashCode}',
              uid: 'eval',
              text: t.text,
              lat: 0,
              lng: 0,
              geohash7: c.geohash7,
              occurredAt: DateTime.utc(2026, 4, 25),
              category: _categoryFromWire(t.category),
              riskLevel: _riskLevelFromWire(t.level),
              createdAt: DateTime.utc(2026, 4, 25),
            ),
          )
          .toList(growable: false);

      final sw = Stopwatch()..start();
      String summary;
      try {
        summary = await summarize(
          geohash7: c.geohash7,
          recentReports: reports,
          isNight: c.night,
          hours: c.hours,
        );
      } catch (e) {
        sw.stop();
        results.add(Mode2CaseResult(
          id: c.id,
          geohash7: c.geohash7,
          hours: c.hours,
          night: c.night,
          reportCount: c.reports.length,
          summary: 'ERROR:$e',
          summaryWordCount: 0,
          rubricPass: false,
          rubricFailures: ['threwException'],
          latencyMs: sw.elapsedMilliseconds,
        ));
        latencies.add(sw.elapsedMilliseconds);
        continue;
      }
      sw.stop();
      latencies.add(sw.elapsedMilliseconds);

      final rubric = checkMode2Summary(summary);
      if (rubric.pass) rubricPasses++;

      results.add(Mode2CaseResult(
        id: c.id,
        geohash7: c.geohash7,
        hours: c.hours,
        night: c.night,
        reportCount: c.reports.length,
        summary: summary,
        summaryWordCount: rubric.wordCount,
        rubricPass: rubric.pass,
        rubricFailures: rubric.failures,
        latencyMs: sw.elapsedMilliseconds,
      ));
    }

    return Mode2Outcome(
      caseResults: results,
      perCallLatency: LatencyStats.fromSamples(latencies),
      totalCount: dataset.cases.length,
      rubricPasses: rubricPasses,
    );
  }

  // -- wire <-> enum --------------------------------------------------------
  // Mirror of GemmaPrompts._categoryFromWire / _riskLevelFromWire — kept
  // private here so eval/ doesn't reach into ai/ implementation details.

  static ReportCategory _categoryFromWire(String wire) {
    switch (wire.trim().toLowerCase()) {
      case 'violence':
        return ReportCategory.violence;
      case 'theft':
        return ReportCategory.theft;
      case 'harassment':
        return ReportCategory.harassment;
      case 'suspicious_activity':
        return ReportCategory.suspiciousActivity;
      case 'vandalism':
        return ReportCategory.vandalism;
      case 'other':
      default:
        return ReportCategory.other;
    }
  }

  static RiskLevel _riskLevelFromWire(String wire) {
    switch (wire.trim().toLowerCase()) {
      case 'medium':
        return RiskLevel.medium;
      case 'high':
        return RiskLevel.high;
      case 'low':
      default:
        return RiskLevel.low;
    }
  }
}
