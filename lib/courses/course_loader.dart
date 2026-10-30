// Flutter imports:
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart' show visibleForTesting;

// Project imports:
import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_content_source.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/courses/section_level_overlay.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent, Vocabulary, GrammarPoint;
import 'package:turna/data/course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';

export 'course_json_parser.dart';

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
/// `units`; they carry enough (id/name/description/level/prerequisiteSectionIds)
/// for the section switcher and selection logic. [loadSection] rebuilds a
/// fully-populated [Section] from the DB. An empty stored level is filled
/// from the bundled `index.json` shell, so an already-seeded install shows
/// A1/A2 without a content-version bump. A non-empty stored level is kept.
class CourseLoader {
  /// Lightweight section shells built from the DB index — id/name/description/
  /// level/prerequisiteSectionIds, `units` empty until [loadSection] is called.
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

  /// Directory holding the seed JSON assets for [languageCode].
  static String baseDirFor(String languageCode) {
    final dir = LanguageRegistry.instance.assetDir(languageCode);
    return 'assets/courses/$dir';
  }

  static String indexAssetFor(String languageCode) =>
      '${baseDirFor(languageCode)}/index.json';

  static String vocabAssetFor(String languageCode) =>
      '${baseDirFor(languageCode)}/vocab.json';

  static String grammarPointsAssetFor(String languageCode) =>
      '${baseDirFor(languageCode)}/grammar_points.json';

  static String expressionsAssetFor(String languageCode) =>
      '${baseDirFor(languageCode)}/expressions.json';

  /// Turkish asset dir — tests that `File()`-read the packed tree.
  static String get baseDir => baseDirFor(LanguageCodes.turkish);

  /// Cached per-language loads of index + vocabulary.
  static final Map<String, Future<CourseLoader>> _instances = {};

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
    _instances.clear();
    _sectionLoads.clear();
    _lessonLoads.clear();
    _indexLevelLoads.clear();
  }

  /// CEFR tags from the bundled index, cached per language. Missing indexes
  /// (imported packs, Anki) resolve to an empty map.
  static final Map<String, Future<Map<String, String>>> _indexLevelLoads = {};

  static Future<Map<String, String>> indexLevelsFor(String languageCode) {
    final code = LanguageCodes.canonicalize(languageCode);
    return _indexLevelLoads[code] ??= _readIndexLevels(code);
  }

  static Future<Map<String, String>> _readIndexLevels(
      String languageCode) async {
    try {
      final raw = await CourseContentSource.instance
          .loadCourseJson(languageCode, 'index.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return sectionLevelsFromIndex(decoded);
      }
      if (decoded is Map) {
        return sectionLevelsFromIndex(Map<String, dynamic>.from(decoded));
      }
    } on Object {
      // Imported packs and Anki have no bundled index. Leave the DB level.
    }
    return const {};
  }

  static Future<List<Section>> _overlayLevels(
    List<Section> shells,
    String languageCode,
  ) async {
    final levels = await indexLevelsFor(languageCode);
    if (levels.isEmpty) return shells;
    return [for (final shell in shells) overlaySectionLevel(shell, levels)];
  }

  static Future<String?> _languageCodeOfSection(String id) async {
    final rows = await _db.customSelect(
      'SELECT language_code FROM sections WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
      readsFrom: {_db.sections},
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<String>('language_code');
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

  /// Every section shell in the database (all builtin languages + Anki).
  static Future<List<Section>> loadAllSectionShells() async {
    final shells = await CourseRepository(_db).sectionShells();
    if (shells.isEmpty) return shells;
    final codes = await sectionLanguageCodes();
    final grouped = <String, List<int>>{};
    for (var i = 0; i < shells.length; i++) {
      final code = codes[shells[i].id];
      if (code == null) continue;
      grouped.putIfAbsent(code, () => []).add(i);
    }
    final out = List<Section>.of(shells);
    for (final entry in grouped.entries) {
      final levels = await indexLevelsFor(entry.key);
      if (levels.isEmpty) continue;
      for (final index in entry.value) {
        out[index] = overlaySectionLevel(out[index], levels);
      }
    }
    return out;
  }

  /// section id → language code for builtin rows (Anki rows still carry a
  /// language_code default but ownership is by Anki source, not this map).
  static Future<Map<String, String>> sectionLanguageCodes() async {
    final rows = await _db.customSelect(
      'SELECT id, language_code FROM sections',
      readsFrom: {_db.sections},
    ).get();
    return {
      for (final row in rows)
        row.read<String>('id'):
            LanguageCodes.canonicalize(row.read<String>('language_code')),
    };
  }

  /// Load the index + vocabulary (no section bodies) for [languageCode].
  /// Subsequent calls for the same language return the cached result.
  static Future<CourseLoader> load([String? languageCode]) {
    final code = LanguageCodes.canonicalize(
      languageCode ?? LanguageRegistry.instance.defaultCode,
    );
    return _instances[code] ??= _loadFresh(code);
  }

  static Future<CourseLoader> _loadFresh(String languageCode) async {
    final repo = CourseRepository(_db);
    // The four lookups are independent — fan them out instead of awaiting
    // four DB round-trips in series on the cold-start path.
    final results = await Future.wait<dynamic>([
      repo.sectionShells(languageCode: languageCode),
      repo.vocabulary(languageCode: languageCode),
      repo.grammarPoints(languageCode: languageCode),
      repo.expressions(languageCode: languageCode),
    ]);
    final shells = await _overlayLevels(
      results[0] as List<Section>,
      languageCode,
    );
    final vocab = results[1] as List<WordEntry>;
    final grammar = results[2] as List<GrammarPoint>;
    final expressions = results[3] as List<Expression>;
    return CourseLoader(
      sectionShells: shells,
      vocabulary: vocab,
      vocabularyById: {for (final w in vocab) w.id: w},
      vocabularyByTerm: {
        for (final w in vocab)
          LanguageCodes.lookupFoldKey(w.term, languageCode): w,
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
  /// [languageCode] scopes the DB lookup to one language (ids are unique per
  /// language only); `null` loads any language's row. The cache key stays the
  /// bare id regardless.
  ///
  /// Failed loads are **not** cached so a later retry can succeed.
  static Future<Section> loadSection(String id, {String? languageCode}) {
    final existing = _sectionLoads[id];
    if (existing != null) return existing;

    final future = () async {
      try {
        final section =
            await CourseRepository(_db).section(id, languageCode: languageCode);
        final code = languageCode ?? await _languageCodeOfSection(id);
        final overlaid = code == null
            ? section
            : overlaySectionLevel(section, await indexLevelsFor(code));
        validateSectionTree(overlaid);
        return overlaid;
      } catch (e) {
        unawaited(_sectionLoads.remove(id));
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
        unawaited(_lessonLoads.remove(id));
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
      unawaited(_lessonLoads.remove(lesson.id));
      _lessonLoads[lesson.id] = Future.value(lesson);
    }
    while (_lessonLoads.length > lessonBodyCacheCap) {
      unawaited(_lessonLoads.remove(_lessonLoads.keys.first));
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
