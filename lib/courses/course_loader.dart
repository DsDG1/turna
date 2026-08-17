// Flutter imports:
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

// Project imports:
import 'package:turna/courses/course_validator.dart';
import 'package:turna/data/course_database.dart'
    hide
        Section,
        Unit,
        Lesson,
        LessonContent,
        Vocabulary,
        GrammarPoint;
import 'package:turna/data/course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Loads a language course from a SQLite database ([CourseDatabase]) that is
/// seeded from the bundled JSON assets under `assets/courses/turkish/` on
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
class CourseLoader {
  /// Lightweight section shells built from the DB index — id/name/description/
  /// prerequisiteSectionIds only, `units` empty until [loadSection] is called.
  final List<Section> sectionShells;

  final List<WordEntry> vocabulary;
  final Map<String, WordEntry> vocabularyById;
  final Map<String, WordEntry> vocabularyByTerm;
  final Map<String, WordEntry> vocabularyByTranslation;

  /// Grammar points loaded at startup for the grammar-review SRS queue.
  final List<GrammarPoint> grammarPoints;
  final Map<String, GrammarPoint> grammarPointsById;

  /// Expressions / phrases loaded at startup for the expression SRS queue.
  final List<Expression> expressions;
  final Map<String, Expression> expressionsById;

  const CourseLoader({
    required this.sectionShells,
    required this.vocabulary,
    required this.vocabularyById,
    required this.vocabularyByTerm,
    required this.vocabularyByTranslation,
    required this.grammarPoints,
    required this.grammarPointsById,
    required this.expressions,
    required this.expressionsById,
  });

  /// Directory holding the seed JSON assets (index + per-section files +
  /// vocab + grammar points). Used by [DatabaseSeeder]; exposed for seed-time
  /// file resolution.
  static const String baseDir = 'assets/courses/turkish';

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
  /// read once per process even though both [loadVocabulary] (startup)
  /// and [loadSectionShells] (CourseProvider.load) call [load].
  static Future<CourseLoader>? _instance;

  /// Max resolved lesson bodies kept in process memory (L2 LRU).
  @visibleForTesting
  static const int lessonBodyCacheCap = 48;

  /// In-flight / completed per-section loads, keyed by section id. Coalesces
  /// concurrent requests for the same section and caches the result.
  static final Map<String, Future<Section>> _sectionLoads = {};

  /// In-flight / completed per-lesson body loads (L2), insertion-order LRU.
  static final LinkedHashMap<String, Future<Lesson>> _lessonLoads =
      LinkedHashMap<String, Future<Lesson>>();

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

  @visibleForTesting
  static void clearDatabaseOverride() {
    _dbProvider = null;
    invalidateCaches();
  }

  /// Drop process-lifetime load caches (call after content reseed).
  static void invalidateCaches() {
    _instance = null;
    _sectionLoads.clear();
    _lessonLoads.clear();
  }

  static CourseDatabase? databaseOrNull() {
    final provider = _dbProvider;
    if (provider != null) return provider();
    if (getIt.isRegistered<CourseDatabase>()) return getIt<CourseDatabase>();
    return null;
  }

  static CourseDatabase get _db {
    final provider = _dbProvider;
    if (provider != null) return provider();
    if (getIt.isRegistered<CourseDatabase>()) return getIt<CourseDatabase>();
    throw StateError(
      'CourseDatabase is not registered. Call setupLocator() (or '
      'CourseLoader.overrideDatabase in tests) before loading the course.',
    );
  }

  /// Load the index + vocabulary (no section bodies). Subsequent calls return
  /// the cached result (the same future), so the DB is queried exactly once
  /// per session for shells + vocab.
  static Future<CourseLoader> load() {
    return _instance ??= _loadFresh();
  }

  static Future<CourseLoader> _loadFresh() async {
    final repo = CourseRepository(_db);
    // The four lookups are independent — fan them out instead of awaiting
    // four DB round-trips in series on the cold-start path.
    final results = await Future.wait<dynamic>([
      repo.sectionShells(),
      repo.vocabulary(),
      repo.grammarPoints(),
      repo.expressions(),
    ]);
    final shells = results[0] as List<Section>;
    final vocab = results[1] as List<WordEntry>;
    final grammar = results[2] as List<GrammarPoint>;
    final expressions = results[3] as List<Expression>;
    return CourseLoader(
      sectionShells: shells,
      vocabulary: vocab,
      vocabularyById: {for (final w in vocab) w.id: w},
      vocabularyByTerm: {
        for (final w in vocab) w.term.toLowerCase(): w,
      },
      vocabularyByTranslation: {
        for (final w in vocab) w.translation.toLowerCase(): w,
      },
      grammarPoints: grammar,
      grammarPointsById: {for (final g in grammar) g.id: g},
      expressions: expressions,
      expressionsById: {for (final e in expressions) e.id: e},
    );
  }

  /// Load a section's L1 tree (units + lesson metadata, empty content) on
  /// demand, with in-flight coalescing and caching. Uses [validateSectionTree]
  /// only — deep content checks stay in seed/CI via [validateCourse].
  /// Throws [ArgumentError] for an unknown id.
  ///
  /// Failed loads are **not** cached so a later retry can succeed.
  static Future<Section> loadSection(String id) {
    final existing = _sectionLoads[id];
    if (existing != null) return existing;

    final future = () async {
      try {
        final section = await CourseRepository(_db).section(id);
        validateSectionTree(section);
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
  /// an LRU cache capped at [lessonBodyCacheCap]. Throws [ArgumentError] for
  /// an unknown id. Failed loads are not cached.
  static Future<Lesson> loadLessonById(String id) {
    final existing = _lessonLoads.remove(id);
    if (existing != null) {
      // Touch: re-insert at end (most recently used).
      _lessonLoads[id] = existing;
      return existing;
    }

    final future = () async {
      try {
        return await CourseRepository(_db).lessonById(id);
      } catch (e) {
        _lessonLoads.remove(id);
        rethrow;
      }
    }();
    _lessonLoads[id] = future;
    while (_lessonLoads.length > lessonBodyCacheCap) {
      _lessonLoads.remove(_lessonLoads.keys.first);
    }
    return future;
  }

  /// Load lesson bodies whose content contains any of [needles] (substring).
  ///
  /// Results are also inserted into the L2 LRU so a subsequent
  /// [loadLessonById] for the same id is free. Used by Anki review to
  /// resolve a small batch of word ids without walking the whole deck.
  static Future<List<Lesson>> loadLessonsContainingAny(
    Iterable<String> needles,
  ) async {
    final lessons = await CourseRepository(_db).lessonsContainingAny(needles);
    for (final lesson in lessons) {
      // Touch / insert into L2 LRU as a completed future.
      _lessonLoads.remove(lesson.id);
      _lessonLoads[lesson.id] = Future.value(lesson);
    }
    while (_lessonLoads.length > lessonBodyCacheCap) {
      _lessonLoads.remove(_lessonLoads.keys.first);
    }
    return lessons;
  }

  /// Owning section id for a unit, or `null` if unknown. Used by
  /// [CourseProvider.selectUnit] to load only the needed L1 tree.
  static Future<String?> sectionIdForUnit(String unitId) =>
      CourseRepository(_db).sectionIdForUnit(unitId);

  /// Owning section id for a lesson, or `null` if unknown.
  static Future<String?> sectionIdForLesson(String lessonId) =>
      CourseRepository(_db).sectionIdForLesson(lessonId);
}

/// Parse a single [Section] from a per-section JSON string. Used by
/// [DatabaseSeeder] (seed path) and tests; not on the runtime read path.
/// Visible for testing.
Section parseSection(String raw) =>
    Section.fromJson(_normalizeSection(jsonDecode(raw) as Map<String, dynamic>));

/// Pre-process a raw section map before handing it to [Section.fromJson].
///
/// Supports the flat-lesson authoring shape: a lesson may declare
/// `content.questions: [...]` instead of `content.stages: [...]`. Here we
/// synthesize a single default stage wrapping those questions so the runtime
/// model is always `List<Stage>` and no downstream consumer ever branches on
/// "flat vs grouped". A lesson must carry exactly one of `stages`/`questions`
/// — carrying both is rejected by [validateCourse] via the loader.
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
List<WordEntry> parseVocabulary(String raw) => _parseVocabulary(raw);

List<WordEntry> _parseVocabulary(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final words = json['words'] as List<dynamic>;
  return words
      .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Parse a list of [GrammarPoint]s from a JSON string. Used by
/// [DatabaseSeeder] and tests. Visible for testing.
List<GrammarPoint> parseGrammarPoints(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final points = json['grammarPoints'] as List<dynamic>;
  return points
      .map((e) => GrammarPoint.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Parse a list of [Expression]s from a JSON string. Used by
/// [DatabaseSeeder] and tests. Visible for testing.
List<Expression> parseExpressions(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final expressions = (json['expressions'] as List<dynamic>?) ?? [];
  return expressions
      .map((e) => Expression.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}