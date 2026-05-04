// ReportSheet — modal bottom sheet for "+ Report".
//
// One-tap, one-sentence flow per DEMO.md Scene 3. Auto-attached location
// chip (read-only in v1), 280-char free-text field, big submit button.
// Optimistic UI: on submit we close the sheet immediately and surface a
// snackbar — the actual classification continues in the background.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:uuid/uuid.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/photo_storage.dart';
import '../providers.dart';
import 'voice_input.dart';

/// Convenience opener — keeps the call site in MapScreen short.
Future<void> showReportSheet(
  BuildContext context, {
  VoiceRecognizer Function()? recognizerFactory,
  ImagePicker? imagePicker,
  PhotoStorage? photoStorage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ReportSheet(
      recognizerFactory: recognizerFactory,
      imagePicker: imagePicker,
      photoStorage: photoStorage,
    ),
  );
}

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    this.recognizerFactory,
    this.imagePicker,
    this.photoStorage,
  });

  final VoiceRecognizer Function()? recognizerFactory;
  final ImagePicker? imagePicker;
  final PhotoStorage? photoStorage;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _uploading = false;
  double? _uploadProgress;
  String? _error;

  late final VoiceRecognizer _recognizer =
      (widget.recognizerFactory ?? SpeechToTextRecognizer.new)();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();
  bool _voiceInitialized = false;
  bool _voiceAvailable = true;
  bool _listening = false;
  String _committedText = '';
  String? _photoPath;

  @override
  void dispose() {
    if (_listening) {
      unawaitedStop();
    }
    _controller.dispose();
    super.dispose();
  }

  void unawaitedStop() {
    _recognizer.stop();
  }

  Future<void> _ensureVoiceInitialized() async {
    if (_voiceInitialized) return;
    try {
      final ok = await _recognizer.initialize(
        onError: (_) => _handleVoiceFailure(),
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            if (_listening) {
              setState(() => _listening = false);
              _committedText = _controller.text;
            }
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _voiceInitialized = true;
        _voiceAvailable = ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceInitialized = true;
        _voiceAvailable = false;
      });
    }
  }

  void _handleVoiceFailure() {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _voiceAvailable = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ref.read(stringsProvider).reportSheetVoiceUnavailable),
      ),
    );
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _recognizer.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      _committedText = _controller.text;
      return;
    }

    await _ensureVoiceInitialized();
    if (!mounted || !_voiceAvailable) {
      _handleVoiceFailure();
      return;
    }

    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final localeId = lang == 'tr' ? 'tr_TR' : 'en_US';
    _committedText = _controller.text;

    try {
      await _recognizer.listen(
        onResult: _handleResult,
        localeId: localeId,
        pauseFor: const Duration(seconds: 8),
      );
      if (!mounted) return;
      setState(() => _listening = true);
    } catch (_) {
      _handleVoiceFailure();
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final recognized = result.recognizedWords.trim();
    if (recognized.isEmpty) return;

    if (result.finalResult) {
      final base = _committedText.trim();
      final merged = base.isEmpty ? recognized : '$base $recognized';
      _committedText = merged;
      _controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
      setState(() => _listening = false);
    } else {
      final base = _committedText.trim();
      final preview = base.isEmpty ? recognized : '$base $recognized';
      _controller.value = TextEditingValue(
        text: preview,
        selection: TextSelection.collapsed(offset: preview.length),
      );
    }
  }

  Future<void> _submit() async {
    if (_listening) {
      await _recognizer.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Type one sentence describing what you saw.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      String? photoUrl;
      final localPath = _photoPath;
      if (localPath != null) {
        final PhotoStorage storage =
            widget.photoStorage ?? ref.read(photoStorageProvider);
        final reportId = const Uuid().v4();
        setState(() {
          _uploading = true;
          _uploadProgress = 0.0;
        });
        photoUrl = await storage.uploadIfPresent(
          reportId,
          localPath,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _uploadProgress = p.fraction);
          },
        );
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _uploadProgress = null;
        });
      }
      final position = await ref.read(locationServiceProvider).currentPosition();
      await ref.read(reportsRepositoryProvider).submitReport(
            text: text,
            at: position,
            photoLocalPath: _photoPath,
            photoUrl: photoUrl,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(stringsProvider).reportSheetSubmitted),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uploading = false;
        _uploadProgress = null;
        _error = _humaniseError(e);
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_submitting) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (!mounted || picked == null) return;
      setState(() => _photoPath = picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(stringsProvider).reportSheetCouldNotAttach)),
      );
    }
  }

  void _clearPhoto() {
    if (_submitting) return;
    setState(() => _photoPath = null);
  }

  String _humaniseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('rate') || msg.contains('limit')) {
      return 'You\'ve hit the per-hour report limit. Try again later.';
    }
    if (msg.contains('location') || msg.contains('permission')) {
      return 'Location permission is required to attach the report.';
    }
    return 'Submission failed. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(currentLocationProvider);
    final position = positionAsync.whenOrNull(data: (p) => p);
    final padding = MediaQuery.of(context).viewInsets;

    final showMic = !_voiceInitialized || _voiceAvailable;
    final micColor = _listening
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New report',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _LocationChip(position: position),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 280,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(280)],
            decoration: InputDecoration(
              hintText: 'Describe what happened in one sentence…',
              border: const OutlineInputBorder(),
              suffixIcon: showMic
                  ? IconButton(
                      key: const ValueKey('voiceMicButton'),
                      tooltip: _listening ? 'Stop voice input' : 'Voice input',
                      icon: Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        color: micColor,
                      ),
                      onPressed: _submitting ? null : _toggleListening,
                    )
                  : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          if (_photoPath != null) ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_photoPath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('photoClearButton'),
                  tooltip: 'Remove photo',
                  icon: const Icon(Icons.close),
                  onPressed: _submitting ? null : _clearPhoto,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (_uploading) ...[
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    key: const ValueKey('photoUploadProgress'),
                    value: _uploadProgress,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_uploadProgress == null
                    ? '…'
                    : '${(_uploadProgress! * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('photoCameraButton'),
                  onPressed: _submitting
                      ? null
                      : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(ref.read(stringsProvider).reportSheetCamera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('photoGalleryButton'),
                  onPressed: _submitting
                      ? null
                      : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(ref.read(stringsProvider).reportSheetGallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Sending…' : 'Submit report'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.position});

  final dynamic position;

  @override
  Widget build(BuildContext context) {
    final label = position == null
        ? 'Resolving location…'
        : '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.location_on, size: 18),
        label: Text(label),
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      ),
    );
  }
}
