import 'dart:io';

import 'package:app/data/photo_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhotoStorage', () {
    test('null path returns null without touching storage', () async {
      final storage = PhotoStorage();
      expect(await storage.uploadIfPresent('r1', null), isNull);
    });

    test('missing file returns null', () async {
      final storage = PhotoStorage();
      final result = await storage.uploadIfPresent(
        'r1',
        '/tmp/definitely-not-here-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      expect(result, isNull);
    });

    test('present file with no FirebaseStorage returns null gracefully',
        () async {
      final tmp = await File(
        '${Directory.systemTemp.path}/photo_storage_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ).create();
      try {
        await tmp.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
        final storage = PhotoStorage();
        final result = await storage.uploadIfPresent('r1', tmp.path);
        expect(result, isNull);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    });

    test('deleteIfPresent without FirebaseStorage is a silent no-op', () async {
      final storage = PhotoStorage();
      await expectLater(storage.deleteIfPresent('r1'), completes);
    });
  });
}
