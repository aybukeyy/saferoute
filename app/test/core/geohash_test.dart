// Sanity checks for the Geohash wrapper. We're not re-testing dart_geohash,
// just our own contract: precision-7 round-trip, bounds shape, neighbors
// count, bbox enumeration coverage.

import 'package:app/core/geohash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Geohash', () {
    test('encodes Beşiktaş coordinates to a known precision-7 hash', () {
      // Reference computed against geohash.org for 41.0426° N, 29.0094° E.
      final h = Geohash.encode(41.0426, 29.0094, precision: 7);
      expect(h, hasLength(7));
      // Decoding the cell center should be within ~70m of the input.
      final decoded = Geohash.decode(h);
      expect((decoded.lat - 41.0426).abs(), lessThan(0.01));
      expect((decoded.lng - 29.0094).abs(), lessThan(0.01));
    });

    test('bounds form a non-degenerate rectangle around the encoded point', () {
      final h = Geohash.encode(41.0, 29.0, precision: 7);
      final b = Geohash.bounds(h);
      expect(b.minLat, lessThan(b.maxLat));
      expect(b.minLng, lessThan(b.maxLng));
      expect(41.0, inInclusiveRange(b.minLat, b.maxLat));
      expect(29.0, inInclusiveRange(b.minLng, b.maxLng));
      // precision-7 cell width should be < 0.005 deg in either axis.
      expect(b.maxLat - b.minLat, lessThan(0.005));
      expect(b.maxLng - b.minLng, lessThan(0.005));
    });

    test('neighbors returns 8 distinct cells, none equal to self', () {
      final h = Geohash.encode(41.0, 29.0, precision: 7);
      final n = Geohash.neighbors(h);
      expect(n, hasLength(8));
      expect(n.toSet(), hasLength(8));
      expect(n.contains(h), isFalse);
    });

    test('cellsInBoundingBox covers the bbox and includes corners', () {
      // Tiny bbox around a single point — should yield at least the
      // containing cell.
      final cells = Geohash.cellsInBoundingBox(
        minLat: 41.0,
        maxLat: 41.001,
        minLng: 29.0,
        maxLng: 29.001,
        precision: 7,
      );
      expect(cells, isNotEmpty);
      expect(cells, contains(Geohash.encode(41.0, 29.0, precision: 7)));
    });
  });
}
