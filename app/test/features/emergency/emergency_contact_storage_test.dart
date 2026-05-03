import 'package:app/features/emergency/emergency_contact_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EmergencyContactStorage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('read returns null when unset', () async {
      final s = EmergencyContactStorage();
      expect(await s.read(), isNull);
    });

    test('write then read round-trips', () async {
      final s = EmergencyContactStorage();
      await s.write('+905551234567');
      expect(await s.read(), '+905551234567');
    });

    test('clear removes the value', () async {
      final s = EmergencyContactStorage();
      await s.write('+905551234567');
      await s.clear();
      expect(await s.read(), isNull);
    });

    test('empty string treated as unset', () async {
      SharedPreferences.setMockInitialValues({
        'emergency_contact_phone': '',
      });
      final s = EmergencyContactStorage();
      expect(await s.read(), isNull);
    });
  });
}
