import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location_service.dart';
import '../../data/reports_repository.dart' as data;
import '../../data/sync_service.dart' as data;
import 'emergency_action.dart';
import 'emergency_contact_storage.dart';

final emergencyContactStorageProvider =
    Provider<EmergencyContactStorage>((ref) {
  return EmergencyContactStorage();
});

final emergencyActionBuilderProvider =
    Provider<Future<EmergencyAction> Function()>((ref) {
  return () async {
    final reports = await ref.read(data.reportsRepositoryProvider.future);
    final sync = await ref.read(data.syncServiceProvider.future);
    final uid = await sync.ensureAnonymousAuth();
    return EmergencyAction(
      location: LocationService(),
      reports: reports,
      storage: ref.read(emergencyContactStorageProvider),
      uid: uid,
    );
  };
});
