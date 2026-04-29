// Geohash-7 helpers (encode/decode/bounds/neighbors). Wraps `dart_geohash`
// for the heavy lifting (encode/decode/neighbor traversal) and adds the
// missing `bounds` + bounding-box-to-cell-set utilities the Risk Engine and
// heatmap painter need. Risk grid precision is locked at 7 (~150m × 150m
// cells; see ARCHITECTURE.md §2.3).

import 'package:dart_geohash/dart_geohash.dart' as dg;

/// A simple immutable lat/lng pair with no Flutter dependency. Routing and
/// LocationService use the `latlong2` LatLng directly; this internal record
/// is only what `Geohash` returns to keep `core/` Flutter-free.
typedef LatLngRecord = ({double lat, double lng});

/// A geohash cell's geographic bounding box in degrees.
typedef GeohashBounds = ({
  double minLat,
  double maxLat,
  double minLng,
  double maxLng,
});

/// Stateless utility around `dart_geohash`. All methods are deterministic
/// and side-effect-free, so they can be called from any isolate.
class Geohash {
  Geohash._();

  static final dg.GeoHasher _hasher = dg.GeoHasher();

  /// Encodes a [lat]/[lng] coordinate to a base-32 geohash. Default
  /// [precision] of 7 matches the locked risk-cell grid.
  ///
  /// Throws [RangeError] if the coordinates are outside WGS-84 bounds.
  static String encode(double lat, double lng, {int precision = 7}) {
    return _hasher.encode(lng, lat, precision: precision);
  }

  /// Decodes a [geohash] back to its center lat/lng. Note that geohash decode
  /// is lossy — precision-7 has roughly ±70 m horizontal error.
  static LatLngRecord decode(String geohash) {
    final lngLat = _hasher.decode(geohash);
    return (lat: lngLat[1], lng: lngLat[0]);
  }

  /// Returns the rectangular geographic bounds of a geohash cell. Computed
  /// by interleaving lat/lng bits from the geohash characters using the
  /// canonical base-32 alphabet `0123456789bcdefghjkmnpqrstuvwxyz`.
  static GeohashBounds bounds(String geohash) {
    if (geohash.isEmpty) {
      throw ArgumentError.value(geohash, 'geohash', 'cannot be empty');
    }
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

    double minLat = -90.0, maxLat = 90.0;
    double minLng = -180.0, maxLng = 180.0;
    bool isLng = true;

    for (final ch in geohash.toLowerCase().split('')) {
      final idx = base32.indexOf(ch);
      if (idx < 0) {
        throw ArgumentError.value(
          geohash,
          'geohash',
          'invalid character "$ch"',
        );
      }
      // Each character contributes 5 bits, msb first.
      for (int bitPos = 4; bitPos >= 0; bitPos--) {
        final bit = (idx >> bitPos) & 1;
        if (isLng) {
          final mid = (minLng + maxLng) / 2.0;
          if (bit == 1) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2.0;
          if (bit == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isLng = !isLng;
      }
    }

    return (
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  /// Returns the eight neighbors of [geohash] (N, NE, E, SE, S, SW, W, NW)
  /// in clockwise order starting from north. Self is *not* included.
  static List<String> neighbors(String geohash) {
    final n = _hasher.neighbors(geohash);
    return [
      n[dg.Direction.NORTH.name]!,
      n[dg.Direction.NORTHEAST.name]!,
      n[dg.Direction.EAST.name]!,
      n[dg.Direction.SOUTHEAST.name]!,
      n[dg.Direction.SOUTH.name]!,
      n[dg.Direction.SOUTHWEST.name]!,
      n[dg.Direction.WEST.name]!,
      n[dg.Direction.NORTHWEST.name]!,
    ];
  }

  /// Enumerates every geohash cell at the given [precision] that falls
  /// inside (or overlaps) the [minLat]/[maxLat]/[minLng]/[maxLng] bounding
  /// box. Used by the heatmap painter and Firestore range listener.
  ///
  /// Implementation walks the cell grid by stepping from the SW corner cell
  /// to the NE corner cell using cell width derived from `bounds()` of the
  /// SW corner. Safer than naïve geohash arithmetic, and at precision 7 the
  /// counts stay small (a 1 km² box yields ~50 cells).
  ///
  /// The bbox crosses neither the antimeridian nor the poles in our demo
  /// region, so we don't handle longitude wrap-around.
  static List<String> cellsInBoundingBox({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int precision = 7,
  }) {
    if (minLat > maxLat || minLng > maxLng) {
      throw ArgumentError('Inverted bounding box');
    }
    final result = <String>{};

    // Start at the SW corner cell.
    final swHash = encode(minLat, minLng, precision: precision);
    final swBounds = bounds(swHash);
    final cellHeight = swBounds.maxLat - swBounds.minLat;
    final cellWidth = swBounds.maxLng - swBounds.minLng;

    if (cellHeight <= 0 || cellWidth <= 0) {
      // Degenerate — fall back to a single cell.
      return [swHash];
    }

    // Step a half-cell beyond max so that boundary touches are included.
    for (double lat = swBounds.minLat + cellHeight / 2;
        lat <= maxLat + cellHeight / 2;
        lat += cellHeight) {
      for (double lng = swBounds.minLng + cellWidth / 2;
          lng <= maxLng + cellWidth / 2;
          lng += cellWidth) {
        // Clamp to legal WGS-84 to avoid the encoder throwing.
        final clampedLat = lat.clamp(-90.0, 90.0);
        final clampedLng = lng.clamp(-180.0, 180.0);
        result.add(encode(clampedLat, clampedLng, precision: precision));
      }
    }

    return result.toList(growable: false);
  }
}
