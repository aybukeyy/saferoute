import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContactStorage {
  EmergencyContactStorage({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'emergency_contact_phone';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _resolve() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> read() async {
    final p = await _resolve();
    final v = p.getString(_key);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> write(String phone) async {
    final p = await _resolve();
    await p.setString(_key, phone);
  }

  Future<void> clear() async {
    final p = await _resolve();
    await p.remove(_key);
  }
}
