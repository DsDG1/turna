// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:drift/drift.dart' show Value;
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_service.dart';
import 'package:turna/application/ai/ai_prompt_builder.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/ai_resource_consistency.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';

/// State machine for the AI course generation flow.
enum AiCourseState { idle, generating, generated, saving, saved, error }

/// Holds in-memory AI configuration and orchestrates generate → preview →
/// save-to-DB. The [AiApiConfig] is intentionally **never persisted**.
///
/// Generated course JSON is kept in [_generatedJson] for the user to edit
/// before saving. Saving writes a new section (and its units/lessons/content
/// blobs + top-level resources) into [CourseDatabase], then invalidates
/// [CourseLoader] caches so the course tree refreshes.
@lazySingleton
class AiCourseProvider extends ChangeNotifier {
  AiCourseProvider({AiEngine? engine, AiGroundedResourceProvider? groundedProvider})
      : _engine = engine ?? getIt<AiEngine>(),
        _service = AiCourseService(),
        _groundedProvider = groundedProvider ?? AiGroundedResourceProvider();

  AiCourseProvider.withEngine(this._engine, {AiGroundedResourceProvider? groundedProvider})
      : _service = AiCourseService(),
        _groundedProvider = groundedProvider ?? AiGroundedResourceProvider();

  final AiEngine _engine;
  final AiCourseService _service;
  final AiGroundedResourceProvider _groundedProvider;

  /// Active cancel token for the in-flight generation, if any.
  AiCancelToken? _cancelToken;

  /// Lazy lookup of the shared config holder (registered in DI and exposed in
  /// `providers.dart` as a `ChangeNotifierProvider`). The holder is the single
  /// source of truth for AI config since the Phase 4 migration; this provider
  /// no longer keeps a separate config field.
  AiEngineConfigHolder get _holder => getIt<AiEngineConfigHolder>();

  AiCourseState _state = AiCourseState.idle;
  AiCourseState get state => _state;

  String? _error;
  String? get error => _error;

  /// Editable raw JSON of the last generated course. `null` until generation
  /// succeeds.
  String? _generatedJson;
  String? get generatedJson => _generatedJson;

  /// Parsed section id of the last generated course.
  String? _generatedSectionId;
  String? get generatedSectionId => _generatedSectionId;

  /// Optional plain-language explanation (wish mode sets this).
  String? _explanation;
  String? get explanation => _explanation;

  // --- Generation flow ---

  /// Calls the AI endpoint with [spec] and stores the result for preview.
  /// Runs validateSection + resource self-consistency; on errors retries the
  /// AI once (C3 self-heal).
  Future<void> generate(AiCourseSpec spec) async {
    _cancelToken?.cancel();
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _state = AiCourseState.generating;
    _generatedJson = null;
    _generatedSectionId = null;
    _explanation = null;
    notifyListeners();
    try {
      final applied = _service.applyGenreToSpec(spec);
      final groundedContext = await _loadGroundedContext(applied);
      final messages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content':
              'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences.',
        },
        {
          'role': 'user',
          'content': buildPrompt(applied, groundedContext: groundedContext),
        },
      ];
      var result = _service.parseCompletion(
        (await _engine.requestJson(
          config: _holder.config,
          messages: messages,
          temperature: 0.4,
          timeout: const Duration(seconds: 120),
          cancelToken: token,
        ))
            .body,
      );
      // C3 self-heal: if the validator reports errors, re-prompt once with
      // the errors listed. The retry's prompt differs so it won't hit the
      // cache; the first attempt is cacheable for repeat-clicks.
      final errors = _validateGenerated(result.parsed);
      if (errors.isNotEmpty) {
        final correction =
            'The previous version has the following validation errors. Fix them and output only the complete corrected JSON:\n- ${errors.join('\n- ')}';
        messages.add({'role': 'assistant', 'content': jsonEncode(result.parsed)});
        messages.add({'role': 'user', 'content': correction});
        result = _service.parseCompletion(
          (await _engine.requestJson(
            config: _holder.config,
            messages: messages,
            temperature: 0.2,
            timeout: const Duration(seconds: 120),
            cancelToken: token,
          ))
              .body,
        );
      }
      _generatedJson = result.rawJson;
      _generatedSectionId = result.parsed['id'] as String?;
      _state = AiCourseState.generated;
      _recordRecent(spec);
    } on AiCancelled {
      _state = AiCourseState.idle;
    } catch (e) {
      logger.w('AiCourseProvider.generate failed: $e');
      _error = e.toString();
      _state = AiCourseState.error;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    notifyListeners();
  }

  /// Loads existing resources when [spec.groundedMode] is enabled.
  Future<String?> _loadGroundedContext(AiCourseSpec spec) async {
    if (!spec.groundedMode) return null;
    await _groundedProvider.load(scope: spec.resourceScope);
    if (_groundedProvider.error != null) {
      logger.w('AiCourseProvider grounded load failed: ${_groundedProvider.error}');
      return null;
    }
    return _groundedProvider.formatContext(
      maxResources: spec.maxGroundedResources,
    );
  }

  /// Validator used by [requestCourseWithRetry]. Combines structural
  /// validation ([validateSection]) with resource self-consistency (already
  /// enforced inside [AiCourseService.parseCompletion], so this mainly
  /// re-checks the structure).
  List<String> _validateGenerated(Map<String, dynamic> parsed) {
    final errors = <String>[];
    try {
      final wordIds = <String>{
        for (final w in (parsed['words'] as List? ?? const []))
          if (w is Map) w['id']?.toString() ?? '',
      }..remove('');
      final exprIds = <String>{
        for (final e in (parsed['expressions'] as List? ?? const []))
          if (e is Map) e['id']?.toString() ?? '',
      }..remove('');
      final section = Section.fromJson(_normalizeForSave(parsed));
      validateSection(section, wordIds, exprIds);
    } on CourseValidationException catch (e) {
      errors.addAll(e.errors);
    } catch (e) {
      errors.add(e.toString());
    }
    return errors;
  }

  /// Replace the editable JSON (e.g. user edited it in the preview screen).
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

  /// Set the plain-language explanation (used by wish provider).
  void setExplanation(String? text) {
    _explanation = text;
    notifyListeners();
  }

  /// Persists the current generated JSON as a new section in the course DB,
  /// including its top-level resources, then refreshes [CourseLoader] caches.
  /// Throws on invalid JSON or DB write failure.
  Future<void> save() async {
    final raw = _generatedJson;
    if (raw == null) {
      throw StateError('No generated course to save.');
    }
    _error = null;
    _state = AiCourseState.saving;
    notifyListeners();
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      normalizeResources(parsed);
      autoFixResources(parsed);
      checkResourceSelfConsistency(parsed);
      final section = Section.fromJson(_normalizeForSave(parsed));
      await _writeSectionToDb(section, parsed);
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

  /// Persists an arbitrary section JSON (e.g. from textbook import) into the
  /// DB after normalization and validation. Used by importers that already
  /// hold parsed JSON.
  Future<void> saveSectionJson(Map<String, dynamic> parsed) async {
    normalizeResources(parsed);
    autoFixResources(parsed);
    checkResourceSelfConsistency(parsed);
    final section = Section.fromJson(_normalizeForSave(parsed));
    await _writeSectionToDb(section, parsed);
    CourseLoader.invalidateCaches();
  }

  /// Updates a single existing lesson and its content in the DB. Used by the
  /// AI lesson helper. The caller is responsible for validating [lesson].
  Future<void> updateLessonInDb(Lesson lesson) async {
    final database = getIt<db.CourseDatabase>();

    // Preserve existing unit/sort metadata by reading the current lesson row.
    final existing = await (database.select(database.lessons)
          ..where((t) => t.id.equals(lesson.id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('Lesson ${lesson.id} not found in database.');
    }

    await database.transaction(() async {
      await database.into(database.lessons).insertOnConflictUpdate(
            db.LessonsCompanion(
              id: Value(lesson.id),
              unitId: Value(existing.unitId),
              name: Value(lesson.name),
              description: Value(lesson.description),
              type: Value(lesson.type.name),
              template: Value(lesson.template.name),
              prerequisiteLessonIds:
                  Value(jsonEncode(lesson.prerequisiteLessonIds)),
              sortOrder: Value(existing.sortOrder),
            ),
          );
      await database.into(database.lessonContents).insertOnConflictUpdate(
            db.LessonContentsCompanion(
              lessonId: Value(lesson.id),
              contentJson: Value(jsonEncode(lesson.content.toJson())),
            ),
          );
    });
    CourseLoader.invalidateCaches();
  }

  /// Reset to idle, dropping any generated/edited JSON.
  void reset() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiCourseState.idle;
    _error = null;
    _generatedJson = null;
    _generatedSectionId = null;
    _explanation = null;
    notifyListeners();
  }

  /// Cancel the in-flight generation (if any) and return to idle, keeping any
  /// previously generated JSON. A no-op when not generating.
  void cancel() {
    if (_state != AiCourseState.generating) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiCourseState.idle;
    notifyListeners();
  }

  // --- DB write ---

  Future<void> _writeSectionToDb(
    Section section,
    Map<String, dynamic> parsed,
  ) async {
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

      // Top-level resources: words / expressions / grammar points.
      await _writeResources(database, parsed);
    });
  }

  Future<void> _writeResources(
    db.CourseDatabase database,
    Map<String, dynamic> parsed,
  ) async {
    final words = (parsed['words'] as List?) ?? const [];
    for (final w in words) {
      if (w is! Map) continue;
      await database.into(database.vocabulary).insertOnConflictUpdate(
            db.VocabularyCompanion(
              id: Value(w['id']?.toString() ?? ''),
              term: Value(w['term']?.toString() ?? ''),
              translation: Value(w['translation']?.toString() ?? ''),
              pronunciation: Value(w['pronunciation']?.toString()),
              audioAsset: Value(w['audioAsset']?.toString()),
              tags: Value(jsonEncode(w['tags'] ?? const [])),
            ),
          );
    }
    final exprs = (parsed['expressions'] as List?) ?? const [];
    for (final e in exprs) {
      if (e is! Map) continue;
      await database.into(database.expressions).insertOnConflictUpdate(
            db.ExpressionsCompanion(
              id: Value(e['id']?.toString() ?? ''),
              term: Value(e['term']?.toString() ?? ''),
              translation: Value(e['translation']?.toString() ?? ''),
              pronunciation: Value(e['pronunciation']?.toString()),
              audioAsset: Value(e['audioAsset']?.toString()),
              tags: Value(jsonEncode(e['tags'] ?? const [])),
            ),
          );
    }
    final gps = (parsed['grammarPoints'] as List?) ?? const [];
    for (final g in gps) {
      if (g is! Map) continue;
      await database.into(database.grammarPoints).insertOnConflictUpdate(
            db.GrammarPointsCompanion(
              id: Value(g['id']?.toString() ?? ''),
              title: Value(g['title']?.toString() ?? ''),
              explanation: Value(g['explanation']?.toString() ?? ''),
              exampleExpressionIds:
                  Value(jsonEncode(g['exampleExpressionIds'] ?? const [])),
              exampleSentenceIds:
                  Value(jsonEncode(g['exampleSentenceIds'] ?? const [])),
              practiceItems: Value(jsonEncode(g['practiceItems'] ?? const [])),
            ),
          );
    }
  }

  Future<int> _nextSectionSortOrder(db.CourseDatabase database) async {
    final rows = await database.select(database.sections).get();
    if (rows.isEmpty) return 0;
    return rows
            .map((r) => r.sortOrder)
            .fold<int>(0, (a, b) => a > b ? a : b) +
        1;
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

  /// Append a one-shot course-generation task to the AI Hub's recent list.
  void _recordRecent(AiCourseSpec spec) {
    try {
      getIt<AiRecentTasksProvider>().record(
            AiRecentTask(
              kind: AiTaskKind.courseGenerate,
              summary: '${spec.topic} · ${spec.level}',
              timestamp: DateTime.now(),
            ),
          );
    } catch (_) {
      // Advisory only.
    }
  }
}