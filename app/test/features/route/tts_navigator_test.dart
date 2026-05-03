import 'dart:async';

import 'package:app/core/geohash.dart';
import 'package:app/features/route/tts_navigator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class FakeFlutterTts implements TtsEngine {
  final List<String> spoken = [];
  String? language;
  int stopCount = 0;

  @override
  Future<void> setLanguage(String value) async {
    language = value;
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

LatLng _offsetMeters(LatLng base, double dxMeters, double dyMeters) {
  const metersPerDegLat = 111320.0;
  final metersPerDegLng = 111320.0 *
      (1.0 - (base.latitude * 0.0)).abs(); // simple at equator-ish
  // Use approximate cosine for our test latitude.
  final cosLat = 0.7536; // ~ cos(41 deg)
  final dLat = dyMeters / metersPerDegLat;
  final dLng = dxMeters / (metersPerDegLng * cosLat);
  return LatLng(base.latitude + dLat, base.longitude + dLng);
}

void main() {
  group('TtsNavigator turn detection', () {
    test('announces turn cue when approaching a right turn', () async {
      // Build a polyline: long west-to-east then turn 90° south.
      const start = LatLng(41.0, 29.0);
      final corner = _offsetMeters(start, 600, 0); // 600 m east
      final end = _offsetMeters(corner, 0, -600); // 600 m south
      final polyline = [start, corner, end];

      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      final nav = TtsNavigator(
        tts: tts,
        polyline: polyline,
        avoidedCells: const [],
        languageCode: 'en',
      );
      await nav.start(controller.stream);

      // Position about 100 m east of start — corner is ~500 m ahead.
      final p1 = _offsetMeters(start, 100, 0);
      // Position about 400 m east of start — corner is ~200 m ahead.
      final p2 = _offsetMeters(start, 400, 0);

      controller.add(p1);
      await Future<void>.delayed(Duration.zero);
      controller.add(p2);
      await Future<void>.delayed(Duration.zero);

      expect(tts.language, 'en-US');
      // Corner is south of east-going traveler -> right turn.
      expect(
        tts.spoken.any((s) => s == 'Turn right in 200 meters'),
        isTrue,
        reason: 'expected a right turn cue, got: ${tts.spoken}',
      );

      await nav.dispose();
      await controller.close();
    });

    test('does not re-announce the same turn vertex twice', () async {
      const start = LatLng(41.0, 29.0);
      final corner = _offsetMeters(start, 600, 0);
      final end = _offsetMeters(corner, 0, -600);
      final polyline = [start, corner, end];

      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      var fakeTime = DateTime(2024, 1, 1, 12);
      final nav = TtsNavigator(
        tts: tts,
        polyline: polyline,
        avoidedCells: const [],
        languageCode: 'en',
        now: () => fakeTime,
      );
      await nav.start(controller.stream);

      controller.add(_offsetMeters(start, 400, 0));
      await Future<void>.delayed(Duration.zero);

      fakeTime = fakeTime.add(const Duration(seconds: 5));
      controller.add(_offsetMeters(start, 410, 0));
      await Future<void>.delayed(Duration.zero);

      final turnCues = tts.spoken
          .where((s) => s.startsWith('Turn right'))
          .toList();
      expect(turnCues.length, 1, reason: 'expected one turn cue, got $turnCues');

      await nav.dispose();
      await controller.close();
    });

    test('uses Turkish phrases when languageCode is tr', () async {
      const start = LatLng(41.0, 29.0);
      final corner = _offsetMeters(start, 600, 0);
      final end = _offsetMeters(corner, 0, 600); // left turn (north)
      final polyline = [start, corner, end];

      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      final nav = TtsNavigator(
        tts: tts,
        polyline: polyline,
        avoidedCells: const [],
        languageCode: 'tr',
      );
      await nav.start(controller.stream);

      controller.add(_offsetMeters(start, 400, 0));
      await Future<void>.delayed(Duration.zero);

      expect(tts.language, 'tr-TR');
      expect(
        tts.spoken.any((s) => s.contains('sola')),
        isTrue,
        reason: 'expected Turkish left cue, got: ${tts.spoken}',
      );

      await nav.dispose();
      await controller.close();
    });
  });

  group('TtsNavigator risk warnings', () {
    test('announces risk warning when within 150 m of an avoided cell',
        () async {
      const cellCenter = LatLng(41.005, 29.005);
      final geohash = Geohash.encode(cellCenter.latitude, cellCenter.longitude);
      final b = Geohash.bounds(geohash);
      final centroid = LatLng((b.minLat + b.maxLat) / 2,
          (b.minLng + b.maxLng) / 2);

      // Polyline: irrelevant straight line far away from cell.
      final polyline = [
        const LatLng(40.9, 28.9),
        const LatLng(40.91, 28.91),
      ];

      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      final nav = TtsNavigator(
        tts: tts,
        polyline: polyline,
        avoidedCells: [geohash],
        languageCode: 'en',
      );
      await nav.start(controller.stream);

      // 50 m east of centroid.
      controller.add(_offsetMeters(centroid, 50, 0));
      await Future<void>.delayed(Duration.zero);

      expect(
        tts.spoken,
        contains('Approaching a high-risk area'),
      );

      await nav.dispose();
      await controller.close();
    });

    test('respects 60 s cooldown for risk warnings on same cell', () async {
      const cellCenter = LatLng(41.005, 29.005);
      final geohash = Geohash.encode(cellCenter.latitude, cellCenter.longitude);
      final b = Geohash.bounds(geohash);
      final centroid = LatLng((b.minLat + b.maxLat) / 2,
          (b.minLng + b.maxLng) / 2);

      final polyline = [
        const LatLng(40.9, 28.9),
        const LatLng(40.91, 28.91),
      ];

      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      var fakeTime = DateTime(2024, 1, 1, 12);
      final nav = TtsNavigator(
        tts: tts,
        polyline: polyline,
        avoidedCells: [geohash],
        languageCode: 'en',
        now: () => fakeTime,
      );
      await nav.start(controller.stream);

      controller.add(_offsetMeters(centroid, 50, 0));
      await Future<void>.delayed(Duration.zero);

      fakeTime = fakeTime.add(const Duration(seconds: 10));
      controller.add(_offsetMeters(centroid, 40, 0));
      await Future<void>.delayed(Duration.zero);

      final warnings = tts.spoken
          .where((s) => s == 'Approaching a high-risk area')
          .toList();
      expect(warnings.length, 1,
          reason: 'expected one warning within cooldown, got $warnings');

      await nav.dispose();
      await controller.close();
    });
  });

  group('TtsNavigator lifecycle', () {
    test('dispose cancels subscription and stops TTS', () async {
      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      final nav = TtsNavigator(
        tts: tts,
        polyline: const [LatLng(41.0, 29.0), LatLng(41.001, 29.001)],
        avoidedCells: const [],
        languageCode: 'en',
      );
      await nav.start(controller.stream);

      await nav.dispose();

      expect(controller.hasListener, isFalse);
      // setLanguage called once on start, plus stop on dispose.
      expect(tts.stopCount, greaterThanOrEqualTo(1));

      await controller.close();
    });

    test('mute prevents announcements', () async {
      const start = LatLng(41.0, 29.0);
      final corner = _offsetMeters(start, 600, 0);
      final end = _offsetMeters(corner, 0, -600);
      final polyline = [start, corner, end];

      final tts = FakeFlutterTts();
      final controller = StreamController<LatLng>();
      final nav = TtsNavigator(
        tts: tts,
        polyline: polyline,
        avoidedCells: const [],
        languageCode: 'en',
      );
      await nav.start(controller.stream);
      nav.mute();

      controller.add(_offsetMeters(start, 400, 0));
      await Future<void>.delayed(Duration.zero);

      expect(tts.spoken, isEmpty);

      await nav.dispose();
      await controller.close();
    });
  });
}
