import 'dart:io';

import 'package:app/ai/vision_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisionService', () {
    test('null path returns null without invoking model', () async {
      final loader = _FakeLoader.success('Bright park, several people.');
      final service = VisionService(loader: loader);
      expect(await service.analyzeImage(null), isNull);
      expect(loader.loadCalls, 0);
    });

    test('missing file returns null', () async {
      final loader = _FakeLoader.success('ignored');
      final service = VisionService(loader: loader);
      final result = await service.analyzeImage(
        '/tmp/missing-vision-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      expect(result, isNull);
      expect(loader.loadCalls, 0);
    });

    test('loader throws → returns null (no vision encoder available)',
        () async {
      final tmp = await _writeTmpJpeg();
      try {
        final loader = _FakeLoader.failing();
        final service = VisionService(loader: loader);
        final result = await service.analyzeImage(tmp.path);
        expect(result, isNull);
        expect(loader.loadCalls, 1);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    });
  });
}

Future<File> _writeTmpJpeg() async {
  final f = File(
    '${Directory.systemTemp.path}/vision_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await f.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
  return f;
}

class _FakeLoader implements VisionInferenceLoader {
  _FakeLoader._({this.fail = false});
  factory _FakeLoader.success(String _) => _FakeLoader._();
  factory _FakeLoader.failing() => _FakeLoader._(fail: true);

  final bool fail;
  int loadCalls = 0;

  @override
  Future<InferenceModel> loadVisionModel() async {
    loadCalls += 1;
    throw fail
        ? StateError('vision encoder unavailable')
        : UnimplementedError('not used in this test');
  }
}
