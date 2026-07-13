// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:drift/drift.dart';

// Project imports:
import 'package:varnamala/application/ai_course_service.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/section.dart';

/// State machine for the AI course generation flow.
enum AiCourseState { idle, generating, generated, saving, saved, error }

/// Holds in-memory AI configuration and orchestrates generate → preview →
/// save-to-DB. The [AiApiConfig] is intentionally **never persisted**; it
/// lives only for the current app session and is lost on exit (per product
/// requirement).
///
/// Generated course JSON is kept in [_generatedJson] for the user to edit
/// before saving. Saving writes a new section (and its units/lessons/content
/// blobs) into [CourseDatabase], then invalidates [CourseLoader] caches so
/// the course tree refreshes.
class AiCourseProvider extends ChangeNotifier {
  AiCourseProvider();

  final AiCourseService _service = const AiCourseService();

  AiApiConfig _config = const AiApiConfig(
    baseUrl: 'https://api.openai.com/v1',
    apiKey: '',
    model: 'gpt-4o-mini',
  );

  AiApiConfig get config => _config;

  AiCourseState _state = AiCourseState.idle;
  AiCourseState get state => _state;

  String? _error;
  String? get error => _error;

  /// Editable raw JSON of the last generated course (for the preview/edit
  /// screen). `null` until generation succeeds.
  String? _generatedJson;
  String? get generatedJson => _generatedJson;

  /// Parsed section id of the last generated course (extracted from JSON).
  String? _generatedSectionId;
  String? get generatedSectionId => _generatedSectionId;

  // --- Config mutation (in-memory only) ---

  void updateConfig({
    String? baseUrl,
    String? apiKey,
    String? model,
  }) {
    _config = _config.copyWith(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
    notifyListeners();
  }

  // --- Generation flow ---

  /// Calls the AI endpoint with [spec] and stores the result for preview.
  Future<void> generate(AiCourseRequestSpec spec) async {
    _error = null;
    _state = AiCourseState.generating;
    _generatedJson = null;
    _generatedSectionId = null;
    notifyListeners();
    try {
      final result = await _service.generateCourse(
        config: _config,
        spec: spec,
      );
      _generatedJson = result.rawJson;
      _generatedSectionId = result.parsed['id'] as String?;
      _state = AiCourseState.generated;
    } catch (e) {
      logger.w('AiCourseProvider.generate failed: $e');
      _error = e.toString();
      _state = AiCourseState.error;
    }
    notifyListeners();
  }

  /// Replace the editable JSON (e.g. user edited it in the preview screen).
  /// Re-parses the section id so save knows what to write.
  void updateGeneratedJson(String raw) {
    _generatedJson = raw;
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      _generatedSectionId = parsed['id'] as String?;
    } catch (_) {
      // Keep raw; validation happens on save.
    }
    notifyListeners();
  }

  /// Persists the current generated JSON as a new section in the course DB,
  /// then refreshes the [CourseLoader] caches so the tree re-reads from disk.
  /// Throws on invalid JSON or DB write failure; the caller should surface
  /// the message.
  Future<void> save() async {
    final raw = _generatedJson;
    if (raw == null) {
      throw StateError('No generated course to save.');
    }
    _error = null;
    _state = AiCourseState.saving;
    notifyListeners();
    try {
      final section = Section.fromJson(
        _normalizeForSave(jsonDecode(raw) as Map<String, dynamic>),
      );
      await _writeSectionToDb(section);
      CourseLoader.invalidateCaches();
      _state = AiCourseState.saved;
    } catch (e, st) {
      logger.e('AiCourseProvider.save failed', error: e, stackTrace: st);
      _error = e.toString();
      _state = AiCourseState.error;
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  /// Reset to idle, dropping any generated/edited JSON.
  void reset() {
    _state = AiCourseState.idle;
    _error = null;
    _generatedJson = null;
    _generatedSectionId = null;
    notifyListeners();
  }

  // --- DB write ---

  Future<void> _writeSectionToDb(Section section) async {
    final database = getIt<db.CourseDatabase>();
    final nextOrder = await _nextSectionSortOrder(database);

    await database.transaction(() async {
      await database.into(database.sections).insertOnConflictUpdate(
            db.SectionsCompanion(
              id: Value(section.id),
              name: Value(section.name),
              description: Value(section.description),
              prerequisiteSectionIds:
                  Value(jsonEncode(section.prerequisiteSectionIds)),
              sortOrder: Value(nextOrder),
            ),
          );

      for (var uOrder = 0; uOrder < section.units.length; uOrder++) {
        final u = section.units[uOrder];
        await database.into(database.units).insertOnConflictUpdate(
              db.UnitsCompanion(
                id: Value(u.id),
                sectionId: Value(section.id),
                name: Value(u.name),
                description: Value(u.description),
                prerequisiteUnitIds: Value(jsonEncode(u.prerequisiteUnitIds)),
                sortOrder: Value(uOrder),
              ),
            );
        for (var lOrder = 0; lOrder < u.lessons.length; lOrder++) {
          final l = u.lessons[lOrder];
          await database.into(database.lessons).insertOnConflictUpdate(
                db.LessonsCompanion(
                  id: Value(l.id),
                  unitId: Value(u.id),
                  name: Value(l.name),
                  description: Value(l.description),
                  type: Value(l.type.name),
                  template: Value(l.template.name),
                  prerequisiteLessonIds:
                      Value(jsonEncode(l.prerequisiteLessonIds)),
                  sortOrder: Value(lOrder),
                ),
              );
          await database.into(database.lessonContents).insertOnConflictUpdate(
                db.LessonContentsCompanion(
                  lessonId: Value(l.id),
                  contentJson: Value(jsonEncode(l.content.toJson())),
                ),
              );
        }
      }
    });
  }

  Future<int> _nextSectionSortOrder(db.CourseDatabase database) async {
    final rows = await database.select(database.sections).get();
    if (rows.isEmpty) return 0;
    return rows.map((r) => r.sortOrder).fold<int>(0, (a, b) => a > b ? a : b) +
        1;
  }

  /// Minimal normalization mirroring [CourseLoader._normalizeLesson]:
  /// supports flat `content.questions` by wrapping them in one stage so the
  /// runtime is always `List<Stage>`.
  Map<String, dynamic> _normalizeForSave(Map<String, dynamic> section) {
    final units = section['units'] as List<dynamic>?;
    if (units == null) return section;
    section['units'] = [
      for (final u in units)
        _normalizeUnitJson(u as Map<String, dynamic>),
    ];
    return section;
  }

  Map<String, dynamic> _normalizeUnitJson(Map<String, dynamic> unit) {
    final lessons = unit['lessons'] as List<dynamic>?;
    if (lessons == null) return unit;
    unit['lessons'] = [
      for (final l in lessons)
        _normalizeLessonJson(l as Map<String, dynamic>),
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