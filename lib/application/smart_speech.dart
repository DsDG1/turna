// Project imports:
import 'package:flutter/widgets.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/language_detector.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/language_codes.dart';

/// The target and native (translation) TTS languages for the currently
/// active course.
class SpeechLanguages {
  const SpeechLanguages({
    required this.target,
    required this.native,
    this.signatureChars,
  });

  /// BCP-47 base code of the language being learned (e.g. `tr`).
  final String target;

  /// BCP-47 base code of the learner's translation / native language for this
  /// course (e.g. `en`), used as the TTS fallback for plain-Latin text.
  final String native;

  /// The target language's distinguishing-letter set, forwarded to
  /// [LanguageDetector]'s `signatureChars`. `null` keeps the detector's
  /// Turkish default.
  final String? signatureChars;
}

/// Resolve the target + native TTS languages for the active course.
///
/// Falls back to Turkish-target / English-native when DI is unavailable
/// (some unit tests don't register the full provider graph) so callers never
/// throw just because smart-speech can't resolve its inputs.
SpeechLanguages currentSpeechLanguages() {
  try {
    final languageProvider = getIt<LanguageProvider>();
    final code = languageProvider.selectedLanguageCode;
    final target = languageProvider.ttsLanguageCode;
    final scope = getIt<CourseProvider>().courseScope;
    final native = getIt<SettingsProvider>().nativeLanguageCodeFor(scope);
    return SpeechLanguages(
      target: target,
      native: native,
      // The trailing `?? ''` is "no signature", NOT "keep the detector's
      // Turkish default": a course that declares no signature set (e.g. an
      // imported pack without `signatureChars`) must not route Turkish
      // letters in its translations to the target-language voice. Builtin
      // tr/fr always declare their set, so '' only reaches undeclared
      // languages. The null below (DI failure) stays Turkish on purpose —
      // the app's original target language.
      signatureChars:
          ImportedLanguageRegistry.instance.signatureCharsOrNull(code) ??
              LanguageRegistry.instance.signatureChars(code) ??
              '',
    );
  } catch (_) {
    return const SpeechLanguages(
      target: LanguageCodes.turkish,
      native: 'en',
      signatureChars: LanguageDetector.defaultSignatureChars,
    );
  }
}

/// Detect the spoken language of [text] using the active course's target +
/// native languages. Convenience wrapper for callers that don't need the
/// context-aware MCQ / card-pair heuristics in [LanguageDetector].
String detectSpeakLanguage(String text) {
  final langs = currentSpeechLanguages();
  return const LanguageDetector().detect(
    text,
    targetLanguage: langs.target,
    nativeLanguage: langs.native,
    signatureChars: langs.signatureChars,
  );
}

/// Whether the active course auto-reads content on tap / reveal.
///
/// Gated by the opt-in master switch ([SettingsProvider.ttsFeatureEnabled]):
/// while off, auto-read never fires even if a course opts in per-course.
/// Manual speak buttons are not affected.
bool autoReadOnTapForActiveCourse() {
  try {
    final settings = getIt<SettingsProvider>();
    if (!settings.ttsFeatureEnabled) return false;
    final scope = getIt<CourseProvider>().courseScope;
    return settings.autoReadOnTapFor(scope);
  } catch (_) {
    return false;
  }
}

/// Speaks after the first frame if auto-read is on. Failures stay with the
/// manual speaker button.
void maybeAutoSpeak(VoidCallback speak) {
  if (!autoReadOnTapForActiveCourse()) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    speak();
  });
  WidgetsBinding.instance.scheduleFrame();
}

/// Speaks a target-language word chip on tap — word-bank tokens in sentence
/// building, 选择填空 choice chips. Unlike MCQ options (where the tap means
/// "this is my answer" and the re-read follows the auto-read toggle), tapping
/// one of these chips is the learner directly handling language material, so
/// the read-aloud is part of the action itself — the same stance as the
/// ShowWord card's word tap. Chips are always target-language text, so no
/// language inference is needed.
///
/// Returns `null` when the controller is not registered (tests without a
/// full DI graph); callers stay silent — the pick/fill action must not
/// depend on audio being available.
Future<TtsSpeakResult?> speakTargetChip(String text) async {
  try {
    final controller = getIt<AudioController>();
    return await controller.speakWithResult(
      text,
      languageCode: currentSpeechLanguages().target,
    );
  } catch (_) {
    // Best-effort audio: no controller means no sound, not a failed action.
    return null;
  }
}
