// Standalone Dart entry point for the eval scaffolding.
//
// Purpose:
//   * Lets `dart analyze` cover the eval/lib/* code without needing the
//     `integration_test` package.
//   * Lets the user smoke-test the harness wiring with a stub classifier on
//     the host (no real Gemma weights required) before running the heavy
//     integration tests on a device.
//
// Usage:
//   dart run app/eval/bin/run_eval.dart           # both modes, stub model
//   dart run app/eval/bin/run_eval.dart mode1     # mode 1 only
//   dart run app/eval/bin/run_eval.dart mode2     # mode 2 only
//
// The stub classifier returns the parser's safeDefault for every input — so
// the printed accuracy is deliberately near-zero. The point is to exercise
// the runner + CSV pipeline end-to-end on the host.

import 'dart:io';

import 'package:app/ai/parser.dart' show GemmaClassificationParser;
import 'package:app/models/classification.dart';
import 'package:app/models/report.dart';

import '../src/dataset.dart';
import '../src/harness.dart';
import '../src/mode1_runner.dart';
import '../src/mode2_runner.dart';

const String _mode1Path = 'eval/data/mode1_dataset.json';
const String _mode2Path = 'eval/data/mode2_cases.json';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'all' : args.first;
  final outputDir = OutputDir.defaultHostPath();

  if (mode == 'mode1' || mode == 'all') {
    await _runMode1(outputDir);
  }
  if (mode == 'mode2' || mode == 'all') {
    await _runMode2(outputDir);
  }
}

Future<void> _runMode1(String outputDir) async {
  stdout.writeln(banner('Mode 1 stub run (no real model)'));
  final dataset = await Mode1Dataset.loadFromFile(_mode1Path);
  stdout.writeln('loaded ${dataset.rows.length} rows '
      '(version=${dataset.version}, targetAccuracy=${dataset.targetAccuracy})');

  final runner = Mode1Runner(
    dataset: dataset,
    classify: _stubClassify,
  );
  final outcome = await runner.run();

  stdout.writeln(
      'category=${outcome.categoryMatches}/${outcome.totalCount}  '
      'risk=${outcome.riskLevelMatches}/${outcome.totalCount}  '
      'rubric=${outcome.rubricPasses}/${outcome.totalCount}  '
      'latency=${outcome.perCallLatency.toLogLine()}');

  final csv = OutputDir.timestampedFile(outputDir, 'mode1_stub', 'csv');
  await writeCsv(
    path: csv,
    header: Mode1RowResult.csvHeader,
    rows: outcome.rowResults.map((r) => r.toCsvRow()).toList(growable: false),
  );
  stdout.writeln('wrote $csv');
}

Future<void> _runMode2(String outputDir) async {
  stdout.writeln(banner('Mode 2 stub run (no real model)'));
  final dataset = await Mode2Dataset.loadFromFile(_mode2Path);
  stdout.writeln('loaded ${dataset.cases.length} cases '
      '(version=${dataset.version}, targetRubric=${dataset.targetRubric})');

  final runner = Mode2Runner(
    dataset: dataset,
    summarize: _stubSummarize,
  );
  final outcome = await runner.run();

  stdout.writeln('rubric=${outcome.rubricPasses}/${outcome.totalCount}  '
      'latency=${outcome.perCallLatency.toLogLine()}');

  final csv = OutputDir.timestampedFile(outputDir, 'mode2_stub', 'csv');
  await writeCsv(
    path: csv,
    header: Mode2CaseResult.csvHeader,
    rows: outcome.caseResults.map((r) => r.toCsvRow()).toList(growable: false),
  );
  stdout.writeln('wrote $csv');
}

// -- stub model implementations --------------------------------------------

Future<Classification> _stubClassify({
  required String text,
  required double lat,
  required double lng,
  required DateTime occurredAt,
}) async {
  // Pretend an inference happened.
  await Future<void>.delayed(const Duration(milliseconds: 1));
  return GemmaClassificationParser.safeDefault;
}

Future<String> _stubSummarize({
  required String geohash7,
  required List<Report> recentReports,
  required bool isNight,
  int hours = 6,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
  return 'Reports in this cell are mixed and sparse over the recent period.';
}
