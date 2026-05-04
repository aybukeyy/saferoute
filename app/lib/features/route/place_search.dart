// Lightweight place-search wrapper around the Photon (komoot / OSM) public
// API. Photon is purpose-built for typeahead — supports prefix matching,
// returns ranked GeoJSON, and is much more permissive than Nominatim's free
// instance (which has been returning 403 for our hackathon traffic).
//
// We avoid the `http` / `geocoding` packages on purpose so pubspec doesn't
// need to grow — the `dart:io HttpClient` pattern is more than enough for a
// typeahead that fires once every 300 ms.
//
// Network errors and non-2xx responses silently fall back to an empty list.
// The caller (`PlaceSearchField`) is responsible for surfacing a hint to the
// user — the service itself never throws so the UI stays simple.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One search hit returned by Photon, narrowed down to the fields the UI
/// actually consumes.
@immutable
class PlaceSearchResult {
  const PlaceSearchResult({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.type,
  });

  /// e.g. `"Marmara Park, Beylikdüzü, İstanbul"`. Built by joining the most
  /// relevant Photon `properties` fields.
  final String displayName;

  final double lat;
  final double lng;

  /// Photon's `osm_value` (or `osm_key`) — `"supermarket"`, `"tourism"`,
  /// `"residential"`, etc. Drives the leading icon choice.
  final String? type;

  /// Parses one entry from a Photon `features` list. Photon emits a GeoJSON
  /// FeatureCollection — `geometry.coordinates` is `[lng, lat]`.
  factory PlaceSearchResult.fromPhotonFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List?;
    final lng = (coords != null && coords.length >= 2)
        ? _parseDouble(coords[0]) ?? 0.0
        : 0.0;
    final lat = (coords != null && coords.length >= 2)
        ? _parseDouble(coords[1]) ?? 0.0
        : 0.0;

    final props = (feature['properties'] as Map<String, dynamic>?) ?? const {};
    final name = props['name'] as String?;
    final street = props['street'] as String?;
    final houseNumber = props['housenumber'] as String?;
    final city = props['city'] as String?;
    final district = (props['district'] ?? props['locality']) as String?;
    final state = props['state'] as String?;
    final country = props['country'] as String?;

    final segments = <String>[
      if (name != null && name.isNotEmpty) name,
      if (street != null && street.isNotEmpty)
        houseNumber != null && houseNumber.isNotEmpty
            ? '$street $houseNumber'
            : street,
      if (district != null && district.isNotEmpty) district,
      if (city != null && city.isNotEmpty) city,
      if (state != null && state.isNotEmpty && state != city) state,
      if (country != null && country.isNotEmpty) country,
    ];

    final display = segments.toSet().toList().join(', ');

    return PlaceSearchResult(
      displayName: display,
      lat: lat,
      lng: lng,
      type: (props['osm_value'] ?? props['osm_key']) as String?,
    );
  }

  static double? _parseDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlaceSearchResult &&
      other.displayName == displayName &&
      other.lat == lat &&
      other.lng == lng &&
      other.type == type;

  @override
  int get hashCode => Object.hash(displayName, lat, lng, type);
}

/// Minimal Nominatim wrapper. Stateless apart from a tiny LRU-ish cache —
/// safe to construct once at app boot and share across screens.
class PlaceSearchService {
  PlaceSearchService({HttpClient Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  // -------------------------------------------------------------------------
  // Constants
  // -------------------------------------------------------------------------

  static const String _baseUrl = 'https://photon.komoot.io/api/';

  /// Photon doesn't strictly require a User-Agent but adding one keeps us
  /// polite and identifies the demo if anyone looks at access logs.
  static const String _userAgent =
      'SafeRoute/1.0 (+https://github.com/aybukeyy/saferoute)';

  /// Hard cap on the in-memory cache so a user spamming the search field
  /// can't grow it without bound.
  static const int _maxCacheEntries = 64;

  static const Duration _timeout = Duration(seconds: 5);

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  final HttpClient Function() _httpClientFactory;

  /// `query|bias` -> result list. Populated lazily; oldest entries evicted
  /// when the map grows past [_maxCacheEntries].
  final Map<String, List<PlaceSearchResult>> _cache = {};

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Performs a Nominatim `/search` request. The optional `viewbox*` args
  /// bias results toward a region without strictly excluding hits outside it
  /// — perfect for "prefer Beşiktaş, but show Kadıköy if the user types it".
  ///
  /// Returns an empty list (never throws) on network/parse/rate-limit errors;
  /// the UI treats that as "no suggestions" which already matches the empty
  /// dropdown state.
  Future<List<PlaceSearchResult>> search({
    required String query,
    int limit = 10,
    double? viewboxMinLng,
    double? viewboxMinLat,
    double? viewboxMaxLng,
    double? viewboxMaxLat,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final cacheKey = _cacheKey(
      trimmed,
      limit,
      viewboxMinLng,
      viewboxMinLat,
      viewboxMaxLng,
      viewboxMaxLat,
    );
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final uri = _buildUri(
      query: trimmed,
      limit: limit,
      viewboxMinLng: viewboxMinLng,
      viewboxMinLat: viewboxMinLat,
      viewboxMaxLng: viewboxMaxLng,
      viewboxMaxLat: viewboxMaxLat,
    );

    HttpClient? client;
    try {
      client = _httpClientFactory();
      client.connectionTimeout = _timeout;

      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        // Drain so the socket can be recycled / closed cleanly.
        await response.drain<void>();
        debugPrint(
          '[PlaceSearch] HTTP ${response.statusCode} for "$trimmed"',
        );
        return const [];
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final features = decoded['features'];
      if (features is! List) return const [];

      final results = <PlaceSearchResult>[];
      for (final entry in features) {
        if (entry is Map<String, dynamic>) {
          final hit = PlaceSearchResult.fromPhotonFeature(entry);
          if (hit.displayName.isNotEmpty) {
            results.add(hit);
          }
        }
      }

      _putCache(cacheKey, results);
      return results;
    } on TimeoutException catch (e) {
      debugPrint('[PlaceSearch] timeout for "$trimmed": $e');
      return const [];
    } catch (e, st) {
      debugPrint('[PlaceSearch] failed for "$trimmed": $e\n$st');
      return const [];
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  Uri _buildUri({
    required String query,
    required int limit,
    double? viewboxMinLng,
    double? viewboxMinLat,
    double? viewboxMaxLng,
    double? viewboxMaxLat,
  }) {
    final params = <String, String>{
      'q': query,
      'limit': '$limit',
      // Photon only supports {en, fr, de, it} — Turkish would return HTTP 400.
      // Place names in Turkey come back in their native form regardless.
    };

    // Photon biases by a single (lat, lon) point rather than a rectangle. We
    // derive that point from the bbox centroid so the existing call sites
    // (which pass a Beşiktaş/Istanbul rectangle) stay unchanged.
    final hasFullViewbox = viewboxMinLng != null &&
        viewboxMinLat != null &&
        viewboxMaxLng != null &&
        viewboxMaxLat != null;
    if (hasFullViewbox) {
      final centroidLng = (viewboxMinLng + viewboxMaxLng) / 2;
      final centroidLat = (viewboxMinLat + viewboxMaxLat) / 2;
      params['lat'] = '$centroidLat';
      params['lon'] = '$centroidLng';
    }

    return Uri.parse(_baseUrl).replace(queryParameters: params);
  }

  String _cacheKey(
    String query,
    int limit,
    double? minLng,
    double? minLat,
    double? maxLng,
    double? maxLat,
  ) {
    final lower = query.toLowerCase();
    return '$lower|$limit|$minLng,$minLat,$maxLng,$maxLat';
  }

  void _putCache(String key, List<PlaceSearchResult> value) {
    if (_cache.length >= _maxCacheEntries) {
      // Drop the oldest insertion — `Map`'s iteration order is preserved.
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
    }
    _cache[key] = value;
  }

  @visibleForTesting
  int get cacheSize => _cache.length;
}

/// App-wide singleton. Light enough to construct once and share — caches per
/// instance so the same query typed on different screens still hits memory.
final placeSearchServiceProvider =
    Provider<PlaceSearchService>((ref) => PlaceSearchService());
