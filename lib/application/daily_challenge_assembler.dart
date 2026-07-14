// Dart imports:
import 'dart:math';

// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/stage.dart';

/// Assembles a "Daily Challenge" — a synthetic [Lesson] holding a random
/// sample of real authored questions drawn from the loaded course tree.
///
/// The challenge reuses [LessonViewModel] end-to-end, so this class only
/// needs to produce a [Lesson] with one [Stage] of ~15 [Interaction]s; the
/// viewmodel + renderers handle answering, grading, XP, and completion.
class DailyChallengeAssembler {
  final CourseProvider _courseProvider;

  /// Synthetic ids for the assembled lesson + stage. Stable so the
  /// viewmodel's per-item state keys remain consistent within a session.
  static const String lessonId = 'daily-challenge';
  static const String stageId = 'daily-challenge-stage';

  DailyChallengeAssembler(this._courseProvider);

  /// Build a challenge [Lesson] with up to [count] random gradable
  /// interactions sampled (without replacement) from the loaded course tree.
  /// If fewer than [count] gradable items exist, all of them are used — the
  /// challenge is never padded with synthetic questions.
  Lesson assemble({required int count, required Random random}) {
    final pool = collectGradableInteractions(_courseProvider);
    final selected = pickChallengeItems(pool, count, random);
    // Stamp each picked item with a stable per-position id so the viewmodel's
    // interactionItemId keys are unique even when the source items carried
    // empty ids (legacy data).
    final reidentified = [
      for (var i = 0; i < selected.length; i++)
        selected[i].copyWith(id: 'challenge-$i'),
    ];

    final stage = Stage(
      id: stageId,
      name: 'Challenge',
      items: reidentified,
    );

    return Lesson(
      id: lessonId,
      name: 'Daily Challenge',
      type: LessonType.challenge,
      template: LessonTemplate.legacy,
      content: LessonContent(stages: [stage]),
    );
  }

  /// Gather every gradable [Interaction] from the loaded course sections.
  ///
  /// Only sections whose bodies have been loaded contribute items (shells
  /// have empty `units` and are skipped naturally), so this never triggers
  /// a full course load. [ShowWord] (display card, no answer) and
  /// [ListenOnly] (no grading) are excluded — they would stall the
  /// graded challenge flow.
  static List<Interaction> collectGradableInteractions(
    CourseProvider courseProvider,
  ) {
    final pool = <Interaction>[];
    for (final section in courseProvider.sections) {
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          for (final stage in lesson.flattenedStages) {
            for (final item in stage.items) {
              if (isChallengeGradable(item)) pool.add(item);
            }
          }
        }
      }
    }
    return pool;
  }
}

/// True for interactions that have a gradeable correct answer and thus fit
/// the challenge's "answer → correct/incorrect" flow.
bool isChallengeGradable(Interaction interaction) {
  return interaction is! ShowWord && interaction is! ListenOnly;
}

/// Sample [count] items from [pool] without replacement using [random].
/// Returns all of [pool] (shuffled) when it has fewer than [count] items.
List<Interaction> pickChallengeItems(
  List<Interaction> pool,
  int count,
  Random random,
) {
  if (pool.isEmpty || count <= 0) return const [];
  final remaining = List<Interaction>.of(pool);
  final n = count < remaining.length ? count : remaining.length;
  // Fisher–Yates partial shuffle: pick n random positions from the front.
  for (var i = 0; i < n; i++) {
    final j = i + random.nextInt(remaining.length - i);
    final tmp = remaining[i];
    remaining[i] = remaining[j];
    remaining[j] = tmp;
  }
  return remaining.sublist(0, n);
}