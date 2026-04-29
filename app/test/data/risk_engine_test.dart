// Pure-function tests for RiskEngine. The DB-backed methods need a sqflite
// instance which Flutter test harness doesn't ship by default — instead we
// pin down the constants and helper formulas, since the Layer 3 explanation
// UI cites them verbatim and any drift would silently change user-facing
// copy.

import 'package:app/data/risk_engine.dart';
import 'package:app/models/report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RiskEngine.decay', () {
    test('decay(0) == 1', () {
      expect(RiskEngine.decay(Duration.zero), closeTo(1.0, 1e-9));
    });

    test('decay(7d) == 1/e', () {
      expect(
        RiskEngine.decay(const Duration(days: 7)),
        closeTo(0.36787944117, 1e-6),
      );
    });

    test('negative ages clamp to 1.0', () {
      expect(
        RiskEngine.decay(const Duration(hours: -5)),
        closeTo(1.0, 1e-9),
      );
    });
  });

  group('RiskEngine.surgeFactor', () {
    test('zero recent reports = 1.0', () {
      expect(RiskEngine.surgeFactor(0), 1.0);
    });

    test('5 reports → 1 + min(2.0, 5×0.3) = 2.5', () {
      expect(RiskEngine.surgeFactor(5), closeTo(2.5, 1e-9));
    });

    test('caps at 3.0 regardless of input', () {
      expect(RiskEngine.surgeFactor(1000), closeTo(3.0, 1e-9));
    });
  });

  group('RiskEngine.timeFactor', () {
    test('22:00 is night', () {
      expect(
        RiskEngine.timeFactor(DateTime(2026, 4, 26, 22, 0)),
        1.5,
      );
    });

    test('04:59 is night', () {
      expect(
        RiskEngine.timeFactor(DateTime(2026, 4, 26, 4, 59)),
        1.5,
      );
    });

    test('05:00 is day', () {
      expect(
        RiskEngine.timeFactor(DateTime(2026, 4, 26, 5, 0)),
        1.0,
      );
    });

    test('14:00 is day', () {
      expect(
        RiskEngine.timeFactor(DateTime(2026, 4, 26, 14, 0)),
        1.0,
      );
    });
  });

  group('RiskEngine.reputationFor', () {
    test('clamps low', () {
      expect(RiskEngine.reputationFor(0.1), 0.5);
    });

    test('clamps high', () {
      expect(RiskEngine.reputationFor(2.5), 1.5);
    });

    test('passes mid-range through', () {
      expect(RiskEngine.reputationFor(1.0), 1.0);
    });
  });

  group('Category & severity weight tables', () {
    test('all enum values are weighted (no missing keys)', () {
      for (final c in ReportCategory.values) {
        expect(RiskEngine.categoryWeight[c], isNotNull);
      }
      for (final l in RiskLevel.values) {
        expect(RiskEngine.severityWeight[l], isNotNull);
      }
    });

    test('violence is the heaviest category', () {
      final maxC =
          RiskEngine.categoryWeight.values.reduce((a, b) => a > b ? a : b);
      expect(RiskEngine.categoryWeight[ReportCategory.violence], maxC);
    });

    test('high severity is heaviest', () {
      expect(RiskEngine.severityWeight[RiskLevel.high], 1.0);
      expect(
        RiskEngine.severityWeight[RiskLevel.high]!,
        greaterThan(RiskEngine.severityWeight[RiskLevel.medium]!),
      );
      expect(
        RiskEngine.severityWeight[RiskLevel.medium]!,
        greaterThan(RiskEngine.severityWeight[RiskLevel.low]!),
      );
    });
  });
}
