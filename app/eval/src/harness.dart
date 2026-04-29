// Shared eval harness: latency aggregation, CSV helpers, and the eval-row /
// summary structures consumed by Mode 1, Mode 2, latency, and memory tests.
//
// Lives outside `lib/` (the production module) so eval code never accidentally
// ships with the app.

import 'dart:io' show Directory, File;
import 'dart:math' as math;

/// Aggregated latency stats over a list of millisecond samples.
class LatencyStats {
  final int count;
  final int min;
  final int max;
  final int mean;
  final int median;
  final int p95;
  final int p99;

  const LatencyStats({
    required this.count,
    required this.min,
    required this.max,
    required this.mean,
    required this.median,
    required this.p95,
    required this.p99,
  });

  factory LatencyStats.fromSamples(List<int> samples) {
    if (samples.isEmpty) {
      return const LatencyStats(
        count: 0,
        min: 0,
        max: 0,
        mean: 0,
        median: 0,
        p95: 0,
        p99: 0,
      );
    }
    final sorted = [...samples]..sort();
    final n = sorted.length;
    final sum = sorted.fold<int>(0, (a, b) => a + b);
    int pct(double p) {
      // Nearest-rank percentile, clamped to [0, n-1].
      final rank = (p * n).ceil() - 1;
      return sorted[rank.clamp(0, n - 1)];
    }

    return LatencyStats(
      count: n,
      min: sorted.first,
      max: sorted.last,
      mean: (sum / n).round(),
      median: pct(0.50),
      p95: pct(0.95),
      p99: pct(0.99),
    );
  }

  Map<String, dynamic> toMap() => {
        'count': count,
        'min_ms': min,
        'max_ms': max,
        'mean_ms': mean,
        'median_ms': median,
        'p95_ms': p95,
        'p99_ms': p99,
      };

  String toLogLine() =>
      'count=$count mean=${mean}ms median=${median}ms p95=${p95}ms p99=${p99}ms (min=${min}ms max=${max}ms)';
}

/// Single Mode 1 row outcome — one CSV line.
class Mode1RowResult {
  final String id;
  final String lang;
  final String expectedCategory;
  final String actualCategory;
  final bool categoryMatch;
  final String expectedRiskLevel;
  final String actualRiskLevel;
  final bool riskLevelMatch;
  final bool bothMatch;
  final bool expectedTimeSensitive;
  final bool actualTimeSensitive;
  final double confidence;
  final bool needsReview;
  final String explanation;
  final int explanationWordCount;
  final bool rubricPass;
  final List<String> rubricFailures;
  final int latencyMs;

  const Mode1RowResult({
    required this.id,
    required this.lang,
    required this.expectedCategory,
    required this.actualCategory,
    required this.categoryMatch,
    required this.expectedRiskLevel,
    required this.actualRiskLevel,
    required this.riskLevelMatch,
    required this.bothMatch,
    required this.expectedTimeSensitive,
    required this.actualTimeSensitive,
    required this.confidence,
    required this.needsReview,
    required this.explanation,
    required this.explanationWordCount,
    required this.rubricPass,
    required this.rubricFailures,
    required this.latencyMs,
  });

  static const List<String> csvHeader = [
    'id',
    'lang',
    'expected_category',
    'actual_category',
    'category_match',
    'expected_risk_level',
    'actual_risk_level',
    'risk_level_match',
    'both_match',
    'expected_time_sensitive',
    'actual_time_sensitive',
    'confidence',
    'needs_review',
    'rubric_pass',
    'rubric_failures',
    'explanation_word_count',
    'explanation',
    'latency_ms',
  ];

  List<dynamic> toCsvRow() => [
        id,
        lang,
        expectedCategory,
        actualCategory,
        categoryMatch,
        expectedRiskLevel,
        actualRiskLevel,
        riskLevelMatch,
        bothMatch,
        expectedTimeSensitive,
        actualTimeSensitive,
        confidence.toStringAsFixed(2),
        needsReview,
        rubricPass,
        rubricFailures.join('|'),
        explanationWordCount,
        explanation,
        latencyMs,
      ];
}

class Mode2CaseResult {
  final String id;
  final String geohash7;
  final int hours;
  final bool night;
  final int reportCount;
  final String summary;
  final int summaryWordCount;
  final bool rubricPass;
  final List<String> rubricFailures;
  final int latencyMs;

  const Mode2CaseResult({
    required this.id,
    required this.geohash7,
    required this.hours,
    required this.night,
    required this.reportCount,
    required this.summary,
    required this.summaryWordCount,
    required this.rubricPass,
    required this.rubricFailures,
    required this.latencyMs,
  });

  static const List<String> csvHeader = [
    'id',
    'geohash7',
    'hours',
    'night',
    'report_count',
    'rubric_pass',
    'rubric_failures',
    'summary_word_count',
    'summary',
    'latency_ms',
  ];

  List<dynamic> toCsvRow() => [
        id,
        geohash7,
        hours,
        night,
        reportCount,
        rubricPass,
        rubricFailures.join('|'),
        summaryWordCount,
        summary,
        latencyMs,
      ];
}

/// CSV writer with minimal RFC-4180-style escaping. Avoids pulling in a
/// `csv` dependency for ten lines of output.
class CsvWriter {
  static String row(List<dynamic> values) {
    return values.map(_escape).join(',');
  }

  static String _escape(dynamic v) {
    final s = v.toString();
    final needsQuote =
        s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    final escaped = s.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }
}

/// Resolves an output directory inside `app/eval/output/`. When running on a
/// real Android device the host filesystem isn't accessible from the device
/// side; in that case we fall back to the device-local app documents dir and
/// emit a hint line so the user knows where to pull the file from.
///
/// Pass `documentsDir` when calling from a Flutter context (we use
/// `path_provider` from the test side, but it pulls in Flutter and breaks the
/// pure-Dart entry point — so plumbing it through here keeps both paths
/// honest).
class OutputDir {
  /// Default host-side path used by the standalone Dart runner.
  static String defaultHostPath() {
    final cwd = Directory.current.path;
    return _ensureExists('$cwd/eval/output');
  }

  /// Helper for picking a path: prefer [override] if non-null, else
  /// [defaultHostPath].
  static String resolve({String? override}) {
    if (override != null && override.isNotEmpty) {
      return _ensureExists(override);
    }
    return defaultHostPath();
  }

  static String timestampedFile(String dir, String prefix, String ext) {
    final now = DateTime.now().toUtc();
    final stamp = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '$dir/${prefix}_$stamp.$ext';
  }

  static String _ensureExists(String path) {
    final d = Directory(path);
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return path;
  }
}

/// Helper: writes [header] + [rows] to [path]. Each row's values are passed
/// through [CsvWriter.row].
Future<void> writeCsv({
  required String path,
  required List<String> header,
  required List<List<dynamic>> rows,
}) async {
  final buf = StringBuffer();
  buf.writeln(CsvWriter.row(header));
  for (final r in rows) {
    buf.writeln(CsvWriter.row(r));
  }
  await File(path).writeAsString(buf.toString());
}

/// Tiny helper used to print a writeup-ready single-line summary block. The
/// caller fills in the model name; we keep formatting consistent so the
/// WRITEUP.md §6 table can be filled by copy-paste.
String writeupSummaryLine({
  required String model,
  required String coldStartLabel,
  required int coldStartMs,
  required LatencyStats perCall,
  required String accuracyLabel,
  String? accuracyValue,
  String? rubricValue,
  String? memoryValue,
}) {
  final cells = <String>[
    model,
    '$coldStartMs ms',
    '${perCall.median} ms (median) / ${perCall.p95} ms (p95)',
    memoryValue ?? 'TBD',
    accuracyValue ?? 'TBD',
    rubricValue ?? 'TBD',
  ];
  return '| ${cells.join(' | ')} |  // $coldStartLabel · $accuracyLabel';
}

/// Helper: clamp a number to a percentage string with one decimal.
String pct(int numerator, int denominator) {
  if (denominator == 0) return '0.0%';
  return '${(100.0 * numerator / denominator).toStringAsFixed(1)}%';
}

/// Pretty-print a histogram-like banner — used by tests for stdout summary.
String banner(String title) {
  final bar = '=' * math.max(8, title.length + 4);
  return '$bar\n$title\n$bar';
}
