// Heatmap painter tests — verifies the score → colour gradient.
//
// We do NOT golden-test the painter here because the camera projection
// requires a fully laid-out FlutterMap and golden files are sensitive to
// platform font rendering. Instead we lock the colour function — the
// part that defines the demo's visual identity (PLAN.md §4.1).

import 'package:app/app/theme.dart';
import 'package:app/features/map/heatmap_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeatmapPainter.colorForScore', () {
    test('low scores use yellow/amber', () {
      final c = HeatmapPainter.colorForScore(0.1);
      expect(c.a, closeTo(80 / 255, 0.01));
      // Hue close to amber (R high, G high, B low).
      expect(c.r, greaterThan(c.b));
    });

    test('mid scores blend amber → orange', () {
      final c = HeatmapPainter.colorForScore(0.4);
      expect(c.a, closeTo(120 / 255, 0.01));
    });

    test('high scores blend orange → red', () {
      final c = HeatmapPainter.colorForScore(0.65);
      expect(c.a, closeTo(150 / 255, 0.01));
    });

    test('top bracket pins to red with the highest alpha', () {
      final c = HeatmapPainter.colorForScore(0.95);
      expect(c.a, closeTo(180 / 255, 0.01));
      // The red bracket uses the kRiskHigh seed colour exactly.
      expect(c.r, equals(kRiskHigh.r));
      expect(c.g, equals(kRiskHigh.g));
      expect(c.b, equals(kRiskHigh.b));
    });

    test('alpha increases monotonically across brackets', () {
      final lo = HeatmapPainter.colorForScore(0.1).a;
      final mid = HeatmapPainter.colorForScore(0.4).a;
      final hi = HeatmapPainter.colorForScore(0.7).a;
      final top = HeatmapPainter.colorForScore(0.9).a;
      expect(lo, lessThan(mid));
      expect(mid, lessThan(hi));
      expect(hi, lessThan(top));
    });
  });

  test('Color tokens are not the default Material palette', () {
    // Sanity check — the design tokens should be the custom risk gradient,
    // not Flutter's stock primary/red.
    expect(kRiskHigh, isNot(Colors.red));
    expect(kRiskMid, isNot(Colors.orange));
  });
}
