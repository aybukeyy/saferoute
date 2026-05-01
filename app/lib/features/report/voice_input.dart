import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class VoiceRecognizer {
  Future<bool> initialize({
    void Function(SpeechRecognitionError error)? onError,
    void Function(String status)? onStatus,
  });

  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    required String localeId,
    Duration pauseFor,
  });

  Future<void> stop();

  bool get isAvailable;
  bool get isListening;
}

class SpeechToTextRecognizer implements VoiceRecognizer {
  SpeechToTextRecognizer([SpeechToText? impl]) : _impl = impl ?? SpeechToText();

  final SpeechToText _impl;

  @override
  Future<bool> initialize({
    void Function(SpeechRecognitionError error)? onError,
    void Function(String status)? onStatus,
  }) {
    return _impl.initialize(onError: onError, onStatus: onStatus);
  }

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    required String localeId,
    Duration pauseFor = const Duration(seconds: 8),
  }) {
    return _impl.listen(
      onResult: onResult,
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
      pauseFor: pauseFor,
    );
  }

  @override
  Future<void> stop() => _impl.stop();

  @override
  bool get isAvailable => _impl.isAvailable;

  @override
  bool get isListening => _impl.isListening;
}
