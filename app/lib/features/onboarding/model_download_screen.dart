// First-launch onboarding screen. Downloads the two Gemma 4 weights into
// the per-app local storage directory then routes the user to MapScreen.
//
// State machine (StateNotifier-driven):
//   initial    → Download CTA + Wi-Fi warning + "Skip" link.
//   downloading → progress bar (E2B 0–50%, E4B 50–100%) + cancel.
//   error      → message + retry. The partial file is preserved on disk so
//                retry resumes (when the server honours Range).
//   complete   → brief "Hazır" then auto-navigate to '/'.
//
// Why sequential and not parallel?
//   - Bandwidth: parallel halves the per-stream throughput on a typical
//     home Wi-Fi link, doubling user wait time perceived.
//   - Memory pressure: two large download buffers + write streams on a
//     mid-range Android phone hits the ~150 MB allocation ceiling.
//   - Resumability: a single-track progress bar with two phases is easier
//     to communicate than a two-bar UI.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../ai/model_storage.dart';

// ---------------------------------------------------------------------------
// State machine.
// ---------------------------------------------------------------------------

enum ModelDownloadPhase { initial, downloading, error, complete }

@immutable
class ModelDownloadState {
  const ModelDownloadState({
    this.phase = ModelDownloadPhase.initial,
    this.activeModelKey,
    this.modelDisplayName,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.progress,
    this.totalProgress = 0.0,
    this.errorMessage,
    this.startedAt,
  });

  /// Current phase of the download flow.
  final ModelDownloadPhase phase;

  /// Manifest key currently being downloaded (e.g. `gemma-4-e2b`). `null`
  /// outside the [ModelDownloadPhase.downloading] phase.
  final String? activeModelKey;

  /// Human-readable label of the active model — surfaced in the UI under
  /// the progress bar.
  final String? modelDisplayName;

  /// Per-file bytes for the current model.
  final int bytesDownloaded;
  final int? totalBytes;

  /// Per-file progress 0..1 (or null if total unknown).
  final double? progress;

  /// Combined progress across all models, 0..1. With 2 models, E2B fills
  /// 0..0.5 and E4B fills 0.5..1.
  final double totalProgress;

  final String? errorMessage;
  final DateTime? startedAt;

  ModelDownloadState copyWith({
    ModelDownloadPhase? phase,
    String? activeModelKey,
    String? modelDisplayName,
    int? bytesDownloaded,
    int? totalBytes,
    double? progress,
    double? totalProgress,
    String? errorMessage,
    DateTime? startedAt,
    bool clearError = false,
  }) =>
      ModelDownloadState(
        phase: phase ?? this.phase,
        activeModelKey: activeModelKey ?? this.activeModelKey,
        modelDisplayName: modelDisplayName ?? this.modelDisplayName,
        bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
        totalBytes: totalBytes ?? this.totalBytes,
        progress: progress ?? this.progress,
        totalProgress: totalProgress ?? this.totalProgress,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        startedAt: startedAt ?? this.startedAt,
      );
}

/// Drives [ModelDownloadScreen]. Consumes [ModelStorage.download] streams
/// in sequence (E2B first, then E4B). Cancellation tears down the active
/// stream subscription; the partial file remains on disk for next-launch
/// resume.
class ModelDownloadController extends StateNotifier<ModelDownloadState> {
  ModelDownloadController({
    required ModelStorage storage,
    required ModelManifest manifest,
  })  : _storage = storage,
        _manifest = manifest,
        super(const ModelDownloadState());

  final ModelStorage _storage;
  final ModelManifest _manifest;
  StreamSubscription<ModelDownloadProgress>? _sub;
  bool _cancelled = false;

  /// Stable order so progress allocation is deterministic. We deliberately
  /// don't use Map iteration order (manifest may be re-ordered by Agent B).
  static const List<String> _orderedKeys = ['gemma-4-e2b', 'gemma-4-e4b'];

  /// Kick off the full download sequence. Idempotent: a no-op if a
  /// download is already in flight.
  Future<void> start() async {
    if (state.phase == ModelDownloadPhase.downloading) return;
    _cancelled = false;
    state = state.copyWith(
      phase: ModelDownloadPhase.downloading,
      totalProgress: 0.0,
      bytesDownloaded: 0,
      totalBytes: null,
      progress: null,
      startedAt: DateTime.now(),
      clearError: true,
    );

    final keys =
        _orderedKeys.where((k) => _manifest.models.containsKey(k)).toList();
    if (keys.isEmpty) {
      state = state.copyWith(
        phase: ModelDownloadPhase.error,
        errorMessage: 'No models declared in manifest.',
      );
      return;
    }

    final sliceSize = 1.0 / keys.length;

    for (var i = 0; i < keys.length; i++) {
      if (_cancelled) return;
      final key = keys[i];
      final cfg = _manifest.models[key]!;
      final startSlice = sliceSize * i;
      final ok = await _downloadOne(
        key: key,
        cfg: cfg,
        sliceStart: startSlice,
        sliceSize: sliceSize,
      );
      if (!ok) return; // _downloadOne already updated state to error/cancel.
    }

    if (_cancelled) return;
    state = state.copyWith(
      phase: ModelDownloadPhase.complete,
      totalProgress: 1.0,
    );
  }

  Future<bool> _downloadOne({
    required String key,
    required ModelConfig cfg,
    required double sliceStart,
    required double sliceSize,
  }) async {
    if (cfg.isPlaceholder) {
      state = state.copyWith(
        phase: ModelDownloadPhase.error,
        errorMessage:
            'Model URL not configured for $key. See MANUAL_SETUP.md §2.',
      );
      return false;
    }

    state = state.copyWith(
      activeModelKey: key,
      modelDisplayName: cfg.displayName,
      bytesDownloaded: 0,
      totalBytes: cfg.sizeBytes > 0 ? cfg.sizeBytes : null,
      progress: 0.0,
      totalProgress: sliceStart,
    );

    final completer = Completer<bool>();
    final stream = _storage.download(
      url: cfg.url,
      filename: cfg.filename,
      expectedSize: cfg.sizeBytes > 0 ? cfg.sizeBytes : null,
      sha256: cfg.hasSha256 ? cfg.sha256 : null,
    );

    _sub = stream.listen(
      (event) {
        if (_cancelled) return;
        if (event.error != null) {
          state = state.copyWith(
            phase: ModelDownloadPhase.error,
            errorMessage: event.error,
          );
          if (!completer.isCompleted) completer.complete(false);
          return;
        }
        final perFile = event.progress ?? 0.0;
        state = state.copyWith(
          bytesDownloaded: event.bytesDownloaded,
          totalBytes: event.totalBytes ?? state.totalBytes,
          progress: event.progress,
          totalProgress: (sliceStart + perFile * sliceSize).clamp(0.0, 1.0),
        );
        if (event.done) {
          if (!completer.isCompleted) completer.complete(true);
        }
      },
      onError: (Object e, StackTrace st) {
        state = state.copyWith(
          phase: ModelDownloadPhase.error,
          errorMessage: e.toString(),
        );
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    final result = await completer.future;
    await _sub?.cancel();
    _sub = null;
    return result;
  }

  /// Cancel the in-flight download. Leaves the `.partial` on disk so the
  /// next call to [start] resumes via Range header.
  Future<void> cancel() async {
    _cancelled = true;
    await _sub?.cancel();
    _sub = null;
    state = state.copyWith(
      phase: ModelDownloadPhase.initial,
      clearError: true,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Riverpod wiring.
// ---------------------------------------------------------------------------

final modelDownloadControllerProvider = StateNotifierProvider.autoDispose<
    ModelDownloadController, ModelDownloadState>((ref) {
  final storage = ref.watch(modelStorageProvider);
  final manifestAsync = ref.watch(modelManifestProvider);
  final manifest = manifestAsync.maybeWhen(
    data: (m) => m,
    orElse: () => const ModelManifest(version: 0, models: {}),
  );
  return ModelDownloadController(storage: storage, manifest: manifest);
});

// ---------------------------------------------------------------------------
// Screen.
// ---------------------------------------------------------------------------

class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  bool _navigatedToHome = false;

  @override
  Widget build(BuildContext context) {
    // Watch the manifest so we can render the Wi-Fi warning copy with the
    // right total MB before the user taps Download.
    final manifestAsync = ref.watch(modelManifestProvider);
    final state = ref.watch(modelDownloadControllerProvider);

    // Auto-navigate after the brief "complete" flash so the user lands on
    // MapScreen without an extra tap.
    if (state.phase == ModelDownloadPhase.complete && !_navigatedToHome) {
      _navigatedToHome = true;
      // Capture the router up front — the BuildContext-across-async lint
      // gets unhappy if we touch `context` after the awaited delay.
      final router = GoRouter.of(context);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        // Invalidate the availability provider so any banner the MapScreen
        // listens to flips to "ready".
        ref.invalidate(modelsAvailableProvider);
        router.go('/');
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: manifestAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, st) => _ErrorView(
              message: 'Manifest yüklenemedi: $e',
              onRetry: () => ref.invalidate(modelManifestProvider),
            ),
            data: (manifest) =>
                _Body(manifest: manifest, state: state),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.manifest, required this.state});

  final ModelManifest manifest;
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(modelDownloadControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Center(
          child: Icon(Icons.shield, size: 56, color: scheme.primary),
        ),
        const SizedBox(height: 12),
        Text(
          'Safe Route ilk kullanım',
          style: tt.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          "AI modeli telefonunuzda çalışır — internet üzerinden veri göndermez.",
          style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Expanded(child: _PhaseView(manifest: manifest, state: state)),
        const SizedBox(height: 16),
        _Actions(state: state, controller: controller, manifest: manifest),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PhaseView extends StatelessWidget {
  const _PhaseView({required this.manifest, required this.state});

  final ModelManifest manifest;
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case ModelDownloadPhase.initial:
        return _InitialView(manifest: manifest);
      case ModelDownloadPhase.downloading:
        return _DownloadingView(state: state);
      case ModelDownloadPhase.error:
        return _ErrorView(
          message: state.errorMessage ?? 'Bilinmeyen bir hata oluştu.',
          onRetry: null, // Retry is exposed via the bottom action button.
        );
      case ModelDownloadPhase.complete:
        return const _CompleteView();
    }
  }
}

class _InitialView extends StatelessWidget {
  const _InitialView({required this.manifest});

  final ModelManifest manifest;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final totalMb = manifest.totalApproximateMb;
    final totalGb = (totalMb / 1024).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.download_for_offline,
            size: 48, color: scheme.primary),
        const SizedBox(height: 12),
        Text('AI modelini indir', style: tt.titleLarge),
        const SizedBox(height: 8),
        Text(
          "Gemma 4 — Google'ın açık ağırlıklı modeli, telefonda çalışır. "
          'İndirme sonrası tamamen çevrimdışı sınıflandırma yapar.',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi, color: scheme.tertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Wi-Fi öneriyoruz — toplam ~$totalGb GB indirilecek.',
                  style: tt.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in manifest.models.entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.memory),
            title: Text(entry.value.displayName),
            subtitle: Text('~${entry.value.approximateMb} MB'),
          ),
      ],
    );
  }
}

class _DownloadingView extends StatelessWidget {
  const _DownloadingView({required this.state});

  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final received = _formatBytes(state.bytesDownloaded);
    final total = state.totalBytes != null
        ? _formatBytes(state.totalBytes!)
        : '?';
    final pctText = state.progress != null
        ? '${(state.totalProgress * 100).toStringAsFixed(0)}%'
        : '...';
    final eta = _estimateRemaining(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.settings, color: scheme.primary),
            const SizedBox(width: 8),
            Text('AI modelini indiriyor', style: tt.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        if (state.modelDisplayName != null)
          Text(state.modelDisplayName!, style: tt.bodyLarge),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: state.totalProgress > 0 ? state.totalProgress : null,
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(pctText, style: tt.titleMedium),
            Text('$received / $total', style: tt.bodyMedium),
          ],
        ),
        if (eta != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16),
              const SizedBox(width: 6),
              Text('~$eta kaldı', style: tt.bodyMedium),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Wi-Fi öneriyoruz. İndirmeyi durdurursanız ilerleme kaydedilir; '
          'sonra kaldığınız yerden devam edebilirsiniz.',
          style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String? _estimateRemaining(ModelDownloadState s) {
    if (s.startedAt == null || s.totalProgress <= 0.01) return null;
    final elapsed = DateTime.now().difference(s.startedAt!).inSeconds;
    if (elapsed < 2) return null;
    final remainingFrac = (1.0 - s.totalProgress).clamp(0.0, 1.0);
    final remainingSec =
        (elapsed / s.totalProgress * remainingFrac).round();
    if (remainingSec < 60) return '${remainingSec}s';
    final m = remainingSec ~/ 60;
    if (m < 60) return '${m}dk';
    final h = m ~/ 60;
    return '${h}sa ${m % 60}dk';
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline, color: scheme.error, size: 48),
        const SizedBox(height: 12),
        Text('İndirme başarısız oldu',
            style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: tt.bodyMedium?.copyWith(color: scheme.onErrorContainer),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'İpucu: Wi-Fi bağlantınızı kontrol edin. İlerleme kaydedildi; '
          'tekrar başlatmak kaldığınız yerden devam eder.',
          style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      ],
    );
  }
}

class _CompleteView extends StatelessWidget {
  const _CompleteView();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle, color: scheme.primary, size: 72),
        const SizedBox(height: 16),
        Text('Hazır', style: tt.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Modeller telefonunuza yüklendi. Ana ekrana yönlendiriliyorsunuz...',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.controller,
    required this.manifest,
  });

  final ModelDownloadState state;
  final ModelDownloadController controller;
  final ModelManifest manifest;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case ModelDownloadPhase.initial:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: () => controller.start(),
              icon: const Icon(Icons.download),
              label: const Text('Modelleri indir'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Atla (sonra indir)'),
            ),
          ],
        );
      case ModelDownloadPhase.downloading:
        return OutlinedButton.icon(
          onPressed: () => controller.cancel(),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('İndirmeyi durdur'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        );
      case ModelDownloadPhase.error:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: () => controller.start(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Atla (sonra indir)'),
            ),
          ],
        );
      case ModelDownloadPhase.complete:
        return const SizedBox.shrink();
    }
  }
}
