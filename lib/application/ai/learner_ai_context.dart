// Dart imports:
import 'dart:math' as math;

/// Read-only learner snapshot for companion AI system prompts.
///
/// Pure data + formatting — assembled by callers from MistakeProvider /
/// weak words / CEFR. Does not depend on UI or network.
class LearnerAiContext {
  LearnerAiContext({
    required this.languageName,
    this.cefrLevel,
    this.recentMistakeSummaries = const [],
    this.weakTerms = const [],
    this.recentLessonTitles = const [],
    DateTime? builtAt,
  }) : builtAt = builtAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String languageName;
  final String? cefrLevel;
  final List<String> recentMistakeSummaries;
  final List<String> weakTerms;
  final List<String> recentLessonTitles;
  final DateTime builtAt;

  /// Empty context for [language] (still names the language).
  static LearnerAiContext empty(String language) => LearnerAiContext(
        languageName: language,
        builtAt: DateTime.now(),
      );

  bool get isEmpty =>
      (cefrLevel == null || cefrLevel!.isEmpty) &&
      recentMistakeSummaries.isEmpty &&
      weakTerms.isEmpty &&
      recentLessonTitles.isEmpty;

  /// Format as a prompt block. Dedupes lines, caps item counts, then hard-
  /// truncates to [maxChars] with a trailing ellipsis.
  String toPromptBlock({
    int maxChars = 800,
    int maxMistakes = 8,
    int maxWeakTerms = 8,
    int maxLessons = 4,
  }) {
    final mistakes = _dedupeTrim(recentMistakeSummaries, maxMistakes);
    final weak = _dedupeTrim(weakTerms, maxWeakTerms);
    final lessons = _dedupeTrim(recentLessonTitles, maxLessons);

    final buf = StringBuffer()
      ..writeln('[LearnerContext]')
      ..writeln('Language: $languageName');
    if (cefrLevel != null && cefrLevel!.trim().isNotEmpty) {
      buf.writeln('CEFR: ${cefrLevel!.trim()}');
    }
    if (mistakes.isNotEmpty) {
      buf.writeln('Recent mistakes (deduped):');
      for (final m in mistakes) {
        buf.writeln('- $m');
      }
    }
    if (weak.isNotEmpty) {
      buf.writeln('Weak terms:');
      for (final w in weak) {
        buf.writeln('- $w');
      }
    }
    if (lessons.isNotEmpty) {
      buf.writeln('Recent lessons:');
      for (final l in lessons) {
        buf.writeln('- $l');
      }
    }
    buf.write('[/LearnerContext]');

    final raw = buf.toString();
    if (raw.length <= maxChars) return raw;
    if (maxChars <= 1) return '…';
    return '${raw.substring(0, maxChars - 1)}…';
  }

  /// Assemble from raw lists with default caps (for provider use).
  static LearnerAiContext assemble({
    required String languageName,
    String? cefrLevel,
    List<String> recentMistakeSummaries = const [],
    List<String> weakTerms = const [],
    List<String> recentLessonTitles = const [],
    int maxMistakes = 8,
    int maxWeakTerms = 8,
  }) {
    return LearnerAiContext(
      languageName: languageName,
      cefrLevel: cefrLevel,
      recentMistakeSummaries:
          _dedupeTrim(recentMistakeSummaries, maxMistakes),
      weakTerms: _dedupeTrim(weakTerms, maxWeakTerms),
      recentLessonTitles: _dedupeTrim(recentLessonTitles, 4),
      builtAt: DateTime.now(),
    );
  }

  static List<String> _dedupeTrim(List<String> items, int max) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      final key = s.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(s);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Soft-cap a single long summary line.
  static String summarizeMistake({
    required String prompt,
    String? userAnswer,
    int maxLen = 120,
  }) {
    final parts = <String>[prompt.trim()];
    if (userAnswer != null && userAnswer.trim().isNotEmpty) {
      parts.add('→ ${userAnswer.trim()}');
    }
    final joined = parts.join(' ');
    if (joined.length <= maxLen) return joined;
    return '${joined.substring(0, math.max(0, maxLen - 1))}…';
  }
}
