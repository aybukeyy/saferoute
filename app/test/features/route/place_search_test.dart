// Unit tests for `PlaceSearchService`. We follow the pattern from
// `test/ai/model_storage_test.dart`: spin up a real local `HttpServer`,
// point the service at it via the `httpClientFactory` seam, and assert
// against parsed `PlaceSearchResult`s.
//
// Covered:
//   * happy-path JSON parse against a Nominatim-shaped fixture
//   * empty / too-short query short-circuits before any network call
//   * non-200 responses fall back to an empty list (no throw)
//   * connection errors fall back to an empty list (no throw)
//   * identical queries hit the in-memory cache instead of the network

import 'dart:convert';
import 'dart:io';

import 'package:app/features/route/place_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceSearchResult.fromJson', () {
    test('parses a full Nominatim hit', () {
      final json = {
        'display_name': 'Beşiktaş İskelesi, Beşiktaş, İstanbul',
        'lat': '41.0419',
        'lon': '29.0072',
        'type': 'amenity',
      };
      final hit = PlaceSearchResult.fromJson(json);
      expect(hit.displayName, contains('Beşiktaş'));
      expect(hit.lat, closeTo(41.0419, 1e-6));
      expect(hit.lng, closeTo(29.0072, 1e-6));
      expect(hit.type, 'amenity');
    });

    test('accepts numeric lat/lon (some Nominatim mirrors)', () {
      final hit = PlaceSearchResult.fromJson({
        'display_name': 'X',
        'lat': 41.0,
        'lon': 29.0,
      });
      expect(hit.lat, 41.0);
      expect(hit.lng, 29.0);
      expect(hit.type, isNull);
    });

    test('falls back to defaults on missing fields', () {
      final hit = PlaceSearchResult.fromJson(<String, dynamic>{});
      expect(hit.displayName, isEmpty);
      expect(hit.lat, 0.0);
      expect(hit.lng, 0.0);
    });
  });

  group('PlaceSearchService.search', () {
    late HttpServer server;
    late int requestCount;
    late List<Uri> seenUris;

    setUp(() async {
      requestCount = 0;
      seenUris = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        requestCount += 1;
        seenUris.add(req.uri);
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.write(_kSampleNominatimJson);
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    PlaceSearchService buildService() {
      // Override the base URL by overriding the HttpClient's "find proxy"
      // — easier in this codebase: route via a custom HttpClient that
      // redirects every getUrl to our local server. We can't change the
      // base URL easily without exposing it, so we monkey-patch via a
      // small subclass that rewrites the host/port.
      return PlaceSearchService(
        httpClientFactory: () => _RewritingHttpClient(server.port),
      );
    }

    test('parses a JSON list into PlaceSearchResults', () async {
      final service = buildService();
      final results = await service.search(query: 'Beşiktaş İskele');

      expect(results, hasLength(2));
      expect(results.first.displayName, contains('Beşiktaş İskelesi'));
      expect(results.first.lat, closeTo(41.0419, 1e-4));
      expect(results.first.lng, closeTo(29.0072, 1e-4));
      expect(requestCount, 1);
    });

    test('skips network call when query is shorter than 3 characters',
        () async {
      final service = buildService();
      expect(await service.search(query: ''), isEmpty);
      expect(await service.search(query: '  '), isEmpty);
      expect(await service.search(query: 'ab'), isEmpty);
      expect(requestCount, 0);
    });

    test('caches identical queries (no second network hit)', () async {
      final service = buildService();
      final first = await service.search(query: 'Beşiktaş');
      final second = await service.search(query: 'Beşiktaş');
      expect(first, equals(second));
      expect(requestCount, 1);
      expect(service.cacheSize, 1);
    });

    test('forwards bias as a viewbox query param', () async {
      final service = buildService();
      await service.search(
        query: 'iskele',
        viewboxMinLng: 28.985,
        viewboxMinLat: 41.040,
        viewboxMaxLng: 29.045,
        viewboxMaxLat: 41.080,
      );
      expect(seenUris, isNotEmpty);
      final params = seenUris.last.queryParameters;
      expect(params['q'], 'iskele');
      expect(params['format'], 'json');
      expect(params['accept-language'], 'tr');
      expect(params['viewbox'], '28.985,41.04,29.045,41.08');
      // Bias only — never bounded.
      expect(params.containsKey('bounded'), isFalse);
    });
  });

  group('PlaceSearchService failure modes', () {
    test('returns empty list on non-200 response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = HttpStatus.serviceUnavailable;
        await req.response.close();
      });
      addTearDown(() async => server.close(force: true));

      final service = PlaceSearchService(
        httpClientFactory: () => _RewritingHttpClient(server.port),
      );
      expect(await service.search(query: 'beşiktaş'), isEmpty);
    });

    test('returns empty list when the server is unreachable', () async {
      // Bind, then immediately close, so the chosen port is dead.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = server.port;
      await server.close(force: true);

      final service = PlaceSearchService(
        httpClientFactory: () => _RewritingHttpClient(deadPort),
      );
      expect(await service.search(query: 'beşiktaş'), isEmpty);
    });
  });
}

/// HttpClient that rewrites every outgoing request's host + port to point
/// at our in-process test server. This lets us exercise the real
/// `dart:io HttpClient` codepath in [PlaceSearchService] without needing a
/// public seam for the base URL.
class _RewritingHttpClient implements HttpClient {
  _RewritingHttpClient(this._port) : _inner = HttpClient();

  final int _port;
  final HttpClient _inner;

  Uri _rewrite(Uri uri) =>
      uri.replace(scheme: 'http', host: '127.0.0.1', port: _port);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _inner.getUrl(_rewrite(url));

  // ---- Everything below just delegates to the wrapped client. -------------

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) =>
      _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)?
              callback) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(
                  Uri url, String? proxyHost, int? proxyPort)?
              f) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _inner.delete(host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _inner.deleteUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _inner.get(host, port, path);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _inner.head(host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _inner.headUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      _inner.open(method, host, port, path);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _inner.openUrl(method, _rewrite(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _inner.patch(host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _inner.patchUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _inner.post(host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _inner.postUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _inner.put(host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _inner.putUrl(_rewrite(url));
}

const String _kSampleNominatimJson = '''
[
  {
    "place_id": 1,
    "display_name": "Beşiktaş İskelesi, Beşiktaş, İstanbul, Türkiye",
    "lat": "41.0419",
    "lon": "29.0072",
    "type": "amenity",
    "class": "amenity"
  },
  {
    "place_id": 2,
    "display_name": "Beşiktaş, İstanbul, Türkiye",
    "lat": "41.0432",
    "lon": "29.0055",
    "type": "place",
    "class": "boundary"
  }
]
''';

/// Suppresses the analyzer's unused-import warning when we strip JSON in
/// other test variants. Cheap to keep — `jsonDecode` lives here on purpose.
// ignore: unused_element
void _silenceUnused() {
  jsonDecode('[]');
}
