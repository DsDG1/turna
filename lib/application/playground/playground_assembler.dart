// Dart imports:
import 'dart:math';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/playground/language_playground_eligibility.dart';
import 'package:turna/application/playground/playground_content_source.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/stage.dart';

/// Assembles a synthetic Playground [Lesson] from the current language
/// course only (计划 §7). Mirrors [DailyChallengeAssembler]'s contract —
/// produce a [Lesson] with one [Stage]; the session view-model and renderers
/// handle answering — but every entry point re-checks course eligibility
/// and re-filters Anki content instead of trusting the caller.
class PlaygroundAssembler {
  /// Synthetic ids for the assembled lesson + stage. Stable so per-item
  /// state keys remain consistent within a session.
  static const String lessonId = 'playground';
  static const String stageId = 'playground-stage';

  /// 单词配对至少需要的词对数；不足时模式标记不可用，不用外部词表填充
  /// （计划 §7.3）。
  static const int minWordPairsForMatch = 4;

  final PlaygroundContentSource _source;

  PlaygroundAssembler(this._source);

  PlaygroundAssembler.forCourseProvider(CourseProvider courseProvider)
      : this(PlaygroundContentSource(courseProvider));

  /// Assemble a session for [config].
  ///
  /// [courseScope] is re-checked here (layer 3): even a caller that bypasses
  /// the entry and page guards gets an explicit [ineligibleCourse] result,
  /// never a silent pool. [weakEntries] feeds the weak content scope.
  /// [random] drives the deterministic shuffle — tests inject a seeded
  /// [Random]; production callers pass `Random()` per session.
  Future<PlaygroundAssemblyResult> assemble(
    PlaygroundSessionConfig config, {
    required String courseScope,
    Random? random,
    List<MistakeEntry> weakEntries = const [],
  }) async {
    if (!LanguagePlaygroundEligibility.isEligibleScope(courseScope)) {
      return const PlaygroundUnavailable(
        reason: PlaygroundUnavailableReason.ineligibleCourse,
      );
    }
    final bundle = await _source.load(
      config.contentScope,
      weakEntries: weakEntries,
    );
    if (bundle.allSectionsFailed) {
      return PlaygroundUnavailable(
        reason: PlaygroundUnavailableReason.sectionLoadFailed,
        availableAlternatives: const {},
      );
    }

    if (config.mode == PlaygroundMode.wordMatch) {
      return _assembleWordMatch(bundle, config, random);
    }

    final pool = dedupeCandidates(
      bundle.candidates
          .where((c) => matchesMode(config.mode, c.interaction))
          .toList(growable: false),
    );
    if (pool.isEmpty) {
      return PlaygroundUnavailable(
        reason: bundle.candidates.isEmpty
            ? PlaygroundUnavailableReason.noCourseContent
            : PlaygroundUnavailableReason.noItemsForMode,
        availableAlternatives: availableModes(bundle),
      );
    }

    final selected = takeShuffled(pool, config.targetQuestionCount, random);
    return PlaygroundReady(
      lesson: _buildLesson(selected),
      metadata: PlaygroundSessionMetadata(
        questionCount: selected.length,
        sourceLessonIds: selected.map((c) => c.lessonId).toSet(),
      ),
    );
  }

  /// Which modes the UI grid should offer as available for [bundle]
  /// (计划 §4.2: 不可用模式显示原因，而不是点击后进入空页面).
  static Set<PlaygroundMode> availableModes(PlaygroundContentBundle bundle) {
    final available = <PlaygroundMode>{};
    for (final mode in PlaygroundMode.values) {
      if (mode == PlaygroundMode.wordMatch) {
        if (bundle.wordIds.length >= minWordPairsForMatch) {
          available.add(mode);
        }
      } else if (bundle.candidates.any((c) => matchesMode(mode, c.interaction))) {
        available.add(mode);
      }
    }
    return available;
  }

  /// Mode → interaction mapping (计划 §5). Pure so tests can pin each mode.
  static bool matchesMode(PlaygroundMode mode, Interaction interaction) {
    // Defense in depth: even though the content source already filters,
    // keep the Anki blacklist here so no future call path can smuggle an
    // Anki card into a pool.
    if (!PlaygroundContentSource.isLanguageInteraction(interaction)) {
      return false;
    }
    return switch (mode) {
      PlaygroundMode.smartMix ||
      PlaygroundMode.dailyMix =>
        isSmartMixGradable(interaction),
      PlaygroundMode.wordMatch => false, // word-pair driven, not pooled
      PlaygroundMode.quickChoice =>
        interaction is MultipleChoice || interaction is ReadingMcq,
      PlaygroundMode.listenAndPick => interaction is ListenAndPick,
      PlaygroundMode.dictation => interaction is TypeTheWord,
      PlaygroundMode.sentenceOrder => interaction is ReorderSentence,
      PlaygroundMode.fillBlank => interaction is FillBlank,
      PlaygroundMode.translation =>
        interaction is TranslateSentence ||
            interaction is ReadingShortAnswer,
    };
  }

  /// Smart mix pools every gradable language interaction — display cards and
  /// listen-only items have no answer and would stall the graded flow.
  /// Public for [PlaygroundIndex]'s single-pass classification.
  static bool isSmartMixGradable(Interaction interaction) =>
      interaction is! ShowWord && interaction is! ListenOnly;

  /// Deterministic dedup: the same authored question (lesson + interaction
  /// id) appears at most once per session (计划 §5.1 rule 4). Legacy items
  /// with empty ids are kept by object identity.
  static List<PlaygroundInteractionCandidate> dedupeCandidates(
    List<PlaygroundInteractionCandidate> candidates,
  ) {
    final seen = <String>{};
    final out = <PlaygroundInteractionCandidate>[];
    for (final candidate in candidates) {
      final interactionId = candidate.interaction.id;
      final key = interactionId.isEmpty
          ? 'identity:${identityHashCode(candidate.interaction)}'
          : '${candidate.lessonId}:$interactionId';
      if (seen.add(key)) out.add(candidate);
    }
    return out;
  }

  /// Fisher–Yates partial shuffle, then trim to [count] — same seed yields
  /// the same selection and order (计划 §3 rule 10).
  static List<PlaygroundInteractionCandidate> takeShuffled(
    List<PlaygroundInteractionCandidate> pool,
    int count,
    Random? random,
  ) {
    if (pool.isEmpty || count <= 0) return const [];
    final rng = random ?? Random();
    final remaining = List<PlaygroundInteractionCandidate>.of(pool);
    final n = count < remaining.length ? count : remaining.length;
    for (var i = 0; i < n; i++) {
      final j = i + rng.nextInt(remaining.length - i);
      final tmp = remaining[i];
      remaining[i] = remaining[j];
      remaining[j] = tmp;
    }
    return remaining.sublist(0, n);
  }

  PlaygroundAssemblyResult _assembleWordMatch(
    PlaygroundContentBundle bundle,
    PlaygroundSessionConfig config,
    Random? random,
  ) {
    if (bundle.wordIds.length < minWordPairsForMatch) {
      return PlaygroundUnavailable(
        reason: bundle.wordIds.isEmpty
            ? PlaygroundUnavailableReason.noCourseContent
            : PlaygroundUnavailableReason.noItemsForMode,
        availableAlternatives: availableModes(bundle),
      );
    }
    // The P2 match controller resolves these ids into current-course
    // WordEntry pairs; a ready result guarantees at least the minimum pair
    // count (计划 §7.3: 不足 4 对则禁用，不用外部固定词表填充).
    final shuffled = _shuffleWordIds(bundle.wordIds, random);
    final selected = shuffled
        .take(config.targetQuestionCount < minWordPairsForMatch
            ? minWordPairsForMatch
            : config.targetQuestionCount)
        .toSet();
    return PlaygroundReady(
      lesson: _buildLesson(const []),
      wordIds: selected,
      metadata: PlaygroundSessionMetadata(
        questionCount: selected.length,
        sourceLessonIds: bundle.candidates.map((c) => c.lessonId).toSet(),
      ),
    );
  }

  /// Deterministic word-id shuffle: sort first (sets iterate in insertion
  /// order, which is input-history dependent), then Fisher–Yates with the
  /// injected [Random].
  static List<String> _shuffleWordIds(Set<String> wordIds, Random? random) {
    final ordered = wordIds.toList()..sort();
    final rng = random ?? Random();
    for (var i = ordered.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = ordered[i];
      ordered[i] = ordered[j];
      ordered[j] = tmp;
    }
    return ordered;
  }

  Lesson _buildLesson(List<PlaygroundInteractionCandidate> selected) {
    // Stamp per-position ids so view-model interaction keys stay unique even
    // when the source items carried empty (legacy) ids.
    final reidentified = [
      for (var i = 0; i < selected.length; i++)
        selected[i].interaction.copyWith(id: 'pg-$i'),
    ];
    final stage = Stage(
      id: stageId,
      name: 'Playground',
      items: reidentified,
    );
    return Lesson(
      id: lessonId,
      name: 'Playground',
      type: LessonType.challenge,
      template: LessonTemplate.legacy,
      content: LessonContent(stages: [stage]),
    );
  }
}
