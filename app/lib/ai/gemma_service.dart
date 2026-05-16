// Cactus-style on-device router between Gemma 4 E2B and Gemma 4 E4B.
//
// "Cactus" (one of the Gemma 4 Good Hackathon Special Tech tracks) rewards
// **local-first mobile apps that intelligently route tasks between models**.
// This file is exactly that:
//
//   * Mode 1 — short, latency-sensitive **per-report classification** is sent
//     to **Gemma 4 E2B** (~2.4 GB on-device, ~3 s on a Pixel 7-class phone).
//   * Mode 2 — longer, quality-sensitive **per-area summaries** are sent to
//     **Gemma 4 E4B** (~4.3 GB on-device, ~7 s, cached 5 min per cell).
//
// Both run via `flutter_gemma`, which wraps MediaPipe LLM Inference on top of
// LiteRT (Google AI Edge's runtime). On phones the package only keeps **one**
// inference engine warm at a time (`_initializedModel` is a singleton), so the
// router hot-swaps the active model spec when the requested mode changes —
// closing the previous handle to free RAM before loading the next.
//
// Single-flight: even if the UI fires three classification requests in
// parallel, only one inference is in flight at a time. The other two await a
// `Completer` instead of racing the native engine. Same lock guards summary
// calls.
//
// All locked prompts live in `prompts.dart`; the JSON parser + safe-default
// fallback live in `parser.dart`. This file is the orchestrator.
//
// Source-of-truth docs:
//   - docs/planning/IMPLEMENTATION.md §3 (Gemma 4 Usage)
//   - docs/planning/ARCHITECTURE.md     §2.2 (On-Device AI, Cactus-style)

import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/classification.dart';
import '../models/report.dart';
import 'model_storage.dart';
import 'parser.dart';
import 'prompts.dart';

/// Discriminator for the two Gemma 4 weights we route between.
enum GemmaMode { e2b, e4b }

/// Filenames of the two `.task` model bundles inside the on-device model
/// storage directory (resolved by [ModelStorage]). These are downloaded at
/// runtime by the onboarding screen — see `docs/planning/MANUAL_SETUP.md §2`.
class _ModelFiles {
  static const String e2b = 'gemma-4-e2b.litertlm';
  static const String e4b = 'gemma-4-e4b.litertlm';

  /// Manifest key in `assets/model_config.json` for [filename].
  static String keyFor(String filename) => switch (filename) {
        e2b => 'gemma-4-e2b',
        e4b => 'gemma-4-e4b',
        _ => filename,
      };
}

/// Cached Mode-2 summary entry. 5-minute TTL, see [GemmaService.summarizeCell].
class _SummaryCacheEntry {
  final String summary;
  final DateTime at;
  const _SummaryCacheEntry(this.summary, this.at);
}

/// On-device router for the two Gemma 4 inference paths. See file header.
class GemmaService {
  GemmaService({
    GemmaClassificationParser parser = const GemmaClassificationParser(),
    Duration summaryTtl = const Duration(minutes: 5),
    ModelStorage? storage,
  })  : _parser = parser,
        _summaryTtl = summaryTtl,
        _storage = storage ?? ModelStorage();

  // -- Dependencies --

  final GemmaClassificationParser _parser;
  final Duration _summaryTtl;

  /// Resolves the absolute file path of each `.task` weight on disk and
  /// answers presence checks. Injected for tests.
  final ModelStorage _storage;

  // -- Mutable state --

  /// Which mode is currently warm in the underlying singleton engine. `null`
  /// means nothing is loaded yet.
  GemmaMode? _activeMode;

  /// Active-mode singleton handle. Same identity as
  /// `FlutterGemmaPlugin.instance.initializedModel` but cached locally so we
  /// don't have to round-trip through the manager on every call.
  InferenceModel? _activeModel;

  /// Single-flight lock. Exactly one inference may be in flight against the
  /// underlying engine at a time — concurrent callers chain on this future.
  Future<void>? _inflight;

  /// 5-minute area-summary cache, keyed by geohash-7.
  final Map<String, _SummaryCacheEntry> _summaryCache = {};

  /// Set after the E2B install path has been kicked off once. Subsequent
  /// `warmUpE2B()` calls become no-ops.
  bool _e2bInstalled = false;
  bool _e4bInstalled = false;

  bool _disposed = false;

  // -- Public API ---------------------------------------------------------

  /// Eagerly install the E2B `.task` asset and put the inference engine in a
  /// state where the next `classify()` call only pays per-call latency, not
  /// the install + cold-load cost.
  ///
  /// Safe to call from app boot. Idempotent.
  Future<void> warmUpE2B() async {
    _ensureNotDisposed();
    await _ensureInstalled(GemmaMode.e2b);
    await _ensureActive(GemmaMode.e2b);
  }

  /// Same as [warmUpE2B] but for the bigger E4B summariser. Typically called
  /// lazily the first time the UI requests an area summary so the user
  /// doesn't pay a ~4 GB load cost at boot.
  Future<void> warmUpE4B() async {
    _ensureNotDisposed();
    await _ensureInstalled(GemmaMode.e4b);
    await _ensureActive(GemmaMode.e4b);
  }

  /// Mode 1 — Gemma 4 E2B classification. Returns a [Classification] that is
  /// guaranteed to be non-null (the parser falls back to a safe default with
  /// `needsReview = true` after one retry).
  Future<Classification> classify({
    required String text,
    required double lat,
    required double lng,
    required DateTime occurredAt,
  }) async {
    _ensureNotDisposed();
    final userPrompt = GemmaPrompts.classifyUser(
      text: text,
      lat: lat,
      lng: lng,
      occurredAt: occurredAt,
    );

    return _withInferenceLock<Classification>(() async {
      await _ensureInstalled(GemmaMode.e2b);
      await _ensureActive(GemmaMode.e2b);
      final model = _activeModel!;
      final stopwatch = Stopwatch()..start();

      final raw1 = await _runOnce(
        model: model,
        systemPrompt: GemmaPrompts.classifySystem,
        userPrompt: userPrompt,
        // Tighten sampling for JSON-mode-style determinism. flutter_gemma 0.13
        // does not expose a hard "JSON mode" toggle, so we lean on low
        // temperature + topP to discourage prose drift.
        temperature: 0.1,
        topP: 0.9,
        topK: 32,
      );
      final outcome1 = _parser.parse(raw1);
      if (outcome1 is ParseSuccess) {
        debugPrint(
            '[GemmaService] classify ok in ${stopwatch.elapsedMilliseconds} ms');
        return outcome1.classification;
      }
      debugPrint(
          '[GemmaService] classify parse failed (${(outcome1 as ParseFailure).reason}) — retrying once');

      final raw2 = await _runOnce(
        model: model,
        systemPrompt: GemmaPrompts.classifySystem,
        userPrompt: userPrompt,
        temperature: 0.0, // deterministic on retry
        topP: 0.9,
        topK: 32,
      );
      final outcome2 = _parser.parse(raw2);
      if (outcome2 is ParseSuccess) {
        debugPrint(
            '[GemmaService] classify ok on retry in ${stopwatch.elapsedMilliseconds} ms');
        return outcome2.classification;
      }
      debugPrint(
          '[GemmaService] classify retry also failed (${(outcome2 as ParseFailure).reason}); using safe default. Total ${stopwatch.elapsedMilliseconds} ms');
      return GemmaClassificationParser.safeDefault;
    });
  }

  /// Mode 2 — Gemma 4 E4B per-cell summary, cached 5 minutes per geohash.
  ///
  /// `recentReports` is the same window the heatmap renders from; passing it
  /// in (rather than re-querying SQLite here) keeps the AI module test-friendly
  /// and free of `data/` imports.
  Future<String> summarizeCell({
    required String geohash7,
    required List<Report> recentReports,
    required bool isNight,
    int hours = 6,
  }) async {
    _ensureNotDisposed();

    // Cache hit?
    final cached = _summaryCache[geohash7];
    if (cached != null && DateTime.now().difference(cached.at) < _summaryTtl) {
      return cached.summary;
    }

    final tuples = recentReports
        .map((r) => (
              category: r.category != null
                  ? GemmaPrompts.wireCategory(r.category!)
                  : 'other',
              level: r.riskLevel != null
                  ? GemmaPrompts.wireRiskLevel(r.riskLevel!)
                  : 'low',
              text: r.text,
            ))
        .toList(growable: false);

    final userPrompt = GemmaPrompts.summarizeUser(
      geohash: geohash7,
      hours: hours,
      night: isNight,
      reports: tuples,
    );

    return _withInferenceLock<String>(() async {
      await _ensureInstalled(GemmaMode.e4b);
      await _ensureActive(GemmaMode.e4b);
      final model = _activeModel!;
      final stopwatch = Stopwatch()..start();

      final raw = await _runOnce(
        model: model,
        systemPrompt: GemmaPrompts.summarizeSystem,
        userPrompt: userPrompt,
        // Slightly more freedom for prose; still conservative.
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
      );

      final summary = raw.trim();
      _summaryCache[geohash7] = _SummaryCacheEntry(summary, DateTime.now());
      debugPrint(
          '[GemmaService] summarize ok in ${stopwatch.elapsedMilliseconds} ms (cell=$geohash7)');
      return summary;
    });
  }

  /// Tear down the warm engine and clear caches. Call from app shutdown / test
  /// teardown. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _summaryCache.clear();
    final model = _activeModel;
    _activeModel = null;
    _activeMode = null;
    if (model != null) {
      try {
        await model.close();
      } catch (e) {
        debugPrint('[GemmaService] model.close() during dispose threw: $e');
      }
    }
  }

  // -- Internals ----------------------------------------------------------

  /// Run a single classification or summary inference. Builds a fresh session
  /// per call so prompt history never leaks between Mode 1 and Mode 2 —
  /// classifications are pure functions of their input.
  Future<String> _runOnce({
    required InferenceModel model,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
    required double topP,
    required int topK,
  }) async {
    final session = await model.createSession(
      temperature: temperature,
      topP: topP,
      topK: topK,
      randomSeed: 1,
      systemInstruction: systemPrompt,
    );
    try {
      await session.addQueryChunk(GemmaPrompts.asUserMessage(userPrompt));
      return await session.getResponse();
    } finally {
      try {
        await session.close();
      } catch (e) {
        debugPrint('[GemmaService] session.close() threw: $e');
      }
    }
  }

  /// Make sure the requested mode is installed in flutter_gemma's model
  /// registry. Resolves the on-disk path via [ModelStorage] and registers
  /// the file with `installModel().fromFile(...)`.
  ///
  /// Throws [ModelMissingException] if the file isn't present yet — UI
  /// catches this and routes to the onboarding download screen rather than
  /// crashing the app.
  Future<void> _ensureInstalled(GemmaMode mode) async {
    final installed = mode == GemmaMode.e2b ? _e2bInstalled : _e4bInstalled;
    if (installed) return;

    final filename =
        mode == GemmaMode.e2b ? _ModelFiles.e2b : _ModelFiles.e4b;

    // Pre-flight presence check so we surface the typed
    // ModelMissingException before going through flutter_gemma's native
    // path. Fast existence + size check only — sha256 was verified at
    // download time.
    if (!await _storage.isPresent(filename)) {
      debugPrint(
          '[GemmaService] $filename not on disk — surfacing ModelMissingException');
      throw ModelMissingException(
        modelKey: _ModelFiles.keyFor(filename),
        detail: 'See docs/planning/MANUAL_SETUP.md §2',
      );
    }

    final localPath = await _storage.resolveLocalPath(filename);

    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(localPath)
          .install();
    } catch (e) {
      debugPrint('[GemmaService] FAILED to install $localPath: $e\n'
          'Gemma weights present but flutter_gemma rejected them — '
          'see docs/planning/MANUAL_SETUP.md §2.');
      // Surface as ModelMissingException so the UI can offer a
      // re-download. The original error is preserved in `detail`.
      throw ModelMissingException(
        modelKey: _ModelFiles.keyFor(filename),
        detail: 'flutter_gemma install failed: $e',
      );
    }

    if (mode == GemmaMode.e2b) {
      _e2bInstalled = true;
    } else {
      _e4bInstalled = true;
    }
    debugPrint('[GemmaService] installed local file for mode=$mode '
        '($localPath)');
  }

  /// Make sure [mode] is the currently warm engine. Hot-swaps if needed:
  /// closes the existing model, points the manager at the other spec, then
  /// loads.
  ///
  /// Logs cold-start latency on first load — Week-3 benchmarks consume this.
  Future<void> _ensureActive(GemmaMode mode) async {
    if (_activeMode == mode && _activeModel != null) return;

    // Hot-swap: close any model currently warm in the engine.
    if (_activeModel != null) {
      debugPrint(
          '[GemmaService] hot-swap: closing $_activeMode before loading $mode');
      try {
        await _activeModel!.close();
      } catch (e) {
        debugPrint('[GemmaService] previous model.close() threw: $e');
      }
      _activeModel = null;
      _activeMode = null;
    }

    // Re-install (idempotent in flutter_gemma) so the manager's `activeSpec`
    // points at the mode we're about to load. `install()` is cheap when the
    // model is already on disk — it just calls `setActiveModel(spec)`.
    await _ensureInstalled(mode);

    final cold = Stopwatch()..start();
    // Android emülatöründe OpenCL yok → GPU backend fails. Debug build'de CPU'ya düş.
    final backend = kDebugMode ? PreferredBackend.cpu : PreferredBackend.gpu;
    final model = await FlutterGemma.getActiveModel(
      // Generous context: classify prompts are ~300 tokens, summary prompts
      // grow with report count. 2048 is a safe upper bound for both modes.
      maxTokens: 2048,
      preferredBackend: backend,
    );
    debugPrint(
        '[GemmaService] cold-start mode=$mode in ${cold.elapsedMilliseconds} ms');

    _activeModel = model;
    _activeMode = mode;

    // Sanity check the underlying file exists for clearer error messages
    // during development. The manager already validates this internally, but
    // a friendly log line saves time when the asset is missing.
    final paths = await FlutterGemmaPlugin.instance.modelManager
        .getModelFilePaths(
          FlutterGemmaPlugin.instance.modelManager.activeInferenceModel!,
        );
    final firstPath = paths?.values.firstOrNull;
    if (firstPath != null && !await File(firstPath).exists()) {
      debugPrint('[GemmaService] WARNING: active model path $firstPath '
          'does not exist on disk — did the install step fail silently?');
    }
  }

  /// Serialise inference calls. Two callers in parallel ⇒ second one waits.
  Future<T> _withInferenceLock<T>(Future<T> Function() body) async {
    final previous = _inflight;
    final completer = Completer<void>();
    _inflight = completer.future;
    try {
      if (previous != null) {
        await previous;
      }
      return await body();
    } finally {
      completer.complete();
      // Only clear if no one queued behind us in the meantime.
      if (identical(_inflight, completer.future)) {
        _inflight = null;
      }
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('GemmaService was disposed; create a new instance.');
    }
  }
}

// -- Riverpod wiring ---------------------------------------------------------
//
// We hand-roll the provider instead of using `@riverpod` codegen so this file
// stays compile-clean even if `riverpod_generator` hasn't been run yet (the
// skeleton notes mention `riverpod_lint` was skipped due to a 3.x conflict —
// see docs/planning/MANUAL_SETUP.md §7). The provider returns a long-lived
// instance and tears it down when the app shuts down (`autoDispose` is
// intentionally NOT used: the user pays the warm-up cost once per app boot).

final gemmaServiceProvider = Provider<GemmaService>((ref) {
  final storage = ref.watch(modelStorageProvider);
  final service = GemmaService(storage: storage);
  ref.onDispose(() {
    // Fire-and-forget; ProviderContainer.dispose() does not await us.
    unawaited(service.dispose());
  });
  return service;
});
