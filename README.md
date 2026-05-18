<div align="center">

# 🛡️ Safe Route

### Community-powered pedestrian safety navigation with on-device Gemma 4

</div>

---

> **"Like Google Maps — but it tells you which streets to *avoid*."**

Safe Route is a pedestrian safety navigation app that runs entirely **on your phone**. Community members submit one-sentence safety reports; Gemma 4 classifies them in real time, on-device; the app builds a live risk map and offers **two routes** between any A→B: the shortest (gray) and the safest (green). No black box. No cloud AI. No privacy compromise.

Built for the **Kaggle × Google DeepMind Gemma 4 Good Hackathon** — Safety category.

---

## 📋 Table of Contents

- [The Problem](#-the-problem--the-trust-gap)
- [Who It's For](#-who-its-for)
- [Demo](#-demo)
- [How It Works](#️-how-it-works)
- [How Gemma 4 Is Used](#-how-gemma-4-is-used)
- [Risk Model](#-transparent-risk-model)
- [Route Planning](#️-route-planning)
- [Architecture](#️-architecture)
- [Tech Stack](#️-tech-stack)
- [Setup](#-setup)
- [Project Structure](#-project-structure)
- [Evaluation](#-evaluation)
- [Known Limitations](#️-known-limitations)
- [Hackathon](#-hackathon)

---

## 🚨 The Problem — The Trust Gap

Pedestrians in cities make routing decisions based on **safety intuition** — a sense shaped by past experiences and word-of-mouth. That collective knowledge exists, but there has never been any infrastructure to surface it.

Existing navigation apps optimize for time and distance. None of them account for *perceived safety*.

### The Scale of the Problem

| Data | Source |
|---|---|
| English children aged 7–8 who walked to school alone: **80% in 1972 → 9% in 1990** | Policy Studies Institute, UK |
| US children walking to school: **48% in 1969 → 13% in 2009** | National Center for Safe Routes to School |
| **10–14%** of morning traffic is parents driving kids to school | Safe Routes to School Partnership |
| An average of **67,124 children** are injured as pedestrians each year in the US; **704** die | Children's Safety Network |
| **36%** of under-16 pedestrian deaths occur between 3–7 PM — peak school dismissal hours | Children's Safety Network |
| **46%** of parents cite traffic danger as the reason they don't let their child walk to school; **11%** cite crime | CDC, 2018 |

**The real breaking point:** If these parents had concrete, real-time, street-level information, their decision would be far easier. Safe Route provides exactly that.

---

## 👥 Who It's For

### 🧒 Children — The Walk to School Can Be Made Visible

Children's freedom to move independently has shrunk dramatically over the past 50 years. Are streets more dangerous? Perhaps slightly. But the core problem is **invisibility**: parents feel danger without having concrete, street-level data.

#### School Route Scenario

Selin is 10 years old. She leaves home at 8:15 AM to walk to school. On one street, she encounters a stranger standing in a doorway who calls out to her repeatedly.

**Selin opens the app and writes one sentence:**

> *"A stranger was waiting in a doorway on the school route and kept calling out to me."*

**Behind the scenes, in 3 seconds:**

```
Gemma 4 E2B (on-device):
  → category:      "suspicious_behavior"
  → riskLevel:     "medium"
  → timeSensitive: true
  → explanation:   "Persistent contact attempt by stranger — medium risk during morning school hours"

RiskEngine:
  → geohash-7 cell for that street turns red
  → surge_factor updated

Firestore (< 5s):
  → That cell pulses on all other devices
```

**10 minutes later, what does Ahmet (age 11) see when he tries to take the same street?**

That cell is red on the map. When he requests a route:

- **Gray route:** Shortest — but it passes through that street
- **Green route:** +180m, +2 min — but avoids that block entirely

When he taps "Why is this safer?":

> *"This route skips Çiçek Sokak, where a suspicious behavior report was filed this morning. Report came in 12 minutes ago (no night multiplier, density multiplier: 1.3)."*

Ahmet doesn't take that street. And he knows exactly why.

---

### 👩 Women

Real-time visibility of routes to avoid when walking alone at night. Harassment or stalking reports are automatically escalated with a night multiplier (**×1.5**), and neighboring cells are also affected.

### 👴 Elderly & Vulnerable Groups

The risk engine running in the background requires no ML training — data works locally over SQLite even without a network connection. No account needed; anonymous auth is assigned automatically.

### 🌐 Everyone

> **"One person sees it, reports it. The next pedestrian doesn't go there."**

That is Safe Route's community chain. Every report reaches all users on that street in real time.

---

## 🎬 Demo

[▶ Watch the 3-minute demo video](https://youtu.be/EY5UBMpPF_g)

| Risk Map | Safe vs Short Route | Safety Report |
|:---:|:---:|:---:|
| ![map](docs/screenshots/riskmap.png) | ![route](docs/screenshots/route.png) | ![report](docs/screenshots/reportpage.png) |
| Hex-cell heatmap, live pulse animation | Green (safe) vs gray (short), +180m difference | One sentence, audio/photo, <5s sync |

**Highlights in the demo:**
- Model download → first app launch
- Live report submission → pulse animation on another device **< 5 seconds**
- Safe vs short route comparison — +180m / +2min trade-off label
- "Why is this safer?" 3-layer explanation screen
- Emergency button → SMS deeplink

---

## ⚙️ How It Works

### The Core Loop (end-to-end < 5 seconds)

```
1. User taps Report → writes one sentence
2. Gemma 4 E2B classifies on-device → category, risk, explanation
3. RiskEngine recomputes the hex cell for that street
4. Other devices receive a pulse animation via Firestore
```

### Full Pipeline

```
User report (1 sentence)               GPS location
        │                                   │
        └──────────────┬────────────────────┘
                       ▼
           ReportsRepository
           SQLite write → status: PENDING
           [< 100ms — "Report received" snackbar]
                       │
                       ▼
         ┌─────────────────────────────┐
         │   GemmaService.classify     │  ← on-device, ~3s
         │   Gemma 4 E2B               │
         │   prompts.dart (locked)     │
         └─────────────┬───────────────┘
                       │
                       ▼
              Classification
       {category, riskLevel, timeSensitive,
        confidence, explanation}
                       │
          SQLite UPDATE → status: CLASSIFIED
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
  RiskEngine                  SyncService
  recomputeCell(geohash7)     mirror → Firestore
  risk_cells updated          pulse: true flag
          │                         │
          ▼                         ▼
  Heatmap updated           Other devices
  (1s refresh)              pulse animate (< 5s)
          │
          │  [if route request pending]
          ▼
  RoutingService.findRoutes(from, to, time)
  ├─ OSM graph → nearestNode snap
  ├─ A* + Yen K-Shortest (K=5)
  ├─ risk_rerank: cost = distance + α × Σ risk
  └─ GemmaService.summarizeCell [E4B, ~7s, 5min cache]
          │
          ▼
     RouteResult
     shortest (gray) + safest (green)
     + avoidedCells + 3-layer explanation
```

---

## 🧠 How Gemma 4 Is Used

Safe Route uses **two Gemma 4 edge models with a hot-swap architecture**. Both cannot be held in memory simultaneously (Pixel 7, 8 GB RAM); `setActive(spec)` loads whichever is needed on demand.

| Model | Task | Latency | Frequency |
|---|---|---|---|
| **Gemma 4 E2B** (~2.58 GB) | Report classification | ~3s | Every report |
| **Gemma 4 E4B** (~3.65 GB) | Avoided area summary | ~7s | Per route, 5min cache |

### E2B — Report Classification

Converts every incoming report into a structured object:

```json
{
  "category": "harassment",
  "riskLevel": "medium",
  "timeSensitive": true,
  "confidence": 0.87,
  "explanation": "Two individuals following someone — high risk in early evening"
}
```

- The system prompt in `prompts.dart` is **locked** — never modified, for eval determinism
- `parser.dart` parses the JSON response; retry + safe-default on error
- Format: `.litertlm` container (LiteRT-LM), GPU + CPU fallback

### E4B — Area Summary

Summarizes avoided cells in natural language during route planning:

> *"This route skips Barbaros Bulvarı, where 3 incidents were reported tonight."*

- 5-minute cache: E4B is not called repeatedly for the same cell
- Hot-swap: E2B unloads → E4B loads → reverts when cache expires

### Why On-Device?

Personal safety reports are among the most sensitive data that exists. *"I was followed near X at 11 PM"* contains location, time, routine, and vulnerability information. Cloud inference — even with a trusted provider — is not appropriate for this data.

**On-device inference ties privacy to architecture, not policy.**

Firestore is only used for device-to-device sync. AI inference never runs in the cloud.

---

## 🔍 Transparent Risk Model (No ML Training)

We deliberately chose not to use a trained risk model. Every risk score is a publicly auditable formula:

```
predicted_risk(cell, t) = base_risk(cell) × surge_factor(cell, t) × time_factor(t)
```

| Factor | Formula | Default |
|---|---|---|
| `categoryWeight` | violence: 1.0 / theft: 0.8 / harassment: 0.7 / suspicious: 0.5 / vandalism: 0.4 / other: 0.3 | constant |
| `severityWeight` | high: 1.0 / medium: 0.7 / low: 0.4 | constant |
| `decay` | `exp(−days_old / 7)` | 7-day half-life |
| `reputationFor(uid)` | `clamp([0.5, 1.5])` | per-user |
| `surgeFactor` | `1 + min(2.0, last_2h_count × 0.3)` | max 3.0 |
| `timeFactor` | `22:00 ≤ t < 05:00` → **1.5**, otherwise 1.0 | night multiplier |

**The user interface shows these numbers as-is.** Trust the formula, not us.

This is especially critical for safety applications: opaque "AI safety scores" create an illusion of neutrality while hiding bias. Open formulas are auditable.

---

## 🗺️ Route Planning

### Algorithm

```
RoutingService.findRoutes(from, to, time)
  ├─ OsmGraph.nearestNode(from), nearestNode(to)   ← snap to walkable path
  ├─ YenKShortestPaths(K=5)                         ← A* base + spur paths
  ├─ Collect geohash cells crossed by all candidates
  ├─ RiskEngine.predictedRisk(cell, time)           ← pre-compute cache
  ├─ RiskRerank: cost = length + α × Σ risk         ← α default 100m
  ├─ GemmaService.summarizeCell (E4B)               ← top-3 avoided cells
  └─ RouteResult { shortest, safest, avoidedCells, explanation }
```

- **OSM graph:** `app/assets/road_graph.bin` (~1.1 MB Beşiktaş pedestrian network), generated from osmium via `tools/extract_osm.py`
- **A\*:** `astar.dart` + Haversine heuristic + custom `MinHeap` — pure Dart, no external dependencies
- **Yen K-Shortest:** 5 alternative paths; `risk_rerank.dart` recomputes cost for each as `distance + α × risk`

### 3-Layer Explanation

When "Why is this safer?" is tapped:

| Layer | Content |
|---|---|
| **1. Route level** | E4B summary + number of avoided cells, night multiplier, surge multiplier, distance difference |
| **2. Cell level** | Tapping any avoided area shows the community reports feeding that cell + Gemma's neutral explanation |
| **3. Temporal** | `base × 1.5 night × 2.0 surge` multipliers shown verbatim |

The app never says **"AI thinks that..."**. It directly **quotes** the numbers and the model.

---

## 🏗️ Architecture

### Boot Sequence

```
1. WidgetsFlutterBinding.ensureInitialized()
2. GemmaService init       ← check if weights already exist
3. LocalDb open            ← sqflite migrations
4. Firebase.initializeApp  ← skip if unavailable (graceful)
5. SeedLoader.ensureSeeded ← load 50 synthetic reports on first launch
6. GemmaService.warmUp     ← keep E2B engine warm
7. runApp(ProviderScope(overrides: [...realProviders...]))
```

### Storage Layer — Offline-First

```
┌────────────────────────────────────┐
│ SQLite (sqflite) — source of truth │   ← all writes here, < 100ms
│   tables: reports, risk_cells,     │
│           classifications, sync    │
└──────────────┬─────────────────────┘
               │ mirror (async, with retry)
               ▼
┌────────────────────────────────────┐
│ Firestore — sync only              │   ← cross-device distribution
│ Anonymous Auth UID = per device    │
└────────────────────────────────────┘
```

### Dependency Inversion — `*Like` Provider Pattern

```
features/providers.dart   ← *Like abstract interfaces
                            ReportsRepositoryLike, RiskEngineLike,
                            RoutingServiceLike, GemmaServiceLike...

app/real_providers.dart   ← Adapters: wrap real classes to match Like

main.dart                 ← ProviderScope.overrideWith(...)
```

The UI always binds to the `*Like` interface. Test fixtures return mock Likes. Modules evolve independently.

### Emergency Button

```
EmergencyAction.trigger()
  1. LocationService.currentPosition() → current location
  2. Automatic classification (Gemma skipped):
     {category: violence, riskLevel: high, confidence: 1.0}
  3. ReportsRepository.submitClassified() → directly CLASSIFIED
  4. EmergencyContactStorage → saved phone number
  5. SMS deeplink:
     sms:<phone>?body=Emergency. My location: https://maps.google.com/?q=<lat>,<lng>
  6. url_launcher → native SMS app opens
```

In a critical situation, inference latency is unacceptable — the report is filed directly.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.41.7 (Dart 3) + Material 3 |
| On-device AI | Gemma 4 E2B + E4B — flutter_gemma 0.13.6 + MediaPipe LiteRT |
| State management | Riverpod |
| Navigation (UI) | go_router |
| Maps | flutter_map + OpenStreetMap + latlong2 |
| Place search | Nominatim (OSM geocoding) |
| Location | geolocator |
| Routing algorithm | Dart A* + Yen K-Shortest + custom MinHeap |
| Graph source | osmium-tool (Python) → binary asset |
| Local storage | sqflite (offline-first) |
| Sync | Firebase Firestore + Anonymous Auth |
| Code generation | freezed |
| Testing | flutter_test + integration_test (real Pixel 7 inference) |

---

## 🚀 Setup

### Requirements

- **Android Studio Hedgehog (2023.1) or later**
- **Flutter SDK** ^3.11.5 (Dart 3) — must be on PATH
- **Android device, 6 GB+ RAM** — Gemma 4 E4B requires ~4 GB (Pixel 7+ recommended)
- ~7 GB free storage (model weights)
- Wi-Fi connection for initial setup

> **Note:** iOS requires a real device (MediaPipe GPU is not supported in Simulator). Web build is for UI smoke testing only — Gemma does not run on web.

### 1. Android Studio Setup

Add Flutter and Dart plugins:
```
Settings → Plugins → Marketplace → search "Flutter" → Install
```
The Dart plugin installs automatically. Restart the IDE.

### 2. Clone and Open

```bash
git clone https://github.com/aybukeyy/saferoute.git
cd saferoute
```

In Android Studio: **File → Open** → select the `saferoute/app` folder (project root is `app/`).

```bash
# Install dependencies (Android Studio triggers this automatically; or manually:)
cd app
flutter pub get

# Verify setup — all checks should be green
flutter doctor
```

### 3. Manual Setup (required)

**Firebase config** — not in repo (`.gitignore`):
```bash
cd app
flutterfire configure --project=<your-project-id>
```
This generates `firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist`.
In Firebase Console, enable **Firestore + Anonymous Auth**.

**OSM road graph** — not in repo (`.gitignore`):
```bash
cd tools
pip install -r requirements.txt
python extract_osm.py
# → generates app/assets/road_graph.bin
```

**Gemma 4 weights** — not bundled, downloaded automatically on first launch (~6 GB total):
- `gemma-4-e2b.litertlm` (~2.58 GB)
- `gemma-4-e4b.litertlm` (~3.65 GB)

If the download is interrupted, it resumes via `Range` header. Tapping "Skip" allows the app to run with map + heatmap features only, without AI.

### 4. Run

Select a device in Android Studio's top bar → **Run** (`Shift+F10`) or **Debug** (`Shift+F9`).

CLI alternative:
```bash
cd app
flutter run              # on connected device
flutter run -d chrome    # web (Gemma does not run)
flutter run --release    # release mode (inference ~2x faster)
```

### Adding a New Region

```bash
cd tools
python extract_osm.py --bbox <min_lon>,<min_lat>,<max_lon>,<max_lat>

# Then update:
# app/assets/road_graph.bin
# app/assets/seed_reports.json
# app/lib/features/map/map_screen.dart → kDefaultMapCenter
```

### Troubleshooting

| Issue | Fix |
|---|---|
| `flutter doctor` Android toolchain error | Android Studio → SDK Manager → SDK Tools → install "Android SDK Command-line Tools" |
| `Gradle build failed` | `cd app/android && ./gradlew clean` → Android Studio "Sync Project with Gradle Files" |
| `Firebase config not found` | `flutterfire configure` has not been run — see Manual Setup above |
| Gemma model fails to load | Internet connection + at least ~7 GB free disk space required |
| `road_graph.bin not found` | Run `python tools/extract_osm.py` |

---

## 📊 Evaluation

Classification accuracy was measured on a 100-report eval set on **real hardware (Pixel 7)**. Test harness: `app/eval/`

| Metric | E2B |
|---|---|
| Category accuracy | XX% |
| Risk level accuracy | XX% |
| Average inference latency | ~3.1s |
| End-to-end (report → other device pulse) | < 5s |

> The eval dataset and test harness are open in the repo — results are fully reproducible.

---

## ⚠️ Known Limitations

| Limitation | Status |
|---|---|
| Coverage limited to Beşiktaş, Istanbul | New region: `tools/extract_osm.py --bbox <bbox>` |
| ~2s cold start on E2B↔E4B swap | 5min E4B cache throttles calls |
| Gemma does not run in iOS Simulator | Real iPhone required |
| Firestore rate limiting is client-side only | Server-side planned post-hackathon |
| User reputation update is read-only | Cloud Functions planned post-hackathon |
| Model re-downloads on APK reinstall | Workaround: emulator snapshot |
| Gemma does not run in web build | For UI smoke testing only |

---

<div align="center">

Built with ❤️ for safer streets

**Hackathon project** · [GitHub](https://github.com/aybukeyy/saferoute) · [Demo Video](https://youtube.com/...) · [`SYSTEM.md`](SYSTEM.md)

</div>
