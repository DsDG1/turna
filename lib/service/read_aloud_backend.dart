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

// Package imports:
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

  /// The session started but recognition itself failed: nothing spoken,
  /// no match, network hiccup. Not an answer — the learner can tap the mic
  /// again.
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
  Future<void> start({
    required String locale,
    required ReadAloudResultListener onResult,
    required ReadAloudErrorListener onError,
  });

  /// Ends the session early, delivering a final result. Best-effort.
  Future<void> stop();
}

/// Android / iOS: `speech_to_text` (platform SpeechRecognizer /
/// SFSpeechRecognizer).
class SpeechToTextReadAloudBackend implements ReadAloudBackend {
  SpeechToTextReadAloudBackend(this._speech);

  final SpeechToText _speech;

  /// Errors observed outside a session (initialize-time) are parked here so
  /// a session that starts afterwards does not miss a permanent failure.
  ReadAloudErrorListener? _errorListener;

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensureReady() async {
    return _speech.initialize(
      onError: (error) {
        logger.w(
          'read-aloud: recognition error ${error.errorMsg} '
          '(permanent=${error.permanent})',
        );
        _errorListener?.call(_categorize(error.errorMsg));
      },
      // Status is not surfaced through the seam: the final result — not the
      // `done` status — is the session's completion signal, because only the
      // result carries the transcript the scorer needs.
      onStatus: (_) {},
    );
  }

  @override
  Future<void> start({
    required String locale,
    required ReadAloudResultListener onResult,
    required ReadAloudErrorListener onError,
  }) async {
    _errorListener = onError;
    final resolvedLocale = await resolveLocaleId(locale);
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: resolvedLocale,
        // A read-aloud utterance is short: end the session after a pause
        // rather than waiting for the recognizer's own timeouts, but cap the
        // whole session so a noisy room cannot record indefinitely.
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 15),
      ),
    );
  }

  /// Resolves the most appropriate locale identifier for [requestedLocale].
  ///
  /// On iOS / Android, recognizers frequently expose locales as region tags
  /// (e.g. `tr_TR` or `tr-TR`) rather than bare language codes (`tr`). When
  /// available, we find the best matching locale supported by the platform.
  @visibleForTesting
  Future<String> resolveLocaleId(String requestedLocale) async {
    try {
      final available = await _speech.locales();
      if (available.isEmpty) return requestedLocale;
      final req = requestedLocale.replaceAll('_', '-').toLowerCase();
      // 1. Exact match (case-insensitive)
      for (final loc in available) {
        final id = loc.localeId.replaceAll('_', '-').toLowerCase();
        if (id == req) return loc.localeId;
      }
      // 2. Region-tagged match for base language (e.g. 'tr' -> 'tr_TR' or 'tr-TR')
      for (final loc in available) {
        final id = loc.localeId.replaceAll('_', '-').toLowerCase();
        if (id.startsWith('$req-')) return loc.localeId;
      }
      // 3. Fallback: match base code if requested has region (e.g. 'tr-TR' -> 'tr')
      final dash = req.indexOf('-');
      if (dash > 0) {
        final base = req.substring(0, dash);
        for (final loc in available) {
          final id = loc.localeId.replaceAll('_', '-').toLowerCase();
          if (id == base || id.startsWith('$base-')) return loc.localeId;
        }
      }
    } catch (_) {
      // Best-effort: fall back to the raw requestedLocale when locales() fails
      // or in tests with partial mocks.
    }
    return requestedLocale;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
  }

  /// Maps `speech_to_text` error messages onto the coarse categories the UI
  /// needs. The messages come from the plugin's platform docs (see
  /// `SpeechErrorListener`); unknown ones degrade to a retry-able failure
  /// rather than claiming the whole feature is broken.
  @visibleForTesting
  static ReadAloudFailure categorizeFailure(String errorMsg) {
    return _categorize(errorMsg);
  }

  static ReadAloudFailure _categorize(String errorMsg) {
    if (errorMsg.contains('permission')) {
      return ReadAloudFailure.permissionDenied;
    }
    if (errorMsg.contains('language_not_supported') ||
        errorMsg.contains('language_unavailable')) {
      return ReadAloudFailure.serviceUnavailable;
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
