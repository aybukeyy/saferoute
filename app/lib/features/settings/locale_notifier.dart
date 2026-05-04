// Persists the user-selected app locale to SharedPreferences and exposes it
// as a Riverpod Notifier. The notifier loads the saved value once at boot
// and falls back to the device locale on first run (TR if Turkish, EN
// otherwise) — that way a Turkish user sees Turkish on first open without
// touching settings.

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefKey = 'app_locale_code';

/// Returns a sensible default — Turkish if the device is Turkish, English
/// otherwise. Anything we don't ship gets normalised to English.
Locale _defaultLocale() {
  final platform = WidgetsBinding.instance.platformDispatcher.locale;
  return platform.languageCode == 'tr'
      ? const Locale('tr')
      : const Locale('en');
}

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    // Initial sync value while the async load resolves. The async load below
    // races with the first frame; in practice it lands well before any
    // settings UI is shown, so the UI flicker is invisible.
    _loadSaved();
    return _defaultLocale();
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPrefKey);
      if (saved == 'tr' || saved == 'en') {
        state = Locale(saved!);
      }
    } catch (e) {
      debugPrint('[LocaleNotifier] failed to load saved locale: $e');
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == state.languageCode) return;
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, locale.languageCode);
    } catch (e) {
      debugPrint('[LocaleNotifier] failed to persist locale: $e');
    }
  }
}

final localeNotifierProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
