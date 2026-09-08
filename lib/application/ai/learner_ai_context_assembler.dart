// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/di/injection.dart';

/// Best-effort read-only assembly of [LearnerAiContext] from registered
/// providers. Never throws; returns empty language context on failure.
class LearnerAiContextAssembler {
  const LearnerAiContextAssembler._();

  /// The learner's current language; the registry default when DI is not
  /// available (tests, no-turkish-assets startup paths).
  static String _currentLanguageName() {
    if (getIt.isRegistered<LanguageProvider>()) {
      return getIt<LanguageProvider>().displayName;
    }
    return LanguageRegistry.instance.defaultLanguage.displayName;
  }

  /// Assemble when [inject] is true; otherwise returns empty language-only
  /// context so callers can always `setLearnerContext` without branching.
  static Future<LearnerAiContext> assembleIfInjectEnabled({
    String? languageName,
    String? cefrLevel,
    AiExplainPrefsStore? prefs,
    bool? injectOverride,
  }) async {
    final inject = injectOverride ??
        AiExplainPrefsStore.resolve(prefs: prefs, allowEphemeral: true)
            .injectLearnerContext;
    final name = languageName ?? _currentLanguageName();
    if (!inject) {
      return LearnerAiContext.empty(name);
    }
    return assemble(languageName: name, cefrLevel: cefrLevel);
  }

  static Future<LearnerAiContext> assemble({
    String? languageName,
    String? cefrLevel,
  }) async {
    final name = languageName ?? _currentLanguageName();
    final mistakes = <String>[];
    final weak = <String>[];

    try {
      if (getIt.isRegistered<MistakeProvider>()) {
        final mp = getIt<MistakeProvider>();
        for (final e in mp.entries.take(12)) {
          mistakes.add(LearnerAiContext.summarizeMistake(
            prompt: e.interactionId.isNotEmpty ? e.interactionId : e.lessonId,
            userAnswer: e.userAnswer,
          ));
        }
      }
    } catch (_) {}

    try {
      if (getIt.isRegistered<StudyStatsProvider>()) {
        final words = await getIt<StudyStatsProvider>().getWeakWords(limit: 8);
        for (final w in words) {
          weak.add(w.displayText);
        }
      }
    } catch (_) {}

    return LearnerAiContext.assemble(
      languageName: name,
      cefrLevel: cefrLevel,
      recentMistakeSummaries: mistakes,
      weakTerms: weak,
    );
  }
}
