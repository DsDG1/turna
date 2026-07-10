// Project imports:
import 'package:varnamala/domain/course/expression.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/listening_phase.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/course/sub_lesson.dart';
import 'package:varnamala/domain/course/word_entry.dart';

/// Thrown by [validateSwahiliCourse] when the bundled course JSON violates a
/// structural invariant. Carries every problem found in one pass so an
/// author can fix them all at once instead of one error per run.
class CourseValidationException implements Exception {
  final List<String> errors;

  const CourseValidationException(this.errors);

  @override
  String toString() {
    if (errors.length == 1) {
      return 'CourseValidationException: ${errors.first}';
    }
    final buffer = StringBuffer('CourseValidationException (${errors.length} '
        'problems):');
    for (final e in errors) {
      buffer.write('\n  - ');
      buffer.write(e);
    }
    return buffer.toString();
  }
}

/// Strictly validate a parsed course tree against the invariants the rest of
/// the app relies on. Collects every violation, then throws a single
/// [CourseValidationException]; returns normally if the tree is well-formed.
///
/// Invariants:
///  - Section / Unit / Lesson / Stage / Interaction ids are non-empty.
///  - Section ids are unique; unit ids unique across the course; lesson ids
///    unique across the course; stage ids unique within a lesson; item ids
///    non-empty and unique within a stage.
///  - Sub-lesson ids are unique within a lesson; listening phase ids are unique
///    within a lesson.
///  - Every stage has at least one item; every lesson has at least one content
///    structure (stages, subLessons, or listeningPhases).
///  - Every [ShowWord.wordId] resolves to a [WordEntry] in [vocabulary].
///  - Every [ShowWord.expressionId] (when present) resolves to an [Expression]
///    in [expressions].
void validateSwahiliCourse(
  List<Section> sections,
  List<WordEntry> vocabulary, [
  List<Expression> expressions = const [],
]) {
  final errors = <String>[];
  final vocabIds = <String>{for (final w in vocabulary) w.id};
  final expressionIds = <String>{for (final e in expressions) e.id};

  // Sections.
  final sectionIds = <String>{};
  for (final section in sections) {
    if (section.id.isEmpty) {
      errors.add('Section "${section.name}" has an empty id.');
    } else if (!sectionIds.add(section.id)) {
      errors.add('Duplicate section id: ${section.id}.');
    }
  }

  // Units.
  final unitIds = <String>{};
  for (final section in sections) {
    for (final unit in section.units) {
      if (unit.id.isEmpty) {
        errors.add('Unit "${unit.name}" in section ${section.id} has an empty '
            'id.');
      } else if (!unitIds.add(unit.id)) {
        errors.add('Duplicate unit id: ${unit.id}.');
      }
    }
  }

  // Lessons, stages, items.
  final lessonIds = <String>{};
  for (final section in sections) {
    for (final unit in section.units) {
      for (final lesson in unit.lessons) {
        if (lesson.id.isEmpty) {
          errors.add('Lesson "${lesson.name}" in unit ${unit.id} has an empty '
              'id.');
        } else if (!lessonIds.add(lesson.id)) {
          errors.add('Duplicate lesson id: ${lesson.id}.');
        }

        _validateLessonContent(lesson, vocabIds, expressionIds, errors);
      }
    }
  }

  if (errors.isNotEmpty) {
    throw CourseValidationException(errors);
  }
}

/// Validate a single [section] in isolation against the invariants the rest
/// of the app relies on at runtime. This is the per-section gate run when a
/// section's body is loaded on demand; it covers everything that can be
/// checked without the rest of the course:
///  - Unit ids are non-empty and unique within this section.
///  - Lesson ids are non-empty and unique within this section.
///  - Stage / sub-lesson / listening-phase / item id rules (via
///    [_validateLessonContent]).
///  - Every [ShowWord.wordId] resolves to a [WordEntry] in [vocabIds].
///  - Every [ShowWord.expressionId] (when present) resolves to an [Expression]
///    in [expressionIds].
///
/// Cross-course invariants (unit/lesson ids unique across the whole course)
/// are NOT checked here — those need every section assembled together and are
/// enforced offline/CI by [validateSwahiliCourse].
void validateSection(
  Section section,
  Set<String> vocabIds, [
  Set<String> expressionIds = const {},
]) {
  final errors = <String>[];

  if (section.id.isEmpty) {
    errors.add('Section "${section.name}" has an empty id.');
  }

  // Units (unique within this section).
  final unitIds = <String>{};
  for (final unit in section.units) {
    if (unit.id.isEmpty) {
      errors.add('Unit "${unit.name}" in section ${section.id} has an empty '
          'id.');
    } else if (!unitIds.add(unit.id)) {
      errors.add('Duplicate unit id: ${unit.id} (within section '
          '${section.id}).');
    }
  }

  // Lessons, stages, items (unique within this section).
  final lessonIds = <String>{};
  for (final unit in section.units) {
    for (final lesson in unit.lessons) {
      if (lesson.id.isEmpty) {
        errors.add('Lesson "${lesson.name}" in unit ${unit.id} has an empty '
            'id.');
      } else if (!lessonIds.add(lesson.id)) {
        errors.add('Duplicate lesson id: ${lesson.id} (within section '
            '${section.id}).');
      }

      _validateLessonContent(lesson, vocabIds, expressionIds, errors);
    }
  }

  if (errors.isNotEmpty) {
    throw CourseValidationException(errors);
  }
}

void _validateLessonContent(
  Lesson lesson,
  Set<String> vocabIds,
  Set<String> expressionIds,
  List<String> errors,
) {
  final content = lesson.content;

  // Legacy / review / challenge / reading-question path.
  final stages = content.stages;
  final subLessons = content.subLessons;
  final listeningPhases = content.listeningPhases;

  final hasStages = stages.isNotEmpty;
  final hasSubLessons = subLessons.isNotEmpty;
  final hasListeningPhases = listeningPhases.isNotEmpty;
  final hasReadingPassage = content.readingPassage != null || content.passage.isNotEmpty;

  // Template / content shape consistency.
  switch (lesson.template) {
    case LessonTemplate.intro:
    case LessonTemplate.practice:
      if (!hasSubLessons) {
        errors.add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
            'but has no subLessons.');
        return;
      }
      break;
    case LessonTemplate.listening:
      if (!hasListeningPhases) {
        errors.add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
            'but has no listeningPhases.');
        return;
      }
      break;
    case LessonTemplate.reading:
      if (!hasReadingPassage) {
        errors.add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
            'but has no readingPassage or legacy passage.');
        return;
      }
      break;
    case LessonTemplate.mastery:
      if (!hasStages) {
        errors.add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
            'but has no stages.');
        return;
      }
      if (stages.length > 1) {
        errors.add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
            'and should have a single stage, but has ${stages.length}.');
      }
      break;
    case LessonTemplate.legacy:
    case LessonTemplate.review:
      if (!hasStages && !hasSubLessons && !hasListeningPhases) {
        errors.add('Lesson ${lesson.id} has no stages, subLessons, or '
            'listeningPhases.');
        return;
      }
      break;
  }

  if (hasStages) {
    _validateStages(lesson, stages, vocabIds, expressionIds, errors);
  }

  if (hasSubLessons) {
    _validateSubLessons(lesson, subLessons, vocabIds, expressionIds, errors);
  }

  if (hasListeningPhases) {
    _validateListeningPhases(lesson, listeningPhases, vocabIds, expressionIds, errors);
  }
}

void _validateStages(
  Lesson lesson,
  List<Stage> stages,
  Set<String> vocabIds,
  Set<String> expressionIds,
  List<String> errors, {
  String contextPrefix = '',
}) {
  final prefix = contextPrefix.isEmpty ? '' : '$contextPrefix / ';
  final stageIds = <String>{};
  for (final stage in stages) {
    if (stage.id.isEmpty) {
      errors.add('${prefix}Stage "${stage.name}" in lesson ${lesson.id} has an '
          'empty id.');
    } else if (!stageIds.add(stage.id)) {
      errors.add('${prefix}Duplicate stage id "${stage.id}" in lesson '
          '${lesson.id}.');
    }

    final items = stage.items;
    if (items.isEmpty) {
      errors.add('${prefix}Stage ${stage.id} in lesson ${lesson.id} has no '
          'items.');
      continue;
    }

    final itemIds = <String>{};
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.id.isEmpty) {
        errors.add('${prefix}Item #$i in stage ${stage.id} (lesson ${lesson.id}) '
            'has an empty id.');
      } else if (!itemIds.add(item.id)) {
        errors.add('${prefix}Duplicate item id "${item.id}" in stage '
            '${stage.id} (lesson ${lesson.id}).');
      }
      if (item is ShowWord) {
        if (!vocabIds.contains(item.wordId)) {
          errors.add('${prefix}ShowWord "${item.id}" in stage ${stage.id} (lesson '
              '${lesson.id}) references missing wordId '
              '${item.wordId}.');
        }
        if (item.expressionId != null &&
            !expressionIds.contains(item.expressionId!)) {
          errors.add('${prefix}ShowWord "${item.id}" in stage ${stage.id} (lesson '
              '${lesson.id}) references missing expressionId '
              '${item.expressionId}.');
        }
      }
    }
  }
}

void _validateSubLessons(
  Lesson lesson,
  List<SubLesson> subLessons,
  Set<String> vocabIds,
  Set<String> expressionIds,
  List<String> errors,
) {
  final subLessonIds = <String>{};
  for (final subLesson in subLessons) {
    if (subLesson.id.isEmpty) {
      errors.add('SubLesson "${subLesson.name}" in lesson ${lesson.id} has an '
          'empty id.');
    } else if (!subLessonIds.add(subLesson.id)) {
      errors.add('Duplicate subLesson id "${subLesson.id}" in lesson '
          '${lesson.id}.');
    }

    if (subLesson.stages.isEmpty) {
      errors.add('SubLesson ${subLesson.id} in lesson ${lesson.id} has no '
          'stages.');
      continue;
    }

    _validateStages(
      lesson,
      subLesson.stages,
      vocabIds,
      expressionIds,
      errors,
      contextPrefix: subLesson.id,
    );
  }
}

void _validateListeningPhases(
  Lesson lesson,
  List<ListeningPhase> phases,
  Set<String> vocabIds,
  Set<String> expressionIds,
  List<String> errors,
) {
  final phaseIds = <String>{};
  for (final phase in phases) {
    if (phase.id.isEmpty) {
      errors.add('ListeningPhase "${phase.name}" in lesson ${lesson.id} has an '
          'empty id.');
    } else if (!phaseIds.add(phase.id)) {
      errors.add('Duplicate listeningPhase id "${phase.id}" in lesson '
          '${lesson.id}.');
    }

    // Summary phases may have no items; the other two must have items.
    if (phase.type != ListeningPhaseType.summary && phase.items.isEmpty) {
      errors.add('ListeningPhase ${phase.id} in lesson ${lesson.id} has no '
          'items.');
      continue;
    }

    final itemIds = <String>{};
    for (var i = 0; i < phase.items.length; i++) {
      final item = phase.items[i];
      if (item.id.isEmpty) {
        errors.add('Item #$i in listeningPhase ${phase.id} (lesson ${lesson.id}) '
            'has an empty id.');
      } else if (!itemIds.add(item.id)) {
        errors.add('Duplicate item id "${item.id}" in listeningPhase '
            '${phase.id} (lesson ${lesson.id}).');
      }
      if (item is ShowWord) {
        if (!vocabIds.contains(item.wordId)) {
          errors.add('ShowWord "${item.id}" in listeningPhase ${phase.id} (lesson '
              '${lesson.id}) references missing wordId ${item.wordId}.');
        }
        if (item.expressionId != null &&
            !expressionIds.contains(item.expressionId!)) {
          errors.add('ShowWord "${item.id}" in listeningPhase ${phase.id} (lesson '
              '${lesson.id}) references missing expressionId '
              '${item.expressionId}.');
        }
      }
    }
  }
}