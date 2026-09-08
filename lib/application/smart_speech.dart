// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/language_detector.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/language_codes.dart';

/// The target and native (translation) TTS languages for the currently
/// active course.
class SpeechLanguages {
  const SpeechLanguages({required this.target, required this.native});

  /// BCP-47 base code of the language being learned (e.g. `tr`).
  final String target;

  /// BCP-47 base code of the learner's translation / native language for this
  /// course (e.g. `en`), used as the TTS fallback for plain-Latin text.
  final String native;
}

/// Resolve the target + native TTS languages for the active course.
///
/// Falls back to Turkish-target / English-native when DI is unavailable
/// (some unit tests don't register the full provider graph) so callers never
/// throw just because smart-speech can't resolve its inputs.
SpeechLanguages currentSpeechLanguages() {
  try {
    final target = getIt<LanguageProvider>().ttsLanguageCode;
    final scope = getIt<CourseProvider>().courseScope;
    final native = getIt<SettingsProvider>().nativeLanguageCodeFor(scope);
    return SpeechLanguages(target: target, native: native);
  } catch (_) {
    return SpeechLanguages(target: LanguageCodes.turkish, native: 'en');
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
