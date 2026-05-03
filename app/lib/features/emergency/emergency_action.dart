import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location_service.dart';
import '../../core/result.dart';
import '../../data/reports_repository.dart';
import '../../models/classification.dart';
import '../../models/report.dart';
import 'emergency_contact_storage.dart';

typedef UrlLauncher = Future<bool> Function(Uri uri);

class EmergencyAction {
  EmergencyAction({
    required this.location,
    required this.reports,
    required this.storage,
    required this.uid,
    UrlLauncher? launcher,
    DateTime Function()? clock,
  })  : _launcher = launcher ?? _defaultLauncher,
        _clock = clock ?? DateTime.now;

  final LocationService location;
  final ReportsRepository reports;
  final EmergencyContactStorage storage;
  final String uid;
  final UrlLauncher _launcher;
  final DateTime Function() _clock;

  static Future<bool> _defaultLauncher(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static const String message = 'Acil durum / Emergency';

  Future<void> trigger() async {
    final at = await location.currentPosition();
    final occurredAt = _clock().toUtc();
    final classification = const Classification(
      category: ReportCategory.violence,
      riskLevel: RiskLevel.high,
      timeSensitive: true,
      confidence: 1.0,
      explanation: 'User-triggered emergency',
    );
    final res = await reports.submitClassified(
      text: message,
      at: at,
      occurredAt: occurredAt,
      uid: uid,
      classification: classification,
    );
    if (res is Err<Report, SubmitReportError>) {
      debugPrint('[emergency] submit failed: ${res.error}');
      throw StateError('Emergency report submission failed: ${res.error}');
    }
    final phone = await storage.read();
    if (phone == null) return;
    final body = _buildSmsBody(at, occurredAt);
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': body},
    );
    final ok = await _launcher(uri);
    if (!ok) {
      debugPrint('[emergency] launchUrl returned false for $uri');
    }
  }

  static String _buildSmsBody(LatLng at, DateTime occurredAt) {
    final lat = at.latitude.toStringAsFixed(6);
    final lng = at.longitude.toStringAsFixed(6);
    final iso = occurredAt.toIso8601String();
    return 'Acil durum. Konumum: https://maps.google.com/?q=$lat,$lng · $iso';
  }
}
