// Unit tests for `ModelStorage` (path resolution, presence check, manifest
// parsing). The download streamer is exercised against a local in-process
// HTTP server so we don't hit the real internet — small fixture, real
// HttpClient, real Range header behaviour.

import 'dart:convert';
import 'dart:io';

import 'package:app/ai/model_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ModelManifest.fromJson', () {
    test('parses a well-formed manifest', () {
      final json = jsonDecode(_kSampleManifestJson) as Map<String, dynamic>;
      final manifest = ModelManifest.fromJson(json);

      expect(manifest.version, 1);
      expect(manifest.models.keys, containsAll(['gemma-4-e2b', 'gemma-4-e4b']));
      expect(manifest.totalApproximateMb, 1500 + 3000);

      final e2b = manifest.models['gemma-4-e2b']!;
      expect(e2b.filename, 'gemma-4-e2b.task');
      expect(e2b.sizeBytes, 0);
      expect(e2b.isPlaceholder, isTrue);
      expect(e2b.hasSha256, isFalse);
    });

    test('handles null sha256 gracefully', () {
      final manifest = ModelManifest.fromJson({
        'version': 1,
        'models': {
          'm': {
            'url': 'https://example.com/m.task',
            'filename': 'm.task',
            'sizeBytes': 1024,
            'sha256': null,
            'displayName': 'M',
            'approximateMb': 1,
          }
        }
      });
      expect(manifest.models['m']!.hasSha256, isFalse);
      expect(manifest.models['m']!.isPlaceholder, isFalse);
    });
  });

  group('ModelStorage path + presence', () {
    late Directory tempDir;
    late ModelStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_storage_test_');
      storage = ModelStorage(supportDirProvider: () async => tempDir);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('resolveLocalPath joins the support dir + filename', () async {
      final path = await storage.resolveLocalPath('foo.task');
      expect(path, p.join(tempDir.path, 'foo.task'));
    });

    test('isPresent returns false when the file is absent', () async {
      expect(await storage.isPresent('absent.task'), isFalse);
    });

    // NOTE: existing presence/size/sha256 tests use the neutral `.bin`
    // extension so they aren't gated by the ZIP magic-byte check that was
    // added to harden against wrong-format downloads (e.g. an HTML error page
    // that happens to land at the right size, or the `-web.task` web variant
    // that doesn't open as a mobile MediaPipe bundle). The ZIP magic check is
    // exercised separately further down.
    test('isPresent returns true when present and no checks asked', () async {
      final f = File(p.join(tempDir.path, 'present.bin'));
      await f.writeAsBytes([1, 2, 3]);
      expect(await storage.isPresent('present.bin'), isTrue);
    });

    test('isPresent enforces expected size', () async {
      final f = File(p.join(tempDir.path, 'sized.bin'));
      await f.writeAsBytes([1, 2, 3, 4]);
      expect(
        await storage.isPresent('sized.bin', expectedSize: 4),
        isTrue,
      );
      expect(
        await storage.isPresent('sized.bin', expectedSize: 999),
        isFalse,
      );
    });

    test('isPresent verifies sha256 when provided', () async {
      final f = File(p.join(tempDir.path, 'hashed.bin'));
      final bytes = utf8.encode('hello');
      await f.writeAsBytes(bytes);
      final expected = sha256.convert(bytes).toString();
      expect(
        await storage.isPresent('hashed.bin', sha256: expected),
        isTrue,
      );
      expect(
        await storage.isPresent('hashed.bin', sha256: 'deadbeef'),
        isFalse,
      );
    });

    test('areAllPresent short-circuits on first miss', () async {
      await File(p.join(tempDir.path, 'a.bin')).writeAsBytes([1]);
      // 'b.bin' is missing.
      expect(await storage.areAllPresent(['a.bin', 'b.bin']), isFalse);
    });

    // ---- ZIP magic-byte check (added 2026-04-26) -------------------------
    //
    // Both `.task` (MediaPipe) and `.litertlm` (LiteRT-LM) bundles are ZIP
    // containers — the first 4 bytes are `PK\x03\x04`. Any file that lands
    // with one of those extensions but doesn't start with the ZIP magic is
    // a wrong-format download; isPresent now treats it as not-present so the
    // UI can offer a re-download instead of letting flutter_gemma's native
    // init blow up with "Unable to open zip archive".

    test('isPresent rejects a .task file without ZIP magic', () async {
      final f = File(p.join(tempDir.path, 'bogus.task'));
      // 2 MB of zeros — passes the size floor but no ZIP signature.
      await f.writeAsBytes(List<int>.filled(2 * 1024 * 1024, 0));
      expect(await storage.isPresent('bogus.task'), isFalse);
    });

    test('isPresent rejects a .litertlm file without ZIP magic', () async {
      final f = File(p.join(tempDir.path, 'bogus.litertlm'));
      await f.writeAsBytes(List<int>.filled(2 * 1024 * 1024, 0));
      expect(await storage.isPresent('bogus.litertlm'), isFalse);
    });

    test('isPresent accepts a .task file with ZIP magic + sufficient size',
        () async {
      final f = File(p.join(tempDir.path, 'good.task'));
      // PK\x03\x04 prefix + padding to push past the 1 MB size floor.
      final bytes = <int>[0x50, 0x4B, 0x03, 0x04];
      bytes.addAll(List<int>.filled(2 * 1024 * 1024, 0));
      await f.writeAsBytes(bytes);
      expect(await storage.isPresent('good.task'), isTrue);
    });

    test('isPresent rejects a sub-1MB .task file even with ZIP magic',
        () async {
      // A truncated/partial download could begin with 'PK' yet be useless.
      final f = File(p.join(tempDir.path, 'tiny.task'));
      await f.writeAsBytes([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]);
      expect(await storage.isPresent('tiny.task'), isFalse);
    });
  });

  group('ModelStorage.download (against local HTTP server)', () {
    late HttpServer server;
    late Directory tempDir;
    late ModelStorage storage;
    late List<int> payload;
    late String payloadHash;

    setUp(() async {
      // 64 KiB payload so we cross the chunk boundary at least once.
      payload = List<int>.generate(64 * 1024, (i) => i % 256);
      payloadHash = sha256.convert(payload).toString();
      tempDir = await Directory.systemTemp.createTemp('download_test_');
      storage = ModelStorage(supportDirProvider: () async => tempDir);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        // Honour a `Range` header by slicing the payload — gives us a real
        // resumable response in tests.
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range != null && range.startsWith('bytes=')) {
          final spec = range.substring('bytes='.length);
          final start = int.parse(spec.split('-').first);
          final slice = payload.sublist(start);
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.contentLength = slice.length;
          req.response.add(slice);
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentLength = payload.length;
          req.response.add(payload);
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    // NOTE: download tests use the neutral `.bin` extension so the new ZIP
    // magic-byte check in `isPresent` doesn't false-reject the 64 KiB random
    // payload (which is intentionally not a real ZIP). The downloader path
    // itself doesn't run magic-byte validation; only `isPresent` does. The
    // short-circuit test below pre-stages a `.bin` file at the destination
    // for the same reason.
    test('emits progress events and a final done event', () async {
      final url = 'http://127.0.0.1:${server.port}/model.bin';
      final events = await storage
          .download(
            url: url,
            filename: 'model.bin',
            expectedSize: payload.length,
            sha256: payloadHash,
          )
          .toList();

      expect(events, isNotEmpty);
      expect(events.last.done, isTrue);
      expect(events.last.error, isNull);
      expect(events.last.bytesDownloaded, payload.length);

      // Final file landed at the resolved path with the right contents.
      final f = File(await storage.resolveLocalPath('model.bin'));
      expect(await f.exists(), isTrue);
      expect(await f.length(), payload.length);
      expect(sha256.convert(await f.readAsBytes()).toString(), payloadHash);

      // Partial file got cleaned up via rename.
      final partial =
          File(await storage.resolvePartialPath('model.bin'));
      expect(await partial.exists(), isFalse);
    });

    test('emits an error event on sha256 mismatch (and deletes partial)',
        () async {
      final url = 'http://127.0.0.1:${server.port}/model.bin';
      final events = await storage
          .download(
            url: url,
            filename: 'bad.bin',
            expectedSize: payload.length,
            sha256:
                'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
          )
          .toList();

      expect(events.last.error, isNotNull);
      // Partial file was deleted so the user can retry from scratch.
      expect(
        await File(await storage.resolvePartialPath('bad.bin')).exists(),
        isFalse,
      );
      // Final file was never produced.
      expect(
        await File(await storage.resolveLocalPath('bad.bin')).exists(),
        isFalse,
      );
    });

    test('short-circuits when the file is already present + valid', () async {
      // Pre-stage a known-good file at the destination.
      final destPath = await storage.resolveLocalPath('cached.bin');
      await File(destPath).writeAsBytes(payload);

      final url = 'http://127.0.0.1:${server.port}/cached.bin';
      final events = await storage
          .download(
            url: url,
            filename: 'cached.bin',
            expectedSize: payload.length,
            sha256: payloadHash,
          )
          .toList();

      // One event total: a `done` with the cached size.
      expect(events.length, 1);
      expect(events.single.done, isTrue);
      expect(events.single.bytesDownloaded, payload.length);
    });
  });
}

const String _kSampleManifestJson = '''
{
  "version": 1,
  "models": {
    "gemma-4-e2b": {
      "url": "https://TODO_REPLACED_BY_AGENT_B",
      "filename": "gemma-4-e2b.task",
      "sizeBytes": 0,
      "sha256": "TODO_REPLACED_BY_AGENT_B",
      "displayName": "Gemma 4 E2B (classification)",
      "approximateMb": 1500
    },
    "gemma-4-e4b": {
      "url": "https://TODO_REPLACED_BY_AGENT_B",
      "filename": "gemma-4-e4b.task",
      "sizeBytes": 0,
      "sha256": "TODO_REPLACED_BY_AGENT_B",
      "displayName": "Gemma 4 E4B (area summary)",
      "approximateMb": 3000
    }
  }
}
''';
