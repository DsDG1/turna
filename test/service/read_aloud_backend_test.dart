// Tests for the read-aloud recognition backend, ADR 0061.
//
// `SpeechToTextReadAloudBackend` is driven against a fake `SpeechToText`
// (the `_FakeFlutterTts` noSuchMethod convention from speech_backend_test);
// what is under test is the seam's contract — that ensureReady is
// initialize, that listen carries the course locale, that stop reaches the
// plugin, and that plugin error strings collapse into the four categories
// the UI distinguishes. The unavailable backend must fail loudly on start,
// not pretend to listen.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:turna/service/read_aloud_backend.dart';

class _FakeSpeechToText implements SpeechToText {
  _FakeSpeechToText({this.initializeResult = true});

  bool initializeResult;
  Object? initializeError;
  Completer<bool>? initializeCompleter;
  Completer<List<LocaleName>>? localesCompleter;
  int initializeCalls = 0;

  final List<String?> listenLocales = [];
  int stopCount = 0;
  List<LocaleName> availableLocales = [];
  SpeechListenOptions? lastListenOptions;

  @override
  Future<List<LocaleName>> locales() {
    return localesCompleter?.future ?? Future.value(availableLocales);
  }

  // SpeechToText exposes a public errorListener setter; the fake redeclares
  // it as a plain field so tests can read what initialize wired.
  @override
  SpeechErrorListener? errorListener;
  SpeechResultListener? resultListener;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = const Duration(seconds: 2),
    List<SpeechConfigOption>? options,
  }) {
    initializeCalls++;
    errorListener = onError;
    final pending = initializeCompleter;
    if (pending != null) return pending.future;
    final error = initializeError;
    if (error != null) return Future.error(error);
    return Future.value(initializeResult);
  }

  @override
  Future<void> listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    resultListener = onResult;
    lastListenOptions = listenOptions;
    listenLocales.add(listenOptions?.localeId ?? localeId);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SpeechToTextReadAloudBackend', () {
    test('ensureReady is the plugin initialize result', () async {
      final fake = _FakeSpeechToText(initializeResult: false);
      final backend = SpeechToTextReadAloudBackend(fake);

      expect(await backend.ensureReady(), isFalse);
      expect(await backend.ensureReady(), isFalse);
      // The error listener wired at initialize is kept for later sessions.
      expect(fake.errorListener, isNotNull);
      expect(backend.lastFailure, ReadAloudFailure.permissionDenied);
    });

    test('missing recognizer degrades instead of throwing', () async {
      final fake = _FakeSpeechToText()
        ..initializeError = PlatformException(
          code: 'recognizerNotAvailable',
          message: 'Speech recognition not available on this device',
        );
      final backend = SpeechToTextReadAloudBackend(fake);

      expect(await backend.ensureReady(), isFalse);
      expect(backend.lastFailure, ReadAloudFailure.serviceUnavailable);
    });

    test('concurrent readiness calls share one initialization', () async {
      final fake = _FakeSpeechToText()..initializeCompleter = Completer<bool>();
      final backend = SpeechToTextReadAloudBackend(fake);

      final first = backend.ensureReady();
      final second = backend.ensureReady();
      expect(fake.initializeCalls, 1);

      fake.initializeCompleter!.complete(true);
      expect(await Future.wait([first, second]), [true, true]);
    });

    test('start passes the locale and forwards results', () async {
      final fake = _FakeSpeechToText();
      final backend = SpeechToTextReadAloudBackend(fake);

      final results = <(String, bool)>[];
      await backend.start(
        locale: 'tr',
        onResult: (text, isFinal) => results.add((text, isFinal)),
        onError: (_) {},
      );

      expect(fake.listenLocales, ['tr']);
      expect(fake.lastListenOptions?.listenMode, ListenMode.dictation);
      expect(fake.lastListenOptions?.cancelOnError, isTrue);
      expect(fake.lastListenOptions?.listenFor, const Duration(seconds: 30));
      fake.resultListener!(
        SpeechRecognitionResult(
          [const SpeechRecognitionWords('merhaba', null, 1.0)],
          ResultType.finalResult.value,
        ),
      );
      expect(results.last, ('merhaba', true));
    });

    test('start resolves region-specific locale if available on device',
        () async {
      final fake = _FakeSpeechToText();
      fake.availableLocales = [
        LocaleName('en_US', 'English'),
        LocaleName('tr_TR', 'Turkish'),
      ];
      final backend = SpeechToTextReadAloudBackend(fake);

      await backend.start(
        locale: 'tr',
        onResult: (_, __) {},
        onError: (_) {},
      );

      expect(fake.listenLocales, ['tr_TR']);
    });

    test('unanswered locale discovery falls back and still starts', () async {
      final fake = _FakeSpeechToText()
        ..localesCompleter = Completer<List<LocaleName>>();
      final backend = SpeechToTextReadAloudBackend(fake);

      await backend.start(
        locale: 'tr',
        onResult: (_, __) {},
        onError: (_) {},
      );

      expect(fake.listenLocales, ['tr']);
    });

    test('stop reaches the plugin', () async {
      final fake = _FakeSpeechToText();
      final backend = SpeechToTextReadAloudBackend(fake);

      await backend.stop();
      expect(fake.stopCount, 1);
    });
  });

  group('failure categorization', () {
    test('permission errors map to permissionDenied', () {
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure('error_permission'),
        ReadAloudFailure.permissionDenied,
      );
    });

    test('missing-language errors map to serviceUnavailable', () {
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure(
          'error_language_not_supported',
        ),
        ReadAloudFailure.serviceUnavailable,
      );
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure(
          'error_language_unavailable',
        ),
        ReadAloudFailure.serviceUnavailable,
      );
    });

    test('network and server errors map to networkUnavailable', () {
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure('error_network'),
        ReadAloudFailure.networkUnavailable,
      );
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure(
          'error_server_disconnected',
        ),
        ReadAloudFailure.networkUnavailable,
      );
    });

    test('everything else is a retryable recognition failure', () {
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure('error_no_match'),
        ReadAloudFailure.recognitionFailed,
      );
      expect(
        SpeechToTextReadAloudBackend.categorizeFailure('error_speech_timeout'),
        ReadAloudFailure.recognitionFailed,
      );
    });

    test('session errors route to the active onError listener', () async {
      final fake = _FakeSpeechToText();
      final backend = SpeechToTextReadAloudBackend(fake);
      await backend.ensureReady();

      final failures = <ReadAloudFailure>[];
      await backend.start(
        locale: 'tr',
        onResult: (_, __) {},
        onError: failures.add,
      );
      fake.errorListener!(
        SpeechRecognitionError('error_no_match', false),
      );

      expect(failures, [ReadAloudFailure.recognitionFailed]);
    });
  });

  group('UnavailableReadAloudBackend', () {
    const backend = UnavailableReadAloudBackend();

    test('reports itself unsupported and not ready', () async {
      expect(backend.isSupported, isFalse);
      expect(await backend.ensureReady(), isFalse);
    });

    test(
        'start fails loudly — pretending to listen is the one bug worse '
        'than being absent', () {
      expect(
        () => backend.start(
          locale: 'tr',
          onResult: (_, __) {},
          onError: (_) {},
        ),
        throwsStateError,
      );
    });
  });
}
