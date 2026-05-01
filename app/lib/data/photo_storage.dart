import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PhotoStorage {
  PhotoStorage({FirebaseStorage? storage}) : _storage = storage;

  final FirebaseStorage? _storage;

  Future<String?> uploadIfPresent(String reportId, String? localPath) async {
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
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await ref.getDownloadURL();
    } catch (e, st) {
      debugPrint('[PhotoStorage] upload failed: $e\n$st');
      return null;
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
