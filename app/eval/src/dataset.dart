// Dataset loader for Mode 1 and Mode 2 eval JSON.
//
// Loading strategy:
//   * Inside `flutter test integration_test/`: assets aren't bundled into the
//     test binary by default. We work around by reading from the host
//     filesystem with `dart:io` File — the integration test runs on a real
//     device/emulator and `flutter test` for integration tests has its driver
//     side execute on the host, but the under-test side runs on device. To
//     keep the data accessible from the device side, the loader supports BOTH
//     `rootBundle` (asset path) and `File` (host path); the integration tests
//     declare these JSON files as assets via the `flutter:` block in
//     pubspec.yaml — see eval/README.md.
//   * Inside `dart run` (standalone bin/run_eval.dart): always reads from
//     File using a path relative to the package root.
//
// We intentionally do NOT use code generation (json_serializable / freezed)
// here — these eval models are plain throwaway value objects and shipping
// them through build_runner adds noise for the eval scaffolding agent's
// output.

import 'dart:convert';
import 'dart:io' show File;

class Mode1Row {
  final String id;
  final String lang;
  final String text;
  final double lat;
  final double lng;
  final DateTime occurredAt;
  final String expectedCategory;
  final String expectedRiskLevel;
  final bool expectedTimeSensitive;

  const Mode1Row({
    required this.id,
    required this.lang,
    required this.text,
    required this.lat,
    required this.lng,
    required this.occurredAt,
    required this.expectedCategory,
    required this.expectedRiskLevel,
    required this.expectedTimeSensitive,
  });

  factory Mode1Row.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    return Mode1Row(
      id: json['id'] as String,
      lang: json['lang'] as String,
      text: json['text'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      expectedCategory: expected['category'] as String,
      expectedRiskLevel: expected['riskLevel'] as String,
      expectedTimeSensitive: expected['timeSensitive'] as bool,
    );
  }
}

class Mode1Dataset {
  final int version;
  final double targetAccuracy;
  final double targetRubric;
  final int targetLatencyMs;
  final List<Mode1Row> rows;

  const Mode1Dataset({
    required this.version,
    required this.targetAccuracy,
    required this.targetRubric,
    required this.targetLatencyMs,
    required this.rows,
  });

  factory Mode1Dataset.fromJson(Map<String, dynamic> json) {
    final rows = (json['rows'] as List)
        .map((e) => Mode1Row.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return Mode1Dataset(
      version: json['version'] as int,
      targetAccuracy: (json['targetAccuracy'] as num).toDouble(),
      targetRubric: (json['targetRubric'] as num).toDouble(),
      targetLatencyMs: (json['targetLatencyMs'] as num).toInt(),
      rows: rows,
    );
  }

  static Mode1Dataset fromJsonString(String raw) =>
      Mode1Dataset.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Convenience for standalone `dart run` mode — reads from the package root.
  static Future<Mode1Dataset> loadFromFile(String path) async {
    final raw = await File(path).readAsString();
    return fromJsonString(raw);
  }
}

class Mode2ReportTuple {
  final String category;
  final String level;
  final String text;
  const Mode2ReportTuple({
    required this.category,
    required this.level,
    required this.text,
  });

  factory Mode2ReportTuple.fromJson(Map<String, dynamic> json) =>
      Mode2ReportTuple(
        category: json['category'] as String,
        level: json['level'] as String,
        text: json['text'] as String,
      );
}

class Mode2Case {
  final String id;
  final String geohash7;
  final int hours;
  final bool night;
  final List<Mode2ReportTuple> reports;

  const Mode2Case({
    required this.id,
    required this.geohash7,
    required this.hours,
    required this.night,
    required this.reports,
  });

  factory Mode2Case.fromJson(Map<String, dynamic> json) => Mode2Case(
        id: json['id'] as String,
        geohash7: json['geohash7'] as String,
        hours: (json['hours'] as num).toInt(),
        night: json['night'] as bool,
        reports: (json['reports'] as List)
            .map((e) => Mode2ReportTuple.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class Mode2Dataset {
  final int version;
  final double targetRubric;
  final int targetLatencyMs;
  final List<Mode2Case> cases;

  const Mode2Dataset({
    required this.version,
    required this.targetRubric,
    required this.targetLatencyMs,
    required this.cases,
  });

  factory Mode2Dataset.fromJson(Map<String, dynamic> json) {
    final cases = (json['cases'] as List)
        .map((e) => Mode2Case.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return Mode2Dataset(
      version: json['version'] as int,
      targetRubric: (json['targetRubric'] as num).toDouble(),
      targetLatencyMs: (json['targetLatencyMs'] as num).toInt(),
      cases: cases,
    );
  }

  static Mode2Dataset fromJsonString(String raw) =>
      Mode2Dataset.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  static Future<Mode2Dataset> loadFromFile(String path) async {
    final raw = await File(path).readAsString();
    return fromJsonString(raw);
  }
}
