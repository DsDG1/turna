// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/ai_resource_consistency.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

/// Persistence helpers for course-shaped JSON produced by importers and the
/// AI practice pipeline.
///
/// Generation itself lives in `application/ai/practice/` (phased outline →
/// lesson fill). This provider only writes a validated section tree into
/// `course.db` (and refreshes the loader caches) — the job-queue/library path
/// deliberately does **not** call it, because generated drafts stay outside the
/// course tree until the learner asks for them.
@lazySingleton
class AiCourseProvider extends ChangeNotifier {
  AiCourseProvider();

  /// Persists an arbitrary section JSON (e.g. from textbook import) into the
  /// DB after normalization and validation. Used by importers that already
  /// hold parsed JSON.
  Future<void> saveSectionJson(Map<String, dynamic> parsed) async {
    normalizeResources(parsed);
    autoFixResources(parsed);
    checkResourceSelfConsistency(parsed);
    final section = Section.fromJson(_normalizeForSave(parsed));
    await getIt<ICourseRepository>().saveAiCourseSection(
      section: section,
      rawPayload: parsed,
      defaultLanguageCode: LanguageContentStore.activeCode,
    );
    CourseLoader.invalidateCaches();
  }

  /// Updates a single existing lesson and its content in the DB.
  ///
  /// Not wired to any surface today (the in-lesson AI editor is gone); kept as
  /// the single validated write path for a future editor so lesson edits never
  /// grow a second DB writer. The caller is responsible for validating
  /// [lesson].
  Future<void> updateLessonInDb(Lesson lesson) async {
    await getIt<ICourseRepository>().updateLessonRecord(lesson);
    CourseLoader.invalidateCaches();
  }

  /// Minimal normalization mirroring [CourseLoader._normalizeLesson]:
  /// supports flat `content.questions` by wrapping them in one stage.
  Map<String, dynamic> _normalizeForSave(Map<String, dynamic> section) {
    final units = section['units'] as List<dynamic>?;
    if (units == null) return section;
    section['units'] = [
      for (final u in units) _normalizeUnitJson(u as Map<String, dynamic>),
    ];
    return section;
  }

  Map<String, dynamic> _normalizeUnitJson(Map<String, dynamic> unit) {
    final lessons = unit['lessons'] as List<dynamic>?;
    if (lessons == null) return unit;
    unit['lessons'] = [
      for (final l in lessons) _normalizeLessonJson(l as Map<String, dynamic>),
    ];
    return unit;
  }

  Map<String, dynamic> _normalizeLessonJson(Map<String, dynamic> lesson) {
    final content = lesson['content'] as Map<String, dynamic>?;
    if (content == null || !content.containsKey('questions')) {
      return lesson;
    }
    final questions = content['questions'] as List<dynamic>;
    content['stages'] = [
      {
        'id': 'stage-default',
        'name': (lesson['name'] as String?) ?? 'Practice',
        'items': questions,
      },
    ];
    content.remove('questions');
    return lesson;
  }
}
