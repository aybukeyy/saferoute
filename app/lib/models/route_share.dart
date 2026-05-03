import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// One live route-share session. Created when the user taps "Share route" on
/// `RouteDetailScreen`; updated on every position tick; auto-expires via the
/// [expiresAt] field (Firestore rules drop reads/writes once it's past).
///
/// Plain Dart — not freezed — so we don't need `build_runner` for a fresh
/// checkout. Firestore is the source of truth; the model just shapes the doc.
class RouteShare {
  const RouteShare({
    required this.id,
    required this.ownerUid,
    required this.from,
    required this.to,
    required this.safestPath,
    required this.startedAt,
    required this.etaMinutes,
    required this.currentPosition,
    required this.updatedAt,
    required this.expiresAt,
    this.message,
    this.ended = false,
  });

  final String id;
  final String ownerUid;
  final LatLng from;
  final LatLng to;
  final List<LatLng> safestPath;
  final DateTime startedAt;
  final int etaMinutes;
  final LatLng currentPosition;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final String? message;
  final bool ended;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
  bool get isActive => !ended && !isExpired;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'ownerUid': ownerUid,
        'from': _latLngToMap(from),
        'to': _latLngToMap(to),
        'safestPath':
            safestPath.map(_latLngToMap).toList(growable: false),
        'startedAt': Timestamp.fromDate(startedAt),
        'etaMinutes': etaMinutes,
        'currentPosition': _latLngToMap(currentPosition),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'message': message,
        'ended': ended,
      };

  static RouteShare fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('route_shares/${doc.id} has no data');
    }
    return fromMap(doc.id, data);
  }

  /// Plain-map factory — split out from [fromDoc] so unit tests can exercise
  /// serialization without spinning up a fake Firestore.
  static RouteShare fromMap(String id, Map<String, dynamic> data) {
    return RouteShare(
      id: id,
      ownerUid: data['ownerUid'] as String,
      from: _latLngFromMap(data['from'] as Map<String, dynamic>),
      to: _latLngFromMap(data['to'] as Map<String, dynamic>),
      safestPath: ((data['safestPath'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_latLngFromMap)
          .toList(growable: false),
      startedAt: (data['startedAt'] as Timestamp).toDate(),
      etaMinutes: (data['etaMinutes'] as num).toInt(),
      currentPosition:
          _latLngFromMap(data['currentPosition'] as Map<String, dynamic>),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      message: data['message'] as String?,
      ended: (data['ended'] as bool?) ?? false,
    );
  }
}

Map<String, dynamic> _latLngToMap(LatLng p) => <String, dynamic>{
      'lat': p.latitude,
      'lng': p.longitude,
    };

LatLng _latLngFromMap(Map<String, dynamic> m) => LatLng(
      (m['lat'] as num).toDouble(),
      (m['lng'] as num).toDouble(),
    );
