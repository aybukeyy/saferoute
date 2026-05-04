// Thin wrapper over `geolocator` for permission handling and current-position
// streaming. Used by report submission and route planning.
//
// Surfaces a tri-state permission result so the UI can show three different
// flows: granted, denied (we'll re-prompt), and deniedForever (we have to
// send the user to system settings).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';

/// The simplified outcome of [LocationService.ensurePermission].
enum LocationPermission {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Wraps `geolocator`. Every method here is a pure passthrough so widgets and
/// services can be unit-tested by stubbing this class.
class LocationService {
  LocationService();

  /// Requests permission if needed. The Android/iOS native dialog appears
  /// only on the first call; subsequent calls just resolve to the cached
  /// permission state.
  ///
  /// Returns:
  /// - [LocationPermission.serviceDisabled] if the user has location turned
  ///   off in OS settings — caller should prompt them to enable it.
  /// - [LocationPermission.deniedForever] if iOS/Android denied permanently
  ///   (Android API 30+ surfaces this after two denials).
  Future<LocationPermission> ensurePermission() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return LocationPermission.serviceDisabled;
    }
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    return switch (permission) {
      geo.LocationPermission.always ||
      geo.LocationPermission.whileInUse =>
        LocationPermission.granted,
      geo.LocationPermission.deniedForever => LocationPermission.deniedForever,
      geo.LocationPermission.denied ||
      geo.LocationPermission.unableToDetermine =>
        LocationPermission.denied,
    };
  }

  /// Returns a single best-effort position. Throws if permission is missing
  /// or the device cannot acquire a fix within the platform default timeout.
  Future<LatLng> currentPosition() async {
    final p = await geo.Geolocator.getCurrentPosition(
      locationSettings: geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.high,
        // Force LocationManager (not FusedLocationProvider) — the emulator's
        // `adb emu geo fix` injects mock locations into LocationManager's GPS
        // provider, but Fused (GMS) may not propagate them reliably.
        forceLocationManager: true,
      ),
    );
    return LatLng(p.latitude, p.longitude);
  }

  /// Streams positions throttled to at most one per [interval]. The geolocator
  /// position stream emits whenever the device moves, so we layer a periodic
  /// throttle on top to keep the UI cost predictable.
  Stream<LatLng> watchPosition({
    Duration interval = const Duration(seconds: 5),
  }) async* {
    final controller = StreamController<LatLng>.broadcast();
    DateTime? lastEmit;

    final sub = geo.Geolocator.getPositionStream(
      locationSettings: geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.high,
        // distanceFilter in metres; 0 means every update.
        distanceFilter: 5,
        // See currentPosition() for the rationale.
        forceLocationManager: true,
      ),
    ).listen((p) {
      final now = DateTime.now();
      if (lastEmit == null || now.difference(lastEmit!) >= interval) {
        lastEmit = now;
        controller.add(LatLng(p.latitude, p.longitude));
      }
    }, onError: controller.addError, onDone: controller.close);

    try {
      yield* controller.stream;
    } finally {
      await sub.cancel();
      await controller.close();
    }
  }
}

/// Riverpod provider — thin singleton, no state of its own.
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});
