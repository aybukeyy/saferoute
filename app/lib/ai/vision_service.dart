import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class VisionInferenceLoader {
  Future<InferenceModel> loadVisionModel();
}

class _DefaultVisionLoader implements VisionInferenceLoader {
  @override
  Future<InferenceModel> loadVisionModel() => FlutterGemma.getActiveModel(
        maxTokens: 1024,
        // Android emülatöründe OpenCL yok → GPU backend fails. Debug build'de CPU'ya düş.
        preferredBackend:
            kDebugMode ? PreferredBackend.cpu : PreferredBackend.gpu,
        supportImage: true,
      );
}

class VisionService {
  VisionService({VisionInferenceLoader? loader})
      : _loader = loader ?? _DefaultVisionLoader();

  final VisionInferenceLoader _loader;

  static const String _prompt =
      "Describe this scene in 15 words or fewer, focusing on lighting and "
      "isolation level (e.g. 'Dark, narrow alley, no streetlights, no people "
      "visible').";

  Future<String?> analyzeImage(String? localPath) async {
    if (localPath == null) return null;
    // Emülatör/CPU backend'de flutter_gemma vision pipeline'ı SIGSEGV ediyor.
    // Debug build'de no-op döner; release'de (gerçek cihaz, GPU) tam çalışır.
    if (kDebugMode) {
      debugPrint('[VisionService] skipped in debug build (CPU backend incompatible)');
      return null;
    }
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[VisionService] file missing: $localPath');
        return null;
      }
      final Uint8List bytes = await file.readAsBytes();
      final model = await _loader.loadVisionModel();
      final session = await model.createSession(
        temperature: 0.2,
        topP: 0.9,
        topK: 32,
        randomSeed: 1,
        enableVisionModality: true,
      );
      try {
        await session.addQueryChunk(
          Message.withImage(text: _prompt, imageBytes: bytes, isUser: true),
        );
        final raw = await session.getResponse();
        final summary = raw.trim();
        if (summary.isEmpty) return null;
        return summary;
      } finally {
        try {
          await session.close();
        } catch (e) {
          debugPrint('[VisionService] session.close threw: $e');
        }
      }
    } catch (e, st) {
      debugPrint('[VisionService] analyzeImage failed: $e\n$st');
      return null;
    }
  }
}

final visionServiceProvider = Provider<VisionService>((ref) {
  return VisionService();
});
