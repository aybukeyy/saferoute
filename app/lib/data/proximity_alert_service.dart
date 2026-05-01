import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geohash.dart';
import '../core/location_service.dart';
import 'reports_repository.dart';
import 'risk_engine.dart';

const double kHighRiskThreshold = 0.6;
const Duration kProximityNotificationCooldown = Duration(minutes: 5);
const int kProximityNotificationId = 7301;
const String kProximityChannelId = 'safe-route-proximity';

typedef NotificationDispatcher = Future<void> Function({
  required int id,
  required String title,
  required String body,
});

typedef Clock = DateTime Function();

class ProximityAlertService {
  ProximityAlertService({
    required LocationService location,
    required RiskEngine risk,
    required ReportsRepository reports,
    required NotificationDispatcher dispatcher,
    Clock? clock,
  })  : _location = location,
        _risk = risk,
        _reports = reports,
        _dispatch = dispatcher,
        _clock = clock ?? DateTime.now;

  final LocationService _location;
  final RiskEngine _risk;
  final ReportsRepository _reports;
  final NotificationDispatcher _dispatch;
  final Clock _clock;

  StreamSubscription<LatLng>? _sub;
  String? _lastNotifiedCell;
  DateTime? _lastNotificationAt;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _sub = _location.watchPosition().listen(
      (pos) => unawaited(_onPosition(pos)),
      onError: (Object e, StackTrace st) {
        debugPrint('[ProximityAlertService] location stream error: $e');
      },
    );
  }

  Future<void> _onPosition(LatLng pos) async {
    if (_disposed) return;
    try {
      final cell = Geohash.encode(pos.latitude, pos.longitude);
      // Stepping out of the last-notified cell clears the per-cell debounce so
      // a re-entry can fire again once the global cooldown has elapsed.
      if (_lastNotifiedCell != null && cell != _lastNotifiedCell) {
        _lastNotifiedCell = null;
      }
      final now = _clock();
      final risk = await _risk.predictedRisk(cell, now);
      if (risk < kHighRiskThreshold) return;
      if (cell == _lastNotifiedCell) return;
      if (_lastNotificationAt != null &&
          now.difference(_lastNotificationAt!) <
              kProximityNotificationCooldown) {
        return;
      }

      final recent = await _reports.reportsInCell(
        cell,
        maxAge: const Duration(hours: 12),
      );
      final body = recent.length == 1
          ? '⚠ High-risk area: 1 report tonight. Stay alert.'
          : '⚠ High-risk area: ${recent.length} reports tonight. '
              'Stay alert.';

      await _dispatch(
        id: kProximityNotificationId,
        title: 'Safe Route',
        body: body,
      );
      _lastNotifiedCell = cell;
      _lastNotificationAt = now;
    } catch (e, st) {
      debugPrint('[ProximityAlertService] onPosition failed: $e\n$st');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
  }
}
