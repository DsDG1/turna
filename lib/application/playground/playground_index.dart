// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/playground/playground_assembler.dart';
import 'package:turna/application/playground/playground_content_source.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/domain/course/interaction.dart';

/// Cache key for a playground availability analysis (Plan 3 §22.2).
///
/// Built from data identity (scope + loaded-content fingerprint + mistake
/// snapshot fingerprint), NOT from provider notifications — an unrelated
/// [CourseProvider] notify (e.g. a preference change) must not invalidate a
/// still-valid index, and identical data must reuse the cached index.
class PlaygroundSourceRevision {
  const PlaygroundSourceRevision._(this.value);

  final String value;

  static PlaygroundSourceRevision of({
    required CourseProvider course,
    required MistakeProvider mistakes,
    required PlaygroundContentScope scope,
  }) {
    final loaded = course.loadedSectionCount;
    final total = course.sections.length;
    final mistakeCount = mistakes.count;
    // Any entry set change either alters the count or the newest entry's id.
    final newestMistake =
        mistakes.entries.isEmpty ? '' : mistakes.entries.first.id;
    return PlaygroundSourceRevision._(
      '${scope.name}|s$total|l$loaded|m$mistakeCount|$newestMistake',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaygroundSourceRevision && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// One-pass availability + count index over a content bundle (Plan 3 §22.1).
///
/// Replaces the per-mode `where + dedupe + length` loops (≈7 full scans plus
/// N `any()` probes per load) with a single traversal: dedupe first (same
/// canonical rule as [PlaygroundAssembler.dedupeCandidates]), then classify
/// each surviving candidate once against every mode.
class PlaygroundIndex {
  const PlaygroundIndex({
    required this.availableModes,
    required this.counts,
    required this.candidateCount,
    required this.wordPairCount,
  });

  final Set<PlaygroundMode> availableModes;
  final Map<PlaygroundMode, int> counts;
  final int candidateCount;
  final int wordPairCount;

  static PlaygroundIndex build(PlaygroundContentBundle bundle) {
    final trace = Stopwatch()..start();
    // Pass 1 — dedupe (lessonId + interaction id, identity for legacy items).
    final seen = <String>{};
    final deduped = <PlaygroundInteractionCandidate>[];
    for (final candidate in bundle.candidates) {
      final interactionId = candidate.interaction.id;
      final key = interactionId.isEmpty
          ? 'identity:${identityHashCode(candidate.interaction)}'
          : '${candidate.lessonId}:$interactionId';
      if (seen.add(key)) deduped.add(candidate);
    }

    // Pass 2 — classify each candidate once per mode family.
    final counts = <PlaygroundMode, int>{};
    void bump(PlaygroundMode mode) => counts[mode] = (counts[mode] ?? 0) + 1;
    for (final c in deduped) {
      final interaction = c.interaction;
      if (!PlaygroundContentSource.isLanguageInteraction(interaction)) {
        continue;
      }
      final gradable = PlaygroundAssembler.isSmartMixGradable(interaction);
      if (gradable) {
        bump(PlaygroundMode.smartMix);
        bump(PlaygroundMode.dailyMix);
      }
      switch (interaction) {
        case MultipleChoice() || ReadingMcq():
          bump(PlaygroundMode.quickChoice);
        case ListenAndPick():
          bump(PlaygroundMode.listenAndPick);
        case TypeTheWord():
          bump(PlaygroundMode.dictation);
        case ReorderSentence():
          bump(PlaygroundMode.sentenceOrder);
        case FillBlank():
          bump(PlaygroundMode.fillBlank);
        case TranslateSentence() || ReadingShortAnswer():
          bump(PlaygroundMode.translation);
        default:
          break;
      }
    }

    final available = <PlaygroundMode>{};
    counts.forEach((mode, count) {
      if (count > 0) available.add(mode);
    });
    if (bundle.wordIds.length >= PlaygroundAssembler.minWordPairsForMatch) {
      available.add(PlaygroundMode.wordMatch);
      counts[PlaygroundMode.wordMatch] = bundle.wordIds.length;
    } else {
      counts[PlaygroundMode.wordMatch] = bundle.wordIds.length;
    }

    final index = PlaygroundIndex(
      availableModes: available,
      counts: counts,
      candidateCount: deduped.length,
      wordPairCount: bundle.wordIds.length,
    );
    trace.stop();
    PerformanceTrace.instance.record(
      feature: 'playground',
      operation: 'index',
      duration: trace.elapsed,
      resultSize: index.candidateCount,
      cacheStatus: TraceCacheStatus.miss,
    );
    return index;
  }
}
