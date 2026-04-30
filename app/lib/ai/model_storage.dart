// Runtime model download + local-storage path resolver for the Gemma 4 weights.
//
// Why this exists:
// The Safe Route APK ships at ~30 MB. The two Gemma 4 `.task` files (~1.5 GB
// E2B + ~3 GB E4B) are *not* bundled — the user downloads them on first
// launch via the onboarding screen. This file owns:
//
//   1. The on-disk location: `getApplicationSupportDirectory()/<filename>`
//      (per-app, survives updates, NOT scanned by media scanners on Android).
//   2. The "is the file present and intact?" check — file exists + size match
//      + (optional) sha256 match.
//   3. A resumable streaming downloader emitting [ModelDownloadProgress]
//      events. Built on `dart:io HttpClient` so we don't add a new dep.
//
// The downloader writes to `<filename>.partial` and renames on success; if a
// `.partial` already exists we issue a Range request to resume from its
// length. SHA256 is verified after rename; on mismatch the file is deleted
// and an error event surfaces.
//
// flutter_gemma is *not* imported here — `gemma_service.dart` consumes the
// resolved absolute path via `installModel().fromFile(path)`. That keeps
// this module test-friendly: no native plugin call, no Pigeon wiring.
//
// Source-of-truth doc: docs/planning/MANUAL_SETUP.md §2.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// Manifest types — the parsed shape of `assets/model_config.json`.
// ---------------------------------------------------------------------------

const String _kPlaceholderSentinel = '<placeholder>';

/// One model entry in the manifest. URL + filename + integrity metadata.
@immutable
class ModelConfig {
  const ModelConfig({
    required this.url,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    required this.displayName,
    required this.approximateMb,
  });

  /// Public download URL. Placeholder string until Agent B fills it in
  /// (see `docs/planning/MANUAL_SETUP.md §2`).
  final String url;

  /// Bare filename (no directory). Resolved against the app-support dir by
  /// [ModelStorage.resolveLocalPath].
  final String filename;

  /// Expected total bytes. `0` means "unknown" — the downloader will trust
  /// the server's `Content-Length` header in that case.
  final int sizeBytes;

  /// Expected hex-encoded SHA-256 of the *complete* file. Empty string or
  /// the literal placeholder skips verification.
  final String sha256;

  /// Human-readable label for the onboarding UI.
  final String displayName;

  /// Approximate footprint in MB — used by the onboarding screen for the
  /// Wi-Fi warning copy (Total ≈ E2B + E4B mb).
  final int approximateMb;

  /// `true` if either URL or sha256 is still the placeholder. Callers can
  /// short-circuit a download attempt rather than hit a 404.
  bool get isPlaceholder =>
      url.contains(_kPlaceholderSentinel) ||
      sha256.contains(_kPlaceholderSentinel);

  /// `true` if a meaningful sha256 is present (32-byte hex, 64 chars).
  bool get hasSha256 => sha256.length == 64 && !isPlaceholder;

  factory ModelConfig.fromJson(Map<String, dynamic> json) => ModelConfig(
        url: json['url'] as String? ?? '',
        filename: json['filename'] as String? ?? '',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        approximateMb: (json['approximateMb'] as num?)?.toInt() ?? 0,
      );
}

/// Top-level manifest parsed from `assets/model_config.json`.
@immutable
class ModelManifest {
  const ModelManifest({required this.version, required this.models});

  final int version;

  /// Keyed by model id (e.g. `gemma-4-e2b`).
  final Map<String, ModelConfig> models;

  /// Convenience: total approximate MB across all entries (used by the
  /// onboarding UI for the Wi-Fi warning).
  int get totalApproximateMb =>
      models.values.fold<int>(0, (acc, m) => acc + m.approximateMb);

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    final modelsJson = (json['models'] as Map<String, dynamic>?) ?? const {};
    final parsed = <String, ModelConfig>{};
    modelsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsed[key] = ModelConfig.fromJson(value);
      }
    });
    return ModelManifest(
      version: (json['version'] as num?)?.toInt() ?? 0,
      models: Map.unmodifiable(parsed),
    );
  }

  /// Loads + parses `assets/model_config.json` from the bundle. The asset is
  /// tiny (<1 KB) so this is cheap; callers can call it eagerly at boot.
  static Future<ModelManifest> loadFromAsset({
    String assetPath = 'assets/model_config.json',
    AssetBundle? bundle,
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return ModelManifest.fromJson(decoded);
  }
}

// ---------------------------------------------------------------------------
// Progress event emitted by [ModelStorage.download].
// ---------------------------------------------------------------------------

/// One frame of download progress. The stream emits these continuously
/// (~100 ms cadence in practice) and one final event with `done == true` or
/// `error != null`.
@immutable
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.bytesDownloaded,
    this.totalBytes,
    this.progress,
    this.done = false,
    this.error,
  });

  /// Bytes received so far (resumed downloads start at the prior partial
  /// length, not 0).
  final int bytesDownloaded;

  /// Expected final size, or `null` if the server didn't supply it.
  final int? totalBytes;

  /// Convenience: bytesDownloaded / totalBytes, clamped to [0, 1]. `null`
  /// when the total is unknown — UI should fall back to an indeterminate
  /// progress bar in that case.
  final double? progress;

  /// `true` on the final event of a successful run.
  final bool done;

  /// Non-null on the final event of a failed run. Mutually exclusive with
  /// [done].
  final String? error;

  ModelDownloadProgress copyWith({
    int? bytesDownloaded,
    int? totalBytes,
    double? progress,
    bool? done,
    String? error,
  }) =>
      ModelDownloadProgress(
        bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
        totalBytes: totalBytes ?? this.totalBytes,
        progress: progress ?? this.progress,
        done: done ?? this.done,
        error: error ?? this.error,
      );
}

// ---------------------------------------------------------------------------
// Custom exception thrown by `gemma_service.dart` when a required model
// isn't on disk yet — UI catches this and routes to the onboarding screen.
// ---------------------------------------------------------------------------

class ModelMissingException implements Exception {
  const ModelMissingException({required this.modelKey, this.detail});

  /// Manifest key (`gemma-4-e2b` / `gemma-4-e4b`).
  final String modelKey;
  final String? detail;

  @override
  String toString() =>
      'ModelMissingException(modelKey=$modelKey${detail == null ? '' : ', detail=$detail'})';
}

// ---------------------------------------------------------------------------
// ModelStorage — path resolution + presence check + downloader.
//
// Hand-rolled instead of using the `http` package so we don't have to touch
// pubspec dependencies. `dart:io HttpClient` is good enough for a single
// large file with progress + Range support.
// ---------------------------------------------------------------------------

class ModelStorage {
  ModelStorage({
    Future<Directory> Function()? supportDirProvider,
    HttpClient Function()? httpClientFactory,
  })  : _supportDirProvider =
            supportDirProvider ?? getApplicationSupportDirectory,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Future<Directory> Function() _supportDirProvider;
  final HttpClient Function() _httpClientFactory;

  // -- Path resolution ----------------------------------------------------

  /// Absolute path the model would live at on disk. Does NOT check
  /// existence — call [isPresent] for that.
  Future<String> resolveLocalPath(String filename) async {
    final dir = await _supportDirProvider();
    return p.join(dir.path, filename);
  }

  /// Same as [resolveLocalPath] but appends `.partial`. Used as the temp
  /// destination during download; renamed atomically on success.
  Future<String> resolvePartialPath(String filename) async =>
      '${await resolveLocalPath(filename)}.partial';

  // -- Presence check -----------------------------------------------------

  /// `true` if the file is on disk, has the expected size (when supplied),
  /// and (when sha256 supplied) has the expected hash.
  ///
  /// SHA256 verification is potentially seconds-long for a 1.5 GB file —
  /// callers that already verified post-download should pass `sha256: null`
  /// for a fast existence + size check.
  ///
  /// In addition to size/hash, both `.task` (MediaPipe) and `.litertlm`
  /// (LiteRT-LM) bundles are ZIP containers under the hood. We sanity-check
  /// the first four bytes for the ZIP magic so a half-downloaded HTML error
  /// page (or a wrong-format stub like an HF login redirect) doesn't masquerade
  /// as a valid model and explode in flutter_gemma's native init with a
  /// "Unable to open zip archive" stack trace.
  Future<bool> isPresent(
    String filename, {
    int? expectedSize,
    String? sha256,
  }) async {
    final path = await resolveLocalPath(filename);
    final file = File(path);
    if (!await file.exists()) return false;

    if (expectedSize != null && expectedSize > 0) {
      final actual = await file.length();
      if (actual != expectedSize) {
        debugPrint('[ModelStorage] $filename size mismatch: '
            'expected=$expectedSize actual=$actual');
        return false;
      }
    }

    // Format sanity: only run for files we know should be ZIP-backed model
    // bundles. Skips the check for arbitrary filenames so unrelated test
    // fixtures (.txt, etc.) keep working with size-only checks.
    if (_isZipBackedModel(filename)) {
      if (!await _hasZipMagic(file)) {
        debugPrint(
            '[ModelStorage] $filename failed ZIP magic check — likely a wrong '
            "format download (e.g. HTML error page or '-web.task' web variant "
            'on mobile). Treating as not-present so the UI can offer a '
            're-download.');
        return false;
      }
    }

    if (sha256 != null && sha256.isNotEmpty) {
      final actual = await _computeSha256(file);
      if (actual.toLowerCase() != sha256.toLowerCase()) {
        debugPrint('[ModelStorage] $filename sha256 mismatch: '
            'expected=$sha256 actual=$actual');
        return false;
      }
    }

    return true;
  }

  /// `true` for filenames whose extension is one of the ZIP-backed flutter_gemma
  /// model formats (`.task`, `.litertlm`). These have a `PK\x03\x04` magic and
  /// are large (>1 MB); any file whose extension matches but whose first bytes
  /// don't is corrupt or wrong-format and should be re-downloaded.
  static bool _isZipBackedModel(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.task') || lower.endsWith('.litertlm');
  }

  /// Reads the first four bytes of [file] and returns `true` iff they match the
  /// standard ZIP local-file-header magic (`0x504B0304`) or the empty-archive
  /// magic (`0x504B0506`). Files smaller than 1 MB are treated as failing the
  /// check — every Gemma weight is multi-GB; a sub-megabyte `.task` is always
  /// either a partial download or a redirected HTML error body.
  Future<bool> _hasZipMagic(File file) async {
    try {
      final size = await file.length();
      if (size < 1024 * 1024) return false; // < 1 MB clearly wrong for a model
      final raf = await file.open();
      try {
        final magic = await raf.read(4);
        if (magic.length < 4) return false;
        // 'P' (0x50) 'K' (0x4B) — ZIP signature.
        // Second pair: 0x0304 (regular) or 0x0506 (empty archive) or 0x0708
        // (spanned). Accept any 'PK??' opener — flutter_gemma's parser will
        // reject malformed bundles itself; we only catch the catastrophic
        // wrong-format case here.
        return magic[0] == 0x50 && magic[1] == 0x4B;
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('[ModelStorage] _hasZipMagic(${file.path}) threw: $e');
      return false;
    }
  }

  /// Convenience: every filename in the list passes a fast presence check
  /// (no sha256). Used by `modelsAvailableProvider` in the UI.
  Future<bool> areAllPresent(List<String> filenames) async {
    for (final f in filenames) {
      if (!await isPresent(f)) return false;
    }
    return true;
  }

  // -- Download -----------------------------------------------------------

  /// Streams a model file from [url] into the app-support directory.
  /// Resumable when a `<filename>.partial` exists; verifies SHA-256 (if
  /// given) before the final rename.
  ///
  /// The returned stream emits one event per ~64 KB chunk (with a 100 ms
  /// rate limit so we don't drown the UI), plus one terminal event with
  /// either `done == true` or `error != null`.
  ///
  /// The stream cancels the in-flight HTTP request if the consumer cancels
  /// its subscription.
  Stream<ModelDownloadProgress> download({
    required String url,
    required String filename,
    int? expectedSize,
    String? sha256,
  }) {
    late final StreamController<ModelDownloadProgress> controller;
    StreamSubscription<List<int>>? subscription;
    HttpClientRequest? request;
    HttpClient? client;
    var cancelled = false;

    Future<void> start() async {
      try {
        final partialPath = await resolvePartialPath(filename);
        final finalPath = await resolveLocalPath(filename);

        // Make sure the parent dir exists. `getApplicationSupportDirectory`
        // is supposed to create it but the contract isn't strict on every
        // platform.
        await Directory(p.dirname(finalPath)).create(recursive: true);

        // If the final file already exists and matches expected size +
        // sha256, short-circuit with a single `done` event.
        if (await isPresent(filename,
            expectedSize: expectedSize, sha256: sha256)) {
          controller.add(ModelDownloadProgress(
            bytesDownloaded: await File(finalPath).length(),
            totalBytes: expectedSize,
            progress: 1.0,
            done: true,
          ));
          await controller.close();
          return;
        }

        // Resume from `.partial` length when available.
        final partialFile = File(partialPath);
        var resumeFrom = 0;
        if (await partialFile.exists()) {
          resumeFrom = await partialFile.length();
        }

        client = _httpClientFactory();
        // Generous timeouts — ~3 GB on 30 Mbps takes ~14 min.
        client!.connectionTimeout = const Duration(seconds: 30);

        final uri = Uri.parse(url);
        request = await client!.getUrl(uri);
        if (resumeFrom > 0) {
          request!.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
        }

        final response = await request!.close();

        // 200 = full body (server didn't honour Range, restart from 0)
        // 206 = partial content (range honoured, append)
        // any other 2xx is unexpected; non-2xx is fatal.
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          await response.drain<void>();
          throw HttpException(
            'HTTP ${response.statusCode} fetching $url',
            uri: uri,
          );
        }

        // Server didn't honour Range → reset partial.
        final append = response.statusCode == HttpStatus.partialContent;
        final sink = partialFile.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        if (!append) {
          resumeFrom = 0;
        }

        // Total = (resumeFrom + content-length) when partial, else
        // content-length, else expected.
        final contentLength = response.contentLength;
        final total = contentLength > 0
            ? (append ? resumeFrom + contentLength : contentLength)
            : (expectedSize != null && expectedSize > 0 ? expectedSize : null);

        var received = resumeFrom;
        var lastEmit = DateTime.now()
            .subtract(const Duration(seconds: 1)); // emit immediately

        final completer = Completer<void>();
        subscription = response.listen(
          (chunk) {
            if (cancelled) return;
            sink.add(chunk);
            received += chunk.length;
            final now = DateTime.now();
            if (now.difference(lastEmit) >=
                const Duration(milliseconds: 100)) {
              lastEmit = now;
              controller.add(ModelDownloadProgress(
                bytesDownloaded: received,
                totalBytes: total,
                progress: total != null && total > 0
                    ? (received / total).clamp(0.0, 1.0)
                    : null,
              ));
            }
          },
          onError: (Object e, StackTrace st) {
            completer.completeError(e, st);
          },
          onDone: () => completer.complete(),
          cancelOnError: true,
        );

        try {
          await completer.future;
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (cancelled) {
          // Leave the partial on disk for a future resume. Surface a
          // friendly error so the UI can render a retry CTA.
          controller.add(ModelDownloadProgress(
            bytesDownloaded: received,
            totalBytes: total,
            progress: total != null && total > 0
                ? (received / total).clamp(0.0, 1.0)
                : null,
            error: 'Cancelled',
          ));
          await controller.close();
          return;
        }

        // SHA-256 verify before renaming. Mismatch → delete partial + emit
        // error so the user can retry from scratch.
        if (sha256 != null && sha256.isNotEmpty) {
          final actual = await _computeSha256(partialFile);
          if (actual.toLowerCase() != sha256.toLowerCase()) {
            await partialFile.delete();
            throw StateError(
                'SHA-256 mismatch for $filename: expected $sha256, got $actual');
          }
        }

        // Atomic rename → final path.
        final finalFile = File(finalPath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await partialFile.rename(finalPath);

        controller.add(ModelDownloadProgress(
          bytesDownloaded: received,
          totalBytes: total,
          progress: 1.0,
          done: true,
        ));
        await controller.close();
      } catch (e, st) {
        debugPrint('[ModelStorage] download($filename) failed: $e\n$st');
        if (!controller.isClosed) {
          controller.add(ModelDownloadProgress(
            bytesDownloaded: 0,
            error: e.toString(),
          ));
          await controller.close();
        }
      } finally {
        try {
          client?.close(force: true);
        } catch (_) {}
      }
    }

    controller = StreamController<ModelDownloadProgress>(
      onListen: () {
        // ignore: discarded_futures
        start();
      },
      onCancel: () async {
        cancelled = true;
        try {
          await subscription?.cancel();
        } catch (_) {}
        try {
          client?.close(force: true);
        } catch (_) {}
      },
    );

    return controller.stream;
  }

  /// Delete a model file (and any in-flight `.partial`). Best-effort.
  Future<void> delete(String filename) async {
    final finalPath = await resolveLocalPath(filename);
    final partialPath = await resolvePartialPath(filename);
    for (final path in [finalPath, partialPath]) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (e) {
        debugPrint('[ModelStorage] delete($path) failed: $e');
      }
    }
  }

  Future<String> _computeSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }
}

// ---------------------------------------------------------------------------
// Riverpod wiring.
// ---------------------------------------------------------------------------

/// Singleton storage handle. Cheap to construct so this is a `Provider`,
/// not `Provider.autoDispose`.
final modelStorageProvider = Provider<ModelStorage>((ref) {
  return ModelStorage();
});

/// Cached parse of `assets/model_config.json`. Async so the asset bundle
/// load doesn't block the boot path; UI consumes via
/// `ref.watch(modelManifestProvider)`.
final modelManifestProvider = FutureProvider<ModelManifest>((ref) {
  return ModelManifest.loadFromAsset();
});

/// `true` when both Gemma weights are on disk. The MapScreen banner reads
/// this to show a "model not present — [Download]" CTA.
final modelsAvailableProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(modelStorageProvider);
  final manifest = await ref.watch(modelManifestProvider.future);
  final filenames = manifest.models.values.map((m) => m.filename).toList();
  return storage.areAllPresent(filenames);
});
