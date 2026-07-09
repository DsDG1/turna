// Flutter imports:
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

// Project imports:
import 'package:words625/courses/course_validator.dart';
import 'package:words625/data/course_database.dart'
    hide
        Section,
        Unit,
        Lesson,
        LessonContent,
        Vocabulary,
        GrammarPoint;
import 'package:words625/data/course_repository.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/course/expression.dart';
import 'package:words625/domain/course/grammar_point.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/section.dart';
import 'package:words625/domain/course/word_entry.dart';

/// Loads a language course from a SQLite database ([CourseDatabase]) that is
/// seeded from the bundled JSON assets under `assets/courses/swahili/` on
/// first launch.
///
/// At startup only the section index and vocabulary are read — section bodies
/// are loaded on demand via [loadSection] (cached per id), and individual
/// lessons via [loadLessonById]. This keeps cold start independent of the
/// total course size as it scales toward thousands of lessons, and gives the
/// "Lesson by ID" query the JSON layout couldn't offer cheaply.
///
/// [sectionShells] are real [Section] objects built from the index with empty
/// `units`; they carry enough (id/name/description/prerequisiteSectionIds)
/// for the section switcher and selection logic. [loadSection] rebuilds a
/// fully-populated [Section] from the DB.
class SwahiliCourse {
  /// Lightweight section shells built from the DB index — id/name/description/
  /// prerequisiteSectionIds only, `units` empty until [loadSection] is called.
  final List<Section> sectionShells;

  final List<WordEntry> vocabulary;
  final Map<String, WordEntry> vocabularyById;
  final Map<String, WordEntry> vocabularyByTranslation;

  /// Grammar points loaded at startup for the grammar-review SRS queue.
  final List<GrammarPoint> grammarPoints;
  final Map<String, GrammarPoint> grammarPointsById;

  /// Expressions / phrases loaded at startup for the expression SRS queue.
  final List<Expression> expressions;
  final Map<String, Expression> expressionsById;

  const SwahiliCourse({
    required this.sectionShells,
    required this.vocabulary,
    required this.vocabularyById,
    required this.vocabularyByTranslation,
    required this.grammarPoints,
    required this.grammarPointsById,
    required this.expressions,
    required this.expressionsById,
  });

  /// Directory holding the seed JSON assets (index + per-section files +
  /// vocab + grammar points). Used by [DatabaseSeeder]; exposed for seed-time
  /// file resolution.
  static const String baseDir = 'assets/courses/swahili';

  /// Course index: metadata + one lightweight entry per section with a `file`
  /// pointer (relative to [baseDir]) to that section's full JSON. Seed source.
  static const String indexAsset = '$baseDir/index.json';

  /// Full vocabulary list (seed source).
  static const String vocabAsset = '$baseDir/vocab.json';

  /// Grammar points (seed source).
  static const String grammarPointsAsset = '$baseDir/grammar_points.json';

  /// Expressions / phrases (seed source).
  static const String expressionsAsset = '$baseDir/expressions.json';

  /// Cached in-flight / completed load of the index + vocabulary so they are
  /// read once per process even though both [loadSwahiliVocabulary] (startup)
  /// and [loadSwahiliSectionShells] (CourseProvider.load) call [load].
  static Future<SwahiliCourse>? _instance;

  /// Cached vocabulary id set for runtime per-section validation.
  static Set<String> _vocabIdSet = const {};

  /// In-flight / completed per-section loads, keyed by section id. Coalesces
  /// concurrent requests for the same section and caches the result.
  static final Map<String, Future<Section>> _sectionLoads = {};

  /// In-flight / completed per-lesson loads, keyed by lesson id.
  static final Map<String, Future<Lesson>> _lessonLoads = {};

  /// Optional override supplying a [CourseDatabase] (e.g. an in-memory DB for
  /// tests). When `null`, the registered [CourseDatabase] is resolved via
  /// [getIt].
  static CourseDatabase Function()? _dbProvider;

  /// Test hook: inject a [CourseDatabase] provider. Resets the load memos so
  /// subsequent [load]/[loadSection]/[loadLessonById] calls use the injected
  /// DB from a clean slate. Call before [load].
  @visibleForTesting
  static void overrideDatabase(CourseDatabase Function() provider) {
    _dbProvider = provider;
    invalidateCaches();
  }

  /// Drop process-lifetime load caches (call after content reseed).
  static void invalidateCaches() {
    _instance = null;
    _sectionLoads.clear();
    _lessonLoads.clear();
    _vocabIdSet = const {};
  }

  static CourseDatabase get _db {
    final provider = _dbProvider;
    if (provider != null) return provider();
    if (getIt.isRegistered<CourseDatabase>()) return getIt<CourseDatabase>();
    throw StateError(
      'CourseDatabase is not registered. Call setupLocator() (or '
      'SwahiliCourse.overrideDatabase in tests) before loading the course.',
    );
  }

  /// Load the index + vocabulary (no section bodies). Subsequent calls return
  /// the cached result (the same future), so the DB is queried exactly once
  /// per session for shells + vocab.
  static Future<SwahiliCourse> load() {
    return _instance ??= _loadFresh();
  }

  static Future<SwahiliCourse> _loadFresh() async {
    final repo = CourseRepository(_db);
    final shells = await repo.sectionShells();
    final vocab = await repo.vocabulary();
    final grammar = await repo.grammarPoints();
    final expressions = await repo.expressions();
    _vocabIdSet = {for (final w in vocab) w.id};
    return SwahiliCourse(
      sectionShells: shells,
      vocabulary: vocab,
      vocabularyById: {for (final w in vocab) w.id: w},
      vocabularyByTranslation: {
        for (final w in vocab) w.translation.toLowerCase(): w,
      },
      grammarPoints: grammar,
      grammarPointsById: {for (final g in grammar) g.id: g},
      expressions: expressions,
      expressionsById: {for (final e in expressions) e.id: e},
    );
  }

  /// Load a single section's full body on demand, with in-flight coalescing
  /// and caching. Validates the section in isolation ([validateSection]) —
  /// cross-course uniqueness is enforced offline/CI by [validateSwahiliCourse]
  /// over the seed assets. Throws [ArgumentError] for an unknown id.
  ///
  /// Failed loads are **not** cached so a later retry can succeed.
  static Future<Section> loadSection(String id) {
    final existing = _sectionLoads[id];
    if (existing != null) return existing;

    final future = () async {
      try {
        final section = await CourseRepository(_db).section(id);
        validateSection(section, _vocabIdSet);
        return section;
      } catch (e) {
        _sectionLoads.remove(id);
        rethrow;
      }
    }();
    _sectionLoads[id] = future;
    return future;
  }

  /// Load a single [Lesson] by id on demand, with in-flight coalescing and
  /// caching. Throws [ArgumentError] for an unknown id.
  /// Failed loads are not cached.
  static Future<Lesson> loadLessonById(String id) {
    final existing = _lessonLoads[id];
    if (existing != null) return existing;

    final future = () async {
      try {
        return await CourseRepository(_db).lessonById(id);
      } catch (e) {
        _lessonLoads.remove(id);
        rethrow;
      }
    }();
    _lessonLoads[id] = future;
    return future;
  }
}

/// Parse a single [Section] from a per-section JSON string. Used by
/// [DatabaseSeeder] (seed path) and tests; not on the runtime read path.
/// Visible for testing.
Section parseSwahiliSection(String raw) =>
    Section.fromJson(_normalizeSection(jsonDecode(raw) as Map<String, dynamic>));

/// Pre-process a raw section map before handing it to [Section.fromJson].
///
/// Supports the flat-lesson authoring shape: a lesson may declare
/// `content.questions: [...]` instead of `content.stages: [...]`. Here we
/// synthesize a single default stage wrapping those questions so the runtime
/// model is always `List<Stage>` and no downstream consumer ever branches on
/// "flat vs grouped". A lesson must carry exactly one of `stages`/`questions`
/// — carrying both is rejected by [validateSwahiliCourse] via the loader.
Map<String, dynamic> _normalizeSection(Map<String, dynamic> section) {
  final units = section['units'] as List<dynamic>?;
  if (units == null) return section;
  section['units'] = [
    for (final u in units) _normalizeUnit(u as Map<String, dynamic>),
  ];
  return section;
}

Map<String, dynamic> _normalizeUnit(Map<String, dynamic> unit) {
  final lessons = unit['lessons'] as List<dynamic>?;
  if (lessons == null) return unit;
  unit['lessons'] = [
    for (final l in lessons) _normalizeLesson(l as Map<String, dynamic>),
  ];
  return unit;
}

Map<String, dynamic> _normalizeLesson(Map<String, dynamic> lesson) {
  final content = lesson['content'] as Map<String, dynamic>?;
  if (content == null) return lesson;
  final hasStages = content.containsKey('stages');
  final hasQuestions = content.containsKey('questions');
  if (!hasQuestions) return lesson;
  if (hasStages) {
    throw FormatException(
      'Lesson ${lesson['id']} declares both "stages" and "questions" in its '
      'content; use exactly one.',
    );
  }
  // Flat shape: wrap the questions in one default stage. The lesson's own
  // name becomes the stage name; the synthetic stage id is stable.
  final questions = content['questions'] as List<dynamic>;
  final lessonName = (lesson['name'] as String?) ?? 'Practice';
  content['stages'] = [
    {
      'id': 'stage-default',
      'name': lessonName,
      'items': questions,
    },
  ];
  content.remove('questions');
  return lesson;
}

/// Parse a list of [WordEntry]s from a JSON string. Used by [DatabaseSeeder]
/// and tests. Visible for testing.
List<WordEntry> parseSwahiliVocabulary(String raw) =>
    _parseVocabulary(raw);

List<WordEntry> _parseVocabulary(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final words = json['words'] as List<dynamic>;
  return words
      .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Parse a list of [GrammarPoint]s from a JSON string. Used by
/// [DatabaseSeeder] and tests. Visible for testing.
List<GrammarPoint> parseSwahiliGrammarPoints(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final points = json['grammarPoints'] as List<dynamic>;
  return points
      .map((e) => GrammarPoint.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Parse a list of [Expression]s from a JSON string. Used by
/// [DatabaseSeeder] and tests. Visible for testing.
List<Expression> parseSwahiliExpressions(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final expressions = (json['expressions'] as List<dynamic>?) ?? [];
  return expressions
      .map((e) => Expression.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}