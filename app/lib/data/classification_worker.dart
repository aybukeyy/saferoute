// Drains PENDING reports through Gemma → updateClassification. One report
// at a time; GemmaService's inference lock would serialise us anyway but
// keeping the queue explicit makes the boot drain deterministic. The
// recomputeCell + mirror chain is owned by ReportsRepository.updateClassification.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/gemma_service.dart';
import '../ai/vision_service.dart';
import '../app/real_providers.dart';
import '../models/report.dart';
import 'photo_storage.dart';
import 'reports_repository.dart';

class ClassificationWorker {
  ClassificationWorker({
    required ReportsRepository reports,
    required GemmaService gemma,
    PhotoStorage? photoStorage,
    VisionService? visionService,
  })  : _reports = reports,
        _gemma = gemma,
        _photoStorage = photoStorage,
        _visionService = visionService;

  final ReportsRepository _reports;
  final GemmaService _gemma;
  final PhotoStorage? _photoStorage;
  final VisionService? _visionService;

  final Queue<Report> _queue = Queue<Report>();
  final Set<String> _seen = <String>{};
  StreamSubscription<Report>? _sub;
  bool _draining = false;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _sub = _reports.watchPending().listen(_enqueue);

    final existing = await _reports.pendingReports();
    for (final r in existing) {
      _enqueue(r);
    }
  }

  void _enqueue(Report r) {
    if (_disposed) return;
    if (!_seen.add(r.id)) return;
    _queue.add(r);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final report = _queue.removeFirst();
        await _process(report);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _process(Report r) async {
    if (r.photoLocalPath != null) {
      String? photoUrl;
      String? visionSummary;
      try {
        photoUrl = await _photoStorage?.uploadIfPresent(r.id, r.photoLocalPath);
      } catch (e) {
        debugPrint('[ClassificationWorker] photo upload threw for ${r.id}: $e');
      }
      try {
        visionSummary = await _visionService?.analyzeImage(r.photoLocalPath);
      } catch (e) {
        debugPrint('[ClassificationWorker] vision analyze threw for ${r.id}: $e');
      }
      if (photoUrl != null || visionSummary != null) {
        try {
          await _reports.updatePhotoAndVision(
            r.id,
            photoUrl: photoUrl,
            visionSummary: visionSummary,
          );
        } catch (e) {
          debugPrint('[ClassificationWorker] updatePhotoAndVision threw: $e');
        }
      }
    }
    try {
      final classification = await _gemma.classify(
        text: r.text,
        lat: r.lat,
        lng: r.lng,
        occurredAt: r.occurredAt,
      );
      await _reports.updateClassification(r.id, classification);
    } catch (e, st) {
      debugPrint('[ClassificationWorker] classify failed for ${r.id}: $e\n$st');
      try {
        await _reports.markClassificationFailed(r.id);
      } catch (e2) {
        debugPrint('[ClassificationWorker] markClassificationFailed threw: $e2');
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    _queue.clear();
    _seen.clear();
  }
}

final classificationWorkerProvider =
    FutureProvider<ClassificationWorker>((ref) async {
  final reports = await ref.watch(realReportsRepositoryProvider.future);
  final worker = ClassificationWorker(
    reports: reports,
    gemma: ref.watch(realGemmaServiceProvider),
    photoStorage: ref.watch(photoStorageProvider),
    visionService: ref.watch(visionServiceProvider),
  );
  await worker.start();
  ref.onDispose(() => unawaited(worker.dispose()));
  return worker;
});
