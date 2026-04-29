// Lightweight place-search wrapper around the Nominatim (OpenStreetMap)
// public API. We deliberately avoid the `http` / `geocoding` packages so the
// hackathon demo doesn't have to touch pubspec — the existing
// `dart:io HttpClient` pattern from `lib/ai/model_storage.dart` is more than
// enough for a typeahead that fires once every 300 ms.
//
// Nominatim ToS:
//   * 1 req/sec/IP — easy to respect with the 300 ms debounce in the UI
//   * a meaningful, contactable User-Agent header is REQUIRED
//   * no aggressive bulk usage — we cap `limit` at 5 by default and cache
//     identical queries in-memory so a user typing the same word twice
//     doesn't double-charge the public service.
//
// Network errors and rate-limit responses (HTTP 429 / 503) silently fall
// back to an empty list. The caller (`PlaceSearchField`) is responsible for
// surfacing a hint to the user — the service itself never throws so the UI
// stays simple.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One search hit returned by Nominatim, narrowed down to the fields the UI
/// actually consumes.
@immutable
class PlaceSearchResult {
  const PlaceSearchResult({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.type,
  });

  /// e.g. `"Beşiktaş İskelesi, Beşiktaş, İstanbul"`. Already localised when
  /// `accept-language=tr` is sent on the request.
  final String displayName;

  final double lat;
  final double lng;

  /// Nominatim's classification — `"amenity"`, `"place"`, `"tourism"`,
  /// `"highway"`, etc. Used by the UI to pick a leading icon.
  final String? type;

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    return PlaceSearchResult(
      displayName: (json['display_name'] as String?) ?? '',
      lat: _parseDouble(json['lat']) ?? 0.0,
      lng: _parseDouble(json['lon']) ?? 0.0,
      type: json['type'] as String?,
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

  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';

  /// Nominatim's terms require a real, contactable User-Agent. Hackathon
  /// contact is intentionally generic — replace before any production use.
  static const String _userAgent =
      'SafeRoute/1.0 (Hackathon Demo; saferoute@example.com)';

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
    int limit = 5,
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
      if (decoded is! List) return const [];

      final results = <PlaceSearchResult>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          final hit = PlaceSearchResult.fromJson(entry);
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
      'format': 'json',
      'limit': '$limit',
      'accept-language': 'tr',
      'addressdetails': '0',
    };

    final hasFullViewbox = viewboxMinLng != null &&
        viewboxMinLat != null &&
        viewboxMaxLng != null &&
        viewboxMaxLat != null;
    if (hasFullViewbox) {
      // Nominatim viewbox order: minLng,minLat,maxLng,maxLat (lon-lat pairs).
      params['viewbox'] =
          '$viewboxMinLng,$viewboxMinLat,$viewboxMaxLng,$viewboxMaxLat';
      // We intentionally don't send `bounded=1` — biasing yes, hard fence no.
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
