// Pulse animator tests — verifies the colour curve and total duration.
//
// We deliberately do NOT pump a real flutter_map widget here (the camera
// projection is irrelevant to the colour curve). Instead we exercise the
// static `PulseAnimator.sampleAt` curve and assert the total animation
// completes in `kPulseDuration` (2.0 s).

import 'package:app/app/theme.dart';
import 'package:app/features/map/pulse_animator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PulseAnimator.sampleAt', () {
    test('starts as opaque grey at t=0', () {
      final (color, alpha) = PulseAnimatorState.sampleAt(0.0);
      // Color.lerp(grey, kRiskMid, 0) returns a plain Color, not the
      // MaterialColor swatch — compare RGBA components instead.
      expect(color.toARGB32(), equals(Colors.grey.toARGB32()));
      expect(alpha, equals(200));
    });

    test('reaches mid-orange at the 600 ms boundary (t=0.3)', () {
      final (color, alpha) = PulseAnimatorState.sampleAt(0.3);
      // Color.lerp at the segment boundary equals the segment's end colour.
      expect(color, equals(kRiskMid));
      expect(alpha, equals(220));
    });

    test('reaches red by t=0.6', () {
      final (color, _) = PulseAnimatorState.sampleAt(0.6);
      expect(color, equals(kRiskHigh));
    });

    test('fades to alpha=0 at t=1.0', () {
      final (color, alpha) = PulseAnimatorState.sampleAt(1.0);
      expect(color, equals(kRiskHigh));
      expect(alpha, equals(0));
    });
  });

  test('kPulseDuration is exactly 2.0 s — demo beat invariant', () {
    expect(kPulseDuration.inMilliseconds, equals(2000));
  });
}
