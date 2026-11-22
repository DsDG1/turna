// Project imports:
import 'package:turna/application/ai/ai_json_text.dart';
import 'package:turna/application/ai/ai_resource_consistency.dart';
import 'package:turna/application/ai/practice/ai_practice_normalizer.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/domain/course/section.dart';

/// Pure helpers for the phased practice generator: JSON extraction, outline
/// validation, section-shell construction, lesson splicing and final
/// validation.
///
/// Everything here is synchronous and network-free so the shape rules can be
/// unit-tested without an AI endpoint. The orchestration lives in
/// `ai_practice_generator.dart`.
abstract final class AiPracticePipeline {
  /// Templates the in-app generator may emit. `listening` is excluded because
  /// its items need pre-generated audio; `legacy` is a fallback, not a target.
  static const Set<String> allowedTemplates =
      AiPracticeNormalizer.allowedTemplates;

  /// Strip a leading ```lang fence and a trailing ``` so a model that ignored
  /// the "no fences" rule still decodes.
  ///
  /// Delegates to [AiJsonText] — the single implementation shared by the course
  /// service, the textbook importer and the companion surfaces.
  static String stripFences(String input) => AiJsonText.stripCodeFences(input);

  /// Decode a model reply into a JSON object with resilient recovery
  /// (strips `<think>` tags, code fences, trailing commas, and extracts the
  /// first balanced `{...}` object).
  static Map<String, dynamic> decodeObject(String input) =>
      AiPracticeNormalizer.decodeObject(input);

  /// Normalize an outline before validation (fills missing ids, maps `mixed`
  /// onto valid concrete templates, prunes unknown `targetWordIds`).
  static Map<String, dynamic> normalizeOutline(
    Map<String, dynamic> outline, {
    required String fallbackSectionId,
    required String fallbackTitle,
    required String requestedTemplate,
  }) =>
      AiPracticeNormalizer.normalizeOutline(
        outline,
        fallbackSectionId: fallbackSectionId,
        fallbackTitle: fallbackTitle,
        requestedTemplate: requestedTemplate,
      );

  /// Human-readable errors for an outline; empty means usable.
  static List<String> validateOutline(
    Map<String, dynamic> outline, {
    required int expectedUnits,
    required int expectedLessonsPerUnit,
  }) {
    final errors = <String>[];
    if ((outline['id']?.toString() ?? '').isEmpty) {
      errors.add('outline is missing the section id');
    }

    final words = outline['words'];
    final wordIds = <String>{};
    if (words is! List) {
      errors.add('outline.words must be an array');
    } else {
      for (final raw in words) {
        if (raw is! Map) {
          errors.add('outline.words contains a non-object entry');
          continue;
        }
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty) {
          errors.add('outline.words contains an entry without id');
          continue;
        }
        if (!wordIds.add(id)) errors.add('duplicate word id: $id');
        if ((raw['term']?.toString() ?? '').trim().isEmpty) {
          errors.add('word $id has an empty term');
        }
        if ((raw['translation']?.toString() ?? '').trim().isEmpty) {
          errors.add('word $id has an empty translation');
        }
      }
    }

    final units = outline['units'];
    if (units is! List || units.isEmpty) {
      errors.add('outline.units must be a non-empty array');
      return errors;
    }
    if (expectedUnits > 0 && units.length != expectedUnits) {
      errors.add('expected $expectedUnits unit(s), got ${units.length}');
    }

    final lessonIds = <String>{};
    for (var u = 0; u < units.length; u++) {
      final unit = units[u];
      if (unit is! Map) {
        errors.add('units[$u] is not an object');
        continue;
      }
      final unitId = unit['id']?.toString() ?? '';
      if (unitId.isEmpty) errors.add('units[$u] is missing id');
      final lessons = unit['lessons'];
      if (lessons is! List || lessons.isEmpty) {
        errors.add('unit $unitId has no lessons');
        continue;
      }
      if (expectedLessonsPerUnit > 0 &&
          lessons.length != expectedLessonsPerUnit) {
        errors.add('unit $unitId: expected $expectedLessonsPerUnit lesson(s), '
            'got ${lessons.length}');
      }
      for (var l = 0; l < lessons.length; l++) {
        final lesson = lessons[l];
        if (lesson is! Map) {
          errors.add('unit $unitId lessons[$l] is not an object');
          continue;
        }
        final lessonId = lesson['id']?.toString() ?? '';
        if (lessonId.isEmpty) {
          errors.add('unit $unitId lessons[$l] is missing id');
        } else if (!lessonIds.add(lessonId)) {
          errors.add('duplicate lesson id: $lessonId');
        }
        final template = lesson['template']?.toString() ?? '';
        if (template.isEmpty) {
          errors.add('lesson $lessonId is missing template');
        } else if (!allowedTemplates.contains(template)) {
          errors.add('lesson $lessonId has unsupported template: $template');
        }
        for (final rawId in (lesson['targetWordIds'] as List? ?? const [])) {
          final id = rawId.toString();
          if (!wordIds.contains(id)) {
            errors.add('lesson $lessonId references unknown word id: $id');
          }
        }
      }
    }
    if (lessonIds.isEmpty) errors.add('outline has no lessons');
    return errors;
  }

  /// Build a section shell with locked ids/templates and empty lesson content.
  static Map<String, dynamic> sectionShell(
    Map<String, dynamic> outline, {
    required String sectionId,
    required String sectionName,
    String description = '',
  }) {
    return <String, dynamic>{
      'id': sectionId,
      'name': sectionName,
      'description': description,
      'words': _deepCopyList(outline['words']),
      'expressions': _deepCopyList(outline['expressions']),
      'grammarPoints': _deepCopyList(outline['grammarPoints']),
      'units': [
        for (final rawUnit in (outline['units'] as List? ?? const []))
          if (rawUnit is Map)
            {
              'id': rawUnit['id'],
              'name': rawUnit['name'] ?? rawUnit['id'],
              'description': rawUnit['description'] ?? '',
              'prerequisiteUnitIds': rawUnit['prerequisiteUnitIds'] ?? const [],
              'lessons': [
                for (final rawLesson
                    in (rawUnit['lessons'] as List? ?? const []))
                  if (rawLesson is Map)
                    {
                      'id': rawLesson['id'],
                      'name': rawLesson['name'] ?? rawLesson['id'],
                      'description': rawLesson['description'] ?? '',
                      'type': rawLesson['type'] ?? 'normal',
                      'template': rawLesson['template'],
                      'prerequisiteLessonIds':
                          rawLesson['prerequisiteLessonIds'] ?? const [],
                      'content': AiPracticeNormalizer.emptyContentFor(
                        rawLesson['template']?.toString() ?? 'mastery',
                      ),
                    },
              ],
            },
      ],
    };
  }

  /// `(unitId, lessonOutline)` pairs in document order.
  static List<({String unitId, Map<String, dynamic> lesson})> iterLessons(
    Map<String, dynamic> outline,
  ) {
    final result = <({String unitId, Map<String, dynamic> lesson})>[];
    for (final unit in (outline['units'] as List? ?? const [])) {
      if (unit is! Map) continue;
      final unitId = unit['id']?.toString() ?? '';
      for (final lesson in (unit['lessons'] as List? ?? const [])) {
        if (lesson is Map && lesson['id'] != null) {
          result.add((
            unitId: unitId,
            lesson: Map<String, dynamic>.from(lesson),
          ));
        }
      }
    }
    return result;
  }

  /// Replace one lesson body in [section] without touching ids/templates.
  static void spliceLesson(
    Map<String, dynamic> section,
    String lessonId,
    Map<String, dynamic> lesson,
  ) {
    for (final unit in (section['units'] as List? ?? const [])) {
      if (unit is! Map) continue;
      final lessons = unit['lessons'];
      if (lessons is! List) continue;
      for (var i = 0; i < lessons.length; i++) {
        final current = lessons[i];
        if (current is Map && current['id']?.toString() == lessonId) {
          lesson['id'] = current['id'];
          lesson['template'] = current['template'];
          lesson['name'] ??= current['name'];
          lessons[i] = lesson;
          return;
        }
      }
    }
  }

  /// Normalize every lesson inside an already-assembled section (used by
  /// whole-section `adjust` calls).
  static Map<String, dynamic> normalizeSectionJson(
    Map<String, dynamic> rawSection,
  ) {
    final section = Map<String, dynamic>.from(rawSection);
    final wordById = <String, Map<String, dynamic>>{
      for (final w in (section['words'] as List? ?? const []))
        if (w is Map && w['id'] != null)
          w['id'].toString(): Map<String, dynamic>.from(w),
    };
    final units = section['units'];
    if (units is List) {
      final fixedUnits = <Map<String, dynamic>>[];
      for (final rawUnit in units) {
        if (rawUnit is! Map) continue;
        final unit = Map<String, dynamic>.from(rawUnit);
        final lessons = unit['lessons'];
        if (lessons is List) {
          unit['lessons'] = [
            for (final rawLesson in lessons)
              if (rawLesson is Map)
                AiPracticeNormalizer.normalizeLessonJson(
                  Map<String, dynamic>.from(rawLesson),
                  lessonId: rawLesson['id']?.toString() ?? 'lesson',
                  template: rawLesson['template']?.toString() ?? 'mastery',
                  outlineWordById: wordById,
                ),
          ];
        }
        fixedUnits.add(unit);
      }
      section['units'] = fixedUnits;
    }
    return section;
  }

  /// Structural + resource validation of a generated section. Returns
  /// human-readable errors; empty means it can be stored/played.
  static List<String> validateSectionJson(Map<String, dynamic> parsed) {
    final errors = <String>[];
    // Normalize + auto-fix dangling resource references first (mirrors
    // tool/gui's `parse_completion`), then enforce full CourseValidator rules.
    try {
      normalizeResources(parsed);
      checkResourceSelfConsistency(parsed);
    } catch (e) {
      errors.add(e.toString());
    }

    final wordIds = <String>{
      for (final w in (parsed['words'] as List? ?? const []))
        if (w is Map) w['id']?.toString() ?? '',
    }..remove('');
    final expressionIds = <String>{
      for (final e in (parsed['expressions'] as List? ?? const []))
        if (e is Map) e['id']?.toString() ?? '',
    }..remove('');

    try {
      final section = Section.fromJson(parsed);
      validateSection(section, wordIds, expressionIds);
    } on CourseValidationException catch (e) {
      errors.addAll(e.errors);
    } catch (e) {
      errors.add(e.toString());
    }
    return errors;
  }

  /// Ensure a lesson body has the minimum shape the validator expects.
  static Map<String, dynamic> normalizeLessonJson(
    Map<String, dynamic> lesson, {
    required String lessonId,
    required String template,
    Map<String, Map<String, dynamic>> outlineWordById = const {},
  }) =>
      AiPracticeNormalizer.normalizeLessonJson(
        lesson,
        lessonId: lessonId,
        template: template,
        outlineWordById: outlineWordById,
      );

  static List<dynamic> _deepCopyList(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item) else item,
    ];
  }
}
