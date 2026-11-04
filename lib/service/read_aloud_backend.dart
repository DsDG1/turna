// Read-aloud (跟读) recognition backend (ADR 0061).
//
// The mirror of `speech_backend.dart` on the listening side: one abstract
// seam, one Android/iOS implementation behind `speech_to_text` (platform
// SpeechRecognizer / SFSpeechRecognizer), and one unavailable impl for every
// other target. What the recognizer buys us is word-level matching — the
// transcript is compared against the reference sentence by
// `core/read_aloud_scoring.dart` — never phone-level pronunciation scoring
// (that tier has no Turkish provider; see ADR 0061 and project-guide §15).
//
// Privacy: recognition is performed by the platform's speech service, which
// may process audio over the network. The settings copy and ADR say so; the
// master switch (`readAloudExercisesEnabled`) is opt-in for that reason.
//
// Permission timing: `ensureReady` triggers the microphone permission dialog
// (Android inside `speech_to_text.initialize`, iOS on first `listen`). It
// must therefore only ever be called from a user action — the mic button —
// never from startup probing.

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';

/// Why a read-aloud session could not produce a transcript.
enum ReadAloudFailure {
  /// The microphone permission was refused (or permanently denied).
  permissionDenied,

  /// No recognition service exists on this device (e.g. Android without the
  /// Google recognition service).
  serviceUnavailable,

  /// The recognition service could not be reached, or its online language
  /// resources could not be downloaded.
  networkUnavailable,

  /// The session started but recognition itself failed: nothing spoken or no
  /// match. Not an answer — the learner can tap the mic again.
  recognitionFailed,
}

/// One listening session's callbacks. `onResult` fires with partial
/// transcripts while speaking (`isFinal: false`) and once more with the final
/// transcript; that final delivery is the session's completion signal.
typedef ReadAloudResultListener = void Function(String text, bool isFinal);
typedef ReadAloudErrorListener = void Function(ReadAloudFailure reason);

/// Captures one utterance for word-level matching.
abstract class ReadAloudBackend {
  /// Whether this build can recognize at all. Synchronous so callers can
  /// choose the degraded card before asking the user anything.
  bool get isSupported;

  /// The most recent readiness or recognition failure, if one occurred.
  ReadAloudFailure? get lastFailure;

  /// Requests the microphone permission (first call only) and verifies a
  /// recognition service exists.
  ///
  /// Returns false when recognition is impossible — permission refused or no
  /// service. Safe to call repeatedly; `speech_to_text` caches its own
  /// initialized state.
  Future<bool> ensureReady();

  /// Starts one listening session in [locale] (BCP-47; the Android side
  /// feeds it to `Locale.forLanguageTag`, iOS to `Locale(identifier:)`).
  ///
  /// The session ends by itself after [pauseFor] of silence or [listenFor]
  /// overall; [stop] ends it early. Both deliver the final transcript to
  /// `onResult` first. Errors after a successful start go to `onError`.
  ///
  /// The call is bounded: when the platform never confirms the session, or
  /// ends it without a final transcript, `onError` receives a retryable
  /// `recognitionFailed` instead of leaving the caller hanging.
  Future<void> start({
    required String locale,
    required ReadAloudResultListener onResult,
    required ReadAloudErrorListener onError,
  });

  /// Ends the session early, delivering a final result. Best-effort.
  Future<void> stop();
}

/// How long `start` waits for `listen()` itself to confirm before tearing
/// the session down. Bounds the call so the renderer's starting flag can
/// never wedge on a platform that never answers.
const Duration kReadAloudListenConfirmTimeout = Duration(seconds: 6);

/// How long after a seemingly successful start the session has to show a
/// first sign of life (a `listening` status or any transcript) before it is
/// declared never opened.
const Duration kReadAloudStartWatchdog = Duration(seconds: 5);

/// Grace for the final transcript once the session reports (or is asked) to
/// stop. Exceeds the plugin's own final-result timeout (2s) so a merely
/// late final is never declared dead.
const Duration kReadAloudFinalGrace = Duration(seconds: 3);

/// Android / iOS: `speech_to_text` (platform SpeechRecognizer /
/// SFSpeechRecognizer).
///
/// The plugin's own session-end signals can silently never arrive — after a
/// `stop` it waits out its final-result timeout and gives up without
/// notifying Dart — so the backend keeps watchdogs for every phase: the
/// `listen()` confirm race, the never-opened start, and the final that
/// trails a session end. Each watchdog surfaces as a retryable
/// `recognitionFailed` through `onError`, never as silence.
class SpeechToTextReadAloudBackend implements ReadAloudBackend {
  SpeechToTextReadAloudBackend(this._speech);

  final SpeechToText _speech;
  ReadAloudErrorListener? _errorListener;
  ReadAloudFailure? _lastFailure;
  Future<bool>? _readyInFlight;

  // Session lifecycle (see the class comment). The generation token
  // invalidates callbacks still in flight from superseded sessions.
  int _sessionToken = 0;
  bool _sessionActive = false;
  bool _confirmedAlive = false;
  bool _finalDelivered = false;
  Timer? _listenWatchdog;
  Timer? _finalGrace;

  @override
  bool get isSupported => true;

  @override
  ReadAloudFailure? get lastFailure => _lastFailure;

  @override
  Future<bool> ensureReady() {
    final active = _readyInFlight;
    if (active != null) return active;
    final future = _initialize();
    _readyInFlight = future;
    return future.whenComplete(() {
      if (identical(_readyInFlight, future)) _readyInFlight = null;
    });
  }

  Future<bool> _initialize() async {
    _lastFailure = null;
    try {
      final ready = await _speech.initialize(
        debugLogging: kDebugMode,
        options: [SpeechToText.androidNoBluetooth],
        onError: (error) {
          logger.w(
            'read-aloud: recognition error ${error.errorMsg} '
            '(permanent=${error.permanent})',
          );
          // `cancelOnError` ends the session on the plugin side; end it here
          // too so no watchdog fires into the already-notified listener.
          _endSession();
          _reportFailure(_categorize(error.errorMsg));
        },
        // The final result — not the `done` status — is the completion signal,
        // because only the result carries the transcript the scorer needs.
        // The status stream feeds the session watchdogs in `_onPluginStatus`.
        //
        // The plugin wires these listeners only on the first successful
        // `initialize` and ignores later ones; passing method tear-offs of
        // this singleton keeps them valid for its whole lifetime.
        onStatus: _onPluginStatus,
      );
      if (!ready) _lastFailure ??= ReadAloudFailure.permissionDenied;
      return ready;
    } on PlatformException catch (e, st) {
      logger.w(
        'read-aloud: initialize failed (${e.code})',
        error: e,
        stackTrace: st,
      );
      _lastFailure = _platformFailure(e.code);
      return false;
    } catch (e, st) {
      logger.w('read-aloud: initialize failed', error: e, stackTrace: st);
      _lastFailure = ReadAloudFailure.recognitionFailed;
      return false;
    }
  }

  @override
  Future<void> start({
    required String locale,
    required ReadAloudResultListener onResult,
    required ReadAloudErrorListener onError,
  }) async {
    _errorListener = onError;
    _lastFailure = null;
    final token = ++_sessionToken;
    _beginSession();
    try {
      final resolvedLocale = await resolveLocaleId(locale);
      if (token != _sessionToken) return;
      await _speech
          .listen(
            onResult: (result) {
              if (token != _sessionToken) return;
              // Any transcript proves the mic came up; the start watchdog
              // has nothing left to guard.
              _confirmedAlive = true;
              _listenWatchdog?.cancel();
              if (result.finalResult) _finalDelivered = true;
              onResult(result.recognizedWords, result.finalResult);
            },
            listenOptions: SpeechListenOptions(
              partialResults: true,
              cancelOnError: true,
              listenMode: ListenMode.dictation,
              localeId: resolvedLocale,
              pauseFor: const Duration(seconds: 3),
              listenFor: const Duration(seconds: 30),
            ),
          )
          .timeout(kReadAloudListenConfirmTimeout);
    } on TimeoutException {
      // `listen()` never confirmed. `cancel()` is the plugin call that
      // promises no final result — exactly the teardown a half-open session
      // needs — and the failure is retryable, so the card's mic button
      // survives.
      logger.w('read-aloud: listen() never confirmed; cancelling session');
      _endSession();
      await _speech.cancel();
      _reportFailure(ReadAloudFailure.recognitionFailed);
      return;
    } on PlatformException catch (e, st) {
      logger.w(
        'read-aloud: listen failed (${e.code})',
        error: e,
        stackTrace: st,
      );
      _endSession();
      _reportFailure(_platformFailure(e.code));
      return;
    } catch (e, st) {
      logger.w('read-aloud: listen failed', error: e, stackTrace: st);
      _endSession();
      _reportFailure(ReadAloudFailure.recognitionFailed);
      return;
    }
    if (token != _sessionToken || _confirmedAlive) return;
    // `listen()` returned, but the platform can still fail to open the mic
    // at all (service stall, audio focus refused). The first `listening`
    // status or transcript disarms this watchdog.
    _listenWatchdog = Timer(kReadAloudStartWatchdog, () {
      _listenWatchdog = null;
      if (token != _sessionToken || _confirmedAlive) return;
      logger.w('read-aloud: no sign of recognition after start');
      _endSession();
      _reportFailure(ReadAloudFailure.recognitionFailed);
    });
  }

  /// Resolves the most appropriate locale identifier for [requestedLocale].
  ///
  /// Locale discovery is an optimization only. Some Android recognition
  /// services never answer it, so a failed or slow answer must not block the
  /// actual recognition request.
  @visibleForTesting
  Future<String> resolveLocaleId(String requestedLocale) async {
    try {
      final available = await _speech.locales().timeout(
            const Duration(seconds: 2),
          );
      if (available.isEmpty) return requestedLocale;
      final req = requestedLocale.replaceAll('_', '-').toLowerCase();
      for (final loc in available) {
        final id = loc.localeId.replaceAll('_', '-').toLowerCase();
        if (id == req) return loc.localeId;
      }
      for (final loc in available) {
        final id = loc.localeId.replaceAll('_', '-').toLowerCase();
        if (id.startsWith('$req-')) return loc.localeId;
      }
      final dash = req.indexOf('-');
      if (dash > 0) {
        final base = req.substring(0, dash);
        for (final loc in available) {
          final id = loc.localeId.replaceAll('_', '-').toLowerCase();
          if (id == base || id.startsWith('$base-')) return loc.localeId;
        }
      }
    } catch (e) {
      logger
          .w('read-aloud: locale discovery failed, using $requestedLocale: $e');
    }
    return requestedLocale;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    // The plugin waits out its final-result timeout after a stop and stays
    // silent when the wait fails; arm the same grace so a stop that never
    // delivers a final transcript still unblocks the card.
    if (_sessionActive && !_finalDelivered) {
      _armFinalGrace('stop produced no final transcript');
    }
  }

  void _beginSession() {
    _sessionActive = true;
    _confirmedAlive = false;
    _finalDelivered = false;
    _cancelWatchdogs();
  }

  void _endSession() {
    // Bumping the token also invalidates plugin callbacks still in flight.
    _sessionToken++;
    _sessionActive = false;
    _cancelWatchdogs();
  }

  void _cancelWatchdogs() {
    _listenWatchdog?.cancel();
    _listenWatchdog = null;
    _finalGrace?.cancel();
    _finalGrace = null;
  }

  /// Plugin status notifications, wired once at `initialize` and shared by
  /// every session; the guards keep them scoped to the active one.
  void _onPluginStatus(String status) {
    if (!_sessionActive) return;
    if (status == SpeechToText.listeningStatus) {
      _confirmedAlive = true;
      _listenWatchdog?.cancel();
      _finalGrace?.cancel();
      return;
    }
    if (status != SpeechToText.notListeningStatus &&
        status != SpeechToText.doneStatus) {
      return;
    }
    // `notListening` before any sign of life is startup ordering noise on
    // some devices, not a session end.
    if (!_confirmedAlive) return;
    if (_finalDelivered) {
      _endSession();
      return;
    }
    _armFinalGrace('session ended without a final transcript');
  }

  void _armFinalGrace(String reason) {
    _finalGrace?.cancel();
    _finalGrace = Timer(kReadAloudFinalGrace, () {
      _finalGrace = null;
      if (!_sessionActive || _finalDelivered) return;
      logger.w('read-aloud: $reason');
      _endSession();
      _reportFailure(ReadAloudFailure.recognitionFailed);
    });
  }

  void _reportFailure(ReadAloudFailure failure) {
    _lastFailure = failure;
    _errorListener?.call(failure);
  }

  static ReadAloudFailure _platformFailure(String code) {
    if (code == 'recognizerNotAvailable') {
      return ReadAloudFailure.serviceUnavailable;
    }
    return _categorize(code);
  }

  /// Maps `speech_to_text` error messages onto the coarse categories the UI
  /// needs. Unknown ones degrade to a retry-able failure rather than claiming
  /// the whole feature is broken.
  @visibleForTesting
  static ReadAloudFailure categorizeFailure(String errorMsg) {
    return _categorize(errorMsg);
  }

  static ReadAloudFailure _categorize(String errorMsg) {
    if (errorMsg.contains('permission')) {
      return ReadAloudFailure.permissionDenied;
    }
    if (errorMsg.contains('language_not_supported') ||
        errorMsg.contains('language_unavailable') ||
        errorMsg.contains('recognizerNotAvailable')) {
      return ReadAloudFailure.serviceUnavailable;
    }
    if (errorMsg.contains('network') ||
        errorMsg.contains('server') ||
        errorMsg.contains('too_many_requests')) {
      return ReadAloudFailure.networkUnavailable;
    }
    return ReadAloudFailure.recognitionFailed;
  }
}

/// Every platform without a recognizer: the companion build and web.
///
/// The read-aloud renderer checks [isSupported] before touching anything
/// else, so a call reaching [start] is a wiring bug, not a user state — it
/// fails loudly instead of pretending to listen.
class UnavailableReadAloudBackend implements ReadAloudBackend {
  const UnavailableReadAloudBackend();

  @override
  bool get isSupported => false;

  @override
  ReadAloudFailure? get lastFailure => ReadAloudFailure.serviceUnavailable;

  @override
  Future<bool> ensureReady() async => false;

  @override
  Future<void> start({
    required String locale,
    required ReadAloudResultListener onResult,
    required ReadAloudErrorListener onError,
  }) {
    throw StateError('read-aloud recognition is not available on this build');
  }

  @override
  Future<void> stop() async {}
}

/// The backend this build should use (ADR 0061: Android/iOS only).
ReadAloudBackend createReadAloudBackend() {
  // Constructing `SpeechToText()` is pure Dart — the platform channel is only
  // touched on initialize/listen — but there is no reason to build even the
  // object on targets that can never use it.
  if (isHarmonyOsTarget || kIsWeb) return const UnavailableReadAloudBackend();
  return SpeechToTextReadAloudBackend(SpeechToText());
}
