import 'package:app/features/providers.dart';
import 'package:app/features/report/report_sheet.dart';
import 'package:app/features/report/voice_input.dart';
import 'package:app/models/report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

void main() {
  Future<_FakeRecognizer> pumpSheet(
    WidgetTester tester, {
    required _FakeRecognizer recognizer,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(_FakeLocation()),
          reportsRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReportSheet(recognizerFactory: () => recognizer),
          ),
        ),
      ),
    );
    await tester.pump();
    return recognizer;
  }

  testWidgets('renders the mic button', (tester) async {
    await pumpSheet(tester, recognizer: _FakeRecognizer());
    expect(find.byKey(const ValueKey('voiceMicButton')), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('tapping mic with granted permission starts listening',
      (tester) async {
    final fake = _FakeRecognizer(initOk: true);
    await pumpSheet(tester, recognizer: fake);

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();

    expect(fake.initializeCalls, 1);
    expect(fake.listenCalls, 1);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets(
      'final result populates text field; second final appends with space',
      (tester) async {
    final fake = _FakeRecognizer(initOk: true);
    await pumpSheet(tester, recognizer: fake);

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();

    fake.emit('hello there', isFinal: true);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hello there');

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();
    fake.emit('how are you', isFinal: true);
    await tester.pump();

    expect(field.controller!.text, 'hello there how are you');
  });

  testWidgets('partial result shows live transcription without appending',
      (tester) async {
    final fake = _FakeRecognizer(initOk: true);
    await pumpSheet(tester, recognizer: fake);

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();

    fake.emit('hel', isFinal: false);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hel');

    fake.emit('hello', isFinal: false);
    await tester.pump();
    expect(field.controller!.text, 'hello');

    fake.emit('hello there', isFinal: true);
    await tester.pump();
    expect(field.controller!.text, 'hello there');
  });

  testWidgets('permission-denied path shows the SnackBar', (tester) async {
    final fake = _FakeRecognizer(initOk: false);
    await pumpSheet(tester, recognizer: fake);

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Voice input unavailable. Type your report.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping during listening stops it', (tester) async {
    final fake = _FakeRecognizer(initOk: true);
    await pumpSheet(tester, recognizer: fake);

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();
    expect(fake.listenCalls, 1);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voiceMicButton')));
    await tester.pump();

    expect(fake.stopCalls, greaterThanOrEqualTo(1));
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });
}

class _FakeRecognizer implements VoiceRecognizer {
  _FakeRecognizer({this.initOk = true});

  final bool initOk;
  int initializeCalls = 0;
  int listenCalls = 0;
  int stopCalls = 0;
  bool _listening = false;
  void Function(SpeechRecognitionResult)? _onResult;

  @override
  bool get isAvailable => initOk;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize({
    void Function(SpeechRecognitionError error)? onError,
    void Function(String status)? onStatus,
  }) async {
    initializeCalls += 1;
    return initOk;
  }

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    required String localeId,
    Duration pauseFor = const Duration(seconds: 8),
  }) async {
    listenCalls += 1;
    _listening = true;
    _onResult = onResult;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _listening = false;
  }

  void emit(String text, {required bool isFinal}) {
    _onResult?.call(SpeechRecognitionResult(
      [SpeechRecognitionWords(text, [], 1.0)],
      isFinal,
    ));
    if (isFinal) {
      _listening = false;
    }
  }
}

class _FakeLocation implements LocationServiceLike {
  @override
  Stream<LatLng> watchPosition() async* {
    yield const LatLng(41.0, 28.97);
  }

  @override
  Future<LatLng> currentPosition() async => const LatLng(41.0, 28.97);
}

class _FakeRepo implements ReportsRepositoryLike {
  @override
  Future<Report> submitReport({
    required String text,
    required LatLng at,
    String? photoLocalPath,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<Report>> recentReports({int limit = 50}) async => const [];

  @override
  Future<List<Report>> reportsInCell(String geohash7) async => const [];
}
