import 'package:app/data/route_share_service.dart';
import 'package:app/models/route_share.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RouteShare model', () {
    test('toMap/fromMap roundtrip preserves every field', () {
      final at = DateTime.utc(2026, 5, 2, 10, 30);
      final share = RouteShare(
        id: 'abc123',
        ownerUid: 'uid-1',
        from: const LatLng(41.041, 29.001),
        to: const LatLng(41.075, 29.040),
        safestPath: const [
          LatLng(41.041, 29.001),
          LatLng(41.060, 29.020),
          LatLng(41.075, 29.040),
        ],
        startedAt: at,
        etaMinutes: 25,
        currentPosition: const LatLng(41.060, 29.020),
        updatedAt: at,
        expiresAt: at.add(const Duration(hours: 1)),
        message: 'Eve dönüyorum, 25 dk.',
      );
      final m = share.toMap();
      // Firestore stores latlng as a sub-map, not a String — make sure we
      // didn't accidentally serialize it as a stringified pair.
      expect(m['from'], isA<Map<String, dynamic>>());
      expect((m['from'] as Map)['lat'], 41.041);
      // Timestamps survive the trip.
      expect(m['startedAt'], isA<Timestamp>());

      final back = RouteShare.fromMap('abc123', m);
      expect(back.ownerUid, share.ownerUid);
      expect(back.from.latitude, share.from.latitude);
      expect(back.to.longitude, share.to.longitude);
      expect(back.safestPath.length, share.safestPath.length);
      expect(back.etaMinutes, 25);
      expect(back.currentPosition.latitude, 41.060);
      expect(back.message, 'Eve dönüyorum, 25 dk.');
      expect(back.ended, false);
      // Timestamp.toDate() returns local time, so compare moments not equality
      // (the absolute instant matches; only the TZ flag differs).
      expect(back.expiresAt.isAtSameMomentAs(share.expiresAt), isTrue);
      expect(back.startedAt.isAtSameMomentAs(share.startedAt), isTrue);
    });

    test('isExpired flips after expiresAt', () {
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      final share = RouteShare(
        id: 'x',
        ownerUid: 'u',
        from: const LatLng(0, 0),
        to: const LatLng(0, 0),
        safestPath: const [],
        startedAt: past.subtract(const Duration(hours: 1)),
        etaMinutes: 0,
        currentPosition: const LatLng(0, 0),
        updatedAt: past,
        expiresAt: past,
      );
      expect(share.isExpired, isTrue);
      expect(share.isActive, isFalse);
    });
  });

  group('RouteShareService.disabled()', () {
    final svc = RouteShareService.disabled();

    test('isEnabled false', () {
      expect(svc.isEnabled, isFalse);
    });

    test('create returns null', () async {
      final r = await svc.create(
        ownerUid: 'u',
        from: const LatLng(0, 0),
        to: const LatLng(0, 0),
        safestPath: const [],
        etaMinutes: 0,
        startPosition: const LatLng(0, 0),
      );
      expect(r, isNull);
    });

    test('updatePosition / end no-op without throwing', () async {
      await svc.updatePosition(
          shareId: 'whatever', position: const LatLng(0, 0));
      await svc.end('whatever');
    });

    test('watch emits null', () async {
      final v = await svc.watch('whatever').first;
      expect(v, isNull);
    });

    test('get returns null', () async {
      final v = await svc.get('whatever');
      expect(v, isNull);
    });
  });
}
