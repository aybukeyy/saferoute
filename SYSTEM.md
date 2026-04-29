# Safe Route — Sistem Genel Bakışı

**Hedef:** Kaggle × Google DeepMind "Gemma 4 Good" hackathon submission'ı (deadline 2026-05-18). Yaya pedestrian'lara güvenli rota öneren, **tamamen on-device** çalışan Flutter uygulaması.

---

## 1. Tek Cümlelik Özet

> Kullanıcı bir cümlelik güvenlik raporu yazar → **Gemma 4 E2B telefonda** sınıflandırır → şehrin geohash-7 grid'i üstünde risk skoru hesaplanır → A→B rotası istenince **iki yol** çizilir (en kısa gri / en güvenli yeşil) → "neden daha güvenli?" üç katmanlı açıklama gösterir.

---

## 2. Mimari — Hiçbir Backend Server Yok

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter App  (telefon)                        │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────┐  ┌─────────────────┐    │
│  │ flutter_gemma    │  │ Risk Engine  │  │ Routing (A*)    │    │
│  │ (LiteRT runtime) │  │ (pure Dart)  │  │ bundled OSM     │    │
│  │                  │  │              │  │ ~10 MB asset    │    │
│  │ ┌──────────────┐ │  │ base × surge │  │                 │    │
│  │ │ Gemma 4 E2B  │ │  │ × time       │  │ Yen K-shortest  │    │
│  │ │ classify     │ │  │              │  │ + risk re-rank  │    │
│  │ └──────────────┘ │  │              │  │                 │    │
│  │ ┌──────────────┐ │  │              │  │                 │    │
│  │ │ Gemma 4 E4B  │ │  │              │  │                 │    │
│  │ │ summarize    │ │  │              │  │                 │    │
│  │ └──────────────┘ │  │              │  │                 │    │
│  └────────┬─────────┘  └──────┬───────┘  └────────┬────────┘    │
│           │                   │                   │              │
│           ▼                   ▼                   ▼              │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  sqflite (local SQLite) — source of truth                   │ │
│  └────────┬───────────────────────────────────────────────────┘ │
│           │ mirror (offline-first)                                │
│           ▼                                                       │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Firebase Firestore + Anonymous Auth (sadece sync)          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ flutter_map + custom heatmap painter + cell pulse animator  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

Telefon **tüm hesabı yapan tek surface**. Firestore sadece JSON store — sync amaçlı, başka cihazlardan gelen rapor pulse'larını dağıtır.

---

## 3. Klasör Yapısı

```
buk/
├── app/                           # Flutter projesi
│   ├── lib/
│   │   ├── main.dart              # boot order: gemma init → DB → Firebase → seed → warm-up
│   │   ├── app/
│   │   │   ├── router.dart        # go_router rotaları
│   │   │   ├── theme.dart         # Material 3 + risk renk token'ları
│   │   │   └── real_providers.dart # adapter pattern: UI *Like → real impl
│   │   ├── core/
│   │   │   ├── geohash.dart       # encode/decode/bounds/cellsInBoundingBox
│   │   │   ├── location_service.dart # geolocator wrapper
│   │   │   └── result.dart        # sealed Result<T,E>
│   │   ├── data/
│   │   │   ├── local_db.dart      # sqflite v1 schema + migrations
│   │   │   ├── reports_repository.dart # submit/watch/recent + per-UID rate limit
│   │   │   ├── risk_engine.dart   # baseRisk + predictedRisk + heatmap (PUBLIC sabitler)
│   │   │   ├── sync_service.dart  # Firestore mirror + watchCells + graceful degradation
│   │   │   └── seed_loader.dart   # ilk açılışta 50 synthetic Beşiktaş raporu
│   │   ├── ai/
│   │   │   ├── gemma_service.dart # Cactus-style E2B/E4B router (hot-swap)
│   │   │   ├── prompts.dart       # KILITLENMİŞ Mode 1 + Mode 2 system prompts
│   │   │   ├── parser.dart        # JSON parse + retry + safe-default
│   │   │   └── model_storage.dart # runtime download + magic-byte check + resumable
│   │   ├── routing/
│   │   │   ├── osm_graph.dart     # binary asset loader (1.1 MB Beşiktaş)
│   │   │   ├── astar.dart         # A* + Haversine heuristic
│   │   │   ├── yen_k_shortest.dart # K=5 alternative paths
│   │   │   ├── risk_rerank.dart   # cost = length + α × Σ predicted_risk
│   │   │   ├── routing_service.dart # üst-seviye orkestrasyon
│   │   │   └── priority_queue.dart # custom MinHeap (no extra dep)
│   │   ├── features/
│   │   │   ├── map/               # MapScreen + heatmap painter + pulse animator
│   │   │   ├── report/            # ReportSheet (text + auto-location)
│   │   │   ├── route/             # RoutePlanner + RouteDetail + place_search (Nominatim)
│   │   │   ├── explanation/       # 3-layer explainable AI
│   │   │   ├── feed/              # Recent reports list
│   │   │   ├── about/             # Credits + Apache 2.0 attribution
│   │   │   ├── onboarding/        # First-launch model download UI
│   │   │   └── providers.dart     # `*Like` interfaces (UI ↔ data dependency inversion)
│   │   ├── models/                # freezed: Report, RiskCell, Classification, RouteResult
│   │   └── firebase_options.dart  # flutterfire configure ile generate (gitignored)
│   ├── assets/
│   │   ├── road_graph.bin         # 1.1 MB Beşiktaş OSM walkable graph (extract_osm.py)
│   │   ├── seed_reports.json      # 50 synthetic report (3 hot zone)
│   │   └── model_config.json      # Gemma .litertlm URL'leri + size + sha256
│   ├── android/                   # AndroidManifest: location + libOpenCL hint
│   └── ios/                       # Info.plist: NSLocationWhenInUseUsageDescription
├── tools/
│   ├── extract_osm.py             # osmium ile bbox extract → walkable filter → binary
│   ├── requirements.txt           # osmium, pygeohash, tqdm
│   └── README.md                  # bbox örnekleri (Beşiktaş, Moda, Çankaya)
├── docs/planning/
│   ├── PLAN.md, ARCHITECTURE.md, IMPLEMENTATION.md   # source of truth
│   ├── TASKS.md, TODO.md, PROGRESS.md                # iş takibi
│   ├── DEMO.md                    # 3 dk video shot list + voiceover
│   ├── WRITEUP.md                 # Kaggle submission ≤1500 kelime
│   ├── GEMMA_URLS.md              # model URL araştırma raporu
│   └── MANUAL_SETUP.md            # kullanıcının elle yapacakları
├── firestore.rules                # per-UID write + 280-char limit + immutable reports
├── firebase.json + .firebaserc    # CLI config
└── SYSTEM.md                      # bu dosya
```

---

## 4. Kritik Akışlar

### A. Rapor Gönderme

```
[Kullanıcı "Report" FAB → bottom sheet → bir cümle yazıp submit]
       │
       ▼
[ReportsRepository.submitReport]
       │
       ├─► [SQLite write — status PENDING]    ← UI 100ms'de "alındı" snackbar
       │
       ├─► [GemmaService.classify (E2B)]      ← async, ~3s hedefi Pixel 7-class
       │       │
       │       ▼
       │   [SQLite update — CLASSIFIED + category/risk_level/explanation]
       │
       ├─► [RiskEngine.recomputeCell(geohash7)]
       │       │
       │       ▼
       │   [SQLite risk_cells güncellendi]
       │
       └─► [SyncService.mirror → Firestore]
                 │
                 ▼
          [Diğer cihazların listener'ı pulse:true ile çağrılır]
                 │
                 ▼
          [Heatmap painter o cell'i grey→orange→red 2sn animate eder]
```

End-to-end hedef: **< 5 saniye** rapor → uzak cihaz pulse'u (DEMO videosunun yıldızı).

### B. Rota İsteme

```
[Kullanıcı "Plan a route" FAB → search "Beşiktaş İskele" yaz veya haritaya tıkla]
       │
       ▼
[RoutingService.findRoutes(from, to, time)]
       │
       ├─► [OsmGraph.nearestNode(from), nearestNode(to)]   ← snap to walkable
       │
       ├─► [Yen K-shortest paths (K=5)]                    ← A* base + spur paths
       │
       ├─► [Tüm aday path'lerin geçtiği cell'leri topla]
       │
       ├─► [RiskEngine.predictedRisk(cell, time) — pre-compute cache]
       │
       ├─► [RiskRerank: cost = length + α × Σ risk]        ← α default 100m
       │
       ├─► [GemmaService.summarizeCell (E4B) — top-3 avoided cell]
       │   (5 dakika cache; hot-swap E2B → E4B native engine)
       │
       └─► return RouteResult { shortest, safest, avoidedCells, explanation }
                 │
                 ▼
          [RouteDetail: shortest gri instant + safest 600ms yeşil sweep
           + avoided cell outlines + sequential fade-in labels
           + "Why is this safer?" → 3-layer explanation card]
```

---

## 5. AI — Cactus-Style Routing

**İki Gemma 4 variant'ı, tek inference engine, hot-swap:**

| Mod | Model | Görev | Süre | Sıklık |
|---|---|---|---|---|
| Mode 1 | **Gemma 4 E2B** | Per-report classification + neutral explanation | ~3s | Yüksek (her rapor) |
| Mode 2 | **Gemma 4 E4B** | Per-cell area summary | ~7s | Düşük (rota + 5dk cache) |

`flutter_gemma 0.13.6` aynı anda tek `InferenceModel` warm tutar (mobil RAM kısıtı). Pixel 7'de 8GB RAM E2B+E4B aynı anda sığmaz. **Hot-swap** pattern: mod değişince `setActive(spec)`, yeni model load. Cold-start latency ödenir ama 5-min cache E4B çağrısını seyrek tutar.

**Locked system prompt'lar** `ai/prompts.dart`'ta — değişmez (eval determinism için).

**Format:** `.litertlm` (LiteRT-LM container), MediaPipe LLM Inference üzerinde GPU+CPU fallback ile çalışır.

---

## 6. Risk Hesabı (Saydam, Eğitimsiz)

```
predicted_risk(cell, t) = base_risk(cell) × surge_factor(cell, t) × time_factor(t)
```

**Sabitler — `RiskEngine` public expose** (UI Layer 3 explanation aynen kullanır):

| Çarpan | Formül | Default |
|---|---|---|
| `categoryWeight` | violence 1.0, theft 0.8, harassment 0.7, suspicious 0.5, vandalism 0.4, other 0.3 | sabit |
| `severityWeight` | low 0.4, medium 0.7, high 1.0 | sabit |
| `decay` | `exp(-age_days / 7)` | 7-gün half-life |
| `reputationFor` | `clamp([0.5, 1.5])` | per-UID |
| `surgeFactor` | `1 + min(2.0, recent_2h × 0.3)` | cap 3.0 |
| `timeFactor` | `1.5 if 22:00 ≤ t < 05:00 else 1.0` | gece çarpanı |

**ML yok** — her çarpan kullanıcıya gösterilir. Eğitilmiş model'e veri yok, ihtiyacımız da yok. Saydamlık = Safety & Trust track'in pitch'i.

---

## 7. Üç Katmanlı Açıklama (Safety & Trust Track)

| Layer | İçerik | UI |
|---|---|---|
| **1. Route-level** | Gemma E4B summary + factor chips: avoided cell sayısı, gece çarpanı, surge çarpanı, distance trade-off | RouteDetail bottom sheet "Why is this safer?" |
| **2. Report-level** | Avoided cell tap → o cell'deki raporlar listesi (orijinal text + Gemma neutral explanation + risk_level chip) | CellReportsSheet modal |
| **3. Temporal** | "Risk = base × 1.5 (gece) × 2.0 (surge)" verbatim multiplier display | Layer 1 sheet altı küçük row |

App **"AI düşünüyor ki"** demez — verileri ve modeli düz dille **alıntılar**, kullanıcı yargılar.

---

## 8. Sync Modeli

- **SQLite source of truth** — local-first writes <100ms
- **Firestore offline persistence açık** — read/write cache'lenir, network gelince reconcile
- **Anonymous Auth** — stable per-device UID (spam unit + reputation)
- **Conflict policy:** reports immutable (last-write-wins safe), risk_cells deterministik (her cihazda aynı formül)
- **Pulse mekaniği:** her mirror `pulse: true` flag'ler; başka cihazların listener'ı flag'i görür → cell animate
- **Graceful degradation:** Firebase config yoksa SyncService no-op, app local-only mode'da tam çalışır

---

## 9. Provider / Dependency Inversion Pattern

UI modülü gerçek `ReportsRepository` / `RiskEngine` / `RoutingService` sınıflarına **doğrudan bağımlı değil**. `features/providers.dart`'ta `*Like` abstract interface'ler var:

```
ReportsRepositoryLike, RiskEngineLike, RoutingServiceLike,
SyncServiceLike, LocationServiceLike, GemmaServiceLike
```

Test/mock fixture'lar default. `main.dart` boot'unda `app/real_providers.dart`'taki adapter'ları `ProviderScope.overrideWith` ile bağlar:

```dart
ui.reportsRepositoryProvider.overrideWith((ref) => ref.watch(realReportsRepositoryLikeProvider))
```

Adapter pattern → real sınıfların API'sini bozmadan UI sözleşmesine uyum (sync↔async bridge, BoundingBox dönüşümü, vs.).

**Avantaj:** UI build her zaman compile eder, modüller bağımsız evrilir. Integration agent'in işi tek satıra indi.

---

## 10. Manuel Setup (Kullanıcı Tarafı)

`docs/planning/MANUAL_SETUP.md` tam liste. Özet:

1. **Firebase** — Console'dan proje + Firestore + Anonymous Auth → `flutterfire configure` → `firebase deploy --only firestore:rules`
2. **Gemma weights** — runtime download, app ilk açılışta `assets/model_config.json`'daki HuggingFace `litert-community/gemma-4-{E2B,E4B}-it-litert-lm` URL'lerinden 5.8 GB indirir, `getApplicationSupportDirectory()`'ye kaydeder. Magic-byte check ile validation. Tek seferlik (app data persist).
3. **OSM extract** — `osmium extract -b ...` + `python tools/extract_osm.py` → `app/assets/road_graph.bin` (1.1 MB Beşiktaş walkable graph)
4. **Android SDK** — Android Studio veya `brew install --cask android-commandlinetools` + AVD Pixel 7 Pro API 34
5. **App icon** — `app/assets/icon/app_icon.png` 1024×1024 + `dart run flutter_launcher_icons`
6. **Eval (Week 3)** — `flutter pub add --dev integration_test` + Pixel 7 device + `flutter test integration_test/`

---

## 11. Geliştirme Akışı

### Build & Run
```bash
cd app
flutter analyze              # zero error/warning bekleniyor
flutter test                 # 65+ test pass bekleniyor
flutter run -d <device-id>   # debug mode
flutter build apk --release  # GitHub Releases'a yükle
flutter build web --release  # Firebase Hosting'e deploy (Gemma çalışmaz, UI smoke test)
```

### Demo Region Değiştirme
1. `tools/extract_osm.py --bbox <yeni-bbox>` → road_graph.bin yeniden üret
2. `assets/seed_reports.json` koordinatlarını yeni bbox'a uyarla
3. `MapScreen.kDefaultMapCenter` constant'ını yeni merkez ile güncelle
4. `flutter run` — yeniden build

### Yeni AI Prompt
1. `ai/prompts.dart`'taki locked string'i değiştirme **TEHLİKELİ** — eval datasetinin invariant'ı
2. Mecbursak: dataset'i de güncelle (`eval/data/mode1_dataset.json`), accuracy threshold'ı revize et
3. `flutter test integration_test/mode1_accuracy_test.dart` Pixel 7'de re-run

---

## 12. Hackathon Submission Deliverables

1. **Public GitHub repo** — kod + screenshots + README
2. **APK release** — GitHub Releases'a yüklü, kullanıcı sideload (~30 MB APK + runtime 5.8 GB Gemma download)
3. **Live web demo** — Firebase Hosting'e Flutter Web build (Gemma çalışmaz, UI showcase)
4. **YouTube video ≤ 3 dk** — DEMO.md shot list + voiceover, ≥50% scoring weight
5. **Kaggle Writeup ≤ 1500 kelime** — WRITEUP.md, Track: Safety & Trust + Cactus + LiteRT
6. **Cover image** — heatmap screenshot
7. Submit ≥ 24 saat önce (target 2026-05-17)

---

## 13. Bilinen Açıklar / Notlar

- **flutter_gemma `.task` web variant'ı mobile'da çalışmaz** — sadece `.litertlm` (LiteRT-LM container) destekleniyor
- **APK reinstall app data wipe edebilir** — UID değişimi olursa runtime download tekrar gerek (workaround: emulator snapshot)
- **iOS Simulator'de Gemma çalışmaz** — gerçek iPhone gerekli (MediaPipe LLM GPU yok simulator'de)
- **Firestore security rules per-UID rate limit yok server-side** — client-side enforcement, post-hackathon iş
- **Reputation update** — sadece read-only, server-side adjustment (Cloud Functions) post-hackathon
- **Routing region tek bbox'a sabit** — bundled OSM graph 1.1 MB, scaling path: per-region asset bundle veya runtime download

---

## Geliştirici Hızlı Referans

| Soru | Bak |
|---|---|
| Neden bu mimari? | `docs/planning/PLAN.md` + `ARCHITECTURE.md` |
| Hangi task hangi modülde? | `docs/planning/TASKS.md` |
| Manuel setup adımları | `docs/planning/MANUAL_SETUP.md` |
| Demo video shot list | `docs/planning/DEMO.md` |
| Submission writeup taslağı | `docs/planning/WRITEUP.md` |
| Karar gerekçeleri (decision log) | `docs/planning/PROGRESS.md` |
| Eval dataset + harness | `app/eval/` + `app/integration_test/` |
| Gemma URL araştırma | `docs/planning/GEMMA_URLS.md` |
