import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadProgress {
  const UploadProgress({required this.bytesTransferred, required this.totalBytes});

  final int bytesTransferred;
  final int totalBytes;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0).toDouble();
  }
}

class PhotoStorage {
  PhotoStorage({FirebaseStorage? storage}) : _storage = storage;

  final FirebaseStorage? _storage;

  Future<String?> uploadIfPresent(
    String reportId,
    String? localPath, {
    void Function(UploadProgress)? onProgress,
  }) async {
    if (localPath == null) return null;
    final storage = _storage;
    if (storage == null) {
      debugPrint('[PhotoStorage] storage unavailable; skipping upload');
      return null;
    }
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[PhotoStorage] local file missing: $localPath');
        return null;
      }
      final bytes = await file.readAsBytes();
      final ref = storage.ref().child('reports/$reportId.jpg');
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      if (onProgress != null) {
        task.snapshotEvents.listen((snap) {
          onProgress(UploadProgress(
            bytesTransferred: snap.bytesTransferred,
            totalBytes: snap.totalBytes,
          ));
        });
      }
      await task;
      return await ref.getDownloadURL();
    } catch (e, st) {
      debugPrint('[PhotoStorage] upload failed: $e\n$st');
      return null;
    }
  }

  Future<void> deleteIfPresent(String reportId) async {
    final storage = _storage;
    if (storage == null) return;
    try {
      await storage.ref().child('reports/$reportId.jpg').delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found' ||
          e.code == 'unauthorized' ||
          e.code == 'permission-denied') {
        return;
      }
      debugPrint('[PhotoStorage] delete failed: $e');
    } catch (e) {
      debugPrint('[PhotoStorage] delete failed: $e');
    }
  }
}

final photoStorageProvider = Provider<PhotoStorage>((ref) {
  try {
    return PhotoStorage(storage: FirebaseStorage.instance);
  } catch (e) {
    debugPrint('[PhotoStorage] FirebaseStorage unavailable: $e');
    return PhotoStorage();
  }
});
