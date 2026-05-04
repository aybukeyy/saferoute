// Tiny localisation layer — TR/EN string maps + a Riverpod-friendly accessor.
// Deliberately not flutter_gen_l10n / ARB based; the hackathon scope only
// needs two languages and we want zero changes to the build pipeline.
//
// Adding a new key:
//   1. Add it to both `_tr` and `_en` below.
//   2. Add a strongly-typed getter on [AppStrings].
//   3. Use it via `ref.watch(stringsProvider).<key>`.

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/locale_notifier.dart';

class AppStrings {
  const AppStrings._(this._values);

  final Map<String, String> _values;

  static const Locale tr = Locale('tr');
  static const Locale en = Locale('en');
  static const List<Locale> supportedLocales = [tr, en];

  static AppStrings forLocale(Locale locale) {
    final code = locale.languageCode == 'tr' ? 'tr' : 'en';
    return AppStrings._(code == 'tr' ? _tr : _en);
  }

  static AppStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return forLocale(locale ?? en);
  }

  String get(String key) => _values[key] ?? _en[key] ?? key;

  // Map screen / common ------------------------------------------------------
  String get appTitle => get('appTitle');
  String get menuRecentReports => get('menuRecentReports');
  String get menuEmergencyContact => get('menuEmergencyContact');
  String get menuAbout => get('menuAbout');
  String get menuSettings => get('menuSettings');
  String get reportFabLabel => get('reportFabLabel');
  String get planRouteTooltip => get('planRouteTooltip');
  String get locateTooltip => get('locateTooltip');
  String get locationNotReady => get('locationNotReady');

  // Settings -----------------------------------------------------------------
  String get settingsTitle => get('settingsTitle');
  String get settingsLanguage => get('settingsLanguage');
  String get settingsLanguageTurkish => get('settingsLanguageTurkish');
  String get settingsLanguageEnglish => get('settingsLanguageEnglish');

  // Route planner ------------------------------------------------------------
  String get routePlannerTitle => get('routePlannerTitle');
  String get routePlannerHint => get('routePlannerHint');
  String get routePlannerTapHint => get('routePlannerTapHint');
  String get routePlannerDestinationSet => get('routePlannerDestinationSet');
  String get routePlannerFindRoute => get('routePlannerFindRoute');

  // Route detail -------------------------------------------------------------
  String get routeTitle => get('routeTitle');
  String get routeMute => get('routeMute');
  String get routeUnmute => get('routeUnmute');
  String routeFailed(String error) => get('routeFailed').replaceAll('{e}', error);
  String get routeSafestRoute => get('routeSafestRoute');
  String get routeWhyIsThisSafer => get('routeWhyIsThisSafer');

  // Emergency ----------------------------------------------------------------
  String get emergencySent => get('emergencySent');
  String emergencyError(String error) => get('emergencyError').replaceAll('{e}', error);
  String get emergencyHoldHint => get('emergencyHoldHint');
  String get emergencyContactTitle => get('emergencyContactTitle');
  String get emergencyContactHint => get('emergencyContactHint');
  String get emergencyContactPhoneLabel => get('emergencyContactPhoneLabel');
  String get emergencyContactPhoneError => get('emergencyContactPhoneError');
  String get saveAction => get('saveAction');
  String get clearAction => get('clearAction');
  String get saved => get('saved');
  String get cleared => get('cleared');

  // Route share --------------------------------------------------------------
  String get shareDialogTitle => get('shareDialogTitle');
  String get shareDialogHint => get('shareDialogHint');
  String get shareMessageLabel => get('shareMessageLabel');
  String get shareAction => get('shareAction');
  String get shareCancel => get('shareCancel');
  String get shareEnd => get('shareEnd');
  String get shareEndDialogTitle => get('shareEndDialogTitle');
  String get shareEndDialogBody => get('shareEndDialogBody');
  String get shareOffline => get('shareOffline');
  String get shareCouldNotStart => get('shareCouldNotStart');
  String get shareLinkCopied => get('shareLinkCopied');
  String get shareEnded => get('shareEnded');
  String get shareViewerTitle => get('shareViewerTitle');
  String shareViewerUnavailable(String error) =>
      get('shareViewerUnavailable').replaceAll('{e}', error);
  String get shareViewerInvalid => get('shareViewerInvalid');
  String get shareLive => get('shareLive');
  String get shareArrived => get('shareArrived');
  String get shareExpired => get('shareExpired');
  String shareEta(int min) => get('shareEta').replaceAll('{n}', '$min');
  String shareLastUpdate(String rel) =>
      get('shareLastUpdate').replaceAll('{rel}', rel);
  String relJustNow() => get('relJustNow');
  String relSeconds(int n) => get('relSeconds').replaceAll('{n}', '$n');
  String relMinutes(int n) => get('relMinutes').replaceAll('{n}', '$n');
  String relHours(int n) => get('relHours').replaceAll('{n}', '$n');
  String relDays(int n) => get('relDays').replaceAll('{n}', '$n');

  // Explanation card / cell sheet -------------------------------------------
  String get explainAvoidedCells => get('explainAvoidedCells');
  String get explainRiskFormula => get('explainRiskFormula');
  String explainCellSubtitle(String gh) =>
      get('explainCellSubtitle').replaceAll('{gh}', gh);
  String get explainCellReportsTitle => get('explainCellReportsTitle');
  String get explainCellLabel => get('explainCellLabel');
  String get explainNoReportsHere => get('explainNoReportsHere');
  String get explainGenerating => get('explainGenerating');
  String explainFailedToLoad(String error) =>
      get('explainFailedToLoad').replaceAll('{e}', error);

  // Report sheet -------------------------------------------------------------
  String get reportSheetVoiceUnavailable => get('reportSheetVoiceUnavailable');
  String get reportSheetSubmitted => get('reportSheetSubmitted');
  String get reportSheetCouldNotAttach => get('reportSheetCouldNotAttach');
  String get reportSheetCamera => get('reportSheetCamera');
  String get reportSheetGallery => get('reportSheetGallery');

  // Recent reports -----------------------------------------------------------
  String get recentTitle => get('recentTitle');
  String recentFailed(String error) =>
      get('recentFailed').replaceAll('{e}', error);
  String get recentEmpty => get('recentEmpty');

  // About --------------------------------------------------------------------
  String get aboutTitle => get('aboutTitle');
  String get aboutVersionTagline => get('aboutVersionTagline');
  String get aboutGemmaTitle => get('aboutGemmaTitle');
  String get aboutGemmaSubtitle => get('aboutGemmaSubtitle');
  String get aboutOSMTitle => get('aboutOSMTitle');
  String get aboutOSMSubtitle => get('aboutOSMSubtitle');
  String get aboutFirebaseTitle => get('aboutFirebaseTitle');
  String get aboutFirebaseSubtitle => get('aboutFirebaseSubtitle');
  String get aboutSourceTitle => get('aboutSourceTitle');
}

const Map<String, String> _tr = {
  'appTitle': 'Safe Route',
  'menuRecentReports': 'Son raporlar',
  'menuEmergencyContact': 'Acil durum kişisi',
  'menuAbout': 'Hakkında',
  'menuSettings': 'Ayarlar',
  'reportFabLabel': 'Rapor',
  'planRouteTooltip': 'Rota planla',
  'locateTooltip': 'Konumuma git',
  'locationNotReady': 'Konum henüz hazır değil',

  'settingsTitle': 'Ayarlar',
  'settingsLanguage': 'Dil',
  'settingsLanguageTurkish': 'Türkçe',
  'settingsLanguageEnglish': 'İngilizce',

  'routePlannerTitle': 'Rota planla',
  'routePlannerHint': 'Hedef ara (örn: Marmara Park, Beylikdüzü, Kadıköy İskele)',
  'routePlannerTapHint': 'Veya haritaya dokunun',
  'routePlannerDestinationSet': 'Hedef seçildi — rota oluşturulabilir.',
  'routePlannerFindRoute': 'Rota bul',

  'routeTitle': 'Rota',
  'routeMute': 'Sesi kapat',
  'routeUnmute': 'Sesi aç',
  'routeFailed': 'Rota bulunamadı: {e}',
  'routeSafestRoute': 'En güvenli rota',
  'routeWhyIsThisSafer': 'Neden daha güvenli?',

  'emergencySent': 'Acil durum gönderildi',
  'emergencyError': 'Hata: {e}',
  'emergencyHoldHint': 'Basılı tut: 1 saniye',
  'emergencyContactTitle': 'Acil durum kişisi',
  'emergencyContactHint': 'Acil durum butonuna basıldığında SMS gönderilecek numara.',
  'emergencyContactPhoneLabel': 'Telefon (E.164, örn +905551234567)',
  'emergencyContactPhoneError': 'Uluslararası format kullan, örn: +905551234567',
  'saveAction': 'Kaydet',
  'clearAction': 'Sil',
  'saved': 'Kaydedildi',
  'cleared': 'Silindi',

  'shareDialogTitle': 'Rota paylaş',
  'shareDialogHint':
      'Arkadaşına gidecek mesaj. Bağlantıya dokunduğunda konumunu canlı görecek.',
  'shareMessageLabel': 'Mesaj',
  'shareAction': 'Paylaş',
  'shareCancel': 'Vazgeç',
  'shareEnd': 'Bitir',
  'shareEndDialogTitle': 'Paylaşımı bitir?',
  'shareEndDialogBody': 'Arkadaşların artık konumunu göremeyecek.',
  'shareOffline': 'Paylaşım çevrimdışı',
  'shareCouldNotStart': 'Paylaşım başlatılamadı',
  'shareLinkCopied': 'Bağlantı kopyalandı',
  'shareEnded': 'Paylaşım bitirildi',
  'shareViewerTitle': 'Canlı rota',
  'shareViewerUnavailable': 'Paylaşım kullanılamıyor: {e}',
  'shareViewerInvalid': 'Bağlantı geçersiz veya silinmiş.',
  'shareLive': 'CANLI',
  'shareArrived': 'VARDI',
  'shareExpired': 'SÜRESİ DOLDU',
  'shareEta': 'Tahmini {n} dk',
  'shareLastUpdate': 'Son güncelleme: {rel}',
  'relJustNow': 'şimdi',
  'relSeconds': '{n} sn önce',
  'relMinutes': '{n} dk önce',
  'relHours': '{n} sa önce',
  'relDays': '{n} gün önce',

  'explainAvoidedCells': 'Atlanan bölgeler',
  'explainRiskFormula': 'Risk formülü',
  'explainCellSubtitle': 'Hücre {gh} — katkı veren raporlar için dokun',
  'explainCellReportsTitle': 'Bu hücredeki raporlar',
  'explainCellLabel': 'Hücre',
  'explainNoReportsHere': 'Bu hücrede henüz katkı veren rapor yok.',
  'explainGenerating': 'Bölge özeti üretiliyor…',
  'explainFailedToLoad': 'Raporlar yüklenemedi: {e}',

  'reportSheetVoiceUnavailable':
      'Sesli giriş kullanılamıyor. Raporunu yaz.',
  'reportSheetSubmitted': 'Rapor alındı — cihazda sınıflandırılıyor…',
  'reportSheetCouldNotAttach': 'Fotoğraf eklenemedi.',
  'reportSheetCamera': 'Kamera',
  'reportSheetGallery': 'Galeri',

  'recentTitle': 'Son raporlar',
  'recentFailed': 'Yüklenemedi: {e}',
  'recentEmpty': 'Henüz rapor yok.',

  'aboutTitle': 'Hakkında',
  'aboutVersionTagline': 'v1.0.0 · açıklanabilir güvenli navigasyon',
  'aboutGemmaTitle': 'Gemma 4 ile yapıldı',
  'aboutGemmaSubtitle':
      'Cihazda sınıflandırma & özet · Apache 2.0',
  'aboutOSMTitle': 'Haritalar © OpenStreetMap katkıda bulunanlar',
  'aboutOSMSubtitle': 'OSMF politikasına göre tile kullanımı',
  'aboutFirebaseTitle': 'Firebase ile senkron',
  'aboutFirebaseSubtitle':
      'Anonim Auth · Firestore çevrimdışı kalıcılık',
  'aboutSourceTitle': 'Kaynak kod',
};

const Map<String, String> _en = {
  'appTitle': 'Safe Route',
  'menuRecentReports': 'Recent reports',
  'menuEmergencyContact': 'Emergency contact',
  'menuAbout': 'About',
  'menuSettings': 'Settings',
  'reportFabLabel': 'Report',
  'planRouteTooltip': 'Plan a route',
  'locateTooltip': 'Center on me',
  'locationNotReady': 'Location not ready yet',

  'settingsTitle': 'Settings',
  'settingsLanguage': 'Language',
  'settingsLanguageTurkish': 'Turkish',
  'settingsLanguageEnglish': 'English',

  'routePlannerTitle': 'Plan route',
  'routePlannerHint': 'Find a destination (e.g. Marmara Park, Beylikdüzü, Kadıköy Pier)',
  'routePlannerTapHint': 'Or tap the map',
  'routePlannerDestinationSet': 'Destination set — ready to find routes.',
  'routePlannerFindRoute': 'Find route',

  'routeTitle': 'Route',
  'routeMute': 'Mute voice',
  'routeUnmute': 'Unmute voice',
  'routeFailed': 'Routing failed: {e}',
  'routeSafestRoute': 'Safest route',
  'routeWhyIsThisSafer': 'Why is this safer?',

  'emergencySent': 'Emergency sent',
  'emergencyError': 'Error: {e}',
  'emergencyHoldHint': 'Hold for 1 second',
  'emergencyContactTitle': 'Emergency contact',
  'emergencyContactHint':
      'Phone that receives an SMS when the emergency button is held.',
  'emergencyContactPhoneLabel': 'Phone (E.164, e.g. +905551234567)',
  'emergencyContactPhoneError': 'Use international format, e.g. +905551234567',
  'saveAction': 'Save',
  'clearAction': 'Clear',
  'saved': 'Saved',
  'cleared': 'Cleared',

  'shareDialogTitle': 'Share route',
  'shareDialogHint':
      "The message your friend will get. They'll see your live location when they tap the link.",
  'shareMessageLabel': 'Message',
  'shareAction': 'Share',
  'shareCancel': 'Cancel',
  'shareEnd': 'End',
  'shareEndDialogTitle': 'End share?',
  'shareEndDialogBody': 'Friends can no longer see your live location.',
  'shareOffline': 'Sharing offline',
  'shareCouldNotStart': 'Could not start share',
  'shareLinkCopied': 'Link copied',
  'shareEnded': 'Share ended',
  'shareViewerTitle': 'Live route',
  'shareViewerUnavailable': 'Sharing unavailable: {e}',
  'shareViewerInvalid': 'This share link is invalid or has been deleted.',
  'shareLive': 'LIVE',
  'shareArrived': 'ARRIVED',
  'shareExpired': 'EXPIRED',
  'shareEta': 'ETA {n} min',
  'shareLastUpdate': 'Last update: {rel}',
  'relJustNow': 'just now',
  'relSeconds': '{n}s ago',
  'relMinutes': '{n} min ago',
  'relHours': '{n} h ago',
  'relDays': '{n} d ago',

  'explainAvoidedCells': 'Avoided cells',
  'explainRiskFormula': 'Risk formula',
  'explainCellSubtitle': 'Cell {gh} — tap for contributing reports',
  'explainCellReportsTitle': 'Reports in this cell',
  'explainCellLabel': 'Cell',
  'explainNoReportsHere': 'No contributing reports in this cell yet.',
  'explainGenerating': 'Generating area summary…',
  'explainFailedToLoad': 'Failed to load reports: {e}',

  'reportSheetVoiceUnavailable':
      'Voice input unavailable. Type your report.',
  'reportSheetSubmitted': 'Report received — classifying on-device…',
  'reportSheetCouldNotAttach': 'Could not attach photo.',
  'reportSheetCamera': 'Camera',
  'reportSheetGallery': 'Gallery',

  'recentTitle': 'Recent reports',
  'recentFailed': 'Failed to load: {e}',
  'recentEmpty': 'No reports yet.',

  'aboutTitle': 'About',
  'aboutVersionTagline': 'v1.0.0 · explainable safety navigation',
  'aboutGemmaTitle': 'Built with Gemma 4',
  'aboutGemmaSubtitle':
      'On-device classification & summarization · Apache 2.0',
  'aboutOSMTitle': 'Maps © OpenStreetMap contributors',
  'aboutOSMSubtitle': 'Tile usage per OSMF policy',
  'aboutFirebaseTitle': 'Sync via Firebase',
  'aboutFirebaseSubtitle':
      'Anonymous Auth · Firestore offline persistence',
  'aboutSourceTitle': 'Source code',
};

final stringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(localeNotifierProvider);
  return AppStrings.forLocale(locale);
});
