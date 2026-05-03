// Live route-share. Owner publishes a doc + position ticks to Firestore;
// friends watch the same doc and see a moving marker on a map.
//
// Graceful degradation mirrors `SyncService`: if Firebase isn't configured
// the service is "disabled" and every mutation no-ops while reads return an
// empty stream. This keeps the UI codepath unconditional even in dev/CI.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_share.dart';
import 'sync_service.dart' as data;

/// Default lifetime of a share session. Long enough to cover a normal walk
/// home, short enough that a forgotten share auto-cleans. The Firestore rule
/// also rejects writes past [expiresAt] so a malicious client can't extend it.
const Duration kRouteShareTtl = Duration(hours: 1);

/// How often the live position is pushed to Firestore. Trades battery/network
/// against viewer freshness — 10s feels live enough on a moving map.
const Duration kRouteSharePositionPushInterval = Duration(seconds: 10);

class RouteShareService {
  RouteShareService._({
    FirebaseFirestore? firestore,
    required bool enabled,
    required this.ttl,
    required String Function() idGenerator,
    DateTime Function()? clock,
  })  : _firestore = firestore,
        _enabled = enabled,
        _idGenerator = idGenerator,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final FirebaseFirestore? _firestore;
  final bool _enabled;
  final Duration ttl;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  bool get isEnabled => _enabled;

  /// Bridge from a `SyncService` so we share its enabled-state and Firestore
  /// instance instead of double-initializing Firebase.
  factory RouteShareService.fromSync(
    data.SyncService sync, {
    Duration ttl = kRouteShareTtl,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) {
    return RouteShareService._(
      firestore: sync.isEnabled ? FirebaseFirestore.instance : null,
      enabled: sync.isEnabled,
      ttl: ttl,
      idGenerator: idGenerator ?? _defaultIdGenerator,
      clock: clock,
    );
  }

  /// Visible for testing — lets a fake Firestore (e.g. fake_cloud_firestore)
  /// be wired up without going through `SyncService`.
  @visibleForTesting
  factory RouteShareService.test({
    required FirebaseFirestore firestore,
    Duration ttl = kRouteShareTtl,
    required String Function() idGenerator,
    DateTime Function()? clock,
  }) {
    return RouteShareService._(
      firestore: firestore,
      enabled: true,
      ttl: ttl,
      idGenerator: idGenerator,
      clock: clock,
    );
  }

  /// Disabled instance — every mutation no-ops, every watch returns empty.
  /// Used when Firestore couldn't initialize.
  factory RouteShareService.disabled() {
    return RouteShareService._(
      enabled: false,
      ttl: kRouteShareTtl,
      idGenerator: _defaultIdGenerator,
    );
  }

  /// Creates a fresh share. Returns `null` if sync is disabled — callers
  /// should surface a "Sharing unavailable" message instead of pretending it
  /// worked. The returned share's [RouteShare.id] is the share token the
  /// owner hands to a friend.
  Future<RouteShare?> create({
    required String ownerUid,
    required LatLng from,
    required LatLng to,
    required List<LatLng> safestPath,
    required int etaMinutes,
    required LatLng startPosition,
    String? message,
  }) async {
    if (!_enabled || _firestore == null) return null;
    final now = _clock();
    final share = RouteShare(
      id: _idGenerator(),
      ownerUid: ownerUid,
      from: from,
      to: to,
      safestPath: List.unmodifiable(safestPath),
      startedAt: now,
      etaMinutes: etaMinutes,
      currentPosition: startPosition,
      updatedAt: now,
      expiresAt: now.add(ttl),
      message: message,
    );
    try {
      await _firestore
          .collection('route_shares')
          .doc(share.id)
          .set(share.toMap());
      return share;
    } catch (e, st) {
      debugPrint('RouteShareService.create failed: $e\n$st');
      return null;
    }
  }

  /// Pushes a fresh position. Best-effort — silently drops on error so a
  /// flaky network never crashes the route screen.
  Future<void> updatePosition({
    required String shareId,
    required LatLng position,
  }) async {
    if (!_enabled || _firestore == null) return;
    try {
      await _firestore.collection('route_shares').doc(shareId).update({
        'currentPosition': <String, dynamic>{
          'lat': position.latitude,
          'lng': position.longitude,
        },
        'updatedAt': Timestamp.fromDate(_clock()),
      });
    } catch (e) {
      debugPrint('RouteShareService.updatePosition $shareId: $e');
    }
  }

  /// Marks the share as ended. Viewer screens hide the moving marker and
  /// show "arrived / ended" instead.
  Future<void> end(String shareId) async {
    if (!_enabled || _firestore == null) return;
    try {
      await _firestore.collection('route_shares').doc(shareId).update({
        'ended': true,
        'updatedAt': Timestamp.fromDate(_clock()),
      });
    } catch (e) {
      debugPrint('RouteShareService.end $shareId: $e');
    }
  }

  /// Streams the share doc so the viewer's marker tracks the owner live.
  /// Emits `null` if the share id doesn't exist or has been deleted.
  Stream<RouteShare?> watch(String shareId) {
    if (!_enabled || _firestore == null) {
      return Stream<RouteShare?>.value(null);
    }
    return _firestore
        .collection('route_shares')
        .doc(shareId)
        .snapshots()
        .map<RouteShare?>((doc) {
      if (!doc.exists) return null;
      try {
        return RouteShare.fromDoc(doc);
      } catch (e) {
        debugPrint('RouteShareService.watch $shareId: malformed doc ($e)');
        return null;
      }
    });
  }

  /// One-shot read. Useful for the viewer's first paint before the stream
  /// settles.
  Future<RouteShare?> get(String shareId) async {
    if (!_enabled || _firestore == null) return null;
    try {
      final doc =
          await _firestore.collection('route_shares').doc(shareId).get();
      if (!doc.exists) return null;
      return RouteShare.fromDoc(doc);
    } catch (e) {
      debugPrint('RouteShareService.get $shareId: $e');
      return null;
    }
  }
}

/// 12-char URL-safe id. Plenty of entropy (~71 bits) for a 1-hour share, no
/// hyphen-uppercase mix that's awkward to dictate over the phone.
String _defaultIdGenerator() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = math.Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < 12; i++) {
    buf.write(alphabet[rand.nextInt(alphabet.length)]);
  }
  return buf.toString();
}

/// Riverpod provider — boots off the existing `SyncService`, falls back to
/// a disabled instance when sync is unavailable so callers don't have to
/// branch on async state.
final routeShareServiceProvider =
    FutureProvider<RouteShareService>((ref) async {
  try {
    final sync = await ref.watch(data.syncServiceProvider.future);
    return RouteShareService.fromSync(sync);
  } catch (e) {
    debugPrint('routeShareServiceProvider: falling back to disabled ($e)');
    return RouteShareService.disabled();
  }
});
