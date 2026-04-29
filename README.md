# Safe Route

Explainable on-device safety navigation — Flutter uygulaması.

Risk verisini kullanıcı raporları + risk grid (cell) hesaplarından üretir,
yol seçimini Gemma 4 modeli ile cihazda (offline) açıklar. Harita: OSM /
flutter_map; backend: Firebase (Firestore + Anonymous Auth); LLM:
flutter_gemma + MediaPipe Inference.

## Stack

- **Flutter** ^3.11.5 (Dart 3)
- **Riverpod** state management
- **flutter_map + latlong2** OSM tabanlı harita
- **flutter_gemma 0.13.6** on-device LLM (Gemma 4 E2B / E4B)
- **Firebase** Firestore + Anonymous Auth
- **Android** Kotlin, **iOS** Swift, **Web** desteği

## Android Studio ile Projeyi Açma

### Önkoşullar

1. **Android Studio Hedgehog (2023.1) veya üzeri** kurulu olsun
2. **Flutter SDK** kurulu ve PATH'te olsun
   - macOS: `brew install --cask flutter` veya https://docs.flutter.dev/get-started/install
   - Doğrula: `flutter --version` → 3.x görünmeli
3. **Flutter & Dart pluginleri** Android Studio'ya eklenmiş olmalı
   - Settings → Plugins → Marketplace → "Flutter" ara → Install
   - Dart plugin otomatik yüklenir
   - IDE'yi yeniden başlat

### Projeyi açma

1. **Repo'yu klonla**
   ```sh
   git clone https://github.com/aybukeyy/saferoute.git
   cd saferoute
   ```

2. **Android Studio'da File → Open** → klonladığın `saferoute/app` klasörünü seç
   (proje root'u `app/` klasörüdür, üst klasör değil)

3. **Pub get** otomatik çalışır. Manuel tetiklemek istersen:
   ```sh
   cd app
   flutter pub get
   ```

4. **Flutter Doctor** ile kurulumu doğrula:
   ```sh
   flutter doctor
   ```
   Tüm onay işaretleri yeşil olmalı. Eksik varsa Android Studio'nun verdiği "fix" linklerini takip et.

### Manuel kurulum (zorunlu — kod tarafının yapamadığı adımlar)

- **Firebase config:**
  ```sh
  cd app
  flutterfire configure --project=<proje-id>
  ```
  Bu komut `firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist` üretir (üçü de `.gitignore`'da, repo'da yok). Firebase Console'da Firestore + Anonymous Auth aktif olmalı.

- **Gemma 4 weights:** İlk açılışta uygulama otomatik indirir (~4.6 GB, `getApplicationSupportDirectory` altına). Bundle edilmez.

- **OSM road graph:**
  ```sh
  cd tools
  pip install -r requirements.txt
  python extract_osm.py
  ```
  `app/assets/road_graph.bin` üretilir (`.gitignore`'da, repo'da yok).

### Çalıştırma

Android Studio'da üst bardan:

1. **Device seç** (emülatör veya bağlı fiziksel cihaz)
2. **Run** butonu (veya `Shift+F10`)
3. Debug için **Debug** (`Shift+F9`)

CLI alternatif:
```sh
cd app
flutter run                    # bağlı cihazda çalıştır
flutter run -d chrome          # web
flutter run --release          # release modu
```

### Cihaz / Emülatör hazırlama

- **Android emülatör:** Android Studio → Device Manager → Create Device → Pixel 7+ (API 33+ önerilir)
- **iOS simülatör (yalnız macOS):** `open -a Simulator`
- **Fiziksel Android:** Settings → About → Build Number 7 kez tıkla → Developer options → USB debugging aç → kabloyla bağla

## Proje Yapısı

```
saferoute/
├── app/                        # Flutter projesi (Android Studio bunu açar)
│   ├── lib/                    # Dart kaynak kodu
│   ├── android/                # Android native (Kotlin, Gradle)
│   ├── ios/                    # iOS native (Swift, Pods)
│   ├── web/                    # Web desteği
│   ├── test/                   # Unit testler
│   ├── integration_test/       # Integration testler
│   ├── eval/                   # LLM çıktı eval scriptleri
│   └── pubspec.yaml            # Flutter bağımlılıkları
├── tools/                      # Python yardımcı scriptleri (OSM extract)
├── firebase.json               # Firebase Hosting config
├── firestore.rules             # Firestore security rules
└── SYSTEM.md                   # Sistem tasarım dokümanı
```

## Daha fazla bilgi

- **Sistem tasarımı:** [`SYSTEM.md`](SYSTEM.md)

## Sorun Giderme

| Sorun | Çözüm |
|---|---|
| `flutter doctor` Android toolchain hatalı | Android Studio → SDK Manager → SDK Tools → "Android SDK Command-line Tools" yükle |
| `Gradle build failed` | `cd app/android && ./gradlew clean` sonra Android Studio "Sync Project with Gradle Files" |
| `Firebase config not found` | `flutterfire configure` çalıştırılmamış. Yukarıdaki **Manuel kurulum** bölümüne bak. |
| Gemma model yüklenmiyor | İnternet bağlantısı + en az ~5 GB boş disk gerekli (ilk açılış) |
| `road_graph.bin not found` | `python tools/extract_osm.py` çalıştır |

## Lisans

Hackathon projesi — şimdilik özel kullanım.
