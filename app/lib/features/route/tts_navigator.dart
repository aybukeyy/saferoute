import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geohash.dart';

abstract class TtsEngine {
  Future<void> setLanguage(String language);
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;

  @override
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

const Map<String, Map<String, String>> _kPhrases = {
  'tr': {
    'right_200': '200 metre sonra sağa',
    'right_100': '100 metre sonra sağa',
    'right_50': '50 metre sonra sağa',
    'left_200': '200 metre sonra sola',
    'left_100': '100 metre sonra sola',
    'left_50': '50 metre sonra sola',
    'straight_200': '200 metre sonra düz devam edin',
    'straight_100': '100 metre sonra düz devam edin',
    'straight_50': '50 metre sonra düz devam edin',
    'risk': 'Yüksek riskli bölgeye yaklaşıyorsunuz',
  },
  'en': {
    'right_200': 'Turn right in 200 meters',
    'right_100': 'Turn right in 100 meters',
    'right_50': 'Turn right in 50 meters',
    'left_200': 'Turn left in 200 meters',
    'left_100': 'Turn left in 100 meters',
    'left_50': 'Turn left in 50 meters',
    'straight_200': 'Continue straight in 200 meters',
    'straight_100': 'Continue straight in 100 meters',
    'straight_50': 'Continue straight in 50 meters',
    'risk': 'Approaching a high-risk area',
  },
};

class TtsNavigator {
  TtsNavigator({
    required TtsEngine tts,
    required this.polyline,
    required this.avoidedCells,
    required this.languageCode,
    DateTime Function()? now,
  })  : _tts = tts,
        _now = now ?? DateTime.now {
    _segLengths = _computeSegLengths(polyline);
    _cellCenters = avoidedCells.map((g) {
      final b = Geohash.bounds(g);
      return LatLng((b.minLat + b.maxLat) / 2, (b.minLng + b.maxLng) / 2);
    }).toList(growable: false);
  }

  final TtsEngine _tts;
  final List<LatLng> polyline;
  final List<String> avoidedCells;
  final String languageCode;
  final DateTime Function() _now;

  late final List<double> _segLengths;
  late final List<LatLng> _cellCenters;

  StreamSubscription<LatLng>? _sub;
  bool _muted = false;
  bool _disposed = false;
  DateTime? _lastAnnounceAt;
  int _lastAnnouncedTurnVertex = -1;
  final Map<int, DateTime> _lastRiskWarnByCell = {};

  Future<void> start(Stream<LatLng> positionStream) async {
    final lang = _resolveLanguage(languageCode);
    await _tts.setLanguage(lang);
    _sub = positionStream.listen(_onPosition);
  }

  void mute() {
    _muted = true;
    _tts.stop();
  }

  void unmute() {
    _muted = false;
  }

  bool get isMuted => _muted;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await _tts.stop();
  }

  Future<void> _onPosition(LatLng pos) async {
    if (_disposed || _muted) return;
    final phrases = _kPhrases[languageCode == 'tr' ? 'tr' : 'en']!;

    if (_cellCenters.isNotEmpty) {
      for (var i = 0; i < _cellCenters.length; i++) {
        final d = _haversine(pos, _cellCenters[i]);
        if (d <= 150) {
          final last = _lastRiskWarnByCell[i];
          final t = _now();
          if (last == null || t.difference(last).inSeconds >= 60) {
            if (_canAnnounce(t)) {
              _lastRiskWarnByCell[i] = t;
              await _announce(phrases['risk']!, t);
              return;
            }
          }
        }
      }
    }

    if (polyline.length < 2) return;
    final nearest = _nearestSegment(pos);
    if (nearest == null) return;

    final ahead = _lookAhead(pos, nearest, 200);
    if (ahead == null) return;

    if (ahead.turnVertex <= _lastAnnouncedTurnVertex) return;

    final dir = _direction(ahead.bearingChangeDeg);
    final bucket = _distanceBucket(ahead.distanceM);
    if (bucket == null) return;

    final t = _now();
    if (!_canAnnounce(t)) return;

    final key = '${dir}_$bucket';
    final phrase = phrases[key];
    if (phrase == null) return;

    _lastAnnouncedTurnVertex = ahead.turnVertex;
    await _announce(phrase, t);
  }

  bool _canAnnounce(DateTime t) {
    final last = _lastAnnounceAt;
    if (last == null) return true;
    return t.difference(last).inMilliseconds >= 3000;
  }

  Future<void> _announce(String text, DateTime t) async {
    _lastAnnounceAt = t;
    await _tts.speak(text);
  }

  String _direction(double deg) {
    if (deg > 30) return 'right';
    if (deg < -30) return 'left';
    return 'straight';
  }

  int? _distanceBucket(double meters) {
    if (meters <= 60) return 50;
    if (meters <= 130) return 100;
    if (meters <= 230) return 200;
    return null;
  }

  static String _resolveLanguage(String code) {
    return code == 'tr' ? 'tr-TR' : 'en-US';
  }

  static List<double> _computeSegLengths(List<LatLng> path) {
    final out = <double>[];
    for (var i = 0; i + 1 < path.length; i++) {
      out.add(_haversine(path[i], path[i + 1]));
    }
    return out;
  }

  _NearestSeg? _nearestSegment(LatLng pos) {
    if (polyline.length < 2) return null;
    var bestIdx = 0;
    var bestDist = double.infinity;
    var bestT = 0.0;
    for (var i = 0; i + 1 < polyline.length; i++) {
      final r = _projectOnSegment(pos, polyline[i], polyline[i + 1]);
      if (r.distance < bestDist) {
        bestDist = r.distance;
        bestIdx = i;
        bestT = r.t;
      }
    }
    return _NearestSeg(index: bestIdx, t: bestT, distanceM: bestDist);
  }

  _LookAhead? _lookAhead(LatLng pos, _NearestSeg seg, double aheadMeters) {
    final segLen = _segLengths[seg.index];
    var remainOnSeg = segLen * (1 - seg.t);
    var idx = seg.index;

    while (remainOnSeg < aheadMeters && idx + 1 < _segLengths.length) {
      idx += 1;
      remainOnSeg += _segLengths[idx];
    }

    final turnVertex = idx + 1;
    if (turnVertex >= polyline.length - 0) {
      // Would index past end; fallthrough to compute bearing if possible.
    }

    if (idx + 1 >= polyline.length) return null;

    double currentBearing;
    if (idx == seg.index) {
      currentBearing = _bearing(pos, polyline[idx + 1]);
    } else {
      currentBearing = _bearing(polyline[idx], polyline[idx + 1]);
    }

    if (idx + 2 >= polyline.length) {
      return _LookAhead(
        turnVertex: turnVertex,
        distanceM: remainOnSeg,
        bearingChangeDeg: 0,
      );
    }

    final nextBearing = _bearing(polyline[idx + 1], polyline[idx + 2]);
    final delta = _normalizeBearingDelta(nextBearing - currentBearing);

    return _LookAhead(
      turnVertex: turnVertex,
      distanceM: remainOnSeg,
      bearingChangeDeg: delta,
    );
  }

  static double _normalizeBearingDelta(double deg) {
    var d = deg;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  static double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final br = math.atan2(y, x) * 180.0 / math.pi;
    return (br + 360.0) % 360.0;
  }

  static _ProjResult _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    double t;
    if (len2 == 0) {
      t = 0;
    } else {
      t = ((px - ax) * dx + (py - ay) * dy) / len2;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
    }
    final proj = LatLng(ay + dy * t, ax + dx * t);
    final dist = _haversine(p, proj);
    return _ProjResult(t: t, distance: dist);
  }
}

class _NearestSeg {
  _NearestSeg({required this.index, required this.t, required this.distanceM});
  final int index;
  final double t;
  final double distanceM;
}

class _LookAhead {
  _LookAhead({
    required this.turnVertex,
    required this.distanceM,
    required this.bearingChangeDeg,
  });
  final int turnVertex;
  final double distanceM;
  final double bearingChangeDeg;
}

class _ProjResult {
  _ProjResult({required this.t, required this.distance});
  final double t;
  final double distance;
}
