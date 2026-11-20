// Project imports:
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/guide_page.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/interaction_rules.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/listening_phase.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/sub_lesson.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Design-contract limits for course-tree performance (~9300 lessons target).
/// Enforced at seed/CI ([validateCourse] / [validateSection]) and on
/// runtime L1 open ([validateSectionTree]). Soft production targets are lower
/// (≈30 lessons/unit); these are hard fail ceilings.
const int kMaxUnitsPerSection = 60;
const int kMaxLessonsPerUnit = 40;

/// Thrown by [validateCourse] when the bundled course JSON violates a
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
///    structure (guide pages, stages, subLessons, or listeningPhases).
///  - Every [ShowWord.wordId] resolves to a [WordEntry] in [vocabulary].
///  - Every [ShowWord.expressionId] (when present) resolves to an [Expression]
///    in [expressions].
void validateCourse(
  List<Section> sections,
  List<WordEntry> vocabulary, [
  List<Expression> expressions = const [],
  List<GrammarPoint> grammarPoints = const [],
]) {
  final errors = <String>[];
  final vocabIds = <String>{for (final w in vocabulary) w.id};
  final expressionIds = <String>{for (final e in expressions) e.id};
  errors.addAll(collectResourceIdCollisionErrors(
    vocabulary: vocabulary,
    grammarPoints: grammarPoints,
    expressions: expressions,
  ));

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
    if (section.units.length > kMaxUnitsPerSection) {
      errors.add(
        'Section ${section.id} has ${section.units.length} units '
        '(max $kMaxUnitsPerSection).',
      );
    }
    for (final unit in section.units) {
      if (unit.id.isEmpty) {
        errors.add('Unit "${unit.name}" in section ${section.id} has an empty '
            'id.');
      } else if (!unitIds.add(unit.id)) {
        errors.add('Duplicate unit id: ${unit.id}.');
      }
      if (unit.lessons.length > kMaxLessonsPerUnit) {
        errors.add(
          'Unit ${unit.id} has ${unit.lessons.length} lessons '
          '(max $kMaxLessonsPerUnit).',
        );
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

/// Cross-pool id uniqueness within one language. `srs_states` is keyed by
/// `(language_code, word_id)` with no `queue` column in the PK, so an id
/// shared between the vocabulary / grammar / expression pools would make
/// their schedule rows clobber each other. Enforced at seed time (see
/// [DatabaseSeeder]) and inside [validateCourse].
List<String> collectResourceIdCollisionErrors({
  required Iterable<WordEntry> vocabulary,
  required Iterable<GrammarPoint> grammarPoints,
  required Iterable<Expression> expressions,
}) {
  final errors = <String>[];
  final ownerById = <String, String>{};
  void check(Iterable<String> ids, String pool) {
    for (final id in ids) {
      final owner = ownerById[id];
      if (owner != null && owner != pool) {
        errors.add('Id "$id" is used by both "$owner" and "$pool"; SRS state '
            'is keyed by (language_code, id) across pools and the rows would '
            'clobber each other.');
      } else {
        ownerById[id] ??= pool;
      }
    }
  }

  check(vocabulary.map((w) => w.id), 'vocabulary');
  check(grammarPoints.map((g) => g.id), 'grammar points');
  check(expressions.map((e) => e.id), 'expressions');
  return errors;
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
/// enforced offline/CI by [validateCourse].
void validateSection(
  Section section,
  Set<String> vocabIds, [
  Set<String> expressionIds = const {},
]) {
  final errors = <String>[];

  if (section.id.isEmpty) {
    errors.add('Section "${section.name}" has an empty id.');
  }

  if (section.units.length > kMaxUnitsPerSection) {
    errors.add(
      'Section ${section.id} has ${section.units.length} units '
      '(max $kMaxUnitsPerSection).',
    );
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
    if (unit.lessons.length > kMaxLessonsPerUnit) {
      errors.add(
        'Unit ${unit.id} has ${unit.lessons.length} lessons '
        '(max $kMaxLessonsPerUnit).',
      );
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

/// Lightweight L1 gate for runtime [CourseLoader.loadSection].
///
/// Checks ids, within-section uniqueness, and [kMaxUnitsPerSection] /
/// [kMaxLessonsPerUnit] only. Does **not** walk lesson content (bodies are
/// empty on the tree path and validated offline/CI or at seed time).
void validateSectionTree(Section section) {
  final errors = <String>[];

  if (section.id.isEmpty) {
    errors.add('Section "${section.name}" has an empty id.');
  }

  if (section.units.length > kMaxUnitsPerSection) {
    errors.add(
      'Section ${section.id} has ${section.units.length} units '
      '(max $kMaxUnitsPerSection).',
    );
  }

  final unitIds = <String>{};
  final lessonIds = <String>{};
  for (final unit in section.units) {
    if (unit.id.isEmpty) {
      errors.add('Unit "${unit.name}" in section ${section.id} has an empty '
          'id.');
    } else if (!unitIds.add(unit.id)) {
      errors.add('Duplicate unit id: ${unit.id} (within section '
          '${section.id}).');
    }
    if (unit.lessons.length > kMaxLessonsPerUnit) {
      errors.add(
        'Unit ${unit.id} has ${unit.lessons.length} lessons '
        '(max $kMaxLessonsPerUnit).',
      );
    }
    for (final lesson in unit.lessons) {
      if (lesson.id.isEmpty) {
        errors.add('Lesson "${lesson.name}" in unit ${unit.id} has an empty '
            'id.');
      } else if (!lessonIds.add(lesson.id)) {
        errors.add('Duplicate lesson id: ${lesson.id} (within section '
            '${section.id}).');
      }
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
  final hasPages = content.pages.isNotEmpty;
  final hasReadingPassage =
      content.readingPassage != null || content.passage.isNotEmpty;

  // Template / content shape consistency.
  switch (lesson.template) {
    case LessonTemplate.guide:
      if (!hasPages) {
        errors.add('Lesson ${lesson.id} uses template "guide" but has no '
            'pages.');
        return;
      }
      if (hasStages || hasSubLessons || hasListeningPhases) {
        errors
            .add('Guide lesson ${lesson.id} must contain only ungraded pages.');
      }
      break;
    case LessonTemplate.intro:
    case LessonTemplate.practice:
      if (!hasSubLessons) {
        errors
            .add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
                'but has no subLessons.');
        return;
      }
      break;
    case LessonTemplate.listening:
      if (!hasListeningPhases) {
        errors
            .add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
                'but has no listeningPhases.');
        return;
      }
      break;
    case LessonTemplate.dialogue:
      if (content.dialogueScene == null || !hasStages) {
        errors.add('Lesson ${lesson.id} uses template "dialogue" but needs '
            'both dialogueScene and stages.');
        return;
      }
      break;
    case LessonTemplate.reading:
      if (!hasReadingPassage) {
        errors
            .add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
                'but has no readingPassage or legacy passage.');
        return;
      }
      break;
    case LessonTemplate.mastery:
      if (!hasStages) {
        errors
            .add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
                'but has no stages.');
        return;
      }
      if (stages.length > 1) {
        errors
            .add('Lesson ${lesson.id} uses template "${lesson.template.name}" '
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

  if (hasPages) {
    _validateGuidePages(lesson, content.pages, vocabIds, errors);
  }

  if (hasSubLessons) {
    _validateSubLessons(lesson, subLessons, vocabIds, expressionIds, errors);
  }

  if (hasListeningPhases) {
    _validateListeningPhases(
        lesson, listeningPhases, vocabIds, expressionIds, errors);
  }

  if (lesson.template == LessonTemplate.dialogue) {
    _validateDialogueScene(lesson, errors);
  }
  if (content.reviewPolicy != null) {
    _validateReviewPolicy(lesson, errors);
  }
}

void _validateGuidePages(
  Lesson lesson,
  List<GuidePage> pages,
  Set<String> vocabIds,
  List<String> errors,
) {
  final pageIds = <String>{};
  final blockIds = <String>{};
  for (final page in pages) {
    if (page.id.isEmpty) {
      errors.add('Guide lesson ${lesson.id} has a page with an empty id.');
    } else if (!pageIds.add(page.id)) {
      errors.add('Duplicate guide page id "${page.id}" in ${lesson.id}.');
    }
    if (page.title.trim().isEmpty) {
      errors.add('Guide page ${page.id} in ${lesson.id} has an empty title.');
    }
    if (page.blocks.isEmpty) {
      errors.add('Guide page ${page.id} in ${lesson.id} has no blocks.');
    }
    if (page.nextSubLessonId != null && page.nextLessonId == null) {
      errors.add('Guide page ${page.id} has nextSubLessonId without '
          'nextLessonId.');
    }
    for (final block in page.blocks) {
      if (block.id.isEmpty) {
        errors.add('Guide page ${page.id} has a block with an empty id.');
      } else if (!blockIds.add(block.id)) {
        errors.add('Duplicate guide block id "${block.id}" in ${lesson.id}.');
      }
      switch (block) {
        case GuideTextBlock():
          if (block.body.trim().isEmpty) {
            errors.add('Guide text block ${block.id} has an empty body.');
          }
        case GuideTermsBlock():
          if (block.items.isEmpty) {
            errors.add('Guide terms block ${block.id} has no items.');
          }
          for (final term in block.items) {
            if (term.text.trim().isEmpty) {
              errors.add('Guide terms block ${block.id} has an empty term.');
            }
            final wordId = term.wordId;
            if (wordId != null && !vocabIds.contains(wordId)) {
              errors.add('Guide term ${term.text} references missing wordId '
                  '$wordId.');
            }
          }
        case GuideClassificationBlock():
          if (block.categories.length < 2 || block.cards.isEmpty) {
            errors.add('Guide classification ${block.id} needs at least two '
                'categories and one card.');
          }
          final categoryIds = <String>{};
          for (final category in block.categories) {
            if (category.id.isEmpty || category.label.trim().isEmpty) {
              errors.add('Guide classification ${block.id} has an invalid '
                  'category.');
            } else if (!categoryIds.add(category.id)) {
              errors.add('Duplicate category id "${category.id}" in guide '
                  'block ${block.id}.');
            }
          }
          final cardIds = <String>{};
          for (final card in block.cards) {
            if (card.id.isEmpty || card.text.trim().isEmpty) {
              errors.add('Guide classification ${block.id} has an invalid '
                  'card.');
            } else if (!cardIds.add(card.id)) {
              errors.add('Duplicate classification card id "${card.id}" in '
                  'guide block ${block.id}.');
            }
            if (!categoryIds.contains(card.categoryId)) {
              errors.add('Guide classification card ${card.id} references '
                  'missing category ${card.categoryId}.');
            }
          }
        case GuideSuffixBuilderBlock():
          if (block.examples.isEmpty) {
            errors.add('Guide suffix builder ${block.id} has no examples.');
          }
          final exampleIds = <String>{};
          for (final example in block.examples) {
            if (example.id.isEmpty ||
                example.root.trim().isEmpty ||
                example.rootMeaning.trim().isEmpty) {
              errors.add('Guide suffix builder ${block.id} has an invalid '
                  'example.');
            } else if (!exampleIds.add(example.id)) {
              errors.add('Duplicate suffix example id "${example.id}" in '
                  'guide block ${block.id}.');
            }
            if (example.steps.isEmpty) {
              errors.add('Guide suffix example ${example.id} has no steps.');
            }
            for (final step in example.steps) {
              if (step.suffix.trim().isEmpty ||
                  step.result.trim().isEmpty ||
                  step.meaning.trim().isEmpty) {
                errors.add('Guide suffix example ${example.id} has an '
                    'incomplete step.');
              }
            }
          }
        case GuideWordOrderBlock():
          if (block.tokens.isEmpty) {
            errors.add('Guide word order block ${block.id} has no tokens.');
          }
          final tokenIds = <String>{};
          for (final token in block.tokens) {
            if (token.id.isEmpty ||
                token.text.trim().isEmpty ||
                token.role.trim().isEmpty ||
                token.meaning.trim().isEmpty) {
              errors.add('Guide word order block ${block.id} has an invalid '
                  'token.');
            } else if (!tokenIds.add(token.id)) {
              errors.add('Duplicate sentence token id "${token.id}" in guide '
                  'block ${block.id}.');
            }
          }
          if (block.tokens.any((token) => token.optional) &&
              block.optionalToggleLabel.trim().isEmpty) {
            errors.add('Guide word order block ${block.id} has optional '
                'tokens but no optionalToggleLabel.');
          }
      }
    }
  }
}

void _validateDialogueScene(Lesson lesson, List<String> errors) {
  final scene = lesson.content.dialogueScene;
  if (scene == null) return;
  if (scene.id.trim().isEmpty) {
    errors.add('Dialogue lesson ${lesson.id} has an empty scene id.');
  }

  final characters = <String>{};
  for (final character in scene.characters) {
    if (character.id.trim().isEmpty || character.name.trim().isEmpty) {
      errors.add('Dialogue scene ${scene.id} has a character with an empty '
          'id or name.');
    } else if (!characters.add(character.id)) {
      errors.add('Duplicate dialogue character id "${character.id}" in '
          '${lesson.id}.');
    }
  }
  if (scene.turns.isEmpty) {
    errors.add('Dialogue scene ${scene.id} has no turns.');
  }

  final interactions = <Interaction>[
    for (final stage in lesson.content.stages) ...stage.items,
  ];
  final interactionById = <String, Interaction>{};
  for (final item in interactions) {
    if (item.id.isEmpty) continue;
    if (interactionById.containsKey(item.id)) {
      errors.add('Dialogue interaction id "${item.id}" is not unique within '
          '${lesson.id}.');
    } else {
      interactionById[item.id] = item;
    }
  }

  final turnIds = <String>{};
  final referencedIds = <String>[];
  var learnerTurns = 0;
  for (final turn in scene.turns) {
    if (turn.id.trim().isEmpty) {
      errors.add('Dialogue scene ${scene.id} has a turn with an empty id.');
    } else if (!turnIds.add(turn.id)) {
      errors.add('Duplicate dialogue turn id "${turn.id}" in ${lesson.id}.');
    }
    if (!characters.contains(turn.speakerId)) {
      errors.add('Dialogue turn ${turn.id} references missing speakerId '
          '${turn.speakerId}.');
    }

    final hasText = turn.text != null;
    final hasInteraction = turn.interactionId != null;
    if (hasText == hasInteraction) {
      errors.add('Dialogue turn ${turn.id} must declare exactly one of text '
          'or interactionId.');
      continue;
    }
    if (hasText) {
      if (turn.text!.trim().isEmpty) {
        errors.add('Dialogue turn ${turn.id} has empty text.');
      }
      continue;
    }

    learnerTurns++;
    final interactionId = turn.interactionId!;
    if (referencedIds.contains(interactionId)) {
      errors.add('Dialogue interaction "$interactionId" is referenced by '
          'more than one turn in ${lesson.id}.');
    }
    referencedIds.add(interactionId);
    final item = interactionById[interactionId];
    if (item == null) {
      errors.add('Dialogue turn ${turn.id} references missing interactionId '
          '$interactionId.');
    } else if (!isReviewPoolInteraction(item)) {
      errors.add('Dialogue turn ${turn.id} references non-response interaction '
          '$interactionId.');
    }
  }
  if (learnerTurns == 0) {
    errors.add('Dialogue scene ${scene.id} has no learner response turns.');
  }

  for (final item in interactions) {
    if (item.id.isNotEmpty && !referencedIds.contains(item.id)) {
      errors
          .add('Dialogue interaction ${item.id} is not referenced by a turn.');
    }
  }
  final authoredIds = [for (final item in interactions) item.id];
  if (referencedIds.length == authoredIds.length) {
    for (var i = 0; i < authoredIds.length; i++) {
      if (referencedIds[i] != authoredIds[i]) {
        errors.add('Dialogue learner turns must follow the stage item order '
            'in ${lesson.id}.');
        break;
      }
    }
  }
}

void _validateReviewPolicy(Lesson lesson, List<String> errors) {
  final content = lesson.content;
  final policy = content.reviewPolicy!;
  if (lesson.template != LessonTemplate.review) {
    errors.add(
        'Lesson ${lesson.id} has reviewPolicy but is not a review lesson.');
  }
  if (content.subLessons.isNotEmpty || content.listeningPhases.isNotEmpty) {
    errors.add('Review lesson ${lesson.id} reviewPolicy requires flat stages.');
  }

  final pool = <Interaction>[
    for (final stage in content.stages) ...stage.items,
  ];
  if (policy.minItems < 1 || policy.maxItems < policy.minItems) {
    errors.add('Review lesson ${lesson.id} must use '
        '1 <= minItems <= maxItems.');
  }
  if (policy.maxItems > pool.length) {
    errors.add('Review lesson ${lesson.id} maxItems ${policy.maxItems} exceeds '
        'the pool size ${pool.length}.');
  }
  for (final item in pool) {
    if (!isReviewPoolInteraction(item)) {
      errors.add('Review lesson ${lesson.id} pool contains non-gradable or '
          'imported item ${item.id}.');
    }
  }
  for (final entry in policy.typeWeights.entries) {
    if (!reviewPoolInteractionTypeNames.contains(entry.key)) {
      errors.add('Review lesson ${lesson.id} has unsupported typeWeight '
          '${entry.key}.');
    }
    if (!entry.value.isFinite || entry.value <= 0) {
      errors.add('Review lesson ${lesson.id} typeWeight ${entry.key} must be '
          'finite and greater than zero.');
    }
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
        errors
            .add('${prefix}Item #$i in stage ${stage.id} (lesson ${lesson.id}) '
                'has an empty id.');
      } else if (!itemIds.add(item.id)) {
        errors.add('${prefix}Duplicate item id "${item.id}" in stage '
            '${stage.id} (lesson ${lesson.id}).');
      }
      if (item is ShowWord) {
        if (!vocabIds.contains(item.wordId)) {
          errors.add(
              '${prefix}ShowWord "${item.id}" in stage ${stage.id} (lesson '
              '${lesson.id}) references missing wordId '
              '${item.wordId}.');
        }
        if (item.expressionId != null &&
            !expressionIds.contains(item.expressionId!)) {
          errors.add(
              '${prefix}ShowWord "${item.id}" in stage ${stage.id} (lesson '
              '${lesson.id}) references missing expressionId '
              '${item.expressionId}.');
        }
      }
      // ReadAloud is driven entirely by targetText (model audio is TTS), so
      // an empty one leaves nothing to read and nothing to match against.
      if (item is ReadAloud && item.targetText.trim().isEmpty) {
        errors
            .add('${prefix}ReadAloud "${item.id}" in stage ${stage.id} (lesson '
                '${lesson.id}) has an empty targetText.');
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
        errors
            .add('Item #$i in listeningPhase ${phase.id} (lesson ${lesson.id}) '
                'has an empty id.');
      } else if (!itemIds.add(item.id)) {
        errors.add('Duplicate item id "${item.id}" in listeningPhase '
            '${phase.id} (lesson ${lesson.id}).');
      }
      if (item is ShowWord) {
        if (!vocabIds.contains(item.wordId)) {
          errors.add(
              'ShowWord "${item.id}" in listeningPhase ${phase.id} (lesson '
              '${lesson.id}) references missing wordId ${item.wordId}.');
        }
        if (item.expressionId != null &&
            !expressionIds.contains(item.expressionId!)) {
          errors.add(
              'ShowWord "${item.id}" in listeningPhase ${phase.id} (lesson '
              '${lesson.id}) references missing expressionId '
              '${item.expressionId}.');
        }
      }
      if (item is ReadAloud && item.targetText.trim().isEmpty) {
        errors.add('ReadAloud "${item.id}" in listeningPhase ${phase.id} '
            '(lesson ${lesson.id}) has an empty targetText.');
      }
    }
  }
}
